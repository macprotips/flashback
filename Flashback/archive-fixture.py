#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Small authored Archive API fixture for download and native UI checks."""
import hashlib
import http.server
import io
import json
import re
import struct
import sys
import time
import urllib.parse
import zipfile
import zlib
from pathlib import Path

HTML = b'''<!doctype html><meta charset="utf-8"><title>Archive Test Game</title><style>body{background:#211d36;color:#e5dcff;font:24px system-ui;text-align:center;padding:70px}button{font:inherit;padding:15px}</style><h1>Back in play.</h1><p id="state">Loading...</p><button onclick="window.archiveMoves++;document.querySelector('#state').textContent='Move '+archiveMoves">Move</button><script src="game.js"></script>'''
JS = b"window.archiveMoves=0;fetch('level.json').then(r=>r.json()).then(v=>{window.archiveReady=v.level===1;document.querySelector('#state').textContent='Level '+v.level+' ready';});"

def png():
    def chunk(tag, data):
        return struct.pack('>I', len(data))+tag+data+struct.pack('>I', zlib.crc32(tag+data)&0xffffffff)
    data = b''.join(b'\0'+bytes([110,80,185])*320 for _ in range(180))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',320,180,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(data))+chunk(b'IEND',b'')
ART = png()
FILES = {'play.html':HTML,'game.js':JS,'level.json':b'{"level":1}','cover.png':ART}
stream = io.BytesIO()
with zipfile.ZipFile(stream,'w',zipfile.ZIP_DEFLATED) as z:
    for name, data in FILES.items(): z.writestr(name,data)
ZIP = stream.getvalue()

def item(key, title=None):
    return {'identifier':key,'title':title or 'Archive Test Game','creator':['Flashback fixtures','Local test'],'subject':['Flash','Browser games'],'description':'<p>An authored game for testing <b>offline downloads</b>.</p><p>Includes a script and a level file.</p>','date':'2004-06-01'}

def files(key):
    if key == 'blocked-file': return {'game-18+.swf':b'not a game'}
    if key == 'zip-game': return {'Archive Game.zip':ZIP}
    if key == 'unsupported': return {'installer.exe':b'installer'}
    if key == 'slow-game': return {'slow.swf':b'x'*204800}
    return FILES

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_GET(self):
        split = urllib.parse.urlsplit(self.path); path = urllib.parse.unquote(split.path)
        data = None; mime = 'application/json'
        if path == '/advancedsearch.php':
            query = urllib.parse.parse_qs(split.query); q = query.get('q',[''])[0]
            page = int(query.get('page',['1'])[0]); docs=[]
            if 'offline' in q: self.send_response(503); self.end_headers(); return
            if 'missing-game' not in q:
                docs = [item('test-game'),item('zip-game','Archived ZIP Game'),item('unsupported','Installer Only'),item('slow-game','Slow Download')] if page == 1 else [item('page-two','Second Page')]
            total = 5 if docs else 0
            if 'filter-check' in q:
                docs = [dict(item('blocked-tags'),subject=['Flash','NSFW']),item('blocked-description'),item('blocked-file'),dict(item('ordinary-game'),collection=['softwarelibrary_flash','fav-nsfw_user'])] if page == 1 else [item('page-two')]
            if 'filtered-page' in q:
                docs = [dict(item('blocked-tags'),subject=['NSFW']),item('blocked-description')] if page == 1 else [item('page-two')]
            # Discover's featured list asks for a slice of identifiers by name.
            # Echo back exactly what was asked for so its paging can be checked.
            requested = re.findall(r'identifier:([A-Za-z0-9._-]+)', q)
            if requested:
                docs = [item(name) for name in requested]
                total = len(docs)
            data = {'response':{'numFound':total,'docs':docs}}
        elif path.startswith('/metadata/'):
            key = path.split('/')[-1]
            listing = [{'name':name,'size':str(len(body)),'sha1':hashlib.sha1(body).hexdigest()} for name,body in files(key).items()]
            if key == 'bad-hash': listing[0]['sha1']='0'*40
            listing += [{'name':'../escape.swf','size':'12'},{'name':'secret.swf','size':'12','private':'true'}]
            metadata = item(key)
            if key == 'blocked-description': metadata['description'] = '<p>For adults only. Explicit sexual content.</p>'
            if key == 'blocked-tags': metadata['subject'] = ['Flash','NSFW']
            data = {'metadata':metadata,'files':listing}
        elif path.startswith('/services/img/'):
            data = ART; mime='image/png'
        elif path.startswith('/download/'):
            _,_,key,name = path.split('/',3)
            data = files(key).get(name); mime='text/html' if name.endswith('.html') else 'application/octet-stream'
            if key == 'slow-game' and data:
                self.send_response(200);self.send_header('Content-Length',str(len(data)));self.end_headers()
                try:
                    for offset in range(0,len(data),1024):self.wfile.write(data[offset:offset+1024]);self.wfile.flush();time.sleep(.05)
                except (BrokenPipeError,ConnectionResetError):pass
                return
        if data is None:self.send_response(404);self.end_headers();return
        if isinstance(data,dict):data=json.dumps(data).encode()
        self.send_response(200);self.send_header('Content-Type',mime);self.send_header('Content-Length',str(len(data)));self.end_headers()
        try:self.wfile.write(data)
        except (BrokenPipeError,ConnectionResetError):pass

if __name__ == '__main__':
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
    Path(sys.argv[1]).write_text(f'http://127.0.0.1:{server.server_port}/')
    server.serve_forever()
