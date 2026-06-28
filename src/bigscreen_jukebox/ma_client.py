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
    nowPlayingChanged = Signal()
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
