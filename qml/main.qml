import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: win
    visible: true
    visibility: Window.FullScreen
    color: Theme.bg
    property var tabs: ["Now Playing", "Search", "Lyrics", "Visualizer"]

    Item {
        id: root
        anchors.fill: parent
        focus: true

        Keys.onRightPressed: stack.currentIndex = Math.min(stack.currentIndex + 1, tabs.length - 1)
        Keys.onLeftPressed: stack.currentIndex = Math.max(stack.currentIndex - 1, 0)
        Keys.onDigit1Pressed: stack.currentIndex = 0
        Keys.onDigit2Pressed: stack.currentIndex = 1
        Keys.onDigit3Pressed: stack.currentIndex = 2
        Keys.onDigit4Pressed: stack.currentIndex = 3

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            RowLayout {                                   // tab bar
                Layout.fillWidth: true
                Layout.margins: 32
                spacing: 48
                Repeater {
                    model: win.tabs
                    Text {
                        text: modelData
                        font.pixelSize: Theme.md
                        color: stack.currentIndex === index ? Theme.fg : Theme.muted
                        MouseArea { anchors.fill: parent; onClicked: stack.currentIndex = index }
                    }
                }
            }

            StackLayout {
                id: stack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: 0
                NowPlaying { }
                Search { }
                Lyrics { }
                Rectangle { color: "transparent"; Text { anchors.centerIn: parent; color: Theme.fg; text: "Visualizer"; font.pixelSize: Theme.xl } }
            }
        }
    }
}
