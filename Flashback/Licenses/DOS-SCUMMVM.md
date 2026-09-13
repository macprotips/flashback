# DOSBox Staging and ScummVM runtime notices

These records cover the optional classic-game runtimes fetched by
`fetch-dos.sh` and `fetch-scummvm.sh`. They are not game files. A release that
bundles either runtime must include its copied notice files and the matching
source archives identified in `DOS-SCUMMVM-SOURCES.json`.

## DOSBox Staging 0.83.0

DOSBox Staging is licensed under **GPL-2.0-or-later**. Its upstream macOS
release is a universal `arm64` and `x86_64` application. The fetch script
copies the upstream `LICENSE` to `vendor/dosbox-staging/LICENSE` and retains
the source archive in `vendor/sources/`.

Upstream's 0.83.0 macOS packaging workflow injects the optional
`Nuked-SC55.clap` plug-in. Its original MAME license prohibits use in a
commercial product or activity and has separate source conditions. Flashback
removes exactly `DOSBox Staging.app/Contents/PlugIns/Nuked-SC55.clap` from the
checksum-verified app before bundling it, then ad-hoc re-signs the modified
app while retaining the original `com.apple.security.cs.allow-jit`
entitlement. The recorded runtime hash is for the upstream DMG, not the
locally transformed app.

The Flashback host is responsible for generating each game's DOSBox
configuration, mounting a private working copy and using the runtime's `--conf` and `-c`
command-line interface. No claim is
made that every DOS executable or its original copy protection works.

## ScummVM 2026.3.0

ScummVM's main code is licensed under **GPL-3.0-or-later**. Flashback builds
its separate universal Apple Silicon/Intel runtime from official 2026.3.0
source with only the Director engine and the pinned media/text/audio/MIDI
closure in `DOS-SCUMMVM-BUILD-LOCK.json`. RetroWave carries
**AGPL-3.0-or-later**; other dependencies keep their original terms. Upstream
license texts are copied to `vendor/scummvm/notices/` and app resources. The
complete main/dependency sources, recipes, patches, command/configuration logs
and source-to-code evidence accompany the source package.

The retained main source is official `v2026.3.0`
(`fed42f2068dcafc6aafa1c28c77e4c88def74b66`). This source-built replacement
supersedes the official macOS DMG, whose external static-source recipe was not
fully established. Sparkle updating and the Dock tile plug-in are disabled;
no Sparkle code is linked in this replacement.

Flashback first runs `scummvm --path <directory> --game=director --detect`
and retains the reported `director:` game identifier. It launches only that
detected title with private config/save locations. The Director engine being
present does not mean every `.dir`, `.dcr`, or Director version is playable.

## Dependency sources and verification

`NATIVE-SOURCES.json` includes both native runtimes' pinned dependency sources.
`DOS-SCUMMVM-PROVENANCE.json` records the verified replacement's code identities
and retained build evidence. `fetch-native-sources.py --require-complete`
checks the real retained inputs and build record rather than accepting a
coverage label alone. Rebuild instructions, local changes and the remaining
actual-Intel-Mac sandbox qualification are in `DOS-SCUMMVM-BUILD.md`.
