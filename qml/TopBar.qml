// qml/TopBar.qml — wordmark + centered tabs + player chip + Guest button,
// matching .topbar / .wordmark / .tabs / .topright in styles.css.
import QtQuick

Item {
    id: bar
    height: 104

    // state from the shell
    property int currentIndex: 0
    property string focusZone: "content"
    property int topIdx: 0
    property var tabs: []
    property int guestIdx: 0
    property bool guestOn: false
    property string playerName: ""

    signal tabActivated(int index)
    signal chipClicked()
    signal guestClicked()

    readonly property bool guestFocused: focusZone === "topbar" && topIdx === guestIdx

    // gradient scrim behind the bar
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0; color: Qt.rgba(0.027, 0.027, 0.043, 0.92) }
            GradientStop { position: 1; color: Qt.rgba(0.027, 0.027, 0.043, 0) }
        }
    }

    // Wordmark (left)
    Row {
        anchors { left: parent.left; leftMargin: 56; verticalCenter: parent.verticalCenter }
        spacing: 15
        Rectangle {
            width: 34; height: 34; radius: 9
            anchors.verticalCenter: parent.verticalCenter
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.a1 }
                GradientStop { position: 1; color: Theme.a2 }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.StyledText
            text: "Bigscreen <font color='#00e0c6'>Jukebox</font>"
            color: Theme.fg
            font.pixelSize: 26
            font.weight: Font.ExtraBold
        }
    }

    // Centered tabs
    Row {
        anchors.centerIn: parent
        spacing: 6
        Repeater {
            model: bar.tabs
            delegate: Item {
                width: tabLabel.implicitWidth + 52
                height: 64
                property bool active: bar.currentIndex === index
                property bool focused: bar.focusZone === "topbar" && bar.topIdx === index

                Rectangle {            // focus highlight
                    anchors.fill: parent
                    radius: 14
                    visible: parent.focused
                    color: Qt.rgba(1, 1, 1, 0.1)
                    border.color: Theme.a1
                    border.width: 3
                }
                Text {
                    id: tabLabel
                    anchors.centerIn: parent
                    text: modelData
                    font.pixelSize: 30
                    font.weight: Font.Bold
                    color: (active || focused) ? Theme.fg : Qt.rgba(1, 1, 1, 0.45)
                }
                Rectangle {            // active underline
                    visible: active
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 24 }
                    anchors.bottomMargin: 5
                    height: 4; radius: 3
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Theme.a1 }
                        GradientStop { position: 1; color: Theme.a2 }
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: bar.tabActivated(index) }
            }
        }
    }

    // Top-right: player chip (Now Playing only) + Guest button
    Row {
        anchors { right: parent.right; rightMargin: 56; verticalCenter: parent.verticalCenter }
        spacing: 16

        // Player chip — hidden in guest mode (corner QR card owns that space)
        Rectangle {
            id: playerChip
            visible: bar.currentIndex === 0 && !bar.guestOn
            anchors.verticalCenter: parent.verticalCenter
            height: 50
            width: chipRow.implicitWidth + 44
            radius: 40
            color: Qt.rgba(1, 1, 1, 0.06)
            border.color: Qt.rgba(1, 1, 1, 0.1)
            border.width: 1
            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 11
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 9; height: 9; radius: 5; color: Theme.a1
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.StyledText
                    text: "Playing on <b>" + bar.playerName + "</b> ▾"
                    color: Qt.rgba(1, 1, 1, 0.78)
                    font.pixelSize: 23
                }
            }
            MouseArea { anchors.fill: parent; onClicked: bar.chipClicked() }
        }

        // Guest button — replaced by the corner QR card when active
        Rectangle {
            id: guestBtn
            visible: !bar.guestOn
            anchors.verticalCenter: parent.verticalCenter
            height: 50
            width: guestRow.implicitWidth + 40
            radius: 40
            color: Qt.rgba(1, 1, 1, 0.06)
            border.color: bar.guestFocused ? Theme.a1 : Qt.rgba(1, 1, 1, 0.1)
            border.width: bar.guestFocused ? 3 : 1
            Row {
                id: guestRow
                anchors.centerIn: parent
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "▦"; font.pixelSize: 22; color: Qt.rgba(1, 1, 1, 0.78)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Guest"; font.pixelSize: 23; font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.78)
                }
            }
            MouseArea { anchors.fill: parent; onClicked: bar.guestClicked() }
        }
    }
}
