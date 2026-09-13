# Flashback experimental Windows 98 test build

This is a development build for testing the opt-in Classic Windows path. It
is not a release and does not include any Windows or game media.

1. Open Flashback with Finder's Open command if macOS shows a development-signing warning.
2. Add a Windows 98 game ISO, executable, or complete game folder. Flashback
   preserves it in the library immediately, even before Windows is installed.
3. Click the Windows game entry. Drop a user-supplied Windows 98 ISO into the
   setup sheet and choose Continue Setup.
4. Complete the Windows screens, including the product key, then restart until
   the Windows desktop is stable. Close the emulator and choose Windows Desktop
   Is Ready so Flashback records the verified setup state.
5. If setup is interrupted, click the same game or another Windows game entry.
   Flashback resumes the saved private ISO and disk from the active library.

Per-game Windows installation and Play remain gated while private game-disk
checkpointing, guest shutdown evidence, display mode, sound, input, and actual
title compatibility are being qualified. Reports should include the title,
guest display mode, emulator window size, input capture state, and the setup log
from the library's `ClassicWindows` folder.
