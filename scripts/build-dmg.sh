#!/bin/bash
set -euo pipefail

VERSION="${1:-1.0.0}"

echo "==> Building release..."
swift build -c release

BUILD_DIR=".build/arm64-apple-macosx/release"
APP_DIR=".build/neetly.app"
DMG_NAME="neetly-macos.dmg"
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
SPARKLE_FRAMEWORK=$(find .build -name "Sparkle.framework" -type d 2>/dev/null | head -1)

echo "==> Creating .app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$FRAMEWORKS_DIR"

# Copy binaries
cp "$BUILD_DIR/neetly-app" "$APP_DIR/Contents/MacOS/neetly-app"
cp "$BUILD_DIR/neetly" "$APP_DIR/Contents/MacOS/neetly"

# Copy Sparkle framework if found
if [ -n "$SPARKLE_FRAMEWORK" ] && [ -d "$SPARKLE_FRAMEWORK" ]; then
    echo "==> Copying Sparkle.framework from $SPARKLE_FRAMEWORK"
    cp -R "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/"

    # SPM doesn't add the @loader_path/../Frameworks rpath automatically.
    # The executable links @rpath/Sparkle.framework/... so we need to tell dyld
    # to look in Contents/Frameworks/ relative to the executable.
    echo "==> Adding @loader_path/../Frameworks rpath to executable"
    install_name_tool -add_rpath "@loader_path/../Frameworks" "$APP_DIR/Contents/MacOS/neetly-app" 2>&1 || true
else
    echo "==> WARNING: Sparkle.framework not found"
fi

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
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
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>SUFeedURL</key>
    <string>https://github.com/neetozone/neetly/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>L0ljaNTkCDOrcaLiMg8NIPHt+XLj5dr+Fp4dZ9AmsR8=</string>
    <key>SUEnableAutomaticChecks</key>
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
