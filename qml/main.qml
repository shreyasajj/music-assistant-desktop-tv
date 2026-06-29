// qml/main.qml — app shell faithful to bigscreen-jukebox/ prototype.
// Authored at a fixed 1920x1080 stage and scaled to fill any screen (4K-ready),
// matching the prototype's fitToViewport(). Topbar = wordmark + centered tabs +
// player chip (Now Playing only) + guest button / corner QR card.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: win
    visible: true
    visibility: Window.FullScreen
    color: Theme.bg

    readonly property var tabs: ["Now Playing", "Search", "Lyrics", "Visualizer", "Settings"]
    readonly property int guestIdx: tabs.length            // topbar focus index of the guest button
    property bool guestOn: guestController.enabled

    // ── 1920x1080 stage, scaled & centered to the window (4K scaling) ──────────
    Item {
        id: stage
        width: 1920
        height: 1080
        property real s: Math.min(win.width / 1920, win.height / 1080)
        transform: [
            Scale { xScale: stage.s; yScale: stage.s },
            Translate { x: (win.width - 1920 * stage.s) / 2; y: (win.height - 1080 * stage.s) / 2 }
        ]

        focus: true
        // focusZone: "content" | "topbar";  topIdx: 0..tabs-1 = tabs, guestIdx = guest button
        property string focusZone: "content"
        property int topIdx: 0
        property bool playerMenuOpen: false

        function go(i) {
            stack.currentIndex = i
            focusZone = "content"
            playerMenuOpen = false
            if (i === 1) Qt.callLater(searchScreen.focusInput)   // type immediately on Search
            else stage.forceActiveFocus()
        }
        function enterTopbar() {
            focusZone = "topbar"
            topIdx = stack.currentIndex
            playerMenuOpen = false
            stage.forceActiveFocus()
        }
        function activateTop() {
            if (topIdx === win.guestIdx) guestController.toggle()
            else go(topIdx)
        }

        // ── Keyboard / TV-remote D-pad ─────────────────────────────────────────
        Keys.onPressed: function (e) {
            if (e.key === Qt.Key_G) { guestController.toggle(); e.accepted = true; return }
            if (e.key >= Qt.Key_1 && e.key <= Qt.Key_5) { go(e.key - Qt.Key_1); e.accepted = true; return }

            if (stage.focusZone === "topbar") {
                if (e.key === Qt.Key_Left)  { stage.topIdx = Math.max(0, stage.topIdx - 1); e.accepted = true }
                else if (e.key === Qt.Key_Right) { stage.topIdx = Math.min(win.guestIdx, stage.topIdx + 1); e.accepted = true }
                else if (e.key === Qt.Key_Down)  { stage.focusZone = "content"; e.accepted = true }
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { stage.activateTop(); e.accepted = true }
                return
            }

            // content zone (reached when the stage holds focus, i.e. not typing in Search)
            if (e.key === Qt.Key_Up) {
                if (stack.currentIndex === 1) {
                    if (searchScreen.focusIdx > 0) searchScreen.moveFocus(-1)
                    else searchScreen.focusInput()     // top of results -> back to the search box
                } else {
                    stage.enterTopbar()
                }
                e.accepted = true; return
            }
            if (e.key === Qt.Key_Space) { maClient.playPause(); e.accepted = true; return }

            if (stack.currentIndex === 0) {            // Now Playing
                if (e.key === Qt.Key_Right) { maClient.next(); e.accepted = true }
                else if (e.key === Qt.Key_Left) { maClient.previous(); e.accepted = true }
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { maClient.playPause(); e.accepted = true }
            } else if (stack.currentIndex === 1) {     // Search results
                if (e.key === Qt.Key_Down) { searchScreen.moveFocus(1); e.accepted = true }
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { searchScreen.activate(); e.accepted = true }
            } else if (stack.currentIndex === 2) {     // Lyrics — arrows toggle viz behind lyrics
                if (e.key === Qt.Key_Right) { settingsController.setVizBehindLyrics(true); e.accepted = true }
                else if (e.key === Qt.Key_Left) { settingsController.setVizBehindLyrics(false); e.accepted = true }
            } else if (stack.currentIndex === 3) {     // Visualizer
                if (e.key === Qt.Key_Right) { vizScreen.cycleMode(1); e.accepted = true }
                else if (e.key === Qt.Key_Left) { vizScreen.cycleMode(-1); e.accepted = true }
            }
        }

        // ── Screens ────────────────────────────────────────────────────────────
        StackLayout {
            id: stack
            anchors.fill: parent
            currentIndex: 0
            NowPlaying { guestOn: win.guestOn }
            Search {
                id: searchScreen
                onRequestTopbar: stage.enterTopbar()
                onRequestResults: { stage.forceActiveFocus(); searchScreen.focusIdx = 0 }
            }
            Lyrics { }
            Visualizer { id: vizScreen }
            SettingsView { }
        }

        // ── Top bar ──────────────────────────────────────────────────────────────
        TopBar {
            id: topbar
            anchors { top: parent.top; left: parent.left; right: parent.right }
            z: 60
            currentIndex: stack.currentIndex
            focusZone: stage.focusZone
            topIdx: stage.topIdx
            tabs: win.tabs
            guestIdx: win.guestIdx
            guestOn: win.guestOn
            playerName: stage.activePlayerName()
            onTabActivated: function (index) { stage.go(index) }
            onChipClicked: stage.playerMenuOpen = !stage.playerMenuOpen
            onGuestClicked: guestController.toggle()
        }

        // Player dropdown menu (Now Playing) — overlays under the chip
        PlayerMenu {
            id: playerMenu
            z: 80
            open: stage.playerMenuOpen && stack.currentIndex === 0
            guestOn: win.guestOn
            anchors { top: topbar.bottom; topMargin: -8; right: parent.right; rightMargin: 64 }
            onRequestClose: stage.playerMenuOpen = false
        }

        // ── Guest corner QR card (replaces the guest button when on) ──────────────
        GuestOverlay {
            id: qrCard
            anchors { top: parent.top; right: parent.right; topMargin: 20; rightMargin: 48 }
            z: 70
            focused: stage.focusZone === "topbar" && stage.topIdx === win.guestIdx
        }

        function activePlayerName() {
            var ps = maClient.players
            for (var i = 0; i < ps.length; i++)
                if (ps[i].id === maClient.activePlayerId) return ps[i].name || ps[i].id
            return ps.length > 0 ? (ps[0].name || ps[0].id) : "No player"
        }
    }
}
