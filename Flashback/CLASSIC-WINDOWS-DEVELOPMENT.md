# Classic Windows development status

This feature is experimental. Recognized Windows game media can be preserved in
the library and Library Play reopens the guided Windows setup, but verified
per-game installation and gameplay are still gated. No Windows 98 game is
currently claimed compatible. No public release is authorized.
Build the local prototype with `FLASHBACK_EXPERIMENTAL_CLASSIC_WINDOWS=1`;
ordinary builds omit its runtime and menu, and release packaging rejects it.

## Implemented

- Adding a valid ISO9660 disc, Windows PE executable, or folder containing a
  Windows executable creates a durable `WINDOWS 98` library entry. Clicking any
  such entry opens or resumes the shared one-time setup. Multiple games may be
  added before setup finishes; each remains independently selectable.
- File → Set Up Classic Windows opens the same one-time ISO drag/drop or Browse flow.
  The importer validates ISO9660 structure and WIN98/SETUP.EXE, then copies the
  disc into the active Flashback library. There is no second storage chooser.
  Imported media is not treated as an installed operating system.
- A supervised DOSBox-X setup process creates a private FAT16 disk and starts
  Windows installation. Continue Setup reopens the installation disk. Its setup
  profile keeps the pointer unlocked and uses DOSBox-X integration mode, so
  Windows' absolute desktop controls receive a complete click without changing
  capture state between button-down and button-up.
- ClassicWindows.swift separately implements disposable sessions and explicit
  confirmed-shutdown checkpoint promotion. Its future gameplay profile retains
  captured relative input (`autolock=true`, `mouse_emulation=locked`); the setup
  runner does not yet use this as a ready-to-play library lifecycle.
- The shared base-installation record is stored under the active Flashback
  library as `ClassicWindows/base-installation.json`, with explicit
  `notStarted`, `installing`, `ready`, and `repairNeeded` states. It records
  only validated relative paths to Flashback's private ISO and disk, allowing a
  guided setup sheet to resume after relaunch or library migration.
- ClassicWindowsGuest.c builds a Win98-compatible helper that starts the chosen
  executable, waits for it, writes state, and requests normal guest shutdown.
  It has been compiled and injected into the test disk, but not executed yet.
- DOSBox-X 2026.08.31 dependency fetch verifies both upstream archive hashes and
  assembles an arm64/x86_64 app with provenance and license files. No Windows
  or game media is included in the runtime or source package.
- NativeHost accepts dosbox-x. ClassicWindows.policy extends the existing native
  sandbox narrowly for SDL1 power notification initialization (IOPMrootDomain /
  RootDomainUserClient). It retains filesystem and network restrictions.

## Evidence

The user authorized the Windows ISO at
https://archive.org/details/windows-98-se-isofile for local testing. SHA1
fa040cd3f7fd472e9612b1721bc72d7b82538450 matches the archive's metadata.
The installer completed a local Windows 98 SE installation on a disposable
development disk. Product-key entry remained a user action and no product key
is stored in source, configuration, or output artifacts. An installed checkpoint
was retained outside the repository for continued qualification.

The actual packaged runtime passes ClassicWindows sandbox checks: allowed GAME
content can be copied to SAVES, an unrelated sibling secret cannot, and the
supervised graphical launch reports READY followed by clean EXIT 0. This proves
host launch, not Windows guest shutdown. Original failed graphical runs exposed
an SDL1 power-notification crash; the narrow policy addition resolves that crash.

The Hot Wheels Crash disc was mounted and its source hash stayed unchanged:
- Hot Wheels Crash test ISO SHA256:
  cc83f08d7a8e1372a92b1eb0d168df83072298f05d15fa93ac99d6d34a489de5
  Its MDF consisted entirely of 118386 Mode 1 data sectors; the local test ISO
  retained the 2048-byte payload from each sector. General MDF/MDS support is
  not implemented. This conversion does not prove protection compatibility.

Foundation, setup-import, Windows-library-import, native sandbox, and library
regression checks have passed. The first-use window compiled into the signed
development app. A live
Windows desktop test showed that the old setup profile could lock the pointer
on the initial mouse-down, leaving a Start-button click visually depressed
without completing its mouse-up action. The setup profile now deliberately
uses `autolock=false`, `usesystemcursor=true`, and
`mouse_emulation=integration` for absolute desktop controls. It retains the
documented default sensitivity and explicit OpenGL/original-window-size path.
The separate gameplay configuration remains captured-relative and is checked
as such. The DOSBox-X 2026.08.31 reference configuration has no
`raw_mouse_input` or `mouse_warp` setting in this macOS SDL1 runtime; its `dpi
aware` setting is for Windows host DPI virtualization, so it cannot repair a
macOS coordinate mapping. A temporary copy-on-write boot probe recorded the
same 640x480 to 720x540 pixel-ratio transition and Mojave graphics-context
warning as the previous report. It is configuration evidence only, not proof
of click accuracy at either window size.

ClassicWindowsChecks now proves that the source disk and ISO remain untouched,
that both session disk and CD are private copies, that only explicit checkpoint
calls promote a session, and that the generated coordinate policy is retained.
ClassicWindowsGuest reports a nonzero game exit as failure and records only a
shutdown *request* after a zero exit; `ExitWindowsEx` acceptance is explicitly
not treated as a completed guest shutdown. Ordinary builds run these focused
checks but still omit the runtime and menu; experimental builds additionally
run the packaged sandbox check.

## Remaining before one-button Windows gameplay

1. Finish the private per-game install/checkpoint lifecycle and enable its
   currently gated action after all promotion checks pass.
2. Finish Hot Wheels qualification: verify actual play, audio, mouse, keyboard, save,
   restart, disc requirements, and game-specific dependencies.
3. Verify the guest helper in Win98 and distinguish requested shutdown from
   completed shutdown. Never promote a checkpoint solely on emulator EXIT 0.
4. Wire verified per-game installation/launch state to the existing library
   entries and recovery flow.
5. Test first-use cancellation, interrupted install, continuation, input at
   normal and resized window sizes, and end-to-end repeat launches.
6. Review Intel runtime behavior, signing/notarization and source distribution.

### Bounded manual guest-input check still required

Use a disposable copy of the installed disk, never the source image. Start
Windows through the development app, wait for a stable guest desktop, then:

1. At the initial window size, click the centers of four clearly visible guest
   controls near each corner and record the intended and activated control.
2. Resize the DOSBox-X window, repeat those four clicks, and record its window
   size plus the guest video mode.
3. Confirm the setup profile remains unlocked while repeating one center click;
   save the NativeHost/session log immediately. A future gameplay profile must
   separately be tested with Control-F10 capture/release and relative input.

Pass only when each intended control activates at both sizes and the log has no
new SDL graphics/context error beyond the known Mojave warning. If any click
misses, retain the disposable disk and log; report host window size, guest mode,
backing scale, capture state, intended point, and observed target. The current
prototype has no evidence satisfying this check.

The main development task is concurrently changing Shockwave. This directory
is an isolated snapshot containing copied uncommitted base files. Never replace
the main project wholesale. Integrate only reviewed narrow diffs/new files.
