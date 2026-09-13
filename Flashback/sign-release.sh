#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 'Developer ID Application: Name (TEAMID)'" >&2
    exit 2
fi

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
identity=$1
app="$root/Flashback.app"
dos="$app/Contents/Resources/DOS/DOSBox Staging.app"

[ -d "$app" ] || { echo "Build Flashback.app first." >&2; exit 1; }
case "$identity" in
    'Developer ID Application:'*) ;;
    *) echo "Use a Developer ID Application identity for public distribution." >&2; exit 1 ;;
esac

# Sign changed nested code from the inside out. ScummVM and the Java runtimes
# are unmodified upstream applications and retain their original signatures.
find "$dos/Contents/MacOS/lib" -type f -name '*.dylib' \
    -exec codesign --force --options runtime --timestamp --sign "$identity" '{}' ';'
codesign --force --options runtime --timestamp --sign "$identity" \
    --entitlements "$root/Flashback/DOSBox.entitlements.plist" "$dos"
codesign --force --options runtime --timestamp --sign "$identity" "$app/Contents/MacOS/NativeHost"
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
echo "Developer ID signing verified. Submit the app for notarization before packaging."
