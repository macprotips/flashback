#!/usr/bin/env python3
"""Fail closed if the Win98 guest helper weakens shutdown confirmation."""
from pathlib import Path

source = (Path(__file__).with_name("ClassicWindowsGuest.c")).read_text(encoding="utf-8")
required = (
    "#define WM_ENDSESSION 0x0016U",
    "static LRESULT __stdcall shutdown_window_proc",
    "if (message == WM_ENDSESSION)",
    "if (w_param != 0)",
    '"shutdown", "completed"',
    "WritePrivateProfileStringA((LPCSTR)0, (LPCSTR)0, (LPCSTR)0, STATE_PATH)",
    "if (!create_shutdown_observer())",
    "WritePrivateProfileStringA(\"State\", \"shutdown\", \"requested\", STATE_PATH)",
    "if (!ExitWindowsEx(EWX_SHUTDOWN, 0))",
    "while (GetMessageA(&shutdown_message, (HWND)0, 0, 0) > 0)",
    "if (!shutdown_completed)",
)
for text in required:
    if text not in source:
        raise SystemExit("missing shutdown confirmation invariant: " + text)
requested = source.index('"shutdown", "requested"')
completed = source.index('"shutdown", "completed"')
if completed < source.index("if (message == WM_ENDSESSION)") or requested > source.index("if (!ExitWindowsEx(EWX_SHUTDOWN, 0))"):
    raise SystemExit("shutdown markers are not ordered around the real end-session path")
print("Classic Windows guest shutdown source checks passed")
