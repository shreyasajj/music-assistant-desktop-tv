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

async def test_search_slot_populates_results(client):
    async def fake_dispatch(command, **a):
        assert command == "search"
        return [{"name": "Hit", "artist": "A", "album": "Al", "uri": "u1", "image": "i"}]
    client._dispatch = fake_dispatch
    client.search("anything")          # the QML-callable sync slot
    import asyncio
    await asyncio.sleep(0)             # let the scheduled coroutine run
    assert client.searchResults[0]["title"] == "Hit"
    assert client.searchResults[0]["uri"] == "u1"
