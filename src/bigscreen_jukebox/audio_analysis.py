from __future__ import annotations
import numpy as np
from PySide6.QtCore import QObject, Signal, Property

class AudioAnalyzer(QObject):
    bandsChanged = Signal()
    NBARS = 64

    def __init__(self):
        super().__init__()
        self._energy = 0.0
        self._beat = 0.0
        self._level = 0.0
        self._bars = [0.0] * self.NBARS
        self._avg_bass = 0.0

    def analyze(self, samples: np.ndarray, sample_rate: int = 48000) -> dict:
        x = np.asarray(samples, dtype=np.float32)
        if x.ndim > 1:
            x = x.mean(axis=1)
        n = len(x)
        if n == 0:
            return {"energy": 0.0, "beat": 0.0, "bars": [0.0] * self.NBARS, "level": 0.0}
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
        bass = float(np.mean(bars[:5]))
        beat = 1.0 if bass > self._avg_bass * 1.3 + 0.05 else 0.0
        self._avg_bass = 0.9 * self._avg_bass + 0.1 * bass
        level = float(min(1.4, beat * (0.5 + energy * 0.6)))
        return {"energy": energy, "beat": beat, "bars": bars, "level": level}

    def push(self, samples: np.ndarray, sample_rate: int = 48000) -> None:
        r = self.analyze(samples, sample_rate)
        self._energy, self._beat = r["energy"], r["beat"]
        self._level, self._bars = r["level"], r["bars"]
        self.bandsChanged.emit()

    def start(self) -> None:
        try:
            import sounddevice as sd  # PipeWire monitor source; device chosen in Task 14
        except ImportError:
            return
        self._stream = sd.InputStream(
            channels=1, samplerate=48000, blocksize=2048,
            callback=lambda indata, frames, t, status: self.push(indata[:, 0], 48000))
        self._stream.start()

    def stop(self) -> None:
        s = getattr(self, "_stream", None)
        if s is not None:
            s.stop(); s.close(); self._stream = None

    energy = Property(float, lambda s: s._energy, notify=bandsChanged)
    beat = Property(float, lambda s: s._beat, notify=bandsChanged)
    level = Property(float, lambda s: s._level, notify=bandsChanged)
    bars = Property("QVariantList", lambda s: s._bars, notify=bandsChanged)
