#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
cd "$(dirname "$0")"
download=$(mktemp -d)
trap 'rm -rf "$download"' EXIT
curl --fail --location --output "$download/ruffle.zip" \
    https://github.com/ruffle-rs/ruffle/releases/download/v0.6.0/ruffle-0.6.0-web-selfhosted.zip
printf '%s  %s\n' e8acfacc37443303872379d0e215999af846854d1dd3fa8fac0a765445b43dbf "$download/ruffle.zip" | shasum -a 256 -c -
unzip -q "$download/ruffle.zip" -d "$download/runtime"
mkdir -p ../vendor/ruffle-web
cp "$download/runtime/"*.js "$download/runtime/"*.wasm "$download/runtime/"LICENSE_* ../vendor/ruffle-web/
