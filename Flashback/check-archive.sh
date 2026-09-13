#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
cd "$(dirname "$0")"
fixture="$(mktemp -d /tmp/flashback-archive-XXXXXX)"
server_pid=''
trap 'if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi; rm -rf "$fixture"' EXIT
python3 archive-fixture.py "$fixture/address" &
server_pid=$!
for attempt in 1 2 3 4 5; do [ -s "$fixture/address" ] && break; sleep 1; done
sdk="${SDKROOT:-$(xcrun --show-sdk-path)}"
mkdir -p build
if [ ! -f ../Flashback.app/Contents/Resources/JavaRunner.jar ]; then
    echo 'Build Flashback first; catalog ZIP checks use its bundled archive reader.' >&2
    exit 1
fi
swiftc -sdk "$sdk" Library.swift LegacyImport.swift WebPage.swift WebTransfer.swift WebImport.swift Archive.swift ArchiveChecks.swift -o build/archive-checks
build/archive-checks "$(cat "$fixture/address")"
