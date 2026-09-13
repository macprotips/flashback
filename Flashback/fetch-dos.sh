#!/bin/sh
# Fetch the checksum-pinned universal DOSBox Staging runtime and its source.
# The app launcher supplies a per-game config; this script neither mounts a
# game directory nor launches a game.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
vendor="$root/vendor"
version=0.83.0
runtime_url="https://github.com/dosbox-staging/dosbox-staging/releases/download/v$version/dosbox-staging-macOS-v$version.dmg"
runtime_sha256=d8a771adfb8010fa6b5f7fb5351abfba659273ad01c89f03675a92bdbdae8167
source_url="https://codeload.github.com/dosbox-staging/dosbox-staging/tar.gz/refs/tags/v$version"
source_sha256=9b36be5a666784adaeffa560bd0950691f851a76bdb97e7ae3c989561e91caf3

validate_runtime() {
    app=$1
    binary="$app/Contents/MacOS/dosbox"
    [ -x "$binary" ] || return 1
    [ ! -e "$app/Contents/PlugIns/Nuked-SC55.clap" ] || return 1
    case "$(lipo -archs "$binary")" in
        *arm64*x86_64*|*x86_64*arm64*) ;;
        *) return 1 ;;
    esac
    "$binary" --version | grep -F "dosbox-staging, version $version" >/dev/null
    "$binary" --help | grep -F -- '--conf <config_file>' >/dev/null
    codesign --verify --deep --strict "$app" >/dev/null 2>&1
}

if [ -d "$vendor/dosbox-staging/DOSBox Staging.app" ] && [ -f "$vendor/sources/dosbox-staging-v$version.tar.gz" ]; then
    if printf '%s  %s\n' "$source_sha256" "$vendor/sources/dosbox-staging-v$version.tar.gz" | shasum -a 256 -c -; then
        if validate_runtime "$vendor/dosbox-staging/DOSBox Staging.app"; then
            echo "Verified cached DOSBox Staging $version in $vendor/dosbox-staging"
            exit 0
        fi
        # The external vendor volume does not permit codesign to rewrite nested
        # signatures in place. Re-sign a local copy, then replace this one app.
        cache_stage=$(mktemp -d "${TMPDIR:-/tmp}/flashback-dos-resign.XXXXXX")
        ditto "$vendor/dosbox-staging/DOSBox Staging.app" "$cache_stage/DOSBox Staging.app"
        codesign -d --entitlements :- "$vendor/dosbox-staging/DOSBox Staging.app" >"$cache_stage/entitlements.plist" 2>/dev/null
        rm -rf -- "$cache_stage/DOSBox Staging.app/Contents/PlugIns/Nuked-SC55.clap"
        codesign --force --deep --sign - --entitlements "$cache_stage/entitlements.plist" "$cache_stage/DOSBox Staging.app"
        rm -rf -- "$vendor/dosbox-staging/DOSBox Staging.app"
        ditto "$cache_stage/DOSBox Staging.app" "$vendor/dosbox-staging/DOSBox Staging.app"
        rm -rf -- "$cache_stage"
        if validate_runtime "$vendor/dosbox-staging/DOSBox Staging.app"; then
            echo "Re-signed cached DOSBox Staging $version after removing Nuked-SC55.clap"
            exit 0
        fi
    fi
    echo "Cached DOSBox Staging is incomplete; fetching a fresh verified copy" >&2
fi

stage=$(mktemp -d "${TMPDIR:-/tmp}/flashback-dos.XXXXXX")
mountpoint="$stage/mount"
attached=false
cleanup() {
    if [ "$attached" = true ]; then
        hdiutil detach "$mountpoint" >/dev/null 2>&1 || true
    fi
    rm -rf -- "$stage"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$mountpoint" "$stage/runtime" "$stage/sources"
curl --fail --location --retry 3 --output "$stage/dosbox.dmg" "$runtime_url"
printf '%s  %s\n' "$runtime_sha256" "$stage/dosbox.dmg" | shasum -a 256 -c -
curl --fail --location --retry 3 --output "$stage/dosbox-staging-v$version.tar.gz" "$source_url"
printf '%s  %s\n' "$source_sha256" "$stage/dosbox-staging-v$version.tar.gz" | shasum -a 256 -c -

hdiutil attach -nobrowse -readonly -mountpoint "$mountpoint" "$stage/dosbox.dmg" >/dev/null
attached=true
app="$mountpoint/DOSBox Staging.app"
binary="$app/Contents/MacOS/dosbox"
[ -x "$binary" ] || { echo "DOSBox Staging executable was not found in the official DMG" >&2; exit 1; }
ditto "$app" "$stage/runtime/DOSBox Staging.app"
runtime_app="$stage/runtime/DOSBox Staging.app"
rm -rf -- "$runtime_app/Contents/PlugIns/Nuked-SC55.clap"
codesign -d --entitlements :- "$app" >"$stage/entitlements.plist" 2>/dev/null
codesign --force --deep --sign - --entitlements "$stage/entitlements.plist" "$runtime_app"
validate_runtime "$runtime_app" || { echo "DOSBox Staging validation failed after plug-in removal" >&2; exit 1; }
cp "$runtime_app/Contents/SharedSupport/LICENSE" "$stage/runtime/LICENSE"
hdiutil detach "$mountpoint" >/dev/null
attached=false

mkdir -p "$vendor/sources"
rm -rf -- "$vendor/dosbox-staging"
rm -f -- "$vendor/sources/dosbox-staging-v$version.tar.gz"
mv "$stage/runtime" "$vendor/dosbox-staging"
mv "$stage/dosbox-staging-v$version.tar.gz" "$vendor/sources/dosbox-staging-v$version.tar.gz"
echo "Fetched DOSBox Staging $version to $vendor/dosbox-staging"
