#!/usr/bin/env python3
"""Run an end-to-end native DOS smoke check against a built Flashback.app.

The fixture is authored at runtime outside the source tree. It is a tiny DOS
.COM program that writes CHECK.SAV and loops until Flashback closes the native
session. A second app launch must reuse that private game directory unchanged.
"""
import argparse
import hashlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


HERE = Path(__file__).resolve().parent


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_digest(directory: Path) -> dict[str, str]:
    return {str(path.relative_to(directory)): digest(path)
            for path in sorted(directory.rglob("*")) if path.is_file()}


def require(value: bool, message: str) -> None:
    if not value:
        raise RuntimeError(message)


def run_check(binary: Path, source: Path, output: Path) -> str:
    command = [str(binary), "--self-check", str(source), "GAME/CHECK.COM", str(output)]
    completed = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, timeout=75)
    result = output / "Result.txt"
    detail = completed.stdout + ("\n" + result.read_text(errors="replace") if result.exists() else "")
    require(completed.returncode == 0, f"native self-check exited {completed.returncode}:\n{detail[-6000:]}")
    require(result.exists() and result.read_text().startswith("PASS: native game import"),
            f"native self-check did not report its native pass condition:\n{detail[-6000:]}")
    return detail


def one_save(output: Path) -> Path:
    matches = list((output / "Library" / "Native Saves").glob("*/Files/GAME/CHECK.SAV"))
    require(len(matches) == 1, f"expected one private DOS save, found {matches}")
    return matches[0]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=HERE.parent / "Flashback.app",
                        help="built Flashback.app (default: ../Flashback.app)")
    parser.add_argument("--keep", action="store_true", help="keep the temporary fixture and results")
    options = parser.parse_args()
    binary = options.app.resolve() / "Contents/MacOS/Flashback"
    require(binary.is_file(), f"built app binary is missing: {binary}")
    dos_docs = options.app.resolve() / "Contents/Resources/DOS/DOSBox Staging.app/Contents/Resources/docs"
    require(not dos_docs.exists(), "the embedded DOSBox manual contains third-party game screenshots")
    dos_app = options.app.resolve() / "Contents/Resources/DOS/DOSBox Staging.app"
    signed = subprocess.run(["codesign", "-d", "--entitlements", "-", str(dos_app)],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    require(signed.returncode == 0 and "com.apple.security.cs.allow-jit" in signed.stdout,
            "the embedded DOSBox runtime lost its required JIT entitlement")

    root = Path(tempfile.mkdtemp(prefix="flashback-native-dos-"))
    try:
        source, output = root / "authored-dos-game", root / "results"
        source.mkdir()
        game_directory = source / "GAME"
        game_directory.mkdir()
        entry = game_directory / "CHECK.COM"
        # A real-mode DOS executable: create CHECK.SAV containing FIRST-LAUNCH
        # and then loop.  Unlike a batch file, DOSBox waits for this process;
        # the visible engine window therefore remains open for the app check.
        entry.write_bytes(bytes([
            0xB4, 0x3C, 0xBA, 0x1B, 0x01, 0xB9, 0x00, 0x00, 0xCD, 0x21,
            0x93, 0xB4, 0x40, 0xBA, 0x25, 0x01, 0xB9, 0x0E, 0x00, 0xCD,
            0x21, 0xB4, 0x3E, 0xCD, 0x21, 0xEB, 0xFE,
        ]) + b"CHECK.SAV\0FIRST-LAUNCH\r\n")
        original = tree_digest(source)

        run_check(binary, source, output)
        save = one_save(output)
        config = save.parents[2] / "dosbox.conf"
        config_text = config.read_text()
        require("window_size = 960x720" in config_text,
                "the generated DOSBox config does not set the supported window size")
        require("windowresolution" not in config_text and "\ncycles =" not in config_text,
                "the generated DOSBox config uses deprecated settings")
        first_save = digest(save)
        require(save.read_text(errors="replace").strip() == "FIRST-LAUNCH",
                "the DOS fixture did not execute and write its expected private save")
        require(tree_digest(source) == original, "import or play modified the original DOS source folder")
        preserved = save.parent / "PRESERVE.TXT"
        preserved.write_text("private game data retained across launch\n")

        run_check(binary, source, output)
        second_save = one_save(output)
        require(digest(second_save) == first_save and preserved.exists(),
                "the private DOS game directory was recreated on the repeat launch")
        require(tree_digest(source) == original, "the repeat launch modified the original DOS source folder")
        print("PASS: real DOSBox fixture executed, wrote a private save, self-check covered duplicate process/history/cleanup, and repeat launch preserved source and saves")
    finally:
        if options.keep:
            print(f"Kept native fixture and results: {root}")
        elif root is not None:
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
