#!/usr/bin/env bash
#
# Install the latest production Noos Bridge release from GitHub.
#
# Usage:
#   Scripts/install-prod.sh              # latest release
#   Scripts/install-prod.sh v0.2.22      # specific tag

set -euo pipefail

REPO="${REPO:-IdeaFlowCo/noos-bridge}"
VERSION="${1:-}"
APP_NAME="Noos Bridge"
APP_PATH="/Applications/${APP_NAME}.app"

if [ -z "$VERSION" ]; then
  VERSION=$(gh release list --repo "$REPO" --limit 20 \
    | awk '$0 !~ /Pre-release/ && $0 ~ /Latest/ {print $3; exit}')
  if [ -z "$VERSION" ]; then
    VERSION=$(gh release list --repo "$REPO" --limit 1 | awk '{print $3; exit}')
  fi
fi

if [ -z "$VERSION" ]; then
  echo "ERROR: could not determine latest release. Pass a tag, e.g. v0.2.22." >&2
  exit 1
fi

TMPDIR=$(mktemp -d)
cleanup() {
  if [ -n "${MOUNT:-}" ] && [ -d "$MOUNT" ]; then
    hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
  fi
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

echo "==> Downloading $REPO $VERSION"
gh release download "$VERSION" --repo "$REPO" --pattern "*.dmg" -D "$TMPDIR"

DMG=$(find "$TMPDIR" -maxdepth 1 -name "*.dmg" -print | head -1)
if [ -z "$DMG" ]; then
  echo "ERROR: release $VERSION did not contain a DMG" >&2
  exit 1
fi

echo "==> Verifying Gatekeeper signature"
spctl -a -t open --context context:primary-signature -vv "$DMG"

echo "==> Mounting $DMG"
hdiutil attach "$DMG" -nobrowse -quiet
MOUNT=$(find /Volumes -maxdepth 1 -type d -name "Noos Bridge*" -print | head -1)
if [ -z "$MOUNT" ] || [ ! -d "$MOUNT/${APP_NAME}.app" ]; then
  echo "ERROR: could not find ${APP_NAME}.app in mounted DMG" >&2
  exit 1
fi

echo "==> Quitting running production app"
osascript -e "tell application \"${APP_NAME}\" to quit" 2>/dev/null || true
pkill -f "${APP_NAME}.app/Contents" 2>/dev/null || true
sleep 1

STAGING="/Applications/${APP_NAME}-staging-$$.app"
echo "==> Copying to staging"
rm -rf "$STAGING"
if ! ditto "$MOUNT/${APP_NAME}.app" "$STAGING"; then
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
echo "Installed ${APP_NAME} v${VER} (${BUILD}) from $VERSION"
echo "  $APP_PATH"
echo "  $BUNDLE"
