// qml/Lyrics.qml — karaoke lyrics (option: settingsController.compactLyrics):
//   compact  — a smooth-scrolling window: lines slide up to center the active one,
//              growing/fading as they reach the middle (like the web prototype)
//   full     — the whole lyric sheet scrolling through a centered highlight
// Optionally renders the visualizer behind the text (settingsController.vizBehindLyrics).
import QtQuick
import QtQuick.Controls

Item {
    id: root
    property var lyrics: JSON.parse(maClient.lyricsJson)
    property int active: activeLineIndex(maClient.positionMs)
    readonly property int count: (lyrics.lines ? lyrics.lines.length : 0)
    // clamp so the first line reads as "active" before the first timestamp passes
    readonly property int act: Math.max(0, active)
    // before the first timestamped line there is nothing to highlight yet
    readonly property bool intro: active < 0 && count > 0

    function activeLineIndex(posMs) {
        if (!lyrics.synced || !lyrics.lines) return -1
        var idx = -1
        for (var i = 0; i < lyrics.lines.length; i++) {
            if (lyrics.lines[i].time_ms !== null && lyrics.lines[i].time_ms <= posMs) idx = i
            else break
        }
        return idx
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

    // ── Compact: smooth-scrolling karaoke window ──────────────────────────────
    Item {
        id: compact
        anchors.fill: parent
        clip: true
        visible: settingsController.compactLyrics && root.count > 0

        readonly property int step: 124          // vertical spacing between lines
        // scroll so the active line sits at the vertical centre (-1 during the intro)
        readonly property real scrollPos: root.active

        function lineOpacity(d) {
            var ad = Math.abs(d)
            return ad === 0 ? 1.0 : ad === 1 ? 0.5 : ad === 2 ? 0.28 : ad === 3 ? 0.12 : 0.0
        }

        Item {
            id: mover
            width: parent.width
            y: parent.height / 2 - compact.scrollPos * compact.step - compact.step / 2
            Behavior on y { NumberAnimation { duration: 480; easing.type: Easing.OutCubic } }

            Repeater {
                model: lyrics.lines
                delegate: Text {
                    x: 200
                    width: compact.width - 400
                    y: index * compact.step
                    height: compact.step
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                    text: modelData.text
                    property int d: index - root.active
                    property bool isActive: d === 0 && !root.intro
                    color: isActive ? Theme.a1 : Qt.rgba(1, 1, 1, 1)
                    opacity: compact.lineOpacity(d)
                    font.pixelSize: isActive ? 92 : (Math.abs(d) === 1 ? 48 : 42)
                    font.weight: isActive ? Font.ExtraBold : Font.Bold
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                    Behavior on font.pixelSize { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                }
            }
        }

        // music note shown during the intro (before the first line), fades out
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            text: "🎵"
            font.pixelSize: 96
            opacity: root.intro ? 0.9 : 0.0
            Behavior on opacity { NumberAnimation { duration: 350 } }
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
        highlightMoveDuration: 400
        highlightMoveVelocity: -1
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
