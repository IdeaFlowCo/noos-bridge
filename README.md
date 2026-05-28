# Noos Bridge

Noos Bridge is a macOS app that lets an explicitly paired remote agent query local Mac data through an outbound WebSocket connection. It is designed for the common case where your Mac is at home or in the office and you want to ask questions from a web or mobile app without opening inbound network access to the Mac.

The official IdeaFlow build pairs with Noos by default. The bridge protocol is intentionally small enough that other trusted brokers can implement it later.

## What It Can Access

- iMessage history from the local Messages database
- Contacts, for resolving phone numbers and email addresses
- Calendar events
- Reminders

The Mac app must be granted the relevant macOS privacy permissions. iMessage search requires Full Disk Access because Apple stores Messages in a protected local database.

## Security Model

- The Mac initiates the connection. No inbound port needs to be opened.
- The Mac has the authoritative Bridge On/Off switch.
- Web and mobile clients cannot turn the bridge back on after it is disabled locally.
- Remote unlock passwords are relayed to the Mac for local verification and are not saved by the broker.
- The Mac can disable remote unlock, requiring unlock from the local app.
- Pairing credentials are stored in the macOS Keychain when available.

See [docs/security.md](docs/security.md) for details.

## Local Development

Requirements:

- macOS 13 or newer
- Xcode command line tools
- Swift 5.9 or newer

Build the Swift package:

```bash
swift build
```

Build a local app bundle:

```bash
CONFIGURATION=debug SKIP_SIGN=1 Scripts/build-app.sh
```

Install a distinct development app for day-to-day testing:

```bash
Scripts/install-dev.sh
```

This installs `/Applications/Noos Bridge Dev.app` with its own bundle ID, icon, Keychain service, and Application Support folder so dev testing does not mutate production pairing credentials or macOS privacy grants.

Build a signed release bundle if you have the IdeaFlow Developer ID certificate installed:

```bash
APP_CHANNEL=production CONFIGURATION=release Scripts/build-app.sh
```

Package a release DMG:

```bash
APP_VERSION=0.2.22 APP_BUILD=1 Scripts/package-release.sh
```

Install the latest production release from GitHub:

```bash
Scripts/install-prod.sh
```

Regenerate app icons after editing the icon source script:

```bash
Scripts/generate-icons.py
```

Production uses `Resources/AppIcon.icns`; development uses `Resources/AppIconDev.icns` with an orange `DEV` ribbon.

## Configuration

The official defaults point at Noos:

- `BRIDGE_WSS_URL`: broker WebSocket URL, default `wss://globalbr.ai/api/bridge/connect`
- `BRIDGE_AUTH_URL`: pairing URL, derived from `BRIDGE_WSS_URL` unless set
- `BRIDGE_DEVICE_TOKEN`: development-only token override
- `BRIDGE_PASSWORD`: development-only first-run bridge password setup

For production user installs, pair through the app UI instead of placing tokens in files or environment variables.

## Repository Boundary

This repository owns the Mac app, local tools, bridge protocol client, and release scripts.

The Noos web app, account system, broker API, mobile UI, and remote agent orchestration live outside this repository.

## License

Apache-2.0. See [LICENSE](LICENSE).
