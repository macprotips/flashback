#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Capture collection launch failures without counting title screens as gameplay.

Use check-shockwave-corpus.py for asserted native gameplay interactions.
The manifest uses the supplied collection's games.json schema; paths are relative
to that manifest. No game binaries are downloaded or changed by this script.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import shutil
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--app', type=Path, default=Path(__file__).resolve().parent.parent/'Flashback.app')
    parser.add_argument('--games', nargs='+')
    parser.add_argument('--wait', type=float, default=4, help='Seconds to wait after loading before capture')
    parser.add_argument('--discard-imports', action='store_true',
                        help='Remove each temporary imported library after preserving its index')
    args = parser.parse_args()
    manifest = args.manifest.resolve()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    runtime = args.app.resolve()/'Contents/Resources/Shockwave/dirplayer-polyfill.js'
    (root/'Runtime.json').write_text(json.dumps({'app':str(args.app.resolve()),
        'polyfill_sha256':hashlib.sha256(runtime.read_bytes()).hexdigest()},indent=2)+'\n')
    cases = json.loads(manifest.read_text())
    if args.games:
        by_id = {case['id']: case for case in cases}
        cases = [by_id[name] for name in args.games]
    results = []
    for case in cases:
        entry = (manifest.parent/case['entry']).resolve()
        source = (manifest.parent/case['import_folder']).resolve()
        assert entry.is_relative_to(manifest.parent) and source.is_relative_to(manifest.parent)
        assert entry.is_relative_to(source)
        assert (source/case['entry_relative_to_import_folder']).resolve() == entry
        assert hashlib.sha256(entry.read_bytes()).hexdigest() == case['sha256'], entry
        assert Path(case['id']).name == case['id'] and case['id'] not in ('.', '..')
        out = root/case['id']
        out.mkdir()
        probe = {'wait': args.wait}
        # A resource the archived package itself does not contain is recorded in
        # the manifest, not tolerated globally: Galidor Quest's original package
        # links a `dummy.cct` placeholder that was never distributed, so the
        # survey reported the title as a launch failure while its own gameplay
        # case — which records the same expectation — passed. Every other
        # missing file still fails the title.
        if case.get('expected_missing'):
            probe['expectedMissing'] = case['expected_missing']
        if case.get('parameters'):
            probe['parameters'] = case['parameters']
        (out/'Probe.json').write_text(json.dumps(probe, indent=2)+'\n')
        start = time.monotonic()
        with (out/'Console.txt').open('w') as log:
            try:
                subprocess.run([str(args.app.resolve()/'Contents/MacOS/Flashback'), '--shockwave-probe',
                                str(source), case['entry_relative_to_import_folder'], str(out)],
                               stdout=log, stderr=subprocess.STDOUT, timeout=max(45, args.wait+30), check=False)
                detail = (out/'Result.txt').read_text().strip() if (out/'Result.txt').exists() else 'No result'
            except subprocess.TimeoutExpired:
                detail = f'Timed out after {max(45, args.wait+30):g} seconds'
        status = 'OBSERVED' if detail.startswith('OBSERVED:') else 'FAIL'
        results.append(dict(id=case['id'], title=case['title'], sha256=case['sha256'], status=status,
                            seconds=round(time.monotonic()-start, 1), detail=detail))
        (root/'Results.json').write_text(json.dumps(results, indent=2)+'\n')
        print(f"{case['title']}: {status} — {detail}", flush=True)
        library = out/'Library'
        if args.discard_imports and (library/'Library.json').is_file() and (library/'Games').is_dir():
            shutil.copy2(library/'Library.json', out/'Library-index.json')
            shutil.rmtree(library)


if __name__ == '__main__':
    main()
