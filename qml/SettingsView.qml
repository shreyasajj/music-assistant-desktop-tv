// qml/SettingsView.qml — pre-fills current settings (never clobbers the token) and
// is fully keyboard/D-pad navigable: Up/Down move between controls, Space/Enter
// activates (toggle / open list / Save), Up from the first field exits to the tabs.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    signal requestTopbar()                       // Up from the first field -> tabs
    function focusFirst() { host.forceActiveFocus() }
    onVisibleChanged: if (visible) Qt.callLater(focusFirst)

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 20
        width: 980

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

        Field {
            id: host; placeholderText: "MA host"; text: settingsController.host
            KeyNavigation.down: port
            Keys.onUpPressed: function (e) { root.requestTopbar(); e.accepted = true }
        }
        Field {
            id: port; placeholderText: "MA port"; text: String(settingsController.port)
            KeyNavigation.up: host; KeyNavigation.down: token
        }
        Field {
            id: token; placeholderText: "MA token (optional)"; text: settingsController.token
            echoMode: TextInput.PasswordEchoOnEdit
            KeyNavigation.up: port; KeyNavigation.down: gport
        }
        Field {
            id: gport; placeholderText: "Guest port"; text: String(settingsController.guestPort)
            KeyNavigation.up: token; KeyNavigation.down: lrclibSwitch.control
        }

        component OptionToggle: RowLayout {
            property alias checked: sw.checked
            property alias control: sw
            property var navUp: null
            property var navDown: null
            property string label: ""
            Layout.topMargin: 2
            Layout.fillWidth: true
            spacing: 16
            Switch {
                id: sw
                KeyNavigation.up: parent.navUp
                KeyNavigation.down: parent.navDown
                Rectangle {                       // focus ring
                    anchors.fill: parent; anchors.margins: -6; radius: 10; z: -1
                    color: "transparent"
                    border.color: sw.activeFocus ? Theme.a1 : "transparent"
                    border.width: 3
                }
            }
            Text {
                text: parent.label
                color: Theme.fg
                font.pixelSize: Theme.sm
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }

        OptionToggle { id: lrclibSwitch; checked: settingsController.lrclibFallback
            label: "Fetch lyrics from LRCLIB when Music Assistant has none"
            navUp: gport; navDown: compactSwitch.control }
        OptionToggle { id: compactSwitch; checked: settingsController.compactLyrics
            label: "Compact lyrics — show only the previous, current and next two lines"
            navUp: lrclibSwitch.control; navDown: artPumpSwitch.control }
        OptionToggle { id: artPumpSwitch; checked: settingsController.artPump
            label: "Pump the Now Playing artwork with the beat and bass"
            navUp: compactSwitch.control; navDown: behindSwitch.control }
        OptionToggle { id: behindSwitch; checked: settingsController.vizBehindLyrics
            label: "Show the visualizer behind the lyrics"
            navUp: artPumpSwitch.control; navDown: deviceBox }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
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
                // Up/Down navigate to other controls when the list is closed;
                // Enter/Space opens it (then the popup handles Up/Down).
                Keys.onUpPressed: function (e) { if (!popup.visible) { behindSwitch.control.forceActiveFocus(); e.accepted = true } }
                Keys.onDownPressed: function (e) { if (!popup.visible) { saveBtn.forceActiveFocus(); e.accepted = true } }
                Keys.onReturnPressed: function (e) { if (!popup.visible) { popup.open(); e.accepted = true } }
                Keys.onSpacePressed: function (e) { if (!popup.visible) { popup.open(); e.accepted = true } }
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
                    border.color: deviceBox.activeFocus ? Theme.a1 : Qt.rgba(1, 1, 1, 0.12)
                    border.width: deviceBox.activeFocus ? 2 : 1
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
            property bool saved: false
            text: "Save"
            font.pixelSize: Theme.md
            Layout.topMargin: 6
            KeyNavigation.up: deviceBox
            contentItem: Text {
                text: saveBtn.saved ? "Saved ✓" : "Save"
                color: "#06121a"
                font.pixelSize: Theme.md
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                implicitWidth: 240
                implicitHeight: 64
                radius: 40
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Theme.a1 }
                    GradientStop { position: 1; color: Theme.a2 }
                }
                border.color: saveBtn.activeFocus ? "#ffffff" : "transparent"
                border.width: saveBtn.activeFocus ? 3 : 0
            }
            onClicked: {
                settingsController.save(host.text, parseInt(port.text) || 0,
                                        token.text, parseInt(gport.text) || 0,
                                        lrclibSwitch.checked, compactSwitch.checked,
                                        artPumpSwitch.checked, behindSwitch.checked,
                                        deviceBox.valueAt(deviceBox.currentIndex))
                saveBtn.saved = true
                savedTimer.restart()
            }
            Timer { id: savedTimer; interval: 1600; onTriggered: saveBtn.saved = false }
        }
    }
}
