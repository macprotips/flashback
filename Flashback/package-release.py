#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Verify and package the signed app with its corresponding source."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tarfile
import tempfile
import zipfile

PROJECT = Path(__file__).resolve().parent.parent
SOURCE = PROJECT / 'Flashback'
UPSTREAM = PROJECT / 'vendor/sources'
APP = PROJECT / 'Flashback.app'
VERSION = '1.10.0'
JAVA_SOURCE = PROJECT / 'vendor/java/liberica/bellsoft-jdk8u504+1-src.tar.gz'

def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b''): digest.update(data)
    return digest.hexdigest()

def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True)

def verify():
    resources = APP/'Contents/Resources'
    info = plistlib.loads((APP/'Contents/Info.plist').read_bytes())
    assert info['CFBundleShortVersionString'] == VERSION
    run('codesign', '--verify', '--deep', '--strict', str(APP))
    signature = run('codesign', '-dvv', str(APP)).stderr
    assert 'Authority=Developer ID Application:' in signature, 'Sign with Developer ID before packaging.'
    assert 'runtime' in signature, 'The release must use hardened runtime signing.'
    assert set(run('lipo', '-archs', str(APP/'Contents/MacOS/Flashback')).stdout.split()) == {'arm64', 'x86_64'}
    for source_dir, runtime_dir in [(PROJECT/'vendor/ruffle-web', resources/'Runtime'),
                                    (PROJECT/'vendor/dirplayer/runtime', resources/'Shockwave')]:
        for path in source_dir.rglob('*'):
            if path.is_file(): assert sha256(path) == sha256(runtime_dir/path.relative_to(source_dir)), path
    for arch, original in [('arm64', PROJECT/'vendor/java/liberica/arm64/jdk8u504.jdk/jre'),
                           ('x86_64', PROJECT/'vendor/java/liberica/x86_64/jre8u504.jre')]:
        target = resources/'Java'/arch
        for path in original.rglob('*'):
            if path.is_file(): assert sha256(path) == sha256(target/path.relative_to(original)), path
        for name in ('LICENSE', 'ASSEMBLY_EXCEPTION', 'THIRD_PARTY_README', 'readme.txt', 'release'):
            assert (target/name).is_file(), (arch, name)
    assert sha256(JAVA_SOURCE) == '037fe8766504a21ed4727599ca5c8af4988232082352d9c596dc2898049f2c42'
    for path in APP.rglob('*'):
        if not path.is_file(): continue
        assert path.suffix.lower() not in ('.swf','.dcr','.dir','.dxr','.cct','.cst'), path
        assert path.name not in ('Library.json', 'wiz3.jar', 'game.swf'), path
        assert 'texttwist' not in str(path.relative_to(APP)).lower(), path
    for name in ('BrandArtwork.swift', 'MakeIcon.swift', 'App.swift', 'Player.swift'):
        assert 'play.square.stack' not in (SOURCE/name).read_text(), name
    assert 'systemSymbolName' not in (SOURCE/'MakeIcon.swift').read_text()
    for link in re.findall(r'href="([^"]+)"', (resources/'Licenses.html').read_text()):
        if not link.startswith(('https:', 'http:')): assert (resources/link).is_file(), link
    for name in ('LICENSE', 'SOURCE.md', 'Licenses.html', 'Player.html', 'Shockwave.html', 'Java.policy'):
        assert sha256(SOURCE/name) == sha256(resources/name), name
    for path in (SOURCE/'Licenses').rglob('*'):
        if path.is_file(): assert sha256(path) == sha256(resources/'Licenses'/path.relative_to(SOURCE/'Licenses')), path
    records = json.loads((UPSTREAM/'MANIFEST.json').read_text())
    records += json.loads((UPSTREAM/'JAVASCRIPT-SOURCES.json').read_text())
    checked = set()
    for record in records:
        if 'path' not in record: continue
        path = UPSTREAM/record['path']
        if path in checked: continue
        assert sha256(path) == record['sha256'], path
        checked.add(path)
    required = ['dirplayer/vm-rust/src/lib.rs', 'dirplayer/vm-rust/Cargo.lock',
                'dirplayer/.github/workflows/build.yml', 'dirplayer/xtra-sdk/src/lib.rs',
                'bobba-xtra/src/lib.rs', 'groove-xtra/src/lib.rs',
                'ruffle/Cargo.lock', 'ruffle/web/package-lock.json',
                'dirplayer-ruffle/Cargo.lock', 'dirplayer-ruffle/web/package-lock.json']
    for name in required: assert (UPSTREAM/name).is_file(), name
    for name, digest in json.loads((UPSTREAM/'SOURCE-TREE.json').read_text()).items():
        assert sha256(UPSTREAM/name) == digest, name
    print(f'PASS: signed universal app, matching runtimes, source, notices, branding, and {len(checked)} dependency archives.', flush=True)
    return signature

def main():
    signature = verify()
    notarized = subprocess.run(['xcrun', 'stapler', 'validate', str(APP)], capture_output=True).returncode == 0
    stage = Path(tempfile.mkdtemp(prefix='release-', dir=SOURCE/'build'))
    release = stage/f'Flashback-{VERSION}'
    release.mkdir()
    source_archive = release/f'Flashback-Source-{VERSION}.tar.gz'
    top = f'Flashback-Source-{VERSION}'
    # An explicit allowlist keeps local games, verification images, builds, and
    # unrelated vendor applications out of the public source archive.
    own_files = [p for p in SOURCE.iterdir() if p.is_file() and
                 (p.suffix in ('.swift','.java','.sh','.py','.html','.policy','.plist','.md','.patch') or p.name in ('LICENSE','shockwave-host-probe.json','compatibility-results.json','skeleton-corpus.json','shockwave-galidor-fixtures.json','featured-catalog.json'))]
    source_paths = own_files + [SOURCE/'Licenses', JAVA_SOURCE]
    source_paths += [UPSTREAM/name for name in ('dirplayer','dirplayer-ruffle','bobba-xtra','groove-xtra','ruffle','dependencies',
                                               'MANIFEST.json','JAVASCRIPT-SOURCES.json','SOURCE-TREE.json')]
    def filter_source(member):
        if Path(member.name).name in ('.DS_Store', '.git'): return None
        if '/.git/' in member.name: return None
        member.uid = member.gid = 0
        member.uname = member.gname = ''
        return member
    with tarfile.open(source_archive, 'w:gz', compresslevel=6) as output:
        for path in source_paths:
            output.add(path, arcname=f'{top}/{path.relative_to(PROJECT)}', filter=filter_source)
    with tarfile.open(source_archive) as archive:
        names = archive.getnames()
        assert f'{top}/Flashback/BrandArtwork.swift' in names
        assert f'{top}/Flashback/WebImport.swift' in names
        assert f'{top}/Flashback/WebsiteImportView.swift' in names
        assert f'{top}/Flashback/check-website.sh' in names
        for name in ('Archive.swift','ArchiveView.swift','ArchiveChecks.swift','ArchiveUICheck.swift','archive-fixture.py','check-archive.sh','dirplayer-compat.patch','check-dirplayer-patch.py','rebuild-shockwave.sh','check-shockwave-corpus.py','shockwave-host-probe.json','check-installation.py','check-shockwave-collection.py','inspect-shockwave-skeletons.py','COMPATIBILITY-RESEARCH.md','compatibility-results.json','skeleton-corpus.json'):
            assert f'{top}/Flashback/{name}' in names
        assert f'{top}/vendor/java/liberica/{JAVA_SOURCE.name}' in names
        assert not any('/Flashback/build/' in name or '/java-games/' in name or '/shockwave-games/' in name for name in names)
        assert not any(Path(name).suffix.lower() in ('.swf','.dcr','.dir','.dxr','.cct','.cst') for name in names)
        assert not any('texttwist' in name.lower() for name in names)
    run('ditto', str(APP), str(release/'Flashback.app'))
    for name in ('LICENSE', 'SOURCE.md', 'DISTRIBUTION-AUDIT.md', 'RELEASING.md', 'SHOCKWAVE-COMPATIBILITY.md', 'COMPATIBILITY-RESEARCH.md', 'compatibility-results.json', 'skeleton-corpus.json'):
        shutil.copy2(SOURCE/name, release/name)
    (release/'README.txt').write_text(f'''Flashback {VERSION}

Drag Flashback.app to Applications, then open it. macOS 13 or later.
Import your own Flash, Java, HTML, or experimental Shockwave games.
Browse Discover to search Internet Archive and download games to your library.
Use Add from Website to recover a game from its page or download address.
No commercial games or personal library data are supplied.

This release includes Flashback-Source-{VERSION}.tar.gz.
Keep that source archive with the app when sharing this download.
Flashback's original code and artwork use GPLv3; each dependency retains
its upstream license. Licenses and author credits are also available
inside the app through Flashback > Licenses and Source.

Developer ID signed: yes.
Apple notarization ticket attached: {'yes' if notarized else 'no — see RELEASING.md for the final account-authenticated step'}.
''')
    (release/'SIGNATURE.txt').write_text(signature)
    (release/'SHA256SUMS').write_text(f'{sha256(source_archive)}  {source_archive.name}\n')
    run('codesign', '--verify', '--deep', '--strict', str(release/'Flashback.app'))
    archive_path = stage/'Flashback-Mac.zip'
    run('ditto', '-c', '-k', '--keepParent', str(release), str(archive_path))
    with zipfile.ZipFile(archive_path) as archive:
        assert archive.testzip() is None
        assert f'Flashback-{VERSION}/{source_archive.name}' in archive.namelist()
    target = PROJECT/'Flashback-Mac.zip'
    os.replace(archive_path, target)
    (PROJECT/'Flashback-Mac.zip.sha256').write_text(f'{sha256(target)}  Flashback-Mac.zip\n')
    # Keep a convenient standalone source copy for hosting beside the app.
    os.replace(source_archive, PROJECT/source_archive.name)
    (SOURCE/'build/release-result.json').write_text(json.dumps(dict(version=VERSION, notarized=notarized,
        zip_sha256=sha256(target), source_sha256=sha256(PROJECT/source_archive.name),
        zip_bytes=target.stat().st_size), indent=2) + '\n')
    shutil.rmtree(stage)
    print(f'PASS: {target.name} contains the signed app, corresponding source, licenses, and instructions.', flush=True)

if __name__ == '__main__': main()
