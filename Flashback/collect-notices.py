#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Preserve dependency notices from the checksum-verified source cache."""
import hashlib
import json
from pathlib import Path
import tarfile
import tomllib

ROOT = Path(__file__).resolve().parent
SOURCES = ROOT.parent / 'vendor/sources'

def main():
    records = json.loads((SOURCES / 'MANIFEST.json').read_text())
    # Original JS/TS sources supplement npm's sometimes-transpiled packages.
    records += json.loads((SOURCES / 'JAVASCRIPT-SOURCES.json').read_text())
    texts, packages = {}, []
    seen = set()
    for record in records:
        if 'path' not in record: continue
        archive = SOURCES / record['path']
        if archive in seen: continue
        seen.add(archive)
        assert hashlib.sha256(archive.read_bytes()).hexdigest() == record['sha256'], archive
        entry = dict(record)
        entry['notices'] = []
        with tarfile.open(archive) as source:
            for member in source:
                if not member.isfile(): continue
                parts = Path(member.name).parts
                name = parts[-1].lower()
                # Preserve nested notices as well as top-level ones.
                if name.startswith(('license', 'licence', 'unlicense', 'copying', 'copyright', 'notice', 'authors')) and member.size < 2_000_000:
                    text = source.extractfile(member).read().decode('utf-8', errors='replace')
                    digest = hashlib.sha256(text.encode()).hexdigest()
                    texts[digest] = text
                    entry['notices'].append(dict(file=member.name, text=digest))
                if len(parts) == 2 and name in ('package.json', 'cargo.toml'):
                    raw = source.extractfile(member).read().decode('utf-8')
                    data = json.loads(raw) if name == 'package.json' else tomllib.loads(raw).get('package', {})
                    for key in ('name', 'version', 'license', 'licenses', 'license-file', 'author', 'authors', 'repository', 'homepage'):
                        if key in data: entry[key] = data[key]
                if len(parts) == 2 and name.startswith('readme') and member.size < 500_000:
                    text = source.extractfile(member).read().decode('utf-8', errors='replace')
                    # Some older npm packages place the complete grant in README.
                    import re
                    match = re.search(r'^#+\s+(?:License|Copyright)\b', text, flags=re.M | re.I)
                    if match:
                        text = text[match.start():]
                        digest = hashlib.sha256(text.encode()).hexdigest()
                        texts[digest] = text
                        entry['notices'].append(dict(file=member.name, text=digest))
        packages.append(entry)
    output = ROOT / 'Licenses'
    output.mkdir(exist_ok=True)
    (output / 'DEPENDENCIES.json').write_text(json.dumps(packages, indent=2) + '\n')
    with (output / 'DEPENDENCIES.txt').open('w') as stream:
        stream.write('FLASHBACK 1.3.1 — UPSTREAM DEPENDENCY CREDITS\n\n'
                     'This inventory covers the supplied engine lockfiles and source cache,\n'
                     'including build/development packages that are not part of the running app.\n'
                     'Upstream authors retain their copyrights and license terms.\n'
                     'Archive paths and checksums are in DEPENDENCIES.json and the source manifest.\n'
                     'Repeated license texts are stored once below and referenced by SHA-256.\n'
                     'The original archives retain all source files and their notices.\n\n')
        for package in packages:
            stream.write(f"\n{package['name']} {package.get('version', package.get('revision', ''))}\n")
            stream.write(f"Source: {package['url']}\n")
            for key in ('license', 'licenses', 'license-file', 'author', 'authors', 'repository'):
                if key in package: stream.write(f'{key}: {package[key]}\n')
            for notice in package['notices']:
                stream.write(f"Notice: {notice['file']} — text {notice['text']}\n")
        for digest, content in texts.items():
            stream.write(f'\n\nLICENSE / NOTICE TEXT {digest}\n' + '-' * 72 + '\n' + content + '\n')
    print(f'Preserved {len(texts)} distinct notice texts for {len(packages)} dependency archives.')

if __name__ == '__main__':
    main()
