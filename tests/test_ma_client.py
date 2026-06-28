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
