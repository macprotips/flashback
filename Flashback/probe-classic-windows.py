#!/usr/bin/env python3
"""Read-only DOSBox-X media probe. This does not establish Windows/gameplay compatibility."""
import argparse, hashlib, json, subprocess
from pathlib import Path

def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()

def probe(runtime, media, output):
    runtime, media, output = (Path(p).resolve() for p in (runtime, media, output))
    if media.suffix.lower() != ".iso":
        raise ValueError("The probe accepts ISO media only; preserve and convert other formats separately.")
    if any(c in str(media) for c in '\"\n\r%'):
        raise ValueError("Media path contains unsupported DOS command characters")
    output.mkdir(parents=True, exist_ok=True)
    before = digest(media)
    command = [str(runtime), "-defaultconf", "-defaultmapper", "-nopromptfolder", "-silent",
               "-c", f'imgmount d "{media}" -t iso', "-c", "dir d:\\"]
    result = subprocess.run(command, cwd=output, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    log = result.stdout.decode("utf-8", errors="replace")
    (output / "runtime.log").write_text(log)
    unchanged = before == digest(media)
    mounted = "CD-ROM image mounted to drive D" in log
    report = {"media": media.name, "sha256": before, "runtime_sha256": digest(runtime),
              "returncode": result.returncode, "mounted": mounted, "source_unchanged": unchanged,
              "windows_boot_tested": False, "gameplay_tested": False}
    (output / "media-probe.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if result.returncode == 0 and mounted and unchanged else 1

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runtime")
    parser.add_argument("media")
    parser.add_argument("output")
    args = parser.parse_args()
    raise SystemExit(probe(args.runtime, args.media, args.output))
