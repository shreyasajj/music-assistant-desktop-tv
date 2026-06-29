// qml/NowPlaying.qml
// Now Playing screen — centered layout matching the bigscreen-jukebox prototype.
// Layout:
//   - Full-screen blurred art background with gradient overlay
//   - Centered album art 560x560 at top:150px
//   - Lower panel (width 1180px, centered, bottom:50px): title/artist/album,
//     progress bar, transport controls, volume, player picker

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    // true while guest mode is on — drops the queue below the corner QR card
    property bool guestOn: false

    // ── Background: blurred art + gradient overlay ──────────────────────────
    // QML doesn't have a built-in blur without Qt5Compat or QtGraphicalEffects;
    // we fake depth-of-field blur with an overscaled, low-opacity image —
    // acceptable at TV viewing distance and avoids extra runtime dependencies.
    Image {
        id: bgBlurImage
        anchors {
            fill: parent
            margins: -100
        }
        source: maClient.artUrl
        fillMode: Image.PreserveAspectCrop
        smooth: true
        opacity: 0.45
        transform: Scale {
            xScale: 1.25; yScale: 1.25
            origin.x: bgBlurImage.width / 2
            origin.y: bgBlurImage.height / 2
        }
    }

    // Gradient overlay  (.np-overlay)
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.00; color: Qt.rgba(0.027, 0.027, 0.043, 0.35) }
            GradientStop { position: 0.38; color: Qt.rgba(0.027, 0.027, 0.043, 0.42) }
            GradientStop { position: 0.70; color: Qt.rgba(0.027, 0.027, 0.043, 0.80) }
            GradientStop { position: 1.00; color: Qt.rgba(0.027, 0.027, 0.043, 0.98) }
        }
    }

    // ── Album art (.np-art-wrap / .np-art) ──────────────────────────────────
    Item {
        // .np-art-wrap: position absolute, top:150px, centered horizontally
        anchors {
            top: parent.top
            topMargin: 150
            horizontalCenter: parent.horizontalCenter
        }
        width: 560
        height: 560

        Rectangle {
            id: artFrame
            anchors.fill: parent
            radius: 28
            color: Theme.panel
            clip: true

            Image {
                id: artImage
                anchors.fill: parent
                source: maClient.artUrl
                fillMode: Image.PreserveAspectCrop
                smooth: true
            }

            // Subtle inset border (.np-art box-shadow: inset 0 0 0 1px rgba(255,255,255,.07))
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.07)
                border.width: 1
            }
        }
    }

    // ── Lower panel (.np-lower) ──────────────────────────────────────────────
    // position: absolute; left:50%; transform:translateX(-50%); bottom:50px; width:1180px
    Item {
        id: lowerPanel
        width: 1180
        anchors {
            bottom: parent.bottom
            bottomMargin: 50
            horizontalCenter: parent.horizontalCenter
        }
        // height is determined by child column
        height: lowerColumn.implicitHeight

        ColumnLayout {
            id: lowerColumn
            width: parent.width
            spacing: 0

            // Title (.np-title: 84px, weight 800)
            Text {
                Layout.fillWidth: true
                text: maClient.trackTitle !== "" ? maClient.trackTitle : "Nothing playing"
                color: Theme.fg
                font.pixelSize: Theme.xxl   // 84
                font.weight: Font.ExtraBold
                font.letterSpacing: -1.5
                lineHeight: 1
                elide: Text.ElideRight
            }

            // Artist + Album (.np-sub: 38px, color rgba(255,255,255,.62))
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 12
                text: {
                    if (maClient.trackArtist !== "" && maClient.trackAlbum !== "")
                        return maClient.trackArtist + "  ·  " + maClient.trackAlbum
                    else if (maClient.trackArtist !== "")
                        return maClient.trackArtist
                    else if (maClient.trackAlbum !== "")
                        return maClient.trackAlbum
                    return ""
                }
                color: Qt.rgba(1, 1, 1, 0.62)
                font.pixelSize: 38
                font.weight: Font.Medium
                elide: Text.ElideRight
                visible: text !== ""
            }

            // ── Progress bar (.progress) ────────────────────────────────────
            // margin-top: 36px; track height: 8px; fill gradient a1→a2
            Item {
                Layout.fillWidth: true
                Layout.topMargin: 36
                height: 36   // enough room for track + time labels

                // Elapsed time label
                Text {
                    id: timeLeft
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: formatMs(maClient.positionMs)
                    color: Qt.rgba(1, 1, 1, 0.72)
                    font.pixelSize: 28
                    width: 90
                }

                // Track background
                Rectangle {
                    id: progressTrack
                    anchors {
                        left: timeLeft.right; leftMargin: 24
                        right: timeRight.left; rightMargin: 24
                        verticalCenter: parent.verticalCenter
                    }
                    height: 8
                    radius: 6
                    color: Qt.rgba(1, 1, 1, 0.16)
                    clip: true

                    // Fill gradient a1→a2
                    Rectangle {
                        width: maClient.durationMs > 0
                               ? Math.max(0, Math.min(1, maClient.positionMs / maClient.durationMs)) * parent.width
                               : 0
                        height: parent.height
                        radius: parent.radius
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Theme.a1 }
                            GradientStop { position: 1; color: Theme.a2 }
                        }
                    }

                    // Clickable seek area
                    MouseArea {
                        anchors.fill: parent
                        onClicked: function(mouse) {
                            if (maClient.durationMs > 0) {
                                var ratio = mouse.x / progressTrack.width
                                maClient.seek(Math.round(ratio * maClient.durationMs))
                            }
                        }
                    }
                }

                // Duration label
                Text {
                    id: timeRight
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: formatMs(maClient.durationMs)
                    color: Qt.rgba(1, 1, 1, 0.72)
                    font.pixelSize: 28
                    width: 90
                    horizontalAlignment: Text.AlignRight
                }
            }

            // ── Transport controls (.transport) ─────────────────────────────
            // margin-top: 34px; grid: 1fr auto 1fr; center group has gap:48px
            Item {
                Layout.fillWidth: true
                Layout.topMargin: 34
                height: 116   // play button height

                // Left side: (empty for now — prototype had shuffle/repeat, Task 17 scope)
                Item {
                    id: transportLeft
                    width: parent.width / 3
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                }

                // Center group (.transport-mid): Prev | Play/Pause | Next
                Row {
                    anchors.centerIn: parent
                    spacing: 48

                    // Previous button
                    Item {
                        width: 54; height: 54
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: "⏮"
                            font.pixelSize: 54
                            color: Qt.rgba(1, 1, 1, 0.9)
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { try { maClient.previous() } catch(e) {} }
                        }
                    }

                    // Play/Pause button (116x116 circle, gradient fill)
                    Rectangle {
                        width: 116; height: 116
                        radius: 58
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Theme.a1 }
                            GradientStop { position: 1; color: Theme.a2 }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: maClient.isPlaying ? "⏸" : "▶"
                            font.pixelSize: 46
                            color: "#06121a"
                            leftPadding: maClient.isPlaying ? 0 : 4   // optical centering for play icon
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { try { maClient.playPause() } catch(e) {} }
                        }
                    }

                    // Next button
                    Item {
                        width: 54; height: 54
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: "⏭"
                            font.pixelSize: 54
                            color: Qt.rgba(1, 1, 1, 0.9)
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { try { maClient.next() } catch(e) {} }
                        }
                    }
                }

                // Right side: Volume control (.volume: width 170px track)
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 16

                    Text {
                        text: "🔊"
                        font.pixelSize: 30
                        color: Qt.rgba(1, 1, 1, 0.7)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // Volume track (170px wide, 8px tall, gradient fill)
                    Item {
                        id: volumeTrackItem
                        width: 170; height: 36
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            id: volumeTrack
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: 8
                            radius: 6
                            color: Qt.rgba(1, 1, 1, 0.16)

                            Rectangle {
                                width: Math.max(0, Math.min(1, maClient.volume / 100)) * parent.width
                                height: parent.height
                                radius: parent.radius
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: Theme.a1 }
                                    GradientStop { position: 1; color: Theme.a2 }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: function(mouse) {
                                    var ratio = mouse.x / volumeTrack.width
                                    try { maClient.setVolume(Math.round(ratio * 100)) } catch(e) {}
                                }
                            }
                        }
                    }
                }
            }

        }
    }

    // ── Up Next queue (.queue) ───────────────────────────────────────────────
    // top:124 right:48; drops below the corner QR card in guest mode.
    UpNextQueue {
        guestOn: root.guestOn
        anchors {
            top: parent.top
            topMargin: root.guestOn ? 336 : 124   // 124 + 212 QR-card clearance
            right: parent.right
            rightMargin: 48
        }
        Behavior on anchors.topMargin { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────
    function formatMs(ms) {
        if (ms <= 0) return "0:00"
        var totalSec = Math.floor(ms / 1000)
        var m = Math.floor(totalSec / 60)
        var s = totalSec % 60
        return m + ":" + (s < 10 ? "0" + s : s)
    }
}
