#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
cd "$(dirname "$0")/.."
output="${1:-/tmp/flashback-shockwave-check}"
mkdir -p "$output/Fixtures"
output=$(cd "$output" && pwd)
fixtures="$output/Fixtures"
fetch() {
    if [ ! -f "$fixtures/$1" ]; then curl --fail --location --referer "${4:-$2}" --output "$fixtures/$1" "$2"; fi
    printf '%s  %s\n' "$3" "$fixtures/$1" | shasum -a 256 -c -
}
fetch Rapunzel.zip https://themetalbox.com/downloads/rapunzel_153.zip \
    855c495bebc78b6d9ba826ce96e6d7f00f7682d32acd626921846855f982c7d9
fetch Supersonic.zip 'https://archive.org/download/legosupersonicrcgame/Supersonic%20RC.zip' \
    ef33d0c507ab447847803e7aadb0c420a9de4b5d1fc8a7cf62b52fb8babfb23e
fetch Merlin3.zip https://themetalbox.com/downloads/merlin_3_open_065.zip \
    57daeda7e304a86ababfb8c02647dc9008082a09045f7242e5cc5bf7bb295606
fetch Merlin.dcr https://themetalbox.com/dcr/games/merlin_1.dcr \
    6929773973ad606e81c270c026d248dbdaef6813d8b19b045123b2354268d1cc \
    'https://themetalbox.com/index.php?page=merlin_1'
app_bundle="${FLASHBACK_APP:-./Flashback.app}"
app="$app_bundle/Contents/MacOS/Flashback"
# Record which runtime produced this evidence. Every other check writes this,
# and a recorded result is only meaningful next to the build it came from.
runtime=$(shasum -a 256 "$app_bundle/Contents/Resources/Shockwave/dirplayer-polyfill.js" | cut -d' ' -f1)
printf '{\n  "app": "%s",\n  "polyfill_sha256": "%s"\n}\n' \
    "$(cd "$app_bundle" && pwd)" "$runtime" > "$output/Runtime.json"
"$app" --self-check "$fixtures/Rapunzel.zip" rapunzel_153_allInOne_original.dir "$output/Rapunzel"
"$app" --self-check "$fixtures/Supersonic.zip" game.dcr "$output/Supersonic"
"$app" --self-check "$fixtures/Merlin3.zip" merlin_3_open_065_importCreditsTxt.dir "$output/Merlin3"
"$app" --self-check "$fixtures/Merlin.dcr" Merlin.dcr "$output/Merlin1"
# The identical movie without its published embed settings fails during startup.
cp "$fixtures/Merlin.dcr" "$fixtures/Raw.dcr"
if "$app" --self-check "$fixtures/Raw.dcr" Raw.dcr "$output/Missing-parameters"; then
    printf 'FAIL: expected missing-parameter compatibility error was not reported.\n' >&2
    exit 1
fi
python3 - "$output" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
for game in ('Rapunzel', 'Supersonic', 'Merlin3', 'Merlin1'):
    assert (root / game / 'Result.txt').read_text().startswith('PASS:'), game
assert (root / 'Merlin1' / 'Shockwave-Started.png').is_file()
error = json.loads((root / 'Missing-parameters' / 'Timeout-details.txt').read_text())
assert any('goTitle' in text for text in error['errors']), error
assert (root / 'Missing-parameters' / 'Player-failure.png').is_file()
print('PASS: four playable 2D/3D games, recovered parameters, recoverable diagnostics, and a visible failure for missing launch settings; original fixtures remain outside the app')
PY
