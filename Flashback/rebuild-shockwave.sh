#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Rebuild the patched Director VM/polyfill; retain the pinned companion assets.
set -eu
cd "$(dirname "$0")/.."
project_dir="$PWD"
source_dir="$PWD/vendor/sources/dirplayer"
[ -f "$source_dir/vm-rust/Cargo.lock" ] || { echo 'Run Flashback/fetch-sources.py first.' >&2; exit 1; }
command -v wasm-pack >/dev/null
command -v npm >/dev/null
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
# Build outside the supplied source tree to keep its manifest valid.
ditto "$source_dir" "$build_dir/dirplayer"
cd "$build_dir/dirplayer"
npm ci --ignore-scripts --no-audit --no-fund
cd vm-rust
wasm-pack build --target web --release --no-opt
cd ..
npm exec -- vite build -c vite.config.polyfill.js
mkdir -p "$project_dir/vendor/dirplayer/runtime"
cp dist-polyfill/dirplayer-polyfill.js "$project_dir/vendor/dirplayer/runtime/dirplayer-polyfill.js"
