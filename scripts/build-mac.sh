#!/bin/bash
set -euo pipefail

APP_NAME="FastNetConnect"
SCHEME="FastNetConnect"
PROJECT="FastNet.xcodeproj"
BUILD_DIR="build/mac"
DMG_NAME="FastNetConnect.dmg"

# --- Configuration ---
# Set these before running, or export as environment variables:
#   DEVELOPER_ID    - "Developer ID Application: Your Name (TEAMID)"
#   APPLE_ID        - Your Apple ID email
#   TEAM_ID         - Your Apple Developer Team ID
#   APP_PASSWORD    - App-specific password (generate at appleid.apple.com)

if [ -z "${DEVELOPER_ID:-}" ]; then
    echo "Error: Set DEVELOPER_ID environment variable"
    echo "  Example: export DEVELOPER_ID='Developer ID Application: Paul Jiang (XXXXXXXXXX)'"
    exit 1
fi

if [ -z "${APPLE_ID:-}" ] || [ -z "${TEAM_ID:-}" ] || [ -z "${APP_PASSWORD:-}" ]; then
    echo "Error: Set APPLE_ID, TEAM_ID, and APP_PASSWORD environment variables"
    echo "  APPLE_ID    = your Apple ID email"
    echo "  TEAM_ID     = your dev team ID"
    echo "  APP_PASSWORD = app-specific password from appleid.apple.com"
    exit 1
fi

echo "==> Cleaning build directory"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Building release archive"
xcodebuild -project "$PROJECT" \
    -scheme "$SCHEME" \
    -sdk macosx \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/derived" \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
    CODE_SIGN_STYLE=Manual \
    ENABLE_HARDENED_RUNTIME=YES \
    clean build

APP_PATH="$BUILD_DIR/derived/Build/Products/Release/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: Build product not found at $APP_PATH"
    exit 1
fi

echo "==> Verifying code signature"
codesign --verify --deep --strict "$APP_PATH"
codesign -d --verbose=2 "$APP_PATH"

echo "==> Creating zip for notarization"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Submitting for notarization"
xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"

echo "==> Creating DMG"
rm -f "$BUILD_DIR/$DMG_NAME"
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$APP_PATH" \
    -ov -format UDZO \
    "$BUILD_DIR/$DMG_NAME"

echo "==> Stapling DMG"
xcrun stapler staple "$BUILD_DIR/$DMG_NAME"

echo ""
echo "Done! Distribution file: $BUILD_DIR/$DMG_NAME"
echo ""
echo "Users can download and drag to /Applications."
