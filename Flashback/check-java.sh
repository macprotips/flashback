#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
cd "$(dirname "$0")"
jdk='../vendor/java/liberica/arm64/jdk8u504.jdk'
check=$(mktemp -d "${TMPDIR:-/tmp}/flashback-java.XXXXXX")
trap 'rm -rf "$check"' EXIT
mkdir -p "$check/game/classes" "$check/saves" "$check/host"
"$jdk/bin/javac" -XDignore.symbol.file -d "$check/host" JavaRunner.java Wiz3Display.java
"$jdk/bin/javac" -d "$check/game/classes" JavaPolicyCheck.java
"$jdk/bin/jar" cf "$check/Host.jar" -C "$check/host" .
"$jdk/bin/jar" cfe "$check/game/Check.jar" JavaPolicyCheck -C "$check/game/classes" .
runner=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).as_uri())' "$check/Host.jar")
# A small trusted driver invokes the game code; --play normally waits for AWT windows.
cat > "$check/RunCheck.java" <<'JAVA'
public class RunCheck { public static void main(String[] args) throws Exception {
    JavaRunner.launch(new java.io.File(args[0]));
} }
JAVA
"$jdk/bin/javac" -cp "$check/host" -d "$check/host" "$check/RunCheck.java"
"$jdk/bin/jar" cf "$check/Host.jar" -C "$check/host" .
"$jdk/bin/java" -Djava.security.manager "-Djava.security.policy==$(pwd)/Java.policy" \
    "-Dflashback.runner=$runner" "-Dflashback.game=$check/game" "-Duser.home=$check/saves" \
    -cp "$check/Host.jar" RunCheck "$check/game/Check.jar"
"$jdk/bin/java" -cp "$check/Host.jar" JavaRunner --inspect "$check/game/Check.jar"
"$jdk/bin/jar" cf "$check/game/Library.jar" -C "$check/game/classes" .
if "$jdk/bin/java" -cp "$check/Host.jar" JavaRunner --inspect "$check/game/Library.jar" >"$check/error" 2>&1; then
    echo 'FAIL: accepted a library without a Main-Class'; exit 1
fi
if [ "$#" = 2 ]; then
    mkdir -p "$2"
    rm -f "$2/Result.txt"
    "$jdk/bin/javac" -cp "$check/host" -d "$check/host" JavaChecks.java
    "$jdk/bin/jar" cf "$check/Host.jar" -C "$check/host" .
    "$jdk/bin/java" -Djava.security.manager "-Djava.security.policy==$(pwd)/Java.policy" \
        "-Dflashback.runner=$runner" "-Dflashback.game=$(dirname "$1")" "-Duser.home=$check/saves" \
        -cp "$check/Host.jar" JavaChecks "$1" "$2"
    test -f "$2/Result.txt"
fi
