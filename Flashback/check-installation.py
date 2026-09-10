#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Check a release ZIP, replace its installed app, and retain its isolated game data."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def seed_profile(profile):
    library = profile / 'Library'
    index = library / 'Library.json'
    games = json.loads(index.read_text())
    assert len(games) == 1 and games[0]['lastPlayed'] is not None
    games[0].update(title='My Saved Game', favorite=True)
    index.write_text(json.dumps(games, indent=2))
    saves = library / 'Java Saves' / games[0]['id'] / 'Files'
    saves.mkdir(parents=True, exist_ok=True)
    (saves / 'installation-check.save').write_bytes(b'Existing saved data\n')
    assert (library / 'Covers' / (games[0]['id'] + '.png')).is_file()
    files = {str(file.relative_to(library)): hashlib.sha256(file.read_bytes()).hexdigest()
             for file in library.rglob('*') if file.is_file()}
    (profile / 'Installation-files.json').write_text(json.dumps(files, indent=2))


def isolate(app):
    # Preserve the running user's app and its WebKit store during native UI checks.
    run('/usr/libexec/PlistBuddy', '-c', 'Set :CFBundleIdentifier local.flashback.installation-check', app / 'Contents/Info.plist')
    run('codesign', '--force', '--sign', '-', app)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('previous_zip', type=Path)
    parser.add_argument('updated_app', type=Path)
    parser.add_argument('flash_game_folder', type=Path, help='TextTwist fixture folder containing root/game.swf')
    parser.add_argument('output', type=Path, help='New, empty test directory')
    args = parser.parse_args()
    output = args.output.absolute()
    output.mkdir(parents=True, exist_ok=False)
    run('ditto', '-x', '-k', args.previous_zip.resolve(), output / 'Release')
    apps = list((output / 'Release').glob('*/Flashback.app'))
    assert len(apps) == 1, apps
    run('codesign', '--verify', '--deep', '--strict', apps[0])
    installed = output / 'Applications/Flashback.app'
    installed.parent.mkdir()
    apps[0].rename(installed)
    isolate(installed)
    profile = output / 'Profile'
    run(installed / 'Contents/MacOS/Flashback', '--self-check', args.flash_game_folder.resolve(), 'root/game.swf', profile)
    seed_profile(profile)
    installed.rename(output / 'Previous.app')
    run('codesign', '--verify', '--deep', '--strict', args.updated_app.resolve())
    run('ditto', args.updated_app.resolve(), installed)
    isolate(installed)
    run(installed / 'Contents/MacOS/Flashback', '--installation-check', profile)
    assert (profile / 'Installation-result.txt').read_text().startswith('PASS:')
    print('PASS: extracted release launches; replacing the installed bundle preserves the existing library and storage.')


if __name__ == '__main__':
    main()
