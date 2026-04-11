#!/bin/bash
set -euo pipefail

echo "==> Building release..."
swift build -c release

BUILD_DIR=".build/arm64-apple-macosx/release"
APP_DIR=".build/neetly.app"
DMG_NAME="neetly-macos.dmg"

echo "==> Creating .app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binaries
cp "$BUILD_DIR/neetly-app" "$APP_DIR/Contents/MacOS/neetly-app"
cp "$BUILD_DIR/neetly" "$APP_DIR/Contents/MacOS/neetly"

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>neetly-app</string>
    <key>CFBundleIdentifier</key>
    <string>com.neetly.app</string>
    <key>CFBundleName</key>
    <string>neetly</string>
    <key>CFBundleDisplayName</key>
    <string>neetly</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Creating DMG..."
rm -f "$DMG_NAME"
hdiutil create -volname "neetly" \
    -srcfolder "$APP_DIR" \
    -ov -format UDZO \
    "$DMG_NAME"

echo "==> Done: $DMG_NAME"
echo ""
echo "To create a GitHub release:"
echo "  gh release create v1.0.0 $DMG_NAME --title 'neetly v1.0.0' --notes 'Initial release'"
