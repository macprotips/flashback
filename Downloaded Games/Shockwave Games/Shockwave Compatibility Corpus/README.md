# Shockwave compatibility corpus

**105 games in 85 preserved packages, about 1.64 GB**, prepared September 10, 2026 for Flashback/DirPlayer compatibility work. The collection contains 192 Director movies (130 distinct movie hashes), 105 cast libraries, 247 external W3D files, 45 SWF sidecars, and 36 preserved HTML pages. The movie count includes loaders and wrappers; it is not a game count.

[Browse all games](INDEX.md) · [Game manifest](games.json) · [Package inventory](packages.json) · [Download provenance](download-sources.json) · [File hashes](SHA256SUMS.txt)

## How to use it

Import a game's complete folder under **Games**, then choose the movie listed in the index. Preserve its internal directories. Importing a lone DCR can omit casts, models, sounds, or the original page settings. Where an archive supplies several loaders or wrappers, the alternatives are listed in `games.json` for investigation.

**Original Archives** contains 75 untouched ZIPs. The extracted folders preserve game asset bytes and relative paths. Windows executables, DLLs, native Xtras, and macOS resource-fork metadata stay inside those original ZIPs; they were not installed or run. An Xtra bundled with a generic Windows projector is not evidence that a particular game requires it. `packages.json` lists these members for reference.

The five Metal Box fixtures were copied from the project's existing verified caches and checked against its pinned hashes. Other original downloads were verified against Internet Archive metadata. This is a collection of preserved builds: uploader modifications to historical games have not been independently audited.

## A useful order for compatibility work

| Area to exercise | Starting games | What to establish |
| --- | --- | --- |
| Basic Lingo, sprites, text, input | Centipede, Frogger, Missile Command, Super Breakout, Breakout Lite | Start play and demonstrate an input-driven score, ball, or sprite change |
| Menus, action, and timing | Merlin's Revenge 1–3, Rapunzel's Escape, Nintendo webgames | Advance through menus, move, interact, and survive more than one screen |
| External cast loading | Galidor Quest, Candystand Mini-Golf, Oreo Adventure | Resolve casts locally, enter a playable scene, and transition to another area |
| 3D assets and rendering | Free Running, On The Run 2, Turbo Racing 2, Battle Wheels, Redline Rumble 2 | Load models/textures, reach gameplay, move the player or vehicle, and verify collisions |
| Flash sidecars and preloaders | Creepy Pong and the Miniclip packages with SWF files | Distinguish a stuck loader from a working main game; inspect callback failures |
| Movie handoffs | Donkey Kong Country Barrel Maze, Wario's Whack Attack, LEGO Studios Backlot | Follow the original loader-to-game path with all assets available |
| Older containers and source movies | NiGHTS, the Nintendo/Eidos sets, Merlin 3 and Rapunzel source movies | Record parser/version gaps and compare movie/cast state before changing runtime behavior |

These are suggested investigations. Package contents guide the selection; they do not establish which emulator feature is responsible for a failure. First distinguish an emulator error from a missing asset, absent launch parameter, or unavailable online service. Downloading these files has not changed the emulator.

## Existing reproducible checks

**Probes** contains 10 copied `Probe.json` files from the repository's existing corpus checker, each matched to the exact source hash: seven opening-gameplay assertions and three diagnostic-only probes. The diagnostic cases are Backlot, Creepy Pong, and Monster Bash; a rendered title or 3D scene is not counted as gameplay. Three further games have existing checks in `Flashback/check-shockwave.sh`.

The checked-in [compatibility record](../../../Flashback/SHOCKWAVE-COMPATIBILITY.md) describes earlier test results. **Those checks were not rerun during collection. Every new game entry is marked NOT_TESTED.**

For example, from the project root, run the existing Centipede probe with a fresh output directory:

```sh
mkdir /tmp/shockwave-centipede-new-run
cp "Downloaded Games/Shockwave Games/Shockwave Compatibility Corpus/Probes/centipede/Probe.json" /tmp/shockwave-centipede-new-run/Probe.json
./Flashback.app/Contents/MacOS/Flashback --shockwave-probe   "Downloaded Games/Shockwave Games/Shockwave Compatibility Corpus/Games/Hasbro Interactive Shockwave Games"   "Hasbro Interactive Shockwave Games/Games/centipede.dcr"   /tmp/shockwave-centipede-new-run
```

This launches the native test app. The existing harness writes its result, runtime details, and captures into the output directory. `games.json` provides the import folder, relative entry path, and probe path for each available case. For additional games, record normal menu/input steps and add an observable gameplay assertion before classifying a result as a gameplay pass.

Merlin 1 and 2 include small, clearly identified generated `launch.html` descriptors carrying the original site's required parameters. Their game files are unchanged; the launch settings also appear in `games.json`. Other supplied HTML files are preserved assets.

## Integrity and boundaries

All 133 source files match their recorded hashes. Internet Archive files match its published byte counts and MD5 hashes; the reused Metal Box fixtures match the repository's pinned SHA-256 values. All ZIPs passed CRC checks. Every indexed Director movie and cast has a RIFX/XFIR header. Two files have bytes beyond their container's declared length; these bytes are preserved unchanged and recorded in [container-size-notes.json](container-size-notes.json).

`files.json` and `SHA256SUMS.txt` cover 973 original-archive and game-asset files. Generated launch descriptors, copied probes, and explanatory documents are kept separate from original-asset counts. `download-sources.json` contains exact URLs and hashes; `packages.json` records all movie alternatives, asset lists, and archive-only native files.

A package tagged as LEGO The Robot Chronicles turned out to contain Flash SWFs and was excluded from this Shockwave collection. The prior Junkbot, Supersonic RC, and Snowcraft downloads remain in [Shockwave Classics](../Shockwave%20Classics/), giving the library **108 Shockwave titles** in total. They were not duplicated here.

## Source collections

The largest groups came from [Miniclip Shockwave Games](https://archive.org/details/miniclip_shockwave-games), [Nintendo webgames](https://archive.org/details/nintendo-shockwave-webgames), [Eidos webgames](https://archive.org/details/eidos-shockwave-webgames), and [Hasbro webgames](https://archive.org/details/hasbrointeractive). Individual sources for every other title are in the index and manifest. No game servers or online accounts have been reconstructed.
