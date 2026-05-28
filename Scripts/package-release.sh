#!/usr/bin/env bash
#
# Build, sign, and package Noos Bridge.app for external distribution.
#
# Output:
#   mac/NoosBridge/dist/Noos-Bridge-${APP_VERSION}-${APP_BUILD}.dmg
#
# Required for signed release:
#   SIGN_IDENTITY="Developer ID Application: IdeaFlow, Inc. (JESMXK96LG)"
#
# Optional:
#   APP_VERSION=0.2.22
#   APP_BUILD=1
#   SKIP_SIGN=1          # local unsigned package only

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PKG_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

APP_VERSION="${APP_VERSION:-0.2.22}"
APP_BUILD="${APP_BUILD:-1}"
APP_NAME="Noos Bridge"
DMG_BASENAME="Noos-Bridge-${APP_VERSION}-${APP_BUILD}"
DIST_DIR="$PKG_DIR/dist"
STAGING_DIR="$DIST_DIR/staging"
APP_BUNDLE="$PKG_DIR/build/${APP_NAME}.app"
DMG_PATH="$DIST_DIR/${DMG_BASENAME}.dmg"
TMP_DMG_PATH="$DIST_DIR/${DMG_BASENAME}.tmp.dmg"

mkdir -p "$DIST_DIR"
rm -rf "$STAGING_DIR" "$TMP_DMG_PATH" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

echo "==> Building ${APP_NAME} ${APP_VERSION} (${APP_BUILD})"
CONFIGURATION=release APP_VERSION="$APP_VERSION" APP_BUILD="$APP_BUILD" "$SCRIPT_DIR/build-app.sh"

echo "==> Staging app"
ditto "$APP_BUNDLE" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDRW \
  "$TMP_DMG_PATH" >/dev/null

hdiutil convert "$TMP_DMG_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
rm -f "$TMP_DMG_PATH"
rm -rf "$STAGING_DIR"

echo "==> Verifying code signature"
if [ "${SKIP_SIGN:-0}" = "1" ]; then
  echo "SKIP_SIGN=1, skipping codesign verification"
else
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
fi

echo
echo "Built release artifact:"
echo "  $DMG_PATH"
echo
echo "Next:"
echo "  APPLE_ID=... APP_SPECIFIC_PASSWORD=... APPLE_TEAM_ID=... \\"
echo "    $SCRIPT_DIR/notarize-release.sh '$DMG_PATH'"
