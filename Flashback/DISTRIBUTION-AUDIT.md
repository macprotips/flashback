# Flashback 1.10.0 distribution record

Prepared September 10, 2026. This supersedes the 1.3.0 audit: the source,
licensing, attribution, and icon issues identified there have been addressed
in the 1.10.0 release package. This is an engineering license inventory and
verification record, not a legal opinion or a trademark clearance.

## Changes completed

| Component | License and release treatment |
| --- | --- |
| Flashback source, documentation, and artwork | GPL-3.0-only, selected for this release. Full license and source accompany the app. SPDX identifiers identify original source. |
| App icon and brand mark | Original vector paths in `BrandArtwork.swift`, also used by the icon generator. No SF Symbol or external image is used in branding. Standard functional macOS controls still use system symbols. |
| Ruffle 0.6.0 | Original upstream binaries under MIT or Apache-2.0. Exact release source, dependency sources, upstream copyright/license inventory, and Noto font notices accompany the release. |
| DirPlayer at 68376fb | Rebuilt with the supplied Flashback compatibility patch under GPL-3.0-only. The patched source, original upstream revision, Ruffle fork, Bobba/Groove Xtra revisions, shared SDK, build scripts, and dependency source archives are supplied. |
| BellSoft Liberica 8u504+1 | Replaces Zulu with the same Java update from a vendor publishing its complete corresponding source. Both Mac architectures preserve their GPLv2/Classpath Exception, assembly exception, third-party notices, and vendor signatures. The matching complete vendor source archive accompanies the binaries. |
| Dependency notices | Original notices are preserved in the source archives and indexed in `Licenses/DEPENDENCIES.json` and `.txt`, including build dependencies present only in the source cache. |
| In-app disclosure | Flashback → Licenses and Source opens the GPL terms, no-warranty notice, component credits, and instructions for obtaining the supplied source. |
| Game files and personal data | Commercial games, imported game artwork, saves, personal covers, the separate TextTwist 2 app, and development verification screenshots are excluded from the distributable. |

Flashback retains each third party's license; choosing GPLv3 for the host does
not relicense their independent code or games. The corresponding-source route
is actual supplied source, rather than relying on a forwarded vendor source
offer. The complete release archive keeps source and binaries together.
For separately hosted downloads, follow `SOURCE.md` and keep matching source
available beside the binary without an additional charge.

## Provenance

- Independent Ruffle binary: official `ruffle-0.6.0-web-selfhosted.zip`, SHA-256
  `e8acfacc37443303872379d0e215999af846854d1dd3fa8fac0a765445b43dbf`.
- DirPlayer companion assets: official `dirplayer-polyfill-0.8.1.zip`, SHA-256
  `6f5000412c50833345a630ade25fb70359dc4e1aae66352c80de7da77542162c`.
- DirPlayer VM/polyfill source: `68376fbb4494a6bbad4c70081ecdcb99814a74c9`,
  plus `Flashback/dirplayer-compat.patch`. Toolchain and rebuild commands are
  in `SOURCE.md` and `rebuild-shockwave.sh`.
- Shipped patched `dirplayer-polyfill.js`: SHA-256
  `a2954af3a91e3838bc6ea14647a8b9ea2ff1eae55dc62770524ca2ca6b511b7e`.
- Its Ruffle fork: `79d1ca0f45d79e28c3a0658bbc6b8430d26ef308`.
- Bobba: `3022f6f924d23ac1838be7b212cf745f52448dcd`.
- Groove: `86ea920f3b4d8add58b8f3e07629699cefa1763e`.
- Liberica ARM JDK: SHA-256
  `7806c4411d27155651c422a40ab6f5f17d7a48f575cfd932391fa88adc6e37c6`.
- Liberica Intel JRE: SHA-256
  `5f0f636c81c522048de98c7b2d582776d0125f2ca4636e365c114faf5461eeab`.
- Complete Liberica source: SHA-256
  `037fe8766504a21ed4727599ca5c8af4988232082352d9c596dc2898049f2c42`.

`vendor/sources/MANIFEST.json` records the source/dependency archives and their
checksums. `JAVASCRIPT-SOURCES.json` additionally maps browser-library packages
to their original repository source. The final ZIP and source hashes are
written to `Flashback-Mac.zip.sha256` and the release's `SHA256SUMS`.

The source contains the preferred code and original build material. Unrelated
commercial game fixtures and visual reference data are omitted; source test
harnesses and build manifests remain. Upstream Xtra projects did not publish
separate Cargo lockfiles; the declared source and shared SDK are supplied.
No claim of bit-identical reproduction across compiler versions is made.

## Verification

The release build passes importer and ZIP checks and verifies both native
architectures. Liberica passes restricted Java permissions, manifest checks,
and real Wiz 3 opening gameplay, input, resize, and minimize/restore checks.
The rebuilt app passes Java import/launch/process lifecycle checks and the
library audit across five sizes, light/dark appearances, click targets, and
compact Flash/HTML/Shockwave player states. The Flash runtime files are compared against their pinned upstream assets;
Shockwave files are compared against the patched build and pinned companion assets.

Version 1.6.0 expanded the original four-game Shockwave checks with a broader
fixture corpus, including native menu clicks and gameplay conditions.
`SHOCKWAVE-COMPATIBILITY.md` records the exact scope and remaining failures.
Version 1.6.1 changes the original icon and in-app branding, and lets the UI
audit regain window focus before opening each dialog. Game runtimes and
compatibility fixes are retained.
A separate native installation check replaces a complete old app bundle and
verifies retained metadata, covers, game files, saved storage, and the quit warning. Packaging
also compares the bundled HTML players and Java policy to their source files.

The packaging check verifies source presence, checksums, preserved runtime
notices, no symbol-derived branding, and exclusion of personal data and game
fixtures. This does not assert compatibility with every game or every level.

## Delivery status and limits

The local release is Developer ID signed with hardened runtime; signing
status is checked by the packaging script. Apple notarization needs developer-account
authentication, which is not saved in the default keychain. `RELEASING.md`
gives the remaining submission/stapling commands; no public site or store
listing has been published.

The product name, distribution jurisdictions, store-specific terms, and
game-specific EULAs have not received legal clearance. No permission to
redistribute other people's games or their marketing artwork is implied.
Commercial use of GPL software is permitted subject to its terms, including
recipients' source and redistribution rights. Obtain professional advice if
you need a legal clearance for a particular commercial release or store.

Primary references: [GPLv3 distribution terms](https://www.gnu.org/licenses/gpl-3.0.html#section6),
[BellSoft's exact binary/source release](https://github.com/bell-sw/Liberica/releases/tag/8u504%2B1),
[DirPlayer's pinned license](https://github.com/igorlira/dirplayer-rs/blob/68376fbb4494a6bbad4c70081ecdcb99814a74c9/LICENSE),
[Ruffle's source and notices](https://github.com/ruffle-rs/ruffle/blob/v0.6.0/LICENSE.md),
and [Apple's SF Symbols rules](https://developer.apple.com/design/human-interface-guidelines/sf-symbols).

Version 1.6.2 adds custom game artwork using Apple ImageIO and the existing
native library. Image validation, preview sizing, persistence, default
restoration, chooser cancellation, and light/dark cards are checked. The
game runtimes and compatibility fixes are retained.

Version 1.6.3 uses original pixel-grid rewind artwork in the icon and native
branding. Custom artwork support and game runtimes are retained.

## 1.7.0 catalog

Discover adds a native Internet Archive search and download interface using system
frameworks and existing import code. No additional third-party library, Archive
game, or Archive image is bundled. The source package includes the catalog and
its authored fixture tests. Existing player runtime and license inventories apply.

Version 1.7.1 adds original pixel lettering beside the in-app rewind logo.
It is part of Flashback's GPLv3 artwork and introduces no font dependency.
