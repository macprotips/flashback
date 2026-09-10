#!/bin/sh
set -eu
cd "$(dirname "$0")"
app='TextTwist 2.app/Contents'
mkdir -p "$app/MacOS" "$app/Resources/game" "$app/Frameworks"
cp -R vendor/Ruffle.app "$app/Frameworks/"
cp -R assets/root "$app/Resources/game/"
cp vendor/LICENSE.md "$app/Resources/Ruffle-LICENSE.md"
clang -Os -arch arm64 -arch x86_64 -framework CoreFoundation launcher.c -o "$app/MacOS/TextTwist2"
cat > "$app/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>TextTwist 2</string>
<key>CFBundleDisplayName</key><string>TextTwist 2</string>
<key>CFBundleIdentifier</key><string>local.texttwist2.mac</string>
<key>CFBundleExecutable</key><string>TextTwist2</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>11.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
codesign --force --deep --sign - --preserve-metadata=entitlements,identifier,runtime "$app/Frameworks/Ruffle.app"
codesign --force --sign - 'TextTwist 2.app'
codesign --verify --deep --strict 'TextTwist 2.app'
python3 verify.py
