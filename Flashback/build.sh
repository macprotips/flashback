#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
set -eu
cd "$(dirname "$0")"
sdk="${SDKROOT:-$(xcrun --show-sdk-path)}"
cache="${TMPDIR:-/tmp}/flashback-module-cache"
app='../Flashback.app/Contents'
mkdir -p "$app/MacOS" "$app/Resources/Runtime" build
swiftc -module-cache-path "$cache" -sdk "$sdk" Library.swift Tests.swift -o build/checks
build/checks
SDKROOT="$sdk" sh ./check-website.sh
for arch in arm64 x86_64; do
    swiftc -O -module-cache-path "$cache" -sdk "$sdk" -target "${arch}-apple-macosx13.0" \
        Library.swift WebPage.swift WebTransfer.swift WebImport.swift Archive.swift ArchiveView.swift ArchiveUICheck.swift WebsiteImportView.swift WebRouting.swift WebsiteUICheck.swift BrandArtwork.swift Welcome.swift Help.swift Player.swift JavaPlayer.swift App.swift SmokeCheck.swift LayoutCheck.swift -framework Cocoa -framework SwiftUI -framework WebKit \
        -o "build/Flashback-$arch"
done
lipo -create build/Flashback-arm64 build/Flashback-x86_64 -output build/Flashback-universal
mv build/Flashback-universal "$app/MacOS/Flashback"
cp Player.html Shockwave.html Licenses.html LICENSE SOURCE.md "$app/Resources/"
ditto Licenses "$app/Resources/Licenses"
ditto ../vendor/dirplayer/runtime "$app/Resources/Shockwave"
cp ../vendor/ruffle-web/*.js ../vendor/ruffle-web/*.wasm ../vendor/ruffle-web/LICENSE_* "$app/Resources/Runtime/"
cp Info.plist "$app/Info.plist"
jdk='../vendor/java/liberica/arm64/jdk8u504.jdk'
rm -rf "$app/Resources/Java"
mkdir -p build/java "$app/Resources/Java"
# Use the ASM copy already included in this pinned JDK/JRE.
"$jdk/bin/javac" -XDignore.symbol.file -d build/java JavaRunner.java Wiz3Display.java GameArchive.java
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
"$jdk/bin/java" -cp build/java:build/archive-check ArchiveChecks
cp Java.policy "$app/Resources/"
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
printf 'Built Flashback.app for Apple Silicon and Intel.\n'
