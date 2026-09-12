#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Exercise real MIDlet startup, descriptors, URI paths, saves and permissions."""
import pathlib
import subprocess
import sys
import tempfile
import time
import zipfile

SOURCE = pathlib.Path(__file__).resolve().parent
RESOURCES = SOURCE.parent / 'Flashback.app/Contents/Resources'
JDK = SOURCE.parent / 'vendor/java/liberica/arm64/jdk8u504.jdk'


def main():
    runner = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else RESOURCES / 'JavaRunner.jar'
    emulator = RESOURCES / 'J2ME/freej2me.jar'
    with tempfile.TemporaryDirectory(prefix='flashback-j2me-') as tmp:
        root = pathlib.Path(tmp)
        classes, saves = root / 'classes', root / 'saves'
        classes.mkdir(); saves.mkdir()
        subprocess.run([str(JDK / 'bin/javac'), '-cp', str(emulator), '-d', str(classes),
                        str(SOURCE / 'J2MEChecks.java'), str(SOURCE / 'JavaPolicyCheck.java')], check=True)
        game = root / 'Game + 50% # café.jar'
        manifest = ('Manifest-Version: 1.0\nMIDlet-1: Flashback Check,,J2MEChecks\n'
                    'MIDlet-Name: Flashback Check\nMIDlet-Vendor: Nokia\nMIDlet-Version: 1.0\n'
                    'MicroEdition-Profile: MIDP-2.0\nMicroEdition-Configuration: CLDC-1.1\n\n')
        with zipfile.ZipFile(game, 'w') as archive:
            archive.writestr('META-INF/MANIFEST.MF', manifest)
            for file in classes.glob('*.class'): archive.write(file, file.name)
            archive.writestr('check + % # é.txt', b'*')
        jad = 'Nokia-MIDlet-Original-Display-Size: 176x208\nFlashback-JAD-Check: companion\n'
        game.with_suffix('.jad').write_text(jad)
        command = [str(JDK / 'bin/java'), '-Xmx512m', '-Dfile.encoding=ISO_8859_1',
                   '-Djava.security.manager', '-Djava.security.policy==' + str(SOURCE / 'Java.policy'),
                   '-Dflashback.runner=' + runner.as_uri(), '-Dflashback.j2me=' + emulator.as_uri(),
                   '-Dflashback.game=' + str(root), '-Duser.home=' + str(saves),
                   '-cp', str(runner) + ':' + str(emulator), 'JavaRunner', '--play', str(game)]
        for iteration in (1, 2, 3, 4):
            if iteration == 3:
                # Emulate the changes written by the player's Settings menu.
                configs = list(saves.glob('config/*/game.conf'))
                assert len(configs) == 1, configs
                settings = dict(line.split(':', 1) for line in configs[0].read_text().splitlines())
                settings.update(scrwidth='208', scrheight='176', phone='Siemens', fps='30')
                configs[0].write_text(''.join(f'{key}:{value}\n' for key, value in settings.items()))
                game.with_suffix('.jad').write_text(jad + 'Flashback-Changed-Settings: yes\n')
            if iteration == 4: game.with_suffix('.jad').write_text(jad + 'Flashback-Fail: yes\n')
            log = root / f'launch-{iteration}.log'
            with log.open('wb') as output:
                child = subprocess.Popen(command, cwd=saves, stdin=subprocess.PIPE, stdout=output, stderr=output)
                try:
                    deadline = time.monotonic() + 40
                    while time.monotonic() < deadline:
                        text = log.read_text(errors='replace')
                        if 'FLASHBACK_READY' in text or child.poll() is not None: break
                        if iteration == 4 and 'Intentional startup failure' in text: break
                        time.sleep(0.1)
                    if iteration < 4:
                        size = '208x176' if iteration == 3 else '176x208'
                        assert f'FLASHBACK_MIDLET_PASS:{size}:saves={iteration}' in text, text[-7000:]
                        assert 'FLASHBACK_READY' in text, text[-7000:]
                    else:
                        assert 'Intentional startup failure' in text and 'FLASHBACK_READY' not in text, text[-7000:]
                    # Losing the app's pipe must shut down the child promptly.
                    child.stdin.close()
                    assert child.wait(timeout=5) == (1 if iteration == 4 else 0)
                finally:
                    if child.poll() is None: child.kill(); child.wait()
    print('PASS: MIDlet launches at 176x208, loads JAD and escaped paths, persists RMS and device settings across launches, '
          'enforces game permissions, rejects false readiness, and exits with its parent.')


if __name__ == '__main__':
    main()
