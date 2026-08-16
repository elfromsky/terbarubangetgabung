# Command protocol (Flutter -> Firebase RTDB -> Master)

This document describes the exact command contract that travels from the
Flutter application, through Firebase Realtime Database (RTDB), to the ESP32
Master firmware.

> There is **no explicit protocol-version field** in the current protocol.
> Versioning, if ever introduced, must be a deliberate future decision; do not
> assume one exists now.

## Route

The command path is:

```text
/commands/rooms/<roomKey>/tools/<deviceKey>
```

`roomKey` and `deviceKey` are the room and device identifiers used throughout
the system (see the device table below).

## Payload shape

A command is a JSON object. Its allowed fields depend on whether the target
device is a **dimmer** (supports `brightness`) or a **relay/switch**
(does not).

```jsonc
// Dimmer command (4 fields)
{
  "state": true,          // bool: ON=true / OFF=false
  "brightness": 75,       // int: 0..100 (dimmer only)
  "request_id": "abc",    // string: 1..31 characters
  "issued_at": 1755400000123  // int: epoch milliseconds
}

// Relay command (3 fields — no brightness)
{
  "state": true,
  "request_id": "abc",
  "issued_at": 1755400000123
}
```

## Fields

| Field | Type | Presence | Constraints | Notes |
|-------|------|----------|-------------|-------|
| `state` | bool | required | `true` or `false` | ON/OFF |
| `brightness` | integer | dimmer only | `0..100` | absent on non-dimmable devices |
| `request_id` | string | required | `1..31` chars | opaque; Flutter uses base64url of 16 random bytes with `=` stripped (22 chars) |
| `issued_at` | integer | required | epoch **milliseconds** | command freshness timestamp |

Unknown/extra fields are rejected (`$other` rule denies, and the Master
enforces an exact field-count check).

## Device table

| Room | Device | Owner | Kind | Fields |
|------|--------|-------|------|--------|
| `teras` | `lampu` | Master | relay | state, request_id, issued_at |
| `teras` | `sanyo` | Master | relay | state, request_id, issued_at |
| `lorong` | `blower` | Slave | relay | state, request_id, issued_at |
| `lorong` | `stop_kontak` | Slave | relay | state, request_id, issued_at |
| `kamar_1` | `stop_kontak` | Slave | relay | state, request_id, issued_at |
| `kamar_2` | `stop_kontak` | Slave | relay | state, request_id, issued_at |
| `dapur` | `blower` | Slave | relay | state, request_id, issued_at |
| `kamar_1` | `lampu` | Slave | dimmer | + brightness |
| `kamar_2` | `lampu` | Slave | dimmer | + brightness |
| `dapur` | `lampu` | Slave | dimmer | + brightness |

## Timestamp generation

- Flutter computes `issued_at` as
  `DateTime.now().millisecondsSinceEpoch + round(RTDB .info/serverTimeOffset)`,
  i.e. an estimate of the Firebase server clock in epoch milliseconds.
- `request_id` is generated per command with a cryptographically secure random
  source; each command in a batch gets a distinct id (duplicate id in a batch
  is an error).

## Freshness

Two independent freshness checks apply (see `time-and-freshness.md`):

- **RTDB rules** (writing side): `issued_at >= now - 15000 && issued_at <= now + 5000`
  (milliseconds, inclusive bounds, `now` = Firebase server ms).
- **Master** (consuming side): rejects `issued_at > now + 5000` (too far in the
  future) and `issued_at <= now - 15000` (stale), i.e. accepts the open-closed
  interval `(now - 15000, now + 5000]` using Master NTP time.

## Duplicate / ordering semantics

- **Master** stores the newest accepted command per route
  (`commandVersionIsNewer`): a command is accepted only if it is newer
  (`issued_at` greater, or equal with a lexicographically larger `request_id`).
  Older or duplicate commands are ignored.
- **Slave** dedup is performed by a payload-aware duplicate cache keyed on
  `roomKey + deviceKey + requestId + state + brightness` (see
  `espnow-protocol.md` and `shared-dimmer.md`).

## Authorization

- Writing a command requires `auth.token.owner == true` (strict boolean).
- The device whitelist in the RTDB rules matches the device table above.
- `controller` alone cannot write a command.

## Failure behavior

- Invalid payloads (wrong field count, wrong types, out-of-range values,
  unknown room/device) are rejected by RTDB rules and/or silently ignored by
  the Master (with a serial log). There is no command-level error response to
  the Flutter client.
