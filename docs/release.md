# Release Process

## Local Signed DMG

Build a signed app and package it as a DMG:

```bash
APP_VERSION=0.2.22 APP_BUILD=1 Scripts/package-release.sh
```

The output is written to `dist/`.

## Notarization

Use a stored notarytool profile:

```bash
NOTARYTOOL_PROFILE=ideaflow-notary \
  Scripts/notarize-release.sh dist/Noos-Bridge-0.2.22-1.dmg
```

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
spctl -a -vv "dist/Noos-Bridge-0.2.22-1.dmg"
```
