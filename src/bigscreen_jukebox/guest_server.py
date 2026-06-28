# src/bigscreen_jukebox/guest_server.py
from __future__ import annotations
import socket
from typing import Awaitable, Callable
from aiohttp import web
from .qr import qr_data_uri


def local_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()

PAGE = """<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Add a song</title>
<style>body{font-family:system-ui;background:#0b0b12;color:#fff;margin:0;padding:20px}
h1{font-size:24px}input{width:100%;font-size:22px;padding:16px;border-radius:12px;border:0;margin:12px 0}
.row{display:flex;justify-content:space-between;align-items:center;background:#15151f;padding:16px;border-radius:12px;margin:10px 0}
button{font-size:18px;padding:12px 18px;border:0;border-radius:999px;background:#00e0c6;color:#000}</style></head>
<body><h1>Add a song</h1>
<input id="q" placeholder="Search..." oninput="go()">
<div id="results"></div>
<script>
async function go(){let q=document.getElementById('q').value;if(!q)return;
 let r=await fetch('/api/search?q='+encodeURIComponent(q));let d=await r.json();
 document.getElementById('results').innerHTML=d.results.map(x=>
  `<div class=row><span>${x.title}${x.artist?' — '+x.artist:''}</span>
   <button onclick="add(${JSON.stringify(x.uri)})">Add</button></div>`).join('');}
async function add(uri){await fetch('/api/add',{method:'POST',headers:{'Content-Type':'application/json'},
 body:JSON.stringify({uri})});}
</script></body></html>"""

class GuestServer:
    def __init__(self, search_fn: Callable[[str], Awaitable[list[dict]]],
                 add_fn: Callable[[str], Awaitable[None]], port: int):
        self._search_fn = search_fn
        self._add_fn = add_fn
        self.port = port
        self.join_url = ""
        self.qr_uri = ""
        self._runner: web.AppRunner | None = None

    def make_app(self) -> web.Application:
        app = web.Application()
        app.add_routes([
            web.get("/", self._index),
            web.get("/api/search", self._search),
            web.post("/api/add", self._add),
        ])
        return app

    async def _index(self, request):
        return web.Response(text=PAGE, content_type="text/html")

    async def _search(self, request):
        q = request.query.get("q", "")
        results = await self._search_fn(q) if q else []
        return web.json_response({"results": results})

    async def _add(self, request):
        body = await request.json()
        await self._add_fn(body["uri"])
        return web.json_response({"ok": True})

    async def start(self, host_ip: str) -> str:
        self._runner = web.AppRunner(self.make_app())
        await self._runner.setup()
        site = web.TCPSite(self._runner, "0.0.0.0", self.port)
        await site.start()
        self.join_url = f"http://{host_ip}:{self.port}"
        self.qr_uri = qr_data_uri(self.join_url)
        return self.join_url

    async def stop(self) -> None:
        if self._runner is not None:
            await self._runner.cleanup()
            self._runner = None
            self.join_url = ""
            self.qr_uri = ""
