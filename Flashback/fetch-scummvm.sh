#!/bin/sh
# Reuse only the verified source-built runtime; never restore the official DMG.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "$#" -eq 0 ] && [ -d "$root/vendor/scummvm/ScummVM.app" ]; then
    python3 "$root/Flashback/fetch-native-sources.py" --verify-only --require-complete \
        --audit-scummvm-runtime --scummvm-app "$root/vendor/scummvm/ScummVM.app"
    echo "Verified retained-source ScummVM 2026.3.0 runtime"
    exit 0
fi
if [ "$#" -eq 0 ]; then
    : "${SCUMMVM_BUILD_DIR:?Set SCUMMVM_BUILD_DIR to an external scratch directory; see Flashback/Licenses/DOS-SCUMMVM-BUILD.md}"
    set -- --work-dir "$SCUMMVM_BUILD_DIR"
fi
exec python3 "$root/Flashback/build-scummvm.py" "$@" --install
