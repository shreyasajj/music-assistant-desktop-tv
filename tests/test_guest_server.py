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

def test_local_ip_returns_dotted_quad():
    from bigscreen_jukebox.guest_server import local_ip
    ip = local_ip()
    parts = ip.split(".")
    assert len(parts) == 4 and all(p.isdigit() for p in parts)
