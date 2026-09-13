#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# vcpkg supplies sdl2.pc rather than sdl2-config. Query only the isolated prefix.
set -eu
for argument in "$@"; do
    case "$argument" in
        --prefix=*) ;;
        --prefix) pkg-config --variable=prefix sdl2 ;;
        --version) pkg-config --modversion sdl2 ;;
        --cflags) pkg-config --cflags sdl2 ;;
        --libs) pkg-config --static --libs sdl2 ;;
        --static-libs) pkg-config --static --libs sdl2 ;;
        *) echo "Unsupported sdl2-config option: $argument" >&2; exit 1 ;;
    esac
done
