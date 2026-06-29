// qml/Search.qml — search field + results with TV-remote D-pad focus and a
// PLAY affordance on the focused row, matching .search / .results in styles.css.
import QtQuick
import QtQuick.Controls

Item {
    id: root
    // D-pad focus index into the results list (driven by main.qml's key handler)
    property int focusIdx: 0

    signal requestTopbar()    // Up from the search box -> exit to the tabs
    signal requestResults()   // Down from the search box -> move into the results
    signal songPlayed()       // played a result -> jump to Now Playing

    function focusInput() { input.forceActiveFocus() }

    function moveFocus(d) {
        var n = maClient.searchResults.length
        if (n === 0) return
        focusIdx = Math.max(0, Math.min(n - 1, focusIdx + d))
        results.positionViewAtIndex(focusIdx, ListView.Contain)
    }
    function play(uri) {
        maClient.playNow(uri)
        songPlayed()
    }
    function activate() {
        var r = maClient.searchResults[focusIdx]
        if (r) play(r.uri)
    }
    Connections {
        target: maClient
        function onSearchResultsChanged() { root.focusIdx = 0 }
    }

    // Land on Search ready to type.
    onVisibleChanged: if (visible) Qt.callLater(focusInput)

    // ── Search field (.search-field) ─────────────────────────────────────────
    Rectangle {
        id: field
        anchors { top: parent.top; topMargin: 148; left: parent.left; right: parent.right
                  leftMargin: 150; rightMargin: 150 }
        height: 92
        radius: 24
        color: Qt.rgba(1, 1, 1, 0.06)
        border.color: input.activeFocus ? Theme.a1 : Qt.rgba(1, 1, 1, 0.12)
        border.width: 2

        Row {
            anchors { fill: parent; leftMargin: 34; rightMargin: 34 }
            spacing: 26
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "🔍"; font.pixelSize: 38; color: Qt.rgba(1, 1, 1, 0.55)
            }
            TextField {
                id: input
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 70
                placeholderText: "Search songs, artists, albums"
                placeholderTextColor: Qt.rgba(1, 1, 1, 0.32)
                color: Theme.fg
                font.pixelSize: 44
                font.weight: Font.DemiBold
                background: Item {}
                onAccepted: maClient.search(text)
                // Up exits Search; Down dives into the results list.
                Keys.onUpPressed: function (e) { root.requestTopbar(); e.accepted = true }
                Keys.onDownPressed: function (e) { root.requestResults(); e.accepted = true }
            }
        }
    }

    // ── Results (.results) ───────────────────────────────────────────────────
    ListView {
        id: results
        anchors { top: field.bottom; topMargin: 36; left: field.left; right: field.right; bottom: parent.bottom }
        anchors.bottomMargin: 50
        clip: true
        spacing: 14
        model: maClient.searchResults

        delegate: Rectangle {
            width: results.width
            height: 144
            radius: 22
            property bool focused: index === root.focusIdx
            color: focused ? Qt.rgba(0, 224 / 255, 198 / 255, 0.22) : Qt.rgba(1, 1, 1, 0.04)
            border.color: focused ? Theme.a1 : Qt.rgba(1, 1, 1, 0.06)
            border.width: 2

            Rectangle {            // thumb
                id: rthumb
                anchors { left: parent.left; leftMargin: 28; verticalCenter: parent.verticalCenter }
                width: 104; height: 104; radius: 14
                color: Theme.panel
                clip: true
                Image { anchors.fill: parent; source: modelData.image || ""; fillMode: Image.PreserveAspectCrop }
            }
            Text {
                id: rtitle
                anchors { left: rthumb.right; leftMargin: 30; right: playAff.left; rightMargin: 24
                          bottom: parent.verticalCenter }
                text: modelData.title || ""
                color: Theme.fg
                font.pixelSize: 42
                font.weight: Font.ExtraBold
                elide: Text.ElideRight
            }
            Text {
                anchors { left: rthumb.right; leftMargin: 30; right: playAff.left; rightMargin: 24
                          top: parent.verticalCenter; topMargin: 6 }
                text: (modelData.artist || "") + (modelData.album ? "  ·  " + modelData.album : "")
                color: Qt.rgba(1, 1, 1, 0.55)
                font.pixelSize: 28
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Row {            // PLAY affordance (focused row only)
                id: playAff
                visible: parent.focused
                anchors { right: parent.right; rightMargin: 28; verticalCenter: parent.verticalCenter }
                spacing: 14
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "PLAY ▶"; color: Theme.a1; font.pixelSize: 24; font.weight: Font.Bold
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: { root.focusIdx = index; root.play(modelData.uri) }
            }
        }

        // empty state
        Text {
            anchors.centerIn: parent
            visible: results.count === 0
            text: "Type to search your library"
            color: Qt.rgba(1, 1, 1, 0.3)
            font.pixelSize: Theme.xl
        }
    }
}
