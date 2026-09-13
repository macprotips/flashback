#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
for argument in "$@"; do
    case "$argument" in
        --prefix=*) ;;
        --prefix) pkg-config --variable=prefix libmikmod ;;
        --version) pkg-config --modversion libmikmod ;;
        --cflags) pkg-config --cflags libmikmod ;;
        --libs) pkg-config --static --libs libmikmod ;;
        *) echo "Unsupported libmikmod-config option: $argument" >&2; exit 1 ;;
    esac
done
