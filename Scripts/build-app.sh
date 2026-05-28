#!/usr/bin/env bash
#
# Wrap the SwiftPM-built NoosBridge executable into a signed .app bundle.
#
# Output:
#   dev:        build/Noos Bridge Dev.app
#   production: build/Noos Bridge.app
#
# Env vars (with sensible defaults for IdeaFlow / Mac Mini):
#   SIGN_IDENTITY      — codesigning identity (default: IdeaFlow Developer ID)
#   APP_CHANNEL        — dev | production (default: dev)
#   BUNDLE_ID          — CFBundleIdentifier (default follows channel)
#   APP_NAME           — CFBundleDisplayName / .app name (default follows channel)
#   APP_VERSION        — CFBundleShortVersionString (default: 0.2.22)
#   APP_BUILD          — CFBundleVersion             (default: 1)
#   CONFIGURATION      — release | debug             (default: debug for fast iteration)
#   SKIP_SIGN          — set to 1 to skip codesign (for ad-hoc dev runs)
#
# After this script: drag the .app to /Applications, launch via NoMachine.

set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PKG_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

APP_VERSION="${APP_VERSION:-0.2.22}"
APP_BUILD="${APP_BUILD:-1}"
CONFIGURATION="${CONFIGURATION:-debug}"
APP_CHANNEL="${APP_CHANNEL:-dev}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: IdeaFlow, Inc. (JESMXK96LG)}"
case "$APP_CHANNEL" in
  production|prod|release)
    APP_CHANNEL="production"
    DEFAULT_APP_NAME="Noos Bridge"
    DEFAULT_BUNDLE_ID="com.ideaflow.noos-bridge"
    DEFAULT_ICON_NAME="AppIcon"
    ;;
  dev|development)
    APP_CHANNEL="dev"
    DEFAULT_APP_NAME="Noos Bridge Dev"
    DEFAULT_BUNDLE_ID="com.ideaflow.noos-bridge.dev"
    DEFAULT_ICON_NAME="AppIconDev"
    ;;
  *)
    echo "ERROR: APP_CHANNEL must be dev or production (got '$APP_CHANNEL')" >&2
    exit 2
    ;;
esac
APP_NAME="${APP_NAME:-$DEFAULT_APP_NAME}"
BUNDLE_ID="${BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"
ICON_NAME="${ICON_NAME:-$DEFAULT_ICON_NAME}"
EXE_NAME="NoosBridge"
GIT_COMMIT="$(git -C "$PKG_DIR" rev-parse --short HEAD 2>/dev/null || echo local)"
BUILD_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

cd "$PKG_DIR"

echo "→ swift build (-c $CONFIGURATION)"
swift build -c "$CONFIGURATION"

BUILD_BIN="$PKG_DIR/.build/$([ "$CONFIGURATION" = "debug" ] && echo debug || echo release)/$EXE_NAME"
[ -x "$BUILD_BIN" ] || { echo "ERROR: build output missing at $BUILD_BIN"; exit 1; }

OUT_DIR="$PKG_DIR/build"
APP_BUNDLE="$OUT_DIR/$APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "→ assemble bundle at $APP_BUNDLE"
cp "$BUILD_BIN" "$APP_BUNDLE/Contents/MacOS/$EXE_NAME"

ICON_SRC="$PKG_DIR/Resources/${ICON_NAME}.icns"
if [ ! -f "$ICON_SRC" ]; then
  echo "ERROR: icon missing at $ICON_SRC. Run Scripts/generate-icons.py." >&2
  exit 1
fi
cp "$ICON_SRC" "$APP_BUNDLE/Contents/Resources/${ICON_NAME}.icns"

# Sparkle is a SwiftPM binary dependency — its xcframework lives under
# .build/artifacts/. Copy the macOS slice into Contents/Frameworks/ and
# teach the main binary's rpath to look there. Without this, dyld bails at
# launch with: Library not loaded: @rpath/Sparkle.framework/...
SPARKLE_SRC="$PKG_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE_SRC" ]; then
  echo "→ bundle Sparkle.framework"
  mkdir -p "$APP_BUNDLE/Contents/Frameworks"
  ditto "$SPARKLE_SRC" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
  install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$APP_BUNDLE/Contents/MacOS/$EXE_NAME" 2>/dev/null || true
else
  echo "WARNING: Sparkle.framework not found at $SPARKLE_SRC — did 'swift build' run?"
fi

# Info.plist — menubar-only app, no main window, custom URL scheme for OAuth.
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>                <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>         <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>          <string>$EXE_NAME</string>
  <key>CFBundleIdentifier</key>          <string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key>         <string>APPL</string>
  <key>CFBundleShortVersionString</key>  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>             <string>$APP_BUILD</string>
  <key>CFBundleIconFile</key>            <string>$ICON_NAME</string>
  <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
  <key>LSMinimumSystemVersion</key>      <string>13.0</string>
  <key>LSApplicationCategoryType</key>   <string>public.app-category.productivity</string>
  <key>BridgeBuildChannel</key>          <string>$APP_CHANNEL</string>
  <key>BridgeGitCommit</key>             <string>$GIT_COMMIT</string>
  <key>BridgeBuildDate</key>             <string>$BUILD_DATE</string>

  <!-- LSMultipleInstancesProhibited prevents accidental double-launch -->
  <key>LSMultipleInstancesProhibited</key> <true/>

  <!-- We deliberately do NOT set LSUIElement. With LSUIElement=true, Launch
       Services treats the bundle as an "agent" — even setActivationPolicy(.regular)
       at runtime can't fully restore normal activation event delivery, so
       applicationDidBecomeActive only fires once on cold launch and Cmd+Tab
       activations are silent. We want a regular app (Dock + Cmd+Tab) plus
       a menubar icon, so leave LSUIElement unset. -->

  <!-- Custom URL scheme for OAuth callback. The Mac app opens the user's
       browser at noos.app/bridge/auth and that page redirects back to
       noos-bridge://auth-callback?token=… -->
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>         <string>$BUNDLE_ID.auth</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>noos-bridge</string>
      </array>
    </dict>
  </array>

  <key>NSHumanReadableCopyright</key>    <string>© IdeaFlow, Inc.</string>

  <!-- Permission usage strings — required by TCC even for outside-sandbox apps -->
  <key>NSContactsUsageDescription</key>
    <string>Noos Bridge resolves phone numbers and emails in your iMessage and Calendar history to the people they belong to.</string>
  <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Noos Bridge lets approved remote agents search your calendar events when you ask questions about your schedule.</string>
  <key>NSRemindersFullAccessUsageDescription</key>
    <string>Noos Bridge lets approved remote agents search your reminders when you ask questions about your tasks.</string>
  <key>NSAppleEventsUsageDescription</key>
    <string>Noos Bridge uses AppleScript to send iMessages on your behalf when you explicitly ask an approved remote agent to.</string>
</dict>
</plist>
PLIST
echo "→ Info.plist written ($(wc -c < "$APP_BUNDLE/Contents/Info.plist") bytes)"

# Code-sign with the IdeaFlow Developer ID cert (--options runtime is required
# by notarytool; we always set it so debug builds match release behavior).
if [ "${SKIP_SIGN:-0}" = "1" ]; then
  echo "→ SKIP_SIGN=1, ad-hoc signing local bundle"
  # install_name_tool mutates the SwiftPM-built executable after compilation.
  # On modern macOS, leaving the stale SwiftPM signature in place causes
  # LaunchServices to kill the app at dyld load time with Code Signature Invalid.
  if [ -d "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework" ]; then
    codesign --force --deep --sign - "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
  fi
  codesign --force --sign - "$APP_BUNDLE/Contents/MacOS/$EXE_NAME"
  codesign --force --deep --sign - "$APP_BUNDLE"
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" 2>&1 | tail -5
else
  echo "→ codesign with: $SIGN_IDENTITY"
  # Sparkle's helpers must be re-signed with our Team ID so dyld's library-
  # validation under hardened runtime accepts them at load time. Order
  # matters: innermost helpers first, then framework, then main bundle.
  SPARKLE_BUNDLE="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
  if [ -d "$SPARKLE_BUNDLE" ]; then
    for path in \
      "$SPARKLE_BUNDLE/Versions/B/XPCServices/Downloader.xpc" \
      "$SPARKLE_BUNDLE/Versions/B/XPCServices/Installer.xpc" \
      "$SPARKLE_BUNDLE/Versions/B/Updater.app" \
      "$SPARKLE_BUNDLE/Versions/B/Autoupdate" \
      "$SPARKLE_BUNDLE"; do
      codesign --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" "$path"
    done
  fi
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$APP_BUNDLE/Contents/MacOS/$EXE_NAME"
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$APP_BUNDLE"
  echo "→ verify signature"
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" 2>&1 | tail -5
fi

echo
echo "✓ Built: $APP_BUNDLE"
echo "  size:  $(du -sh "$APP_BUNDLE" | cut -f1)"
echo
echo "Next steps:"
echo "  1. cp -R '$APP_BUNDLE' /Applications/"
echo "  2. Launch from Applications via NoMachine (menubar apps need a GUI session)"
echo "  3. Grant Full Disk Access in System Settings → Privacy & Security"
echo
