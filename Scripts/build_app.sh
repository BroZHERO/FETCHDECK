#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "=== Building MacDownloader for Apple Silicon (arm64) ==="
swift build --build-system native --disable-sandbox -c release

BIN_PATH="$DIR/.build/arm64-apple-macosx/release/MacDownloader"
if [ ! -f "$BIN_PATH" ]; then
    BIN_PATH="$DIR/.build/release/MacDownloader"
fi

APP_DIR="$DIR/MacDownloader.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "=== Packaging MacDownloader.app ==="
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN_PATH" "$MACOS/MacDownloader"
chmod +x "$MACOS/MacDownloader"

cat << 'EOF' > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MacDownloader</string>
    <key>CFBundleIdentifier</key>
    <string>com.antigravity.MacDownloader</string>
    <key>CFBundleName</key>
    <string>MacDownloader</string>
    <key>CFBundleDisplayName</key>
    <string>MacDownloader</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

# Ad-hoc code signing for Apple Silicon
if which codesign > /dev/null; then
    echo "=== Signing Application (Ad-hoc) ==="
    codesign --force --deep --sign - "$APP_DIR"
fi

echo "=== Done! MacDownloader.app is ready at: $APP_DIR ==="
