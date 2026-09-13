#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Recover authored Java embeds through HTTP/import and execute offline bytecode."""
import functools
import http.server
import os
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile
import threading
import time

harness, jdk, host, game, policy, runner = sys.argv[1:]
class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args): pass

source = Path(game)
(source/'embed.html').write_text('''<applet codebase="lib%20%2B%25%20space/" code="JavaFormatFixture$LifecycleApplet" archive="game.jar,helper.jar" width="320" height="200"><param name="magic" value="value with spaces"/></applet>''')
server = http.server.ThreadingHTTPServer(('127.0.0.1',0), functools.partial(QuietHandler,directory=game))
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='flashback-java-recovery-') as temporary:
        for index, entry in enumerate(('embed.html','applet.jnlp')):
            imported = subprocess.check_output([harness,f'http://127.0.0.1:{server.server_port}/{entry}',str(Path(temporary)/str(index))],text=True,timeout=40).strip()
            saves = Path(temporary)/f'saves-{index}'; saves.mkdir()
            command = [jdk+'/bin/java','-Djava.security.manager','-Djava.security.policy=='+policy,'-Dflashback.runner='+runner,'-Dflashback.game='+imported,'-Duser.home='+str(saves),'-cp',host,'JavaRunner','--play',imported+'/Flashback-launch.jnlp']
            process = subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
            try:
                data=b''; deadline=time.monotonic()+15
                with selectors.DefaultSelector() as selector:
                    selector.register(process.stdout,selectors.EVENT_READ)
                    while time.monotonic()<deadline and b'FLASHBACK_READY\n' not in data:
                        if not selector.select(max(0,deadline-time.monotonic())): break
                        chunk=os.read(process.stdout.fileno(),65536)
                        if not chunk: break
                        data+=chunk
                assert b'FLASHBACK_READY\n' in data, data.decode(errors='replace')
                process.stdin.close()
                assert process.wait(timeout=8)==0
                assert (saves/'applet.txt').read_text()=='init,start,stop,destroy,'
            finally:
                if process.poll() is None: process.kill(); process.wait(timeout=5)
finally:
    server.shutdown(); server.server_close()
print('PASS: HTTP applet/JNLP recovery, imported descriptor selection, encoded multi-JAR resources, offline execution and lifecycle')
