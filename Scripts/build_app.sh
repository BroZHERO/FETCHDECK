#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "=== Building FETCHDECK for Apple Silicon (Release) ==="
swift build --build-system native --disable-sandbox -c release

BIN_PATH="$DIR/.build/arm64-apple-macosx/release/MacDownloader"
if [ ! -f "$BIN_PATH" ]; then
    BIN_PATH="$DIR/.build/release/MacDownloader"
fi

BUNDLE_PATH="$DIR/.build/arm64-apple-macosx/release/MacDownloader_MacDownloader.bundle"
if [ ! -d "$BUNDLE_PATH" ]; then
    BUNDLE_PATH="$DIR/.build/release/MacDownloader_MacDownloader.bundle"
fi

APP_DIR="$DIR/FetchDeck.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "=== Assembling FetchDeck.app ==="
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

# Copy binary
cp "$BIN_PATH" "$MACOS/FetchDeck"
chmod +x "$MACOS/FetchDeck"

# Copy App Icon
if [ -f "$DIR/AppIcon.icns" ]; then
    cp "$DIR/AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi

# Copy SPM Resource Bundle if present
if [ -d "$BUNDLE_PATH" ]; then
    cp -R "$BUNDLE_PATH" "$RESOURCES/"
fi

# Copy Embedded Binaries (yt-dlp, ffmpeg, node)
if [ -d "$DIR/bin" ]; then
    echo "=== Bundling Universal Helper Engines ==="
    mkdir -p "$RESOURCES/bin"
    cp -R "$DIR/bin/"* "$RESOURCES/bin/" 2>/dev/null || true
    chmod +x "$RESOURCES/bin/"* 2>/dev/null || true
fi

# Create Info.plist with modern Sequoia settings & AppIcon
cat << 'EOF' > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FetchDeck</string>
    <key>CFBundleIdentifier</key>
    <string>com.brozhero.fetchdeck</string>
    <key>CFBundleName</key>
    <string>FETCHDECK</string>
    <key>CFBundleDisplayName</key>
    <string>FETCHDECK</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>2026.10.30</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.brozhero.fetchdeck</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>fetchdeck</string>
                <string>macdownloader</string>
            </array>
        </dict>
    </array>
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
    echo "=== Code Signing FetchDeck.app (Ad-hoc) ==="
    codesign --force --deep --sign - "$APP_DIR"
fi

# Also deploy to ~/Applications for easy user launch
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/FetchDeck.app"
cp -R "$APP_DIR" "$HOME/Applications/FetchDeck.app"

echo "=== Done! FetchDeck.app is assembled at: ==="
echo "1. Workspace: $APP_DIR"
echo "2. User Applications: $HOME/Applications/FetchDeck.app"
