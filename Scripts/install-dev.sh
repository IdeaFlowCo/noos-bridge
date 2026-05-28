#!/usr/bin/env bash
#
# Fast local install of a distinct development Noos Bridge build.
#
# Installs:
#   /Applications/Noos Bridge Dev.app
#
# The dev app intentionally uses a separate bundle ID, icon, Keychain service,
# and Application Support directory from production so local testing cannot
# clobber the signed production install's permissions or credentials.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PKG_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

APP_NAME="Noos Bridge Dev"
APP_PATH="/Applications/${APP_NAME}.app"
STAGING="/Applications/${APP_NAME}-staging-$$.app"

echo "==> Building dev app"
APP_CHANNEL=dev CONFIGURATION="${CONFIGURATION:-debug}" "$SCRIPT_DIR/build-app.sh"

BUILT_APP="$PKG_DIR/build/${APP_NAME}.app"
if [ ! -d "$BUILT_APP" ]; then
  echo "ERROR: build did not produce $BUILT_APP" >&2
  exit 1
fi

echo "==> Quitting running dev app"
osascript -e "tell application \"${APP_NAME}\" to quit" 2>/dev/null || true
pkill -f "${APP_NAME}.app/Contents" 2>/dev/null || true
sleep 1

echo "==> Copying to staging"
rm -rf "$STAGING"
if ! ditto "$BUILT_APP" "$STAGING"; then
  rm -rf "$STAGING"
  echo "ERROR: staging copy failed; existing app left untouched" >&2
  exit 1
fi

echo "==> Installing $APP_PATH"
if [ -d "$APP_PATH" ]; then
  mv "$APP_PATH" "$HOME/.Trash/${APP_NAME}-prev-$(date +%s).app"
fi
mv "$STAGING" "$APP_PATH"

VER=$(defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")
BUILD=$(defaults read "$APP_PATH/Contents/Info" CFBundleVersion 2>/dev/null || echo "?")
BUNDLE=$(defaults read "$APP_PATH/Contents/Info" CFBundleIdentifier 2>/dev/null || echo "?")

echo
echo "Installed ${APP_NAME} v${VER} (${BUILD})"
echo "  $APP_PATH"
echo "  $BUNDLE"
echo
echo "Grant Full Disk Access separately for this dev app if you need iMessage tests."
