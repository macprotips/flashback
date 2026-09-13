# ScummVM retained-source build — September 12, 2026

The replacement is ScummVM 2026.3.0 with only the Director engine, built for
arm64 and x86_64 from the official release source and 26 locked dependency
source archives. `DOS-SCUMMVM-BUILD-LOCK.json` pins every selected dependency's
version, URL, SHA-256, upstream SHA-512 and recipe. The retained vcpkg baseline
contains unmodified port recipes and patches; `Flashback/scummvm-build/` contains
all local overlays, toolchain files, compatibility patches and configure flags.

This supplies the source/build closure for the replacement. It does not resolve
the source provenance of the superseded official DMG. Exact code identities,
recipe hashes and successful validation evidence are in
`DOS-SCUMMVM-PROVENANCE.json`; source-accessible detailed records are under
`vendor/sources/scummvm-build/`. No bit-identical result across different SDKs,
compiler versions, paths or signatures is claimed.

## Rebuild

Prerequisites are full Xcode, Python 3, pkg-config/pkgconf, Autoconf, Automake,
GNU libtool (`glibtool`/`glibtoolize`) and NASM. The successful build used Xcode
27.0 (27A5194q), Apple clang 21.0.0, macOS SDK 27.0, Python 3.14.2,
Autoconf 2.73, Automake 1.18.1, libtool 2.6.2 and NASM 3.02. The build record
pins the actual general-purpose tool versions and executable hashes, separately
from linked inputs. vcpkg's baseline pins its downloaded CMake, Ninja and Meson
tools and its bootstrap executable. Apple frameworks, libSystem, libc++, libcurl
and libiconv are operating-system inputs; their SDK/compiler versions are
recorded. No Homebrew runtime libraries are linked.

From the repository root, use an external scratch directory. The measured
working set was approximately 3.1 GiB; reserve at least 8 GiB for extraction,
temporary copies and a retained previous runtime.

```sh
export DEVELOPER_DIR='/Volumes/Mac mini Hub/Xcode-beta.app/Contents/Developer'
python3 Flashback/build-scummvm.py \
  --work-dir '/Volumes/Mac mini Hub/Flashback-scummvm-build'
# After initial source and general-purpose tool downloads, rebuild everything:
python3 Flashback/build-scummvm.py \
  --work-dir '/Volumes/Mac mini Hub/Flashback-scummvm-build' \
  --offline --clean --install
python3 Flashback/record-scummvm-build.py
python3 Flashback/fetch-native-sources.py --verify-only --require-complete \
  --audit-scummvm-runtime --scummvm-app vendor/scummvm/ScummVM.app
```

`record-scummvm-build.py` verifies the completed clean/offline build logs,
source/recipe hashes, dependency archive identities and host integration before
recording the accepted code and complete coverage. It also retains each
dependency's underlying configuration/build logs and SPDX source mapping.

`--offline --clean` discards both dependency prefixes and rebuilds them with
binary caches disabled and network source downloads prohibited. An already
bootstrapped, baseline-pinned vcpkg/general-purpose tool cache is required for
this offline command. `--install` first runs the pinned Director fixture and
NativeHost checks; it preserves an existing runtime in the external scratch
`previous-vendor-scummvm` directory and refuses to overwrite that backup.
`fetch-scummvm.sh` verifies the existing source-built runtime or invokes this
recipe using `SCUMMVM_BUILD_DIR`/explicit build arguments. It never downloads the
unresolved official DMG as a fallback.

The stable `work/scummvm-source-build` symlink prevents old configure/make scripts
from splitting external-volume paths containing spaces. Each architecture has
an isolated installation and pkg-config prefix. The toolchain explicitly sets
both CMake architecture and compiler target flags. Every one of the 39 static
archives in each prefix must pass `lipo -archs` before ScummVM links. All selected
non-system linker libraries are named by absolute static archive path. Both
main executables must report macOS minimum 11.0, only system dynamic imports,
the required version/features, and exactly one engine (`director`).

## Playback features and local changes

The feature gate retains JPEG/MJPEG, AAC, MP3, MPEG2, A/52, Vorbis, FLAC,
Theora, VPX, PNG/GIF, FreeType/FriBidi, TiMidity, FluidSynth, Sonivox/EAS,
RetroWave, MIDI/shared codecs, OpenGL/TinyGL, TTS and the upstream networking
features. ARM retains OpenMPT; Intel retains MikMod, matching the official
per-architecture selection. `Native.policy` continues to deny networking.
The Director component declaration is expanded so upstream's unused-component
pruning does not discard these shared codec/MIDI paths. A small configure fix
makes explicit `--enable-sdlnet` run the same check as autodetection.

Sparkle auto-updating and the Dock tile plug-in are disabled for this privately
supervised runtime. They do not decode game media; the replacement includes no
Sparkle framework or updater. No unsupported Director version is made supported
by these build changes, and Flashback still requires engine detection before
normal game launch.

The macOS libmpeg2/liba52 overlays compile their complete portable decoder
implementations using small CMake recipes. libmikmod uses upstream CMake with
its static library, thread and high-quality mixer options. The libvpx overlay
retains baseline patches, splits configure options correctly, respects SDKROOT
and fixes recursive make path handling. It retains decoder and architecture
optimizations. All changes are source-visible; no binary SDK is a source input.

RetroWave's pinned revision carries AGPL-3.0-or-later. Its license accompanies
the separate runtime, along with ScummVM's GPL-3.0-or-later and all selected
component notices. The host and individual dependencies retain their own terms.

## Validation scope

`check-scummvm-build.py` fetches only three hash-pinned files from ScummVM's
`director-tests` commit `8fda334bba3610504c5c35467be58acb335eb057`: the original
2.5 KiB `D3-Events-NonShared` movie, its directory README and upstream GPL license.
It retains those inputs and evidence in the source package, never in the app.
Detection uses upstream's documented developer `start_movie` configuration for
a standalone movie: Finder type VWMD detects version 300; the loaded movie is
version 310. The checks require score loading and actual `startMovie` Lingo
execution. This tests engine startup and text/score execution, not every codec
or every commercial game.

On Apple Silicon, the ARM slice passes detection/playback through the unchanged
NativeHost sandbox, real-window READY and stdin-EOF shutdown. The Intel slice
executes and plays this movie through Rosetta outside the sandbox. The existing
policy blocks Rosetta's runtime loading when translating a sandboxed Intel
child; it was not widened. NativeHost integration of the Intel slice must still
be qualified on an actual Intel Mac. Flashback's normal ARM launch remains
sandboxed and never falls back to an unsandboxed player.

`check-native-sandbox.py --scummvm-app <candidate> --windows` passes external
file/symlink, network, process, executable mapping, quarantine and lifecycle
denials, both native runtime version checks, non-game Director rejection, and
real DOSBox/ScummVM window readiness and shutdown on this ARM Mac.
