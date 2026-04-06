import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    property string hardeningScore: "--"
    property string aiAdvice: "Waiting for scan..."
    property bool isRunning: false
    property bool aiStarted: false
    property bool inArchSection: false

    ListModel { id: resultsModel }
    ListModel { id: archModel }

    Process {
        id: auditProc
        command: ["/home/ppk/.config/Scripts/audit.sh"]

        stdout: SplitParser {
            onRead: function(line) {
                let trimmed = line.trim()
                if (!trimmed) return

                    // Score - now matches the exact line the script prints
                    if (trimmed.includes("Hardening Index:")) {
                        let match = trimmed.match(/(\d+)/)
                        if (match) hardeningScore = match[1]
                    }

                    // === Arch-Audit section handling (inserted before AI parsing) ===
                    else if (trimmed.includes("Arch-Audit High Risk Issues:")) {
                        inArchSection = true
                        archModel.clear()
                    }
                    else if (inArchSection && trimmed.length > 3 && !trimmed.includes("Consulting AI...")) {
                        archModel.append({ "entry": trimmed })
                    }

                    // Warnings (always first) — unchanged
                    else if (
                        trimmed.includes("Warnings") ||
                        trimmed.startsWith("!") ||
                        trimmed.startsWith("*") ||
                        trimmed.match(/^\s*-\s/) ||
                        trimmed.includes("Details") ||
                        trimmed.includes("Solution") ||
                        trimmed.includes("https://") ||
                        trimmed.match(/^\s{2,}/) ||
                        trimmed.includes("None found")
                    ) {
                        resultsModel.append({ "entry": trimmed })
                    }

                    // AI only starts after "Consulting AI..."
                    else if (trimmed.includes("Consulting AI...")) {
                        inArchSection = false
                        aiStarted = true
                        aiAdvice = trimmed
                    }
                    else if (aiStarted && trimmed.length > 3 && !trimmed.startsWith("[")) {
                        aiAdvice += "\n" + trimmed
                    }
            }
        }
        onExited: { isRunning = false }
    }

    PanelWindow {
        id: window
        implicitWidth: 740
        implicitHeight: 1050
        visible: true
        color: Qt.rgba(0.07, 0.08, 0.09, 0.90)

        anchors { top: true; left: true }

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrLayer.OnDemand

        WlrLayershell.margins { top: 20; left: 20 }

        Rectangle {
            anchors.fill: parent
            border.color: "#b0ac63"
            border.width: 1
            radius: 12
            color: "transparent"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 18

                RowLayout {
                    Text {
                        text: "Lynis Security Audit"
                        color: "#dde5a2"
                        font.family: "Monospace"
                        font.pixelSize: 26
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "Score: " + hardeningScore + "/100"
                        color: "#c0d0a0"
                        font.family: "Monospace"
                        font.pixelSize: 24
                        font.bold: true
                    }
                }

                Text {
                    text: "Warnings:"
                    color: "#b0ac63"
                    font.family: "Monospace"
                    font.bold: true
                    font.pixelSize: 17
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Qt.rgba(0.1, 0.11, 0.12, 0.95)
                    radius: 8
                    clip: true

                    ScrollView {
                        anchors.fill: parent
                        anchors.margins: 12
                        clip: true

                        ListView {
                            model: resultsModel
                            spacing: 6
                            delegate: TextEdit {
                                width: parent.width - 20
                                text: model.entry
                                color: model.entry.startsWith("!") ? "#f38ba8" : "#d0d0d0"
                                font.family: "Monospace"
                                font.pixelSize: 13
                                wrapMode: TextEdit.Wrap
                                readOnly: true
                                selectByMouse: true
                            }
                        }
                    }
                }

                // === Arch-Audit heading now matches Lynis Security Audit style exactly ===
                Text {
                    text: "Arch-Audit High Risk Issues:"
                    color: "#dde5a2"
                    font.family: "Monospace"
                    font.pixelSize: 26
                    font.bold: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 210
                    color: Qt.rgba(0.1, 0.11, 0.12, 0.95)
                    radius: 8
                    clip: true

                    ScrollView {
                        anchors.fill: parent
                        anchors.margins: 12
                        clip: true

                        ListView {
                            model: archModel
                            spacing: 6
                            delegate: TextEdit {
                                width: parent.width - 20
                                text: model.entry
                                color: (model.entry.includes("High risk!") || model.entry.includes("NOT INSTALLED") || model.entry.includes("Install with")) ? "#f38ba8" : "#d0d0d0"
                                font.family: "Monospace"
                                font.pixelSize: 13
                                wrapMode: TextEdit.Wrap
                                readOnly: true
                                selectByMouse: true
                            }
                        }
                    }
                }

                Text {
                    text: "AI Strategic Advice:"
                    color: "#e0c070"
                    font.family: "Monospace"
                    font.bold: true
                    font.pixelSize: 17
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 290
                    clip: true

                    TextArea {
                        text: aiAdvice
                        color: "#d0cc93"
                        font.family: "Monospace"
                        font.pixelSize: 15
                        wrapMode: Text.Wrap
                        readOnly: true
                        selectByMouse: true
                        background: Rectangle { color: Qt.rgba(0.1, 0.11, 0.12, 0.95) }
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 24

                    Button {
                        text: isRunning ? "Auditing..." : "Start Deep Scan"
                        enabled: !isRunning
                        onClicked: {
                            resultsModel.clear()
                            archModel.clear()
                            hardeningScore = "--"
                            aiAdvice = "Waiting for scan..."
                            aiStarted = false
                            inArchSection = false
                            isRunning = true
                            auditProc.running = true
                        }
                        background: Rectangle {
                            implicitHeight: 48; implicitWidth: 190; radius: 8; color: "#a5a15e"
                        }
                        contentItem: Text {
                            text: parent.text; color: "#121317"; font.bold: true
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: "Exit"
                        onClicked: window.visible = false
                        background: Rectangle {
                            implicitHeight: 48; implicitWidth: 140; radius: 8; color: "#a83f3f"
                        }
                        contentItem: Text {
                            text: parent.text; color: "#121317"; font.bold: true
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
