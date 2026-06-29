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
        return Settings()
    data = json.loads(path.read_text())
    fields = {f for f in Settings().__dict__}
    return Settings(**{k: v for k, v in data.items() if k in fields})

def save_settings(settings: Settings, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(asdict(settings), indent=2))
