# Release Process

## Local Signed DMG

Build a signed app and package it as a DMG:

```bash
APP_VERSION=0.2.22 APP_BUILD=1 Scripts/package-release.sh
```

The output is written to `dist/`.

## Notarization

On Jacob's M5, use the stored IdeaFlow notarytool profile:

```bash
NOTARYTOOL_PROFILE=ideaflow-notary \
  Scripts/notarize-release.sh dist/Noos-Bridge-0.2.22-1.dmg
```

That profile lives in the local Keychain and validates against IdeaFlow's App Store Connect API key material under `~/.appstoreconnect/`. Do not print or commit the `.p8` private key contents.

Or pass Apple credentials through environment variables:

```bash
APPLE_ID=dev@example.com \
APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx \
APPLE_TEAM_ID=JESMXK96LG \
  Scripts/notarize-release.sh dist/Noos-Bridge-0.2.22-1.dmg
```

Do not commit notarization credentials or signing certificates.

## Verification

After packaging:

```bash
codesign --verify --deep --strict --verbose=2 "build/Noos Bridge.app"
spctl -a -t open --context context:primary-signature -vv "dist/Noos-Bridge-0.2.22-1.dmg"
stapler validate "dist/Noos-Bridge-0.2.22-1.dmg"
```

A successful notarized DMG assessment should report `accepted` with source `Notarized Developer ID`.
