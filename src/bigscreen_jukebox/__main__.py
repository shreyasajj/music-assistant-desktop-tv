from __future__ import annotations
import asyncio
import os
import signal
import sys
from pathlib import Path
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle
from PySide6.QtCore import QObject, Signal, Property, Slot, QTimer
from .config import load_settings, save_settings, default_config_path
from .ma_client import MaClient
from .audio_analysis import AudioAnalyzer
from .guest_server import GuestServer, local_ip
from .qr import qr_data_uri

def _qml_dir() -> Path:
    # System/Flatpak installs set BIGSCREEN_QML_DIR (e.g. /app/share/.../qml).
    # In a PyInstaller bundle the qml/ folder ships alongside the code
    # (--add-data "qml:qml"); otherwise it's at the repo root.
    env = os.environ.get("BIGSCREEN_QML_DIR")
    if env:
        return Path(env)
    if getattr(sys, "frozen", False):
        return Path(getattr(sys, "_MEIPASS", Path(sys.executable).parent)) / "qml"
    return Path(__file__).resolve().parent.parent.parent / "qml"

QML_DIR = _qml_dir()


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
        self._mode = None      # "party" | "server"
        self._poll_timer = None

    @Slot()
    def toggle(self):
        if not self._enabled:
            asyncio.ensure_future(self._enable())
        else:
            asyncio.ensure_future(self._disable())

    async def _enable(self):
        # Prefer the Music Assistant "party" plugin (maintained guest UI, rate
        # limiting, remote access). Fall back to the built-in guest server.
        if self._ma.has_party():
            applied = await self._ma.party_set_guest_access(True)
            url = await self._ma.party_url() if applied else None
            if url:
                self._url = url
                self._qr = qr_data_uri(url)
                self._mode = "party"
                self._enabled = True
                self.enabledChanged.emit()
                return
        # Fallback: our embedded LAN guest server
        self._server = GuestServer(
            self._ma.search_for_guest, self._ma.addToQueue_async, self._settings.guest_port)
        await self._server.start(local_ip())
        self._url = self._server.join_url
        self._qr = self._server.qr_uri
        self._mode = "server"
        self._enabled = True
        self.enabledChanged.emit()

    async def _disable(self):
        # Turn guest access off everywhere so guests can no longer request anything.
        if self._ma.has_party():
            await self._ma.party_set_guest_access(False)
        if self._server is not None:
            await self._server.stop()
            self._server = None
        self._url = ""
        self._qr = ""
        self._mode = None
        self._enabled = False
        self.enabledChanged.emit()

    async def poll(self):
        """Mirror the party plugin's guest-access state so guest mode enabled from
        anywhere else (the Party dashboard, a phone) shows up here too."""
        if not self._ma.has_party() or self._mode == "server":
            return
        enabled = await self._ma.party_guest_enabled()
        if enabled and not self._enabled:
            url = await self._ma.party_url()
            if url:
                self._url = url
                self._qr = qr_data_uri(url)
                self._mode = "party"
                self._enabled = True
                self.enabledChanged.emit()
        elif not enabled and self._enabled and self._mode == "party":
            self._url = ""
            self._qr = ""
            self._mode = None
            self._enabled = False
            self.enabledChanged.emit()

    def start_polling(self, interval_ms: int = 4000):
        if self._poll_timer is None:
            self._poll_timer = QTimer(self)
            self._poll_timer.setInterval(interval_ms)
            self._poll_timer.timeout.connect(lambda: asyncio.ensure_future(self.poll()))
            self._poll_timer.start()

    def _display_url(self):
        if not self._url:
            return ""
        from urllib.parse import urlparse
        return urlparse(self._url).netloc or self._url

    enabled = Property(bool, lambda s: s._enabled, notify=enabledChanged)
    joinUrl = Property(str, lambda s: s._url, notify=enabledChanged)
    displayUrl = Property(str, lambda s: s._display_url(), notify=enabledChanged)
    qrUri = Property(str, lambda s: s._qr, notify=enabledChanged)


class SettingsController(QObject):
    changed = Signal()

    def __init__(self, settings):
        super().__init__()
        self._s = settings

    saveError = Signal(str)   # emitted when save_settings raises (shown as a console warning)

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
        try:
            save_settings(self._s, default_config_path())
        except Exception as e:
            msg = f"Could not save settings: {e}"
            print(f"[error] {msg}")
            self.saveError.emit(msg)
            return                # don't emit changed if the write failed
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
    # Index 0 = simulated (""), 1 = auto-detect monitor ("__auto__"), rest = device names.
    audioDevices = Property("QVariantList",
                            lambda s: ["Simulated (random beats)", "Auto (output monitor)"]
                                      + s._input_device_names(),
                            notify=changed)


def main() -> int:
    # A non-native style is required for the custom control backgrounds in the QML
    # (TextField/Button/ComboBox) to render; the native style ignores them.
    QQuickStyle.setStyle("Basic")
    app = QGuiApplication(sys.argv)

    # Qt's event loop doesn't call Python's default SIGINT handler, so Ctrl+C
    # has no effect without this. app.quit() triggers a clean shutdown.
    signal.signal(signal.SIGINT, lambda *_: app.quit())

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
    analyzer = AudioAnalyzer(device=settings.audio_device)
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

    # Reconnect MA and restart the audio analyzer whenever settings are saved.
    def _on_settings_changed():
        asyncio.ensure_future(_reconnect_ma())

    async def _reconnect_ma():
        try:
            await ma.disconnect_server()
        except Exception as e:
            print(f"[warn] MA disconnect: {e}")
        try:
            await ma.connect_server()
        except Exception as e:
            print(f"[warn] MA reconnect failed: {e}")
        analyzer.restart(device=settings.audio_device)

    settings_ctrl.changed.connect(_on_settings_changed)

    if use_qasync:
        async def startup():
            try:
                await ma.connect_server()
            except Exception as e:
                print(f"[warn] MA connect failed: {e}")
            try:
                await guest.poll()              # reflect the current party guest state
                guest.start_polling()           # poll (catches enable, which fires no event)
                # PROVIDERS_UPDATED fires on disable/reload -> re-check immediately
                ma.providersUpdated.connect(
                    lambda: asyncio.ensure_future(guest.poll()))
            except Exception as e:
                print(f"[warn] guest state sync failed: {e}")
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
