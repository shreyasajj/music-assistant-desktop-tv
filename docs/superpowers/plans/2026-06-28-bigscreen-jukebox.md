# Bigscreen Jukebox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native Plasma Bigscreen app that lets a TV control a Music Assistant server — search/play music, show now-playing, karaoke lyrics, a fullscreen beat-reactive visualizer, and a toggleable guest queue via phone QR.

**Architecture:** A single Python (PySide6) process owns all I/O and state (Music Assistant WebSocket client, PipeWire audio analysis, embedded guest web server) and exposes it to a Kirigami/QML UI through `QObject` properties and signals. QML binds reactively to that state. Static HTML mockups are built first to lock the 10-foot visual design.

**Tech Stack:** Python 3.11+, PySide6 (Qt 6 / QML / Kirigami), `music-assistant-client`, `aiohttp`, `qrcode`, `numpy`, PipeWire (via `sounddevice`/`pasimple`), `pytest` + `pytest-asyncio`.

## Global Constraints

- Target platform: Plasma Bigscreen (Wayland), TV / 10-foot UI — large fonts, large artwork, high contrast, focus-navigable by remote **and** keyboard.
- Minimum Music Assistant server version: **2.6** (first version exposing lyrics). Pin and document this.
- Music Assistant connection is **direct to the server WebSocket** (`ws://<host>:8095/ws`); no Home Assistant dependency. Host/port/token come from settings; token is optional.
- Lyrics come **only** from Music Assistant's own track metadata (synced LRC when available). Do not call LRCLIB or any other lyrics source directly.
- Guest songs go **straight to the active player's queue** — no host-approval step in v1.
- Layout is **separate tabbed full screens**: Now Playing · Search · Lyrics · Visualizer.
- Player targeting: a **configured default player, switchable on screen** via a player picker. Guest additions go to the active player's queue.
- Playback: **full transport** — play/pause, next, previous, seek, volume.
- All network/I/O is async (`asyncio`); integrate the asyncio loop with the Qt event loop via `qasync`.
- TDD: every logic task is test-first. UI (QML) tasks use concrete QML + manual verification, per the spec's testing strategy. Commit after every passing step.

---

## File Structure

```
music_assistant_desktop_linux/
  pyproject.toml                      # package + deps + pytest config
  README.md
  src/bigscreen_jukebox/
    __init__.py
    __main__.py                       # entry point: QApplication + qasync + load QML
    config.py                         # Settings load/save (JSON in XDG config dir)
    lyrics.py                         # LRC parse + current-line selection (pure logic)
    ma_client.py                      # MaClient QObject: WS connect, state, actions
    audio_analysis.py                 # AudioAnalyzer QObject: PipeWire capture + FFT
    guest_server.py                   # GuestServer: aiohttp app, search/add endpoints
    qr.py                             # QR code data-URI generation
  qml/
    main.qml                          # shell: tab bar + StackLayout + GuestOverlay
    Theme.qml                         # colors, font sizes (10-foot scale) — singleton
    NowPlaying.qml
    Search.qml
    Lyrics.qml
    Visualizer.qml
    GuestOverlay.qml
    SettingsView.qml
  mockups/
    index.html                        # screen switcher
    nowplaying.html  search.html  lyrics.html  visualizer.html
    styles.css                        # shared 10-foot styling
  tests/
    test_config.py
    test_lyrics.py
    test_ma_client.py
    test_audio_analysis.py
    test_guest_server.py
    test_qr.py
  packaging/
    org.bigscreen.jukebox.desktop     # Bigscreen app launcher entry
```

---

## Task 1: Project scaffold

**Files:**
- Create: `pyproject.toml`, `src/bigscreen_jukebox/__init__.py`, `README.md`
- Test: `tests/test_smoke.py`

**Interfaces:**
- Consumes: nothing.
- Produces: importable package `bigscreen_jukebox` with `__version__: str`; working `pytest` setup.

- [ ] **Step 1: Write the failing test**

```python
# tests/test_smoke.py
import bigscreen_jukebox

def test_package_has_version():
    assert isinstance(bigscreen_jukebox.__version__, str)
    assert bigscreen_jukebox.__version__
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_smoke.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'bigscreen_jukebox'`

- [ ] **Step 3: Write minimal implementation**

```toml
# pyproject.toml
[project]
name = "bigscreen-jukebox"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = [
  "PySide6>=6.6",
  "qasync>=0.27",
  "music-assistant-client>=1.0",
  "aiohttp>=3.9",
  "qrcode>=7.4",
  "numpy>=1.26",
  "sounddevice>=0.4",
]

[project.optional-dependencies]
dev = ["pytest>=8.0", "pytest-asyncio>=0.23"]

[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[tool.setuptools.packages.find]
where = ["src"]

[tool.pytest.ini_options]
pythonpath = ["src"]
asyncio_mode = "auto"
```

```python
# src/bigscreen_jukebox/__init__.py
__version__ = "0.1.0"
```

```markdown
# Bigscreen Jukebox

Native Plasma Bigscreen app for controlling a Music Assistant server from the TV.
See docs/superpowers/specs/2026-06-28-bigscreen-jukebox-design.md.

## Dev setup
    pip install -e ".[dev]"
    pytest
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pip install -e ".[dev]" && pytest tests/test_smoke.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add pyproject.toml src/bigscreen_jukebox/__init__.py README.md tests/test_smoke.py
git commit -m "chore: project scaffold"
```

---

## Task 2: Static HTML mockups (the visual mock design)

**Files:**
- Create: `mockups/index.html`, `mockups/nowplaying.html`, `mockups/search.html`, `mockups/lyrics.html`, `mockups/visualizer.html`, `mockups/styles.css`

**Interfaces:**
- Consumes: nothing (static, no app code).
- Produces: a browser-viewable visual reference for all screens and the guest overlay. Becomes the source of truth for `Theme.qml` values (colors, font sizes, spacing) in later tasks.

This task is the "mock design" — open `mockups/index.html` in a browser at 1920×1080 to see exactly how each screen looks on the TV. No tests; deliverable is the visual.

- [ ] **Step 1: Create the shared 10-foot stylesheet**

```css
/* mockups/styles.css */
:root {
  --bg: #0b0b12; --panel: #15151f; --fg: #ffffff; --muted: #a0a0b0;
  --accent: #00e0c6; --accent2: #ff3da6;
  --xxl: 84px; --xl: 56px; --lg: 40px; --md: 30px; --sm: 24px;
  --pad: 64px; --radius: 24px;
}
* { box-sizing: border-box; margin: 0; }
html, body { height: 100%; }
body {
  background: var(--bg); color: var(--fg);
  font-family: "Noto Sans", system-ui, sans-serif;
  width: 1920px; height: 1080px; overflow: hidden; position: relative;
}
.tabbar { display: flex; gap: 48px; padding: 32px var(--pad); font-size: var(--md); color: var(--muted); }
.tabbar .active { color: var(--fg); border-bottom: 6px solid var(--accent); padding-bottom: 8px; }
.guest-qr {
  position: absolute; top: 40px; right: 48px; background: var(--panel);
  border-radius: var(--radius); padding: 24px; text-align: center; font-size: var(--sm);
}
.guest-qr .code { width: 180px; height: 180px; background:
  repeating-conic-gradient(#fff 0 25%, #000 0 50%) 0 0/40px 40px; border-radius: 12px; }
.art { background: linear-gradient(135deg, var(--accent), var(--accent2)); border-radius: var(--radius); }
.btn { background: var(--panel); border-radius: 999px; padding: 24px 40px; font-size: var(--lg); display: inline-flex; }
.btn.primary { background: var(--accent); color: #000; }
.muted { color: var(--muted); }
```

- [ ] **Step 2: Now Playing mockup**

```html
<!-- mockups/nowplaying.html -->
<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="styles.css"></head>
<body>
  <div class="tabbar"><span class="active">Now Playing</span><span>Search</span><span>Lyrics</span><span>Visualizer</span></div>
  <div class="guest-qr"><div class="code"></div><div>Scan to add songs<br><b>tv.local:8950</b></div></div>
  <div style="display:flex; gap:80px; padding:40px var(--pad); align-items:center;">
    <div class="art" style="width:560px; height:560px;"></div>
    <div>
      <div style="font-size:var(--xxl); font-weight:800;">Midnight City</div>
      <div style="font-size:var(--xl); color:var(--muted);">M83</div>
      <div style="font-size:var(--md); color:var(--muted); margin-top:16px;">Hurry Up, We're Dreaming</div>
      <div style="margin-top:48px; width:900px; height:14px; background:var(--panel); border-radius:999px;">
        <div style="width:42%; height:100%; background:var(--accent); border-radius:999px;"></div></div>
      <div style="display:flex; justify-content:space-between; width:900px; font-size:var(--sm); color:var(--muted); margin-top:12px;"><span>1:42</span><span>4:03</span></div>
      <div style="display:flex; gap:32px; margin-top:48px;">
        <span class="btn">⏮</span><span class="btn primary">⏸</span><span class="btn">⏭</span>
        <span class="btn">🔊 ▮▮▮▯▯</span>
      </div>
      <div style="margin-top:40px; font-size:var(--sm);" class="muted">Player: <b style="color:var(--fg)">Living Room ▾</b></div>
    </div>
  </div>
</body></html>
```

- [ ] **Step 3: Search mockup**

```html
<!-- mockups/search.html -->
<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="styles.css"></head>
<body>
  <div class="tabbar"><span>Now Playing</span><span class="active">Search</span><span>Lyrics</span><span>Visualizer</span></div>
  <div style="padding:20px var(--pad);">
    <div style="background:var(--panel); border-radius:var(--radius); padding:36px 48px; font-size:var(--xl); display:flex; gap:24px; align-items:center;">
      <span>🔍</span><span>daft pun<span style="color:var(--accent)">|</span></span>
    </div>
    <div style="margin-top:48px; display:flex; flex-direction:column; gap:28px;">
      <div style="display:flex; gap:32px; align-items:center; background:var(--accent); color:#000; border-radius:var(--radius); padding:24px 36px;">
        <div class="art" style="width:120px; height:120px;"></div>
        <div><div style="font-size:var(--lg); font-weight:800;">One More Time</div><div style="font-size:var(--md);">Daft Punk · Discovery</div></div>
      </div>
      <div style="display:flex; gap:32px; align-items:center; background:var(--panel); border-radius:var(--radius); padding:24px 36px;">
        <div class="art" style="width:120px; height:120px;"></div>
        <div><div style="font-size:var(--lg); font-weight:800;">Get Lucky</div><div style="font-size:var(--md); color:var(--muted);">Daft Punk · Random Access Memories</div></div>
      </div>
      <div style="display:flex; gap:32px; align-items:center; background:var(--panel); border-radius:var(--radius); padding:24px 36px;">
        <div class="art" style="width:120px; height:120px;"></div>
        <div><div style="font-size:var(--lg); font-weight:800;">Harder, Better, Faster, Stronger</div><div style="font-size:var(--md); color:var(--muted);">Daft Punk · Discovery</div></div>
      </div>
    </div>
  </div>
</body></html>
```

- [ ] **Step 4: Lyrics (karaoke) mockup**

```html
<!-- mockups/lyrics.html -->
<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="styles.css"></head>
<body>
  <div class="tabbar"><span>Now Playing</span><span>Search</span><span class="active">Lyrics</span><span>Visualizer</span></div>
  <div style="display:flex; flex-direction:column; align-items:center; justify-content:center; height:880px; gap:40px; text-align:center;">
    <div style="font-size:var(--lg); color:var(--muted);">Waiting all night for the sun</div>
    <div style="font-size:var(--lg); color:var(--muted);">To shine on the lonely ones</div>
    <div style="font-size:var(--xxl); font-weight:800; color:var(--accent);">Now I'm dancing in the dark</div>
    <div style="font-size:var(--lg); color:var(--muted);">With you between my arms</div>
    <div style="font-size:var(--lg); color:var(--muted);">Barefoot on the grass</div>
  </div>
</body></html>
```

- [ ] **Step 5: Visualizer mockup**

```html
<!-- mockups/visualizer.html -->
<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="styles.css"></head>
<body style="background:#000;">
  <div class="guest-qr"><div class="code"></div><div>Scan to add songs<br><b>tv.local:8950</b></div></div>
  <div style="position:absolute; inset:0; display:flex; align-items:flex-end; justify-content:center; gap:18px; padding:160px;">
    <!-- representative bars; real version is canvas/WebGL driven by audio -->
    <div style="width:60px; height:220px; background:linear-gradient(var(--accent),var(--accent2)); border-radius:12px;"></div>
    <div style="width:60px; height:520px; background:linear-gradient(var(--accent),var(--accent2)); border-radius:12px;"></div>
    <div style="width:60px; height:680px; background:linear-gradient(var(--accent),var(--accent2)); border-radius:12px;"></div>
    <div style="width:60px; height:400px; background:linear-gradient(var(--accent),var(--accent2)); border-radius:12px;"></div>
    <div style="width:60px; height:760px; background:linear-gradient(var(--accent),var(--accent2)); border-radius:12px;"></div>
    <div style="width:60px; height:300px; background:linear-gradient(var(--accent),var(--accent2)); border-radius:12px;"></div>
    <div style="width:60px; height:560px; background:linear-gradient(var(--accent),var(--accent2)); border-radius:12px;"></div>
  </div>
  <div style="position:absolute; bottom:80px; left:80px; font-size:var(--xl); font-weight:800;">Midnight City · M83</div>
</body></html>
```

- [ ] **Step 6: Index switcher**

```html
<!-- mockups/index.html -->
<!doctype html><html><head><meta charset="utf-8"><title>Bigscreen Jukebox mockups</title>
<style>body{font-family:system-ui;background:#0b0b12;color:#fff;padding:40px;} a{display:block;font-size:28px;color:#00e0c6;margin:16px 0;}</style></head>
<body><h1>Bigscreen Jukebox — screen mockups</h1>
<a href="nowplaying.html">Now Playing</a><a href="search.html">Search</a>
<a href="lyrics.html">Lyrics (karaoke)</a><a href="visualizer.html">Visualizer</a>
<p style="color:#a0a0b0">Open each at 1920×1080 to preview the 10-foot layout.</p></body></html>
```

- [ ] **Step 7: Verify visually**

Run: `python -m http.server -d mockups 8000` then open `http://localhost:8000` and view each screen at 1920×1080 (browser zoom/responsive mode). Confirm fonts read from across a room and the guest QR sits top-right.

- [ ] **Step 8: Commit**

```bash
git add mockups/
git commit -m "feat: static HTML mockups of all screens (visual design reference)"
```

**STOP — show these mockups to the user for visual sign-off before continuing.** Adjust colors/sizes here first; later QML styling copies these values.

---

## Task 3: Config / Settings

**Files:**
- Create: `src/bigscreen_jukebox/config.py`
- Test: `tests/test_config.py`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `@dataclass Settings(ma_host: str = "localhost", ma_port: int = 8095, ma_token: str = "", default_player_id: str = "", guest_port: int = 8950)`
  - `load_settings(path: Path) -> Settings` — returns defaults if file missing.
  - `save_settings(settings: Settings, path: Path) -> None` — writes JSON, creating parent dirs.
  - `default_config_path() -> Path` — `$XDG_CONFIG_HOME/bigscreen-jukebox/settings.json` (fallback `~/.config/...`).

- [ ] **Step 1: Write the failing test**

```python
# tests/test_config.py
from pathlib import Path
from bigscreen_jukebox.config import Settings, load_settings, save_settings

def test_load_missing_returns_defaults(tmp_path):
    s = load_settings(tmp_path / "nope.json")
    assert s == Settings()
    assert s.ma_port == 8095 and s.guest_port == 8950

def test_save_then_load_roundtrip(tmp_path):
    p = tmp_path / "sub" / "settings.json"
    save_settings(Settings(ma_host="tv.local", ma_token="abc", default_player_id="living"), p)
    loaded = load_settings(p)
    assert loaded.ma_host == "tv.local"
    assert loaded.ma_token == "abc"
    assert loaded.default_player_id == "living"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_config.py -v`
Expected: FAIL — `ModuleNotFoundError: bigscreen_jukebox.config`

- [ ] **Step 3: Write minimal implementation**

```python
# src/bigscreen_jukebox/config.py
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_config.py -v`
Expected: PASS (both tests)

- [ ] **Step 5: Commit**

```bash
git add src/bigscreen_jukebox/config.py tests/test_config.py
git commit -m "feat: settings load/save"
```

---

## Task 4: Lyrics LRC parsing

**Files:**
- Create: `src/bigscreen_jukebox/lyrics.py`
- Test: `tests/test_lyrics.py`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `@dataclass LyricLine(time_ms: int | None, text: str)`
  - `@dataclass Lyrics(lines: list[LyricLine], synced: bool)`
  - `parse_lyrics(raw: str | None) -> Lyrics` — parses LRC (`[mm:ss.xx]text`) into timed lines; if no timestamps present, returns `synced=False` with one `LyricLine(None, text)` per source line; empty/None → `Lyrics([], False)`.
  - `current_line_index(lyrics: Lyrics, position_ms: int) -> int` — index of the active line for a playback position (the last line whose `time_ms <= position_ms`); `-1` before the first timestamp or when not synced/empty.

- [ ] **Step 1: Write the failing test**

```python
# tests/test_lyrics.py
from bigscreen_jukebox.lyrics import parse_lyrics, current_line_index

LRC = "[00:01.00]first line\n[00:04.50]second line\n[00:09.00]third line\n"

def test_parse_synced():
    lyr = parse_lyrics(LRC)
    assert lyr.synced is True
    assert [l.text for l in lyr.lines] == ["first line", "second line", "third line"]
    assert lyr.lines[1].time_ms == 4500

def test_parse_plain_when_no_timestamps():
    lyr = parse_lyrics("just\nplain\nwords")
    assert lyr.synced is False
    assert len(lyr.lines) == 3
    assert lyr.lines[0].time_ms is None

def test_parse_empty():
    assert parse_lyrics(None).lines == []
    assert parse_lyrics("").lines == []

def test_current_line_index():
    lyr = parse_lyrics(LRC)
    assert current_line_index(lyr, 0) == -1
    assert current_line_index(lyr, 1500) == 0
    assert current_line_index(lyr, 4500) == 1
    assert current_line_index(lyr, 100000) == 2

def test_current_line_index_plain_is_minus_one():
    assert current_line_index(parse_lyrics("plain"), 5000) == -1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_lyrics.py -v`
Expected: FAIL — `ModuleNotFoundError: bigscreen_jukebox.lyrics`

- [ ] **Step 3: Write minimal implementation**

```python
# src/bigscreen_jukebox/lyrics.py
from __future__ import annotations
import re
from dataclasses import dataclass, field

_TS = re.compile(r"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]")

@dataclass
class LyricLine:
    time_ms: int | None
    text: str

@dataclass
class Lyrics:
    lines: list[LyricLine] = field(default_factory=list)
    synced: bool = False

def parse_lyrics(raw: str | None) -> Lyrics:
    if not raw or not raw.strip():
        return Lyrics([], False)
    lines: list[LyricLine] = []
    synced = False
    for raw_line in raw.splitlines():
        stamps = list(_TS.finditer(raw_line))
        text = _TS.sub("", raw_line).strip()
        if stamps:
            synced = True
            for m in stamps:
                mm, ss, frac = m.group(1), m.group(2), m.group(3) or "0"
                ms = int(mm) * 60000 + int(ss) * 1000 + int(frac.ljust(3, "0"))
                lines.append(LyricLine(ms, text))
        elif text:
            lines.append(LyricLine(None, text))
    if synced:
        lines.sort(key=lambda l: (l.time_ms is None, l.time_ms or 0))
    return Lyrics(lines, synced)

def current_line_index(lyrics: Lyrics, position_ms: int) -> int:
    if not lyrics.synced:
        return -1
    idx = -1
    for i, line in enumerate(lyrics.lines):
        if line.time_ms is not None and line.time_ms <= position_ms:
            idx = i
        else:
            break
    return idx
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_lyrics.py -v`
Expected: PASS (all 5 tests)

- [ ] **Step 5: Commit**

```bash
git add src/bigscreen_jukebox/lyrics.py tests/test_lyrics.py
git commit -m "feat: LRC lyrics parsing and current-line selection"
```

---

## Task 5: MA Client — connection & state

**Files:**
- Create: `src/bigscreen_jukebox/ma_client.py`
- Test: `tests/test_ma_client.py`

**Interfaces:**
- Consumes: `Settings` (Task 3), `parse_lyrics` (Task 4).
- Produces a PySide6 `QObject` `MaClient(settings: Settings)` with:
  - Qt properties (each with a `Changed` signal): `connected: bool`, `players: list[dict]` (`[{"id","name"}]`), `activePlayerId: str`, `trackTitle: str`, `trackArtist: str`, `trackAlbum: str`, `artUrl: str`, `positionMs: int`, `durationMs: int`, `isPlaying: bool`, `volume: int`, `queue: list[dict]`, `lyricsJson: str` (serialized `Lyrics`).
  - `update_from_player_state(state: dict) -> None` — pure method mapping a Music Assistant player/queue state dict into the properties above (this is the unit-tested seam; the live WS handler calls it).
  - `select_player(player_id: str) -> None` — sets `activePlayerId` and emits change.
  - async `connect() -> None` / `disconnect() -> None` — manage the `music-assistant-client` session (not unit-tested; exercised manually).

Note: tests target `update_from_player_state` and `select_player` with plain dicts so no live server is needed. Confirm the exact MA state schema during Task 13 manual wiring and adjust the mapping keys in one place if needed.

- [ ] **Step 1: Write the failing test**

```python
# tests/test_ma_client.py
import json
import pytest
from bigscreen_jukebox.config import Settings

@pytest.fixture
def client():
    from bigscreen_jukebox.ma_client import MaClient
    return MaClient(Settings())

SAMPLE = {
    "player_id": "living",
    "playing": True,
    "volume_level": 55,
    "elapsed_ms": 1742,
    "current_media": {
        "title": "Midnight City", "artist": "M83", "album": "Hurry Up",
        "image": "http://art/1.jpg", "duration_ms": 243000,
        "lyrics": "[00:01.00]hello\n[00:03.00]world",
    },
    "queue": [{"title": "Next Song", "artist": "Artist"}],
}

def test_update_maps_now_playing(client):
    client.update_from_player_state(SAMPLE)
    assert client.trackTitle == "Midnight City"
    assert client.trackArtist == "M83"
    assert client.durationMs == 243000
    assert client.positionMs == 1742
    assert client.isPlaying is True
    assert client.volume == 55
    assert client.artUrl == "http://art/1.jpg"

def test_update_serializes_lyrics(client):
    client.update_from_player_state(SAMPLE)
    data = json.loads(client.lyricsJson)
    assert data["synced"] is True
    assert data["lines"][0]["text"] == "hello"

def test_update_maps_queue(client):
    client.update_from_player_state(SAMPLE)
    assert client.queue[0]["title"] == "Next Song"

def test_select_player_emits(client):
    seen = []
    client.activePlayerIdChanged.connect(lambda: seen.append(client.activePlayerId))
    client.select_player("kitchen")
    assert client.activePlayerId == "kitchen"
    assert seen == ["kitchen"]

def test_missing_media_is_safe(client):
    client.update_from_player_state({"player_id": "x", "playing": False})
    assert client.trackTitle == ""
    assert client.durationMs == 0
    assert json.loads(client.lyricsJson)["lines"] == []
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_ma_client.py -v`
Expected: FAIL — `ModuleNotFoundError: bigscreen_jukebox.ma_client`

- [ ] **Step 3: Write minimal implementation**

```python
# src/bigscreen_jukebox/ma_client.py
from __future__ import annotations
import json
from dataclasses import asdict
from PySide6.QtCore import QObject, Signal, Property
from .config import Settings
from .lyrics import parse_lyrics

class MaClient(QObject):
    connectedChanged = Signal()
    playersChanged = Signal()
    activePlayerIdChanged = Signal()
    nowPlayingChanged = Signal()       # title/artist/album/art/duration
    positionMsChanged = Signal()
    isPlayingChanged = Signal()
    volumeChanged = Signal()
    queueChanged = Signal()
    lyricsJsonChanged = Signal()

    def __init__(self, settings: Settings):
        super().__init__()
        self._settings = settings
        self._connected = False
        self._players: list[dict] = []
        self._active = settings.default_player_id
        self._title = self._artist = self._album = self._art = ""
        self._pos = 0
        self._dur = 0
        self._playing = False
        self._volume = 0
        self._queue: list[dict] = []
        self._lyrics_json = json.dumps({"lines": [], "synced": False})

    def update_from_player_state(self, state: dict) -> None:
        media = state.get("current_media") or {}
        self._title = media.get("title", "")
        self._artist = media.get("artist", "")
        self._album = media.get("album", "")
        self._art = media.get("image", "")
        self._dur = int(media.get("duration_ms", 0) or 0)
        self._pos = int(state.get("elapsed_ms", 0) or 0)
        self._playing = bool(state.get("playing", False))
        self._volume = int(state.get("volume_level", 0) or 0)
        self._queue = list(state.get("queue", []) or [])
        self._lyrics_json = json.dumps(asdict(parse_lyrics(media.get("lyrics"))))
        for sig in (self.nowPlayingChanged, self.positionMsChanged, self.isPlayingChanged,
                    self.volumeChanged, self.queueChanged, self.lyricsJsonChanged):
            sig.emit()

    def select_player(self, player_id: str) -> None:
        if player_id != self._active:
            self._active = player_id
            self.activePlayerIdChanged.emit()

    # --- Qt properties ---
    connected = Property(bool, lambda s: s._connected, notify=connectedChanged)
    players = Property("QVariantList", lambda s: s._players, notify=playersChanged)
    activePlayerId = Property(str, lambda s: s._active, notify=activePlayerIdChanged)
    trackTitle = Property(str, lambda s: s._title, notify=nowPlayingChanged)
    trackArtist = Property(str, lambda s: s._artist, notify=nowPlayingChanged)
    trackAlbum = Property(str, lambda s: s._album, notify=nowPlayingChanged)
    artUrl = Property(str, lambda s: s._art, notify=nowPlayingChanged)
    positionMs = Property(int, lambda s: s._pos, notify=positionMsChanged)
    durationMs = Property(int, lambda s: s._dur, notify=nowPlayingChanged)
    isPlaying = Property(bool, lambda s: s._playing, notify=isPlayingChanged)
    volume = Property(int, lambda s: s._volume, notify=volumeChanged)
    queue = Property("QVariantList", lambda s: s._queue, notify=queueChanged)
    lyricsJson = Property(str, lambda s: s._lyrics_json, notify=lyricsJsonChanged)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_ma_client.py -v`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add src/bigscreen_jukebox/ma_client.py tests/test_ma_client.py
git commit -m "feat: MaClient state mapping and player selection"
```

---

## Task 6: MA Client — actions & live connection

**Files:**
- Modify: `src/bigscreen_jukebox/ma_client.py`
- Test: `tests/test_ma_client.py` (add cases)

**Interfaces:**
- Consumes: Task 5 `MaClient`.
- Produces, on `MaClient`, async action methods plus a recordable command seam:
  - `_dispatch(command: str, **args) -> Awaitable` — single place that sends a command to MA; in tests it's monkeypatched to record calls.
  - Qt-invokable wrappers (via `@Slot`): `searchAsync(query: str)`, `playNow(uri: str)`, `addToQueue(uri: str)`, `playPause()`, `next()`, `previous()`, `seek(position_ms: int)`, `setVolume(level: int)`. Each builds the right command + args and calls `_dispatch`.
  - `searchResults: list[dict]` Qt property (`[{"title","artist","album","uri","image"}]`) + `searchResultsChanged` signal; `set_search_results(items: list[dict])` updates it (unit-tested seam).
  - async `connect()`: opens the `music-assistant-client` session to `ws://{host}:{port}/ws` (token if set), subscribes to player-state events → calls `update_from_player_state`, populates `players`, and sets `_connected`.

- [ ] **Step 1: Write the failing test (add to tests/test_ma_client.py)**

```python
def test_actions_dispatch_expected_commands(client, monkeypatch):
    calls = []
    monkeypatch.setattr(client, "_dispatch", lambda command, **a: calls.append((command, a)))
    client.select_player("living")
    client.playPause(); client.next(); client.previous()
    client.seek(30000); client.setVolume(40)
    client.playNow("library://track/5"); client.addToQueue("library://track/6")
    names = [c[0] for c in calls]
    assert "play_pause" in names and "next" in names and "previous" in names
    assert ("seek", {"player_id": "living", "position_ms": 30000}) in calls
    assert ("set_volume", {"player_id": "living", "level": 40}) in calls
    assert ("play_media", {"player_id": "living", "uri": "library://track/5", "enqueue": "play"}) in calls
    assert ("play_media", {"player_id": "living", "uri": "library://track/6", "enqueue": "add"}) in calls

def test_set_search_results(client):
    seen = []
    client.searchResultsChanged.connect(lambda: seen.append(len(client.searchResults)))
    client.set_search_results([{"title": "T", "artist": "A", "uri": "u"}])
    assert client.searchResults[0]["uri"] == "u"
    assert seen == [1]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_ma_client.py::test_actions_dispatch_expected_commands -v`
Expected: FAIL — `AttributeError: 'MaClient' object has no attribute 'playPause'`

- [ ] **Step 3: Write minimal implementation (add to ma_client.py)**

Add imports `from PySide6.QtCore import Slot` and `import asyncio`. Add to `__init__`: `self._search_results: list[dict] = []` and `self._session = None`. Add:

```python
    searchResultsChanged = Signal()

    def _dispatch(self, command: str, **args):
        # Replaced by live implementation in connect(); default raises if no session.
        if self._session is None:
            raise RuntimeError("not connected")
        return self._session.send_command(command, **args)

    def set_search_results(self, items: list[dict]) -> None:
        self._search_results = list(items)
        self.searchResultsChanged.emit()

    @Slot()
    def playPause(self): self._dispatch("play_pause", player_id=self._active)
    @Slot()
    def next(self): self._dispatch("next", player_id=self._active)
    @Slot()
    def previous(self): self._dispatch("previous", player_id=self._active)
    @Slot(int)
    def seek(self, position_ms: int): self._dispatch("seek", player_id=self._active, position_ms=position_ms)
    @Slot(int)
    def setVolume(self, level: int): self._dispatch("set_volume", player_id=self._active, level=level)
    @Slot(str)
    def playNow(self, uri: str): self._dispatch("play_media", player_id=self._active, uri=uri, enqueue="play")
    @Slot(str)
    def addToQueue(self, uri: str): self._dispatch("play_media", player_id=self._active, uri=uri, enqueue="add")

    searchResults = Property("QVariantList", lambda s: s._search_results, notify=searchResultsChanged)
```

Add the live connection (exercised manually in Task 13, not unit-tested):

```python
    async def connect(self):
        from music_assistant_client import MusicAssistantClient  # import name verified in Task 13
        url = f"ws://{self._settings.ma_host}:{self._settings.ma_port}/ws"
        self._session = MusicAssistantClient(url, self._settings.ma_token or None)
        await self._session.connect()
        self._connected = True
        self.connectedChanged.emit()
        self._players = [{"id": p.player_id, "name": p.display_name}
                         for p in self._session.players]
        self.playersChanged.emit()
        if not self._active and self._players:
            self.select_player(self._players[0]["id"])
        self._session.subscribe(lambda evt: self._on_event(evt))

    def _on_event(self, evt):
        state = getattr(evt, "data", None)
        if isinstance(state, dict) and state.get("player_id") == self._active:
            self.update_from_player_state(state)

    async def searchAsync(self, query: str):
        results = await self._dispatch("search", query=query, limit=20)
        self.set_search_results([
            {"title": r.get("name", ""), "artist": r.get("artist", ""),
             "album": r.get("album", ""), "uri": r.get("uri", ""), "image": r.get("image", "")}
            for r in (results or [])
        ])

    async def disconnect(self):
        if self._session is not None:
            await self._session.disconnect()
            self._session = None
            self._connected = False
            self.connectedChanged.emit()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_ma_client.py -v`
Expected: PASS (all tests in the file)

- [ ] **Step 5: Commit**

```bash
git add src/bigscreen_jukebox/ma_client.py tests/test_ma_client.py
git commit -m "feat: MaClient transport actions, search, and live connection"
```

---

## Task 7: Audio analysis service

**Files:**
- Create: `src/bigscreen_jukebox/audio_analysis.py`
- Test: `tests/test_audio_analysis.py`

**Interfaces:**
- Consumes: nothing.
- Produces a PySide6 `QObject` `AudioAnalyzer` with:
  - `analyze(samples: "np.ndarray", sample_rate: int = 48000) -> dict` — pure function returning `{"low": float, "mid": float, "high": float, "energy": float, "beat": bool}`, each band normalized 0..1; `beat` True when energy jumps above a running threshold.
  - Qt properties `low, mid, high, energy: float`, `beat: bool` + `bandsChanged` signal, updated by `push(samples, sample_rate)` which calls `analyze` and stores results.
  - `start()` / `stop()` — open/close a PipeWire monitor capture stream (via `sounddevice`) on a background thread, calling `push` per block. Not unit-tested; verified manually in Task 14.

- [ ] **Step 1: Write the failing test**

```python
# tests/test_audio_analysis.py
import numpy as np
from bigscreen_jukebox.audio_analysis import AudioAnalyzer

def sine(freq, n=4096, sr=48000):
    t = np.arange(n) / sr
    return np.sin(2 * np.pi * freq * t).astype(np.float32)

def test_silence_is_low_energy():
    a = AudioAnalyzer()
    out = a.analyze(np.zeros(4096, dtype=np.float32))
    assert out["energy"] < 0.01
    assert out["beat"] is False

def test_low_tone_loads_low_band():
    a = AudioAnalyzer()
    out = a.analyze(sine(80))
    assert out["low"] > out["high"]

def test_high_tone_loads_high_band():
    a = AudioAnalyzer()
    out = a.analyze(sine(8000))
    assert out["high"] > out["low"]

def test_bands_are_normalized():
    a = AudioAnalyzer()
    out = a.analyze(sine(440) * 10)  # loud
    for k in ("low", "mid", "high", "energy"):
        assert 0.0 <= out[k] <= 1.0

def test_push_updates_properties_and_signal():
    a = AudioAnalyzer()
    seen = []
    a.bandsChanged.connect(lambda: seen.append(a.energy))
    a.push(sine(80) * 5)
    assert a.low >= 0.0
    assert len(seen) == 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_audio_analysis.py -v`
Expected: FAIL — `ModuleNotFoundError: bigscreen_jukebox.audio_analysis`

- [ ] **Step 3: Write minimal implementation**

```python
# src/bigscreen_jukebox/audio_analysis.py
from __future__ import annotations
import numpy as np
from PySide6.QtCore import QObject, Signal, Property

def _band(mag, freqs, lo, hi):
    sel = (freqs >= lo) & (freqs < hi)
    return float(mag[sel].mean()) if sel.any() else 0.0

class AudioAnalyzer(QObject):
    bandsChanged = Signal()

    def __init__(self):
        super().__init__()
        self._low = self._mid = self._high = self._energy = 0.0
        self._beat = False
        self._avg_energy = 0.0

    def analyze(self, samples: np.ndarray, sample_rate: int = 48000) -> dict:
        x = np.asarray(samples, dtype=np.float32)
        if x.ndim > 1:
            x = x.mean(axis=1)
        n = len(x)
        if n == 0:
            return {"low": 0.0, "mid": 0.0, "high": 0.0, "energy": 0.0, "beat": False}
        win = x * np.hanning(n)
        mag = np.abs(np.fft.rfft(win)) / n
        freqs = np.fft.rfftfreq(n, 1.0 / sample_rate)
        low = _band(mag, freqs, 20, 250)
        mid = _band(mag, freqs, 250, 4000)
        high = _band(mag, freqs, 4000, 20000)
        energy = float(np.sqrt(np.mean(x ** 2)))
        norm = lambda v: float(min(1.0, v / 0.1))
        beat = energy > max(0.02, self._avg_energy * 1.3)
        self._avg_energy = 0.9 * self._avg_energy + 0.1 * energy
        return {"low": norm(low), "mid": norm(mid), "high": norm(high),
                "energy": min(1.0, energy), "beat": bool(beat)}

    def push(self, samples: np.ndarray, sample_rate: int = 48000) -> None:
        r = self.analyze(samples, sample_rate)
        self._low, self._mid, self._high = r["low"], r["mid"], r["high"]
        self._energy, self._beat = r["energy"], r["beat"]
        self.bandsChanged.emit()

    def start(self) -> None:
        import sounddevice as sd  # PipeWire monitor source; device chosen in Task 14
        self._stream = sd.InputStream(
            channels=1, samplerate=48000, blocksize=2048,
            callback=lambda indata, frames, t, status: self.push(indata[:, 0], 48000))
        self._stream.start()

    def stop(self) -> None:
        s = getattr(self, "_stream", None)
        if s is not None:
            s.stop(); s.close(); self._stream = None

    low = Property(float, lambda s: s._low, notify=bandsChanged)
    mid = Property(float, lambda s: s._mid, notify=bandsChanged)
    high = Property(float, lambda s: s._high, notify=bandsChanged)
    energy = Property(float, lambda s: s._energy, notify=bandsChanged)
    beat = Property(bool, lambda s: s._beat, notify=bandsChanged)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_audio_analysis.py -v`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add src/bigscreen_jukebox/audio_analysis.py tests/test_audio_analysis.py
git commit -m "feat: audio FFT band/beat analysis"
```

---

## Task 8: QR code utility

**Files:**
- Create: `src/bigscreen_jukebox/qr.py`
- Test: `tests/test_qr.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `qr_data_uri(text: str) -> str` — returns a `data:image/png;base64,...` PNG of a QR code for `text` (used directly as a QML `Image.source`).

- [ ] **Step 1: Write the failing test**

```python
# tests/test_qr.py
import base64
from bigscreen_jukebox.qr import qr_data_uri

def test_returns_png_data_uri():
    uri = qr_data_uri("http://tv.local:8950")
    assert uri.startswith("data:image/png;base64,")
    payload = uri.split(",", 1)[1]
    assert base64.b64decode(payload)[:8] == b"\x89PNG\r\n\x1a\n"

def test_distinct_inputs_differ():
    assert qr_data_uri("a") != qr_data_uri("bbbb")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_qr.py -v`
Expected: FAIL — `ModuleNotFoundError: bigscreen_jukebox.qr`

- [ ] **Step 3: Write minimal implementation**

```python
# src/bigscreen_jukebox/qr.py
from __future__ import annotations
import base64, io
import qrcode

def qr_data_uri(text: str) -> str:
    img = qrcode.make(text)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    b64 = base64.b64encode(buf.getvalue()).decode("ascii")
    return f"data:image/png;base64,{b64}"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_qr.py -v`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add src/bigscreen_jukebox/qr.py tests/test_qr.py
git commit -m "feat: QR code data-URI generation"
```

---

## Task 9: Guest web server

**Files:**
- Create: `src/bigscreen_jukebox/guest_server.py`
- Test: `tests/test_guest_server.py`

**Interfaces:**
- Consumes: `qr_data_uri` (Task 8); an injected callable interface so MA isn't required in tests.
- Produces `GuestServer(search_fn, add_fn, port: int)`:
  - `search_fn: Callable[[str], Awaitable[list[dict]]]` → result rows.
  - `add_fn: Callable[[str], Awaitable[None]]` → enqueue by uri.
  - `make_app() -> aiohttp.web.Application` with routes: `GET /` (mobile page HTML), `GET /api/search?q=` → JSON results, `POST /api/add` `{uri}` → `{"ok": true}`.
  - async `start(host_ip: str) -> str` returns the join URL `http://{host_ip}:{port}`; async `stop()`.
  - `join_url` and `qr_uri` properties for the TV overlay.

- [ ] **Step 1: Write the failing test**

```python
# tests/test_guest_server.py
import pytest
from bigscreen_jukebox.guest_server import GuestServer

@pytest.fixture
def server():
    added = []
    async def search_fn(q): return [{"title": f"hit:{q}", "uri": "u:1"}]
    async def add_fn(uri): added.append(uri)
    s = GuestServer(search_fn, add_fn, port=0)
    s._added = added
    return s

async def test_search_route(server, aiohttp_client):
    client = await aiohttp_client(server.make_app())
    resp = await client.get("/api/search", params={"q": "abba"})
    assert resp.status == 200
    data = await resp.json()
    assert data["results"][0]["title"] == "hit:abba"

async def test_add_route(server, aiohttp_client):
    client = await aiohttp_client(server.make_app())
    resp = await client.post("/api/add", json={"uri": "library://track/9"})
    assert resp.status == 200
    assert (await resp.json())["ok"] is True
    assert server._added == ["library://track/9"]

async def test_index_serves_html(server, aiohttp_client):
    client = await aiohttp_client(server.make_app())
    resp = await client.get("/")
    assert resp.status == 200
    assert "text/html" in resp.headers["Content-Type"]
    assert "Add a song" in await resp.text()
```

Note: `aiohttp_client` fixture comes from `pytest-aiohttp`. Add `pytest-aiohttp>=1.0` to the `dev` deps in `pyproject.toml` as part of Step 3.

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_guest_server.py -v`
Expected: FAIL — `ModuleNotFoundError: bigscreen_jukebox.guest_server`

- [ ] **Step 3: Write minimal implementation**

```python
# src/bigscreen_jukebox/guest_server.py
from __future__ import annotations
from typing import Awaitable, Callable
from aiohttp import web
from .qr import qr_data_uri

PAGE = """<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Add a song</title>
<style>body{font-family:system-ui;background:#0b0b12;color:#fff;margin:0;padding:20px}
h1{font-size:24px}input{width:100%;font-size:22px;padding:16px;border-radius:12px;border:0;margin:12px 0}
.row{display:flex;justify-content:space-between;align-items:center;background:#15151f;padding:16px;border-radius:12px;margin:10px 0}
button{font-size:18px;padding:12px 18px;border:0;border-radius:999px;background:#00e0c6;color:#000}</style></head>
<body><h1>Add a song</h1>
<input id="q" placeholder="Search..." oninput="go()">
<div id="results"></div>
<script>
async function go(){let q=document.getElementById('q').value;if(!q)return;
 let r=await fetch('/api/search?q='+encodeURIComponent(q));let d=await r.json();
 document.getElementById('results').innerHTML=d.results.map(x=>
  `<div class=row><span>${x.title}${x.artist?' — '+x.artist:''}</span>
   <button onclick="add('${x.uri}')">Add</button></div>`).join('');}
async function add(uri){await fetch('/api/add',{method:'POST',headers:{'Content-Type':'application/json'},
 body:JSON.stringify({uri})});}
</script></body></html>"""

class GuestServer:
    def __init__(self, search_fn: Callable[[str], Awaitable[list[dict]]],
                 add_fn: Callable[[str], Awaitable[None]], port: int):
        self._search_fn = search_fn
        self._add_fn = add_fn
        self.port = port
        self.join_url = ""
        self.qr_uri = ""
        self._runner: web.AppRunner | None = None

    def make_app(self) -> web.Application:
        app = web.Application()
        app.add_routes([
            web.get("/", self._index),
            web.get("/api/search", self._search),
            web.post("/api/add", self._add),
        ])
        return app

    async def _index(self, request):
        return web.Response(text=PAGE, content_type="text/html")

    async def _search(self, request):
        q = request.query.get("q", "")
        results = await self._search_fn(q) if q else []
        return web.json_response({"results": results})

    async def _add(self, request):
        body = await request.json()
        await self._add_fn(body["uri"])
        return web.json_response({"ok": True})

    async def start(self, host_ip: str) -> str:
        self._runner = web.AppRunner(self.make_app())
        await self._runner.setup()
        site = web.TCPSite(self._runner, "0.0.0.0", self.port)
        await site.start()
        self.join_url = f"http://{host_ip}:{self.port}"
        self.qr_uri = qr_data_uri(self.join_url)
        return self.join_url

    async def stop(self) -> None:
        if self._runner is not None:
            await self._runner.cleanup()
            self._runner = None
            self.join_url = ""
            self.qr_uri = ""
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pip install -e ".[dev]" && pytest tests/test_guest_server.py -v`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add src/bigscreen_jukebox/guest_server.py tests/test_guest_server.py pyproject.toml
git commit -m "feat: embedded guest web server (search + add to queue)"
```

---

## Task 10: QML theme + app shell

**Files:**
- Create: `qml/Theme.qml`, `qml/main.qml`
- Modify: `src/bigscreen_jukebox/__main__.py` (create)

**Interfaces:**
- Consumes: `Theme` singleton values; later screen tasks fill in the tab bodies.
- Produces: a runnable app window with a focusable tab bar and a `StackLayout` of four placeholder pages, navigable by Left/Right (or remote) and number keys; a `Theme.qml` singleton exposing color/size tokens copied from `mockups/styles.css`.

This and the remaining QML tasks are verified by running the app and looking, per the spec's UI testing strategy.

- [ ] **Step 1: Create the Theme singleton**

```qml
// qml/Theme.qml
pragma Singleton
import QtQuick
QtObject {
    readonly property color bg: "#0b0b12"
    readonly property color panel: "#15151f"
    readonly property color fg: "#ffffff"
    readonly property color muted: "#a0a0b0"
    readonly property color accent: "#00e0c6"
    readonly property color accent2: "#ff3da6"
    readonly property int xxl: 84
    readonly property int xl: 56
    readonly property int lg: 40
    readonly property int md: 30
    readonly property int sm: 24
    readonly property int pad: 64
    readonly property int radius: 24
}
```

Add `qml/qmldir` so the singleton resolves:

```
singleton Theme 1.0 Theme.qml
```

- [ ] **Step 2: Create the app shell**

```qml
// qml/main.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: win
    visible: true
    visibility: Window.FullScreen
    color: Theme.bg
    property var tabs: ["Now Playing", "Search", "Lyrics", "Visualizer"]

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {                                   // tab bar
            Layout.fillWidth: true
            Layout.margins: 32
            spacing: 48
            Repeater {
                model: win.tabs
                Text {
                    text: modelData
                    font.pixelSize: Theme.md
                    color: stack.currentIndex === index ? Theme.fg : Theme.muted
                    MouseArea { anchors.fill: parent; onClicked: stack.currentIndex = index }
                }
            }
        }

        StackLayout {
            id: stack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: 0
            Rectangle { color: "transparent"; Text { anchors.centerIn: parent; color: Theme.fg; text: "Now Playing"; font.pixelSize: Theme.xl } }
            Rectangle { color: "transparent"; Text { anchors.centerIn: parent; color: Theme.fg; text: "Search"; font.pixelSize: Theme.xl } }
            Rectangle { color: "transparent"; Text { anchors.centerIn: parent; color: Theme.fg; text: "Lyrics"; font.pixelSize: Theme.xl } }
            Rectangle { color: "transparent"; Text { anchors.centerIn: parent; color: Theme.fg; text: "Visualizer"; font.pixelSize: Theme.xl } }
        }
    }

    focus: true
    Keys.onRightPressed: stack.currentIndex = Math.min(stack.currentIndex + 1, tabs.length - 1)
    Keys.onLeftPressed: stack.currentIndex = Math.max(stack.currentIndex - 1, 0)
    Keys.onDigit1Pressed: stack.currentIndex = 0
    Keys.onDigit2Pressed: stack.currentIndex = 1
    Keys.onDigit3Pressed: stack.currentIndex = 2
    Keys.onDigit4Pressed: stack.currentIndex = 3
}
```

- [ ] **Step 3: Create the entry point**

```python
# src/bigscreen_jukebox/__main__.py
from __future__ import annotations
import sys
from pathlib import Path
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

QML_DIR = Path(__file__).resolve().parent.parent.parent / "qml"

def main() -> int:
    app = QGuiApplication(sys.argv)
    engine = QQmlApplicationEngine()
    engine.addImportPath(str(QML_DIR))
    engine.load(QML_DIR / "main.qml")
    if not engine.rootObjects():
        return 1
    return app.exec()

if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run the app and verify**

Run: `python -m bigscreen_jukebox`
Expected: fullscreen window; tab bar highlights the active tab; Left/Right and keys 1–4 switch the four placeholder pages. Close with Alt+F4 / window controls.

- [ ] **Step 5: Commit**

```bash
git add qml/Theme.qml qml/qmldir qml/main.qml src/bigscreen_jukebox/__main__.py
git commit -m "feat: QML theme singleton and tabbed app shell"
```

---

## Task 11: Wire backend objects into QML + Now Playing screen

**Files:**
- Create: `qml/NowPlaying.qml`
- Modify: `src/bigscreen_jukebox/__main__.py`, `qml/main.qml`

**Interfaces:**
- Consumes: `MaClient` (Tasks 5–6), `Settings` (Task 3).
- Produces: `maClient` exposed to QML as a context property; the Now Playing page bound to it with art, title/artist, progress, transport controls, and a player picker.

- [ ] **Step 1: Expose MaClient + settings to QML (edit __main__.py)**

```python
# add imports
from PySide6.QtCore import QUrl
from .config import load_settings, default_config_path
from .ma_client import MaClient

# inside main(), after creating engine, before load():
    settings = load_settings(default_config_path())
    ma = MaClient(settings)
    engine.rootContext().setContextProperty("maClient", ma)
```

(Live `await ma.connect()` is added with the asyncio/qasync loop in Task 14; until then the UI binds to default/empty state.)

- [ ] **Step 2: Create NowPlaying.qml**

```qml
// qml/NowPlaying.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.pad
        spacing: 80
        Rectangle {                                   // album art
            Layout.preferredWidth: 560; Layout.preferredHeight: 560
            radius: Theme.radius; color: Theme.panel
            Image { anchors.fill: parent; source: maClient.artUrl; fillMode: Image.PreserveAspectCrop }
        }
        ColumnLayout {
            spacing: 12
            Text { text: maClient.trackTitle || "Nothing playing"; color: Theme.fg
                   font.pixelSize: Theme.xxl; font.bold: true }
            Text { text: maClient.trackArtist; color: Theme.muted; font.pixelSize: Theme.xl }
            Text { text: maClient.trackAlbum; color: Theme.muted; font.pixelSize: Theme.md }

            ProgressBar {
                Layout.topMargin: 40; Layout.preferredWidth: 900
                from: 0; to: Math.max(1, maClient.durationMs); value: maClient.positionMs
            }

            RowLayout {
                Layout.topMargin: 40; spacing: 32
                Button { text: "⏮"; font.pixelSize: Theme.lg; onClicked: maClient.previous() }
                Button { text: maClient.isPlaying ? "⏸" : "▶"; font.pixelSize: Theme.lg; onClicked: maClient.playPause() }
                Button { text: "⏭"; font.pixelSize: Theme.lg; onClicked: maClient.next() }
                Slider { from: 0; to: 100; value: maClient.volume
                         onMoved: maClient.setVolume(Math.round(value)) }
            }

            ComboBox {
                Layout.topMargin: 24
                model: maClient.players
                textRole: "name"
                onActivated: maClient.select_player(maClient.players[currentIndex].id)
            }
        }
    }
}
```

- [ ] **Step 3: Mount NowPlaying in the shell (edit main.qml)**

Replace the first `Rectangle { ... "Now Playing" ... }` placeholder inside `StackLayout` with:

```qml
            NowPlaying { }
```

- [ ] **Step 4: Run the app and verify**

Run: `python -m bigscreen_jukebox`
Expected: Now Playing tab shows the layout (empty state "Nothing playing" until connected); buttons and sliders render and are clickable without errors in the console.

- [ ] **Step 5: Commit**

```bash
git add qml/NowPlaying.qml qml/main.qml src/bigscreen_jukebox/__main__.py
git commit -m "feat: expose MaClient to QML and build Now Playing screen"
```

---

## Task 12: Search & Lyrics screens

**Files:**
- Create: `qml/Search.qml`, `qml/Lyrics.qml`
- Modify: `qml/main.qml`

**Interfaces:**
- Consumes: `maClient.searchResults`, `maClient.searchAsync`, `maClient.playNow`, `maClient.addToQueue`, `maClient.lyricsJson`, `maClient.positionMs`.
- Produces: Search screen (text field + result rows) and Lyrics screen (karaoke highlight driven by `lyricsJson` + `positionMs`).

- [ ] **Step 1: Create Search.qml**

```qml
// qml/Search.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    ColumnLayout {
        anchors.fill: parent; anchors.margins: Theme.pad; spacing: 32
        TextField {
            id: q; Layout.fillWidth: true
            placeholderText: "Search..."; font.pixelSize: Theme.xl
            background: Rectangle { color: Theme.panel; radius: Theme.radius }
            onAccepted: maClient.searchAsync(text)
        }
        ListView {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 24; clip: true
            model: maClient.searchResults
            delegate: Rectangle {
                width: ListView.view.width; height: 168
                radius: Theme.radius; color: Theme.panel
                RowLayout {
                    anchors.fill: parent; anchors.margins: 24; spacing: 32
                    Rectangle { width: 120; height: 120; radius: 12; color: Theme.bg
                        Image { anchors.fill: parent; source: modelData.image; fillMode: Image.PreserveAspectCrop } }
                    ColumnLayout {
                        Text { text: modelData.title; color: Theme.fg; font.pixelSize: Theme.lg; font.bold: true }
                        Text { text: modelData.artist + (modelData.album ? " · " + modelData.album : "")
                               color: Theme.muted; font.pixelSize: Theme.md }
                    }
                    Item { Layout.fillWidth: true }
                    Button { text: "Play"; font.pixelSize: Theme.md; onClicked: maClient.playNow(modelData.uri) }
                    Button { text: "Queue"; font.pixelSize: Theme.md; onClicked: maClient.addToQueue(modelData.uri) }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Create Lyrics.qml**

```qml
// qml/Lyrics.qml
import QtQuick
import QtQuick.Controls

Item {
    property var lyrics: JSON.parse(maClient.lyricsJson)
    Connections { target: maClient; function onLyricsJsonChanged() { lyrics = JSON.parse(maClient.lyricsJson) } }

    function currentIndex(posMs) {
        if (!lyrics.synced) return -1
        var idx = -1
        for (var i = 0; i < lyrics.lines.length; i++) {
            if (lyrics.lines[i].time_ms !== null && lyrics.lines[i].time_ms <= posMs) idx = i
            else break
        }
        return idx
    }

    ListView {
        id: list
        anchors.fill: parent
        model: lyrics.lines
        property int active: currentIndex(maClient.positionMs)
        Connections { target: maClient; function onPositionMsChanged() { list.active = list.currentIndex = currentIndex(maClient.positionMs) } }
        preferredHighlightBegin: height / 2 - 60
        preferredHighlightEnd: height / 2 + 60
        highlightRangeMode: ListView.StrictlyEnforceRange
        delegate: Text {
            width: ListView.view.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: modelData.text
            color: index === list.active ? Theme.accent : Theme.muted
            font.pixelSize: index === list.active ? Theme.xxl : Theme.lg
            font.bold: index === list.active
            Behavior on font.pixelSize { NumberAnimation { duration: 150 } }
        }
        Text {
            anchors.centerIn: parent; visible: lyrics.lines.length === 0
            text: "No lyrics found"; color: Theme.muted; font.pixelSize: Theme.xl
        }
    }
}
```

- [ ] **Step 3: Mount both in the shell (edit main.qml)**

Replace the Search and Lyrics placeholder `Rectangle`s in `StackLayout` with:

```qml
            Search { }
            Lyrics { }
```

- [ ] **Step 4: Run the app and verify**

Run: `python -m bigscreen_jukebox`
Expected: Search tab renders the field + empty list; Lyrics tab shows "No lyrics found" with empty state (no console errors). Full data appears once connected (Task 14).

- [ ] **Step 5: Commit**

```bash
git add qml/Search.qml qml/Lyrics.qml qml/main.qml
git commit -m "feat: Search and karaoke Lyrics screens"
```

---

## Task 13: Visualizer screen + guest overlay

**Files:**
- Create: `qml/Visualizer.qml`, `qml/GuestOverlay.qml`
- Modify: `qml/main.qml`, `src/bigscreen_jukebox/__main__.py`

**Interfaces:**
- Consumes: `audioAnalyzer` (Task 7) and `guestController` (a thin QObject wrapping `GuestServer`, added here) as context properties.
- Produces: a fullscreen `Canvas` visualizer driven by `audioAnalyzer` bands/beat, and a top-right guest overlay showing the QR + URL when guest mode is enabled, toggled by the `G` key.

- [ ] **Step 1: Add audioAnalyzer + guestController context properties (edit __main__.py)**

```python
# add imports
from PySide6.QtCore import QObject, Signal, Property, Slot
from .audio_analysis import AudioAnalyzer
from .guest_server import GuestServer

class GuestController(QObject):
    enabledChanged = Signal()
    def __init__(self, ma, settings):
        super().__init__(); self._ma = ma; self._settings = settings
        self._enabled = False; self._url = ""; self._qr = ""
        self._server = None
    @Slot()
    def toggle(self):
        # Live start/stop is driven from the asyncio loop in Task 14; here we flip state.
        self._enabled = not self._enabled
        self.enabledChanged.emit()
    enabled = Property(bool, lambda s: s._enabled, notify=enabledChanged)
    joinUrl = Property(str, lambda s: s._url, notify=enabledChanged)
    qrUri = Property(str, lambda s: s._qr, notify=enabledChanged)

# inside main(), after creating ma:
    analyzer = AudioAnalyzer()
    guest = GuestController(ma, settings)
    engine.rootContext().setContextProperty("audioAnalyzer", analyzer)
    engine.rootContext().setContextProperty("guestController", guest)
```

- [ ] **Step 2: Create Visualizer.qml**

```qml
// qml/Visualizer.qml
import QtQuick

Item {
    Rectangle { anchors.fill: parent; color: "#000000" }
    Canvas {
        id: canvas; anchors.fill: parent
        property int bars: 48
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var w = width / bars
            var base = audioAnalyzer.energy
            for (var i = 0; i < bars; i++) {
                var f = i / bars
                var band = f < 0.33 ? audioAnalyzer.low : (f < 0.66 ? audioAnalyzer.mid : audioAnalyzer.high)
                var h = (0.1 + band * 0.85) * height * (audioAnalyzer.beat ? 1.0 : 0.85)
                var grad = ctx.createLinearGradient(0, height - h, 0, height)
                grad.addColorStop(0, Theme.accent); grad.addColorStop(1, Theme.accent2)
                ctx.fillStyle = grad
                ctx.fillRect(i * w + 4, height - h, w - 8, h)
            }
        }
    }
    Connections { target: audioAnalyzer; function onBandsChanged() { canvas.requestPaint() } }
    Text {
        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 80
        text: maClient.trackTitle + (maClient.trackArtist ? " · " + maClient.trackArtist : "")
        color: Theme.fg; font.pixelSize: Theme.xl; font.bold: true
    }
}
```

- [ ] **Step 3: Create GuestOverlay.qml**

```qml
// qml/GuestOverlay.qml
import QtQuick
import QtQuick.Layouts

Rectangle {
    visible: guestController.enabled
    width: 240; height: 300; radius: Theme.radius; color: Theme.panel
    ColumnLayout {
        anchors.centerIn: parent; spacing: 12
        Image {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 180; Layout.preferredHeight: 180
            source: guestController.qrUri
        }
        Text { text: "Scan to add songs"; color: Theme.fg; font.pixelSize: Theme.sm
               Layout.alignment: Qt.AlignHCenter }
        Text { text: guestController.joinUrl; color: Theme.muted; font.pixelSize: Theme.sm
               Layout.alignment: Qt.AlignHCenter }
    }
}
```

- [ ] **Step 4: Mount visualizer + overlay + G key (edit main.qml)**

Replace the Visualizer placeholder `Rectangle` with `Visualizer { }`. Add, as the last child of `ApplicationWindow` (so it floats top-right over everything):

```qml
    GuestOverlay {
        anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 40
        z: 100
    }
```

Add to the window's `Keys` handlers:

```qml
    Keys.onPressed: (e) => { if (e.key === Qt.Key_G) guestController.toggle() }
```

- [ ] **Step 5: Run the app and verify**

Run: `python -m bigscreen_jukebox`
Expected: Visualizer tab shows animated bars reacting to `audioAnalyzer` (idle/low until capture starts in Task 14). Pressing `G` toggles the top-right overlay box on/off over all tabs.

- [ ] **Step 6: Commit**

```bash
git add qml/Visualizer.qml qml/GuestOverlay.qml qml/main.qml src/bigscreen_jukebox/__main__.py
git commit -m "feat: fullscreen visualizer and toggleable guest overlay"
```

---

## Task 14: Live integration — asyncio loop, MA connect, audio + guest start/stop

**Files:**
- Modify: `src/bigscreen_jukebox/__main__.py`, `src/bigscreen_jukebox/guest_server.py` (add LAN-IP helper)
- Test: `tests/test_guest_server.py` (add IP helper test)

**Interfaces:**
- Consumes: everything above.
- Produces: a running app that connects to a real MA server via `qasync`, starts audio capture, and starts/stops the guest server when toggled. Wires `GuestController.toggle()` to actually start/stop `GuestServer` using the active player's search/add. Adds `local_ip() -> str` to `guest_server.py`.

- [ ] **Step 1: Write the failing test for the IP helper (add to tests/test_guest_server.py)**

```python
def test_local_ip_returns_dotted_quad():
    from bigscreen_jukebox.guest_server import local_ip
    ip = local_ip()
    parts = ip.split(".")
    assert len(parts) == 4 and all(p.isdigit() for p in parts)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/test_guest_server.py::test_local_ip_returns_dotted_quad -v`
Expected: FAIL — `ImportError: cannot import name 'local_ip'`

- [ ] **Step 3: Implement local_ip (add to guest_server.py)**

```python
import socket

def local_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/test_guest_server.py::test_local_ip_returns_dotted_quad -v`
Expected: PASS

- [ ] **Step 5: Wire the asyncio loop and live start/stop (edit __main__.py)**

```python
# replace QGuiApplication.exec() flow with qasync
import asyncio
import qasync
from .guest_server import GuestServer, local_ip

def main() -> int:
    app = QGuiApplication(sys.argv)
    loop = qasync.QEventLoop(app)
    asyncio.set_event_loop(loop)

    settings = load_settings(default_config_path())
    ma = MaClient(settings)
    analyzer = AudioAnalyzer()
    guest = GuestController(ma, settings)

    engine = QQmlApplicationEngine()
    engine.addImportPath(str(QML_DIR))
    for name, obj in (("maClient", ma), ("audioAnalyzer", analyzer), ("guestController", guest)):
        engine.rootContext().setContextProperty(name, obj)
    engine.load(QML_DIR / "main.qml")
    if not engine.rootObjects():
        return 1

    async def startup():
        try:
            await ma.connect()
        except Exception as e:
            print(f"[warn] MA connect failed: {e}")
        try:
            analyzer.start()
        except Exception as e:
            print(f"[warn] audio capture unavailable: {e}")

    loop.create_task(startup())
    with loop:
        return loop.run_forever()
```

Update `GuestController.toggle()` to start/stop the real server via the loop:

```python
    @Slot()
    def toggle(self):
        import asyncio
        if not self._enabled:
            self._server = GuestServer(
                lambda q: self._ma.searchAsync(q) or [],   # see note below
                self._ma.addToQueue_async,
                self._settings.guest_port)
            async def _go():
                from .guest_server import local_ip
                await self._server.start(local_ip())
                self._url = self._server.join_url; self._qr = self._server.qr_uri
                self._enabled = True; self.enabledChanged.emit()
            asyncio.ensure_future(_go())
        else:
            async def _stop():
                await self._server.stop(); self._server = None
                self._url = ""; self._qr = ""; self._enabled = False; self.enabledChanged.emit()
            asyncio.ensure_future(_stop())
```

Add async helpers to `MaClient` so the guest server gets list results and can enqueue:

```python
    async def search_for_guest(self, query: str) -> list[dict]:
        await self.searchAsync(query)
        return list(self._search_results)

    async def addToQueue_async(self, uri: str) -> None:
        await self._dispatch("play_media", player_id=self._active, uri=uri, enqueue="add")
```

Then point `GuestController` at `self._ma.search_for_guest` and `self._ma.addToQueue_async`.

- [ ] **Step 6: Run the full app against a real MA server and verify**

Run: `python -m bigscreen_jukebox` (with `settings.json` pointing at your MA server)
Verify, and fix the documented unknowns in one place as you go:
1. **Now Playing** reflects the real current track and transport buttons work. *(Confirm the MA event/state schema keys used in `update_from_player_state`; adjust mapping if the real fields differ.)*
2. **Search** returns results and Play/Queue work. *(Confirm `search`/`play_media` command names + the `music_assistant_client` import/API.)*
3. **Lyrics** shows synced lyrics for a track that has them. *(Confirm the lyrics field name on MA media.)*
4. **Visualizer** reacts to audio. *(Pick the correct PipeWire monitor source for `sounddevice`; set it as the input device.)*
5. **Guest**: press `G`, scan the QR on a phone, search, add — song lands in the queue; press `G` again, server stops.

- [ ] **Step 7: Commit**

```bash
git add src/bigscreen_jukebox/__main__.py src/bigscreen_jukebox/ma_client.py src/bigscreen_jukebox/guest_server.py tests/test_guest_server.py
git commit -m "feat: live integration (qasync loop, MA connect, audio + guest start/stop)"
```

---

## Task 15: Settings screen + Bigscreen packaging

**Files:**
- Create: `qml/SettingsView.qml`, `packaging/org.bigscreen.jukebox.desktop`
- Modify: `qml/main.qml`, `src/bigscreen_jukebox/__main__.py`, `README.md`

**Interfaces:**
- Consumes: `Settings`, `save_settings` (Task 3); the context objects.
- Produces: an in-app settings screen (MA host/port/token, default player, guest port) that saves to disk, and a Bigscreen launcher `.desktop` entry so the app appears as a tile.

- [ ] **Step 1: Expose a settings controller (edit __main__.py)**

```python
class SettingsController(QObject):
    def __init__(self, settings): super().__init__(); self._s = settings
    @Slot(str, int, str, int)
    def save(self, host, port, token, guest_port):
        self._s.ma_host = host; self._s.ma_port = port
        self._s.ma_token = token; self._s.guest_port = guest_port
        save_settings(self._s, default_config_path())

# in main(): engine.rootContext().setContextProperty("settingsController", SettingsController(settings))
# import save_settings alongside load_settings
```

- [ ] **Step 2: Create SettingsView.qml**

```qml
// qml/SettingsView.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    ColumnLayout {
        anchors.centerIn: parent; spacing: 24; width: 900
        Text { text: "Settings"; color: Theme.fg; font.pixelSize: Theme.xl; font.bold: true }
        TextField { id: host; placeholderText: "MA host"; text: "localhost"; font.pixelSize: Theme.md; Layout.fillWidth: true }
        TextField { id: port; placeholderText: "MA port"; text: "8095"; font.pixelSize: Theme.md; Layout.fillWidth: true }
        TextField { id: token; placeholderText: "MA token (optional)"; font.pixelSize: Theme.md; Layout.fillWidth: true }
        TextField { id: gport; placeholderText: "Guest port"; text: "8950"; font.pixelSize: Theme.md; Layout.fillWidth: true }
        Button {
            text: "Save"; font.pixelSize: Theme.md
            onClicked: settingsController.save(host.text, parseInt(port.text), token.text, parseInt(gport.text))
        }
    }
}
```

- [ ] **Step 3: Add a fifth tab (edit main.qml)**

Add `"Settings"` to `win.tabs`, append `SettingsView { }` as the last `StackLayout` child, and add `Keys.onDigit5Pressed: stack.currentIndex = 4`.

- [ ] **Step 4: Create the Bigscreen launcher entry**

```ini
# packaging/org.bigscreen.jukebox.desktop
[Desktop Entry]
Type=Application
Name=Bigscreen Jukebox
Comment=Music Assistant on the big screen
Exec=python -m bigscreen_jukebox
Icon=multimedia-player
Categories=AudioVideo;Audio;Player;
X-KDE-FormFactor=mediacenter,tv
```

- [ ] **Step 5: Run, save settings, and verify packaging**

Run: `python -m bigscreen_jukebox`, open Settings, change host, Save; confirm `settings.json` is written under the XDG config dir. Then copy the `.desktop` file to `~/.local/share/applications/` and confirm the app appears/launches from the Bigscreen home grid. Document these steps in `README.md`.

- [ ] **Step 6: Commit**

```bash
git add qml/SettingsView.qml qml/main.qml src/bigscreen_jukebox/__main__.py packaging/ README.md
git commit -m "feat: settings screen and Bigscreen launcher packaging"
```

---

## Self-Review notes (covered)

- **Spec coverage:** native QML/Kirigami (T10–T15), direct MA WS (T5–T6, T14), PipeWire+FFT visualizer (T7, T13), MA-sourced synced lyrics (T4, T12), guest QR→phone→queue with top-right toggle (T8–T9, T13–T14), tabbed screens (T10), default+switchable player (T5, T11), full transport (T6, T11), straight-to-queue guest add (T9), settings (T3, T15), 10-foot styling + visual mockups (T2, T10).
- **Deferred unknowns** from the spec's Open Questions are all resolved against a real server in **Task 14, Step 6**, with the exact mapping points called out (MA state schema, command names, client import, lyrics field, PipeWire source). Each is isolated to one place so a single edit fixes it.
- **Type consistency:** property/method names (`update_from_player_state`, `searchResults`, `addToQueue`/`addToQueue_async`, `lyricsJson`, `analyze`/`push`, `qr_data_uri`, `GuestServer(search_fn, add_fn, port)`) are used identically across producing and consuming tasks.
