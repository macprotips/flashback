#!/usr/bin/env python3
"""Verify both source-built slices using ScummVM's pinned Director 3 test movie."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import shutil
import subprocess
import tempfile
import time
import urllib.request

HERE = Path(__file__).resolve().parent
COMMIT = '8fda334bba3610504c5c35467be58acb335eb057'
FILES = {
    'D3-Events-NonShared': ('D3-mac/D3-Events-NonShared', 'f9849d1a33aa06545809d99545e00b3e37e28bd35b5ccd862ef04c040f5e92a4'),
    'LICENSE': ('LICENSE', '8177f97513213526df2cf6184d8ff986c675afb514d4e68a404010521b880643'),
    'README.md': ('D3-mac/README.md', '4e064112241f81fe944863983fd7f91b7db4b09a51cab7a8c8b64823a70a9c97'),
}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--offline', action='store_true')
    args = parser.parse_args()
    record = HERE.parent / 'vendor/sources/scummvm-build'
    fixture = record / 'director-tests'
    fixture.mkdir(parents=True, exist_ok=True)
    manifest = {'repository': 'https://github.com/scummvm/director-tests', 'commit': COMMIT, 'license': 'GPL-2.0 (upstream LICENSE)', 'files': {}}
    for name, (relative, expected) in FILES.items():
        path = fixture / name
        url = f'https://raw.githubusercontent.com/scummvm/director-tests/{COMMIT}/{relative}'
        if not path.exists():
            if args.offline: raise RuntimeError(f'Missing fixture {path}')
            path.write_bytes(urllib.request.urlopen(url, timeout=60).read())
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected: raise RuntimeError(f'Fixture checksum mismatch: {path}')
        manifest['files'][name] = {'url': url, 'sha256': expected}
    (fixture / 'SOURCE.json').write_text(json.dumps(manifest, indent=2) + '\n')
    spec = importlib.util.spec_from_file_location('native_checks', HERE / 'check-native-sandbox.py')
    checks = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checks)
    results = {'fixture': manifest, 'architectures': {}}
    with tempfile.TemporaryDirectory(prefix='flashback-director-check-') as directory:
        temp = Path(directory)
        host = temp / 'NativeHost'
        checks.run(['xcrun', 'swiftc', '-target', 'arm64-apple-macos13', '-O', HERE / 'NativeHost.swift', '-o', host])
        for architecture in ['arm64', 'x86_64']:
            app = temp / (architecture + '.app')
            checks.run(['/usr/bin/ditto', '--noextattr', '--noqtn', args.app.resolve(), app])
            binary = app / 'Contents/MacOS/scummvm'
            thin = temp / architecture
            checks.run(['/usr/bin/lipo', binary, '-thin', architecture, '-output', thin])
            shutil.copy2(thin, binary)
            checks.run(['/usr/bin/codesign', '--force', '--sign', '-', app])
            saves = temp / (architecture + '-saves')
            saves.mkdir()
            config = saves / 'scummvm.ini'
            # --detect runs before transient CLI settings; use persistent start_movie.
            config.write_text('[scummvm]\nstart_movie=D3-Events-NonShared\n')
            command = checks.host_command(host, app, binary, fixture, saves,
                '--config=' + str(config), '--path=' + str(fixture), '--game=director', '--detect')
            if architecture == 'x86_64':
                command = [str(binary), *command[command.index('--') + 1:]]
                result = checks.run(command)
                output, error = result.stdout, result.stderr
            else:
                output, error = checks.supervised(command)
            checks.require('director:director' in output + error and 'version guessed as 300' in error, f'Director v3 detection failed: {error}')
            (record / (architecture + '-fixture-detect.log')).write_text(output + error)
            command = checks.host_command(host, app, binary, fixture, saves,
                '--config=' + str(config), '--path=' + str(fixture), '--debuglevel=3', '--debugflags=loading,lingoexec',
                '--start-movie=D3-Events-NonShared', 'director:director')
            if architecture == 'x86_64':
                command = [str(binary), *command[command.index('--') + 1:]]
                with tempfile.TemporaryFile() as capture:
                    process = subprocess.Popen(command, stdout=capture, stderr=subprocess.STDOUT)
                    try:
                        process.wait(timeout=5)
                        raise RuntimeError('Intel Director fixture exited before five-second playback')
                    except subprocess.TimeoutExpired:
                        process.terminate()
                        process.wait(timeout=5)
                    checks.require(process.returncode in (0, -15), 'Intel Director shutdown failed')
                    capture.seek(0)
                    output, error = '', capture.read().decode(errors='replace')
            else:
                output, error = checks.supervised(command, timeout=5, window=True)
            checks.require('-- "Movie SCRIPT: startMovie"' in error and 'Switching to Director v310' in error, f'Director startup failed: {error[-3000:]}')
            (record / (architecture + '-fixture-start.log')).write_text(output + error)
            results['architectures'][architecture] = {'detected_finder_version': 300, 'loaded_movie_version': 310, 'start_movie_lingo_executed': True, 'native_host_ready': architecture == 'arm64', 'stdin_eof_shutdown': architecture == 'arm64', 'execution_context': 'NativeHost sandbox' if architecture == 'arm64' else 'Rosetta outside sandbox; NativeHost qualification on an Intel Mac remains required'}
            print(f'PASS {architecture}: Director 3 detection and movie/score/Lingo startup; ' + ('NativeHost window READY and stdin-EOF shutdown' if architecture == 'arm64' else 'Rosetta playback and orderly termination outside sandbox'))
    (record / 'integration.json').write_text(json.dumps(results, indent=2) + '\n')

if __name__ == '__main__':
    main()
