#!/usr/bin/env python3
"""Fetch checksum-pinned Apache Commons Compress runtime and source inputs."""
import hashlib
import shutil
import tarfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DESTINATION = ROOT / "vendor" / "archive"
ARTIFACTS = (
    ("commons-compress-1.28.0.jar",
     "https://repo.maven.apache.org/maven2/org/apache/commons/commons-compress/1.28.0/commons-compress-1.28.0.jar",
     "e1522945218456f3649a39bc4afd70ce4bd466221519dba7d378f2141a4642ca"),
    ("commons-compress-1.28.0-src.tar.gz",
     "https://dlcdn.apache.org/commons/compress/source/commons-compress-1.28.0-src.tar.gz",
     "5c870fa454221b24c81d10a28031a9183d55f2baab92c160ecc985e51a387662"),
    ("commons-io-2.20.0.jar",
     "https://repo.maven.apache.org/maven2/commons-io/commons-io/2.20.0/commons-io-2.20.0.jar",
     "df90bba0fe3cb586b7f164e78fe8f8f4da3f2dd5c27fa645f888100ccc25dd72"),
    ("commons-io-2.20.0-sources.jar",
     "https://repo.maven.apache.org/maven2/commons-io/commons-io/2.20.0/commons-io-2.20.0-sources.jar",
     "7a87277538cce40da6389a7163a4d9458bc7a9c39937a329881b91d144be8e0d"),
    ("commons-lang3-3.18.0.jar",
     "https://repo.maven.apache.org/maven2/org/apache/commons/commons-lang3/3.18.0/commons-lang3-3.18.0.jar",
     "4eeeae8d20c078abb64b015ec158add383ac581571cddc45c68f0c9ae0230720"),
    ("commons-lang3-3.18.0-sources.jar",
     "https://repo.maven.apache.org/maven2/org/apache/commons/commons-lang3/3.18.0/commons-lang3-3.18.0-sources.jar",
     "b15732a13e40df7f07c30f2cb8572874798e8dde581f1398943d2ad3765bafaa"),
)

def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()

def fetch(name: str, url: str, expected: str) -> Path:
    path = DESTINATION / name
    if not path.is_file() or digest(path) != expected:
        temporary = path.with_suffix(path.suffix + ".part")
        with urllib.request.urlopen(url, timeout=60) as response, temporary.open("wb") as output:
            shutil.copyfileobj(response, output)
        temporary.replace(path)
    actual = digest(path)
    if actual != expected:
        raise RuntimeError(f"SHA-256 mismatch for {name}: {actual}")
    print(f"Verified {name}")
    return path

def main() -> None:
    DESTINATION.mkdir(parents=True, exist_ok=True)
    paths = {path.name: path for path in (fetch(*artifact) for artifact in ARTIFACTS)}
    with tarfile.open(paths["commons-compress-1.28.0-src.tar.gz"], "r:gz") as source:
        for name in ("LICENSE.txt", "NOTICE.txt"):
            member = source.getmember("commons-compress-1.28.0-src/" + name)
            with source.extractfile(member) as input, (DESTINATION / ("commons-compress-" + name)).open("wb") as output:
                shutil.copyfileobj(input, output)
    with zipfile.ZipFile(paths["commons-io-2.20.0-sources.jar"]) as source:
        for name in ("LICENSE.txt", "NOTICE.txt"):
            with source.open("META-INF/" + name) as input, (DESTINATION / ("commons-io-" + name)).open("wb") as output:
                shutil.copyfileobj(input, output)
    with zipfile.ZipFile(paths["commons-lang3-3.18.0-sources.jar"]) as source:
        for name in ("LICENSE.txt", "NOTICE.txt"):
            with source.open("META-INF/" + name) as input, (DESTINATION / ("commons-lang3-" + name)).open("wb") as output:
                shutil.copyfileobj(input, output)
    print(f"Archive dependency is ready in {DESTINATION}")

if __name__ == "__main__":
    main()
