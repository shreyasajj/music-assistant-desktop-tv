// qml/GuestOverlay.qml — corner QR card matching .qr-card in styles.css (white card, dark text).
// Shown only while guest mode is on; positioned by the parent. `focused` adds the D-pad ring.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: card
    property bool focused: false
    visible: guestController.enabled
    width: 212
    height: overlayCol.implicitHeight + 36
    radius: 20
    color: "#ffffff"
    border.color: focused ? Qt.rgba(0, 224 / 255, 198 / 255, 1) : "transparent"
    border.width: focused ? 3 : 0

    ColumnLayout {
        id: overlayCol
        anchors.centerIn: parent
        spacing: 13
        width: parent.width - 36

        Image {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 176
            Layout.preferredHeight: 176
            source: guestController.qrUri
            fillMode: Image.PreserveAspectFit
        }
        Text {
            text: "Scan to add songs"
            color: "#14141a"
            font.pixelSize: 21
            font.bold: true
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Text {
            text: guestController.displayUrl
            color: "#0a8f80"
            font.pixelSize: 16
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    MouseArea { anchors.fill: parent; onClicked: guestController.toggle() }
}
