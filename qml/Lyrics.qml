// qml/Lyrics.qml
import QtQuick
import QtQuick.Controls

Item {
    property var lyrics: JSON.parse(maClient.lyricsJson)
    Connections { target: maClient; function onLyricsJsonChanged() { lyrics = JSON.parse(maClient.lyricsJson) } }

    function activeLineIndex(posMs) {
        if (!lyrics.synced) return -1
        var idx = -1
        for (var i = 0; i < lyrics.lines.length; i++) {
            if (lyrics.lines[i].time_ms !== null && lyrics.lines[i].time_ms <= posMs) idx = i
            else break
        }
        return idx
    }

    ListView {
        id: list
        anchors.fill: parent
        model: lyrics.lines
        property int active: activeLineIndex(maClient.positionMs)
        Connections { target: maClient; function onPositionMsChanged() { var idx = activeLineIndex(maClient.positionMs); list.active = idx; list.currentIndex = idx } }
        preferredHighlightBegin: height / 2 - 60
        preferredHighlightEnd: height / 2 + 60
        highlightRangeMode: ListView.StrictlyEnforceRange
        delegate: Text {
            width: ListView.view.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: modelData.text
            color: index === list.active ? Theme.a1 : Theme.muted
            font.pixelSize: index === list.active ? Theme.xxl : Theme.lg
            font.bold: index === list.active
            Behavior on font.pixelSize { NumberAnimation { duration: 150 } }
        }
        Text {
            anchors.centerIn: parent; visible: lyrics.lines.length === 0
            text: "No lyrics found"; color: Theme.muted; font.pixelSize: Theme.xl
        }
    }
}
