# Flashback

A native Mac library for Flash, Java, offline HTML, and experimental Shockwave games. Drop a game in and play.

## Use it

Version 1.10.0 lets you **drag an image straight onto a game's card** to use it as that game's artwork, and fills **Discover** with 136 well-known browser games from the Flash and Shockwave era, each matched to an Internet Archive item that has a playable file. `featured-catalog.json` records how that list was assembled and what was rejected; listings are still labelled untested unless Flashback has actually checked them. It also validates a score entry before reading it as a sprite span, which stops fifteen titles from reporting a frame count in the billions and never looping; reads a movie property written with call syntax; and reads a vector's components by index. It adds native gameplay cases for Beach Soccer and American Football, and relaunches every indexed title against the shipped runtime. See [tested interactions](SHOCKWAVE-COMPATIBILITY.md) for the measured scope and remaining failures.

Version 1.9.0 repaired shared Director script dispatch, string operations, cast allocation, and embedded Flash startup. It recovers original Miniclip launchers and adds native gameplay replays for Courage, Mini Golf, Air Show, Barrel Maze, Great Firework Race, Creepy Pong, and Galidor. See [tested interactions](SHOCKWAVE-COMPATIBILITY.md) for the measured scope and remaining failures.

Version 1.7.3 added an always-on adult-content filter to **Discover**. Titles, tags, descriptions, and file names are checked before cards or artwork appear, and again when opening details or downloading. The filter relies on Archive metadata and can miss unlabelled content. **Keep Looking** continues past a fully filtered page.

Version 1.7.2 renames the library’s All Games view to **Installed Games** in the sidebar and heading.

Version 1.7.1 matches the sidebar’s Flashback name to the rewind logo with original 8-bit lettering.

Version 1.7.0 adds **Discover**, a searchable Internet Archive catalog. Browse featured games, search by title, or filter Flash and Shockwave entries. Open a card for its description, available downloads, and compatibility notes. **Download to Library** keeps its game files and artwork on this Mac; **Play** opens the downloaded game.

Archive artwork is saved as a default cover. Any custom artwork you choose stays in place.

Version 1.6.3 gives the rewind arrows an 8-bit pixel style in the icon, library, and welcome screen.

Version 1.6.2 adds custom game artwork. Right-click a game and choose **Change Artwork…** to select an image, or **Restore Default Artwork** to undo your choice. Custom artwork is copied into the library and stays in place when you play or reopen Flashback.

Open **Flashback.app** from the parent folder, or drag it into Applications.
Supports macOS 13 Ventura or later. The app includes Apple Silicon and Intel
binaries, Ruffle 0.6.0, BellSoft Liberica Java 8u504+1 for both CPUs, and a patched DirPlayer build. No browser,
Flash plug-in, separate Java installation, package manager, or account is needed.

The welcome window introduces supported games, website extraction, and your library.
It appears once and can be reopened from **Help → Welcome to Flashback**.
Only extract copyright-free games.

Version 1.5 refines every app surface with native controls, simpler typography,
quieter game cards, consistent import steps, and window-attached dialogs.
See [DESIGN-REVIEW.md](DESIGN-REVIEW.md) for the findings and verification.
**Help → Flashback Help** opens the full guide; **Flashback → About Flashback**
shows the app version and credits.

- Drop a **.swf file** anywhere in the library, or use **Add Games** / **⌘O**.
- Choose **Add from Website** / **⌘⇧O** to recover a game from a web page or direct download.
- Drop a **.jar file** to play a classic Java desktop game such as Wiz 3 or a
  Java ME/MIDP mobile game such as Bounce Tales. Desktop Java games and mobile
  games open in their own native windows and use their own game controls.
  Right-click a running game in the library to quit it. Closing Flashback also
  closes its Java games.
- Drop an **HTML/HTML5 game folder** with its `index.html` (or other start page).
  A single `.html` or `.htm` file also works for self-contained games.
- Drop a **Shockwave movie** (`.dcr`, `.dir`, or `.dxr`). Support is experimental;
  include external casts, sounds, and levels by dropping the whole folder or ZIP.
- Drop a **ZIP** directly; Flashback unpacks it and keeps the game’s assets together.
- For games with extra images, sounds, or levels, drop the **entire folder** or ZIP.
  If it contains several game files, choose the main game file when prompted.
  For an archive containing an old plug-in page, choose its SWF, JAR, or Shockwave movie.
- A single imported game starts automatically. Click its cover to play again.
- Use the heart for favorites. Right-click a game to rename it, show its files,
  or remove Flashback's copy to the Trash. Original files are never modified.
- Press **⌘F** to search the current library or Discover view. The sidebar switches between Installed Games,
  Favorites, and Recently Played.
- Flash player controls provide pause, restart, mute, and full screen. **⌘L** brings
  back the library; **⌃⌘F** toggles full screen; **⌘W** closes a window.
- HTML and Shockwave games get restart and full screen. Use the game’s own pause and sound
  controls; browsers have no universal pause button for arbitrary game logic.

Flashback stores copies in `~/Library/Application Support/Flashback/Games` and
its library in `Library.json` beside that folder. Captured game covers are in
`Covers`. Games that implement Flash local saves or HTML local storage use WebKit's persistent,
per-app website storage. Each game gets its own stable origin; importing the
same files and relative paths again preserves that identity. Flashback does not create save
states for games that never supported saving.

Java gets a persistent working copy under `Java Saves/<game-id>/Files`, with
its Java home and temporary files inside the same game-specific save folder.
This supports games that save relative to their working directory or Java home.
Removing a game keeps this save folder; reimporting identical originals uses it
again. Java games start with a placeholder cover; you can choose your own artwork. Browser-cookie saves,
Java Preferences, and games that write to hard-coded external paths are not
supported. **Wiz 3's old browser-cookie save feature does not persist progress
in its standalone JAR.**

## Compatibility

### Internet Archive catalog

Discover reads Internet Archive’s public search, metadata, file listing, and thumbnail APIs. No account or separate browser is needed. Downloads use the item’s listed files, check file sizes and available SHA-1 checksums, and retain source URLs in the existing website report. ZIPs go through the same validated extraction as local imports. A loose game includes supported companion assets from its folder and subfolders. Download limits are 512 MB per file, 500 files, and 1 GB total. Restricted items, installers, and unsupported archives explain why a download is unavailable.

Search and artwork responses have a bounded in-memory cache. Games remain playable from the library without the catalog or an Internet connection, subject to the game’s own dependencies. Compatibility is untested unless a specific downloaded file matches a recorded opening-gameplay check; those checks do not claim full-game completion. No Archive game or thumbnail is bundled with the app.

Run `SDKROOT=/path/to/MacOSX.sdk sh Flashback/check-archive.sh` from the project root for authored API/download checks. The built app also accepts `--catalog-check BASE_URL OUTPUT_DIRECTORY` to exercise the native catalog, an isolated library, and offline playback. `archive-fixture.py ADDRESS_FILE` provides the local API fixture; `https://archive.org` exercises a live Flash download.

### Import from a website

Paste the game page or a direct SWF, Shockwave movie, JAR, or ZIP address.
**Find Games** reads embeds, object parameters, Java archives, nested frames,
and external game-loader scripts. If no game appears, it also checks the
rendered page in a temporary WebKit session. **Look Deeper** runs this extra
check when a static scan has already found other results. No extension or
installed browser is needed.
It captures common Flash loader calls even when their version check refuses
to create a player, retaining computed download addresses and launch variables.
The temporary web view stays active during the bounded scan so WebKit does not
suspend delayed page scripts before they reveal the game.

Select the main game and choose **Recover Game**. Flashback
downloads available supporting assets, follows references in HTML, CSS,
JavaScript, and readable game bytecode, and checks public directory indexes
and configured asset directories for sound/level folders. It preserves original file bytes, launch parameters,
different hosts, and URL query variants. The offline player maps the original
web addresses to those library files.

Review the file count and unavailable references, edit the game name if needed,
then choose **Add to Library**.
The required game file must download and validate; failed supporting references
remain visible in the recovery report. Some are optional filenames guessed
from bytecode. **Cancel** stops scanning/downloading and removes temporary
files. The final library copy finishes atomically. Right-click an imported
game for **Website Details** or **Open Source Page**; **Save Report** exports
the source URLs, byte counts, SHA-256 hashes, and missing/skipped references.
Provenance lives in `Web Imports/<game-id>.json` alongside the library.

This recovers publicly available files. It cannot restore deleted games,
sign into websites, replace required online services, or guarantee player
compatibility. Applet-only JARs still need a standalone application entry point.
Computed or encrypted filenames, LZMA-compressed SWF references, service workers,
and assets available only after gameplay may require a complete game archive.
The rendered scan runs ordinary site scripts for up to ten seconds in a
temporary browser without the user's cookies; it suppresses dialogs and popups.

Transfers are streamed with timeouts, redirect checks, cancellation, and limits:
512 MB per file, 1 GB downloaded per import, 5,000 recovered files, up to 24 page
scans and 30 external scripts, and 32 MB of scan text. Local/private addresses
are rejected by the downloader, including DNS and redirect destinations.
Network access is used during recovery; the players remain offline.

### Players

Flash uses Ruffle; Java uses a separate Java 8 process with a restricted policy.
Java support covers **AWT/Swing desktop JARs with a `Main-Class` manifest** and
**Java ME/MIDP JARs with a `MIDlet-1` manifest**, including older applet games
that their author has packaged as applications. Applet-only HTML, raw `.class`
files, `.jnlp` launchers, JavaFX, newer Java bytecode, and games needing native
libraries are unsupported. Java ME support uses the bundled FreeJ2ME player and
is limited by the APIs it implements.
An ordinary library JAR gives a clear error instead of pretending to play.

HTML uses the Mac’s built-in WebKit and supports self-contained offline HTML,
JavaScript, Canvas, and browser-supported WebGL games. Keep all scripts, styles,
fonts, and other assets together in the folder or ZIP. Root-relative paths resolve
from the imported game folder. Pages depending on remote servers, browser
extensions, service workers, or old plug-ins are outside this support. HTML
support does not turn an applet, Shockwave, or Unity Web Player page into a
playable game. Games needing HTTP-only browser APIs may also need a different host.

Shockwave uses the bundled **DirPlayer** with Flashback's compatibility
patches. It runs inside Flashback without Wine or an installed Shockwave
plug-in. The original movie files stay unchanged; imported assets resolve from
the movie's folder. The player preserves the game's aspect ratio across
resizing and full screen.
Local folder and ZIP imports also recover settings from matching nearby HTML
launchers. Website imports retain Director plug-in parameters, including `sw1`–`sw9` and
custom language/settings values; extensionless Director ActiveX embeds are
recognized too. Equally strong matches favor the page you entered over related
game pages; a deeper scan can update an existing game’s launch settings.
Recoverable console diagnostics do not stop an otherwise
running movie. Fatal startup and Lingo errors still show a compatibility error.
Compatibility is experimental: some 2D and 3D games, Director versions, Xtras,
and browser scripting features remain unsupported. A script/runtime failure
stops playback and shows a compatibility message. Use the game’s own pause
and sound controls. Games using Director `getPref`/`setPref` store those
preferences in persistent, per-game WebKit storage; arbitrary FileIO writes
and emulator save states are not promised.

Windows `.exe` programs remain unsupported. Some Flash features are also unsupported. Games needing live websites, login services,
or remotely hosted assets may not work. All players block remote game
requests. HTML and Shockwave carry an offline Content Security Policy. Java game code can read imported assets and read/write its own save
folder; it cannot execute processes, load native libraries, or change that
policy. This uses Java's legacy SecurityManager, not an OS-level sandbox.

Imports are limited to 1 GB and 10,000 files per game. Hidden files are skipped,
and symbolic links in folders are rejected. ZIP extraction uses the bundled
Java standard library without executing archive contents. It rejects paths
outside the destination, conflicting files, damaged checksums, and oversized
archives; macOS metadata is skipped. ZIP symlink entries become inert regular
files rather than links. Temporary extraction files are removed after import
or cancellation. Games with nested assets resolve paths from
the main SWF's directory, with a fallback to the enclosing game folder for
browser archives. If files are missing, the player displays a helpful message.

No games are included in the distributable. Compatibility fixtures are kept
separately from the app’s runtime and source.

Wiz 3 files come from [Steve Eaborn's page](http://www.eaborn.com/wiz3/wiz3web.html)
and its [standalone JAR](http://www.eaborn.com/wiz3jnlp/wiz3.jar). Press **S** to
start, **←/→** to walk, **Space** to jump, **↑** to enter doors, and **P** to pause.

Wiz 3 v4 caches a startup `Graphics` object and has an empty `paint` method,
which can leave its Mac window white even while its internal game buffer is
updating. Flashback 1.1.1 repairs that display path in memory: the five screen
blits request AWT repaints, and `paint` draws the current playfield with nearest
neighbor scaling and its original aspect ratio. It applies only to the known
SHA-256 of the original Wiz 3 class. The JAR on disk and its game permissions
are preserved. `Wiz3Display.java` uses ASM already included in the pinned Java
runtime, so no extra dependency is downloaded.

## Build

The build script runs on Apple Silicon with Apple's command-line developer
tools and produces a universal Mac app. No third-party build framework is used.

```sh
./Flashback/fetch-runtime.sh  # Only needed if vendor/ruffle-web is missing
./Flashback/fetch-java.sh     # Downloads pinned Java archives; verifies SHA-256
./Flashback/fetch-shockwave.sh # Downloads pinned DirPlayer assets; verifies SHA-256
./Flashback/build.sh
```

Runtime fetchers verify official release archive SHA-256 values before
extracting them. The build runs importer checks, compiles both CPU versions
and the Java host, checks ZIP extraction, generates the icon, bundles the runtimes,
and verifies signing.
`SDKROOT` can select a particular installed Mac SDK when needed.

Flashback's original source and artwork are licensed under GPL-3.0-only.
The **Flashback-Mac.zip** release includes the app and its matching source
package. Keep both together when sharing it. **Flashback → Licenses and Source**
opens the license, author credits, and rebuild guide.

See [SOURCE.md](SOURCE.md) for corresponding-source contents and build
instructions, and [DISTRIBUTION-AUDIT.md](DISTRIBUTION-AUDIT.md) for the checked
release inventory. No commercial games or personal library data are supplied.
The source and dependency archives retain their upstream licenses.

The public release is signed with Developer ID. Apple notarization is a
separate final step and requires the distributor's developer-account
credentials; see [RELEASING.md](RELEASING.md). Ordinary `build.sh` builds keep
using an ad-hoc signature so anyone can build and run modified copies.

## Checks

Close other copies of Flashback before running GUI checks, and let the test
windows stay active. Multiple copies with the same bundle identifier can
compete for native keyboard focus. The checks use isolated game libraries.

The website checks use an authored local HTTP fixture and an isolated library:

```sh
./Flashback/check-website.sh
./Flashback/check-website.sh --ui /tmp/flashback-website-ui
```

They cover legacy embeds, parameters, script loaders, frames, compressed SWF
references, directory indexes, query variants, module imports, cross-host assets,
extensionless downloads, failures, transfer limits, cancellation, provenance,
and offline routing. The UI check renders light/dark import screens, adds and
plays a recovered HTML game, verifies its modules/data/input, checks remote
requests stay blocked, and captures a dynamic, plug-in-gated loader with its parameters.
The local-network allowance exists only in the explicit test harness.

The library layout audit runs without changing the personal library:

```sh
./Flashback.app/Contents/MacOS/Flashback --layout-check /tmp/flashback-layout-check
```

It renders the actual SwiftUI library with 24 games, wide/portrait/missing
artwork, long and multilingual names, and five widths from 800 to 1440 points.
It checks light/dark appearance, scrolling to the last row, search, favorites,
recent games, empty states, and long import status messages. Geometry assertions
check card bounds, gutters, title/button separation, and header/footer bounds.
Native mouse events verify favorite buttons, gaps, filters, and clearing search.
The audit also renders compact Flash/HTML/Shockwave player loading, error, and pause views
with long titles and verifies that status text cannot enlarge the player window.
It covers high contrast, native dialogs and cancellation, Help, About, and licenses.
It exports PNGs, frame measurements, and `Result.txt`.
Geometry probes are enabled only during this check.

Set `FLASHBACK_CAPTURE_WINDOWS=1` when running the UI checks to capture the
composited Mac windows, including native controls and title bars. This needs
screen-recording access on the test Mac. Without it the checks capture view
bitmaps, which may omit some native control layers on newer macOS releases.
`--surfaces-check` runs just the secondary windows and player states;
`--welcome-check` verifies first launch, dismissal, reopening, and navigation.

Flashback 1.2.1 fixes cover images sizing cards beyond their grid columns. Cover
art now paints inside a fixed-height overlay, and clicks stay inside each card.
Captions have a separate flexible width, with 28-point favorite controls. Player
controls also have larger click targets and consistent adaptive purple styling;
long loading messages are centered and bounded.

`Tests.swift` covers complete folder imports, duplicate detection, persistence,
renaming metadata, independence from original files, unusual names, invalid
input, path containment, symlinks, resource fallback, and damaged-index
preservation, plus mixed Flash/Java/HTML/Shockwave library metadata and Director movie headers.

`ArchiveChecks.java`, run during builds, checks ZIP assets, metadata filtering,
path traversal, file collisions, file-count and expanded-size limits, and invalid
archives. The HTML integration check creates and imports an isolated zipped game
with a nested page and runs it in the production WebKit player:

```sh
./Flashback/check-web.sh /tmp/flashback-html-check
```

It checks JavaScript modules, local fetch, CSS, keyboard input, offline requests,
restart, local storage, duplicate imports, recent history, and exports player
and library screenshots. The same HTML check also accepts the original
[Gabriele Cirulli 2048 source ZIP](https://github.com/gabrielecirulli/2048)
with `index.html` as its entry; it verifies tile rendering, real keyboard moves,
and the game’s own saved board across restart. This fixture is not bundled.

Java policy, manifest, and optional unmodified Wiz 3 gameplay checks:

```sh
./Flashback/check-java.sh
./Flashback/check-java.sh /absolute/path/to/wiz3.jar /tmp/wiz3-check
./Flashback.app/Contents/MacOS/Flashback --self-check \
  /absolute/path/to/Wiz3 wiz3.jar /tmp/flashback-java-check
```

The policy check loads its fixture as untrusted game code. It verifies file
saves and denial of external file access, network access, process execution,
native-library loading, reflection, and policy replacement. The optional game
check uses the production loader, renders the actual AWT paint path, and
captures the test game's visible client area. It checks for blank output at
startup, during play, and after resize and minimize/restore. The test window
briefly stays above other windows to keep the capture confined to the game.
Start/movement events go through its input handler. The app check verifies JAR import, native window readiness,
recent play history, duplicate-process prevention, and child-process cleanup.

The embedded player integration check uses a separate test library and exports
native view renders for inspection:

```sh
./Flashback.app/Contents/MacOS/Flashback --self-check \
  /absolute/path/to/game-folder root/game.swf /tmp/flashback-check
```

This checks actual SWF loading, dependency resolution, pause/resume, mute,
restart, local storage, the offline content policy, and recent-play history.
On macOS 14 and later, these checks also use a separate persistent WebKit data
store so test saves do not affect your games. On macOS 13 they use a temporary
in-memory test store.
Finder gestures, VoiceOver, older supported macOS versions, and Intel hardware
still need manual release testing.

## Shockwave checks

```sh
./Flashback/check-shockwave.sh /tmp/flashback-shockwave-check
```

This downloads hash-pinned, preserved games into the check output folder and
runs them through the production ZIP importer and WebKit player. The 2D fixture
is [Rapunzel’s Escape](https://themetalbox.com/index.php?page=rapunzel), using the
author’s downloadable Director source. The 3D fixture is
[LEGO Supersonic RC](https://archive.org/details/legosupersonicrcgame), with its
external GUI cast. Bundled Windows executables in an archive are never run.
The third fixture is [Merlin’s Revenge 3](https://themetalbox.com/index.php?page=downloads),
using the author's `merlin_3_open_065.zip` Director source. The check opens the
title screen, starts the game, and enters the first playable map.

Checks use real Mac mouse/keyboard events, inspect the running Director VM,
verify the audio backend (including non-silent audio buffers for Supersonic RC and Merlin 3),
test offline requests, resizing, full screen, and minimize/restore, and confirm Director preferences survive
restart. Screenshots and runtime state are exported for visual inspection.
These temporary test windows ignore unrelated live input during the check;
normal game windows accept input as usual. Tests use an isolated library and
WebKit data store.
Rapunzel also checks recovered page parameters inside the Director VM and
confirms that a recoverable console diagnostic leaves gameplay running.
Merlin 1 is only partially supported: its published embed settings fix the
`goTitle` startup failure, but its Start button has not advanced into gameplay
in this check. The identical movie without those settings must show a visible
compatibility error. These are opening-gameplay checks for the three working
fixtures, not whole-game completion claims. See [the compatibility record](SHOCKWAVE-COMPATIBILITY.md).

Flashback 1.3.0 adds experimental Shockwave import, play, covers, and recent
history. Rapunzel’s Escape reaches its first room and responds to movement;
Supersonic RC reaches its 3D driving level with controls and sound. These are
opening-gameplay checks, not a claim that every level or feature is compatible.

Merlin’s Revenge 1 is also checked as a known incompatible movie with the pinned
emulator: its `goTitle` handler currently fails. The check verifies that Flashback
shows a compatibility error instead of leaving the opening overlay indefinitely.
The downloaded games and their owners’ rights remain separate from the player.

## Runtime credits

[Ruffle](https://ruffle.rs/) is licensed under MIT or Apache 2.0. Both license
texts are bundled in `Flashback.app/Contents/Resources/Runtime`.

- [Pinned Ruffle release](https://github.com/ruffle-rs/ruffle/releases/tag/v0.6.0)
- [Ruffle compatibility](https://ruffle.rs/compatibility)
- Companion asset archive SHA-256: `e8acfacc37443303872379d0e215999af846854d1dd3fa8fac0a765445b43dbf`

[BellSoft Liberica OpenJDK](https://github.com/bell-sw/Liberica/releases/tag/8u504%2B1)
8u504+1 is bundled unmodified under GPLv2 with the Classpath Exception. Its
`LICENSE`, `ASSEMBLY_EXCEPTION`, and `THIRD_PARTY_README` accompany both runtimes
in `Contents/Resources/Java`. Its complete corresponding source accompanies the
release. Pinned binary and source archive hashes are in `fetch-java.sh`.


[DirPlayer](https://github.com/igorlira/dirplayer-rs) at revision `68376fb` is rebuilt with `dirplayer-compat.patch`
under GPLv3, with its license in `Contents/Resources/Shockwave/LICENSE_DIRPLAYER`.
Its embedded Flash bridge includes its own Ruffle fork and MIT/Apache license texts.
The release also supplies WebAssembly Xtras; it never installs native Xtras.

- [Pinned release](https://github.com/igorlira/dirplayer-rs/releases/tag/v0.8.1)
- [Exact source and build instructions](https://github.com/igorlira/dirplayer-rs/tree/68376fbb4494a6bbad4c70081ecdcb99814a74c9)
- Companion asset archive SHA-256: `6f5000412c50833345a630ade25fb70359dc4e1aae66352c80de7da77542162c`

Flashback 1.3.1 adds original branding, GPLv3 licensing for Flashback's code,
a source-inclusive release, complete component/dependency notices, and
Liberica Java 8u504+1 with matching vendor source. The Ruffle and DirPlayer
engine binaries remained the pinned upstream releases in 1.3.1. Version 1.6.0
rebuilds DirPlayer with the supplied compatibility changes; see `SOURCE.md`.

To render and verify the welcome window in light and dark appearances, including
its first-launch behavior, buttons, and Help menu entry, use an isolated check:

```sh
./Flashback.app/Contents/MacOS/Flashback --welcome-check /tmp/flashback-welcome-check
```

Flashback 1.6.0 asks before quitting while games are open. Cancel resumes a
running Flash game and preserves an already paused game. To check an update
from an older source-inclusive ZIP in an isolated profile, run:

```sh
python3 Flashback/check-installation.py OLD-RELEASE.zip Flashback.app GAME-ASSET-FOLDER /tmp/flashback-update-check
```
