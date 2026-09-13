# Native runtime source/build provenance

ScummVM 2026.3.0 now uses a universal Director-only replacement built from
retained, checksum-pinned source. `DOS-SCUMMVM-BUILD-LOCK.json` describes the
26 selected dependency source archives and their exact baseline/overlay
recipes. `DOS-SCUMMVM-BUILD.md` contains commands and changes; detailed command,
configuration and compiler logs live under `vendor/sources/scummvm-build/`.

`DOS-SCUMMVM-PROVENANCE.json` binds the installed runtime to that source lock,
recipe hashes, build receipt and verification evidence. The runtime audit
compares each slice after removing only its code signature, allowing the same
code to be Developer ID signed later without accepting a different executable.
It also executes both slices, checks version/features and Director-only engine
listing, and rejects any non-system dynamic import or deployment target change.

The successful clean offline build discarded both dependency prefixes, disabled
vcpkg binary caching and prohibited source downloads. Every static archive was
architecture-audited before linking. Both slices run; ARM passes NativeHost's
sandbox and ScummVM's original Director 3 movie starts through the host. Intel
movie startup is verified under Rosetta outside the sandbox. Actual Intel
NativeHost qualification remains outstanding; no production sandbox permission
or fallback was added. These are compatibility limits, separate from source
closure. Every codec is compiled with pinned source, but the small startup movie
does not exercise every media format.

ScummVM's notices include GPL-3.0-or-later main code and AGPL-3.0-or-later
RetroWave, plus all selected dependency terms. Sparkle/updating and the Dock
plug-in are absent. Their old upstream artifacts are retained only as historical
reference and are not relied on for the replacement's corresponding source.

DOSBox Staging's existing complete CMake/vcpkg source closure is unchanged.
Its restricted optional Nuked-SC55 plug-in remains excluded.

## Superseded official-runtime investigation

The following dated investigation is preserved as historical evidence. Its
partial status applies to the old official DMG, not the source-built replacement.
The old binary evidence is nested under `superseded_official_runtime` in the
current JSON record.

# Native corresponding-source review — September 12, 2026

The DOSBox Staging source inventory is complete for the retained runtime.
The official ScummVM macOS runtime still has unresolved static-library source
provenance. `NATIVE-SOURCES.json` deliberately remains `partial`; do not change
that value merely because all listed archives pass their hashes.

## DOSBox Staging 0.83.0

The source release's `.github/workflows/macos.yml` builds both architectures
with CMake and the vcpkg baseline
`6283825b81bb60f952af1d0703638df1de611243`. Its
`.github/actions/setup-vcpkg/action.yml` explicitly checks out that baseline;
`vcpkg-triplets/{arm64,x64}-osx.cmake` requests static libraries.
The older Meson `subprojects/*.wrap` files are **not** the release's dependency
pins. [Pinned upstream workflow](https://github.com/dosbox-staging/dosbox-staging/blob/v0.83.0/.github/workflows/macos.yml).

The supplied archives cover Asio 1.32.0, IIR1 1.10.0, libmt32emu 2.7.3,
libpng 1.6.54, opusfile revision `9d718345ce03b2fad5d7d28e0bcd1cc69ab2b166`,
FluidSynth 2.5.2, SDL 2.32.10, SDL_image 2.8.8, SpeexDSP 1.2.1,
zlib-ng 2.3.3, libogg 1.3.6, Opus 1.5.2, GCEM 1.18.0, and zlib 1.3.1.
GoogleTest 1.17.0 is supplied for the upstream build's tests. Each new archive
was checked against the exact port's SHA-512 before recording its SHA-256.
The baseline retains all port patches and helper scripts. The main DOSBox
archive retains the SDL overlay and its macOS color-space patch, plus the
code and notices already embedded under `src/libs` and `licenses`.

The external dependency recipe `dosbox-staging-ext` at `v0.83.0-4` uses the
same baseline, its own libslirp overlay, and dynamic macOS triplets. Its
`deps-macos.txt` names exactly the five libraries retained in the runtime:
libslirp, GLib, GThread, libintl, and PCRE2. Their sources and the PCRE2 SLJIT
input are supplied. libffi 3.5.2 is also retained as a GLib build dependency;
the app does not contain a separate libffi dylib. The macOS libiconv port
uses the system implementation. [Pinned external recipe](https://github.com/dosbox-staging/dosbox-staging-ext/tree/v0.83.0-4).

To rebuild, extract the main source, external recipe, and vcpkg baseline.
Set `VCPKG_ROOT` to that baseline, retain each project's overlays, and follow
their included macOS workflows and `CMakePresets.json`. Populate vcpkg's
download cache from these retained archives, using the archive names in each
portfile when they differ from this inventory's names. Use an appropriate
Apple SDK/C++ toolchain, CMake, and vcpkg's documented bootstrap prerequisites.
The general-purpose build tools and Apple system libraries are not represented
as third-party code inside the app. Local signing keys are not required for
rebuilding or running an ad-hoc signed replacement. The final packaging
removes Nuked-SC55 exactly as described in `DOS-SCUMMVM.md`.

The bundled DOS utilities and keyboard/font resources were also checked.
`extras/dos-programs` in the main archive retains six nested upstream ZIPs:
DEBUGX 2.50 (assembly and makefile), DELTREE 1.02g (assembly), XCOPY from
DOSBox-X 2025.05.03 (C source identifying version 1.9a), keyboard layouts
(including editable `.KEY` files), and both original CPI bitmap-font packs
with documentation. `extras/dos-programs/README.md` records their source
revisions/URLs; `NATIVE-SOURCES.json` records each nested ZIP's SHA-256.
The main archive therefore supplies these sources too. The hand-drawn CPI
fonts are retained in their upstream binary resource form, as explained in
the upstream LICENSE; they are not missing generated C/C++ source.

## Sparkle 2.6.4 correction

`Sparkle-2.6.4.tar.xz` from upstream's release assets is a **binary SDK**.
It did not supply the corresponding source previously claimed by the inventory.
The source input is now `Sparkle-2.6.4-source.tar.gz`, the tag's repository
archive (Git tree `0ef1ee0220239b3776f433314515fd849025673f`). It contains
Objective-C source and the Xcode project; the tag has no Git submodules.
The fetcher checks two source-file markers as well as its SHA-256. Sparkle's
complete license, including its embedded third-party notices, is copied to
`DOS-SCUMMVM-SPARKLE-LICENSE.txt`. [Upstream source](https://github.com/sparkle-project/Sparkle/tree/2.6.4).

The old SDK was moved out of `vendor/sources/native` into local investigation
scratch storage so it is no longer presented or packaged as source. The
bundled ScummVM framework itself is unchanged.

## Verified ScummVM release identity

The bundled executable is the official `scummvm-2026.3.0-macosx.dmg` payload:
the DMG hash is
`d483f41a67d389a3bf50832b9a1a054fbeded56fc148216e4f84a06d330d2172` and
the universal executable hash is
`a8b56a5fd4fe1b1bf747581cafdfd9a491c4e2f2cef069007b29630e84120f3a`.
Its signed upstream release is Git tag `v2026.3.0`, resolving to
`fed42f2068dcafc6aafa1c28c77e4c88def74b66`; the release was published on
2026-06-20. The matching vendor source archive is retained as
`vendor/sources/scummvm-2026.3.0.tar.xz` and its SHA-256 is
`b863a81e1598df8bc4aa0c33e3d9b1c8bbede1879d94d91568a4f200057677e7`.
[Official release record](https://github.com/scummvm/scummvm/releases/tag/v2026.3.0).

The Intel slice has SHA-256
`f8c1619bc79b49d0c16dd41b708372b0dbdfede1db069e720c2b0eeea93e0b4d`, UUID
`F8BBA369-8D4D-320A-9C94-B8EAAA7D2B10`, deployment target 10.13, SDK 10.14,
and embeds `Apple Clang 11.0.0` and build time `Jun 20 2026 19:19:20`. The
Apple Silicon slice has SHA-256
`593632b8080397ec302cccac37ad2244c1b439239acb1a55575fde5fc19510be`, UUID
`59446182-2466-3D7F-BD01-349AFED8620B`, deployment target 11.0, SDK 26.2,
and embeds `Apple Clang 17.0.0` and build time `Jun 20 2026 20:51:06`.
Both report ScummVM 2026.3.0 and SDL 2.30.9. Intel reports MikMod, while Apple
Silicon reports OpenMPT. `fetch-native-sources.py --audit-scummvm-runtime`
checks all of these identity values from the bundled executable.

The exact release source's `ports.mk` defines the `scummvm-static` link target;
its conditional entries account for SDL2/SDL2_net, FreeType/bzip2, FriBidi,
Vorbis/Ogg, FLAC, FluidSynth/GLib/libintl, MAD, PNG, GIF, Theora, FAAD, the
architecture-specific MikMod or OpenMPT/mpg123 choice, MPEG2, A/52, VPX, JPEG,
zlib, RetroWave, Sonivox, and Sparkle. The feature lines choose those branches.
This identifies the static-link *topology*, but it does not pin every selected
archive or transitive source revision.

## Blocker: SCUMMVM-MACOS-STATIC-SOURCES

The retained ScummVM main source archive is complete, but it does not contain
the external static libraries built into the official macOS executable.
`DOS-SCUMMVM-PROVENANCE.json` records per-architecture binary evidence,
the executable hash, `otool -L` output, and version metadata from the official
ARM library development ZIP. These are evidence, not corresponding source.

For example, the executable embeds FLAC 1.3.2 on Intel and 1.3.3 on ARM,
Vorbis 1.3.7, libpng 1.6.37, and FriBiDi 1.0.10. Intel includes paths under
`/Users/criezy/Dev/scummvm-releases/libs-src/fluidsynth-2.1.4` and
`RetroWave-0.1.0`. ARM includes OpenMPT 0.7.12. Running `--version` reports
SDL 2.30.9. It reports MikMod on Intel and OpenMPT on ARM. That difference
means a single guessed list of modern library releases cannot establish
matching source for both slices.

The official ARM development ZIP contains installed libraries and headers,
including GLib 2.46.2, FluidSynth 2.1.4, libffi 3.4.2, SDL_net 2.0.1,
MPEG2 0.5.1, Sonivox 3.6.14.0 and other inputs listed in the evidence JSON.
It supplies a relocation script, not the exact build recipes, source archive
checksums, patches, or configure arguments that produced the shipped slices.
Some entries may be unused; installed headers alone cannot prove linkage.
The remaining inventory must account for the actual linked codecs, font and
bidirectional-text libraries, MIDI backends and their transitive dependencies,
including components without reliably identifiable version strings.
[Official development archives](https://downloads.scummvm.org/frs/build/).

The official macOS build guide at revision 43015 documents package-manager
builds, these development ZIPs, and generic manual configure commands. It does
not pin the official release's complete source inputs or local patches.
The main source's GitHub CI uses a different Xcode dependency-package workflow.
The separate `dockerized-bb` repository is also not evidence for this official
DMG: for example, its inspected revision uses FluidSynth 2.5.7 and macOS 14
ARM deployment, unlike the observed binary. [Build guide](https://wiki.scummvm.org/index.php?title=Compiling_ScummVM/macOS&oldid=43015),
[inspected cross-build recipe](https://github.com/scummvm/dockerized-bb/blob/4a9a449cadf50cd4662f760b3b0f486561616f61/toolchains/common/packages/fluidsynth/build.sh).

The smallest resolution preserving the existing official runtime is to obtain
its maintainer's exact Intel and ARM library source snapshots, local patches,
and build/configure recipes, then archive them with checksums and map the
linked components to each slice. No upstream contact has been sent.

An independent resolution is to build a replacement universal ScummVM from
the supplied 2026.3.0 main source and a fully pinned dependency closure in an
isolated prefix. That requires supplying every source and patch, explicitly
controlling all optional features instead of detecting Homebrew libraries,
recording the compiler/SDK and per-architecture configure commands, checking
`otool -L` for unintended paths, retaining all license notices, and verifying
Director detection and representative codec/text/MIDI playback under NativeHost.
A minimal SDL-only Director build would disable optional playback features;
it is not an established equivalent replacement. No replacement build or
runtime change is claimed by this review.

## Verification

Run `python3 Flashback/fetch-native-sources.py` to fetch missing pinned inputs,
or add `--verify-only` to forbid downloads. Both check SHA-256 and, where
recorded, the upstream recipe SHA-512. `--verify-only --require-complete`
intentionally exits nonzero until the ScummVM blocker is resolved. The
existing release-packaging coverage gate must stay in place.

## Replacement-build feasibility follow-up

[`DOS-SCUMMVM-BUILD.md`](DOS-SCUMMVM-BUILD.md) records the successful local
arm64/x86_64 compiler and Rosetta probes, the exact engine-selection flags,
and source-level examples showing why SDL-only is not an equivalent runtime.
It specifies the next dependency-lock step and the validation required before
replacing the official app. No replacement was built; source coverage remains
partial and the existing binary identity evidence remains authoritative.
