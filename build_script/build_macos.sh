#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

APP_NAME="joycai_image_ai_toolkits"
DISPLAY_NAME="Joycai Image AI Toolkits"
DMG_NAME="Joycai-Image-Ai-Toolkits-Installer"
BUILD_DIR="build/macos/Build/Products/Release"
STAGING_DIR="build/macos/dmg_staging"
OUTPUT_DIR="build/dist"

echo "🚀 Starting macOS Build & Package Script..."

# 1. Build the Flutter App
echo "🔨 Building macOS release..."
# Go to project root (assuming script is in build_script/)
cd "$(dirname "$0")/.."
flutter clean
flutter pub get
flutter gen-l10n
flutter build macos --release

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
open "$OUTPUT_DIR"
