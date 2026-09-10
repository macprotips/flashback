#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Verify or recover unchanged Director launchers from the collection's archives.

Uses the recorded projector_provenance in games.json. Executables are only read
as data. Existing files must match; original archives and movies are preserved.
"""
import hashlib
import json
from pathlib import Path
import struct
import sys
import zipfile


def recover(manifest):
    base = manifest.resolve().parent
    count = 0
    for game in json.loads(manifest.read_text()):
        source = game.get('projector_provenance')
        if not source:
            continue
        archive = (base/'Original Archives'/source['archive']).resolve()
        target = (base/game['entry']).resolve()
        assert archive.is_relative_to(base) and target.is_relative_to(base)
        assert hashlib.sha256(archive.read_bytes()).hexdigest() == source['archive_sha256'], archive
        with zipfile.ZipFile(archive) as files:
            projector = files.read(source['member'])
        start, size = source['offset'], source['size']
        assert start >= 0 and size >= 12 and start+size <= len(projector)
        movie = projector[start:start+size]
        assert movie[:4] == b'XFIR' and movie[8:12] in (b'MDGF', b'39VM')
        assert struct.unpack_from('<I', movie, 4)[0]+8 == size
        assert hashlib.sha256(movie).hexdigest() == game['sha256'], target
        if target.exists():
            assert target.read_bytes() == movie, target
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(movie)
        count += 1
    print(f'Verified {count} archived Director launchers.')


if __name__ == '__main__':
    recover(Path(sys.argv[1]))
