#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
cd "$(dirname "$0")"
sdk="${SDKROOT:-$(xcrun --show-sdk-path)}"
cache="${TMPDIR:-/tmp}/flashback-module-cache"
app='../Flashback.app/Contents'
# Smoke and compatibility runs write reports next to Contents. The app bundle
# is derived output, so remove those reports before signing a fresh build.
find "${app%/Contents}" -mindepth 1 -maxdepth 1 ! -name Contents -exec rm -rf {} + 2>/dev/null || true
mkdir -p "$app/MacOS" "$app/Resources/Runtime" build
swiftc -module-cache-path "$cache" -sdk "$sdk" Library.swift LegacyImport.swift Tests.swift -o build/checks
swiftc -module-cache-path "$cache" -sdk "$sdk" Library.swift LegacyImport.swift LegacyImportChecks.swift -o build/legacy-checks
swiftc -parse-as-library -module-cache-path "$cache" -sdk "$sdk" -D SHOCKWAVE_COMPAT_CHECK ShockwaveCompatibility.swift -o build/shockwave-compat-check
swiftc -module-cache-path "$cache" -sdk "$sdk" StorageLocation.swift StorageLocationChecks.swift -o build/storage-location-checks
swiftc -module-cache-path "$cache" -sdk "$sdk" ClassicWindows.swift ClassicWindowsChecks.swift -o build/classic-windows-checks
swiftc -module-cache-path "$cache" -sdk "$sdk" ClassicWindowsSetup.swift ClassicWindowsSetupChecks.swift -o build/classic-windows-setup-checks
swiftc -module-cache-path "$cache" -sdk "$sdk" Library.swift LegacyImport.swift ClassicWindowsImport.swift ClassicWindowsImportChecks.swift -o build/classic-windows-import-checks
for check in DOSOptions DOSGameData; do
    swiftc -module-cache-path "$cache" -sdk "$sdk" Library.swift LegacyImport.swift "${check}.swift" "${check}Checks.swift" -o "build/${check}-checks"
    "build/${check}-checks"
done
swiftc -module-cache-path "$cache" -sdk "$sdk" Library.swift LegacyImport.swift DOSDisc.swift DOSDiscChecks.swift -o build/DOSDisc-checks
swiftc -module-cache-path "$cache" -sdk "$sdk" Library.swift LegacyImport.swift DOSOptions.swift DOSDisc.swift NativePlayer.swift DOSLaunchChecks.swift -framework Cocoa -o build/DOSLaunch-checks
dosbox="$(cd '../vendor/dosbox-staging/DOSBox Staging.app/Contents/MacOS' && pwd)/dosbox"
build/DOSDisc-checks "$dosbox"
build/legacy-checks
build/checks
build/shockwave-compat-check
build/storage-location-checks
build/classic-windows-checks
build/classic-windows-setup-checks
build/classic-windows-import-checks
python3 ./check-classic-guest-source.py
python3 ./shockwave_health.py --self-test
SDKROOT="$sdk" sh ./check-website.sh
for arch in arm64 x86_64; do
    swiftc -O -module-cache-path "$cache" -sdk "$sdk" -target "${arch}-apple-macosx13.0" \
        Library.swift StorageLocation.swift StorageSettingsWindow.swift LegacyImport.swift WebPage.swift WebTransfer.swift WebImport.swift Archive.swift ArchiveView.swift ArchiveUICheck.swift WebsiteImportView.swift WebRouting.swift WebsiteUICheck.swift BrandArtwork.swift Welcome.swift Help.swift Player.swift ShockwaveCompatibility.swift JavaPlayer.swift NativePlayer.swift DOSOptions.swift DOSDisc.swift DOSGameData.swift DOSSettingsWindow.swift DOSDiscsView.swift ClassicWindows.swift ClassicWindowsImport.swift ClassicWindowsSetup.swift ClassicWindowsSetupView.swift ClassicWindowsInstaller.swift ClassicWindowsSetupWindow.swift App.swift SmokeCheck.swift LayoutCheck.swift -framework Cocoa -framework SwiftUI -framework WebKit \
        -o "build/Flashback-$arch"
done
for arch in arm64 x86_64; do
    swiftc -O -sdk "$sdk" -target "${arch}-apple-macosx13.0" NativeHost.swift -framework Cocoa -o "build/NativeHost-$arch"
done
lipo -create build/NativeHost-arm64 build/NativeHost-x86_64 -output "$app/MacOS/NativeHost"
codesign --force --sign - "$app/MacOS/NativeHost"
lipo -create build/Flashback-arm64 build/Flashback-x86_64 -output build/Flashback-universal
mv build/Flashback-universal "$app/MacOS/Flashback"
cp Player.html Shockwave.html shockwave-compat-profiles.json Licenses.html LICENSE SOURCE.md "$app/Resources/"
ditto Licenses "$app/Resources/Licenses"
ditto ../vendor/dirplayer/runtime "$app/Resources/Shockwave"
cp ../vendor/ruffle-web/*.js ../vendor/ruffle-web/*.wasm ../vendor/ruffle-web/LICENSE_* "$app/Resources/Runtime/"
cp Info.plist "$app/Info.plist"
jdk='../vendor/java/liberica/arm64/jdk8u504.jdk'
rm -rf "$app/Resources/Java"
rm -rf build/java
mkdir -p build/java "$app/Resources/Java"
# Use the ASM copy already included in this pinned JDK/JRE.
archive_jar='../vendor/archive/commons-compress-1.28.0.jar'
archive_io_jar='../vendor/archive/commons-io-2.20.0.jar'
archive_lang_jar='../vendor/archive/commons-lang3-3.18.0.jar'
[ -f "$archive_jar" ] && [ -f "$archive_io_jar" ] && [ -f "$archive_lang_jar" ] || { echo 'Run python3 Flashback/fetch-archive-dependencies.py before building.' >&2; exit 1; }
archive_classpath="$archive_jar:$archive_io_jar:$archive_lang_jar"
archive_jar_tool="$(cd "$jdk/bin" && pwd)/jar"
"$jdk/bin/javac" -XDignore.symbol.file -cp "$archive_classpath" -d build/java JavaRunner.java Wiz3Display.java GameArchive.java
# JavaRunner is launched with a deliberately fixed classpath, so merge the
# checksum-pinned archive reader into this private helper JAR.
(cd build/java && "$archive_jar_tool" xf "../../$archive_jar")
(cd build/java && "$archive_jar_tool" xf "../../$archive_io_jar")
(cd build/java && "$archive_jar_tool" xf "../../$archive_lang_jar")
"$jdk/bin/jar" cf "$app/Resources/JavaRunner.jar" -C build/java .
rm -rf build/j2me
mkdir -p build/j2me/classes "$app/Resources/J2ME"
find ../vendor/sources/freej2me/src -name '*.java' \
    -not -path '*/libretro/*' -not -path '*/win32pad/*' -print > build/j2me-sources.txt
"$jdk/bin/javac" -d build/j2me/classes @build/j2me-sources.txt
cp -R ../vendor/sources/freej2me/resources/. build/j2me/classes/
mkdir -p build/j2me/classes/META-INF
cp ../vendor/sources/freej2me/META-INF/freej2me-build.version build/j2me/classes/META-INF/
cat > build/j2me-manifest <<'EOF'
Manifest-Version: 1.0
Main-Class: org.recompile.freej2me.FreeJ2ME
EOF
"$jdk/bin/jar" cfm "$app/Resources/J2ME/freej2me.jar" build/j2me-manifest -C build/j2me/classes .
mkdir -p build/archive-check
"$jdk/bin/javac" -cp build/java -d build/archive-check ArchiveChecks.java
if [ -f ../work/checks/tmp/dos-matrix/lemmdemo.zip ]; then
    "$jdk/bin/java" -cp build/java:build/archive-check ArchiveChecks ../work/checks/tmp/dos-matrix/lemmdemo.zip
else
    "$jdk/bin/java" -cp build/java:build/archive-check ArchiveChecks
fi
cp Java.policy Native.policy ClassicWindows.policy "$app/Resources/"
# Classic Windows remains a development-only prototype. Opt in explicitly;
# ordinary and release-candidate builds must not expose an unfinished player.
rm -rf "$app/Resources/ClassicWindows"
if [ "${FLASHBACK_EXPERIMENTAL_CLASSIC_WINDOWS:-0}" = 1 ] && [ -d ../vendor/classic-windows ]; then
    ditto ../vendor/classic-windows "$app/Resources/ClassicWindows"
    codesign --force --sign - --entitlements DOSBox.entitlements.plist "$app/Resources/ClassicWindows/dosbox-x.app"
fi
rm -rf "$app/Resources/DOS" "$app/Resources/ScummVM"
ditto ../vendor/dosbox-staging "$app/Resources/DOS"
ditto ../vendor/scummvm "$app/Resources/ScummVM"
build/DOSLaunch-checks "$(cd .. && pwd)/Flashback.app"
# Upstream's offline manual contains third-party game screenshots and is not
# needed by the embedded runtime. Keep it out of Flashback and release ZIPs.
rm -rf "$app/Resources/DOS/DOSBox Staging.app/Contents/Resources/docs"
codesign --force --sign - --entitlements DOSBox.entitlements.plist "$app/Resources/DOS/DOSBox Staging.app"
# Nested applications must launch at their bundled path, not through App Translocation.
for attribute in com.apple.quarantine com.apple.FinderInfo com.apple.ResourceFork; do
    xattr -dr "$attribute" "$app/Resources/DOS" "$app/Resources/ScummVM" 2>/dev/null || true
done
sh ./check-java.sh
sh ./check-java-formats.sh
ditto "$jdk/jre" "$app/Resources/Java/arm64"
cp -f "$jdk/LICENSE" "$jdk/ASSEMBLY_EXCEPTION" "$jdk/THIRD_PARTY_README" "$jdk/readme.txt" "$jdk/release" "$app/Resources/Java/arm64/"
ditto '../vendor/java/liberica/x86_64/jre8u504.jre' "$app/Resources/Java/x86_64"
SDKROOT="$sdk" sh ./check-archive.sh
swiftc -module-cache-path "$cache" -sdk "$sdk" BrandArtwork.swift MakeIcon.swift -o build/make-icon
mkdir -p build/AppIcon.iconset
build/make-icon build/AppIcon.iconset/icon_512x512@2x.png
sips -z 1024 1024 build/AppIcon.iconset/icon_512x512@2x.png >/dev/null
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" build/AppIcon.iconset/icon_512x512@2x.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    if [ "$size" != 512 ]; then
        double=$((size * 2))
        sips -z "$double" "$double" build/AppIcon.iconset/icon_512x512@2x.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
    fi
done
iconutil -c icns build/AppIcon.iconset -o "$app/Resources/AppIcon.icns"
codesign --force --sign - '../Flashback.app'
codesign --verify --deep --strict '../Flashback.app'
python3 ./check-native-sandbox.py --host "$app/MacOS/NativeHost" \
    --dos-app "$app/Resources/DOS/DOSBox Staging.app" \
    --scummvm-app "$app/Resources/ScummVM/ScummVM.app"
python3 ./check-native-games.py --app '../Flashback.app'
if [ "${FLASHBACK_EXPERIMENTAL_CLASSIC_WINDOWS:-0}" = 1 ]; then
    python3 ./check-classic-sandbox.py --app '../Flashback.app'
fi
printf 'Built Flashback.app for Apple Silicon and Intel.\n'
