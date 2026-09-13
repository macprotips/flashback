#!/usr/bin/env python3
"""Build the locked Director-only ScummVM runtime in external scratch storage.

Source downloads are checksum checked before vcpkg runs with --no-downloads.
General-purpose tools/Apple SDK are prerequisites, recorded in the build record.
The candidate is installed in vendor only with --install after all binary gates.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
RECIPES = ROOT / 'Flashback/scummvm-build'
LOCK_PATH = ROOT / 'Flashback/Licenses/DOS-SCUMMVM-BUILD-LOCK.json'
BASELINE = '6283825b81bb60f952af1d0703638df1de611243'
PACKAGES = 'sdl2 sdl2-net zlib libpng libjpeg-turbo faad2 libmad freetype fribidi libogg libvorbis libflac libtheora libvpx libopenmpt fluidsynth sonivox giflib libmpeg2 libmikmod liba52 retrowave'.split()
PC_PACKAGES = 'sdl2 freetype2 fribidi vorbisfile flac mad libpng theoradec faad2 libmikmod libopenmpt vpx libjpeg zlib fluidsynth sonivox'.split()
EXPECTED_FEATURES = 'Vorbis FLAC MP3 TiMidity RGB zLib MPEG2 FluidSynth EAS Theora VPX AAC A/52 FreeType2 FriBiDi JPEG PNG GIF taskbar TTS cloud libcurl SDL_net ENet SDL2 TinyGL OpenGL RetroWave'.split()


def digest(path, algorithm='sha256'):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, algorithm).hexdigest()


def checked_source(path, entry):
    if digest(path) != entry['sha256']:
        raise RuntimeError(f'Source checksum mismatch: {path}')
    if entry.get('upstream_sha512') and digest(path, 'sha512') != entry['upstream_sha512']:
        raise RuntimeError(f'Upstream recipe checksum mismatch: {path}')


def fetch(path, entry, offline):
    if not path.exists():
        if offline:
            raise RuntimeError(f'Missing retained source: {path}')
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + '.partial')
        try:
            with urllib.request.urlopen(entry['url'], timeout=120) as src, temporary.open('wb') as dst:
                shutil.copyfileobj(src, dst)
            checked_source(temporary, entry)
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)
    checked_source(path, entry)


def run(command, *, cwd=None, env=None, log=None):
    if log:
        Path(log).parent.mkdir(parents=True, exist_ok=True)
        Path(str(log) + '.command.json').write_text(json.dumps(command, indent=2) + '\n')
        with Path(log).open('w') as output:
            result = subprocess.run(command, cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT)
        if result.returncode:
            raise RuntimeError(f'Command failed ({result.returncode}); see {log}')
        return ''
    return subprocess.check_output(command, cwd=cwd, env=env, text=True, stderr=subprocess.STDOUT)


def audit_archives(prefix, architecture):
    archives = sorted((prefix / 'lib').glob('*.a'))
    if not archives:
        raise RuntimeError(f'No dependency archives: {prefix}')
    evidence = {}
    for archive in archives:
        actual = run(['/usr/bin/lipo', '-archs', str(archive)]).split()
        if actual != [architecture]:
            raise RuntimeError(f'Wrong static archive architecture: {archive}: {actual}')
        evidence[archive.name] = digest(archive)
    return evidence


def audit_binary(binary, architecture, config):
    if run(['/usr/bin/lipo', '-archs', str(binary)]).split() != [architecture]:
        raise RuntimeError(f'Incorrect ScummVM architecture: {binary}')
    metadata = run(['/usr/bin/otool', '-l', str(binary)])
    if 'minos 11.0' not in metadata: raise RuntimeError(f'Unexpected macOS deployment target: {binary}')
    imports = run(['/usr/bin/otool', '-L', str(binary)])
    for line in imports.splitlines()[1:]:
        imported = line.strip().split(' (', 1)[0]
        if not imported.startswith(('/usr/lib/', '/System/Library/')):
            raise RuntimeError(f'Non-system dynamic dependency: {imported}')
    version = run(['/usr/bin/arch', '-' + architecture, str(binary), '--config=' + str(config), '--version'])
    features = next(line for line in version.splitlines() if line.startswith('Features compiled in:'))
    required = EXPECTED_FEATURES + (['OpenMPT'] if architecture == 'arm64' else ['MikMod'])
    missing = set(required) - set(features.split())
    if missing or 'ScummVM 2026.3.0' not in version:
        raise RuntimeError(f'Unexpected version/features ({sorted(missing)}): {version}')
    listing = run(['/usr/bin/arch', '-' + architecture, str(binary), '--config=' + str(config), '--list-engines'])
    engines = [line.split()[0] for line in listing.splitlines() if line.strip() and not line.startswith(('Engine ID', '---', 'WARNING:', 'Creating configuration'))]
    if engines != ['director']:
        raise RuntimeError(f'Unexpected engine list: {listing}')
    return {'sha256': digest(binary), 'version_output': version, 'imports': imports, 'load_commands': metadata, 'engine_listing': listing}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-dir', required=True, type=Path, help='External scratch directory; may contain spaces')
    parser.add_argument('--offline', action='store_true', help='Require all source inputs already retained')
    parser.add_argument('--install', action='store_true', help='Install the verified candidate into vendor/scummvm')
    parser.add_argument('--jobs', type=int, default=8)
    parser.add_argument('--clean', action='store_true', help='Rebuild both scratch dependency prefixes from retained sources')
    parser.add_argument('--skip-dependencies', action='store_true', help='Reuse and audit already built prefixes')
    args = parser.parse_args()
    if args.clean and args.skip_dependencies: parser.error('--clean and --skip-dependencies conflict')
    lock = json.loads(LOCK_PATH.read_text())
    work_actual = args.work_dir.expanduser().resolve()
    work_actual.mkdir(parents=True, exist_ok=True)
    # Upstream makefiles split paths. A stable logical alias avoids space-bearing
    # source, prefix and SDK arguments while retaining all bulk files externally.
    alias = ROOT / 'work/scummvm-source-build'
    alias.parent.mkdir(exist_ok=True)
    if alias.is_symlink():
        if alias.resolve() != work_actual:
            raise RuntimeError(f'{alias} already refers to another build; choose a separate checkout')
    elif alias.exists():
        raise RuntimeError(f'Refusing to replace existing non-symlink {alias}')
    else:
        alias.symlink_to(work_actual, target_is_directory=True)
    work = alias
    developer = Path(os.environ.get('DEVELOPER_DIR', run(['/usr/bin/xcode-select', '-p']).strip()))
    if not (developer / 'Toolchains').is_dir():
        raise RuntimeError('Set DEVELOPER_DIR to a full Xcode installation')
    xcode = work / 'xcode'
    if xcode.is_symlink():
        if xcode.resolve() != developer.resolve():
            raise RuntimeError('Existing build uses another Xcode; start with clean scratch')
    elif not xcode.exists():
        xcode.symlink_to(developer.resolve(), target_is_directory=True)
    tools_dir = work / 'tools'
    tools_dir.mkdir(exist_ok=True)
    tool_evidence = {}
    for tool in ['python3', 'pkg-config', 'autoconf', 'autoheader', 'autoreconf', 'automake', 'aclocal', 'glibtool', 'glibtoolize', 'nasm']:
        found = shutil.which(tool)
        if not found:
            raise RuntimeError(f'Missing general-purpose build tool: {tool}')
        target = Path(found).resolve()
        link = tools_dir / tool
        if link.is_symlink():
            if link.resolve() != target:
                raise RuntimeError(f'Build tool changed: {tool}; use clean scratch')
        elif not link.exists():
            link.symlink_to(target)
        tool_evidence[tool] = {'path': str(target), 'sha256': digest(target), 'version': run([str(target), '--version']).splitlines()[0]}
    env = {key: os.environ[key] for key in ['HOME', 'TMPDIR', 'USER', 'LOGNAME'] if key in os.environ}
    env.update(DEVELOPER_DIR=str(xcode), PATH=str(tools_dir) + ':/usr/bin:/bin:/usr/sbin:/sbin', LC_ALL='C', VCPKG_DISABLE_METRICS='1', VCPKG_BINARY_SOURCES='clear', VCPKG_MAX_CONCURRENCY=str(args.jobs), SOURCE_DATE_EPOCH=str(lock['source_date_epoch']))
    sdk = Path(run(['/usr/bin/xcrun', '--show-sdk-path'], env=env).strip())
    env['SDKROOT'] = str(sdk)
    tool_evidence['xcode'] = run(['/usr/bin/xcodebuild', '-version'], env=env)
    tool_evidence['sdk'] = run(['/usr/bin/xcrun', '--show-sdk-version'], env=env).strip()
    tool_evidence['clang'] = run(['/usr/bin/clang', '--version'], env=env)
    (work / 'toolchain.json').write_text(json.dumps(tool_evidence, indent=2) + '\n')
    sources = ROOT / 'vendor/sources'
    components = json.loads((ROOT / 'Flashback/Licenses/DOS-SCUMMVM-SOURCES.json').read_text())
    main_source = next(c['source'] for c in components['components'] if c['name'] == 'ScummVM')
    fetch(sources / 'scummvm-2026.3.0.tar.xz', main_source, args.offline)
    native_manifest = json.loads((ROOT / 'Flashback/Licenses/NATIVE-SOURCES.json').read_text())
    baseline_entry = next(e for e in native_manifest['fetch'] if e['file'] == f'vcpkg-{BASELINE}.tar.gz')
    fetch(sources / 'native' / baseline_entry['file'], baseline_entry, args.offline)
    for entry in lock['sources']:
        fetch(sources / 'native' / entry['file'], entry, args.offline)
    vcpkg = work / ('vcpkg-' + BASELINE)
    if not vcpkg.exists():
        with tarfile.open(sources / 'native' / baseline_entry['file']) as archive:
            archive.extractall(work, filter='data')
    if args.offline:
        env['VCPKG_ASSET_SOURCES'] = 'x-block-origin'
    if not (vcpkg / 'vcpkg').exists():
        if args.offline: raise RuntimeError('Offline build requires the pinned vcpkg build tool to be bootstrapped first')
        run(['/bin/sh', str(vcpkg / 'bootstrap-vcpkg.sh'), '-disableMetrics'], env=env, log=work / 'bootstrap.log')
    tool_evidence['vcpkg'] = {'version': run([str(vcpkg / 'vcpkg'), 'version'], env=env), 'sha256': digest(vcpkg / 'vcpkg')}
    for entry in lock['sources']:
        destination = vcpkg / 'downloads' / entry['build_cache_name']
        destination.parent.mkdir(exist_ok=True)
        shutil.copy2(sources / 'native' / entry['file'], destination)
    src = work / 'scummvm-2026.3.0'
    # Always restore the exact upstream source before applying the retained patch.
    if src.exists():
        shutil.rmtree(src)
    with tarfile.open(sources / 'scummvm-2026.3.0.tar.xz') as archive:
        archive.extractall(work, filter='data')
    with (RECIPES / 'director-components.patch').open('rb') as patch:
        subprocess.run(['/usr/bin/patch', '-p1'], cwd=src, stdin=patch, env=env, check=True)
    recipe_hashes = {str(p.relative_to(ROOT)): digest(p) for p in sorted(RECIPES.rglob('*')) if p.is_file()}
    recipe_hashes['Flashback/build-scummvm.py'] = digest(Path(__file__))
    evidence = {'schema': 1, 'version': '2026.3.0', 'source_lock_sha256': digest(LOCK_PATH), 'recipe_sha256': recipe_hashes, 'toolchain': tool_evidence, 'architectures': {}}
    base_flags = json.loads((RECIPES / 'configure-flags.json').read_text())
    for architecture, triple in [('arm64', 'arm64'), ('x86_64', 'x64')]:
        dep_root = work / triple
        if args.clean and dep_root.exists(): shutil.rmtree(dep_root)
        prefix = dep_root / 'installed' / f'flashback-{triple}-osx'
        if not args.skip_dependencies:
            command = [str(vcpkg / 'vcpkg'), 'install', '--classic', '--no-downloads', '--triplet', f'flashback-{triple}-osx', '--overlay-triplets=' + str(RECIPES / 'triplets'), '--overlay-ports=' + str(RECIPES / 'ports'), '--x-buildtrees-root=' + str(dep_root / 'buildtrees'), '--x-packages-root=' + str(dep_root / 'packages'), '--x-install-root=' + str(dep_root / 'installed'), *PACKAGES]
            run(command, env=env, log=work / f'dependencies-{architecture}.log')
        archives = audit_archives(prefix, architecture)
        (prefix / 'bin').mkdir(exist_ok=True)
        for script in ['sdl2-config', 'libmikmod-config']:
            target = prefix / 'bin' / script
            if target.is_symlink(): target.unlink()
            shutil.copy2(RECIPES / (script + '.sh'), target)
        build = work / f'scummvm-{architecture}'
        if build.exists(): shutil.rmtree(build)
        build.mkdir(exist_ok=True)
        build_env = env | {'PKG_CONFIG_PATH': '', 'PKG_CONFIG_LIBDIR': str(prefix / 'lib/pkgconfig'), 'CXX': '/usr/bin/clang++', 'LD': '/usr/bin/clang++', 'AR': '/usr/bin/ar', 'RANLIB': '/usr/bin/ranlib', 'NM': '/usr/bin/nm', 'STRIP': '/usr/bin/strip'}
        target_flags = f'-arch {architecture} -mmacosx-version-min=11.0 -isysroot {sdk}'
        build_env['CXXFLAGS'] = target_flags + ' -I' + str(prefix / 'include')
        build_env['LDFLAGS'] = target_flags + ' -L' + str(prefix / 'lib')
        flags = base_flags + ['--with-staticlib-prefix=' + str(prefix), '--with-sdl-prefix=' + str(prefix), '--with-mikmod-prefix=' + str(prefix)]
        if architecture == 'x86_64':
            flags += ['--disable-openmpt', '--host=x86_64-apple-darwin']
        (build / 'build-env.json').write_text(json.dumps(build_env, indent=2) + '\n')
        run([str(src / 'configure'), *flags], cwd=build, env=build_env, log=build / 'configure-output.log')
        libs = run(['pkg-config', '--static', '--libs', *PC_PACKAGES], env=build_env).strip() + ' -lSDL2_net -lmpeg2 -la52 -lgif -lRetroWave -lcurl -framework Security -framework OpenGL'
        link_flags = []
        for flag in shlex.split(libs):
            archive = prefix / 'lib' / ('lib' + flag[2:] + '.a') if flag.startswith('-l') else None
            if archive is not None and archive.exists():
                flag = str(archive)
            elif flag.startswith('-l') and flag not in ['-lc++', '-lm', '-lpthread', '-lcurl', '-liconv']:
                raise RuntimeError(f'Unmapped linker library: {flag}')
            link_flags.append(flag)
        # Reject package-manager include/library paths in generated build flags.
        config = (build / 'config.mk').read_text()
        if any(token in config for token in ['-I/opt/homebrew', '-L/opt/homebrew', '-I/usr/local', '-L/usr/local', '-I/opt/local', '-L/opt/local']):
            raise RuntimeError('Unretained package-manager path in ScummVM configuration')
        run(['/usr/bin/make', '-j' + str(args.jobs), 'MAKE=/usr/bin/make', 'AR=/usr/bin/ar cr', 'RANLIB=/usr/bin/ranlib', 'NM=/usr/bin/nm', 'STRIP=/usr/bin/strip', 'scummvm-static', 'OSX_STATIC_LIBS=' + ' '.join(link_flags), 'OSX_ZLIB='], cwd=build, env=build_env, log=build / 'build-output.log')
        binary_evidence = audit_binary(build / 'scummvm-static', architecture, build / 'verify.ini')
        evidence['architectures'][architecture] = binary_evidence | {'dependency_archives': archives, 'configure_flags': flags}
        run(['/usr/bin/make', 'MAKE=/usr/bin/make', 'AR=/usr/bin/ar cr', 'RANLIB=/usr/bin/ranlib', 'NM=/usr/bin/nm', 'STRIP=/usr/bin/strip', 'bundle-pack'], cwd=build, env=build_env, log=build / 'bundle-output.log')
    candidate = work / 'candidate'
    if candidate.exists():
        shutil.rmtree(candidate)
    candidate.mkdir()
    app = candidate / 'ScummVM.app'
    run(['/usr/bin/ditto', '--noextattr', '--noqtn', str(work / 'scummvm-arm64/ScummVM.app'), str(app)])
    binary = app / 'Contents/MacOS/scummvm'
    run(['/usr/bin/lipo', '-create', str(work / 'scummvm-arm64/ScummVM.app/Contents/MacOS/scummvm'), str(work / 'scummvm-x86_64/ScummVM.app/Contents/MacOS/scummvm'), '-output', str(binary)])
    notices = candidate / 'notices'
    notices.mkdir()
    for path in sorted((work / 'arm64/installed/flashback-arm64-osx/share').glob('*/copyright')):
        shutil.copy2(path, notices / (path.parent.name + '-COPYRIGHT.txt'))
    shutil.copy2(src / 'COPYING', notices / 'ScummVM-COPYING.txt')
    run(['/usr/bin/codesign', '--force', '--sign', '-', str(app)])
    run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)])
    evidence['binary_sha256'] = digest(binary)
    (candidate / 'build-provenance.json').write_text(json.dumps(evidence, indent=2) + '\n')
    record = ROOT / 'vendor/sources/scummvm-build'
    record.mkdir(exist_ok=True)
    shutil.copy2(candidate / 'build-provenance.json', record / 'build-provenance.json')
    shutil.copy2(LOCK_PATH, record / 'source-lock.json')
    for architecture in ['arm64', 'x86_64']:
        shutil.copy2(work / f'dependencies-{architecture}.log', record / f'dependencies-{architecture}.log')
        shutil.copy2(work / f'dependencies-{architecture}.log.command.json', record / f'dependencies-{architecture}.log.command.json')
        destination = record / architecture
        destination.mkdir(exist_ok=True)
        for pattern in ['config.h', 'config.mk', 'config.log', '*command.json', 'build-env.json', '*output.log']:
            for path in (work / ('scummvm-' + architecture)).glob(pattern):
                shutil.copy2(path, destination / path.name)
    (record / 'toolchain.json').write_text(json.dumps(tool_evidence, indent=2) + '\n')
    if args.install:
        run([sys.executable, str(ROOT / 'Flashback/check-scummvm-build.py'), '--app', str(app), *(['--offline'] if args.offline else [])], env=env, log=record / 'director-check.log')
        run([sys.executable, str(ROOT / 'Flashback/check-native-sandbox.py'), '--scummvm-app', str(app), '--windows'], env=env, log=record / 'native-sandbox.log')
        vendor = ROOT / 'vendor/scummvm'
        previous = work / 'previous-vendor-scummvm'
        if previous.exists():
            raise RuntimeError(f'Preserved prior runtime already exists: {previous}')
        if vendor.exists():
            shutil.move(vendor, previous)
        shutil.copytree(candidate, vendor, symlinks=True)
    print(f'Built and verified universal Director-only candidate: {app}')
    print('Source coverage is changed only after source and host integration audits.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print(f'ScummVM build failed: {error}', file=sys.stderr)
        raise SystemExit(1)
