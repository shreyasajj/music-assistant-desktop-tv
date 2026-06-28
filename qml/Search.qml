// qml/Search.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    ColumnLayout {
        anchors.fill: parent; anchors.margins: Theme.pad; spacing: 32
        TextField {
            id: q; Layout.fillWidth: true
            placeholderText: "Search..."; font.pixelSize: Theme.xl
            background: Rectangle { color: Theme.panel; radius: Theme.radius }
            onAccepted: maClient.searchAsync(text)
        }
        ListView {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 24; clip: true
            model: maClient.searchResults
            delegate: Rectangle {
                width: ListView.view.width; height: 168
                radius: Theme.radius; color: Theme.panel
                RowLayout {
                    anchors.fill: parent; anchors.margins: 24; spacing: 32
                    Rectangle { width: 120; height: 120; radius: 12; color: Theme.bg
                        Image { anchors.fill: parent; source: modelData.image; fillMode: Image.PreserveAspectCrop } }
                    ColumnLayout {
                        Text { text: modelData.title; color: Theme.fg; font.pixelSize: Theme.lg; font.bold: true }
                        Text { text: modelData.artist + (modelData.album ? " · " + modelData.album : "")
                               color: Theme.muted; font.pixelSize: Theme.md }
                    }
                    Item { Layout.fillWidth: true }
                    Button { text: "Play"; font.pixelSize: Theme.md; onClicked: maClient.playNow(modelData.uri) }
                    Button { text: "Queue"; font.pixelSize: Theme.md; onClicked: maClient.addToQueue(modelData.uri) }
                }
            }
        }
    }
}
