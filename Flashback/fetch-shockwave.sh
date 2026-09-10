#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
cd "$(dirname "$0")"
download=$(mktemp -d)
trap 'rm -rf "$download"' EXIT
curl --fail --location --output "$download/dirplayer.zip" \
    https://github.com/igorlira/dirplayer-rs/releases/download/v0.8.1/dirplayer-polyfill-0.8.1.zip
printf '%s  %s\n' 6f5000412c50833345a630ade25fb70359dc4e1aae66352c80de7da77542162c "$download/dirplayer.zip" | shasum -a 256 -c -
unzip -q "$download/dirplayer.zip" -d "$download/runtime"
curl --fail --location --output "$download/runtime/LICENSE_DIRPLAYER" \
    https://raw.githubusercontent.com/igorlira/dirplayer-rs/7f632b416b55ec351341feda4db2a444564217aa/LICENSE
printf '%s  %s\n' 3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986 "$download/runtime/LICENSE_DIRPLAYER" | shasum -a 256 -c -
mkdir -p ../vendor/dirplayer/runtime
ditto "$download/runtime" ../vendor/dirplayer/runtime
# The companion Ruffle/Xtra revisions are unchanged. Rebuild the Director
# polyfill from the supplied, patched source after fetching those assets.
./rebuild-shockwave.sh
