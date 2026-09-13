#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Authored local fixtures; no third-party game content."""
import http.server
import json
import struct
import sys
import time
import urllib.parse
import zlib
from pathlib import Path

SWF = b"FWS\x08" + struct.pack("<I", 16) + bytes([8, 0, 0, 12, 1, 0, 0, 0])
BODY = b"soundLibrary.swf\0missing.png\0"
CWS = b"CWS\x09" + struct.pack("<I", len(BODY) + 8) + zlib.compress(BODY)


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        path = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path)
        host = f"http://127.0.0.1:{self.server.server_port}"
        other = f"http://localhost:{self.server.server_port}"
        routes = {
            "/related/primary.html": ("text/html", '<title>The requested game</title><embed src="/flash/main.swf"><a href="other.html">Play another game</a>'),
            "/related/other.html": ("text/html", '<title>A related game</title><embed src="/aaa.dcr" type="application/x-director">'),
            "/portal": ("text/html", '<title>Recovered Flash</title><iframe src="/frame/one.html"></iframe>'),
            "/frame/one.html": ("text/html", '<title>Recovered Flash</title><base href="/flash/"><script src="/loader.js"></script>'),
            "/loader.js": ("application/javascript", "var flashvars={language:'en'};swfobject.embedSWF('/flash/main.swf','game');"),
            "/flash/main.swf": ("application/x-shockwave-flash", CWS),
            "/flash/soundLibrary.swf": ("application/x-shockwave-flash", SWF),
            "/flash/": ("text/html", '<title>Index of /flash/</title><a href="levels/">levels/</a><a href="../">Parent Directory</a>'),
            "/flash/levels/": ("text/html", '<title>Index of /flash/levels/</title><a href="one.json">one.json</a>'),
            "/flash/levels/one.json": ("application/json", '{"level":1}'),
            "/html/play.html": ("text/html", f'''<!doctype html><html><head><meta charset="utf-8"><title>Offline Web Check</title>
              <link rel="stylesheet" href="/html/style.css"></head><body><h1>Recovered. Ready to play.</h1>
              <canvas width="600" height="300"></canvas><p id="status">Loading the recovered game…</p>
              <img src="{other}/remote/shared.png" hidden><script type="module" src="js/game.js"></script>
              <script>window.variantURLs=['{host}/html/data.json?v=1','{host}/html/data.json?v=2'];</script></body></html>'''),
            "/html/style.css": ("text/css", 'body{background:#171c30;color:#f4eee4;font:18px system-ui;text-align:center;margin:36px}h1{font-size:32px}canvas{background:#242c49;border-radius:18px}p{color:#c2b8ea}'),
            "/html/js/game.js": ("application/javascript", '''import {color} from './palette.mjs';
              const level=await(await fetch('/api/level')).json();
              const values=await Promise.all(window.variantURLs.map(async url=>(await(await fetch(url)).json()).value));
              const c=document.querySelector('canvas').getContext('2d');c.fillStyle=color;c.fillRect(270,110,60,80);
              window.websiteCheckReady=level.level===1&&values[0]===1&&values[1]===2;
              document.querySelector('#status').textContent=websiteCheckReady?'Graphics, modules, and both levels recovered.':'Something is missing.';
              window.websiteMoves=0;document.addEventListener('keydown',e=>{if(e.key==='ArrowRight')window.websiteMoves++});'''),
            "/html/js/palette.mjs": ("application/javascript", "export const color='#c1a4ff';"),
            "/api/level": ("application/json", '{"level":1}'),
            "/remote/shared.png": ("image/png", bytes.fromhex("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000b49444154789c636000020000050001a5f645400000000049454e44ae426082")),
            "/dynamic": ("text/html", """<title>Dynamic Game</title><div id="game"></div><script>
              window.swfobject={embedSWF(){document.querySelector('#game').textContent='Flash plug-in required';}};
              setTimeout(()=>{swfobject.embedSWF('/flash/'+'main.'+'swf','game',640,480,'9',null,{language:'dynamic'})},800);</script>"""),
            "/java/applet.html": ("text/html", '<title>Applet Check</title><applet codebase="lib%20space/" code="FixtureApplet" archive="main.jar, helper.jar" width="300" height="180"><param name="level" value="two words"/></applet>'),
            "/java/lib space/main.jar": ("application/java-archive", b"main jar"),
            "/java/lib space/helper.jar": ("application/java-archive", b"helper jar"),
            "/java/direct.jnlp": ("application/x-java-jnlp-file", '<jnlp codebase="lib%20space/"><resources><jar href="main.jar"/><jar href="helper.jar"/></resources><application-desc main-class="FixtureMain"><argument>one</argument><argument>two words</argument></application-desc></jnlp>'),
        }
        if path == "/html/data.json":
            value = int(urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)["v"][0])
            routes[path] = ("application/json", json.dumps({"value": value}))
        if path == "/attachment":
            self.send_response(200); self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Disposition", 'attachment; filename="game.swf"')
            self.send_header("Content-Length", str(len(SWF))); self.end_headers(); self.wfile.write(SWF); return
        if path == "/related-start":
            self.send_response(302); self.send_header("Location", "/related/primary.html"); self.end_headers(); return
        if path in ("/redirect-private", "/redirect"):
            self.send_response(302); self.send_header("Location", "http://127.0.0.1/private" if path.endswith("private") else "/html/play.html"); self.end_headers(); return
        if path == "/denied":
            self.send_response(403); self.end_headers(); return
        if path.startswith("/large-") or path == "/slow":
            self.send_response(200); self.send_header("Content-Type", "application/octet-stream")
            if path.endswith("known"): self.send_header("Content-Length", "4096")
            self.end_headers()
            try:
                for _ in range(200 if path == "/slow" else 4):
                    self.wfile.write(b"x" * 1024); self.wfile.flush()
                    if path == "/slow": time.sleep(.1)
            except (BrokenPipeError, ConnectionResetError): pass
            return
        if path not in routes:
            self.send_response(404); self.end_headers(); return
        mime, data = routes[path]
        if isinstance(data, str): data = data.encode()
        self.send_response(200); self.send_header("Content-Type", mime); self.send_header("Content-Length", str(len(data))); self.end_headers()
        try: self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError): pass


if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    Path(sys.argv[1]).write_text(f"http://127.0.0.1:{server.server_port}/")
    server.serve_forever()
