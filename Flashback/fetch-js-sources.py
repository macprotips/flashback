#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Include original repository source for the browser players' JS libraries."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import re
import runpy
import urllib.parse
import urllib.request

HELPERS = runpy.run_path(str(Path(__file__).with_name('fetch-sources.py')))
ROOT, download = HELPERS['ROOT'], HELPERS['download']
DIRECT = ['@fortawesome/fontawesome-svg-core', '@fortawesome/free-solid-svg-icons',
          '@fortawesome/react-fontawesome', '@reduxjs/toolkit', '@tanstack/react-virtual',
          '@uidotdev/usehooks', 'classnames', 'flexlayout-react', 'lodash', 'pako',
          'react', 'react-dom', 'react-icons', 'react-redux', 'redux', 'web-vitals']
# Verified public release-tag commits where npm omits gitHead or records a
# private publishing-workspace commit rather than the public source release.
RELEASE_COMMITS = {
    ('FortAwesome/Font-Awesome', '6.4.2'): 'f0c25837a3fe0e03783b939559e088abcbfb3c4b',
    ('babel/babel', '7.22.11'): '13b1113a95e113dbe37831deda6755da9ecb77e6',
    ('reduxjs/redux', '4.2.1'): 'f4b3ab9ac5370c5520d08383c5fc88e1e1c64587',
    ('facebook/react', '16.13.1'): 'da834083cccb6ef942f701c6b6cecc78213196a8',
    ('react-icons/react-icons', '5.5.0'): '7bf8bdd2501871a73b7f85fe853d751f5c0f2fb3',
    ('TanStack/virtual', '3.14.9'): 'ad2e6d0b0edea1c1e268004f0e686a90185b5097',
    ('TanStack/virtual', '3.17.7'): 'ad2e6d0b0edea1c1e268004f0e686a90185b5097',
    ('facebook/regenerator', '0.14.0'): '30771b77fc6132fa97c892e818cd0bc113491abf',
    ('GoogleChromeLabs/wasm-feature-detect', '1.9.0'): '4fc17f1b98620822a5d62e36101f2bcad345025f',
}

def main():
    wanted = set()
    for lock_path, roots in [(ROOT/'dirplayer/package-lock.json', DIRECT),
                             (ROOT/'ruffle/web/package-lock.json', ['wasm-feature-detect']),
                             (ROOT/'dirplayer-ruffle/web/package-lock.json', ['wasm-feature-detect'])]:
        packages = json.loads(lock_path.read_text())['packages']
        visited = set()
        def visit(key):
            if key in visited: return
            visited.add(key)
            package = packages[key]
            name = key.rsplit('node_modules/', 1)[-1]
            if not name.startswith('@types/'):
                wanted.add((name, package['version']))
            for dependency in package.get('dependencies', {}):
                prefix = key
                while True:
                    candidate = (prefix + '/' if prefix else '') + 'node_modules/' + dependency
                    if candidate in packages:
                        visit(candidate)
                        break
                    if not prefix: raise RuntimeError((key, dependency))
                    prefix = prefix.rsplit('/node_modules/', 1)[0] if '/node_modules/' in prefix else ''
        for root in roots: visit('node_modules/' + root)
    def fetch(item):
        name, version = item
        url = 'https://registry.npmjs.org/' + urllib.parse.quote(name, safe='@') + '/' + version
        metadata_path = ROOT/'dependencies/js-repositories'/f'{name.replace("/", "__")}-{version}.json'
        download(url, metadata_path)
        metadata = json.loads(metadata_path.read_text())
        repository = metadata.get('repository', {})
        repository = repository.get('url', '') if isinstance(repository, dict) else repository
        revision = metadata.get('gitHead')
        record = dict(name=name, version=version, metadata=str(metadata_path.relative_to(ROOT)),
                      repository=repository, revision=revision, license=metadata.get('license'))
        match = re.search(r'github\.com[:/]([^/]+/[^/#]+?)(?:\.git)?$', repository.split('#', 1)[0])
        if match:
            revision = RELEASE_COMMITS.get((match[1], version), revision)
            record['revision'] = revision
        if match and revision:
            source_url = f'https://codeload.github.com/{match[1]}/tar.gz/{revision}'
            path = ROOT/'dependencies/js-repositories'/f'{match[1].replace("/", "__")}-{revision}.tar.gz'
            # Multiple packages may refer to one monorepo; fetches are serialized below.
            record.update(url=source_url, path=str(path.relative_to(ROOT)))
        return record
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        records = list(pool.map(fetch, sorted(wanted)))
    for record in records:
        if 'path' in record:
            record['sha256'] = download(record['url'], ROOT/record['path'])
            print('Original JS source:', record['name'], record['version'], flush=True)
        else:
            print('Source package only:', record['name'], record['version'], flush=True)
    (ROOT/'JAVASCRIPT-SOURCES.json').write_text(json.dumps(records, indent=2) + '\n')

if __name__ == '__main__': main()
