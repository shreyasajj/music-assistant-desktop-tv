// qml/UpNextQueue.qml — "Up Next" glass panel matching .queue in styles.css.
// Bound to maClient.queue; drops below the corner QR card in guest mode.
import QtQuick

Rectangle {
    id: queuePanel
    property bool guestOn: false

    visible: maClient.queue.length > 0
    width: 432
    height: queueCol.implicitHeight + 44
    radius: 24
    color: Qt.rgba(10 / 255, 10 / 255, 16 / 255, 0.5)
    border.color: Qt.rgba(1, 1, 1, 0.08)
    border.width: 1

    function formatMs(ms) {
        if (!ms || ms <= 0) return ""
        var total = Math.floor(ms / 1000)
        var m = Math.floor(total / 60)
        var s = total % 60
        return m + ":" + (s < 10 ? "0" + s : s)
    }

    Column {
        id: queueCol
        anchors { fill: parent; margins: 22 }
        spacing: 2

        // header
        Item {
            width: parent.width
            height: 36
            Text {
                anchors.left: parent.left
                text: "Up Next"
                color: Theme.fg
                font.pixelSize: 27
                font.weight: Font.ExtraBold
            }
            Text {
                anchors.right: parent.right
                anchors.baseline: parent.bottom
                text: maClient.queue.length + (maClient.queue.length === 1 ? " song" : " songs")
                color: Qt.rgba(1, 1, 1, 0.5)
                font.pixelSize: 19
                font.weight: Font.DemiBold
            }
        }

        // rows (cap at 5, or 4 when stacked under the QR card)
        Repeater {
            model: Math.min(maClient.queue.length, queuePanel.guestOn ? 4 : 5)
            delegate: Item {
                width: queueCol.width
                height: 76
                property var item: maClient.queue[index]

                Rectangle {            // thumb
                    id: thumb
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    width: 58; height: 58; radius: 10
                    color: Theme.panel
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: item.image || ""
                        fillMode: Image.PreserveAspectCrop
                    }
                }
                Text {
                    id: qName
                    anchors { left: thumb.right; leftMargin: 15; right: qDur.left; rightMargin: 12
                              top: parent.top; topMargin: 12 }
                    text: item.title || ""
                    color: Theme.fg
                    font.pixelSize: 23
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }
                Text {
                    anchors { left: thumb.right; leftMargin: 15; right: qDur.left; rightMargin: 12
                              top: qName.bottom; topMargin: 2 }
                    text: item.artist || ""
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.pixelSize: 18
                    elide: Text.ElideRight
                }
                Text {
                    id: qDur
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: queuePanel.formatMs(item.duration_ms)
                    color: Qt.rgba(1, 1, 1, 0.45)
                    font.pixelSize: 18
                }
            }
        }
    }
}
