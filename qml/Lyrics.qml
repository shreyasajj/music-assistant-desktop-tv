// qml/Lyrics.qml — karaoke lyrics. Two layouts (option: settingsController.compactLyrics):
//   compact  — only the previous line, the active line, and the next two lines
//   full     — the whole lyric sheet scrolling through a centered highlight
// Optionally renders the visualizer behind the text (settingsController.vizBehindLyrics).
import QtQuick
import QtQuick.Controls

Item {
    id: root
    property var lyrics: JSON.parse(maClient.lyricsJson)
    property int active: activeLineIndex(maClient.positionMs)
    property var win: windowLines()
    readonly property int count: (lyrics.lines ? lyrics.lines.length : 0)
    // clamp so the first line reads as "active" before the first timestamp passes
    readonly property int act: Math.max(0, active)

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
    // {above, center, below1, below2} for the compact window. Inserts a 🎵 filler
    // during the intro and long instrumental gaps so the screen isn't blank.
    function windowLines() {
        var L = lyrics.lines || []
        var n = L.length
        if (n === 0) return { above: "", center: "", below1: "", below2: "" }
        var pos = maClient.positionMs
        var a = active
        var MUSIC = "🎵"
        if (a < 0) {                       // before the first line (intro)
            if (L[0].time_ms !== null && L[0].time_ms > 2000 && pos < L[0].time_ms - 1200)
                return { above: "", center: MUSIC, below1: L[0].text, below2: (n > 1 ? L[1].text : "") }
            return { above: "", center: L[0].text, below1: (n > 1 ? L[1].text : ""), below2: (n > 2 ? L[2].text : "") }
        }
        if (a + 1 < n && L[a].time_ms !== null && L[a + 1].time_ms !== null) {
            var gap = L[a + 1].time_ms - L[a].time_ms      // instrumental break
            if (gap > 8000 && (pos - L[a].time_ms) > 5000 && (L[a + 1].time_ms - pos) > 1500)
                return { above: L[a].text, center: MUSIC, below1: L[a + 1].text, below2: (a + 2 < n ? L[a + 2].text : "") }
        }
        return { above: (a - 1 >= 0 ? L[a - 1].text : ""),
                 center: (a < n ? L[a].text : ""),
                 below1: (a + 1 < n ? L[a + 1].text : ""),
                 below2: (a + 2 < n ? L[a + 2].text : "") }
    }

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
            text: root.win.center
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
            text: root.win.above
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
            text: root.win.below1
            color: Qt.rgba(1, 1, 1, 0.5)
            font.pixelSize: 48
            font.weight: Font.Bold
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; top: aNext1.bottom; topMargin: 24 }
            width: parent.width - 520
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.win.below2
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

    // empty state — make it obvious it's just instrumental, not a load failure
    Column {
        anchors.centerIn: parent
        visible: root.count === 0
        spacing: 16
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "🎵"
            font.pixelSize: 150
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Just the music — no lyrics"
            color: Qt.rgba(1, 1, 1, 0.5)
            font.pixelSize: Theme.xl
            font.weight: Font.DemiBold
        }
    }
}
