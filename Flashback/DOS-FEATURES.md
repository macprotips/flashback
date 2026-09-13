# DOS player capabilities

DOS games still launch from their library card. Right-click a DOS game and
choose DOS Settings for per-game controls. These additions are independent of
the experimental Classic Windows setup.

- Game: automatic or fixed CPU speed, full screen, sound, macOS General MIDI,
  and mouse capture. Advanced launch options select the starting executable and
  bounded simple arguments. Setup tools run another program or open the DOS
  prompt in the same private writable game copy.
- Discs: copy ISO/CUE CD images and IMG/IMA floppy images into private storage,
  including CUE companion tracks. Reorder images before launch, detach sets,
  and use Command–F4 in DOSBox Staging to switch attached media. Original files
  are preserved. Private floppy copies are writable.
- Saves: reveal writable files; snapshot, restore, and reset the game's C:
  drive. Restore/reset keep the previous drive as a backup. Data operations
  block launch, removal, and ordinary app quit until they finish.
- Controls/help: discover fullscreen, pause, pointer release, key/controller
  mapping, CPU speed, disc swap, and capture keys. Mapper and capture paths are
  per game. MIDI uses Apple's synthesizer and bypasses DOSBox's internal mixer;
  in-game music controls or the Sound setting should be used to silence it.
- Restart Game prompts before discarding unsaved progress and relaunches after
  the old supervisor exits. A bounded diagnostic log retains startup and recent
  output; failed launch messages point to setup/discs/settings.

## Validation

`DOSOptionsChecks`, `DOSDiscChecks`, `DOSGameDataChecks`, and `DOSLaunchChecks`
passed. Disc checks mounted authored ISO, CUE/BIN and FAT12 floppy fixtures in
DOSBox Staging 0.83.0. DOSLaunchChecks validated game vs setup vs prompt routing,
arguments, executable failure, and original-file preservation.

`check-native-games.py` passed with a real authored DOS COM executable writing
its own save and reopening with the same private files. The full existing
`check-native-sandbox.py` suite passed, including unrelated-file and network
denial, allowed save writes, symlink escape denial, and child termination.
The final packaged archive helper also extracted a real ZIP using legacy
Implode compression while its traversal, collision, expansion, timeout, and
checksum rejection checks remained green.

## Practical limits

This is not a promise of compatibility with every title. It uses the existing
SVGA / 16 MB DOS machine default. Emulated game executables still require
compatible DOS 8.3 paths. Long host storage paths are supported subject to DOS
command limits, but arbitrary long guest launch names are not normalized.
Arguments are simple tokens; command chaining and quoted strings are rejected.

Disc-only libraries/installers and Windows games are not automatically turned
into DOS game entries. Attach discs to an imported DOS game first. General
MDF/MDS, emulator save states, network multiplayer and MT-32 ROM management are
not implemented. The first-use Windows 98 work is described separately in
CLASSIC-WINDOWS-DEVELOPMENT.md and is not ready for library Play.

Physical controller behavior, arbitrary game audio, and all game-specific
installers require title-level tests. No public release is authorized.
