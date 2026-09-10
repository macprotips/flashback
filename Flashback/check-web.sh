#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
cd "$(dirname "$0")"
project="$(pwd)/.."
fixture="$(mktemp -d /tmp/flashback-web-XXXXXX)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/HTML Check/assets" "$fixture/HTML Check/pages"
cat > "$fixture/HTML Check/pages/play #1.html" <<'HTML'
<!doctype html><html lang="en"><meta charset="utf-8"><title>HTML Game Check</title>
<link rel="stylesheet" href="/assets/style.css">
<main><p>FLASHBACK · HTML5</p><h1>A little space to play.</h1>
<canvas width="720" height="360"></canvas><p id="status">Loading…</p>
<object data="https://example.com/unsupported.swf" type="application/x-shockwave-flash" hidden></object></main>
<script type="module" src="../assets/game.js"></script></html>
HTML
cat > "$fixture/HTML Check/assets/style.css" <<'CSS'
body{margin:0;background:rgb(23,28,48);color:#f4eee4;font:18px system-ui;display:grid;min-height:100vh;place-items:center}main{text-align:center}h1{font-size:36px;margin:15px}p{color:#c2b8ea;font-size:14px;letter-spacing:1px}canvas{border-radius:18px;background:#242c49;max-width:90vw}
CSS
cat > "$fixture/HTML Check/assets/game.js" <<'JS'
import {color} from './palette.mjs';
const config = await (await fetch('/assets/level.json')).json();
const c = document.querySelector('canvas').getContext('2d');
window.moves = 0;
window.keyCount = 0;
function draw(){c.fillStyle='#242c49';c.fillRect(0,0,720,360);for(let i=0;i<40;i++){c.fillStyle=i%3?'#9f97c4':'#eee5c5';c.fillRect((i*137)%710,(i*83)%330,3,3)}c.fillStyle=color;c.beginPath();c.moveTo(360+window.moves*12,130);c.lineTo(330+window.moves*12,210);c.lineTo(390+window.moves*12,210);c.closePath();c.fill();document.querySelector('#status').textContent='Use ← → to move · Your game, right here.'}
document.addEventListener('keydown',e=>{window.keyCount++;if(e.key==='ArrowRight'){window.moves++;draw()}else if(e.key==='ArrowLeft'){window.moves--;draw()}});
draw(); window.checkReady = config.level === 1;
JS
printf '%s\n' 'export const color = "#c1a4ff";' > "$fixture/HTML Check/assets/palette.mjs"
printf '%s\n' '{"level":1}' > "$fixture/HTML Check/assets/level.json"
(cd "$fixture" && /usr/bin/zip -qr "HTML Check.zip" "HTML Check")
"$project/Flashback.app/Contents/MacOS/Flashback" --self-check "$fixture/HTML Check.zip" 'pages/play #1.html' "${1:-/tmp/flashback-html-check}"
