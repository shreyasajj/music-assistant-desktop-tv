// qml/PlayerMenu.qml — player chip dropdown, matching .player-menu in styles.css.
// Glass panel listing maClient.players; the active device is accent-colored.
import QtQuick

Rectangle {
    id: menu
    property bool open: false
    property bool guestOn: false
    signal requestClose()

    visible: open
    width: 300
    height: menuCol.implicitHeight + 18
    radius: 18
    color: Qt.rgba(15 / 255, 15 / 255, 21 / 255, 0.97)
    border.color: Qt.rgba(1, 1, 1, 0.1)
    border.width: 1

    Column {
        id: menuCol
        anchors { fill: parent; margins: 9 }
        spacing: 2
        Repeater {
            model: maClient.players
            delegate: Rectangle {
                width: menuCol.width
                height: 56
                radius: 12
                property bool isActive: modelData.id === maClient.activePlayerId
                color: isActive ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                Text {
                    anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                    text: modelData.name || modelData.id
                    font.pixelSize: 23
                    font.weight: isActive ? Font.Bold : Font.Medium
                    color: isActive ? Theme.a1 : Qt.rgba(1, 1, 1, 0.8)
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { maClient.select_player(modelData.id); menu.requestClose() }
                }
            }
        }
    }
}
