// qml/VizCanvas.qml — the visualizer drawing engine (radial / flow / bars),
// ported from bigscreen-jukebox/app.js. Reusable so it can render full-screen on
// the Visualizer tab and dimmed behind the Lyrics tab. Reads VizState.mode /
// VizState.beatMul and the live audioAnalyzer; simulates 120-BPM when idle.
import QtQuick

Item {
    id: viz
    property real vt: 0
    property string mode: VizState.mode
    property real beatMul: VizState.beatMul
    // When true, paint a translucent backdrop so text on top stays readable.
    property bool dim: false
    // Palette as [r,g,b]; defaults to the teal->magenta accents. Override (e.g.
    // behind lyrics) so the visualizer doesn't blend with the teal active line.
    property var c1: [0, 224, 198]
    property var c2: [255, 61, 166]

    Canvas {
        id: canvas
        anchors.fill: parent
        property var  beatRings: []
        property real spinAngle: 0
        property real prevBeat:  0
        // random-beat simulation state
        property real simNextBeat: 0
        property real simLastKick: -10

        function rgbaStr(r, g, b, a) { return "rgba(" + r + "," + g + "," + b + "," + a + ")" }
        function lerpColRGB(t) {
            var a = viz.c1, b = viz.c2
            return { r: Math.round(a[0] + (b[0] - a[0]) * t),
                     g: Math.round(a[1] + (b[1] - a[1]) * t),
                     b: Math.round(a[2] + (b[2] - a[2]) * t) }
        }

        function flatBars() {
            var b = new Array(64); for (var i = 0; i < 64; i++) b[i] = 0.0; return b
        }

        // Simulated source: hit at random intervals (not a steady BPM).
        function simulate(t) {
            if (t >= canvas.simNextBeat) {
                canvas.simLastKick = t
                canvas.simNextBeat = t + (0.28 + Math.random() * 0.55)   // 0.28..0.83s
            }
            var since = t - canvas.simLastKick
            var kick = Math.exp(-since * 7)
            var energy = Math.max(0.12, 0.45 + 0.3 * Math.sin(t * 0.3) + 0.12 * Math.sin(t * 0.7 + 1))
            var beat = kick * viz.beatMul
            var bass = kick * 0.8 + 0.08
            var level = Math.min(1.4, (beat * 0.6 + bass * 0.9) * (0.6 + energy * 0.5))
            var N = 64, bars = new Array(N)
            for (var i = 0; i < N; i++) {
                var f = i / N
                var v = 0.18 + 0.82 * Math.abs(Math.sin(i * 0.27 + t * 1.6 + Math.sin(i * 0.5 + t * 0.4)))
                v *= (1 - f * 0.45) * (0.55 + energy * 0.55)
                v += beat * 0.4 * Math.max(0, 1 - f * 1.5)
                bars[i] = Math.max(0.02, Math.min(1.15, v))
            }
            return { energy: energy, beat: beat, level: level, bars: bars }
        }

        function getAudioData() {
            // No capture device chosen -> animate random beats.
            if (audioAnalyzer.simulated)
                return canvas.simulate(viz.vt)
            // Live capture: react to the song's beat + bass; stay idle when silent.
            var energy = audioAnalyzer.energy
            var bass   = audioAnalyzer.bass
            var beat   = audioAnalyzer.beat * viz.beatMul
            var bars   = audioAnalyzer.bars
            if (energy < 0.004 && bass < 0.03)
                return { energy: 0, beat: 0, level: 0, bars: canvas.flatBars() }
            var level = Math.min(1.4, (beat * 0.6 + bass * 0.9) * (0.6 + energy * 0.5))
            return { energy: energy, beat: beat, level: level,
                     bars: (bars && bars.length ? bars : canvas.flatBars()) }
        }

        onPaint: {
            var ctx = getContext("2d")
            var a = canvas.getAudioData()
            if      (viz.mode === "radial") canvas.drawRadial(ctx, canvas.width, canvas.height, a)
            else if (viz.mode === "flow")   canvas.drawFlow(ctx, canvas.width, canvas.height, a)
            else                            canvas.drawBars(ctx, canvas.width, canvas.height, a)
        }

        function drawRadial(ctx, W, H, a) {
            ctx.fillStyle = viz.dim ? "rgba(5,5,8,0.42)" : "rgba(5,5,8,0.30)"
            ctx.fillRect(0, 0, W, H)
            var cx = W / 2, cy = H / 2
            canvas.spinAngle = canvas.spinAngle + (0.12 + a.energy * 1.3) * 0.016
            var spokes = 56
            ctx.save(); ctx.translate(cx, cy); ctx.rotate(canvas.spinAngle)
            for (var i = 0; i < spokes; i++) {
                var ang = i / spokes * Math.PI * 2
                var len = 200 + a.energy * 170 + (i % 2 ? a.beat * 120 : 0)
                ctx.strokeStyle = rgbaStr(viz.c1[0], viz.c1[1], viz.c1[2], 0.045 + a.energy * 0.07)
                ctx.lineWidth = 2
                ctx.beginPath()
                ctx.moveTo(Math.cos(ang) * 120, Math.sin(ang) * 120)
                ctx.lineTo(Math.cos(ang) * (120 + len), Math.sin(ang) * (120 + len))
                ctx.stroke()
            }
            ctx.restore()
            if (a.beat > 0.55 && canvas.prevBeat <= 0.55) {
                var nr = canvas.beatRings.slice(); nr.push({ r: 130, a: 1.0 }); canvas.beatRings = nr
            }
            canvas.prevBeat = a.beat
            var upd = []
            for (var ri = 0; ri < canvas.beatRings.length; ri++) {
                var R = { r: canvas.beatRings[ri].r + 0.016 * 820, a: canvas.beatRings[ri].a - 0.016 * 1.5 }
                if (R.a <= 0) continue
                var rc = lerpColRGB(Math.min(1, (R.r - 130) / 560))
                ctx.strokeStyle = rgbaStr(rc.r, rc.g, rc.b, R.a * 0.6)
                ctx.lineWidth = 6 + R.a * 12
                ctx.beginPath(); ctx.arc(cx, cy, R.r, 0, Math.PI * 2); ctx.stroke()
                upd.push(R)
            }
            canvas.beatRings = upd
            var orbR = 130 + a.level * 120
            var grd = ctx.createRadialGradient(cx, cy, 0, cx, cy, orbR * 1.7)
            grd.addColorStop(0, rgbaStr(viz.c2[0], viz.c2[1], viz.c2[2], 0.95))
            grd.addColorStop(0.4, rgbaStr(viz.c1[0], viz.c1[1], viz.c1[2], 0.78))
            grd.addColorStop(1, "rgba(0,0,0,0)")
            ctx.fillStyle = grd
            ctx.beginPath(); ctx.arc(cx, cy, orbR * 1.7, 0, Math.PI * 2); ctx.fill()
            // The bright white center dot is distracting behind centered lyrics — skip it when dimmed.
            if (!viz.dim) {
                ctx.fillStyle = "rgba(255,255,255,0.92)"
                ctx.beginPath(); ctx.arc(cx, cy, orbR * 0.32, 0, Math.PI * 2); ctx.fill()
            }
        }

        function drawFlow(ctx, W, H, a) {
            ctx.fillStyle = viz.dim ? "rgba(5,5,8,0.32)" : "rgba(5,5,8,0.20)"
            ctx.fillRect(0, 0, W, H)
            var lines = 5
            for (var L = 0; L < lines; L++) {
                var t = viz.vt * 1.2 + L * 1.4
                var amp = 70 + a.level * 270 * (1 - L * 0.12) + a.energy * 40
                var yBase = H / 2 + (L - 2) * 72
                var col = lerpColRGB(L / (lines - 1))
                ctx.beginPath()
                for (var x = 0; x <= W; x += 10) {
                    var k = x / W
                    var y = yBase + Math.sin(k * 6.5 + t) * amp * Math.sin(k * Math.PI)
                                  + Math.sin(k * 15 + t * 1.7) * amp * 0.22
                    if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                }
                // Glow via layered strokes — shadowBlur is software-rendered in QML
                // Canvas and stalls badly at 1080p, which froze the Flow mode.
                ctx.strokeStyle = rgbaStr(col.r, col.g, col.b, 0.16)
                ctx.lineWidth = 16 + a.level * 14
                ctx.stroke()
                ctx.strokeStyle = rgbaStr(col.r, col.g, col.b, 0.95)
                ctx.lineWidth = 4 + a.level * 5
                ctx.stroke()
            }
        }

        function drawBars(ctx, W, H, a) {
            ctx.fillStyle = viz.dim ? "rgba(5,5,7,0.5)" : "#050507"
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
                grd.addColorStop(1, rgbaStr(viz.c1[0], viz.c1[1], viz.c1[2], 0.18))
                ctx.fillStyle = grd
                roundRect(ctx, x + gap / 2, baseY - h, bw - gap, h, 6); ctx.fill()
                ctx.globalAlpha = 0.13; ctx.fillStyle = rgbaStr(col.r, col.g, col.b, 1)
                roundRect(ctx, x + gap / 2, baseY + 8, bw - gap, h * 0.32, 4); ctx.fill()
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

    // ~60fps repaint while visible
    Timer {
        interval: 16
        running: viz.visible
        repeat: true
        onTriggered: { viz.vt += 0.016; canvas.requestPaint() }
    }
}
