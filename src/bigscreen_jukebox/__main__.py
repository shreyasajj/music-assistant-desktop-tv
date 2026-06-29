from __future__ import annotations
import asyncio
import sys
from pathlib import Path
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle
from PySide6.QtCore import QObject, Signal, Property, Slot
from .config import load_settings, save_settings, default_config_path
from .ma_client import MaClient
from .audio_analysis import AudioAnalyzer
from .guest_server import GuestServer, local_ip

QML_DIR = Path(__file__).resolve().parent.parent.parent / "qml"


class GuestController(QObject):
    enabledChanged = Signal()

    def __init__(self, ma, settings):
        super().__init__()
        self._ma = ma
        self._settings = settings
        self._enabled = False
        self._url = ""
        self._qr = ""
        self._server = None

    @Slot()
    def toggle(self):
        if not self._enabled:
            self._server = GuestServer(
                self._ma.search_for_guest,
                self._ma.addToQueue_async,
                self._settings.guest_port)

            async def _go():
                await self._server.start(local_ip())
                self._url = self._server.join_url
                self._qr = self._server.qr_uri
                self._enabled = True
                self.enabledChanged.emit()

            asyncio.ensure_future(_go())
        else:
            async def _stop():
                await self._server.stop()
                self._server = None
                self._url = ""
                self._qr = ""
                self._enabled = False
                self.enabledChanged.emit()

            asyncio.ensure_future(_stop())

    enabled = Property(bool, lambda s: s._enabled, notify=enabledChanged)
    joinUrl = Property(str, lambda s: s._url, notify=enabledChanged)
    qrUri = Property(str, lambda s: s._qr, notify=enabledChanged)


class SettingsController(QObject):
    changed = Signal()

    def __init__(self, settings):
        super().__init__()
        self._s = settings

    @Slot(str, int, str, int, bool, bool, bool, bool, str)
    def save(self, host, port, token, guest_port, lrclib_fallback,
             compact_lyrics, art_pump, viz_behind_lyrics, audio_device):
        self._s.ma_host = host
        self._s.ma_port = port
        self._s.ma_token = token
        self._s.guest_port = guest_port
        self._s.lrclib_fallback = lrclib_fallback
        self._s.compact_lyrics = compact_lyrics
        self._s.art_pump = art_pump
        self._s.viz_behind_lyrics = viz_behind_lyrics
        self._s.audio_device = audio_device
        save_settings(self._s, default_config_path())
        self.changed.emit()

    @staticmethod
    def _input_device_names():
        """Names of capture-capable audio devices, for the Settings picker."""
        try:
            import sounddevice as sd
            names, seen = [], set()
            for d in sd.query_devices():
                n = d.get("name") or ""
                if d.get("max_input_channels", 0) > 0 and n and n not in seen:
                    seen.add(n)
                    names.append(n)
            return names
        except Exception:
            return []

    @Slot(bool)
    def setVizBehindLyrics(self, enabled):
        # Live toggle from the Visualizer screen; persists immediately.
        self._s.viz_behind_lyrics = enabled
        save_settings(self._s, default_config_path())
        self.changed.emit()

    # Readable properties so the Settings screen pre-fills current values
    # instead of showing blank defaults and clobbering a saved token on save.
    host = Property(str, lambda s: s._s.ma_host, notify=changed)
    port = Property(int, lambda s: s._s.ma_port, notify=changed)
    token = Property(str, lambda s: s._s.ma_token, notify=changed)
    guestPort = Property(int, lambda s: s._s.guest_port, notify=changed)
    lrclibFallback = Property(bool, lambda s: s._s.lrclib_fallback, notify=changed)
    compactLyrics = Property(bool, lambda s: s._s.compact_lyrics, notify=changed)
    artPump = Property(bool, lambda s: s._s.art_pump, notify=changed)
    vizBehindLyrics = Property(bool, lambda s: s._s.viz_behind_lyrics, notify=changed)
    audioDevice = Property(str, lambda s: s._s.audio_device, notify=changed)
    # First entry = auto (system monitor); the rest are capture-device names.
    audioDevices = Property("QVariantList",
                            lambda s: ["Auto (system monitor)"] + s._input_device_names(),
                            notify=changed)


def main() -> int:
    # A non-native style is required for the custom control backgrounds in the QML
    # (TextField/Button/ComboBox) to render; the native style ignores them.
    QQuickStyle.setStyle("Basic")
    app = QGuiApplication(sys.argv)

    try:
        import qasync
        loop = qasync.QEventLoop(app)
        asyncio.set_event_loop(loop)
        use_qasync = True
    except ImportError:
        print("[warn] qasync not installed; falling back to QApplication.exec() without asyncio integration")
        use_qasync = False

    settings = load_settings(default_config_path())
    ma = MaClient(settings)
    analyzer = AudioAnalyzer(device=settings.audio_device or None)
    guest = GuestController(ma, settings)

    engine = QQmlApplicationEngine()
    engine.addImportPath(str(QML_DIR))
    settings_ctrl = SettingsController(settings)
    for name, obj in (("maClient", ma), ("audioAnalyzer", analyzer),
                      ("guestController", guest), ("settingsController", settings_ctrl)):
        engine.rootContext().setContextProperty(name, obj)
    engine.load(QML_DIR / "main.qml")
    if not engine.rootObjects():
        return 1

    if use_qasync:
        async def startup():
            try:
                await ma.connect()
            except Exception as e:
                print(f"[warn] MA connect failed: {e}")
            try:
                analyzer.start()
            except Exception as e:
                print(f"[warn] audio capture unavailable: {e}")

            # LRCLIB fallback: when a track changes and MA has no lyrics, fetch them.
            import aiohttp
            from . import lrclib
            http = aiohttp.ClientSession()

            async def fetcher(artist, title, album, duration_ms):
                return await lrclib.fetch_lyrics(http, artist, title, album, duration_ms)

            ma.nowPlayingChanged.connect(
                lambda: asyncio.ensure_future(ma.resolve_lyrics_if_missing(fetcher)))

        loop.create_task(startup())
        with loop:
            return loop.run_forever()
    else:
        return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
