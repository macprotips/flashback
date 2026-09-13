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
import sys
import tarfile
import tempfile
import zipfile

PROJECT = Path(__file__).resolve().parent.parent
SOURCE = PROJECT / 'Flashback'
UPSTREAM = PROJECT / 'vendor/sources'
APP = PROJECT / 'Flashback.app'
VERSION = '1.11.0'
JAVA_SOURCE = PROJECT / 'vendor/java/liberica/bellsoft-jdk8u504+1-src.tar.gz'
ARCHIVE_INPUTS = {
    'commons-compress-1.28.0.jar': 'e1522945218456f3649a39bc4afd70ce4bd466221519dba7d378f2141a4642ca',
    'commons-compress-1.28.0-src.tar.gz': '5c870fa454221b24c81d10a28031a9183d55f2baab92c160ecc985e51a387662',
    'commons-io-2.20.0.jar': 'df90bba0fe3cb586b7f164e78fe8f8f4da3f2dd5c27fa645f888100ccc25dd72',
    'commons-io-2.20.0-sources.jar': '7a87277538cce40da6389a7163a4d9458bc7a9c39937a329881b91d144be8e0d',
    'commons-lang3-3.18.0.jar': '4eeeae8d20c078abb64b015ec158add383ac581571cddc45c68f0c9ae0230720',
    'commons-lang3-3.18.0-sources.jar': 'b15732a13e40df7f07c30f2cb8572874798e8dde581f1398943d2ad3765bafaa',
}

def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b''): digest.update(data)
    return digest.hexdigest()

def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True)

def require(condition, message):
    if not condition:
        raise RuntimeError(str(message))

def require_release_signature(path):
    signature = run('codesign', '-dvv', str(path)).stderr
    require('Authority=Developer ID Application:' in signature, f'{path} is not Developer ID signed.')
    require('runtime' in signature, f'{path} is not hardened-runtime signed.')
    return signature

def verify():
    for name, expected in ARCHIVE_INPUTS.items():
        require(sha256(PROJECT/'vendor/archive'/name) == expected, name)
    native = json.loads((SOURCE/'Licenses/NATIVE-SOURCES.json').read_text())
    require(native['coverage']['status'] == 'complete', 'Native runtime corresponding-source inventory is incomplete; do not package a release.')
    for record in native['fetch']:
        require(sha256(UPSTREAM/'native'/record['file']) == record['sha256'], record['file'])
    for record in json.loads((SOURCE/'Licenses/DOS-SCUMMVM-SOURCES.json').read_text())['components']:
        source = record['source']
        archive_path = PROJECT/source['retained_as']
        require(sha256(archive_path) == source['sha256'], record['name'])
        for marker in source.get('source_markers', []):
            with tarfile.open(archive_path) as archive:
                require(archive.getmember(marker).isfile(), f'{record["name"]} source marker: {marker}')
    run(sys.executable, str(SOURCE/'fetch-native-sources.py'), '--verify-only', '--require-complete', '--audit-scummvm-runtime')
    resources = APP/'Contents/Resources'
    require(not (resources/'ClassicWindows').exists(), 'The unfinished Classic Windows prototype must not enter a release.')
    require(not (resources/'DOS/DOSBox Staging.app/Contents/PlugIns/Nuked-SC55.clap').exists(), 'Restricted DOSBox plug-in is present.')
    require(not (resources/'DOS/DOSBox Staging.app/Contents/Resources/docs').exists(), 'DOSBox documentation contains third-party game screenshots.')
    require(set(run('lipo', '-archs', str(APP/'Contents/MacOS/NativeHost')).stdout.split()) == {'arm64', 'x86_64'}, 'NativeHost is not universal.')
    for name in ('DOS/DOSBox Staging.app/Contents/MacOS/dosbox', 'ScummVM/ScummVM.app/Contents/MacOS/scummvm'):
        require(set(run('lipo', '-archs', str(resources/name)).stdout.split()) == {'arm64', 'x86_64'}, f'{name} is not universal.')
    info = plistlib.loads((APP/'Contents/Info.plist').read_bytes())
    require(info['CFBundleShortVersionString'] == VERSION, 'App and package versions differ.')
    run('codesign', '--verify', '--deep', '--strict', str(APP))
    signature = require_release_signature(APP)
    require_release_signature(APP/'Contents/MacOS/NativeHost')
    require_release_signature(resources/'DOS/DOSBox Staging.app')
    require_release_signature(resources/'ScummVM/ScummVM.app')
    entitlements = run('codesign', '-d', '--entitlements', '-', str(resources/'DOS/DOSBox Staging.app')).stdout
    require('com.apple.security.cs.allow-jit' in entitlements, 'DOSBox must retain its JIT entitlement.')
    require(set(run('lipo', '-archs', str(APP/'Contents/MacOS/Flashback')).stdout.split()) == {'arm64', 'x86_64'}, 'Flashback is not universal.')
    j2me = resources/'J2ME/freej2me.jar'
    require(j2me.is_file(), j2me)
    with zipfile.ZipFile(j2me) as archive:
        require('org/recompile/freej2me/FreeJ2ME.class' in archive.namelist(), 'FreeJ2ME main class is missing.')
        require(b'Main-Class: org.recompile.freej2me.FreeJ2ME' in archive.read('META-INF/MANIFEST.MF'), 'FreeJ2ME manifest is invalid.')
    for source_dir, runtime_dir in [(PROJECT/'vendor/ruffle-web', resources/'Runtime'),
                                    (PROJECT/'vendor/dirplayer/runtime', resources/'Shockwave')]:
        for path in source_dir.rglob('*'):
            if path.is_file(): require(sha256(path) == sha256(runtime_dir/path.relative_to(source_dir)), path)
    for arch, original in [('arm64', PROJECT/'vendor/java/liberica/arm64/jdk8u504.jdk/jre'),
                           ('x86_64', PROJECT/'vendor/java/liberica/x86_64/jre8u504.jre')]:
        target = resources/'Java'/arch
        for path in original.rglob('*'):
            if path.is_file(): require(sha256(path) == sha256(target/path.relative_to(original)), path)
        for name in ('LICENSE', 'ASSEMBLY_EXCEPTION', 'THIRD_PARTY_README', 'readme.txt', 'release'):
            require((target/name).is_file(), (arch, name))
    require(sha256(JAVA_SOURCE) == '037fe8766504a21ed4727599ca5c8af4988232082352d9c596dc2898049f2c42', 'Java source archive hash differs.')
    for path in APP.rglob('*'):
        if not path.is_file(): continue
        require(path.suffix.lower() not in ('.swf','.dcr','.dir','.dxr','.cct','.cst'), path)
        require(path.name not in ('Library.json', 'wiz3.jar', 'game.swf'), path)
        require('texttwist' not in str(path.relative_to(APP)).lower(), path)
    for name in ('BrandArtwork.swift', 'MakeIcon.swift', 'App.swift', 'Player.swift'):
        require('play.square.stack' not in (SOURCE/name).read_text(), name)
    require('systemSymbolName' not in (SOURCE/'MakeIcon.swift').read_text(), 'App icon uses a system symbol.')
    for link in re.findall(r'href="([^"]+)"', (resources/'Licenses.html').read_text()):
        if not link.startswith(('https:', 'http:')): require((resources/link).is_file(), link)
    for name in ('LICENSE', 'SOURCE.md', 'Licenses.html', 'Player.html', 'Shockwave.html', 'shockwave-compat-profiles.json', 'Java.policy', 'Native.policy'):
        require(sha256(SOURCE/name) == sha256(resources/name), name)
    for path in (SOURCE/'Licenses').rglob('*'):
        if path.is_file(): require(sha256(path) == sha256(resources/'Licenses'/path.relative_to(SOURCE/'Licenses')), path)
    records = json.loads((UPSTREAM/'MANIFEST.json').read_text())
    records += json.loads((UPSTREAM/'JAVASCRIPT-SOURCES.json').read_text())
    checked = set()
    for record in records:
        if 'path' not in record: continue
        path = UPSTREAM/record['path']
        if path in checked: continue
        require(sha256(path) == record['sha256'], path)
        checked.add(path)
    required = ['dirplayer/vm-rust/src/lib.rs', 'dirplayer/vm-rust/Cargo.lock',
                'dirplayer/.github/workflows/build.yml', 'dirplayer/xtra-sdk/src/lib.rs',
                'bobba-xtra/src/lib.rs', 'groove-xtra/src/lib.rs',
                'ruffle/Cargo.lock', 'ruffle/web/package-lock.json',
                'dirplayer-ruffle/Cargo.lock', 'dirplayer-ruffle/web/package-lock.json',
                'freej2me/LICENSE', 'freej2me/build.xml',
                'freej2me/src/org/recompile/freej2me/FreeJ2ME.java']
    for name in required: require((UPSTREAM/name).is_file(), name)
    for name, digest in json.loads((UPSTREAM/'SOURCE-TREE.json').read_text()).items():
        require(sha256(UPSTREAM/name) == digest, name)
    print(f'PASS: signed universal app, matching runtimes, source, notices, branding, and {len(checked)} dependency archives.', flush=True)
    return signature

def main():
    signature = verify()
    notarized = subprocess.run(['xcrun', 'stapler', 'validate', str(APP)], capture_output=True).returncode == 0
    require(notarized, 'Notarize and staple Flashback.app before packaging.')
    stage = Path(tempfile.mkdtemp(prefix='release-', dir=SOURCE/'build'))
    release = stage/f'Flashback-{VERSION}'
    release.mkdir()
    source_archive = release/f'Flashback-Source-{VERSION}.tar.gz'
    top = f'Flashback-Source-{VERSION}'
    # An explicit allowlist keeps local games, verification images, builds, and
    # unrelated vendor applications out of the public source archive.
    own_files = [p for p in SOURCE.iterdir() if p.is_file() and
                 (p.suffix in ('.swift','.java','.sh','.py','.html','.policy','.plist','.md','.patch') or p.name in ('LICENSE','shockwave-host-probe.json','shockwave-compat-profiles.json','compatibility-results.json','skeleton-corpus.json','shockwave-galidor-fixtures.json','featured-catalog.json'))]
    source_paths = own_files + [SOURCE/'Licenses', JAVA_SOURCE, PROJECT/'USER-GUIDE.md', PROJECT/'SETUP.md', PROJECT/'AGENTS.md', PROJECT/'README.md']
    source_paths += [UPSTREAM/'native']
    source_paths += [PROJECT/'vendor/archive'/name for name in ARCHIVE_INPUTS]
    source_paths += [PROJECT/c['source']['retained_as'] for c in json.loads((SOURCE/'Licenses/DOS-SCUMMVM-SOURCES.json').read_text())['components']]
    source_paths += [UPSTREAM/name for name in ('dirplayer','dirplayer-ruffle','bobba-xtra','groove-xtra','ruffle','freej2me','dependencies',
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
        require(f'{top}/Flashback/BrandArtwork.swift' in names, 'BrandArtwork.swift is missing from source archive.')
        require(f'{top}/Flashback/WebImport.swift' in names, 'WebImport.swift is missing from source archive.')
        require(f'{top}/Flashback/WebsiteImportView.swift' in names, 'WebsiteImportView.swift is missing from source archive.')
        require(f'{top}/Flashback/check-website.sh' in names, 'check-website.sh is missing from source archive.')
        for name in ('Archive.swift','ArchiveView.swift','ArchiveChecks.swift','ArchiveUICheck.swift','archive-fixture.py','check-archive.sh','dirplayer-compat.patch','check-dirplayer-patch.py','rebuild-shockwave.sh','check-shockwave-corpus.py','shockwave_health.py','shockwave-host-probe.json','shockwave-compat-profiles.json','check-installation.py','check-shockwave-collection.py','inspect-shockwave-skeletons.py','COMPATIBILITY-RESEARCH.md','compatibility-results.json','skeleton-corpus.json'):
            require(f'{top}/Flashback/{name}' in names, f'{name} is missing from source archive.')
        require(f'{top}/vendor/sources/freej2me/LICENSE' in names, 'FreeJ2ME license is missing from source archive.')
        require(f'{top}/vendor/sources/freej2me/src/org/recompile/freej2me/FreeJ2ME.java' in names, 'FreeJ2ME source is missing from source archive.')
        require(f'{top}/USER-GUIDE.md' in names, 'User guide is missing from source archive.')
        require(f'{top}/vendor/java/liberica/{JAVA_SOURCE.name}' in names, 'Java source is missing from source archive.')
        for name in ARCHIVE_INPUTS:
            require(f'{top}/vendor/archive/{name}' in names, f'{name} is missing from source archive.')
        require(not any('/Flashback/build/' in name or '/java-games/' in name or '/shockwave-games/' in name for name in names), 'Build or game fixture directory entered source archive.')
        require(not any(Path(name).suffix.lower() in ('.swf','.dcr','.dir','.dxr','.cct','.cst') for name in names), 'Game movie entered source archive.')
        require(not any('texttwist' in name.lower() for name in names), 'Excluded game content entered source archive.')
    run('ditto', str(APP), str(release/'Flashback.app'))
    shutil.copy2(PROJECT/'USER-GUIDE.md', release/'USER-GUIDE.md')
    for name in ('LICENSE', 'SOURCE.md', 'DISTRIBUTION-AUDIT.md', 'RELEASING.md', 'SHOCKWAVE-COMPATIBILITY.md', 'COMPATIBILITY-RESEARCH.md', 'compatibility-results.json', 'skeleton-corpus.json'):
        shutil.copy2(SOURCE/name, release/name)
    (release/'README.txt').write_text(f'''Flashback {VERSION}

Drag Flashback.app to Applications, then open it. macOS 13 or later.
Import your own Flash, Java, HTML, DOS, or supported Director games.
Browse Discover to search Internet Archive and download games to your library.
Use Add from Website to recover a game from its page or download address.
No commercial games or personal library data are supplied.

This release includes Flashback-Source-{VERSION}.tar.gz.
Keep that source archive with the app when sharing this download.
Flashback's original code and artwork use GPLv3; each dependency retains
its upstream license. Licenses and author credits are also available
inside the app through Flashback > Licenses and Source.

Developer ID signed: yes.
Apple notarization ticket attached: yes.
''')
    (release/'SIGNATURE.txt').write_text(signature)
    (release/'SHA256SUMS').write_text(f'{sha256(source_archive)}  {source_archive.name}\n')
    run('codesign', '--verify', '--deep', '--strict', str(release/'Flashback.app'))
    archive_path = stage/'Flashback-Mac.zip'
    run('ditto', '-c', '-k', '--keepParent', str(release), str(archive_path))
    with zipfile.ZipFile(archive_path) as archive:
        require(archive.testzip() is None, 'Release ZIP is damaged.')
        require(f'Flashback-{VERSION}/{source_archive.name}' in archive.namelist(), 'Source archive is missing from release ZIP.')
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
