from pathlib import Path
from bigscreen_jukebox.config import Settings, load_settings, save_settings

def test_load_missing_returns_defaults(tmp_path):
    s = load_settings(tmp_path / "nope.json")
    assert s == Settings()
    assert s.ma_port == 8095 and s.guest_port == 8950
    assert s.lrclib_fallback is True

def test_save_then_load_roundtrip(tmp_path):
    p = tmp_path / "sub" / "settings.json"
    save_settings(Settings(ma_host="tv.local", ma_token="abc", default_player_id="living"), p)
    loaded = load_settings(p)
    assert loaded.ma_host == "tv.local"
    assert loaded.ma_token == "abc"
    assert loaded.default_player_id == "living"
