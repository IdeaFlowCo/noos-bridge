# Agent Notes

This repository contains only the standalone macOS bridge app.

Use these checks before committing code changes:

```bash
swift build
CONFIGURATION=debug SKIP_SIGN=1 Scripts/build-app.sh
```

Do not commit local credentials, device tokens, bridge password verifiers, signing identities, notarization credentials, generated `.app` bundles, or generated DMGs.

The Noos web app, broker API, account system, and remote agent orchestration live in the main Noos repository, not here.

## IdeaFlow Release Credentials On Jacob's M5

The local M5 has the IdeaFlow Developer ID signing identity installed:

- `Developer ID Application: IdeaFlow, Inc. (JESMXK96LG)`

Use `SIGN_IDENTITY="Developer ID Application: IdeaFlow, Inc. (JESMXK96LG)"` for outside-the-App-Store Bridge releases. The `Apple Distribution` and `3rd Party Mac Developer Installer` identities are for App Store / MAS flows and are not the default Bridge DMG path.

Apple notarization is available through the local Keychain profile:

```bash
NOTARYTOOL_PROFILE=ideaflow-notary
```

The profile was created from App Store Connect API key material stored locally under `~/.appstoreconnect/`. Do not print, copy, or commit the `.p8` key contents. To verify the profile without exposing secrets:

```bash
xcrun notarytool history --keychain-profile ideaflow-notary
```
