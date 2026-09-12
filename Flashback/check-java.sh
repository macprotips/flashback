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
cat > "$check/midlet.mf" <<'EOF'
Manifest-Version: 1.0
MIDlet-1: Check,,JavaPolicyCheck
MicroEdition-Profile: MIDP-2.0
MicroEdition-Configuration: CLDC-1.1
EOF
"$jdk/bin/jar" cfm "$check/game/Midlet.jar" "$check/midlet.mf" -C "$check/game/classes" .
test "$($jdk/bin/java -cp "$check/Host.jar" JavaRunner --inspect "$check/game/Midlet.jar")" = J2ME
test "$($jdk/bin/java -cp "$check/Host.jar" JavaRunner --j2me-config "$check/game/Midlet.jar")" = $'J2ME_CONFIG\t240\t320\t2\t0\t60'
cat > "$check/game/Midlet.jad" <<'EOF'
Nokia-MIDlet-Original-Display-Size: 176x208
MIDlet-FPS: 30
Nokia-Platform: Nokia*
EOF
test "$($jdk/bin/java -cp "$check/Host.jar" JavaRunner --j2me-config "$check/game/Midlet.jar")" = $'J2ME_CONFIG\t176\t208\t2\t0\t30'
sed -i '' 's/Nokia\*/Siemens/' "$check/game/Midlet.jad"
test "$($jdk/bin/java -cp "$check/Host.jar" JavaRunner --j2me-config "$check/game/Midlet.jar")" = $'J2ME_CONFIG\t176\t208\t2\t7\t30'
for size in 0x320 999999999999999999999x320 invalid; do
    printf 'MIDlet-Display-Size: %s\n' "$size" > "$check/game/Midlet.jad"
    if "$jdk/bin/java" -cp "$check/Host.jar" JavaRunner --j2me-config "$check/game/Midlet.jar" >"$check/error" 2>&1; then
        echo 'FAIL: accepted an invalid Java ME display'; exit 1
    fi
done
sed -i '' 's/Check,,JavaPolicyCheck/Check,,MissingMIDlet/' "$check/midlet.mf"
"$jdk/bin/jar" cfm "$check/game/Missing.jar" "$check/midlet.mf" -C "$check/game/classes" .
if "$jdk/bin/java" -cp "$check/Host.jar" JavaRunner --inspect "$check/game/Missing.jar" >"$check/error" 2>&1; then
    echo 'FAIL: accepted a missing MIDlet class'; exit 1
fi
"$jdk/bin/jar" cf "$check/game/Library.jar" -C "$check/game/classes" .
if "$jdk/bin/java" -cp "$check/Host.jar" JavaRunner --inspect "$check/game/Library.jar" >"$check/error" 2>&1; then
    echo 'FAIL: accepted a library without a Main-Class'; exit 1
fi
python3 check-j2me.py "$check/Host.jar"
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
