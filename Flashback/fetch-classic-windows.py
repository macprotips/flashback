#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Fetch and combine the checksum-pinned macOS DOSBox-X 2026.08.31 builds.

The upstream macOS archives have one architecture in Contents/MacOS/dosbox-x
and architecture-specific libraries in Contents/MacOS/{arm64,x86_64}.  This
script produces a single app with both library directories and a universal
main executable.  It only publishes a fully verified staging directory and
will not replace an existing vendor/classic-windows runtime.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from urllib.request import urlopen


VERSION = "2026.08.31"
RELEASE = f"https://github.com/joncampbell123/dosbox-x/releases/download/dosbox-x-v{VERSION}"
ARCHIVES = {
    "arm64": {
        "filename": f"dosbox-x-macosx-arm64-{VERSION}.zip",
        "sha256": "09addce22e0846fbe8872b5a4c1be878de529ed2d0c336d7ebe2848814ed0d4e",
    },
    "x86_64": {
        "filename": f"dosbox-x-macosx-x86_64-{VERSION}.zip",
        "sha256": "c367e924179f8d804972eb41313d553ffb1cd9f7e8368113bce5890aa1b512b9",
    },
}
for _asset in ARCHIVES.values():
    _asset["url"] = f"{RELEASE}/{_asset['filename']}"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verified(path: Path, expected: str) -> bool:
    return path.is_file() and sha256(path) == expected


def command(*args: str) -> str:
    return subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE).stdout.strip()


def fetch_archive(root: Path, arch: str, cache: Path) -> Path:
    asset = ARCHIVES[arch]
    destination = cache / asset["filename"]
    if verified(destination, asset["sha256"]):
        print(f"Verified cached {arch} archive: {destination}")
        return destination

    reuse = root / "work" / "runtime" / "dosbox-x-arm64.zip"
    if arch == "arm64" and verified(reuse, asset["sha256"]):
        print(f"Reusing verified ARM archive: {reuse}")
        shutil.copy2(reuse, destination)
        return destination

    temporary = destination.with_suffix(destination.suffix + ".download")
    temporary.unlink(missing_ok=True)
    print(f"Downloading {asset['url']}")
    try:
        with urlopen(asset["url"]) as response, temporary.open("wb") as output:
            shutil.copyfileobj(response, output, 1024 * 1024)
        actual = sha256(temporary)
        if actual != asset["sha256"]:
            raise RuntimeError(f"SHA-256 mismatch for {arch}: {actual}")
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"Verified downloaded {arch} archive: {destination}")
    return destination


def unpack(archive: Path, destination: Path) -> Path:
    command("ditto", "-x", "-k", str(archive), str(destination))
    app = destination / "dosbox-x" / "dosbox-x.app"
    if not app.is_dir():
        raise RuntimeError(f"Expected app bundle missing from {archive}: {app}")
    return app


def require_architecture(app: Path, arch: str) -> Path:
    macos = app / "Contents" / "MacOS"
    executable = macos / "dosbox-x"
    own_libraries = macos / arch
    other_libraries = macos / ("x86_64" if arch == "arm64" else "arm64")
    if not executable.is_file() or not own_libraries.is_dir() or not other_libraries.is_dir():
        raise RuntimeError(f"Malformed {arch} app bundle")
    if not any(own_libraries.iterdir()) or any(other_libraries.iterdir()):
        raise RuntimeError(f"Unexpected library layout in {arch} app bundle")
    architectures = command("lipo", "-archs", str(executable)).split()
    if architectures != [arch]:
        raise RuntimeError(f"Expected {arch} executable, found {architectures}")
    return executable


def copy_upstream_notices(source: Path, destination: Path) -> None:
    for name in ("CHANGELOG.txt", "COPYING.txt", "README.txt"):
        notice = source / name
        if not notice.is_file():
            raise RuntimeError(f"Upstream notice missing: {notice}")
        shutil.copy2(notice, destination / name)


def write_provenance(destination: Path, binary: Path) -> None:
    relative_binary = "dosbox-x.app/Contents/MacOS/dosbox-x"
    file_audit = command("file", "-b", str(binary)).replace(str(binary), relative_binary)
    provenance = {
        "component": "DOSBox-X",
        "version": VERSION,
        "release": f"dosbox-x-v{VERSION}",
        "archives": {
            arch: {"url": asset["url"], "sha256": asset["sha256"]}
            for arch, asset in ARCHIVES.items()
        },
        "layout": {
            "app": "dosbox-x.app",
            "mainExecutable": "dosbox-x.app/Contents/MacOS/dosbox-x",
            "architectureLibraries": [
                "dosbox-x.app/Contents/MacOS/arm64",
                "dosbox-x.app/Contents/MacOS/x86_64",
            ],
        },
        "audit": {
            "lipoArchs": command("lipo", "-archs", str(binary)).split(),
            "file": file_audit,
        },
    }
    (destination / "provenance.json").write_text(
        json.dumps(provenance, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def validate_published(runtime: Path) -> Path:
    binary = runtime / "dosbox-x.app" / "Contents" / "MacOS" / "dosbox-x"
    macos = binary.parent
    if not binary.is_file() or not any((macos / "arm64").iterdir()) or not any((macos / "x86_64").iterdir()):
        raise RuntimeError(f"Existing runtime is incomplete: {runtime}")
    provenance_path = runtime / "provenance.json"
    try:
        provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"Existing runtime lacks valid provenance: {provenance_path}") from error
    expected_archives = {
        arch: {"url": asset["url"], "sha256": asset["sha256"]}
        for arch, asset in ARCHIVES.items()
    }
    if provenance.get("component") != "DOSBox-X" or provenance.get("version") != VERSION or provenance.get("archives") != expected_archives:
        raise RuntimeError(f"Existing runtime does not match pinned DOSBox-X {VERSION}")
    if set(command("lipo", "-archs", str(binary)).split()) != {"arm64", "x86_64"}:
        raise RuntimeError(f"Existing runtime is not universal: {binary}")
    for name in ("CHANGELOG.txt", "COPYING.txt", "README.txt"):
        if not (runtime / name).is_file():
            raise RuntimeError(f"Existing runtime is missing upstream notice: {name}")
    return binary


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    cache = root / "work" / "classic-windows-cache"
    vendor = root / "vendor"
    published = vendor / "classic-windows"
    if published.exists():
        binary = validate_published(published)
        print(f"Verified existing DOSBox-X {VERSION}: {published}")
        print(command("file", str(binary)))
        print(f"lipo: {command('lipo', '-archs', str(binary))}")
        return 0
    cache.mkdir(parents=True, exist_ok=True)
    vendor.mkdir(parents=True, exist_ok=True)

    archives = {arch: fetch_archive(root, arch, cache) for arch in ARCHIVES}
    with tempfile.TemporaryDirectory(prefix="classic-windows-unpack-", dir=cache) as unpack_root:
        unpack_root_path = Path(unpack_root)
        arm_tree = unpack_root_path / "arm64"
        x86_tree = unpack_root_path / "x86_64"
        arm_app = unpack(archives["arm64"], arm_tree)
        x86_app = unpack(archives["x86_64"], x86_tree)
        arm_binary = require_architecture(arm_app, "arm64")
        x86_binary = require_architecture(x86_app, "x86_64")

        stage = Path(tempfile.mkdtemp(prefix=".classic-windows-stage-", dir=vendor))
        try:
            copy_upstream_notices(arm_app.parent, stage)
            merged_app = stage / "dosbox-x.app"
            shutil.copytree(arm_app, merged_app, symlinks=True)
            merged_macos = merged_app / "Contents" / "MacOS"
            shutil.rmtree(merged_macos / "x86_64")
            shutil.copytree(x86_app / "Contents" / "MacOS" / "x86_64", merged_macos / "x86_64", symlinks=True)
            command("lipo", "-create", str(arm_binary), str(x86_binary), "-output", str(merged_macos / "dosbox-x"))
            merged_binary = merged_macos / "dosbox-x"
            merged_architectures = command("lipo", "-archs", str(merged_binary)).split()
            if set(merged_architectures) != {"arm64", "x86_64"}:
                raise RuntimeError(f"Universal executable audit failed: {merged_architectures}")
            if not any((merged_macos / "arm64").iterdir()) or not any((merged_macos / "x86_64").iterdir()):
                raise RuntimeError("Merged app is missing architecture-specific libraries")
            write_provenance(stage, merged_binary)
            if published.exists():
                raise RuntimeError(f"Refusing to replace existing runtime: {published}")
            os.replace(stage, published)
        except BaseException:
            shutil.rmtree(stage, ignore_errors=True)
            raise

    binary = published / "dosbox-x.app" / "Contents" / "MacOS" / "dosbox-x"
    print(f"Published DOSBox-X {VERSION}: {published}")
    print(command("file", str(binary)))
    print(f"lipo: {command('lipo', '-archs', str(binary))}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"fetch-classic-windows: {error}", file=sys.stderr)
        raise SystemExit(1)
