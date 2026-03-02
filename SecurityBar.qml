import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Wayland

ShellRoot {

    // ─── Network Properties ───────────────────────────
    property string netSpeed: "0 KB/s ↓↑ 0 KB/s"
    property real lastRxBytes: 0
    property real lastTxBytes: 0
    property date lastNetCheck: new Date()

    property string localIP: "N/A"

    // ─── Firewall Properties ──────────────────────────
    property string firewallStatus: "Checking..."
    property string firewallMessage: ""
    property string firewallAdvice: ""
    property bool   firewallActive: false

    // ─── Malware Properties ───────────────────────────
    property bool   clamInstalled: false
    property bool   daemonActive: false
    property bool   freshclamActive: false
    property bool   clamonaccActive: false
    property string malwareStatus: "Checking..."
    property string malwareMessage: ""
    property string malwareAdvice: ""

    // ─── Arch Updates Properties ──────────────────────
    property string lastUpdateText: "Last updated: checking..."
    property string pendingUpdatesText: "Checking..."
    property bool   updatesOutdated: false
    property bool   updatesChecking: true

    // ─── Network Speed Process ────────────────────────
    Process {
        id: netSpeedProc
        command: ["sh", "-c", "active=$(nmcli -t -f DEVICE device | grep -v '^lo$' | head -1); if [ -z \"$active\" ]; then echo '0 0'; exit 0; fi; ip -s link show \"$active\" 2>/dev/null | awk '/RX:/ {getline; rx=$1} /TX:/ {getline; tx=$1} END {if (rx && tx) print rx \" \" tx; else print \"0 0\"}'"]

        stdout: SplitParser {
            onRead: function(line) {
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
                        let upBps   = (tx - lastTxBytes) / deltaSec

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

    // ─── Other Network Processes ──────────────────────
    Process {
        id: localIPProc
        command: ["sh", "-c", "active=$(nmcli -t -f DEVICE device | grep -v '^lo$' | head -1); if [ -z \"$active\" ]; then echo 'N/A'; exit 0; fi; nmcli -t -f IP4.ADDRESS device show \"$active\" | cut -d: -f2 | cut -d/ -f1"]
        stdout: SplitParser {
            onRead: function(line) {
                if (line) localIP = line.trim() || "N/A"
            }
        }
    }

    // ─── Simplified Firewall Process ──────────────────
    Process {
        id: firewallProc
        command: ["sh", "-c", "if command -v ufw >/dev/null 2>&1; then echo 'installed'; else echo 'not_installed'; fi"]

        stdout: SplitParser {
            onRead: function(line) {
                if (!line) return
                    let trimmed = line.trim()
                    if (trimmed === "installed") {
                        firewallStatus = "UFW Installed"
                        firewallActive = true
                        firewallMessage = "Check Status:"
                        firewallAdvice = "sudo ufw status verbose"
                    } else {
                        firewallStatus = "Not installed"
                        firewallActive = false
                        firewallMessage = "Install UFW:"
                        firewallAdvice  = "sudo pacman -S ufw && sudo ufw enable && sudo systemctl enable ufw"
                    }
            }
        }
    }

    // ─── Malware Process (ClamAV) ─────────────────────
    Process {
        id: malwareProc
        command: ["sh", "-c", "if ! pacman -Q clamav >/dev/null 2>&1; then echo 'not_installed'; exit 0; fi; daemon=$(systemctl is-active clamav-daemon); fresh=$(systemctl is-active clamav-freshclam); clamon=$(systemctl is-active clamav-clamonacc); echo \"installed|$daemon|$fresh|$clamon\""]

        stdout: SplitParser {
            onRead: function(line) {
                if (!line) return
                    let trimmed = line.trim()
                    if (trimmed === "not_installed") {
                        clamInstalled = false
                        malwareStatus = "Not installed"
                        malwareMessage = "Install ClamAV:"
                        malwareAdvice = "sudo pacman -S clamav && sudo freshclam && sudo systemctl enable --now clamav-freshclam.service clamav-daemon.service clamav-clamonacc.service"
                        return
                    }

                    let parts = trimmed.split('|')
                    if (parts.length < 4) return

                        clamInstalled = true
                        daemonActive = (parts[1] === "active")
                        freshclamActive = (parts[2] === "active")
                        clamonaccActive = (parts[3] === "active")

                        let adviceParts = []
                        if (!daemonActive) adviceParts.push("sudo systemctl start clamav-daemon.service && sudo systemctl enable clamav-daemon.service")
                            if (!freshclamActive) adviceParts.push("sudo systemctl start clamav-freshclam.service && sudo systemctl enable clamav-freshclam.service")
                                if (!clamonaccActive) adviceParts.push("sudo systemctl start clamav-clamonacc.service && sudo systemctl enable clamav-clamonacc.service")

                                    if (adviceParts.length > 0) {
                                        malwareMessage = "Fix inactive services:"
                                        malwareAdvice = adviceParts.join("\n")
                                    } else {
                                        malwareMessage = ""
                                        malwareAdvice = ""
                                    }
            }
        }
    }

    // ─── Simple Arch Updates ──────────────────────────
    Process {
        id: updatesProc
        command: ["sh", "-c", "last=$(grep -E 'full system upgrade|starting full system upgrade' /var/log/pacman.log | tail -n 1 | awk '{print $1}' | tr -d '[]' | cut -d'+' -f1 | cut -d'T' -f1 2>/dev/null || echo 'never'); count=$(checkupdates 2>/dev/null | wc -l || echo 0); echo \"$last|$count\""]

        stdout: SplitParser {
            onRead: function(line) {
                updatesChecking = false

                if (!line) {
                    lastUpdateText = "Last updated: error"
                    pendingUpdatesText = "Error checking updates"
                    updatesOutdated = true
                    return
                }

                let trimmed = line.trim()
                if (trimmed === "") {
                    lastUpdateText = "Last updated: never"
                    pendingUpdatesText = "0 packages pending"
                    updatesOutdated = true
                    return
                }

                let parts = trimmed.split("|")
                if (parts.length < 2) {
                    lastUpdateText = "Last updated: error"
                    pendingUpdatesText = "Parse error"
                    updatesOutdated = true
                    return
                }

                let datePart = parts[0].trim() || "never"
                let countPart = parts[1].trim() || "0"

                lastUpdateText = "Last updated: " + datePart

                let count = parseInt(countPart, 10) || 0
                pendingUpdatesText = count + " package" + (count === 1 ? "" : "s") + " pending"

                if (datePart !== "never") {
                    let lastDate = Date.parse(datePart)
                    if (!isNaN(lastDate)) {
                        let ageDays = (new Date() - lastDate) / (1000 * 60 * 60 * 24)
                        updatesOutdated = ageDays > 2
                    } else {
                        updatesOutdated = true
                    }
                } else {
                    updatesOutdated = true
                }
            }
        }
    }

    // ─── Copy helper process ──────────────────────────
    Process {
        id: copyProcess
    }

    // ─── Launcher for NetworkSecurityBar ──────────────
    Process {
        id: openNetworkPanel
        command: [
            "env",
            "QT_QUICK_BACKEND=software",
            "quickshell",
            "--path",
            "/home/ppk/.config/quickshell/NetworkSecurityBar/NetworkSecurityBar.qml"
        ]
    }

    Component.onCompleted: {
        netSpeedProc.running = true
        localIPProc.running = true
        firewallProc.running = true
        malwareProc.running = true

        updatesChecking = true
        pendingUpdatesText = "Checking..."
        updatesProc.running = true

        Qt.callLater(function() {
            body.x = 50
        })
    }

    Timer {
        interval: 4000
        running: true
        repeat: true
        onTriggered: {
            netSpeedProc.running = false; netSpeedProc.running = true
            localIPProc.running = false; localIPProc.running = true
        }
    }

    PanelWindow {
        id: window
        anchors { top: true; bottom: true; right: true }
        implicitWidth: 400
        visible: true
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0

        Rectangle {
            id: body
            x: window.implicitWidth
            y: 0
            width: 340
            height: parent.height
            color: "#121317"
            opacity: 0.92
            border.color: "#555839"
            border.width: 1
            radius: 16

            Behavior on x {
                NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
            }

            ScrollView {
                id: scrollView
                anchors.fill: parent
                anchors.margins: 8
                clip: true

                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                // ─── Darker scrollbar styling ───────────────────────────────
                ScrollBar.vertical.background: Rectangle {
                    visible: scrollView.ScrollBar.vertical.active   // only show when actually scrolling
                    color: "#252627"           // very dark track
                    radius: 6
                }
                ScrollBar.vertical.contentItem: Rectangle {
                    radius: 6
                    color: "#252627"           // subdued dark gray handle
                    implicitWidth: 3
                    implicitHeight: 40
                }

                Column {
                    width: scrollView.width
                    spacing: 10

                    // ─── TOP HEADING ───────────────────────────────
                    Rectangle {
                        width: parent.width
                        height: 68
                        color: Qt.rgba(0.22, 0.24, 0.21, 0.85)
                        radius: 12
                        border.color: "#b0ac63"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "System Security"
                            color: "#dde5a2"
                            font.pixelSize: 28
                            font.family: "Monospace"
                            font.weight: Font.Bold
                            font.letterSpacing: 2
                        }
                    }

                    Item { height: 8; width: 1 }

                    // ─── Network Info ───
                    Rectangle {
                        width: parent.width
                        implicitHeight: netHeader.implicitHeight + 20
                        radius: 10
                        color: Qt.rgba(0.22, 0.24, 0.21, 0.7)
                        border.color: "#555839"
                        border.width: 1

                        Column {
                            id: netHeader
                            width: parent.width - 20
                            anchors.centerIn: parent
                            spacing: 8
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Network Info"
                                color: "#b0ac63"
                                font.pixelSize: 22
                                font.family: "Monospace"
                                font.weight: Font.Bold
                            }
                        }
                    }

                    Item { height: 4; width: 1 }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: netSpeed
                        color: "#d0cc93"
                        font.pixelSize: 22
                        font.family: "Monospace"
                    }

                    Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.09) }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "Local IP:  " + localIP
                        color: "#d0d0d0"
                        font.pixelSize: 17
                        font.family: "Monospace"
                        wrapMode: Text.Wrap
                    }

                    Item { height: 12; width: 1 }

                    Button {
                        text: "Network Details →"
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 240
                        height: 48

                        font.pixelSize: 16
                        font.family: "Monospace"

                        background: Rectangle {
                            radius: 10
                            color: "#2a3b1a"
                            border.color: "#4a6b3a"
                            border.width: 1

                            Behavior on color {
                                ColorAnimation { duration: 180 }
                            }
                        }

                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#d0e0b0"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            openNetworkPanel.running = false
                            openNetworkPanel.running = true
                        }
                    }

                    Item { height: 20; width: 1 }

                    // ─── Firewall Info ───
                    Rectangle {
                        width: parent.width
                        implicitHeight: fwHeader.implicitHeight + 20
                        radius: 10
                        color: Qt.rgba(0.22, 0.24, 0.21, 0.7)
                        border.color: "#555839"
                        border.width: 1

                        Column {
                            id: fwHeader
                            width: parent.width - 20
                            anchors.centerIn: parent
                            spacing: 8
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Firewall Info"
                                color: "#b0ac63"
                                font.pixelSize: 22
                                font.family: "Monospace"
                                font.weight: Font.Bold
                            }
                        }
                    }

                    Item { height: 6; width: 1 }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: firewallStatus
                        color: firewallActive ? "#c0d0a0" : "#ffaaaa"
                        font.pixelSize: 18
                        font.family: "Monospace"
                        font.weight: Font.Bold
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: firewallMessage !== ""
                        text: firewallMessage
                        color: "#e0c070"
                        font.pixelSize: 16
                        font.family: "Monospace"
                        font.weight: Font.Bold
                    }

                    Rectangle {
                        width: parent.width
                        implicitHeight: fwCol.implicitHeight + 20
                        color: Qt.rgba(0.18, 0.19, 0.17, 0.65)
                        radius: 6
                        visible: firewallAdvice !== ""

                        Column {
                            id: fwCol
                            width: parent.width - 20
                            anchors.centerIn: parent
                            spacing: 8

                            TextEdit {
                                id: firewallCmdText
                                width: parent.width
                                height: implicitHeight
                                text: firewallAdvice
                                color: "#e0c070"
                                font.pixelSize: 15
                                font.family: "Monospace"
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.WrapAnywhere
                                horizontalAlignment: TextEdit.AlignHCenter
                            }

                            Button {
                                text: "Copy"
                                anchors.horizontalCenter: parent.horizontalCenter

                                background: Rectangle {
                                    radius: 6
                                    color: "#b0ac63"
                                    border.color: Qt.darker("#555839", 1.2)
                                    border.width: 1
                                }

                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: "#383e35"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: {
                                    copyProcess.command = ["wl-copy", firewallCmdText.text]
                                    copyProcess.running = false
                                    copyProcess.running = true
                                }
                            }
                        }
                    }

                    Item { height: 16; width: 1 }

                    // ─── Malware Protection ───
                    Rectangle {
                        width: parent.width
                        implicitHeight: malHeader.implicitHeight + 20
                        radius: 10
                        color: Qt.rgba(0.22, 0.24, 0.21, 0.7)
                        border.color: "#555839"
                        border.width: 1

                        Column {
                            id: malHeader
                            width: parent.width - 20
                            anchors.centerIn: parent
                            spacing: 8
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Malware Protection"
                                color: "#b0ac63"
                                font.pixelSize: 22
                                font.family: "Monospace"
                                font.weight: Font.Bold
                            }
                        }
                    }

                    Item { height: 6; width: 1 }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: !clamInstalled
                        text: malwareStatus
                        color: "#ffaaaa"
                        font.pixelSize: 18
                        font.family: "Monospace"
                        font.weight: Font.Bold
                        wrapMode: Text.Wrap
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: !clamInstalled && malwareMessage !== ""
                        text: malwareMessage
                        color: "#e0c070"
                        font.pixelSize: 16
                        font.family: "Monospace"
                        font.weight: Font.Bold
                        wrapMode: Text.Wrap
                    }

                    Rectangle {
                        width: parent.width
                        implicitHeight: malInstCol.implicitHeight + 20
                        color: Qt.rgba(0.18, 0.19, 0.17, 0.65)
                        radius: 6
                        visible: !clamInstalled && malwareAdvice !== ""

                        Column {
                            id: malInstCol
                            width: parent.width - 20
                            anchors.centerIn: parent
                            spacing: 8

                            TextEdit {
                                id: malwareInstallText
                                width: parent.width
                                height: implicitHeight
                                text: malwareAdvice
                                color: "#e0c070"
                                font.pixelSize: 15
                                font.family: "Monospace"
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.WrapAnywhere
                                horizontalAlignment: TextEdit.AlignHCenter
                            }

                            Button {
                                text: "Copy"
                                anchors.horizontalCenter: parent.horizontalCenter

                                background: Rectangle {
                                    radius: 6
                                    color: "#b0ac63"
                                    border.color: Qt.darker("#555839", 1.2)
                                    border.width: 1
                                }

                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: "#383e35"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: {
                                    copyProcess.command = ["wl-copy", malwareInstallText.text]
                                    copyProcess.running = false
                                    copyProcess.running = true
                                }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: clamInstalled
                        text: "clamav-daemon: " + (daemonActive ? "Active" : "Inactive")
                        color: daemonActive ? "#c0d0a0" : "#ffaaaa"
                        font.pixelSize: 17
                        font.family: "Monospace"
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: clamInstalled
                        text: "freshclam:     " + (freshclamActive ? "Active" : "Inactive")
                        color: freshclamActive ? "#c0d0a0" : "#ffaaaa"
                        font.pixelSize: 17
                        font.family: "Monospace"
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: clamInstalled
                        text: "clamonacc:     " + (clamonaccActive ? "Active" : "Inactive")
                        color: clamonaccActive ? "#c0d0a0" : "#ffaaaa"
                        font.pixelSize: 17
                        font.family: "Monospace"
                    }

                    Item {
                        width: parent.width
                        height: childrenRect.height + 16
                        visible: clamInstalled && !clamonaccActive

                        Column {
                            width: parent.width
                            spacing: 10
                            anchors.horizontalCenter: parent.horizontalCenter

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Fix clamonacc here:"
                                color: "#e0c070"
                                font.pixelSize: 16
                                font.family: "Monospace"
                                font.bold: true
                            }

                            Button {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Copy YouTube guide link"
                                font.pixelSize: 15
                                padding: 8

                                background: Rectangle {
                                    radius: 6
                                    color: "#b0ac63"
                                    border.color: Qt.darker("#555839", 1.2)
                                    border.width: 1
                                }

                                contentItem: Text {
                                    text: parent.text
                                    font: parent.font
                                    color: "#383e35"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: {
                                    copyProcess.command = ["wl-copy", "http://youtube.com/post/UgkxA1I8Zf0JjuupMO9TqM8Ix-w8MPAj0qoT?si=nKWE4dK5tVa-leBq"]
                                    copyProcess.running = false
                                    copyProcess.running = true
                                }
                            }
                        }
                    }

                    Item { height: 16; width: 1 }

                    // ─── Arch Updates ───
                    Rectangle {
                        width: parent.width
                        height: 42
                        radius: 10
                        color: Qt.rgba(0.22, 0.24, 0.21, 0.7)
                        border.color: "#555839"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "Arch Updates"
                            color: "#b0ac63"
                            font.pixelSize: 20
                            font.family: "Monospace"
                            font.weight: Font.Bold
                        }
                    }

                    Item { height: 6; width: 1 }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: lastUpdateText
                        color: "#d0d0d0"
                        font.pixelSize: 16
                        font.family: "Monospace"
                        wrapMode: Text.Wrap
                    }

                    Text {
                        id: pendingText
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: updatesChecking ? "Checking..." : pendingUpdatesText
                        color: {
                            if (updatesChecking) return "#888888"
                                if (updatesOutdated) return "#ff4444"
                                    return pendingUpdatesText.includes("0") ? "#c0d0a0" : "#e0c070"
                        }
                        font.pixelSize: 16
                        font.family: "Monospace"
                        font.bold: updatesOutdated || (!updatesChecking && !pendingUpdatesText.includes("0"))
                        wrapMode: Text.WordWrap

                        opacity: 1
                        Behavior on opacity { NumberAnimation { duration: 800 } }

                        Timer {
                            interval: 1000
                            running: updatesOutdated && !updatesChecking
                            repeat: true
                            onTriggered: pendingText.opacity = pendingText.opacity === 1 ? 0.4 : 1
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 8

                        TextEdit {
                            id: updateCmdText
                            text: "sudo pacman -Syu"
                            color: "#c0d0a0"
                            font.pixelSize: 15
                            font.family: "Monospace"
                            readOnly: true
                            selectByMouse: true
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Button {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Copy"
                            font.pixelSize: 14

                            background: Rectangle {
                                radius: 6
                                color: "#b0ac63"
                                border.color: Qt.darker("#555839", 1.2)
                                border.width: 1
                            }

                            contentItem: Text {
                                text: parent.text
                                font: parent.font
                                color: "#383e35"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            onClicked: {
                                copyProcess.command = ["wl-copy", updateCmdText.text]
                                copyProcess.running = false
                                copyProcess.running = true
                            }
                        }
                    }

                    Item { height: 24; width: 1 }

                    // ─── Arch Fortress Mode ───
                    Rectangle {
                        width: parent.width
                        height: 42
                        radius: 10
                        color: Qt.rgba(0.22, 0.24, 0.21, 0.7)
                        border.color: "#555839"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "Arch Fortress Mode"
                            color: "#b0ac63"
                            font.pixelSize: 20
                            font.family: "Monospace"
                            font.weight: Font.Bold
                        }
                    }

                    Item { height: 10; width: 1 }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "https://youtu.be/_C3oBrADBOw"
                        color: "#a0c0ff"
                        font.pixelSize: 16
                        font.family: "Monospace"
                        wrapMode: Text.Wrap
                    }

                    Item { height: 8; width: 1 }

                    Button {
                        text: "Copy Link"
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 160
                        height: 40

                        font.pixelSize: 15
                        font.family: "Monospace"

                        background: Rectangle {
                            radius: 8
                            color: "#b0ac63"
                            border.color: Qt.darker("#555839", 1.2)
                            border.width: 1
                        }

                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: "#383e35"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            copyProcess.command = ["wl-copy", "https://youtu.be/_C3oBrADBOw"]
                            copyProcess.running = false
                            copyProcess.running = true
                        }
                    }

                    Item { height: 12; width: 1 }

                } // Column
            } // ScrollView
        } // body Rectangle
    } // PanelWindow
}
