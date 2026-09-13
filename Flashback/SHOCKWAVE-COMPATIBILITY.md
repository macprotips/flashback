# Shockwave compatibility — Flashback 1.11.0 development build

The current runtime adds a shared invalid-member type fix and repeatable
nonvisual health reports to the 1.10.0 Director repairs. Every recorded result
must identify the exact runtime that produced it. See
`COMPATIBILITY-RESEARCH.md` for the investigation.

Checked September 10, 2026 on Apple Silicon. Shockwave remains experimental.
Flashback rebuilds [DirPlayer source revision 68376fb](https://github.com/igorlira/dirplayer-rs/tree/68376fbb4494a6bbad4c70081ecdcb99814a74c9)
with `dirplayer-compat.patch`. The exact patched source, companion Xtra/Ruffle
sources, dependency archives, and rebuild instructions accompany the release.
See `SOURCE.md`; the companion assets retain their pinned 0.8.1 versions.

## Changes

- Treat a missing cast-member reference as `#void` when Lingo reads `.ilk`,
  while retaining `#member` for a valid reference. Redline Rumble Revolution
  used that check while constructing its menu data; the old runtime raised on
  the invalid reference before the menu could open. The shared VM fix has unit
  coverage for invalid and valid cast references.
- Load optional per-game launch profiles only by an exact SHA-256 match on the
  imported entry movie. The versioned registry rejects duplicate identities,
  malformed hashes, unsafe values, `src` replacement, and oversized input.
  Profile use is included in runtime diagnostics. The initial registry is
  empty: no title currently needs a profile to conceal a runtime failure.
- Write a `Health.json` report for every collection and corpus probe. It records
  exact errors, call stacks, missing resources, frame/image/game-state changes,
  delivered input, and audio evidence. Only an authored input-driven game-state
  assertion is called gameplay; a moving title screen remains active evidence.
- Add a clipboard compatibility report to the Shockwave player so a user can
  return the exact entry hash, runtime state, errors, recent console output,
  call stack, and applied profile immediately after a problem.

- Validate a score entry's header before reading it as a sprite span. Fifteen
  titles contain a 40/48-byte entry holding text rather than a span; each one
  raised its movie's frame count to between 1.4 and 2.0 billion, so the
  playhead never looped back and ran on into empty frames. Those titles now
  report between 17 and 16943 frames.
- Read a movie property written with call syntax, such as
  `_movie.markerlist()`. A call carrying arguments still reports a missing
  handler, so a genuinely absent method stays visible.
- Read a vector's components by index, `vec[1]` through `vec[3]`.
- Record a package's own missing resources in the collection manifest, so a
  placeholder that the original archive never contained is not counted as a
  launch failure. Every other missing file still fails its title.
- Three more Miniclip titles have recorded gameplay conditions: Beach Soccer,
  American Football and Free Running. Free Running was found by sweeping the
  titles that had never been driven with input — its record said its game
  object was not initialized, and it initializes fine once its preloader is
  allowed to finish.

The 1.9.0 changes remain:

- Restore sprite ancestor delegation, dynamic local assignment, numeric-looking
  member names, and Director symbol conversion used by Courage's game events.
- Recover 33 original projector launchers with byte/hash provenance. ZIP imports
  now extract a single compressed bootstrap from the original projector, and the
  entry picker prefers it, and indexed external parameter reads
  now distinguish parameter positions from literal numeric names.
- Apply queued embedded Flash initialization before waiting for SWF startup;
  return default Flash variable values as strings, as Director specifies.
- Map symbolic Flash properties and root clip paths correctly, and await Flash
  readiness before property access. Galidor's character parts now render.
- Preserve quoted script names and stable object identities in Director offspring
  strings; recognize object subtypes in `ilk(value,#object)` checks. Galidor's
  scene registry now retains its separate elements and entrance locations.
- Return `#member` for script cast-member `.ilk`, allowing Backlot's launcher
  to reach its runtime script assignment; dynamic compilation remains unsupported.
- Support indexed transform-property writes used by Creepy Pong's ball graphics.
- Search live cast members when allocating fields and bitmaps; decode the
  compiled last-item deletion used by Galidor's resource loader.
- Resolve repeated internal path separators and cct/cst alternatives while
  retaining exact-file priority and path containment checks.
- Handle field highlighting, latest network-operation IDs, ordered movie-script
  lookup, empty window-list resets, pause-state reads, and audio preferences.

The 1.8.0 and earlier repairs remain:

- Upgrade from the 0.8.1 VM to the pinned newer source revision.
- Route rollover events to the frontmost interactive sprite, allowing buttons
  under decorative artwork to receive hover events. This unlocks Merlin 1's
  Start button while avoiding simultaneous rollover on stacked buttons.
- Map native pointer input against the actual displayed canvas. macOS/WebKit
  page zoom and window resizing previously displaced clicks from the artwork.
- Store and honor Director's `idleHandlerPeriod`, in 60 Hz ticks, between
  score frames. Missile Command no longer stops on this property.
- Preserve readable/writable host-control flags, stage `resizable`, and
  mutable `titlebarOptions` / `appearanceOptions` property lists. These retain
  the game's requested values; Flashback owns the native window controls.
- Recover matching launch parameters from nearby HTML files in folder/ZIP
  imports, including World Builder's local launcher. Website imports retain
  Director object/embed parameters, custom values, and `data-sw-*` settings.
- Canonicalize the import directory before checking relative containment,
  fixing imports through macOS `/private/tmp` and `/tmp` aliases while keeping
  traversal and symlink escape checks.

Recovered settings are passed as inert parameters before the movie starts.
The page's own game outranks equally strong related-page matches. Recoverable
console messages stay diagnostic; fatal initialization, JavaScript, and Lingo
errors still show the native compatibility error. Games remain offline.

## Tested interactions

**23 of 24 tested titles pass their recorded opening-gameplay condition.**
Backlot remains limited and is listed below.

The table records opening interactions, not whole-game completion. A title
screen alone is not counted as successful gameplay. Native mouse/keyboard
inputs drive these checks; read-only runtime inspections assert the resulting
state. No game code or save is changed to force a successful result.

| Original game | Recorded scope |
| --- | --- |
| Rapunzel's Escape | Start the first level and move the playable character. |
| LEGO Supersonic RC | Load the external GUI cast, navigate menus, enter the 3D driving level, and use driving controls. |
| Merlin's Revenge 3 | Pass the introduction and move in the first playable map. |
| Merlin's Revenge 1 | Recover original page parameters, pass Start/introduction, and move in the first playable map. Previously stopped at the title screen. |
| Merlin's Revenge 2 | Pass the title/introduction, enter game mode, and use movement input. |
| Breakout Lite | Launch the ball, move the paddle, and break bricks. |
| Centipede | Start the game and score with the fire key. |
| Frogger | Start the game and score with upward movement. |
| Missile Command | End the attract sequence, start a game, and fire at native pointer positions. |
| Super Breakout | Select Double mode, start play, and move the paddles. |
| LEGO Junkbot | Enter a level, move a brick using native drag/click input, and increase the move counter. |
| LEGO World Builder | Recover the local HTML launch setting, enter Mission 1's tutorial, pan the map, and advance its right-scroll step. Later construction/combat is unverified. |
| LEGO Studios Backlot | Limited: launcher replacement scripts require unsupported dynamic Lingo compilation. No playable level verified. |
| Creepy Pong | Recover the original launcher, choose a bat and opponent, enter a 3D match, move the bat, and strike the ball with native mouse drag. |
| Courage in Creepy TV | Complete the introduction, collect food and a can opener, and verify kitchen state and artwork. A separate interactive session completed the full tutorial. |
| Nabisco Mini Golf | Recover the launch settings, choose Practice, and record the first stroke. |
| Air Show | Recover the original launcher, choose an aircraft, pass the demonstration, and fly with native controls while the countdown runs. |
| Donkey Kong Country Barrel Maze | Recover launch settings, enter the maze, and move the barrel. A separate session also checked collision and respawn. |
| Great Firework Race | Start the race and accelerate using the native Shift modifier. Steering and a completed lap are unverified. |
| Galidor Quest | Build a visible character, enter at the intended tutorial entrance, move with the mouse, and jump with V. Online saving and later levels are unverified. |
| Beach Soccer | Recover the original launcher, start a match from the title screen, skip the briefing, swap the controlled player, and kick off; the ball leaves the centre spot and the 3D match runs with both teams. Scoring and later matches are unverified. |
| American Football | Recover the original launcher, choose a team, skip the briefing, and snap the ball; the ball moves from its snap position in a 3D match with both teams. Completing a drive is unverified. |
| Free Running | Recover the original launcher, start the first level from the title screen, and run with the up arrow; the character moves along the roof while the level timer runs. Later levels and scoring are unverified. |
| Monster Bash | Animate the complete 109-bone character, pick up the club and skull, throw and hit the skull with native Space input, increase the hit counter, and enter game-camera tracking. |

The first four tests additionally check native keyboard input, audio, resizing,
full screen, minimize/restore, offline requests, persistent Director preferences
across restart, recent history, and player/library rendering. Their checks pass.
Merlin 1 without its required page settings intentionally fails with `goTitle`;
a negative check requires that error to remain visible.

Run from the project root, using new output directories:

```sh
./Flashback/check-shockwave.sh /tmp/flashback-shockwave-core
python3 Flashback/check-shockwave-corpus.py /tmp/flashback-shockwave-corpus
```

The first command downloads four original fixtures and verifies their hashes.
The second verifies twenty additional game cases from original archived
movies and packages. It prints per-game results and writes `Results.json`, screenshots,
input/state snapshots, `Health.json`, and the exact `Probe.json` sequence. Known limited cases
are reported as LIMITED and do not become PASS merely because a movie opens.
The collection launch survey is separate: `check-shockwave-collection.py`
records opening observations, with `--wait 15` for slower preloaders.
Use `--games NAME ...` for a subset, `--fixtures PATH` for a previously verified
cache, and `--baseline` to collect failures without requiring the improved level.
`--app PATH` selects the corpus app; `FLASHBACK_APP` selects the core-check app.
Use a copy with a distinct bundle identifier if the normal app is already open.
Fixtures, screenshots, and temporary libraries stay outside the release.
Each run writes `Runtime.json` recording the runtime that produced it, and every
result in `compatibility-results.json` carries that hash — a recorded result
only means something beside the build it came from.

To summarize an individual native probe without looking at its screenshots:

```sh
python3 Flashback/shockwave_health.py /path/to/probe-output
```

`FAIL` preserves runtime exceptions, unexpected missing resources, and early
initialization stacks. `STALLED_EVIDENCE`, `ACTIVE_EVIDENCE`, and
`OPENED_UNVERIFIED` guide investigation but are not passes.

The Shockwave runtime's own source is checked separately:

```sh
python3 Flashback/check-dirplayer-patch.py
```

That applies `dirplayer-compat.patch` to the pinned upstream archive and diffs
the result against the supplied source tree, so the corresponding source a
recipient rebuilds from is verified rather than assumed.

A separate host regression check verifies property assignment/readback and
restoration, including fresh reads of the mutable window option lists. It
verifies that an archived movie address and the original `src` value reach Lingo. It also
requires native hover and click coordinates within one movie pixel at three
window sizes. Its test-only window reference is separate from all gameplay assertions.
The shipped runtime passes this check:

```sh
mkdir /tmp/flashback-shockwave-host
cp Flashback/shockwave-host-probe.json /tmp/flashback-shockwave-host/Probe.json
./Flashback.app/Contents/MacOS/Flashback --shockwave-probe /tmp/flashback-shockwave-corpus/Fixtures/Hasbro.zip Games/missilecommand.dcr /tmp/flashback-shockwave-host
```

## Limits

Galidor's native replay verifies a visible character, the intended entrance,
mouse movement, and a V jump in the first tutorial area. Its original
`game.asp` service is unavailable. Its replay records that service and the
archived `dummy.cct` placeholder as expected missing resources; other missing
resources still fail the check. Longer gameplay and online saving are unverified.
On The Run 2 stops in its own start movie: the Miniclip services object its
recovered launcher builds has no `validateLocation` handler, so the check the
game makes before starting raises. Backlot needs executable handlers compiled
from assigned Lingo `scriptText`, which this runtime does not yet support, and
has no verified playable level. Basketball Slam draws its menu but its
selections did not answer native clicks in this round. The rest of the Miniclip
titles reach a title screen or a menu; those observations do not certify
gameplay, and the two that now have recorded conditions needed roughly sixteen
seconds of preloading before their menus answered a click at all.

This is a deliberately varied convenience sample, not a random survey of the
Shockwave catalog. It does not establish that most existing Shockwave games
work. Some menus need a second click after their transition or rollover.
Unsupported Director versions, Xtras, Flash callbacks, and missing game servers
can still prevent play. Supersonic RC and Monster Bash have verified 3D
interactions. Longer sessions, every level, multiplayer, and server saves are untested.
Preference persistence is not an emulator save state.

Use Add from Website when a bare movie lacks its original page settings, or
import its complete original folder/ZIP including the launcher and sidecars.
An existing import cannot recover settings that were never saved; import it
again from the complete source. The native error explains these recovery paths.
Intel binaries are built and verified, but gameplay on Intel hardware and older
macOS versions has not been run here.
