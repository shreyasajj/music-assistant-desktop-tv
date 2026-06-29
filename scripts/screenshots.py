#!/usr/bin/env python3
"""Render the UI headlessly with mock data — verify QML and (re)generate screenshots.

No display, no Music Assistant server: the real context objects are constructed and
seeded with fake data, then qml/main.qml is loaded offscreen. Use it to:
  * sanity-check the QML (it prints any load warnings and exits non-zero on error)
  * regenerate docs/screenshots/*.png
  * let an AI agent visually self-check a UI change (open the saved PNGs)

Usage:
    python scripts/screenshots.py            # write PNGs to docs/screenshots/
    python scripts/screenshots.py /tmp/out   # ... to a custom dir
    python scripts/screenshots.py --verify    # just load + report warnings, no PNGs
"""
from __future__ import annotations
import json, os, sys
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "src"))

from PySide6.QtGui import QGuiApplication, QWindow
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle
from PySide6.QtCore import QUrl, QTimer, QEventLoop
from PySide6.QtQuick import QQuickItem

from bigscreen_jukebox.config import Settings
from bigscreen_jukebox.ma_client import MaClient
from bigscreen_jukebox.audio_analysis import AudioAnalyzer
from bigscreen_jukebox.__main__ import GuestController, SettingsController

TABS = ["now-playing", "search", "lyrics", "visualizer", "settings"]


def seed(ma: MaClient) -> None:
    ma._players = [{"id": "living", "name": "Living Room TV"}, {"id": "kitchen", "name": "Kitchen"}]
    ma._active = "living"
    ma._title, ma._artist, ma._album = "Neon Tide", "Marisol Vega", "Afterglow"
    ma._dur, ma._pos, ma._volume, ma._playing = 224000, 84000, 70, True
    ma._queue = [
        {"title": "Paper Skylines", "artist": "The Lantern Hours", "duration_ms": 198000},
        {"title": "Slow Dissolve", "artist": "Kaiso", "duration_ms": 251000},
        {"title": "Gold Static", "artist": "Faye Okonkwo", "duration_ms": 176000},
    ]
    ma._queue_count = 11
    ma._search_results = [
        {"title": "Neon Tide", "artist": "Marisol Vega", "album": "Afterglow", "uri": "u1", "image": ""},
        {"title": "Paper Skylines", "artist": "The Lantern Hours", "album": "Cartography", "uri": "u2", "image": ""},
    ]
    ma._lyrics_json = json.dumps({"synced": True, "lines": [
        {"time_ms": 6000, "text": "Lights spill soft across the floor"},
        {"time_ms": 15000, "text": "Another midnight at the door"},
        {"time_ms": 24000, "text": "We were running out of time"},
        {"time_ms": 33000, "text": "Now the silence feels like mine"},
    ]})


def main() -> int:
    args = [a for a in sys.argv[1:]]
    verify_only = "--verify" in args
    out = Path([a for a in args if not a.startswith("--")][0]) if any(
        not a.startswith("--") for a in args) else ROOT / "docs" / "screenshots"

    QQuickStyle.setStyle("Basic")
    app = QGuiApplication(sys.argv)
    settings = Settings()
    ma = MaClient(settings); seed(ma)
    analyzer = AudioAnalyzer()              # energy 0 -> animated simulation
    guest = GuestController(ma, settings)
    sctrl = SettingsController(settings)

    engine = QQmlApplicationEngine()
    engine.addImportPath(str(ROOT / "qml"))
    warnings: list[str] = []
    engine.warnings.connect(lambda ws: [warnings.append(w.toString()) for w in ws])
    for name, obj in (("maClient", ma), ("audioAnalyzer", analyzer),
                      ("guestController", guest), ("settingsController", sctrl)):
        engine.rootContext().setContextProperty(name, obj)
    engine.load(QUrl.fromLocalFile(str(ROOT / "qml" / "main.qml")))

    def settle(ms: int) -> None:
        loop = QEventLoop(); QTimer.singleShot(ms, loop.quit); loop.exec()

    settle(400)
    roots = engine.rootObjects()
    real = [w for w in warnings if "does not support customization" not in w]
    print("ROOT LOADED" if roots else "NO ROOT OBJECTS — main.qml failed to load")
    print(f"{len(real)} load warning(s):")
    for w in real:
        print("  ", w)
    if not roots or real:
        return 1
    if verify_only:
        return 0

    win = roots[0]
    win.setVisibility(QWindow.Visibility.Windowed)
    win.setWidth(1920); win.setHeight(1080)
    stack = next(it for it in win.findChildren(QQuickItem)
                 if it.metaObject().className().startswith("QQuickStackLayout"))
    out.mkdir(parents=True, exist_ok=True)
    settle(400)
    for i, name in enumerate(TABS):
        stack.setProperty("currentIndex", i)
        settle(900)
        win.grabWindow().save(str(out / f"{name}.png"))
        print("saved", out / f"{name}.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
