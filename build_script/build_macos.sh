#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -euo pipefail

APP_NAME="Joycai Image AI Toolkits"
DISPLAY_NAME="Joycai Image AI Toolkits"
DMG_NAME="Joycai-Image-Ai-Toolkits-Direct-Installer"
BUILD_DIR="build/macos/Build/Products/Release"
STAGING_DIR="build/macos/dmg_staging"
OUTPUT_DIR="build/dist"

# This script produces direct-download DMGs only. MAS builds use the default
# Xcode configuration and a separate future Archive/export workflow.
if [[ "${1:-}" != "--distribution" || "${2:-}" != "direct" || "$#" != 2 ]]; then
    echo "Usage: $0 --distribution direct" >&2
    exit 2
fi

echo "🚀 Building direct-download macOS package (not Mac App Store)..."

# 1. Build the Flutter App
echo "🔨 Building macOS release..."
# Go to project root (assuming script is in build_script/)
cd "$(dirname "$0")/.."
# Clean only macOS products; preserve unrelated local fixtures under build/.
rm -rf build/macos
flutter pub get
dart tool/merge_l10n.dart
flutter gen-l10n
XCODE_XCCONFIG_FILE="$PWD/build_script/macos_direct.xcconfig" \
    flutter build macos --release --dart-define=JOYCAI_DIRECT_DISTRIBUTION=true

# Fail closed before packaging if native signing differs from the Dart mode.
python3 build_script/verify_macos_direct.py "$BUILD_DIR/$APP_NAME.app"

# Check if build was successful
if [ ! -d "$BUILD_DIR/$APP_NAME.app" ]; then
    echo "❌ Build failed! Could not find $APP_NAME.app in $BUILD_DIR"
    exit 1
fi

echo "✅ Build successful."

# 2. Prepare Staging Directory for DMG
echo "📦 Preparing DMG staging area..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
mkdir -p "$OUTPUT_DIR"

# Copy the App to staging
cp -R "$BUILD_DIR/$APP_NAME.app" "$STAGING_DIR/$DISPLAY_NAME.app"

# Create Applications Symlink
ln -s /Applications "$STAGING_DIR/Applications"

# 3. Create DMG using hdiutil
echo "💿 Creating DMG..."
DMG_PATH="$OUTPUT_DIR/${DMG_NAME}.dmg"

# Remove existing DMG if it exists
if [ -f "$DMG_PATH" ]; then
    rm "$DMG_PATH"
fi

hdiutil create -volname "$DISPLAY_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

echo "🧹 Cleaning up..."
rm -rf "$STAGING_DIR"

echo "🎉 Success! DMG created at: $DMG_PATH"
# open "$OUTPUT_DIR"
