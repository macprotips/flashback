#!/usr/bin/env python3
"""Record a completed installed build after its source, architecture and host gates."""
from pathlib import Path
import hashlib, json, subprocess, tempfile, shutil, re
root = Path(__file__).resolve().parent.parent
record = root / 'vendor/sources/scummvm-build'
licenses = root / 'Flashback/Licenses'
binary = root / 'vendor/scummvm/ScummVM.app/Contents/MacOS/scummvm'

def sha(p):
    with Path(p).open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()
receipt = json.loads((record / 'build-provenance.json').read_text())
lock = json.loads((licenses / 'DOS-SCUMMVM-BUILD-LOCK.json').read_text())
old = json.loads((licenses / 'DOS-SCUMMVM-PROVENANCE.json').read_text())
old = old.get('superseded_official_runtime', old)
if not sha(binary) == receipt['binary_sha256']:
    raise RuntimeError('Build/source/integration evidence mismatch')
if not sha(licenses / 'DOS-SCUMMVM-BUILD-LOCK.json') == receipt['source_lock_sha256']:
    raise RuntimeError('Build/source/integration evidence mismatch')
for path, digest in receipt['recipe_sha256'].items():
    if not sha(root / path) == digest:
        raise RuntimeError(path)
for triple, arch in [('arm64', 'arm64'), ('x64', 'x86_64')]:
    env = json.loads((record / arch / 'build-env.json').read_text())
    if env.get('VCPKG_ASSET_SOURCES') != 'x-block-origin' or env.get('VCPKG_BINARY_SOURCES') != 'clear':
        raise RuntimeError('Recording complete coverage requires the offline, cache-disabled build')
    log = re.sub(r'\[[^\]\n]*\]', '', (record / f'dependencies-{arch}.log').read_text())
    for dependency in lock['dependencies']:
        if f"Building {dependency['name']}:flashback-{triple}-osx" not in log:
            raise RuntimeError(f"Missing clean build evidence for {dependency['name']} {arch}")
    for name, expected in receipt['architectures'][arch]['dependency_archives'].items():
        path = root / 'work/scummvm-source-build' / triple / 'installed' / f'flashback-{triple}-osx/lib' / name
        if sha(path) != expected or subprocess.check_output(['/usr/bin/lipo', '-archs', str(path)], text=True).split() != [arch]:
            raise RuntimeError(f'Archive build evidence mismatch: {path}')
for source in lock['sources']:
    if sha(root / 'vendor/sources/native' / source['file']) != source['sha256']:
        raise RuntimeError(f"Source mismatch: {source['file']}")
work = root / 'work/scummvm-source-build'
for triple, arch in [('arm64', 'arm64'), ('x64', 'x86_64')]:
    for subtree in ['buildtrees', 'installed']:
        origin = work / triple / subtree
        for path in origin.rglob('*'):
            if path.is_file() and (path.suffix == '.log' or path.name in ['CMakeCache.txt', 'config.status', 'vcpkg.spdx.json', 'vcpkg_abi_info.txt']):
                destination = record / 'dependencies' / arch / subtree / path.relative_to(origin)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, destination)
integration = json.loads((record / 'integration.json').read_text())
if not all((x['start_movie_lingo_executed'] for x in integration['architectures'].values())):
    raise RuntimeError('Build/source/integration evidence mismatch')
if not 'All native sandbox checks passed.' in (record / 'native-sandbox.log').read_text():
    raise RuntimeError('Build/source/integration evidence mismatch')
provenance = {'schema': 2, 'origin': 'retained-source-build', 'version': '2026.3.0', 'build_record': 'vendor/sources/scummvm-build/build-provenance.json', 'build_record_sha256': sha(record / 'build-provenance.json'), 'binary_sha256': sha(binary), 'source_lock': 'Flashback/Licenses/DOS-SCUMMVM-BUILD-LOCK.json', 'architectures': {}, 'validation': {'clean_offline_build': True, 'dependency_archive_count_per_architecture': 39, 'native_host_arm64': True, 'director_v3_startup_both_slices': True, 'intel_execution': 'Rosetta outside sandbox; qualify NativeHost on an actual Intel Mac', 'bit_identical_across_toolchains': 'not claimed'}, 'superseded_official_runtime': old}
with tempfile.TemporaryDirectory() as t:
    for arch in ['arm64', 'x86_64']:
        p = Path(t) / arch
        subprocess.run(['/usr/bin/lipo', str(binary), '-thin', arch, '-output', str(p)], check=True)
        signed = sha(p)
        subprocess.run(['/usr/bin/codesign', '--remove-signature', str(p)], check=True, capture_output=True)
        output = receipt['architectures'][arch]['version_output']
        version = '\n'.join((line for line in output.splitlines() if line.startswith(('ScummVM 2026.3.0', 'Using SDL backend', 'Features compiled in:')))) + '\n'
        provenance['architectures'][arch] = {'slice_sha256': signed, 'unsigned_slice_sha256': sha(p), 'version_output': version}
provenance['retained_evidence_sha256'] = {str(p.relative_to(root)): sha(p) for p in sorted(record.rglob('*')) if p.is_file()}
for relative in ['Flashback/check-scummvm-build.py', 'Flashback/record-scummvm-build.py', 'Flashback/Licenses/DOS-SCUMMVM-TOOLS.json']:
    provenance['retained_evidence_sha256'][relative] = sha(root / relative)
(licenses / 'DOS-SCUMMVM-PROVENANCE.json').write_text(json.dumps(provenance, indent=2) + '\n')
p = licenses / 'NATIVE-SOURCES.json'
x = json.loads(p.read_text())
x['coverage'] = {'status': 'complete', 'statement': 'DOSBox Staging release source closure and the locally rebuilt ScummVM Director-only universal runtime source/build closure are retained and checksum verified. Compatibility qualification on an actual Intel Mac remains separate from source coverage.', 'blockers': [], 'details': 'DOS-SCUMMVM-BUILD.md'}
x['runtime_provenance'][1] = {'component': 'ScummVM 2026.3.0 macOS', 'main_source': lock['main_source'], 'main_source_release_tag': 'v2026.3.0', 'main_source_release_commit': 'fed42f2068dcafc6aafa1c28c77e4c88def74b66', 'coverage_status': 'complete', 'origin': 'retained-source-build', 'engine': 'director', 'source_lock': 'Flashback/Licenses/DOS-SCUMMVM-BUILD-LOCK.json', 'external_dependency_sources': [s['file'] for s in lock['sources']], 'recipe': 'Flashback/build-scummvm.py and Flashback/scummvm-build/', 'evidence': 'DOS-SCUMMVM-PROVENANCE.json', 'build_record': 'vendor/sources/scummvm-build/build-provenance.json', 'identity_audit': 'python3 Flashback/fetch-native-sources.py --verify-only --require-complete --audit-scummvm-runtime', 'not_linked': 'Sparkle/updater and Dock tile plug-in', 'license_note': 'ScummVM GPL-3.0-or-later; linked RetroWave AGPL-3.0-or-later; other dependency terms retained'}
p.write_text(json.dumps(x, indent=2) + '\n')
p = licenses / 'DOS-SCUMMVM-SOURCES.json'
x = json.loads(p.read_text())
c = x['components'][1]
c.setdefault('superseded_official_runtime', c['runtime'])
c['runtime'] = {'origin': 'retained-source-build', 'build_recipe': 'Flashback/build-scummvm.py', 'binary_sha256': sha(binary), 'architectures': ['arm64', 'x86_64']}
c['corresponding_source_status'] = 'complete'
c['license'] = 'GPL-3.0-or-later (ScummVM), AGPL-3.0-or-later (RetroWave), and retained dependency terms'
p.write_text(json.dumps(x, indent=2) + '\n')
print('Recorded complete retained-source ScummVM build:', sha(binary))
