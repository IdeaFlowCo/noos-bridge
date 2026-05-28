# Agent Notes

This repository contains only the standalone macOS bridge app.

Use these checks before committing code changes:

```bash
swift build
CONFIGURATION=debug SKIP_SIGN=1 Scripts/build-app.sh
```

Do not commit local credentials, device tokens, bridge password verifiers, signing identities, notarization credentials, generated `.app` bundles, or generated DMGs.

The Noos web app, broker API, account system, and remote agent orchestration live in the main Noos repository, not here.
