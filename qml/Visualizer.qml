// qml/Visualizer.qml — Canvas dispatches to three modes ported from bigscreen-jukebox/app.js.
// col1=#00e0c6 (Theme.a1), col2=#ff3da6 (Theme.a2). Falls back to 120-BPM simulation
// when audioAnalyzer.energy is ~0 (no audio capture yet).
import QtQuick
import QtQuick.Controls

Item {
    id: viz
    property string mode: "radial"
    property real vt: 0
    property real beatMul: 1.0                       // BEAT slider multiplier
    readonly property var modes: ["radial", "flow", "bars"]

    function cycleMode(d) {
        var i = modes.indexOf(mode)
        mode = modes[(i + d + modes.length) % modes.length]
    }

    // Source label: "Live feed" once the analyzer is receiving audio, else "Simulated".
    readonly property bool live: audioAnalyzer.energy > 0.001

    Rectangle { anchors.fill: parent; color: "#050507" }

    Canvas {
        id: canvas
        anchors.fill: parent
        // persistent per-frame state
        property var  beatRings: []
        property real spinAngle: 0
        property real prevBeat:  0

        function rgbaStr(r, g, b, a) {
            return "rgba(" + r + "," + g + "," + b + "," + a + ")"
        }
        // Interpolate between #00e0c6 and #ff3da6
        function lerpColRGB(t) {
            return {
                r: Math.round(0   + (255 - 0)   * t),
                g: Math.round(224 + (61  - 224) * t),
                b: Math.round(198 + (166 - 198) * t)
            }
        }

        // Return {energy, beat, level, bars[64]}, simulating 120-BPM when idle
        function getAudioData() {
            var energy = audioAnalyzer.energy
            var beat   = audioAnalyzer.beat
            var level  = audioAnalyzer.level
            var bars   = audioAnalyzer.bars

            if (energy < 0.001 || !bars || bars.length === 0) {
                var t      = viz.vt
                var period = 0.5                              // 60/120 BPM
                var phase  = (t % period) / period
                var kick   = Math.exp(-phase * 7)
                energy = 0.5 + 0.32 * Math.sin(t * 0.22) + 0.12 * Math.sin(t * 0.6 + 1)
                beat   = kick
                level  = Math.min(1.4, beat * (0.5 + energy * 0.6))
                var N  = 64
                bars   = new Array(N)
                for (var i = 0; i < N; i++) {
                    var f = i / N
                    var v = 0.18 + 0.82 * Math.abs(Math.sin(
                                i * 0.27 + t * 1.6 + Math.sin(i * 0.5 + t * 0.4)))
                    v *= (1 - f * 0.45) * (0.55 + energy * 0.55)
                    v += beat * 0.4 * Math.max(0, 1 - f * 1.5)
                    bars[i] = Math.max(0.02, Math.min(1.15, v))
                }
            }
            beat *= viz.beatMul
            level = Math.min(1.4, beat * (0.5 + energy * 0.6))
            return { energy: energy, beat: beat, level: level, bars: bars }
        }

        onPaint: {
            var ctx = getContext("2d")
            var a   = canvas.getAudioData()
            if      (viz.mode === "radial") canvas.drawRadial(ctx, canvas.width, canvas.height, a)
            else if (viz.mode === "flow")   canvas.drawFlow(ctx, canvas.width, canvas.height, a)
            else                            canvas.drawBars(ctx, canvas.width, canvas.height, a)
        }

        // ---- vizRadial ported from app.js ----
        function drawRadial(ctx, W, H, a) {
            ctx.fillStyle = "rgba(5,5,8,0.30)"
            ctx.fillRect(0, 0, W, H)
            var cx = W / 2, cy = H / 2
            canvas.spinAngle = canvas.spinAngle + (0.12 + a.energy * 1.3) * 0.016
            var spokes = 56
            ctx.save()
            ctx.translate(cx, cy)
            ctx.rotate(canvas.spinAngle)
            for (var i = 0; i < spokes; i++) {
                var ang = i / spokes * Math.PI * 2
                var len = 200 + a.energy * 170 + (i % 2 ? a.beat * 120 : 0)
                ctx.strokeStyle = rgbaStr(0, 224, 198, 0.045 + a.energy * 0.07)
                ctx.lineWidth = 2
                ctx.beginPath()
                ctx.moveTo(Math.cos(ang) * 120, Math.sin(ang) * 120)
                ctx.lineTo(Math.cos(ang) * (120 + len), Math.sin(ang) * (120 + len))
                ctx.stroke()
            }
            ctx.restore()

            // expanding rings on detected beat
            if (a.beat > 0.55 && canvas.prevBeat <= 0.55) {
                var newRings = canvas.beatRings.slice()
                newRings.push({ r: 130, a: 1.0 })
                canvas.beatRings = newRings
            }
            canvas.prevBeat = a.beat

            var updatedRings = []
            for (var ri = 0; ri < canvas.beatRings.length; ri++) {
                var R = {
                    r: canvas.beatRings[ri].r + 0.016 * 820,
                    a: canvas.beatRings[ri].a - 0.016 * 1.5
                }
                if (R.a <= 0) continue
                var rc = lerpColRGB(Math.min(1, (R.r - 130) / 560))
                ctx.strokeStyle = rgbaStr(rc.r, rc.g, rc.b, R.a * 0.6)
                ctx.lineWidth = 6 + R.a * 12
                ctx.beginPath()
                ctx.arc(cx, cy, R.r, 0, Math.PI * 2)
                ctx.stroke()
                updatedRings.push(R)
            }
            canvas.beatRings = updatedRings

            // center orb
            var orbR = 130 + a.level * 120
            var grd  = ctx.createRadialGradient(cx, cy, 0, cx, cy, orbR * 1.7)
            grd.addColorStop(0,   rgbaStr(255, 61,  166, 0.95))
            grd.addColorStop(0.4, rgbaStr(0,   224, 198, 0.78))
            grd.addColorStop(1,   "rgba(0,0,0,0)")
            ctx.fillStyle = grd
            ctx.beginPath(); ctx.arc(cx, cy, orbR * 1.7, 0, Math.PI * 2); ctx.fill()
            ctx.fillStyle = "rgba(255,255,255,0.92)"
            ctx.beginPath(); ctx.arc(cx, cy, orbR * 0.32, 0, Math.PI * 2); ctx.fill()
        }

        // ---- vizFlow ported from app.js ----
        function drawFlow(ctx, W, H, a) {
            ctx.fillStyle = "rgba(5,5,8,0.20)"
            ctx.fillRect(0, 0, W, H)
            var lines = 5
            for (var L = 0; L < lines; L++) {
                var t     = viz.vt * 1.2 + L * 1.4
                var amp   = 70 + a.level * 270 * (1 - L * 0.12) + a.energy * 40
                var yBase = H / 2 + (L - 2) * 72
                var col   = lerpColRGB(L / (lines - 1))
                ctx.beginPath()
                for (var x = 0; x <= W; x += 10) {
                    var k = x / W
                    var y = yBase
                            + Math.sin(k * 6.5 + t) * amp * Math.sin(k * Math.PI)
                            + Math.sin(k * 15   + t * 1.7) * amp * 0.22
                    if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                }
                ctx.strokeStyle = rgbaStr(col.r, col.g, col.b, 0.92)
                ctx.lineWidth   = 4 + a.level * 5
                ctx.shadowColor = rgbaStr(col.r, col.g, col.b, 1)
                ctx.shadowBlur  = 24 + a.level * 34
                ctx.stroke()
            }
            ctx.shadowBlur = 0
        }

        // ---- vizBars ported from app.js (uses a.bars length-64) ----
        function drawBars(ctx, W, H, a) {
            ctx.fillStyle = "#050507"
            ctx.fillRect(0, 0, W, H)
            var bars = a.bars, N = bars.length
            if (N === 0) return
            var bw = W / N, gap = 7, baseY = H * 0.80
            for (var i = 0; i < N; i++) {
                var v = bars[i], h = v * H * 0.6, x = i * bw
                if (h < 1) continue
                var col = lerpColRGB(i / (N - 1))
                var grd = ctx.createLinearGradient(0, baseY - h, 0, baseY)
                grd.addColorStop(0, rgbaStr(col.r, col.g, col.b, 1))
                grd.addColorStop(1, rgbaStr(0, 224, 198, 0.18))
                ctx.fillStyle = grd
                roundRect(ctx, x + gap / 2, baseY - h, bw - gap, h, 6)
                ctx.fill()
                ctx.globalAlpha = 0.13
                ctx.fillStyle   = rgbaStr(col.r, col.g, col.b, 1)
                roundRect(ctx, x + gap / 2, baseY + 8, bw - gap, h * 0.32, 4)
                ctx.fill()
                ctx.globalAlpha = 1
            }
        }

        function roundRect(ctx, x, y, w, h, r) {
            if (h <= 0 || w <= 0) return
            r = Math.min(r, w / 2, h / 2)
            ctx.beginPath()
            ctx.moveTo(x + r, y)
            ctx.arcTo(x + w, y,     x + w, y + h, r)
            ctx.arcTo(x + w, y + h, x,     y + h, r)
            ctx.arcTo(x,     y + h, x,     y,     r)
            ctx.arcTo(x,     y,     x + w, y,     r)
            ctx.closePath()
        }
    }

    // ~60 fps repaint loop — only runs while the Visualizer tab is visible
    Timer {
        interval: 16
        running: viz.visible
        repeat: true
        onTriggered: { viz.vt += 0.016; canvas.requestPaint() }
    }

    // beat control — match .beat-ctrl (BEAT slider + source toggle), top-left
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
                    id: beatSlider
                    anchors.verticalCenter: parent.verticalCenter
                    width: 210
                    from: 0; to: 2.4; stepSize: 0.05; value: 1
                    onValueChanged: viz.beatMul = value
                }
            }
        }

        Rectangle {            // .source-btn
            height: 60
            width: sourceRow.implicitWidth + 48
            radius: 40
            color: viz.live ? Qt.rgba(0, 224 / 255, 198 / 255, 0.12) : Qt.rgba(10 / 255, 10 / 255, 16 / 255, 0.5)
            border.color: viz.live ? Theme.a1 : Qt.rgba(1, 1, 1, 0.1)
            border.width: 1
            Row {
                id: sourceRow
                anchors.centerIn: parent
                spacing: 12
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 11; height: 11; radius: 6
                    color: viz.live ? Theme.a1 : Qt.rgba(1, 1, 1, 0.4)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: viz.live ? "Live feed" : "Simulated"
                    font.pixelSize: 21; font.weight: Font.Bold
                    color: viz.live ? Theme.a1 : Qt.rgba(1, 1, 1, 0.7)
                }
            }
        }
    }

    // mode bar — match .mode-bar in styles.css
    Rectangle {
        id: modeBarBg
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 48
        height: 72
        width: modeRow.implicitWidth + 24
        radius: 50
        color: Qt.rgba(10/255, 10/255, 16/255, 0.55)
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
                    property bool isActive: viz.mode === modeKey
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
                    MouseArea { anchors.fill: parent; onClicked: viz.mode = modeKey }
                }
            }
        }
    }

    // track name bottom-left — match prototype's bottom track label on visualizer screen
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
