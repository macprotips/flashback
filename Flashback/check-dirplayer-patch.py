#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Check (or rebuild) the DirPlayer compatibility patch against pinned upstream.

The release promises that a recipient can take the pinned upstream revision,
apply `dirplayer-compat.patch`, and arrive at the source the shipped Shockwave
runtime was built from. This verifies exactly that: it unpacks the verified
upstream archive the same way `fetch-sources.py` does, applies the patch, and
diffs the result against the supplied tree. Any file the patch fails to
reproduce is reported.

Usage:
  check-dirplayer-patch.py            verify the committed patch
  check-dirplayer-patch.py --write    regenerate it from the supplied tree

Run `--write` after changing `vendor/sources/dirplayer`, then verify. Nothing
is downloaded and no game file is touched.
"""
import argparse
import hashlib
import re
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ARCHIVE = ROOT/'vendor/sources/dirplayer.tar.gz'
PATCHED = ROOT/'vendor/sources/dirplayer'
PATCH = Path(__file__).with_name('dirplayer-compat.patch')
# Kept in step with fetch-sources.py's recorded revision.
UPSTREAM_SHA = 'c5409f7259a5e0b0db08aa892ed70e0f9f58c18f09912dfc3cac0d850e4cec29'
# Build output and caches live inside the working tree; they are not source.
EXCLUDE = ('node_modules', 'target', 'pkg', 'dist', 'dist-polyfill', 'dist-extension',
           '.DS_Store', 'npm-build.log', 'test-results', 'playwright-report')


def unpack_source(archive, destination):
    """The selection fetch-sources.py uses, so the two trees are comparable."""
    with tarfile.open(archive) as source:
        for member in source:
            parts = Path(member.name).parts[1:]
            if not parts:
                continue
            name = '/'.join(parts)
            if any(part.startswith('dcr_') or part in ('.git', 'fixtures', 'test_data',
                                                       'test_data_legacy') for part in parts):
                continue
            if name.startswith('tests/tests/'):
                continue
            if Path(name).suffix.lower() in ('.swf', '.dcr', '.dir', '.dxr', '.cct',
                                             '.cst', '.exe'):
                continue
            if 'tests' in parts and Path(name).suffix.lower() in ('.png', '.jpg', '.jpeg',
                                                                  '.wav', '.mp3'):
                continue
            member.name = name
            source.extract(member, destination, filter='data')


def normalize(text):
    """Drop diff's per-file timestamps and directory-only notices."""
    lines = []
    for line in text.splitlines():
        if line.startswith('Only in '):
            continue
        lines.append(re.sub(r'^(---|\+\+\+) ([^\t]*)\t.*$', r'\1 \2', line))
    return '\n'.join(lines) + '\n'


def build_patch(temp):
    unpack_source(ARCHIVE, Path(temp)/'a')
    (Path(temp)/'b').symlink_to(PATCHED)
    excludes = [arg for name in EXCLUDE for arg in ('-x', name)]
    result = subprocess.run(['diff', '-ruN', *excludes, 'a', 'b'],
                            cwd=temp, capture_output=True, text=True)
    assert result.returncode in (0, 1), result.stderr[:400]
    return normalize(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--write', action='store_true',
                        help='regenerate the patch instead of verifying it')
    args = parser.parse_args()

    digest = hashlib.sha256(ARCHIVE.read_bytes()).hexdigest()
    if digest != UPSTREAM_SHA:
        sys.exit(f'upstream archive hash is {digest}, expected {UPSTREAM_SHA}')

    with tempfile.TemporaryDirectory() as temp:
        text = build_patch(temp)
    files = sum(1 for line in text.splitlines() if line.startswith('--- a/'))

    if args.write:
        PATCH.write_text(text)
        print(f'wrote {PATCH.name}: {files} files, {len(text)} bytes')
        return

    if PATCH.read_text() != text:
        sys.exit(f'{PATCH.name} does not match the supplied source tree; '
                 f'run with --write to regenerate it')

    with tempfile.TemporaryDirectory() as temp:
        upstream = Path(temp)/'upstream'
        unpack_source(ARCHIVE, upstream)
        applied = subprocess.run(['patch', '-p1', '-i', str(PATCH)],
                                 cwd=upstream, capture_output=True, text=True)
        if applied.returncode:
            sys.exit('patch did not apply to pinned upstream:\n' + applied.stdout[-2000:])
        excludes = [arg for name in EXCLUDE for arg in ('-x', name)]
        result = subprocess.run(['diff', '-ruN', *excludes, str(upstream), str(PATCHED)],
                                capture_output=True, text=True)
        if result.returncode:
            remaining = [line for line in result.stdout.splitlines() if line.startswith('--- ')]
            sys.exit(f'{len(remaining)} files differ after applying the patch:\n' +
                     '\n'.join(remaining[:20]))

    print(f'{PATCH.name} applies to pinned upstream {UPSTREAM_SHA[:12]} and reproduces '
          f'the supplied source tree ({files} files).')


if __name__ == '__main__':
    main()
