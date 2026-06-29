// qml/Lyrics.qml — karaoke lyrics. Two layouts (option: settingsController.compactLyrics):
//   compact  — only the previous line, the active line, and the next two lines
//   full     — the whole lyric sheet scrolling through a centered highlight
// Optionally renders the visualizer behind the text (settingsController.vizBehindLyrics).
import QtQuick
import QtQuick.Controls

Item {
    id: root
    property var lyrics: JSON.parse(maClient.lyricsJson)
    Connections { target: maClient; function onLyricsJsonChanged() { root.lyrics = JSON.parse(maClient.lyricsJson) } }

    property int active: activeLineIndex(maClient.positionMs)
    Connections {
        target: maClient
        function onPositionMsChanged() { root.active = root.activeLineIndex(maClient.positionMs) }
    }

    function activeLineIndex(posMs) {
        if (!lyrics.synced || !lyrics.lines) return -1
        var idx = -1
        for (var i = 0; i < lyrics.lines.length; i++) {
            if (lyrics.lines[i].time_ms !== null && lyrics.lines[i].time_ms <= posMs) idx = i
            else break
        }
        return idx
    }
    function lineText(i) {
        return (lyrics.lines && i >= 0 && i < lyrics.lines.length) ? lyrics.lines[i].text : ""
    }
    readonly property int count: (lyrics.lines ? lyrics.lines.length : 0)
    // clamp so the first line reads as "active" before the first timestamp passes
    readonly property int act: Math.max(0, active)

    // optional visualizer background — recolored to magenta/violet so it doesn't
    // blend with the teal active lyric line.
    VizCanvas {
        anchors.fill: parent
        dim: true
        visible: settingsController.vizBehindLyrics
        c1: [255, 61, 166]
        c2: [124, 77, 255]
    }

    // soft glow (matches .lyrics-glow), hidden when the viz background is on
    Rectangle {
        anchors.fill: parent
        visible: !settingsController.vizBehindLyrics
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 224 / 255, 198 / 255, 0.04) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // ── Compact window: previous / active / next / next ───────────────────────
    Item {
        anchors.fill: parent
        visible: settingsController.compactLyrics && root.count > 0

        Text {
            id: aActive
            anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
            width: parent.width - 360
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.lineText(root.act)
            color: Theme.a1
            font.pixelSize: 92
            font.weight: Font.ExtraBold
            Behavior on font.pixelSize { NumberAnimation { duration: 150 } }
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: aActive.top; bottomMargin: 36 }
            width: parent.width - 460
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.lineText(root.act - 1)
            color: Qt.rgba(1, 1, 1, 0.5)
            font.pixelSize: 48
            font.weight: Font.Bold
        }
        Text {
            id: aNext1
            anchors { horizontalCenter: parent.horizontalCenter; top: aActive.bottom; topMargin: 36 }
            width: parent.width - 460
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.lineText(root.act + 1)
            color: Qt.rgba(1, 1, 1, 0.5)
            font.pixelSize: 48
            font.weight: Font.Bold
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; top: aNext1.bottom; topMargin: 24 }
            width: parent.width - 520
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.lineText(root.act + 2)
            color: Qt.rgba(1, 1, 1, 0.28)
            font.pixelSize: 42
        }
    }

    // ── Full scrolling sheet ──────────────────────────────────────────────────
    ListView {
        id: list
        anchors.fill: parent
        visible: !settingsController.compactLyrics && root.count > 0
        model: lyrics.lines
        currentIndex: root.act
        preferredHighlightBegin: height / 2 - 60
        preferredHighlightEnd: height / 2 + 60
        highlightRangeMode: ListView.StrictlyEnforceRange
        delegate: Text {
            width: ListView.view.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: modelData.text
            color: index === root.active ? Theme.a1 : Qt.rgba(1, 1, 1, 0.4)
            font.pixelSize: index === root.active ? Theme.xxl : Theme.lg
            font.bold: index === root.active
            Behavior on font.pixelSize { NumberAnimation { duration: 150 } }
        }
    }

    // empty state
    Text {
        anchors.centerIn: parent
        visible: root.count === 0
        text: "No lyrics found"
        color: Qt.rgba(1, 1, 1, 0.4)
        font.pixelSize: Theme.xl
    }
}
