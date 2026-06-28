import numpy as np
from bigscreen_jukebox.audio_analysis import AudioAnalyzer

def sine(freq, n=4096, sr=48000):
    t = np.arange(n) / sr
    return np.sin(2 * np.pi * freq * t).astype(np.float32)

def test_silence_is_low_energy():
    a = AudioAnalyzer()
    out = a.analyze(np.zeros(4096, dtype=np.float32))
    assert out["energy"] < 0.01
    assert out["beat"] == 0.0
    assert len(out["bars"]) == 64
    assert max(out["bars"]) < 0.01

def test_bars_length_is_64():
    a = AudioAnalyzer()
    out = a.analyze(sine(440))
    assert len(out["bars"]) == 64

def test_low_tone_loads_low_bars():
    a = AudioAnalyzer()
    out = a.analyze(sine(80) * 5)
    bars = out["bars"]
    assert np.mean(bars[:8]) > np.mean(bars[-8:])

def test_high_tone_loads_high_bars():
    a = AudioAnalyzer()
    out = a.analyze(sine(9000) * 5)
    bars = out["bars"]
    assert np.mean(bars[-8:]) > np.mean(bars[:8])

def test_values_are_normalized():
    a = AudioAnalyzer()
    out = a.analyze(sine(440) * 10)  # loud
    assert 0.0 <= out["energy"] <= 1.0
    assert all(0.0 <= b <= 1.2 for b in out["bars"])

def test_loud_bass_after_silence_triggers_beat():
    a = AudioAnalyzer()
    out = a.analyze(sine(60) * 6)   # running average starts at 0
    assert out["beat"] == 1.0

def test_push_updates_properties_and_signal():
    a = AudioAnalyzer()
    seen = []
    a.bandsChanged.connect(lambda: seen.append(a.energy))
    a.push(sine(80) * 5)
    assert len(a.bars) == 64
    assert a.energy >= 0.0
    assert len(seen) == 1
