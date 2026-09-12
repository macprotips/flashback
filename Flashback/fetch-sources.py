#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Collect pinned upstream source and dependency archives. Requires Python 3.11+."""
import base64
import concurrent.futures
import hashlib
import json
from pathlib import Path
import tarfile
import shutil
import subprocess
import time
import tomllib
import urllib.request

ROOT = Path(__file__).resolve().parent.parent / 'vendor/sources'
REPOS = [
    ('dirplayer', 'igorlira/dirplayer-rs', '68376fbb4494a6bbad4c70081ecdcb99814a74c9', 'c5409f7259a5e0b0db08aa892ed70e0f9f58c18f09912dfc3cac0d850e4cec29'),
    ('dirplayer-ruffle', 'chameleonxxl/ruffle', '79d1ca0f45d79e28c3a0658bbc6b8430d26ef308', '40a2e5aa7702bae789f6dbc4c6060a0eaf0b66c7a39e10651f607e675b8d9c8a'),
    ('bobba-xtra', 'chameleonxxl/bobba-xtra', '3022f6f924d23ac1838be7b212cf745f52448dcd', '391a1773c40f03f93cf83407603fda8170c12ada7a17026034026d3c39eb3a79'),
    ('groove-xtra', 'chameleonxxl/groove-xtra', '86ea920f3b4d8add58b8f3e07629699cefa1763e', '4e4bfc06fc66abab38e35cffdfcbfcb466ae7b7f0eac875fdbf22bbd600f7f28'),
    ('ruffle', 'ruffle-rs/ruffle', 'v0.6.0', '7011cc529e77e1283ac108170b19f5c3c03dee6101e5bed4ad3779197b792f65'),
    ('freej2me', 'TASEmulators/freej2me-plus', '8f87bf1497e7a9738a32d1909379376a1faca7dd', '831504ba7b60eaf89f33946f41315c15995ed67a85bdaeff2ca8cd242cba23d6'),
]

def download(url, path, integrity=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        for attempt in range(4):
            try:
                with urllib.request.urlopen(url, timeout=90) as response:
                    data = response.read()
                path.write_bytes(data)
                break
            except Exception:
                if attempt == 3: raise
                time.sleep(attempt + 1)
    data = path.read_bytes()
    if integrity:
        algorithm, expected = integrity.split('-', 1)
        assert base64.b64encode(hashlib.new(algorithm, data).digest()).decode() == expected, path
    return hashlib.sha256(data).hexdigest()

def unpack_source(archive, destination):
    """Keep build and test harness source; omit unrelated game/visual test fixtures."""
    with tarfile.open(archive) as source:
        for member in source:
            parts = Path(member.name).parts[1:]
            if not parts: continue
            name = '/'.join(parts)
            if any(part.startswith('dcr_') or part in ('.git', 'fixtures', 'test_data', 'test_data_legacy') for part in parts): continue
            if name.startswith('tests/tests/'): continue
            if Path(name).suffix.lower() in ('.swf', '.dcr', '.dir', '.dxr', '.cct', '.cst', '.exe'): continue
            if 'tests' in parts and Path(name).suffix.lower() in ('.png', '.jpg', '.jpeg', '.wav', '.mp3'): continue
            member.name = name
            source.extract(member, destination, filter='data')

def source_tree_manifest():
    files = {}
    for name, *_ in REPOS:
        for path in sorted((ROOT/name).rglob('*')):
            if path.is_file(): files[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    (ROOT/'SOURCE-TREE.json').write_text(json.dumps(files, indent=2) + '\n')

def patch_freej2me(destination):
    """Apply checked edits to the pinned source, preserving its CRLF endings."""
    def replace(path, before, after, count=1):
        data = path.read_bytes()
        old, new = before.encode(), after.encode()
        assert data.count(old) == count, f'FreeJ2ME patch target changed: {path}: {before}'
        path.write_bytes(data.replace(old, new, count))

    entry = destination / 'src/org/recompile/freej2me/FreeJ2ME.java'
    replace(entry, 'main = new Frame("FreeJ2ME-Plus");',
            'main = new Frame(System.getProperty("flashback.title", "FreeJ2ME-Plus"));')
    # URI escaping is UTF-8 and must not use the emulated phone's text encoding.
    replace(entry, 'getFormattedLocation(URLDecoder.decode(args[0], Mobile.textEncoding))',
            'getFormattedLocation(args[0])')
    replace(entry, 'loc.startsWith("file://")', 'loc.startsWith("file:")')
    replace(entry, 'lcdWidth = Integer.parseInt(args[1]);\r\n\t\t\t\tlcdHeight = Integer.parseInt(args[2]);',
            'lcdWidth = Integer.parseInt(args[2]);\r\n\t\t\t\tlcdHeight = Integer.parseInt(args[3]);')
    # Descriptor values seed a new profile; explicit choices in the player's
    # settings must survive the next launch. These are Config's actual keys.
    replace(entry, '/* Allows FreeJ2ME to set the width and height passed as cmd arguments. */',
            'if (Mobile.config.newConfig) {\r\n'
            '\t\t\t/* Initialize this game from the launch descriptor once. */')
    replace(entry, 'settings.put("width",  ""+lcdWidth)', 'settings.put("scrwidth", ""+lcdWidth)')
    replace(entry, 'settings.put("height", ""+lcdHeight)', 'settings.put("scrheight", ""+lcdHeight)')
    replace(entry, 'settingsChanged();\r\n\r\n\t\t\tMobile.getPlatform().runJar();',
            'Mobile.config.saveConfig();\r\n\t\t\t}\r\n'
            '\t\t\tsettingsChanged();\r\n\r\n\t\t\tMobile.getPlatform().runJar();')
    config = destination / 'src/org/recompile/freej2me/Config.java'
    replace(config, 'private File sFile;', 'private File sFile;\r\n\tpublic boolean newConfig;')
    replace(config, 'if(!cFile.exists())', 'newConfig = !cFile.exists();\r\n\t\t\tif(newConfig)')

    platform = destination / 'src/org/recompile/mobile/MobilePlatform.java'
    replace(platform, 'URLDecoder.decode(preparedFileName, Mobile.textEncoding)',
            'new File(new URI(fileName)).getPath()')
    loader = destination / 'src/org/recompile/mobile/MIDletLoader.java'
    replace(loader, 'new File(url.getFile()).getName()', 'new File(url.toURI()).getName()')
    replace(loader, 'URI jarEntryURI = new URI("jar:" + jarUrl.toExternalForm() + "!/" + entryName);',
            'URL jarEntryURL = new URL("jar:" + jarUrl.toExternalForm() + "!/" + '
            'new URI(null, null, "/" + entryName, null).getRawPath().substring(1));', count=2)
    replace(loader, 'return jarEntryURI.toURL();', 'return jarEntryURL;', count=2)
    # A window alone does not prove that the MIDlet started. The shared host
    # emits readiness only after startApp succeeds, and watches the parent pipe.
    replace(loader, 'start.invoke(Mobile.isDoJa ? IAppliInst : midletInst);',
            'start.invoke(Mobile.isDoJa ? IAppliInst : midletInst);\r\n'
            '\t\t\tSystem.setProperty("flashback.j2me.started", "true");')
    replace(loader, 'e.printStackTrace();\r\n\t\t\treturn;\r\n\t\t}\r\n\r\n\t\ttry\r\n\t\t{\r\n\t\t\twhile (start',
            'e.printStackTrace();\r\n\t\t\tthrow new MIDletStateChangeException(e.toString());\r\n\t\t}\r\n\r\n\t\ttry\r\n\t\t{\r\n\t\t\twhile (start')
    replace(loader, 'e.printStackTrace();\r\n\t\t\treturn;\r\n\t\t}\r\n\t}\r\n\r\n\tpublic static void parseDescriptorInto',
            'e.printStackTrace();\r\n\t\t\tthrow new MIDletStateChangeException(e.toString());\r\n\t\t}\r\n\t}\r\n\r\n\tpublic static void parseDescriptorInto')
    replace(platform, '"Error Running Jar");\r\n\t\t\te.printStackTrace();',
            '"Error Running Jar");\r\n\t\t\tthrow new IllegalStateException("Unable to start MIDlet", e);')

def main():
    records = []
    for name, repo, revision, expected in REPOS:
        url = f'https://codeload.github.com/{repo}/tar.gz/{revision}'
        archive = ROOT / f'{name}.tar.gz'
        digest = download(url, archive)
        assert digest == expected, name
        destination = ROOT / name
        if destination.exists(): shutil.rmtree(destination)
        unpack_source(archive, destination)
        if name == 'dirplayer':
            subprocess.run(['patch', '-p1', '-i', str(Path(__file__).with_name('dirplayer-compat.patch'))], cwd=destination, check=True)
        elif name == 'freej2me':
            patch_freej2me(destination)
        records.append(dict(kind='repository', name=name, url=url, revision=revision, sha256=digest))
    crates = {}
    git_sources = set()
    for lock in ROOT.glob('**/Cargo.lock'):
        if 'dependencies' in lock.parts: continue
        for package in tomllib.loads(lock.read_text())['package']:
            source = package.get('source', '')
            if source.startswith('registry+'):
                crates[(package['name'], package['version'])] = package['checksum']
            elif source.startswith('git+'):
                git_sources.add(source)
    npm = {}
    for lock in ROOT.glob('**/package-lock.json'):
        if 'dependencies' in lock.parts: continue
        for package in json.loads(lock.read_text()).get('packages', {}).values():
            source = package.get('resolved', '')
            if source.startswith('https://registry.npmjs.org/'):
                npm[source] = package['integrity']
            elif source.startswith('git+'):
                git_sources.add(source)
    def crate_task(item):
        (name, version), expected = item
        url = f'https://static.crates.io/crates/{name}/{name}-{version}.crate'
        path = ROOT / 'dependencies/crates' / f'{name}-{version}.crate'
        digest = download(url, path)
        assert digest == expected, path
        return dict(kind='crate', name=name, version=version, path=str(path.relative_to(ROOT)), url=url, sha256=digest)
    def npm_task(item):
        url, integrity = item
        name = url.removeprefix('https://registry.npmjs.org/').split('/-/')[0]
        path = ROOT / 'dependencies/npm' / name / url.rsplit('/', 1)[1]
        digest = download(url, path, integrity)
        return dict(kind='npm', name=name, path=str(path.relative_to(ROOT)), url=url, integrity=integrity, sha256=digest)
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        records.extend(pool.map(crate_task, crates.items()))
        print(f'Verified {len(crates)} crate source archives.', flush=True)
        records.extend(pool.map(npm_task, npm.items()))
        print(f'Verified {len(npm)} npm package archives.', flush=True)
    for source in sorted(git_sources):
        repository, revision = source[4:].rsplit('#', 1)
        repository = repository.split('?', 1)[0].removesuffix('.git')
        repository = repository.replace('ssh://git@github.com/', 'https://github.com/')
        name = repository.rsplit('/', 1)[1] + '-' + revision
        url = repository.replace('https://github.com/', 'https://codeload.github.com/') + '/tar.gz/' + revision
        path = ROOT / 'dependencies/git' / (name + '.tar.gz')
        digest = download(url, path)
        records.append(dict(kind='git', name=name, source=source, path=str(path.relative_to(ROOT)), url=url, revision=revision, sha256=digest))
    (ROOT / 'MANIFEST.json').write_text(json.dumps(records, indent=2) + '\n')
    source_tree_manifest()
    print(f'Source manifest: {len(records)} entries.', flush=True)

if __name__ == '__main__':
    main()
