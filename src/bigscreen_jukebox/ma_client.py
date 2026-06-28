from __future__ import annotations
import asyncio
import json
from dataclasses import asdict
from PySide6.QtCore import QObject, Signal, Property, Slot
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
    searchResultsChanged = Signal()

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
        self._search_results: list[dict] = []
        self._session = None

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

    async def search_for_guest(self, query: str) -> list[dict]:
        await self.searchAsync(query)
        return list(self._search_results)

    async def addToQueue_async(self, uri: str) -> None:
        await self._dispatch("play_media", player_id=self._active, uri=uri, enqueue="add")

    async def disconnect(self):
        if self._session is not None:
            await self._session.disconnect()
            self._session = None
            self._connected = False
            self.connectedChanged.emit()

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
    searchResults = Property("QVariantList", lambda s: s._search_results, notify=searchResultsChanged)
