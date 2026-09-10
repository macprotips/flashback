# Flashback

**Flashback.app** is the general-purpose Mac app built in this workspace. Drop
in SWF files, runnable Java JARs, offline HTML games, experimental Shockwave movies, folders, or ZIP archives to import and play them. See [Flashback's guide](Flashback/README.md)
for usage, build instructions, compatibility, and release notes.

Flashback 1.4 adds **Add from Website** (⌘⇧O): paste a game page, find its
embedded game, recover available assets, review the results, and add it to
your offline library. No browser extension is needed. The distributable
**Flashback-Mac.zip** includes the signed app and its matching source.

Flashback 1.5 refines the welcome screen, library, website importer, player,
dialogs, and Help. See the [design review](Flashback/DESIGN-REVIEW.md).
Version 1.5.1 improves Shockwave website parameters and error handling, and
verifies that packaged player files match the tested source.

Version 1.9.0 expands the Shockwave compatibility work and verifies 20 opening gameplay cases. See the [compatibility report](Flashback/SHOCKWAVE-COMPATIBILITY.md) for exact test scopes and remaining failures.

The original standalone **TextTwist 2.app** is also kept here, with its details below.

## TextTwist 2 for Mac

Double-click **TextTwist 2.app** in this folder. You can also drag the app into
Applications; its game files and Ruffle runtime are contained inside it.
Supports Apple Silicon and Intel Macs on macOS 11 or later.

This packages the original GameHouse Flash browser edition with Ruffle 0.6.0.
It is an emulator-backed Mac application, not a source-code port or the full
Windows retail edition. The original browser edition's mode restrictions and
promotional buttons are preserved. Gameplay assets are local; no browser,
Adobe Flash installation, Windows, or online game server is required.

If Ruffle asks to access the game folder on first launch, select the bundled
`Contents/Resources/game` folder. The locally built wrapper is ad-hoc signed,
not Apple-notarized. Saves use Ruffle's normal per-user local storage.

Keyboard: type letters, press Return to submit, or use the game's on-screen
controls. Select Untimed for relaxed play or Timed for the countdown mode.

## Sources

- Game files: https://games2.gamefools.com/onlinegames/TextTwist2/
- Original publisher listing: https://www.gamehouse.com/games/texttwist-2
- Runtime: https://github.com/ruffle-rs/ruffle/releases/tag/v0.6.0
- Mac runtime archive: https://github.com/ruffle-rs/ruffle/releases/download/v0.6.0/ruffle-0.6.0-macos-universal.tar.gz

Game assets remain the property of their respective owners. This local bundle
does not grant redistribution rights. Ruffle's license is included inside the
app at `Contents/Resources/Ruffle-LICENSE.md`.

## Rebuild and verification

`python3 fetch_assets.py` downloads the publicly hosted browser assets into
`assets/`. Extract the official Ruffle Mac archive into `vendor/`, then run
`./build.sh`. This compiles a universal launcher using Apple's command-line
tools, bundles the dependencies, signs locally while preserving Ruffle's
sandbox entitlements, and runs `python3 verify.py`.

Validation performed: every active local XML asset reference exists, all
bundled files match their downloaded originals, both CPU architectures are
present, and deep code-signature verification passes. The native runtime was
launched successfully. Visual gameplay was checked with the same game assets
and Ruffle 0.6.0 web runtime: menu, Untimed game, keyboard word submission,
score increase, and Next Round availability. Native window interaction and
long-term save persistence were not independently automated.
