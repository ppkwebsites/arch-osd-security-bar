import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Wayland

ShellRoot {
    property string netSpeed: "0 KB/s ↓↑ 0 KB/s"
    property real lastRxBytes: 0
    property real lastTxBytes: 0
    property date lastNetCheck: new Date()
    property string localIP: "N/A"
    property string localDns: "Scanning..."
    property string localDevices: "Scanning..."

    property string accumulatedDevices: ""

    property bool sshOpen: false
    property bool sshLimited: true
    property bool fail2banInstalled: false
    property bool sshUsesKeys: false

    // ─── Network Speed ───────────────────────────────────────────────────────────

    Process {
        id: netSpeedProc
        command: ["sh", "-c", "active=$(nmcli -t -f DEVICE device | grep -v '^lo$' | head -1); if [ -z \"$active\" ]; then echo '0 0'; exit 0; fi; ip -s link show \"$active\" 2>/dev/null | awk '/RX:/ {getline; rx=$1} /TX:/ {getline; tx=$1} END {if (rx && tx) print rx \" \" tx; else print \"0 0\"}'"]
        stdout: SplitParser {
            onRead: (line) => {
                if (!line) return
                    let trimmed = line.trim()
                    if (trimmed === "" || trimmed === "0 0") {
                        netSpeed = "0 KB/s ↓↑ 0 KB/s"
                        return
                    }
                    let parts = trimmed.split(/\s+/)
                    if (parts.length !== 2) return
                        let rx = parseFloat(parts[0]) || 0
                        let tx = parseFloat(parts[1]) || 0
                        let now = new Date()
                        let deltaMs = now.getTime() - lastNetCheck.getTime()
                        let deltaSec = deltaMs / 1000
                        if (deltaSec < 0.8 || deltaSec > 15 || isNaN(deltaSec)) {
                            lastRxBytes = rx
                            lastTxBytes = tx
                            lastNetCheck = now
                            netSpeed = "0 KB/s ↓↑ 0 KB/s"
                            return
                        }
                        let downBps = (rx - lastRxBytes) / deltaSec
                        let upBps = (tx - lastTxBytes) / deltaSec
                        lastRxBytes = rx
                        lastTxBytes = tx
                        lastNetCheck = now
                        netSpeed = formatSpeed(downBps) + " ↓↑ " + formatSpeed(upBps)
            }
        }
    }

    function formatSpeed(bps) {
        if (bps < 1024) return "0 KB/s"
            let kbps = bps / 1024
            if (kbps < 1024) return Math.round(kbps) + " KB/s"
                let mbps = kbps / 1024
                if (mbps < 1024) return mbps.toFixed(1) + " MB/s"
                    return (mbps / 1024).toFixed(1) + " GB/s"
    }

    // ─── Local IP ────────────────────────────────────────────────────────────────

    Process {
        id: localIPProc
        command: ["sh", "-c", "active=$(nmcli -t -f DEVICE device | grep -v '^lo$' | head -1); if [ -z \"$active\" ]; then echo 'N/A'; exit 0; fi; nmcli -t -f IP4.ADDRESS device show \"$active\" | cut -d: -f2 | cut -d/ -f1"]
        stdout: SplitParser { onRead: (line) => { if (line) localIP = line.trim() || "N/A" } }
    }

    // ─── Local DNS ───────────────────────────────────────────────────────────────

    Process {
        id: localDnsProc
        command: ["sh", "-c", "active=$(nmcli -t -f DEVICE device | grep -v '^lo$' | head -1); [ -z \"$active\" ] && echo 'N/A' || nmcli -t -f IP4.DNS device show \"$active\" | cut -d: -f2 | paste -sd ', ' || echo 'N/A'"]
        stdout: SplitParser { onRead: (line) => { if (line) localDns = line.trim() || "N/A" } }
    }

    // ─── SSH Limit Check ─────────────────────────────────────────────────────────

    Process {
        id: sshLimitProc
        command: ["sh", "-c", "grep -E '^MaxAuthTries|^MaxStartups' /etc/ssh/sshd_config | wc -l"]
        stdout: SplitParser {
            onRead: (line) => {
                let count = parseInt(line.trim()) || 0
                sshLimited = (count >= 2)
            }
        }
    }

    // ─── SSH Key Auth Check ──────────────────────────────────────────────────────

    Process {
        id: sshAuthProc
        command: ["sh", "-c", "ssh -G localhost | grep -iE 'passwordauthentication|pubkeyauthentication'"]
        property string authOutput: ""

        stdout: SplitParser {
            onRead: (line) => {
                if (line) authOutput += line.trim() + "\n"
            }
        }

        onExited: {
            let lines = authOutput.toLowerCase().split("\n")
            let password = lines.find(l => l.includes("passwordauthentication")) || ""
            let pubkey = lines.find(l => l.includes("pubkeyauthentication")) || ""
            sshUsesKeys = pubkey.includes("yes") && !password.includes("yes")
            authOutput = ""
        }
    }

    // ─── Fail2ban Check ──────────────────────────────────────────────────────────

    Process {
        id: fail2banCheckProc
        command: ["sh", "-c", "pacman -Q fail2ban >/dev/null 2>&1 && echo 'installed' || echo 'not_installed'"]
        stdout: SplitParser {
            onRead: (line) => {
                fail2banInstalled = (line && line.trim() === "installed")
            }
        }
    }

    // ─── Wake + Scan Devices ─────────────────────────────────────────────────────

    Process {
        id: devicesScanProc
        running: false

        command: ["sh", "-c", "
        active=$(nmcli -t -f DEVICE device | grep -v '^lo$' | head -1)
        [ -z \"$active\" ] && echo 'None found' && exit 0

        myip=$(nmcli -t -f IP4.ADDRESS device show \"$active\" | cut -d: -f2 | cut -d/ -f1)
        [ -z \"$myip\" ] && echo 'None found' && exit 0

        base=${myip%.*}.

        ping -c 2 -W 1 -b ${base}255 >/dev/null 2>&1 || true
        sleep 0.2

        for i in {1..254}; do
            [ \"$i\" = \"${myip##*.}\" ] && continue
            ping -c 2 -W 1 \"${base}$i\" >/dev/null 2>&1 &
            done
            wait

            # Read immediately
            ip -4 neigh show | \
            grep -E 'REACHABLE|STALE|DELAY|PERMANENT' | \
            awk '{
            if ($5 ~ /:/) print $1 \" (\" $5 \")\";
        else if ($3 ~ /:/) print $1 \" (\" $3 \")\";
        else print $1
    }' | \
    sort -V | uniq || echo 'None found'
    "]

    stdout: SplitParser {
        onRead: (line) => {
            let trimmed = line.trim()
            if (trimmed && trimmed !== "None found") {
                if (accumulatedDevices !== "") accumulatedDevices += "\n"
                    accumulatedDevices += trimmed
            }
        }
    }

    onExited: {
        let result = accumulatedDevices.trim()
        localDevices = result || "None found"
        accumulatedDevices = ""
    }
    }

    // ─── Bandwhich Check & Launcher ─────────────────────────────────────────────

    property bool bandwhichInstalled: false

    Process {
        id: checkBandwhich
        command: ["sh", "-c", "type -P bandwhich >/dev/null 2>&1"]
        running: false

        onExited: (exitCode, exitStatus) => {
            bandwhichInstalled = (exitCode === 0)
        }
    }

    Process {
        id: bandwhichLauncher
        running: false
        command: ["kitty", "-e", "sudo", "bandwhich"]
    }

    // ─── Copy helper ────────────────────────────────────────────────────────────

    Process {
        id: copyProcess
    }

    // ─── Startup ────────────────────────────────────────────────────────────────

    Component.onCompleted: {
        netSpeedProc.running = true
        localIPProc.running = true
        localDnsProc.running = true
        sshAuthProc.running = true
        fail2banCheckProc.running = true
        checkBandwhich.running = true
        devicesScanProc.running = true
    }

    // ─── UI ──────────────────────────────────────────────────────────────────────

    PanelWindow {
        id: window
        anchors { top: true; bottom: true; right: true }
        implicitWidth: 400
        visible: true
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0

        onVisibleChanged: {
            if (visible) {
                devicesScanProc.running = false
                devicesScanProc.running = true
            }
        }

        Rectangle {
            id: body
            x: window.implicitWidth
            y: 0
            width: 340
            height: parent.height
            color: "#131419"
            opacity: 0.92
            border.color: "#555839"
            border.width: 2
            radius: 16

            Behavior on x { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

            Flickable {
                anchors.fill: parent
                contentHeight: contentColumn.implicitHeight + 60
                clip: true

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AlwaysOn
                    size: 0.08
                    width: 10
                    background: Rectangle { color: "#2a2a2a"; opacity: 0.4 }
                    contentItem: Rectangle {
                        radius: width / 2
                        color: "#808080"
                        opacity: parent.pressed ? 0.9 : 0.6
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }

                Column {
                    id: contentColumn
                    anchors {
                        top: parent.top
                        topMargin: 20
                        left: parent.left
                        right: parent.right
                        leftMargin: 30
                        rightMargin: 30
                    }
                    spacing: 20

                    // Header
                    Rectangle {
                        width: parent.width
                        implicitHeight: 60
                        radius: 10
                        color: Qt.rgba(0.22, 0.22, 0.22, 0.85)
                        border.color: "#555839"
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "Network Info"
                            color: "#dde5a2"
                            font.pixelSize: 32
                            font.family: "Monospace"
                            font.weight: Font.Bold
                        }
                    }

                    // Speed
                    Rectangle {
                        width: parent.width
                        implicitHeight: 70
                        radius: 8
                        color: Qt.rgba(0.33, 0.34, 0.22, 0.88)
                        Text {
                            anchors.centerIn: parent
                            text: netSpeed
                            color: "#e0e0c0"
                            font.pixelSize: 22
                            font.family: "Monospace"
                        }
                    }

                    // Local IP + DNS
                    Rectangle {
                        width: parent.width
                        implicitHeight: ipDnsCol.implicitHeight + 32
                        radius: 8
                        color: Qt.rgba(0.33, 0.34, 0.22, 0.88)
                        Column {
                            id: ipDnsCol
                            anchors.centerIn: parent
                            spacing: 10
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Local IP: " + localIP
                                color: "#e0e0c0"
                                font.pixelSize: 17
                                font.family: "Monospace"
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Local DNS: " + localDns
                                color: localDns === "N/A" || localDns === "None" ? "#c0d0a0" : "#e0c070"
                                font.pixelSize: 16
                                font.family: "Monospace"
                            }
                        }
                    }

                    // ─── Local Connected Devices ────────────────────────────────────────────────

                    Rectangle {
                        width: parent.width
                        implicitHeight: 280
                        radius: 8
                        color: Qt.rgba(0.22, 0.22, 0.22, 0.85)

                        Column {
                            anchors {
                                top: parent.top
                                topMargin: 20
                                left: parent.left
                                leftMargin: 20
                                right: parent.right
                                rightMargin: 20
                            }
                            spacing: 12

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: "Local Connected Devices"
                                color: "#d0d0d0"
                                font.pixelSize: 18
                                font.family: "Monospace"
                                font.weight: Font.Bold
                            }

                            Flickable {
                                width: parent.width
                                height: 165
                                clip: true
                                contentHeight: devicesText.implicitHeight

                                ScrollBar.vertical: ScrollBar {
                                    policy: ScrollBar.AsNeeded
                                    width: 10
                                    contentItem: Rectangle {
                                        radius: width / 2
                                        color: "#808080"
                                        opacity: parent.active ? 0.8 : 0.4
                                    }
                                }

                                Text {
                                    id: devicesText
                                    width: parent.width
                                    text: localDevices
                                    color: localDevices.includes("None") || localDevices.includes("Error") ? "#c0d0a0" : "#e0e070"
                                    font.pixelSize: 14
                                    font.family: "Monospace"
                                    wrapMode: Text.Wrap
                                }
                            }

                            Button {
                                width: 160
                                height: 36
                                text: "Refresh Devices"
                                anchors.horizontalCenter: parent.horizontalCenter

                                font.pixelSize: 15
                                padding: 6

                                background: Rectangle {
                                    radius: 8
                                    color: "#646947"
                                    border.color: "#8a9a5e"
                                    border.width: 1
                                }

                                contentItem: Text {
                                    text: parent.text
                                    color: "#e8f0d0"
                                    font.pixelSize: 15
                                    font.family: "Monospace"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: {
                                    devicesScanProc.running = false
                                    devicesScanProc.running = true
                                }
                            }
                        }
                    }

                    // ─── Network Ports Section ──────────────────────────────────────────────────

                    Rectangle {
                        width: parent.width
                        implicitHeight: networkPortsCol.implicitHeight + 40
                        radius: 8
                        color: Qt.rgba(0.22, 0.22, 0.22, 0.85)

                        Column {
                            id: networkPortsCol
                            width: parent.width - 40
                            anchors.centerIn: parent
                            spacing: 20

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: "Network Ports"
                                color: "#dde5a2"
                                font.pixelSize: 20
                                font.family: "Monospace"
                                font.weight: Font.Bold
                            }

                            // Open ports (ufw status)
                            Column {
                                width: parent.width
                                spacing: 8

                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "Open ports"
                                    color: "#e0e0c0"
                                    font.pixelSize: 16
                                    font.family: "Monospace"
                                }

                                TextEdit {
                                    width: parent.width
                                    text: "sudo ufw status"
                                    color: "#c0d0a0"
                                    font.pixelSize: 14
                                    font.family: "Monospace"
                                    readOnly: true
                                    selectByMouse: true
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Button {
                                    text: "Copy"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    font.pixelSize: 13
                                    padding: 8

                                    background: Rectangle {
                                        radius: 6
                                        color: "#646947"
                                        border.color: "#8a9a5e"
                                        border.width: 1
                                    }

                                    contentItem: Text {
                                        text: parent.text
                                        color: "#e8f0d0"
                                        font: parent.font
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    onClicked: {
                                        copyProcess.command = ["wl-copy", "sudo ufw status"]
                                        copyProcess.running = false
                                        copyProcess.running = true
                                    }
                                }
                            }

                            // Listening ports (ufw show listening)
                            Column {
                                width: parent.width
                                spacing: 8

                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "Listening ports"
                                    color: "#e0e0c0"
                                    font.pixelSize: 16
                                    font.family: "Monospace"
                                }

                                TextEdit {
                                    width: parent.width
                                    text: "sudo ufw show listening"
                                    color: "#c0d0a0"
                                    font.pixelSize: 14
                                    font.family: "Monospace"
                                    readOnly: true
                                    selectByMouse: true
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Button {
                                    text: "Copy"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    font.pixelSize: 13
                                    padding: 8

                                    background: Rectangle {
                                        radius: 6
                                        color: "#646947"
                                        border.color: "#8a9a5e"
                                        border.width: 1
                                    }

                                    contentItem: Text {
                                        text: parent.text
                                        color: "#e8f0d0"
                                        font: parent.font
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    onClicked: {
                                        copyProcess.command = ["wl-copy", "sudo ufw show listening"]
                                        copyProcess.running = false
                                        copyProcess.running = true
                                    }
                                }
                            }

                            // ─── Targeted / Vulnerable Ports ────────────────────────────────────────

                            Column {
                                width: parent.width
                                spacing: 8

                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "Targeted / Vulnerable Ports"
                                    color: "#ff7777"
                                    font.pixelSize: 16
                                    font.family: "Monospace"
                                    font.bold: true
                                }

                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "21 (FTP)\n23 (Telnet)\n445 (SMB)\n3389 (RDP)\n5900 (VNC)"
                                    color: "#ff7777"
                                    font.pixelSize: 14
                                    font.family: "Monospace"
                                    wrapMode: Text.Wrap
                                }

                                TextEdit {
                                    width: parent.width
                                    text: "sudo ufw deny 23/tcp\nsudo ufw reload"
                                    color: "#ffcccc"
                                    font.pixelSize: 13
                                    font.family: "Monospace"
                                    readOnly: true
                                    selectByMouse: true
                                    wrapMode: TextEdit.Wrap
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Button {
                                    text: "Copy close commands"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    font.pixelSize: 13
                                    padding: 8

                                    background: Rectangle {
                                        radius: 6
                                        color: "#646947"
                                        border.color: "#8a9a5e"
                                        border.width: 1
                                    }

                                    contentItem: Text {
                                        text: parent.text
                                        color: "#e8f0d0"
                                        font: parent.font
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    onClicked: {
                                        let cmd = "sudo ufw deny 21/tcp\nsudo ufw deny 23/tcp\nsudo ufw deny 445/tcp\nsudo ufw deny 3389/tcp\nsudo ufw deny 5900/tcp\nsudo ufw reload"
                                        copyProcess.command = ["wl-copy", cmd]
                                        copyProcess.running = false
                                        copyProcess.running = true
                                    }
                                }
                            }
                        }
                    }

                    // ─── SSH Status & Instructions ──────────────────────────────────────────────

                    Column {
                        width: parent.width
                        spacing: 16
                        visible: sshOpen

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: sshUsesKeys ?
                            "SSH: Using key authentication (good)" :
                            "⚠ SSH allows password authentication – switch to key-only!"
                            color: sshUsesKeys ? "#c0d0a0" : "#ffaaaa"
                            font.pixelSize: 15
                            font.family: "Monospace"
                            font.bold: !sshUsesKeys
                            wrapMode: Text.Wrap
                        }

                        Column {
                            width: parent.width
                            spacing: 8
                            visible: sshOpen && !sshUsesKeys

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: "Recommended steps"
                                color: "#ffcc88"
                                font.pixelSize: 14
                                font.family: "Monospace"
                            }

                            TextEdit {
                                width: parent.width
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "# 1. Generate key pair (on your client)\nssh-keygen -t ed25519 -C \"your_email@example.com\"\n\n# 2. Copy public key to this machine\nssh-copy-id $USER@localhost\n   (or manually add to ~/.ssh/authorized_keys)\n\n# 3. Disable password auth in /etc/ssh/sshd_config\nsudo nano /etc/ssh/sshd_config\n   PasswordAuthentication no\n   PubkeyAuthentication yes\n   ChallengeResponseAuthentication no\n\n# 4. Restart SSH\nsudo systemctl restart sshd\n\nTest from another terminal before closing this session!"
                                color: "#ffeeee"
                                font.pixelSize: 14
                                font.family: "Monospace"
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.Wrap
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Button {
                                text: "Copy SSH key-only instructions"
                                anchors.horizontalCenter: parent.horizontalCenter
                                font.pixelSize: 13
                                padding: 8

                                background: Rectangle {
                                    radius: 6
                                    color: "#646947"
                                    border.color: "#8a9a5e"
                                    border.width: 1
                                }

                                contentItem: Text {
                                    text: parent.text
                                    color: "#e8f0d0"
                                    font: parent.font
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: {
                                    let cmd = "# 1. Generate key\nssh-keygen -t ed25519 -C \"your_email@example.com\"\n\n# 2. Copy key\nssh-copy-id $USER@localhost\n\n# 3. Disable password\nsudo nano /etc/ssh/sshd_config\n   PasswordAuthentication no\n   PubkeyAuthentication yes\n\n# 4. Restart\nsudo systemctl restart sshd"
                                    copyProcess.command = ["wl-copy", cmd]
                                    copyProcess.running = false
                                    copyProcess.running = true
                                }
                            }
                        }
                    }

                    // Active Internet Programs
                    Rectangle {
                        width: parent.width
                        implicitHeight: 140
                        radius: 8
                        color: Qt.rgba(0.33, 0.34, 0.22, 0.88)
                        border.color: "#555839"
                        border.width: 1

                        Column {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 12

                            Text {
                                width: parent.width
                                text: "ACTIVE INTERNET PROGRAMS"
                                color: "#e0e0c0"
                                font.pixelSize: 17
                                font.family: "Monospace"
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Item {
                                width: parent.width
                                height: 60

                                Button {
                                    width: 150
                                    height: 38
                                    text: "Run bandwhich"

                                    anchors.centerIn: parent

                                    padding: 6

                                    background: Rectangle {
                                        radius: 8
                                        color: "#646947"
                                        border.color: "#8a9a5e"
                                        border.width: 1
                                    }

                                    contentItem: Text {
                                        text: parent.text
                                        color: "#e8f0d0"
                                        font.pixelSize: 15
                                        font.family: "Monospace"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    onClicked: {
                                        bandwhichLauncher.running = false
                                        bandwhichLauncher.running = true
                                    }
                                }
                            }
                        }
                    }

                    Item { height: 32; width: 1 }

                    // Close Button
                    Button {
                        text: "Close"
                        width: 160
                        height: 44
                        anchors.horizontalCenter: parent.horizontalCenter

                        font.pixelSize: 16
                        font.family: "Monospace"

                        background: Rectangle {
                            radius: 10
                            color: "#3a2a2a"
                            border.color: "#6b3a3a"
                            border.width: 1

                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#e0c0c0"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            window.visible = false
                        }
                    }

                    Item { height: 16; width: 1 }
                }
            }
        }

        Timer {
            id: slideInTimer
            interval: 50
            repeat: false
            running: true
            onTriggered: {
                body.x = 50
            }
        }
    }

    Component {
        id: installTextComponent

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: "#ff9999"
            font.pixelSize: 15
            font.family: "Monospace"
            text: "bandwhich not found\nInstall with:\n\nsudo pacman -S bandwhich"
        }
    }
}
