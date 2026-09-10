#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
cd "$(dirname "$0")"
fixture="$(mktemp -d /tmp/flashback-website-XXXXXX)"
server_pid=''
trap 'if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi; rm -rf "$fixture"' EXIT
python3 website-fixture.py "$fixture/address" &
server_pid=$!
for attempt in 1 2 3 4 5; do [ -s "$fixture/address" ] && break; sleep 1; done
sdk="${SDKROOT:-$(xcrun --show-sdk-path)}"
mkdir -p build
swiftc -sdk "$sdk" Library.swift WebPage.swift WebTransfer.swift WebImport.swift WebRouting.swift WebChecks.swift -o build/website-checks
build/website-checks "$(cat "$fixture/address")"
if [ "${1:-}" = '--ui' ]; then
    ../Flashback.app/Contents/MacOS/Flashback --website-check "$(cat "$fixture/address")html/play.html" "${2:-/tmp/flashback-website-ui}"
fi
