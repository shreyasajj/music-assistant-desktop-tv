// qml/SettingsView.qml — pre-fills current settings so saving never clobbers an
// existing token. Fields seed from settingsController's readable properties.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    function fieldBg(active) {
        return active ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.06)
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 24
        width: 900

        Text {
            text: "Settings"
            color: Theme.fg
            font.pixelSize: Theme.xl
            font.weight: Font.ExtraBold
        }

        component Field: TextField {
            Layout.fillWidth: true
            font.pixelSize: Theme.md
            color: Theme.fg
            placeholderTextColor: Qt.rgba(1, 1, 1, 0.32)
            leftPadding: 22
            background: Rectangle {
                radius: 14
                color: parent.activeFocus ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.06)
                border.color: parent.activeFocus ? Theme.a1 : Qt.rgba(1, 1, 1, 0.12)
                border.width: parent.activeFocus ? 2 : 1
            }
        }

        Field { id: host; placeholderText: "MA host"; text: settingsController.host }
        Field { id: port; placeholderText: "MA port"; text: String(settingsController.port) }
        Field { id: token; placeholderText: "MA token (optional)"; text: settingsController.token; echoMode: TextInput.PasswordEchoOnEdit }
        Field { id: gport; placeholderText: "Guest port"; text: String(settingsController.guestPort) }

        component OptionToggle: RowLayout {
            property alias checked: sw.checked
            property string label: ""
            Layout.topMargin: 4
            Layout.fillWidth: true
            spacing: 16
            Switch { id: sw }
            Text {
                text: parent.label
                color: Theme.fg
                font.pixelSize: Theme.sm
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }

        OptionToggle { id: lrclibSwitch; checked: settingsController.lrclibFallback
            label: "Fetch lyrics from LRCLIB when Music Assistant has none" }
        OptionToggle { id: compactSwitch; checked: settingsController.compactLyrics
            label: "Compact lyrics — show only the previous, current and next two lines" }
        OptionToggle { id: artPumpSwitch; checked: settingsController.artPump
            label: "Pump the Now Playing artwork with the song's bass" }
        OptionToggle { id: behindSwitch; checked: settingsController.vizBehindLyrics
            label: "Show the visualizer behind the lyrics" }

        // Visualizer audio capture device (for the live bars / art pump)
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8
            spacing: 8
            Text {
                text: "Visualizer audio source"
                color: Qt.rgba(1, 1, 1, 0.7)
                font.pixelSize: Theme.sm
            }
            ComboBox {
                id: deviceBox
                Layout.fillWidth: true
                model: settingsController.audioDevices
                font.pixelSize: Theme.sm
                // index 0 = "" (simulated), 1 = "__auto__", rest = device names
                function valueAt(i) { return i === 0 ? "" : i === 1 ? "__auto__" : currentText }
                Component.onCompleted: {
                    var v = settingsController.audioDevice
                    if (v === "") currentIndex = 0
                    else if (v === "__auto__") currentIndex = 1
                    else { var i = model.indexOf(v); currentIndex = i >= 0 ? i : 0 }
                }
                contentItem: Text {
                    leftPadding: 18; rightPadding: 44
                    text: deviceBox.displayText
                    color: Theme.fg
                    font.pixelSize: Theme.sm
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
                background: Rectangle {
                    implicitHeight: 56
                    radius: 14
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                    border.width: 1
                }
                delegate: ItemDelegate {
                    width: deviceBox.width
                    highlighted: deviceBox.highlightedIndex === index
                    contentItem: Text {
                        text: modelData; color: Theme.fg; font.pixelSize: Theme.sm; elide: Text.ElideRight
                    }
                    background: Rectangle {
                        color: highlighted ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(15 / 255, 15 / 255, 21 / 255, 1)
                    }
                }
                popup: Popup {
                    y: deviceBox.height + 4
                    width: deviceBox.width
                    implicitHeight: Math.min(contentItem.implicitHeight + 12, 420)
                    padding: 6
                    contentItem: ListView {
                        clip: true
                        implicitHeight: contentHeight
                        model: deviceBox.popup.visible ? deviceBox.delegateModel : null
                        currentIndex: deviceBox.highlightedIndex
                        ScrollIndicator.vertical: ScrollIndicator {}
                    }
                    background: Rectangle {
                        radius: 12
                        color: Qt.rgba(15 / 255, 15 / 255, 21 / 255, 0.98)
                        border.color: Qt.rgba(1, 1, 1, 0.12)
                        border.width: 1
                    }
                }
            }
        }

        Button {
            id: saveBtn
            text: "Save"
            font.pixelSize: Theme.md
            Layout.topMargin: 8
            contentItem: Text {
                text: saveBtn.text
                color: "#06121a"
                font.pixelSize: Theme.md
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                implicitWidth: 220
                implicitHeight: 64
                radius: 40
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Theme.a1 }
                    GradientStop { position: 1; color: Theme.a2 }
                }
            }
            onClicked: settingsController.save(host.text, parseInt(port.text) || 0,
                                               token.text, parseInt(gport.text) || 0,
                                               lrclibSwitch.checked, compactSwitch.checked,
                                               artPumpSwitch.checked, behindSwitch.checked,
                                               deviceBox.valueAt(deviceBox.currentIndex))
        }
    }
}
