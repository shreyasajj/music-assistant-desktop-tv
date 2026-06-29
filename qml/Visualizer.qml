// qml/Visualizer.qml — full-screen visualizer (VizCanvas) plus controls:
// BEAT slider, source indicator, mode bar, and a "Behind lyrics" toggle.
import QtQuick
import QtQuick.Controls

Item {
    id: viz
    readonly property var modes: ["radial", "flow", "bars"]

    // called from main.qml's D-pad handler
    function cycleMode(d) {
        var i = modes.indexOf(VizState.mode)
        VizState.mode = modes[(i + d + modes.length) % modes.length]
    }

    readonly property bool simulated: audioAnalyzer.simulated
    readonly property bool flowing: audioAnalyzer.energy > 0.004 || audioAnalyzer.bass > 0.03
    readonly property bool sourceActive: simulated || flowing
    readonly property string sourceLabel: simulated ? "Simulated"
                                                     : (flowing ? "Live feed" : "Waiting for audio")

    Rectangle { anchors.fill: parent; color: "#050507" }

    VizCanvas { anchors.fill: parent }

    // beat control + source + behind-lyrics toggle (top-left, matches .beat-ctrl)
    Row {
        anchors { left: parent.left; top: parent.top; leftMargin: 56; topMargin: 128 }
        spacing: 14

        Rectangle {            // .beat-slider
            height: 60
            width: beatSliderRow.implicitWidth + 52
            radius: 40
            color: Qt.rgba(10 / 255, 10 / 255, 16 / 255, 0.5)
            border.color: Qt.rgba(1, 1, 1, 0.08)
            border.width: 1
            Row {
                id: beatSliderRow
                anchors.centerIn: parent
                spacing: 18
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "BEAT"; font.pixelSize: 19; font.weight: Font.ExtraBold
                    font.letterSpacing: 3; color: Qt.rgba(1, 1, 1, 0.55)
                }
                Slider {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 210
                    from: 0; to: 2.4; stepSize: 0.05; value: VizState.beatMul
                    onValueChanged: VizState.beatMul = value
                }
            }
        }

        Rectangle {            // .source-btn (source indicator)
            height: 60
            width: sourceRow.implicitWidth + 48
            radius: 40
            color: viz.sourceActive ? Qt.rgba(0, 224 / 255, 198 / 255, 0.12) : Qt.rgba(10 / 255, 10 / 255, 16 / 255, 0.5)
            border.color: viz.sourceActive ? Theme.a1 : Qt.rgba(1, 1, 1, 0.1)
            border.width: 1
            Row {
                id: sourceRow
                anchors.centerIn: parent
                spacing: 12
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 11; height: 11; radius: 6
                    color: viz.sourceActive ? Theme.a1 : Qt.rgba(1, 1, 1, 0.4)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: viz.sourceLabel
                    font.pixelSize: 21; font.weight: Font.Bold
                    color: viz.sourceActive ? Theme.a1 : Qt.rgba(1, 1, 1, 0.7)
                }
            }
        }

        // Behind-lyrics toggle — option to paint the visualizer under the Lyrics tab.
        Rectangle {
            id: behindBtn
            property bool on: settingsController.vizBehindLyrics
            height: 60
            width: behindRow.implicitWidth + 48
            radius: 40
            color: on ? Qt.rgba(0, 224 / 255, 198 / 255, 0.12) : Qt.rgba(10 / 255, 10 / 255, 16 / 255, 0.5)
            border.color: on ? Theme.a1 : Qt.rgba(1, 1, 1, 0.1)
            border.width: 1
            Row {
                id: behindRow
                anchors.centerIn: parent
                spacing: 12
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 11; height: 11; radius: 6
                    color: behindBtn.on ? Theme.a1 : Qt.rgba(1, 1, 1, 0.4)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Behind lyrics"
                    font.pixelSize: 21; font.weight: Font.Bold
                    color: behindBtn.on ? Theme.a1 : Qt.rgba(1, 1, 1, 0.7)
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: settingsController.setVizBehindLyrics(!behindBtn.on)
            }
        }
    }

    // mode bar — match .mode-bar in styles.css
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 48
        height: 72
        width: modeRow.implicitWidth + 24
        radius: 50
        color: Qt.rgba(10 / 255, 10 / 255, 16 / 255, 0.55)
        border.color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 1

        Row {
            id: modeRow
            anchors.centerIn: parent
            spacing: 0
            Repeater {
                model: ListModel {
                    ListElement { modeKey: "radial"; modeLabel: "Radial Pulse" }
                    ListElement { modeKey: "flow";   modeLabel: "Flow Lines"   }
                    ListElement { modeKey: "bars";   modeLabel: "Bars"         }
                }
                delegate: Rectangle {
                    property bool isActive: VizState.mode === modeKey
                    height: 48
                    width: btnLabel.implicitWidth + 64
                    radius: 40
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: isActive ? Theme.a1 : "transparent" }
                        GradientStop { position: 1.0; color: isActive ? Theme.a2 : "transparent" }
                    }
                    Text {
                        id: btnLabel
                        anchors.centerIn: parent
                        text: modeLabel
                        font.pixelSize: 26
                        font.bold: true
                        color: isActive ? "#06121a" : Qt.rgba(1, 1, 1, 0.7)
                    }
                    MouseArea { anchors.fill: parent; onClicked: VizState.mode = modeKey }
                }
            }
        }
    }

    // track name bottom-left
    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 80
        text: maClient.trackTitle + (maClient.trackArtist ? " · " + maClient.trackArtist : "")
        color: Theme.fg
        font.pixelSize: Theme.xl
        font.bold: true
    }
}
