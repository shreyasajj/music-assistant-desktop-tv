from __future__ import annotations
import json, os
from dataclasses import dataclass, asdict
from pathlib import Path

@dataclass
class Settings:
    ma_host: str = "localhost"
    ma_port: int = 8095
    ma_token: str = ""
    default_player_id: str = ""
    guest_port: int = 8950
    lrclib_fallback: bool = True
    # UI options
    compact_lyrics: bool = True       # show only prev/active/next-2 lyric lines
    art_pump: bool = True             # pump the now-playing art with the bass
    viz_behind_lyrics: bool = False   # render the visualizer behind the lyrics
    audio_device: str = ""            # visualizer source: "" = simulated, "__auto__" = output monitor, else a device

def default_config_path() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "bigscreen-jukebox" / "settings.json"

def load_settings(path: Path) -> Settings:
    if not path.exists():
        print(f"[info] no settings file at {path}, using defaults")
        return Settings()
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
        fields = {f for f in Settings().__dict__}
        s = Settings(**{k: v for k, v in data.items() if k in fields})
        print(f"[info] settings loaded from {path}")
        return s
    except Exception as e:
        print(f"[warn] could not load settings from {path}: {e} — using defaults")
        return Settings()

def save_settings(settings: Settings, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(asdict(settings), indent=2), encoding='utf-8')
    print(f"[info] settings saved to {path}")
