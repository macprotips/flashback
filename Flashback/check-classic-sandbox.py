#!/usr/bin/env python3
"""Exercise the packaged Classic Windows seatbelt with real DOSBox-X I/O.

Run from the repository root:
    python3 Flashback/check-classic-sandbox.py

The harness creates a temporary tree beneath ``work/``.  DOSBox-X is launched
only through the packaged NativeHost and ClassicWindows.policy.  It must copy
an allowed GAME file to SAVES, while a sibling secret directory must remain
unreadable and uncopied.  A second, graphical launch proves that the host
reports a real window READY event before its bounded DOSBox-X exit.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "work/development-build/Flashback Classic Windows.app"
HOST = APP / "Contents/MacOS/NativeHost"
RUNTIME = APP / "Contents/Resources/ClassicWindows/dosbox-x.app"
ENGINE = RUNTIME / "Contents/MacOS/dosbox-x"
POLICY = APP / "Contents/Resources/ClassicWindows.policy"


class CheckFailure(RuntimeError):
    pass


def host_command(game: Path, saves: Path, *engine_args: str) -> list[str]:
    return [str(HOST), "--profile", str(POLICY), "--runtime", str(RUNTIME),
            "--executable", str(ENGINE), "--game", str(game), "--saves", str(saves),
            "--", *engine_args]


def run_logged(label: str, command: list[str], log: Path, timeout: float) -> str:
    """Keep the supervisor stdin pipe open until it has reaped DOSBox-X."""
    with log.open("wb") as output:
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=output,
                                   stderr=subprocess.STDOUT, cwd=ROOT)
        try:
            status = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            raise CheckFailure(f"{label} exceeded {timeout:g} seconds; see {log}")
        finally:
            # Closing stdin earlier asks NativeHost to kill the child.  It is
            # therefore closed only after the child has exited or been reaped.
            if process.stdin is not None:
                process.stdin.close()
    text = log.read_text(encoding="utf-8", errors="replace")
    if status != 0 or "EXIT\t0" not in text:
        raise CheckFailure(f"{label} did not exit cleanly (status {status}); see {log}\n{text[-3000:]}")
    return text


def require_packaged_files() -> None:
    missing = [str(path) for path in (HOST, RUNTIME, ENGINE, POLICY) if not path.exists()]
    if missing:
        raise CheckFailure("missing packaged test inputs: " + ", ".join(missing))


def run_check(keep: bool) -> None:
    require_packaged_files()
    work = ROOT / "work"
    scratch = Path(tempfile.mkdtemp(prefix="classic-sandbox-", dir=work))
    game = scratch / "game"
    saves = scratch / "saves"
    forbidden = scratch / "forbidden-sibling"
    game.mkdir(); saves.mkdir(); forbidden.mkdir()
    allowed = "allowed game payload\n"
    secret = "sibling secret must stay private\n"
    (game / "allowed.txt").write_text(allowed, encoding="utf-8")
    (forbidden / "secret.txt").write_text(secret, encoding="utf-8")
    silent_log = scratch / "silent.log"
    graphical_log = scratch / "graphical.log"
    try:
        # -silent runs the AUTOEXEC section. Mounting E is intentional:
        # DOSBox-X has a host-path reference to the forbidden sibling, but the
        # sandbox may not read it or write its data.
        config = saves / "sandbox.conf"
        config.write_text(
            "[autoexec]\n"
            f'mount c "{game}"\n'
            f'mount d "{saves}"\n'
            f'mount e "{forbidden}"\n'
            "copy c:\\allowed.txt d:\\ok.txt\n"
            "copy e:\\secret.txt d:\\no.txt\n"
            "exit\n",
            encoding="utf-8",
        )
        silent = host_command(
            game, saves, "-conf", str(config), "-silent",
        )
        silent_text = run_logged("silent filesystem probe", silent, silent_log, timeout=20)
        copied = saves / "ok.txt"
        stolen = saves / "no.txt"
        if not copied.is_file() or copied.read_text(encoding="utf-8") != allowed:
            raise CheckFailure(f"allowed GAME file was not copied byte-for-byte; see {silent_log}")
        if stolen.exists():
            raise CheckFailure(f"forbidden sibling secret was copied despite the sandbox; see {silent_log}")
        if (forbidden / "secret.txt").read_text(encoding="utf-8") != secret:
            raise CheckFailure(f"forbidden source changed; see {silent_log}")

        graphical = host_command(game, saves, "-defaultconf", "-defaultmapper",
                                 "-nopromptfolder", "-time-limit", "5")
        graphical_text = run_logged("graphical readiness probe", graphical, graphical_log, timeout=15)
        if "READY\t" not in graphical_text:
            raise CheckFailure(f"graphical launch exited without a window READY event; see {graphical_log}")
        print("Classic Windows sandbox check passed")
        print("  allowed GAME file copied to SAVES; sibling secret was not copied")
        print("  graphical launch reported READY and EXIT 0")
        if keep:
            print(f"  logs: {silent_log} and {graphical_log}")
        else:
            print("  temporary logs were validated and removed; pass --keep to retain them")
    except Exception:
        print(f"Classic Windows sandbox check failed; retained {scratch}", file=sys.stderr)
        raise
    finally:
        if not keep:
            shutil.rmtree(scratch, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep", action="store_true", help="retain the temporary work directory and logs")
    parser.add_argument("--app", type=Path, default=APP, help="packaged Flashback app to check")
    args = parser.parse_args()
    global HOST, RUNTIME, ENGINE, POLICY
    # The build invokes this from Flashback/, while this harness runs child
    # processes from ROOT. Resolve once at the caller boundary so a relative
    # --app keeps referring to the freshly built artifact.
    app = args.app.resolve()
    HOST = app / "Contents/MacOS/NativeHost"
    RUNTIME = app / "Contents/Resources/ClassicWindows/dosbox-x.app"
    ENGINE = RUNTIME / "Contents/MacOS/dosbox-x"
    POLICY = app / "Contents/Resources/ClassicWindows.policy"
    try:
        run_check(args.keep)
    except CheckFailure as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
