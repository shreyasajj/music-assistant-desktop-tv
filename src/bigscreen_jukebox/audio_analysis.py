from __future__ import annotations
import numpy as np
from PySide6.QtCore import QObject, Signal, Property

# device sentinels (see Settings "Visualizer audio capture device")
DEVICE_SIMULATED = ""          # no capture — the visualizer animates random beats
DEVICE_AUTO = "__auto__"       # auto-detect a system output monitor source


class AudioAnalyzer(QObject):
    bandsChanged = Signal()
    NBARS = 64

    def __init__(self, device=None):
        super().__init__()
        self._energy = 0.0
        self._beat = 0.0
        self._bass = 0.0
        self._level = 0.0
        self._bars = [0.0] * self.NBARS
        self._avg_bass = 0.0
        self._device = device      # "" -> simulated, "__auto__" -> monitor, else a device
        # Simulated when no real capture device is chosen.
        self._simulated = device in (None, DEVICE_SIMULATED)
        self._sr = 48000

    def _resolve_device(self, sd):
        """Pick the capture device. '__auto__' prefers a PipeWire/Pulse *monitor*
        source so the visualizer reacts to what's playing; otherwise use the
        explicitly chosen device. Falls back to the default input."""
        if self._device == DEVICE_AUTO:
            try:
                for i, d in enumerate(sd.query_devices()):
                    name = (d.get("name") or "").lower()
                    if d.get("max_input_channels", 0) > 0 and "monitor" in name:
                        return i
            except Exception:
                pass
            return None
        return self._device

    def analyze(self, samples: np.ndarray, sample_rate: int = 48000) -> dict:
        x = np.asarray(samples, dtype=np.float32)
        if x.ndim > 1:
            x = x.mean(axis=1)
        n = len(x)
        if n == 0:
            return {"energy": 0.0, "beat": 0.0, "bass": 0.0, "bars": [0.0] * self.NBARS, "level": 0.0}
        win = x * np.hanning(n)
        mag = np.abs(np.fft.rfft(win)) / n
        freqs = np.fft.rfftfreq(n, 1.0 / sample_rate)
        # 64 log-spaced spectrum bars (20 Hz .. Nyquist-ish)
        edges = np.logspace(np.log10(20), np.log10(min(18000, sample_rate / 2)), self.NBARS + 1)
        bars = []
        for i in range(self.NBARS):
            sel = (freqs >= edges[i]) & (freqs < edges[i + 1])
            v = float(mag[sel].mean()) if sel.any() else 0.0
            bars.append(min(1.2, v / 0.02))
        energy = float(min(1.0, np.sqrt(np.mean(x ** 2)) * 1.5))
        bass = float(np.mean(bars[:5]))                       # low-end energy
        beat = 1.0 if bass > self._avg_bass * 1.3 + 0.05 else 0.0   # kick on a bass spike
        self._avg_bass = 0.9 * self._avg_bass + 0.1 * bass
        # Pulse is driven by the kick (beat) plus the continuous low-end (bass).
        level = float(min(1.4, (beat * 0.6 + bass * 0.9) * (0.6 + energy * 0.5)))
        return {"energy": energy, "beat": beat, "bass": bass, "bars": bars, "level": level}

    def push(self, samples: np.ndarray, sample_rate: int = 48000) -> None:
        r = self.analyze(samples, sample_rate)
        self._energy, self._beat, self._bass = r["energy"], r["beat"], r["bass"]
        self._level, self._bars = r["level"], r["bars"]
        self.bandsChanged.emit()

    def start(self) -> None:
        if self._simulated:
            return    # no capture device chosen — the visualizer animates random beats
        try:
            import sounddevice as sd  # PortAudio; on Linux this reaches PipeWire/Pulse
        except ImportError:
            print("[warn] sounddevice not installed; visualizer will stay idle")
            return
        device = self._resolve_device(sd)

        def _cb(indata, frames, t, status):
            self.push(indata[:, 0], self._sr)

        # Try the device's native rate first, then let PortAudio choose.
        for sr in (48000, None):
            try:
                kwargs = dict(channels=1, blocksize=2048, callback=_cb)
                if device is not None:
                    kwargs["device"] = device
                if sr is not None:
                    kwargs["samplerate"] = sr
                stream = sd.InputStream(**kwargs)
                self._sr = int(stream.samplerate)
                stream.start()
                self._stream = stream
                print(f"[info] visualizer audio capture: device={device!r} rate={self._sr}")
                return
            except Exception as e:
                print(f"[warn] audio capture failed (device={device!r}, rate={sr}): {e}")
        print("[warn] no audio capture device; visualizer will stay idle")

    def stop(self) -> None:
        s = getattr(self, "_stream", None)
        if s is not None:
            s.stop(); s.close(); self._stream = None

    energy = Property(float, lambda s: s._energy, notify=bandsChanged)
    beat = Property(float, lambda s: s._beat, notify=bandsChanged)
    bass = Property(float, lambda s: s._bass, notify=bandsChanged)
    level = Property(float, lambda s: s._level, notify=bandsChanged)
    bars = Property("QVariantList", lambda s: s._bars, notify=bandsChanged)
    simulated = Property(bool, lambda s: s._simulated, constant=True)
