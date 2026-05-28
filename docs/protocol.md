# Bridge Protocol

The bridge opens an outbound WebSocket to a broker. Frames are JSON objects with a `type` field.

## Client To Broker

`hello`

Sent after connection.

```json
{
  "type": "hello",
  "version": 1,
  "hostname": "Jacob's Mac",
  "appVersion": "0.2.22",
  "tools": [],
  "locked": true,
  "remoteUnlockAllowed": true
}
```

`tool-result`

Response to a broker `invoke`.

```json
{
  "type": "tool-result",
  "id": "request-id",
  "ok": true,
  "result": {}
}
```

`lock-state`

Sent when the local lock changes.

```json
{
  "type": "lock-state",
  "locked": false
}
```

`remote-unlock-policy`

Sent when the user changes whether remote clients may send unlock attempts.

```json
{
  "type": "remote-unlock-policy",
  "allowed": false
}
```

## Broker To Client

`hello-ack`

Confirms the broker accepted the bridge.

`invoke`

Requests a local tool call.

```json
{
  "type": "invoke",
  "id": "request-id",
  "tool": "imessage.search",
  "args": { "query": "dinner" }
}
```

`unlock-attempt`

Relays a remote unlock password attempt. The Mac verifies it locally.

```json
{
  "type": "unlock-attempt",
  "id": "attempt-id",
  "password": "not-saved-by-broker"
}
```

The broker should reject unlock attempts itself when the latest bridge status says `remoteUnlockAllowed: false`.
