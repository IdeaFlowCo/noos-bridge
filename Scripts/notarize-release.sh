#!/usr/bin/env bash
#
# Submit a Noos Bridge release artifact to Apple notarization and staple it.
#
# Usage:
#   APPLE_ID=dev@example.com \
#   APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx \
#   APPLE_TEAM_ID=JESMXK96LG \
#   mac/NoosBridge/Scripts/notarize-release.sh mac/NoosBridge/dist/Noos-Bridge-0.2.19-1.dmg
#
# Or use a stored notarytool profile:
#   NOTARYTOOL_PROFILE=ideaflow-notary \
#   mac/NoosBridge/Scripts/notarize-release.sh <artifact.dmg>

set -euo pipefail

ARTIFACT="${1:-}"
if [ -z "$ARTIFACT" ] || [ ! -f "$ARTIFACT" ]; then
  echo "Usage: $0 <artifact.dmg|artifact.zip|Noos Bridge.app>" >&2
  exit 2
fi

NOTARY_ARGS=()
if [ -n "${NOTARYTOOL_PROFILE:-}" ]; then
  NOTARY_ARGS=(--keychain-profile "$NOTARYTOOL_PROFILE")
else
  : "${APPLE_ID:?Set APPLE_ID or NOTARYTOOL_PROFILE}"
  : "${APP_SPECIFIC_PASSWORD:?Set APP_SPECIFIC_PASSWORD or NOTARYTOOL_PROFILE}"
  : "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID or NOTARYTOOL_PROFILE}"
  NOTARY_ARGS=(--apple-id "$APPLE_ID" --password "$APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID")
fi

echo "==> Submitting to Apple notarization"
xcrun notarytool submit "$ARTIFACT" "${NOTARY_ARGS[@]}" --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$ARTIFACT"

echo "==> Gatekeeper assessment"
case "$ARTIFACT" in
  *.dmg)
    spctl -a -t open --context context:primary-signature -vv "$ARTIFACT"
    ;;
  *)
    spctl -a -vv "$ARTIFACT"
    ;;
esac

echo
echo "Notarized and stapled:"
echo "  $ARTIFACT"
