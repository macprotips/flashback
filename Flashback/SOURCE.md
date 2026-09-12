# Flashback 1.10.0 — source and redistribution

Copyright © 2026 Flashback contributors. Flashback's original source,
documentation, and artwork are licensed under **GPL-3.0-only**; see `LICENSE`.
This choice does not relicense third-party components or imported games.
The source is supplied without warranty under the license's terms.

The release ZIP includes the application and `Flashback-Source-1.10.0.tar.gz`.
Keep them together when redistributing this release. If hosting separate
downloads, offer the matching source from the same download location with
equivalent access and no additional charge. Do not replace source with a
link to an upstream homepage. No source-request fee or written offer is needed
for this supplied-source distribution arrangement.

## Contents

- `Flashback/`: all original native and Java host source, HTML player adapters,
  original vector artwork, scripts, tests, license texts, and this guide.
- `vendor/sources/dirplayer/`: DirPlayer at
  `68376fbb4494a6bbad4c70081ecdcb99814a74c9`, with the supplied
  `Flashback/dirplayer-compat.patch` already applied. Run
  `python3 Flashback/check-dirplayer-patch.py` to confirm that applying that
  patch to the pinned upstream archive reproduces this tree exactly; it reports
  any file it does not.
- `vendor/sources/dirplayer-ruffle/`: its Ruffle submodule at
  `79d1ca0f45d79e28c3a0658bbc6b8430d26ef308`.
- `vendor/sources/bobba-xtra/`: Bobba at
  `3022f6f924d23ac1838be7b212cf745f52448dcd`.
- `vendor/sources/groove-xtra/`: Groove at
  `86ea920f3b4d8add58b8f3e07629699cefa1763e`.
- `vendor/sources/ruffle/`: the independent Ruffle 0.6.0 Flash player source.
- `vendor/sources/dependencies/`: Cargo crate source archives, exact Git
  dependency source archives, and npm package archives from the supplied
  lockfiles, with SHA-256 and registry integrity in `MANIFEST.json`.
- `vendor/java/liberica/bellsoft-jdk8u504+1-src.tar.gz`: BellSoft's complete
  corresponding Java source for the supplied 8u504+1 binaries, including
  HotSpot, native libraries, build scripts, and notices. This is the vendor's
  source release, not the Java-class-only `src.zip` from a JDK.
- `vendor/sources/freej2me/`: the pinned FreeJ2ME MIDP/CLDC player source and
  its ObjectWeb ASM notices. `Flashback/freej2me-compat.patch` supplies the
  Flashback title and readiness signal used by the native launcher.

DirPlayer includes Flashback compatibility changes; the other engine sources
are unchanged. Unrelated game binaries,
visual regression fixtures, and reference screenshots are omitted; test
harness source and build files remain. See `fetch-sources.py` for the explicit
filter. The omitted DirPlayer reference-screenshot submodule is test data and
is not needed to build the player. No external game fixture is part of this
release. The Java source archive is supplied as BellSoft published it.

## Build Flashback

On an Apple Silicon Mac with Apple's command-line developer tools installed:

```sh
./Flashback/fetch-runtime.sh
./Flashback/fetch-java.sh
python3 Flashback/fetch-sources.py
./Flashback/fetch-shockwave.sh
./Flashback/build.sh
```

The Shockwave step requires the Rust/Node tools listed below. These scripts
fetch checksum-pinned companion binaries, rebuild the patched Director player,
compile both Mac CPU
architectures and the Java host, run importer/archive checks, generate the
original icon, bundle notices, and apply a local ad-hoc signature.
Set `SDKROOT` to an installed compatible Mac SDK if required. The development
build used the macOS 26.5 command-line SDK, targeting macOS 13 and later.
No secret, account, activation key, or signing key is required to build,
install, modify, or run a local build. Apple Developer ID signing and
notarization, when used for public delivery, are separate distribution steps.

## Rebuild the engines

The supplied source includes each upstream project's build scripts,
lockfiles, `CONTRIBUTING.md`/README where present, and release workflows.
The Flash and Java hosts use upstream release artifacts; rebuilding an engine does
not promise a byte-identical result across compiler versions and platforms.

For the shipped Director polyfill, the build used Rust 1.98.1 with the
`wasm32-unknown-unknown` target, Node.js 24.21.0, npm, wasm-pack 0.15.0,
and wasm-bindgen 0.2.108. From the project root:

```sh
./Flashback/rebuild-shockwave.sh
./Flashback/build.sh
```

`rebuild-shockwave.sh` copies the supplied patched source to a temporary build
directory, uses `npm ci --ignore-scripts`, builds the VM with
`wasm-pack build --target web --release --no-opt`, and runs the Vite polyfill
build. It replaces only `dirplayer-polyfill.js`. The pinned 0.8.1 archive
supplies companion Ruffle/Xtra assets whose source revisions and lockfiles
are unchanged. `fetch-shockwave.sh` obtains those assets before rebuilding.
`fetch-sources.py` applies the local patch after extracting pristine upstream
source and records the resulting file hashes in `SOURCE-TREE.json`.

To rebuild the companion assets too, arrange the supplied `dirplayer-ruffle`,
`bobba-xtra`, and `groove-xtra` trees as the submodules under `dirplayer/`, then
follow its included `.github/workflows/build.yml` and `npm run build-all`.
Upstream Bobba/Groove did not commit separate lockfiles; their declared source,
shared SDK, and dependency source archives accompany the release.

For independent Ruffle, follow the supplied `ruffle/CONTRIBUTING.md` and
`ruffle/web/README.md`: with its Rust/WebAssembly and Node prerequisites,
run `npm ci` then `npm run build` in `ruffle/web`. The self-hosted output is
under `web/packages/selfhosted/dist/`; copy the JavaScript/WebAssembly files
into `vendor/ruffle-web/` and retain its MIT/Apache license files.

Dependency archives are supplied to preserve source availability. Standard
Cargo/npm commands can obtain the same pinned packages from their registries;
for a registry-independent rebuild, unpack/seed the supplied archives using
the corresponding package manager's local cache or vendoring facilities.
The `MANIFEST.json` records each archive, original URL, version/revision, and
checksum. Git source snapshots can be used as local Cargo patches.
`JAVASCRIPT-SOURCES.json` also maps the browser libraries to their original
JavaScript/TypeScript repository snapshots in `dependencies/js-repositories/`,
including exact public release commits where npm omitted publishing metadata.

For Java, extract `bellsoft-jdk8u504+1-src.tar.gz` and follow
`jdk-8u504/doc/building.md` and the `common/autoconf/` configuration scripts.
Use the matching Mac architecture, a supported C/C++/Xcode toolchain, and a
Java 7/8 boot JDK. The vendor sources include the macOS AArch64 port. After
configuration, `make images` builds the JDK/JRE images. Preserve the license,
assembly exception, third-party readme, and version metadata when replacing
either bundled runtime. The host's Java 8 API/ASM dependencies must remain
available; run `check-java.sh` and the app's Java checks after replacement.

The native Java host classifies a JAR from its manifest. Desktop applications
use `JavaRunner`; MIDP/CLDC archives with `MIDlet-1` use the bundled FreeJ2ME
AWT player. `build.sh` compiles FreeJ2ME from `vendor/sources/freej2me/` and
packages its resources into `Flashback.app/Contents/Resources/J2ME/freej2me.jar`.
Run `check-java.sh` to verify both manifest paths.

## Attribution and changes

`Licenses.html` is available through Flashback → Licenses and Source.
`Licenses/` retains component copyright and license texts and dependency
notices. See `fetch-java.sh`, `fetch-runtime.sh`, `fetch-shockwave.sh`, and
`vendor/sources/MANIFEST.json` for source-to-binary provenance.

Flashback 1.3.1 replaces symbol-derived branding with the original ribbon
artwork, selects GPLv3 for its own code, adds source and notices to the release,
and replaces Zulu 8u504 with BellSoft Liberica 8u504+1 so the exact vendor
source can accompany both Java runtimes. The player engine binaries are
unchanged. Native integration and the narrowly scoped in-memory Wiz 3 display
adapter are original Flashback code; no game JAR or modified game is supplied.

Flashback 1.4.0 added the native website scanner, streamed asset recovery, offline URL routing, recovery reports, and their authored checks. These use Apple platform frameworks and the existing bundled players; no additional third-party runtime or game content is included.

Flashback 1.4.1 added a native first-launch welcome window with game formats, website recovery, a copyright-free extraction reminder, and library features. It uses the existing Apple frameworks and original branding.

Flashback 1.5.0 refines the native interface, onboarding, website importer, player controls, help, and About panel. No additional third-party code or game content is included.
Its rendered website scan also keeps the temporary WebKit view active for the existing bounded scan, preventing suspension before delayed loaders run.

Flashback 1.5.1 preserves recovered Shockwave embed parameters, recognizes extensionless Director ActiveX embeds, and keeps recoverable runtime diagnostics from stopping playback. Release verification also checks that the bundled HTML players and Java policy match their source files. DirPlayer and its corresponding upstream source remain unchanged.
The website collector also ranks a page’s own game ahead of equally strong related-page matches, including after redirects, and retains parameters learned by a later rendered scan.

Flashback 1.6.0 updates DirPlayer to the pinned September 6 source revision and
adds the supplied compatibility patch for rollover routing, pointer scaling,
idle scheduling, and Director host/window properties. Local folder/ZIP imports
recover inert launch parameters from matching nearby HTML pages and handle
macOS temporary-directory aliases during contained-path validation. The native
app also confirms quitting with open games and includes a whole-bundle update
check for saved library metadata, files, and player storage. See
`SHOCKWAVE-COMPATIBILITY.md` for verified gameplay and remaining limitations.

Flashback 1.6.1 replaces the cube-like ribbon with original rounded rewind
arrows and a warm orange app icon. The library and welcome screen use the
same mark. The UI audit also restores window focus before opening its
dialogs. The game runtimes and compatibility behavior are unchanged.

Flashback 1.6.2 adds per-game custom artwork, an image chooser, and default
restoration. Apple ImageIO creates bounded, orientation-correct PNG previews.
Custom artwork is stored separately from automatic covers, preserving both
the original artwork and the user’s choice. The checks cover persistence,
invalid images, resizing, native chooser cancellation, and library rendering.
No additional third-party code or game content is included.

Flashback 1.6.3 redraws the original rewind arrows on a pixel grid for an
8-bit appearance in the app icon, library, and welcome screen. No additional
assets, third-party code, or gameplay changes are included.

## Internet Archive catalog (1.7.0)

The native Discover view uses Internet Archive's public search, metadata, and
thumbnail endpoints. `Archive.swift` implements bounded requests, file selection,
checksum checks, companion recovery, and provenance. `ArchiveView.swift` provides
search, details, cancellation, and library import using the existing game storage.
`ArchiveChecks.swift`, `ArchiveUICheck.swift`, and `archive-fixture.py` cover the
service and native UI. This adds no runtime dependency. Archive games and images
are fetched only on request and are not included in the app or source release.

Flashback 1.7.1 adds original 5×7 pixel lettering for the sidebar brand name.
The fixed wordmark is drawn by `BrandArtwork.swift`, follows light/dark appearance,
and retains the accessible name “Flashback”. No font files or dependencies are added.
