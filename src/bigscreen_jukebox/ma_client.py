from __future__ import annotations
import asyncio
import json
import re
import time
from dataclasses import asdict
from PySide6.QtCore import QObject, Signal, Property, Slot, QTimer
from .config import Settings
from .lyrics import parse_lyrics


def server_url(host: str, port: int) -> str:
    """Build the http(s) base URL the music_assistant_client expects.

    The client converts http->ws and appends /ws itself, so we must hand it an
    http(s) base (not ws://). Accepts a bare IP/host, or one already carrying a
    scheme, and appends the port unless the host already includes one.
    """
    h = (host or "").strip().rstrip("/")
    if h.startswith(("http://", "https://")):
        base = h
    elif h.startswith(("ws://", "wss://")):
        base = "http" + h[2:]          # ws://->http://, wss://->https://
    else:
        base = f"http://{h}"
    if re.search(r":\d+$", base):
        return base
    return f"{base}:{port}"


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
        self._pos = 0            # snapshot position in ms
        self._pos_last = 0.0     # epoch (s) the snapshot was taken; 0 = no live correction
        self._dur = 0
        self._playing = False
        self._volume = 0
        self._queue: list[dict] = []
        self._queue_count = 0    # total upcoming songs (may exceed the fetched list)
        self._cur_index = None   # active queue index; up-next is reloaded when it changes
        self._lyrics_json = json.dumps({"lines": [], "synced": False})
        self._search_results: list[dict] = []
        self._session = None
        self._pos_timer = None

    def _position_ms(self) -> int:
        # MA sends a position snapshot + the wall-clock time it was taken; while
        # playing, the live position is the snapshot plus elapsed real time.
        if self._playing and self._pos_last:
            return int(self._pos + max(0.0, time.time() - self._pos_last) * 1000)
        return int(self._pos)

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

    @Slot(str)
    def select_player(self, player_id: str) -> None:
        if player_id != self._active:
            self._active = player_id
            self.activePlayerIdChanged.emit()
            if self._session is not None:
                self._refresh()
                self._spawn(self._reload_queue_items())

    commandError = Signal(str)

    def _spawn(self, coro) -> None:
        """Schedule a client coroutine on the running loop (QML slots are sync)."""
        try:
            task = asyncio.ensure_future(coro)
        except RuntimeError:
            # No running loop (e.g. unit tests without a live session); drop it.
            if hasattr(coro, "close"):
                coro.close()
            return
        task.add_done_callback(self._on_spawned_done)

    def _on_spawned_done(self, task) -> None:
        if task.cancelled():
            return
        exc = task.exception()
        if exc is not None:
            # e.g. "Playback failed to start" when the target player can't output.
            print(f"[warn] MA command failed: {exc}")
            self.commandError.emit(str(exc))

    def set_search_results(self, items: list[dict]) -> None:
        self._search_results = list(items)
        self.searchResultsChanged.emit()

    @Slot()
    def playPause(self):
        if self._session and self._active:
            self._spawn(self._session.players.play_pause(self._active))

    @Slot()
    def next(self):
        if self._session and self._active:
            self._spawn(self._session.players.next_track(self._active))

    @Slot()
    def previous(self):
        if self._session and self._active:
            self._spawn(self._session.players.previous_track(self._active))

    @Slot(int)
    def seek(self, position_ms: int):
        if self._session and self._active:
            self._spawn(self._session.players.seek(self._active, int(position_ms / 1000)))

    @Slot(int)
    def setVolume(self, level: int):
        if self._session and self._active:
            self._spawn(self._session.players.volume_set(self._active, int(level)))

    @Slot(str)
    def playNow(self, uri: str):
        self._spawn(self._play_media(uri, "play"))

    @Slot(str)
    def addToQueue(self, uri: str):
        self._spawn(self._play_media(uri, "add"))

    async def _play_media(self, uri: str, option: str) -> None:
        if not self._session or not self._active:
            return
        from music_assistant_models.enums import QueueOption
        await self._session.player_queues.play_media(
            self._active, uri, option=QueueOption(option))

    async def connect(self):
        from music_assistant_client import MusicAssistantClient
        url = server_url(self._settings.ma_host, self._settings.ma_port)
        self._session = MusicAssistantClient(url, None, self._settings.ma_token or None)
        await self._session.connect()
        self._connected = True
        self.connectedChanged.emit()
        # start_listening fetches initial state then streams events; run it forever.
        ready = asyncio.Event()
        self._listen_task = asyncio.ensure_future(self._session.start_listening(ready))
        try:
            await asyncio.wait_for(ready.wait(), timeout=15)
        except asyncio.TimeoutError:
            pass
        self._session.subscribe(self._on_event)
        # Tick the progress position between MA's (infrequent) time updates.
        if self._pos_timer is None:
            self._pos_timer = QTimer(self)
            self._pos_timer.setInterval(500)
            self._pos_timer.timeout.connect(self._tick_position)
            self._pos_timer.start()
        self._reload_players()
        if not self._active and self._players:
            self.select_player(self._players[0]["id"])
        self._refresh()
        self._spawn(self._reload_queue_items())

    def _on_event(self, event):
        name = getattr(getattr(event, "event", None), "name", "")
        if name in ("PLAYER_ADDED", "PLAYER_REMOVED", "PLAYER_UPDATED"):
            self._reload_players()
        oid = getattr(event, "object_id", None)
        if name.startswith("QUEUE") or oid == self._active:
            self._refresh()
            if name in ("QUEUE_ADDED", "QUEUE_ITEMS_UPDATED"):
                self._spawn(self._reload_queue_items())

    def _tick_position(self):
        if self._playing and self._pos_last:
            self.positionMsChanged.emit()

    def _reload_players(self):
        if not self._session:
            return
        self._players = [{"id": p.player_id, "name": p.name}
                         for p in self._session.players if getattr(p, "available", True)]
        self.playersChanged.emit()

    def _refresh(self):
        """Read the active player + queue from the client controllers and publish."""
        if not self._session or not self._active:
            return
        p = self._session.players.get(self._active)
        q = self._session.player_queues.get(self._active)
        cm = getattr(p, "current_media", None) if p is not None else None
        new_title = (getattr(cm, "title", "") if cm else "") or ""
        track_changed = new_title != self._title
        if cm:
            self._title = new_title
            self._artist = cm.artist or ""
            self._album = cm.album or ""
            self._art = cm.image_url or ""
            self._dur = int((cm.duration or 0) * 1000)
        else:
            self._title = self._artist = self._album = self._art = ""
            self._dur = 0
        if p is not None:
            st = getattr(p.playback_state, "value", p.playback_state)
            self._playing = (st == "playing")
            self._volume = int(p.volume_level or 0)
        if q is not None and q.elapsed_time is not None:
            self._pos = int(q.elapsed_time * 1000)
            self._pos_last = getattr(q, "elapsed_time_last_updated", 0.0) or time.time()
        elif cm is not None and getattr(cm, "elapsed_time", None) is not None:
            self._pos = int(cm.elapsed_time * 1000)
            self._pos_last = getattr(cm, "elapsed_time_last_updated", 0.0) or time.time()
        else:
            self._pos = 0
            self._pos_last = 0.0
        # MA PlayerMedia carries no lyrics; clear on track change so the LRCLIB
        # fallback (if enabled) re-fetches for the new track.
        if track_changed:
            self._lyrics_json = json.dumps({"lines": [], "synced": False})
            self.lyricsJsonChanged.emit()
        # The queue items list doesn't change when a track advances — only the
        # current index does — so refresh Up Next whenever that pointer moves.
        idx = getattr(q, "current_index", None) if q is not None else None
        if idx != self._cur_index:
            self._cur_index = idx
            self._spawn(self._reload_queue_items())
        for sig in (self.nowPlayingChanged, self.positionMsChanged,
                    self.isPlayingChanged, self.volumeChanged):
            sig.emit()

    async def _reload_queue_items(self):
        if not self._session or not self._active:
            return
        try:
            q = self._session.player_queues.get(self._active)
            cur = q.current_index if (q and q.current_index is not None) else -1
            total = int(getattr(q, "items", 0) or 0)
            start = cur + 1
            items = await self._session.player_queues.get_queue_items(
                self._active, limit=100, offset=start)
        except Exception:
            return
        self._queue = [self._queue_item_dict(it) for it in (items or [])]
        # True upcoming count comes from the queue total, not the fetched slice.
        self._queue_count = max(len(self._queue), max(0, total - start))
        self.queueChanged.emit()

    def _queue_item_dict(self, it) -> dict:
        artist = ""
        mi = getattr(it, "media_item", None)
        arts = getattr(mi, "artists", None) if mi is not None else None
        if arts:
            artist = getattr(arts[0], "name", "") or ""
        img = ""
        try:
            img = self._session.get_media_item_image_url(it) or ""
        except Exception:
            img = ""
        return {"title": getattr(it, "name", "") or "", "artist": artist,
                "duration_ms": int((getattr(it, "duration", 0) or 0) * 1000), "image": img}

    @Slot(str)
    def search(self, query: str) -> None:
        # QML-callable entry point: schedule the async search on the running loop.
        self._spawn(self.searchAsync(query))

    async def searchAsync(self, query: str):
        if not self._session:
            return
        res = await self._session.music.search(query, limit=20)
        items = []
        for t in (getattr(res, "tracks", None) or []):
            arts = getattr(t, "artists", None)
            artist = getattr(arts[0], "name", "") if arts else ""
            album = getattr(getattr(t, "album", None), "name", "") or ""
            try:
                img = self._session.get_media_item_image_url(t) or ""
            except Exception:
                img = ""
            items.append({"title": t.name, "artist": artist, "album": album,
                          "uri": t.uri, "image": img})
        self.set_search_results(items)

    async def search_for_guest(self, query: str) -> list[dict]:
        await self.searchAsync(query)
        return list(self._search_results)

    async def addToQueue_async(self, uri: str) -> None:
        await self._play_media(uri, "add")

    # ── Party plugin (guest access) ──────────────────────────────────────────
    # The MA "party" plugin provides a maintained guest-access UI + QR with rate
    # limiting and (with remote access) off-network access. We prefer it over the
    # built-in guest server when it's installed.
    def has_party(self) -> bool:
        if not self._session:
            return False
        try:
            return any(getattr(p, "domain", None) == "party" for p in self._session.providers)
        except Exception:
            return False

    async def party_url(self) -> str | None:
        """The guest join URL from the party plugin, or None if unavailable/disabled."""
        if not self._session:
            return None
        try:
            return await self._session.send_command("party/url")
        except Exception:
            return None

    async def party_set_guest_access(self, enabled: bool) -> bool:
        """Toggle the party plugin's guest access. Returns True if it was applied."""
        if not self._session:
            return False
        try:
            await self._session.config.save_provider_config(
                "party", {"enable_guest_access": enabled}, instance_id="party")
            return True
        except Exception:
            return False

    async def resolve_lyrics_if_missing(self, fetcher) -> None:
        """If lyrics are empty and the LRCLIB fallback is enabled, fetch via
        `fetcher(artist, title, album, duration_ms) -> str | None`, parse, and update."""
        if not self._settings.lrclib_fallback:
            return
        if json.loads(self._lyrics_json)["lines"]:
            return
        raw = await fetcher(self._artist, self._title, self._album, self._dur)
        if raw:
            self._lyrics_json = json.dumps(asdict(parse_lyrics(raw)))
            self.lyricsJsonChanged.emit()

    async def disconnect(self):
        if self._pos_timer is not None:
            self._pos_timer.stop()
            self._pos_timer = None
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
    positionMs = Property(int, lambda s: s._position_ms(), notify=positionMsChanged)
    durationMs = Property(int, lambda s: s._dur, notify=nowPlayingChanged)
    isPlaying = Property(bool, lambda s: s._playing, notify=isPlayingChanged)
    volume = Property(int, lambda s: s._volume, notify=volumeChanged)
    queue = Property("QVariantList", lambda s: s._queue, notify=queueChanged)
    queueCount = Property(int, lambda s: s._queue_count, notify=queueChanged)
    lyricsJson = Property(str, lambda s: s._lyrics_json, notify=lyricsJsonChanged)
    searchResults = Property("QVariantList", lambda s: s._search_results, notify=searchResultsChanged)
