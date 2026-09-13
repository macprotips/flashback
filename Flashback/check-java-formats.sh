#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
cd "$(dirname "$0")"
jdk='../vendor/java/liberica/arm64/jdk8u504.jdk'
check=$(mktemp -d /tmp/flashback-java-formats.XXXXXX)
trap 'rm -rf "$check"' EXIT
mkdir -p "$check/host" "$check/game/lib +% space" "$check/classes" "$check/saves"
"$jdk/bin/javac" -XDignore.symbol.file -d "$check/host" JavaRunner.java Wiz3Display.java JavaFormatChecks.java
"$jdk/bin/javac" -d "$check/classes" JavaFormatHelper.java JavaFormatFixture.java
"$jdk/bin/jar" cf "$check/Host.jar" -C "$check/host" .
runner=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).as_uri())' "$check/Host.jar")
"$jdk/bin/jar" cf "$check/game/lib +% space/helper.jar" -C "$check/classes" JavaFormatHelper.class
printf 'offline resource' > "$check/classes/fixture data.txt"
"$jdk/bin/jar" cf "$check/game/lib +% space/game.jar" -C "$check/classes" JavaFormatFixture.class -C "$check/classes" 'JavaFormatFixture$Application.class' -C "$check/classes" 'JavaFormatFixture$LifecycleApplet.class' -C "$check/classes" 'JavaFormatFixture$FailingApplication.class' -C "$check/classes" 'JavaFormatFixture$FailingApplet.class' -C "$check/classes" 'fixture data.txt'
cat > "$check/applet.mf" <<'EOF'
Manifest-Version: 1.0
Applet-Class: JavaFormatFixture$LifecycleApplet
EOF
"$jdk/bin/jar" cfm "$check/game/Applet.jar" "$check/applet.mf" -C "$check/classes" JavaFormatFixture.class -C "$check/classes" 'JavaFormatFixture$LifecycleApplet.class'
cat > "$check/game/app.jnlp" <<'EOF'
<jnlp><resources><jar href="lib%20%2B%25%20space/game.jar"/><jar href="lib%20%2B%25%20space/helper.jar"/></resources><application-desc main-class="JavaFormatFixture$Application"><argument>first arg</argument><argument>sp ace</argument></application-desc></jnlp>
EOF
cat > "$check/game/applet.jnlp" <<'EOF'
<jnlp codebase="lib%20%2B%25%20space"><resources><jar href="game.jar"/><jar href="helper.jar"/></resources><applet-desc main-class="JavaFormatFixture$LifecycleApplet" width="320" height="200"><param name="magic" value="value with spaces"/></applet-desc></jnlp>
EOF
cat > "$check/game/remote.jnlp" <<'EOF'
<jnlp><resources><jar href="https://example.invalid/game.jar"/></resources><application-desc main-class="Nope"/></jnlp>
EOF
cat > "$check/game/native.jnlp" <<'EOF'
<jnlp><resources><nativelib href="native.jar"/><jar href="lib%20%2B%25%20space/game.jar"/></resources><application-desc main-class="Nope"/></jnlp>
EOF
cat > "$check/game/escape.jnlp" <<'EOF'
<jnlp><resources><jar href="../outside.jar"/></resources><application-desc main-class="Nope"/></jnlp>
EOF
cat > "$check/game/fail.jnlp" <<'EOF'
<jnlp><resources><jar href="lib%20%2B%25%20space/game.jar"/></resources><application-desc main-class="JavaFormatFixture$FailingApplication"/></jnlp>
EOF
cat > "$check/game/fail-applet.jnlp" <<'EOF'
<jnlp codebase="lib%20%2B%25%20space"><resources><jar href="game.jar"/></resources><applet-desc main-class="JavaFormatFixture$FailingApplet" width="320" height="200"/></jnlp>
EOF
cat > "$check/game/properties.jnlp" <<'EOF'
<jnlp><resources><property name="java.security.policy" value="evil"/></resources><application-desc main-class="Nope"/></jnlp>
EOF
cat > "$check/game/platform.jnlp" <<'EOF'
<jnlp><resources os="Windows"><jar href="Applet.jar"/></resources><application-desc main-class="Nope"/></jnlp>
EOF
cat > "$check/game/host.jnlp" <<'EOF'
<jnlp><resources><jar href="Applet.jar"/></resources><application-desc main-class="JavaRunner"/></jnlp>
EOF
"$jdk/bin/java" -Djava.security.manager "-Djava.security.policy==$(pwd)/Java.policy" \
  "-Dflashback.runner=$runner" "-Dflashback.game=$check/game" "-Duser.home=$check/saves" \
  -cp "$check/Host.jar" JavaFormatChecks "$check/game" "$check/saves"
python3 check-java-format-process.py "$jdk" "$check/Host.jar" "$check/game" "$check/saves" "$(pwd)/Java.policy" "$runner"
test "$("$jdk/bin/java" -cp "$check/Host.jar" JavaRunner --inspect "$check/game/Applet.jar")" = 'APPLET:JavaFormatFixture$LifecycleApplet'

sdk="${SDKROOT:-$(xcrun --show-sdk-path)}"
swiftc -sdk "$sdk" Library.swift LegacyImport.swift WebPage.swift WebTransfer.swift WebImport.swift JavaRecoveryChecks.swift -o "$check/recovery-checks"
python3 check-java-recovery.py "$check/recovery-checks" "$jdk" "$check/Host.jar" "$check/game" "$(pwd)/Java.policy" "$runner"
