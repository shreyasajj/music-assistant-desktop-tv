import asyncio
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

class _FakePlayers:
    def __init__(self): self.calls = []
    async def play_pause(self, pid): self.calls.append(("play_pause", pid))
    async def next_track(self, pid): self.calls.append(("next", pid))
    async def previous_track(self, pid): self.calls.append(("previous", pid))
    async def seek(self, pid, pos): self.calls.append(("seek", pid, pos))
    async def volume_set(self, pid, lvl): self.calls.append(("volume", pid, lvl))

class _FakeQueues:
    def __init__(self): self.calls = []
    async def play_media(self, queue_id, media, option=None, **k):
        self.calls.append(("play_media", queue_id, media, getattr(option, "value", option)))

class _FakeMusic:
    async def search(self, query, limit=20):
        class R: tracks = []
        return R()

class _FakeSession:
    def __init__(self):
        self.players = _FakePlayers()
        self.player_queues = _FakeQueues()
        self.music = _FakeMusic()

async def test_actions_call_expected_controllers(client):
    fake = _FakeSession()
    client._session = fake
    client._active = "living"
    client.playPause(); client.next(); client.previous()
    client.seek(30000); client.setVolume(40)
    client.playNow("library://track/5"); client.addToQueue("library://track/6")
    await asyncio.sleep(0)
    assert ("play_pause", "living") in fake.players.calls
    assert ("next", "living") in fake.players.calls
    assert ("previous", "living") in fake.players.calls
    assert ("seek", "living", 30) in fake.players.calls            # ms -> seconds
    assert ("volume", "living", 40) in fake.players.calls
    assert ("play_media", "living", "library://track/5", "play") in fake.player_queues.calls
    assert ("play_media", "living", "library://track/6", "add") in fake.player_queues.calls

def test_set_search_results(client):
    seen = []
    client.searchResultsChanged.connect(lambda: seen.append(len(client.searchResults)))
    client.set_search_results([{"title": "T", "artist": "A", "uri": "u"}])
    assert client.searchResults[0]["uri"] == "u"
    assert seen == [1]

def test_select_player_is_qml_invokable(client):
    # QML can only call methods registered as Qt slots; a plain method is invisible.
    from PySide6.QtCore import QMetaMethod
    meta = client.metaObject()
    slots = {meta.method(i).name().data().decode()
             for i in range(meta.methodCount())
             if meta.method(i).methodType() == QMetaMethod.MethodType.Slot}
    assert "select_player" in slots

async def test_resolve_fills_lyrics_when_missing(client):
    client.update_from_player_state({"player_id": "x",
        "current_media": {"title": "T", "artist": "A"}})
    assert json.loads(client.lyricsJson)["lines"] == []
    async def fake(artist, title, album, dur): return "[00:01.00]hi"
    await client.resolve_lyrics_if_missing(fake)
    assert json.loads(client.lyricsJson)["lines"][0]["text"] == "hi"

async def test_resolve_skips_when_lyrics_present(client):
    client.update_from_player_state({"player_id": "x",
        "current_media": {"title": "T", "artist": "A", "lyrics": "[00:01.00]x"}})
    called = False
    async def fake(*a):
        nonlocal called; called = True; return "[00:02.00]y"
    await client.resolve_lyrics_if_missing(fake)
    assert called is False

async def test_resolve_disabled_by_setting():
    from bigscreen_jukebox.ma_client import MaClient
    from bigscreen_jukebox.config import Settings
    c = MaClient(Settings(lrclib_fallback=False))
    c.update_from_player_state({"player_id": "x", "current_media": {"title": "T", "artist": "A"}})
    async def fake(*a): return "[00:01.00]hi"
    await c.resolve_lyrics_if_missing(fake)
    assert json.loads(c.lyricsJson)["lines"] == []

async def test_refresh_reloads_upnext_when_index_changes(client):
    reloads = []
    async def fake_reload(): reloads.append(1)
    client._reload_queue_items = fake_reload

    class _P:
        current_media = None; playback_state = "playing"; volume_level = 50
    class _Q:
        elapsed_time = 0.0; elapsed_time_last_updated = 0.0; current_index = 0
    class _Players:
        def get(self, pid): return _P()
    class _Queues:
        def get(self, pid): return _Q()
    class _Session:
        players = _Players(); player_queues = _Queues()
    client._session = _Session()
    client._active = "p"

    client._refresh()                 # index 0 (was None) -> reload
    await asyncio.sleep(0)
    assert len(reloads) == 1
    client._refresh()                 # same index -> no extra reload
    await asyncio.sleep(0)
    assert len(reloads) == 1
    _Q.current_index = 1              # track advanced
    client._refresh()
    await asyncio.sleep(0)
    assert len(reloads) == 2          # Up Next refreshed on the index change

async def test_reload_queue_reports_true_upcoming_count(client):
    class _Item:
        def __init__(self, n): self.name = n; self.duration = 180; self.media_item = None
    class _Q:
        current_index = 3; items = 15      # 15 in queue, playing #3 -> 11 upcoming
    class _Queues:
        def get(self, qid): return _Q()
        async def get_queue_items(self, qid, limit=100, offset=0):
            return [_Item(f"t{i}") for i in range(max(0, min(limit, 15 - offset)))]
    class _Session:
        player_queues = _Queues()
        def get_media_item_image_url(self, it): return ""
    client._session = _Session()
    client._active = "p"
    await client._reload_queue_items()
    assert client.queueCount == 11          # not capped at the old limit of 10
    assert client.queue[0]["title"] == "t0"

def test_has_party_false_without_session(client):
    assert client.has_party() is False

async def test_party_helpers(client):
    class _Cfg:
        def __init__(self): self.saved = None
        async def save_provider_config(self, domain, values, instance_id=None):
            self.saved = (domain, values, instance_id); return object()
    class _Prov:
        domain = "party"
    class _Cfg2(_Cfg):
        async def get_provider_config_value(self, domain, key):
            assert domain == "party" and key == "enable_guest_access"
            return True
    class _Session:
        def __init__(self): self.config = _Cfg2(); self.providers = [_Prov()]
        async def send_command(self, cmd, **k):
            assert cmd == "party/url"
            return "https://app.music-assistant.io/?join=ABC"
    client._session = _Session()
    assert client.has_party() is True
    assert await client.party_url() == "https://app.music-assistant.io/?join=ABC"
    assert await client.party_set_guest_access(True) is True
    assert client._session.config.saved == ("party", {"enable_guest_access": True}, "party")
    assert await client.party_guest_enabled() is True

async def test_search_slot_populates_results(client):
    class _Artist:
        name = "A"
    class _Album:
        name = "Al"
    class _Track:
        name = "Hit"; uri = "u1"; artists = [_Artist()]; album = _Album()
    class _Results:
        tracks = [_Track()]
    class _Music:
        async def search(self, query, limit=20): return _Results()
    class _Session:
        music = _Music()
        def get_media_item_image_url(self, item): return "i"
    client._session = _Session()
    client.search("anything")          # the QML-callable sync slot
    await asyncio.sleep(0)             # let the scheduled coroutine run
    assert client.searchResults[0]["title"] == "Hit"
    assert client.searchResults[0]["uri"] == "u1"
    assert client.searchResults[0]["artist"] == "A"
    assert client.searchResults[0]["album"] == "Al"
