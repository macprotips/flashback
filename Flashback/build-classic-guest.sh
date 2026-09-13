#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Build the 32-bit Windows 98 guest launcher without a C runtime.
#
# Prerequisite: an official LLVM-mingw macOS universal release unpacked outside
# the internal disk, for example on the external volume.  Set LLVM_MINGW to
# that release directory (the directory containing bin/).  Releases are at:
# https://github.com/mstorsjo/llvm-mingw/releases
#
# This script performs no download: the guest build must remain offline.
set -eu
cd "$(dirname "$0")/.."

if [ -z "${LLVM_MINGW:-}" ]; then
    printf '%s\n' 'Set LLVM_MINGW to an unpacked official LLVM-mingw macOS universal release.' >&2
    exit 2
fi
compiler="$LLVM_MINGW/bin/i686-w64-mingw32-clang"
reader="$LLVM_MINGW/bin/llvm-readobj"
if [ ! -x "$compiler" ] || [ ! -x "$reader" ]; then
    printf '%s\n' "LLVM_MINGW must contain bin/i686-w64-mingw32-clang and bin/llvm-readobj." >&2
    exit 2
fi

output="work/ClassicWindowsGuest.exe"
mkdir -p work
"$compiler" -m32 -Os -ffreestanding -fno-builtin -fno-stack-protector -fno-ident -nostdlib \
    -Wl,--subsystem,windows:4.0,--entry,WinMainCRTStartup,--no-insert-timestamp,--disable-dynamicbase,--disable-nxcompat \
    -o "$output" Flashback/ClassicWindowsGuest.c -lkernel32 -luser32

audit="work/ClassicWindowsGuest.readobj.txt"
"$reader" --file-headers --coff-imports "$output" > "$audit"
grep -qi 'Machine: IMAGE_FILE_MACHINE_I386' "$audit"
grep -qi 'MajorSubsystemVersion: 4' "$audit"
grep -qi 'MinorSubsystemVersion: 0' "$audit"
grep -qi 'KERNEL32.dll' "$audit"
grep -qi 'USER32.dll' "$audit"
test "$(grep -c '^Import {' "$audit")" -eq 2
for symbol in CloseHandle CreateProcessA ExitProcess GetExitCodeProcess GetLastError GetPrivateProfileStringA WaitForSingleObject WritePrivateProfileStringA ExitWindowsEx MessageBoxA GetModuleHandleA RegisterClassA CreateWindowExA DefWindowProcA GetMessageA TranslateMessage DispatchMessageA PostQuitMessage; do
    grep -q "Symbol: $symbol (0)" "$audit"
done
if grep -Eqi 'MSVCRT|UCRT|VCRUNTIME|API-MS-WIN' "$audit"; then
    printf '%s\n' 'Unexpected runtime import in guest executable.' >&2
    exit 1
fi
printf '%s\n' "Built $output"
printf '%s\n' "Audit $audit"
