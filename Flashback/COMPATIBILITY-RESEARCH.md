# Flash and Shockwave Emulation Compatibility

## Flashback 1.10.0 investigation

This round relaunched every indexed title against the runtime the application
actually ships, rather than against the several intermediate builds the 1.9.0
survey had accumulated, and traced the failures that survey exposed. Three
runtime defects were found and repaired, each with a unit test and a native
check. Current results are in `SHOCKWAVE-COMPATIBILITY.md` and
`compatibility-results.json`; the 1.9.0 and 1.8.0 investigations are retained
below as history.

### One runtime for every recorded result

The 1.9.0 launch survey had been assembled from four partial runs against three
different polyfill builds, none of them the one that shipped. Each title's
recorded hash made that visible, and closing it was the largest single evidence
gap in the release. Relaunching all 105 titles against the shipped runtime is
also what produced the three defects below: two of them were invisible until
the whole collection was measured with one build.

### A text entry parsed as a sprite span

Director's score stores behaviour-attachment entries of several shapes. The
parser accepted any 40, 44 or 48-byte entry as a sprite span on its size alone,
validating the header only for the 52-byte-and-larger case. Fifteen of the
collection's titles contain an entry of one of those sizes whose bytes are
text, so a span was built from it: Doomsday's `end_frame` read back as
`0x6c756769` — the ASCII `"lugi"` — and Donkey Konk's as `0x526f6c6c`,
`"Roll"`. Excitebike, F-Zero X Academy Garage, Kremling Krunch, LEGO World
Builder, Mario's Memory Madness, Merlin's Revenge 1 and 2, Missile Command,
Operation Flashpoint, Pizza Hot, Stunt Sled, Super Breakout and Wario's Whack
Attack all carried one.

A movie's `frame_count` is the maximum over its spans, so a single such entry
set it to between 1.4 and 2.0 billion. `get_next_frame` loops the playhead back
to frame 1 only when the next frame would pass `frame_count`, so these movies
never looped: the playhead ran on into frames that hold nothing, which presents
as a stalled black stage rather than as an error. The same plausible-header
check the 52-byte case already applied now guards the smaller sizes, and an
entry that fails it is skipped as before. All fifteen titles now report between
17 and 16943 frames. The four titles that already had recorded gameplay
conditions — Missile Command, Super Breakout, LEGO World Builder and Merlin's
Revenge 2 — still pass them.

### A movie property read through call syntax

Redline Rumble Revolution's `[M] Misc.goto` reads the movie's marker table as
`_movie.markerlist().count` and `_movie.markerlist()[i]`, with parentheses.
Director accepts that form for a movie property, but the parentheses made the
name arrive as a handler call rather than through the property path, and the
title stopped during its preload with "No handler markerlist for datum
<_movie>". A bare `receiver()` call that names no built-in handler now falls
back to the movie property table; a call carrying arguments still reports
HandlerNotFound, so a genuinely missing method is still a visible failure.

### Vector components read by index

Director exposes a vector's three components by index as well as by name.
American Football's opening play reads its positions that way and stopped with
"Cannot get sub-prop `1` from prop of type vector". Subscripting a vector now
returns the matching component, and an out-of-range subscript reads VOID, which
is the rule the neighbouring list case already followed.

### Two more titles from the Miniclip engine

Air Show and Creepy Pong already had recorded gameplay conditions from this
engine. Beach Soccer and American Football reach live 3D play from their own
title screens once their preloader is allowed to finish — at the survey's
eight-second capture both are still on a black frame, which is what the earlier
launch record showed for them. Their new cases wait for the preloader, work
through the original menus with native clicks, and assert live match state:
before those clicks every one of the asserted game properties is VOID, so a
title screen cannot satisfy the condition. Neither case claims a completed
match. Basketball Slam renders its menu but its selections did not answer
native clicks in this round; it stays an observation.

### Test-order dependence in the runtime suite

The runtime unit suite serialises tests that stand up a player, because the VM
keeps its state in global statics. One test interned a symbol without taking
that lock, which raced whichever test held it, so two object-identity tests
failed or passed depending on the thread scheduling of the run. The recorded
"135 passed, 0 failed" was therefore a scheduling outcome rather than a
property of the code. The lock is now available to tests that touch global
state without a whole player, and the suite is 138 tests.

## Earlier investigation: Flashback 1.9.0

The 1.9.0 round expanded launch inspection to every one of the 105 indexed titles, then used interactive native sessions to trace failures and add gameplay replays. Opening captures remain observations even when no script error occurs. Several black preloaders need more than four seconds; the collection runner accepts `--wait` so delayed titles can be distinguished from permanent stalls. This section and the 1.8.0 section below are kept as history — current results are in `SHOCKWAVE-COMPATIBILITY.md` and `compatibility-results.json`.

### Shared repairs

Courage in Creepy TV exposed several independent defects: string chunks were not accepted as cast member names; dynamic `do` assignments selected the wrong local scope; script instances with native sprite ancestors did not delegate sprite operations; and a missing numeric-looking member name incorrectly fell back to an unrelated numbered slot. Symbol conversion also retained punctuation that Director discards, so the game never recognized its tile/event commands. Repairing those paths restored the kitchen artwork, collision, item collection, combination, and tutorial events. A native session completed the tutorial; the automated replay checks the earlier food/opener inventory state and room rendering.

Mini Golf, Barrel Maze, and Ferrari require parameters checked by their authored initialization handlers. The local HTML settings were reconstructed from those movie scripts; they are not archived copies of the original web pages. The settings are stored beside the unmodified movies. Imports now resolve doubled internal path separators and compressed/uncompressed cast suffix alternatives when the requested exact file is absent, while retaining containment and symlink checks. This repairs the observed Oreo Adventure and Redline Revolution resource lookups.

Many Miniclip archives contain a Director bootstrap inside their Windows projector. Reading the archive bytes recovered 33 launchers with their original initialization code. Each recovered movie records the archive hash, member, byte offset, length, and movie hash; `recover-shockwave-launchers.py` verifies or recreates the extraction. No executable was run and no game script was rewritten. ZIP import now extracts an unambiguous compressed bootstrap into its temporary staging folder. Bounds checks reject truncated data, multiple candidates are not guessed, existing files are preserved, and older Windows launcher stubs are excluded. The import picker prefers the recovered launcher. Indexed external parameter reads were corrected so these launchers receive the values already preserved by the host.

Creepy Pong then exposed a race in the embedded Flash bridge. Queued initialization writes could replay after the SWF had declared itself loaded, resetting its readiness flag. The queue now drains before the startup wait. Director also expects the default `getVariable` return value as a string, including `"true"` for a Flash Boolean.[^8] Returning an integer prevented the authored comparison from succeeding. The next failure occurred on indexed writes to a transform property; forwarding those writes to the existing transform setter allows a native match to start and a mouse drag to strike the ball.

Galidor exposed the cast allocator using the original movie member limit after new members had been created. Repeated allocations overwrote the same slot, replacing fields with text members. Both `findEmpty` entry points now search the live cast. Its compiled last-item deletion also carried an item selector in the character operand; decoding that selector restores the intended external cast filename and resource keys. Further debugging found that its character parts are embedded Flash clips. Symbolic properties such as `#posX`, `#posY`, and `#visible` were all converted to numeric property zero, and unqualified clip paths did not reach the Flash root. Shared property mapping and root-path resolution now preserve the intended values; property reads and writes also use the existing Flash readiness queue.

Galidor's scene registry exposed a separate identity defect: Director offspring strings require a quoted script name and a stable final identity token. The previous formatter put an underscore in that final position, causing distinct scene elements to overwrite the same registry key. The formatter now retains the actual reference count and a unique instance identifier, and `ilk(value,#object)` recognizes object subtypes without changing their primary ilk. The tutorial now registers 26 elements and three entrances, spawns the visible character at its intended entrance, and responds to mouse movement and V jumps. The native regression asserts movement, the three entrances, Flash visibility, and the airborne jump state. The archived `dummy.cct` placeholder and unavailable `game.asp` service are explicitly recorded as expected missing resources for this case; all other missing resources still fail it. Online saving remains unavailable.

Backlot's launcher retains replacement script text across its movie switch. Stepping its original bytecode showed that script cast members incorrectly reported `#script` for `.ilk`, causing its `#member` check to skip installation. Correcting that shared property makes the launcher reach the assignment. The next blocker is unsupported dynamic Lingo script compilation: `scriptText` stores source but does not create executable handlers, and cast duplication/movement does not transfer the stored override. Backlot remains limited with no playable level verified; changing its globals or rewriting its original launcher would not establish runtime compatibility.

Other observed failures led to shared support for `getLatestNetID`, compiled field highlighting, deterministic movie-script handler ordering, clearing an empty window list, pause-state reads, and sound-device preference readback. The host retains device ownership; the preference does not grant a game direct access to a macOS audio device.

### Repeatable evidence

`shockwave-session.py` drives native clicks, drags, keys, and modifier events while preserving each command, screenshot, and read-only state query. Debug stack inspection now preserves argument markers, avoiding a diagnostic operation changing execution. The offline script inspector decodes original files without running them. Barrel Maze also exposed a native test-driver fault: sending `mouseMoved` through the responder chain did not deliver hover to WebKit. The driver now routes that event to the existing AppKit tracking-area owner, matching [WebKit’s native tracking route](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/mac/WebViewImpl.mm). The host check asserts hover and click positions separately at three window sizes. New gameplay cases cover Courage, Mini Golf, Air Show, Barrel Maze, Great Firework Race, Creepy Pong, and Galidor. Original archive/movie hashes are checked before import, and the runner records the runtime hash. These are opening-interaction checks; they do not certify all levels, server services, or the rest of the catalog.

## Earlier investigation: Flashback 1.8.0

Flashback’s most immediate compatibility gains come from correcting Director’s animation and launch behavior. The supplied collection is predominantly Shockwave, and its jungle creature game is Monster Bash. In the previous build that game displayed an undeformed character and did not progress through its opening sequence. The revised runtime loads its complete skeleton, animates the character upright, responds to native input, records a successful hit, and follows the moving skull with the game camera.

This is a measured improvement in opening gameplay, not a claim that the collection is fully supported. Other games still stop at missing resources, incomplete launch context, or unsupported runtime behavior. The accompanying compatibility results distinguish those failures from games that merely open. Findings and upstream versions were checked on September 10, 2026; runtime measurements were made on Apple Silicon with Flashback’s WebKit host.

### Collection and scope

The collection index contains 105 game entries across 85 packages, alongside three separately supplied classics. A filesystem inventory finds 179 `.dcr`, 15 `.dir`, one `.dxr`, 105 `.cct`, one `.cst`, 247 `.w3d`, and 45 `.swf` files. These are file counts: multiple launchers, external casts, and shared assets can belong to one title. In particular, the 45 SWFs do not establish that there are 45 independent Flash games.

The distinction determines where engineering effort belongs. Flashback runs ordinary SWFs through Ruffle 0.6.0. Director movies run through the patched DirPlayer VM, with its own companion Ruffle integration for Flash media embedded inside Director. Updating the standalone Flash player does not automatically change the embedded player or repair Director’s Lingo, score, cast loading, or 3D animation.

| Content | Runtime responsibility | Typical supporting data |
| --- | --- | --- |
| Flash SWF using ActionScript 1 or 2 | Ruffle AVM1 | Other SWFs, images, sound, XML, launch variables |
| Flash SWF using ActionScript 3 | Ruffle AVM2 | The same asset classes, plus APIs used by the particular program |
| Director DCR/DIR/DXR | DirPlayer | External casts, W3D scenes, media, Lingo or JavaScript syntax scripts |
| SWF embedded in Director | DirPlayer and its companion Ruffle bridge | Flash media plus calls and callbacks between the two runtimes |
| Game relying on a remote service | Game runtime and a separately preserved service | Protocol behavior and data; local game files alone may be insufficient |

For SWF classification, the file version is insufficient by itself. Adobe’s format describes the ActionScript 3 flag in `FileAttributes`, as well as distinct script tags. A later-version SWF can still contain AVM1 content; inspecting the actual tags is more reliable than assigning a runtime from a filename or year.[^1]

### Emulator landscape

Ruffle remains the practical Flash engine for this application. Its published compatibility page distinguishes language implementation from API implementation: AVM1 is reported at 99% language and 82% API, and AVM2 at 90% language and 82% API. Those are upstream implementation measures, not percentages of games that will pass Flashback’s tests. A title can depend heavily on a single incomplete API, an unavailable resource, or a host behavior outside those measures.[^2]

The independent player already uses Ruffle 0.6.0, the stable release published September 6, 2026. That release includes relevant work on AVM2 matrices, text, rendering, audio, and loader behavior. A newer development build should be evaluated against a reproducible failure before being adopted; the existence of newer commits is not evidence that they solve a particular game.[^3]

DirPlayer’s bundled source base is commit `68376fbb4494a6bbad4c70081ecdcb99814a74c9`, also the upstream head observed during this investigation. Its release package is 0.8.1, while Flashback rebuilds the newer pinned source with local compatibility changes. The companion Ruffle revision is `79d1ca0f45d79e28c3a0658bbc6b8430d26ef308`. Recording these separately is essential: “Ruffle version” alone does not identify the full execution path of a mixed Director/Flash game.[^4]

Flashpoint provides a useful preservation model: retain original addresses and paths while serving archived content locally. That model supports games whose resource references were authored around their original web environment.[^5] For Flashback, the corresponding recommendation is to preserve the original entry address, base address, parameters, and URL-to-file mapping together. This can recover legitimate launch behavior without editing the movie’s instructions.

ProjectorRays is useful for recovering Director script structure and inspecting authored behavior. Its stated purpose is decompilation, so a successful decompile should not be treated as evidence that the game executes correctly.[^6] The same distinction applies to the VM’s inspection helpers: they reveal state and script behavior; gameplay must still be demonstrated through input.

### Measurement method

The investigation began with 23 selected titles spanning older 2D games, later 3D games, external casts, and Flash preloaders. The original entry files were checked against their recorded SHA-256 values before each run. A native test instance imported the complete selected package, opened the specified movie, and recorded screenshots, runtime state, missing-resource reports, and script errors.

Eight of those baseline runs reported a startup or missing-resource failure. Fifteen reached the observation stage, which only means the host could capture them after opening. Several of those fifteen showed black frames or stalled content. An observation is therefore intentionally weaker than a gameplay pass. The final launch-only rerun recorded six failures and seventeen observations; the two changed preloader outcomes do not establish additional playable games.

Follow-up work used read-only inspection of globals, cast members, active handlers, animation state, and decompiled script logic. Mouse and keyboard events came through the native host. No game variable was set to force a score, skip a loader, change a location check, or advance a level. Source game files were kept unchanged.

The existing 15-title regression set supplies a separate, stronger measure. Its assertions cover a specified interaction in each game: for example, movement in a level, breaking a brick, increasing Junkbot’s move count, or reaching World Builder’s tutorial step. Monster Bash now has a successful-hit assertion in that harness. Long play sessions, every level, online high scores, and multiplayer remain outside those checks.

The test platform matters. A successful WebKit run on Apple Silicon does not establish matching behavior on Intel hardware or every macOS release. Both CPU architectures can be compiled, but that is a build result rather than a substitute for gameplay on each architecture. Likewise, parser tests cannot establish correct GPU rendering; native screenshots and input checks are needed alongside them.

### Monster Bash: causes and implementation

The visible T-pose had several independent causes. Fixing only one of them would have left either a frozen game sequence, an incomplete character, or a rotated character.

**Skeleton parsing.** The W3D skeleton block stores optional minimum/maximum values for constrained rotation axes. The old parser read each bone’s attributes but did not consume these optional values. On Monster Bash, the following bytes were then interpreted as another bone name, and the 109-bone skeleton failed to parse. The updated parser consumes each optional pair when the axis is both active and limited, and rejects truncated bone data. The values keep parsing aligned; this change does not implement an inverse-kinematics constraint solver.

The flag interpretation is a finding from the supplied binary corpus. A structural scan examined 548 Director, cast, and W3D files and found 564 distinct W3D streams containing 112 skeleton blocks. With the former interpretation, 105 blocks could be traversed; with the corrected interpretation, all 112 could be traversed. The seven newly readable blocks belong to two Monster Bash rigs, White Water Rafting’s boat rig, and four Doomsday rigs. This demonstrates wider parser coverage; it does not establish that all three games are completely playable.

**Bone palette.** The renderer previously uploaded at most 48 bone matrices and clamped larger bone indices. Monster Bash needs indices beyond that limit, including its arms and legs. The updated renderer stores the complete matrix palette in an RGBA32F texture, four texels per matrix, and retains the original indices when selecting vertex influences. WebGL 2 provides the required texture sampling facilities.[^7] A regression check verifies that indices 48, 80, 108, and 109 survive packing in weight order.

**Model orientation.** A historical correction rotated passive skinned models after scene transforms had already been resolved. Once the skeleton became readable, this laid the monster sideways. Skinned meshes now use the same resolved model transform as the rest of the imported scene. The parser’s root-center transform and the corresponding inverse in the skin palette remain paired; the extra model rotation is removed.

**Animation events.** The game registers animation-start and animation-end callbacks to advance its authored state machine. Registration was retaining the name of the registration method rather than the requested callback, and animation notifications were not dispatched. The runtime now retains the requested handler and emits notifications from the shared animation clock. Callback invocation happens after the mutable state borrow is released, allowing game code to queue motions or register another timer safely.

**Queue and timer behavior.** A queued motion can start when its player has no active motion or has completed the preceding one. Starting or resuming playback resets the start-notification state. Timer dispatch also uses the correct one-based cast-library number, so the first library is not revisited in place of the next and the final library is not omitted. Director’s scripting reference documents the queue and animation notification concepts used by this implementation.[^8]

The observed native sequence is now: opening animation, club pickup, skull pickup, throw, swing, a positive `myNumWhacks` value, and `doGameCam = 1`. The character’s pose visibly changes and remains upright. The successful-hit condition is much stronger than an animated title screen, while still being limited to the tested opening interaction.

### Shared launch and language improvements

Recovered website imports now expose the archived Director entry address to the VM. Previously the host always supplied its internal local address. That distinction matters when a game reads its movie path, passes addresses to an embedded SWF, or resolves another cast relative to its entry movie. The existing URL mapping continues to serve requests from imported files.

The Director polyfill also retains `src` in the external parameter set. The host already constructs this value from the selected movie; dropping it inside the polyfill made `externalParamValue("src")` unavailable to authored startup logic. Retaining it makes the recorded launch context more complete. It does not invent an original website address for a package that has no such evidence.

The Lingo `.symbol` property is now supported for strings and for values already represented as symbols. This follows the language’s documented string-to-symbol conversion.[^9] Courage in Creep TV previously stopped at that missing property. It advances beyond that error with the change, but later stops during initialization, so it remains limited rather than being counted as newly playable.

Failure diagnostics now include active call frames, the relevant decompiled handlers, scripts, globals, and cast members. The stack helper reports only active frames rather than unused scope capacity. This makes a missing built-in distinguishable from an authored error path that calls an unsupported command. The distinction directly changed the interpretation of the Candystand failure.

### Remaining failures and next actions, as measured for 1.8.0

This table records the 1.8.0 investigation and is kept as history. Several of
its rows were resolved in 1.9.0 and 1.10.0 — Galidor Quest, Courage in Creep TV,
Donkey Kong Country Barrel Maze and Air Show now pass recorded gameplay
conditions. `SHOCKWAVE-COMPATIBILITY.md` and `compatibility-results.json` hold
the current status; read this table only for the reasoning behind each repair.

| Title or group | Measured symptom and evidence | Next action | Current conclusion |
| --- | --- | --- | --- |
| Monster Bash | Former T-pose and stalled sequence; revised run records a hit and game-camera tracking | Continue longer-session and restart coverage | Opening hit verified |
| Courage in Creep TV | Missing `.symbol` fixed; later initialization leaves the VM stopped without a completed launch | Trace the later startup stop and embedded media dependencies | Limited |
| Free Running | Script reaches frame 85 after location/manager checks; `gGame` is not initialized | Recover the original launcher and its address/parameters, then retest | Limited; black frame is not proof of a renderer fault |
| American Football, Air Show | Baseline reaches black frame 85 without gameplay | Inspect each launcher and startup branch separately | Observed only; cause not fully established for these two titles |
| Candystand Mini-Golf | `entryPoint` calls `quit()` after required `sw1`/`sw2` values are absent | Recover the original launch page/settings and complete hole data | Limited; missing launch context confirmed |
| Oreo Adventure, Donkey Kong Country Barrel Maze | Baseline stops at unsupported `quit()` | Inspect their own preceding branch before choosing a runtime or package repair | Limited; exact preceding cause not yet established |
| Creepy Pong, Battle Wheels | Embedded content requests missing `didyouknow_shockwave.swf` | Recover the specific original dependency and verify its completion callback | Limited; another SWF in the folder is not automatically equivalent |
| Galidor Quest | Startup cannot find `RemoteResourceLoader` despite many external casts in the package | Trace cast selection/loading and the intended entry chain | Limited |
| On The Run 2 | A `fileName` assignment targets a cast member classified as unknown | Determine the authored member type and media dependency before implementing the property | Limited |
| LEGO Studios Backlot | Main launcher reaches a black initialization frame | Trace initialization and required assets against the original package | Limited |
| White Water Rafting, Doomsday | Previously rejected skeletons now parse; scene opening was observed | Add menu, movement, and game-state assertions | Rendering observed; gameplay not certified |

The remaining baseline observations include NiGHTS, Banjo-Kazooie Memory Game, Wario’s Whack Attack, Powerpuff Girls Pillow Fight, Scooby-Doo, Tomb Raider, Fear Effect 2, Redline Rumble 2, Turbo Racing 2, and Dinky Rinky. Opening screenshots were captured, but this investigation does not assign them a gameplay pass without an input-driven assertion.

Several of these failures can look identical to a player: a black rectangle, a preloader, or a character standing still. Their causes require different repairs. A missing file needs preservation work; a missing callback needs runtime semantics; an unknown cast type needs format and media investigation; an authored location check needs accurate launch context. A global “ignore errors” option would conceal those distinctions and make the compatibility count less useful.

### Priorities for expanding Flash support

The next Flash-specific expansion should start with a small set of independent SWF games with known entry files and expected interactions. The current Shockwave collection’s sidecars are valuable for mixed-runtime cases, but they are a poor denominator for standalone Flash compatibility. Each new SWF case should record its content hash, AVM family, launch variables, dependent URLs, and one observable gameplay action.

For AVM1, prioritize timeline/input behavior, external movie loading, sound, and storage as they occur in actual failures. For AVM2, choose cases exercising loader events, text layout, bitmap operations, and 3D APIs. These are test categories, not claims that every named API is missing. Ruffle’s detailed compatibility information and a failure’s actual stack should guide the choice of a pinned update or a narrowly scoped patch.[^10]

Mixed Director/Flash cases need a different acceptance test. The embedded SWF must load, accept the values sent by Lingo, deliver its callback, and let the Director timeline proceed. Seeing a Flash frame inside the Director stage verifies only the first part. Creepy Pong’s missing dependency illustrates why asset availability and bridge behavior must be examined together.

Host policy must also be measured independently. Ruffle documents `allowNetworking` behavior, but its current implementation does not make that setting alone a complete offline boundary. Flashback’s content policy and local routing are therefore still required. Compatibility changes should preserve local resource recovery while testing that unarchived requests do not silently gain unrestricted network access.[^11]

Remote-service restoration is a separate project when the program depends on live server behavior. Cached menus or a recovered SWF cannot recreate a game server, account backend, or score service. Flashpoint’s preservation guidance similarly distinguishes preserved client content from unavailable server dependencies.[^12] Such features should have a separate status rather than lowering confidence in a verified offline interaction or being implied by it.

### Release and evidence, as delivered for 1.8.0

The changes are delivered as Flashback 1.8.0 with the patched Director source, a reproducible compatibility patch, source manifest, and rebuild instructions. Standalone Ruffle remains at 0.6.0. The original downloaded games and test screenshots remain outside the distributable application and corresponding-source archive.

`check-shockwave-corpus.py` records the native opening interactions, including Monster Bash’s successful hit. `check-shockwave.sh` covers the four established core games and their host behavior. The final signed app also passes `shockwave-host-probe.json`, including archived `_movie.path`/`src` preservation and native pointer accuracy at three window sizes. The native gameplay set passes 13 of 15 recorded conditions, up from 12; Backlot and Creepy Pong remain limited. The runtime unit suite passes 123 tests, including the new constrained-skeleton and high-index checks. The collection’s structural evidence and title-level observations are recorded in `compatibility-results.json` and `skeleton-corpus.json`; a parser pass, an opening observation, and a gameplay pass retain distinct labels.

The highest-value follow-up is to turn the confirmed launch-context and external-resource failures into reproducible package cases, then add the smallest shared runtime fix each case demonstrates. The Monster Bash work establishes that approach: one character exposed parser, palette, event, queue, and transform defects, and the repair now has both a corpus check and a native successful-hit test.

## Sources

[^1]: Adobe Systems. *SWF File Format Specification, version 19*. 2013. “FileAttributes” and script tags. [Adobe-authored specification, Open Flash mirror](https://open-flash.github.io/mirrors/swf-spec-19.pdf).
[^2]: Ruffle project. *ActionScript Compatibility*. Accessed September 10, 2026. [Compatibility overview](https://ruffle.rs/compatibility).
[^3]: Ruffle project. *Release 0.6.0*. September 6, 2026. [Release notes](https://github.com/ruffle-rs/ruffle/releases/tag/v0.6.0).
[^4]: DirPlayer contributors. *dirplayer-rs*, pinned source revision and repository/submodule metadata. September 6, 2026 revision, inspected September 10. [Pinned source](https://github.com/igorlira/dirplayer-rs/tree/68376fbb4494a6bbad4c70081ecdcb99814a74c9).
[^5]: Flashpoint Archive. *How Flashpoint Works*. Accessed September 10, 2026. [Preservation architecture](https://flashpointarchive.org/datahub/How_Flashpoint_Works).
[^6]: ProjectorRays contributors. *ProjectorRays README*. Accessed September 10, 2026. [Project description](https://github.com/ProjectorRays/ProjectorRays/blob/master/README.md).
[^7]: Khronos Group. *WebGL 2 Specification*, version 2.0.0. Accessed September 10, 2026. Texture formats and shader facilities. [Specification](https://registry.khronos.org/webgl/specs/2.0.0/).
[^8]: Macromedia. *Director MX 2004 Scripting Reference*, second edition, September 2004. Animation events and `queue`. [Macromedia-authored reference, university mirror](https://eclass.hmu.gr/modules/document/file.php/TP194/drmx2004_scripting_ref.pdf). Binary-format findings and before/after results are original measurements of the supplied collection, documented in the accompanying evidence files.
[^9]: Macromedia. *Director MX Lingo Dictionary*. `symbol`, page 647. [Macromedia-authored manual, Manualshelf mirror](https://www.manualshelf.com/manual/macromedia/director-mx-lingo-dictionary/user-guide-english/page-647.html).
[^10]: Ruffle project. *ActionScript 3 API Compatibility*. Accessed September 10, 2026. [Detailed API status](https://ruffle.rs/compatibility/avm2).
[^11]: Ruffle project. *Using Ruffle*. Configuration documentation, accessed September 10, 2026. [Host and networking configuration](https://github.com/ruffle-rs/ruffle/wiki/Using-Ruffle).
[^12]: Flashpoint Archive. *Extended FAQ*. Accessed September 10, 2026. [Preservation limitations and server dependencies](https://flashpointarchive.org/datahub/Extended_FAQ).
