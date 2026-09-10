#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
cd "$(dirname "$0")/.."
mkdir -p vendor/java/liberica
fetch() {
    archive="$1"
    digest="$2"
    destination="$3"
    file="vendor/java/liberica/$archive.tar.gz"
    if [ ! -f "$file" ]; then
        curl -fL --retry 3 "https://github.com/bell-sw/Liberica/releases/download/8u504%2B1/$archive.tar.gz" -o "$file"
    fi
    printf '%s  %s\n' "$digest" "$file" | shasum -a 256 -c -
    if [ "$destination" != source ]; then
        mkdir -p "vendor/java/liberica/$destination"
        tar -xzf "$file" -C "vendor/java/liberica/$destination"
    fi
}
# Same vendor release for binaries and complete source, including native HotSpot.
fetch bellsoft-jdk8u504+1-macos-aarch64 7806c4411d27155651c422a40ab6f5f17d7a48f575cfd932391fa88adc6e37c6 arm64
fetch bellsoft-jre8u504+1-macos-amd64 5f0f636c81c522048de98c7b2d582776d0125f2ca4636e365c114faf5461eeab x86_64
fetch bellsoft-jdk8u504+1-src 037fe8766504a21ed4727599ca5c8af4988232082352d9c596dc2898049f2c42 source
