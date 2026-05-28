# Security Model

Noos Bridge is built around local Mac control. A remote service can ask for data only after the Mac has been explicitly paired and the local bridge is on.

## Local Authority

The Bridge On/Off control in the Mac app is authoritative. When it is off, the bridge closes the broker connection and refuses remote access. A web or mobile app must not be able to turn it back on.

## Pairing

Production pairing should use a broker-issued credential stored in the macOS Keychain. Development builds may use `BRIDGE_DEVICE_TOKEN` or `~/Library/Application Support/Noos Bridge/device-token.txt`, but those paths are for local testing only.

Never commit device tokens, bridge password verifiers, signing certificates, notary credentials, or generated release artifacts.

## Lock And Remote Unlock

The bridge can be locked even while it remains connected. When locked, remote tools cannot run until the Mac unlocks them.

By default, a web or mobile client may send a bridge password to the Mac. The broker relays the password attempt and does not save it. The Mac verifies the password locally.

Users can disable remote unlock in the Mac app. In that mode, the only way to unlock the bridge is from the Mac app itself.

## macOS Permissions

The app needs the specific macOS privacy permissions for the sources a user enables. iMessage search requires Full Disk Access because Messages data is stored in a protected SQLite database under the user's Library folder.

The app should clearly show permission status and avoid silently degrading when permissions are missing.

## Broker Trust

The bridge should show which broker/account it is paired with. Future non-Noos brokers should require explicit local pairing and should not be allowed to connect silently.
