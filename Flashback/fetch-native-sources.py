#!/usr/bin/env python3
"""Fetch the pinned native-runtime source inputs listed in NATIVE-SOURCES.json."""

from __future__ import annotations

import hashlib
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import tarfile
import urllib.error
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MANIFEST = Path(__file__).resolve().parent / "Licenses" / "NATIVE-SOURCES.json"
COMPONENTS = Path(__file__).resolve().parent / "Licenses" / "DOS-SCUMMVM-SOURCES.json"
SCUMMVM_PROVENANCE = Path(__file__).resolve().parent / "Licenses" / "DOS-SCUMMVM-PROVENANCE.json"
DESTINATION = ROOT / "vendor" / "sources" / "native"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify(path: Path, entry: dict) -> None:
    if sha256(path) != entry["sha256"]:
        raise RuntimeError(f"source hash mismatch: {path}")
    if expected := entry.get("upstream_sha512"):
        with path.open("rb") as source:
            actual = hashlib.file_digest(source, "sha512").hexdigest()
        if actual != expected:
            raise RuntimeError(f"upstream recipe SHA-512 mismatch: {path}")
    if markers := entry.get("source_markers"):
        with tarfile.open(path) as archive:
            for marker in markers:
                if not archive.getmember(marker).isfile():
                    raise RuntimeError(f"missing source file {marker}: {path}")


def fetch(entry: dict, verify_only: bool = False) -> None:
    filename = entry["file"]
    destination = DESTINATION / filename
    if destination.exists():
        verify(destination, entry)
        print(f"verified {filename}")
        return
    if verify_only:
        raise RuntimeError(f"missing source archive: {destination}")

    with tempfile.NamedTemporaryFile(dir=DESTINATION, prefix=f".{filename}.", delete=False) as output:
        temporary = Path(output.name)
        try:
            with urllib.request.urlopen(entry["url"], timeout=120) as response:
                shutil.copyfileobj(response, output)
            output.flush()
            os.fsync(output.fileno())
            verify(temporary, entry)
            os.replace(temporary, destination)
            print(f"fetched {filename}")
        finally:
            temporary.unlink(missing_ok=True)


def verify_component_sources() -> None:
    """Verify the source archives paired with the native application bundles."""
    components = json.loads(COMPONENTS.read_text())["components"]
    for component in components:
        source = component["source"]
        path = ROOT / source["retained_as"]
        if not path.is_file():
            raise RuntimeError(f"missing {component['name']} source archive: {path}")
        verify(path, source)
        print(f"verified {path.name}")


def run_output(*args: str) -> str:
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def verify_scummvm_build_record() -> dict:
    """Fail closed when the retained build receipt no longer matches its sources."""
    provenance = json.loads(SCUMMVM_PROVENANCE.read_text())
    if provenance.get("origin") != "retained-source-build":
        raise RuntimeError("ScummVM has no completed retained-source build provenance")
    record = ROOT / provenance["build_record"]
    verify(record, {"sha256": provenance["build_record_sha256"]})
    receipt = json.loads(record.read_text())
    lock_path = ROOT / "Flashback/Licenses/DOS-SCUMMVM-BUILD-LOCK.json"
    verify(lock_path, {"sha256": receipt["source_lock_sha256"]})
    lock = json.loads(lock_path.read_text())
    for entry in lock["sources"]:
        verify(DESTINATION / entry["file"], entry)
    for filename, expected in receipt["recipe_sha256"].items():
        verify(ROOT / filename, {"sha256": expected})
    for filename, expected in provenance["retained_evidence_sha256"].items():
        verify(ROOT / filename, {"sha256": expected})
    if set(receipt["architectures"]) != {"arm64", "x86_64"}:
        raise RuntimeError("ScummVM build receipt lacks both architectures")
    print("verified ScummVM source lock, exact recipes, build receipts and integration evidence")
    return provenance


def audit_scummvm_runtime(app: Path | None = None) -> None:
    """Compare source-built code independently of a later release signature."""
    provenance = verify_scummvm_build_record()
    app = app or ROOT / "Flashback.app/Contents/Resources/ScummVM/ScummVM.app"
    binary = app / "Contents/MacOS/scummvm"
    if not binary.is_file():
        raise RuntimeError(f"missing ScummVM executable: {binary}")
    architectures = set(run_output("/usr/bin/lipo", "-archs", str(binary)).split())
    if architectures != {"arm64", "x86_64"}:
        raise RuntimeError(f"ScummVM architectures differ: {architectures}")
    with tempfile.TemporaryDirectory(prefix="flashback-scummvm-audit-") as scratch:
        for architecture, evidence in provenance["architectures"].items():
            slice_path = Path(scratch) / architecture
            subprocess.run(("/usr/bin/lipo", str(binary), "-thin", architecture, "-output", str(slice_path)), check=True)
            subprocess.run(("/usr/bin/codesign", "--remove-signature", str(slice_path)), check=True, capture_output=True)
            if sha256(slice_path) != evidence["unsigned_slice_sha256"]:
                raise RuntimeError(f"ScummVM {architecture} code differs from the retained-source build")
            version = run_output("/usr/bin/arch", f"-{architecture}", str(binary), f"--config={Path(scratch) / (architecture + '.ini')}", "--version")
            if evidence["version_output"] not in version:
                raise RuntimeError(f"ScummVM {architecture} version/features differ from build provenance")
            listing = run_output("/usr/bin/arch", f"-{architecture}", str(binary), f"--config={Path(scratch) / (architecture + '.ini')}", "--list-engines")
            engines = [line.split()[0] for line in listing.splitlines() if line.strip() and not line.startswith(("Engine ID", "---", "WARNING:", "Creating configuration"))]
            if engines != ["director"]:
                raise RuntimeError(f"Unexpected ScummVM engine list: {listing}")
            imports = run_output("/usr/bin/otool", "-arch", architecture, "-L", str(binary))
            for line in imports.splitlines()[1:]:
                if not line.strip().startswith(("/System/Library/", "/usr/lib/")):
                    raise RuntimeError(f"ScummVM imports a non-system dynamic library: {line}")
            if "minos 11.0" not in run_output("/usr/bin/otool", "-arch", architecture, "-l", str(binary)):
                raise RuntimeError("ScummVM minimum macOS target differs")
    print("verified source-built ScummVM 2026.3.0 code, both architectures and Director-only features")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-only", action="store_true", help="verify cached inputs without network access")
    parser.add_argument("--audit-scummvm-runtime", action="store_true", help="verify the bundled ScummVM code against its retained-source build")
    parser.add_argument("--require-complete", action="store_true", help="also fail while corresponding-source coverage is incomplete")
    parser.add_argument("--scummvm-app", type=Path, help="audit this app instead of the Flashback bundle")
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    filenames = [entry["file"] for entry in manifest["fetch"]]
    if len(set(filenames)) != len(filenames) or any(Path(name).name != name or name in (".", "..") for name in filenames):
        raise RuntimeError("source manifest contains duplicate or unsafe filenames")
    DESTINATION.mkdir(parents=True, exist_ok=True)
    for entry in manifest["fetch"]:
        fetch(entry, args.verify_only)
    verify_component_sources()
    if args.audit_scummvm_runtime:
        audit_scummvm_runtime(args.scummvm_app)
    status = manifest["coverage"]["status"]
    print(f"Verified {len(filenames)} native inputs; corresponding-source coverage: {status}.")
    if status == "complete":
        verify_scummvm_build_record()
    if status != "complete":
        print(manifest["coverage"]["statement"], file=sys.stderr)
        if args.require_complete:
            raise RuntimeError("native corresponding source is incomplete; release packaging remains blocked")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, KeyError, tarfile.TarError, urllib.error.URLError) as error:
        print(f"native source fetch failed: {error}", file=sys.stderr)
        raise SystemExit(1)
