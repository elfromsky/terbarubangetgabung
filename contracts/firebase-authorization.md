# Firebase authorization contract

This document describes the final Firebase authorization model that resulted
from Issues #3 (sensorLogs authorization) and #5 (custom-claim provisioning).

Authoritative source: `firebase/firestore.rules`, `firebase/database.rules.json`,
and `apps/flutter/lib/auth/device_claim.dart`.

## Roles

Two custom claims are recognized; both must be strict booleans (`=== true`):

| Claim | Meaning |
|-------|---------|
| `owner` | trusted owner role; can write commands, read telemetry, create/read sensor logs |
| `controller` | trusted controller role; can read/write telemetry, read sensor logs |

A device is trusted when its ID token carries `owner == true` or
`controller == true` (`hasTrustedDeviceClaim`). Any other value — a missing
claim, `false`, or a non-boolean — fails closed.

## Realtime Database (RTDB) authorization

| Path | Read | Write |
|------|------|-------|
| `device` | owner OR controller | controller |
| `rooms` | owner OR controller | controller |
| `gateway` | owner OR controller | controller |
| `commands` | controller | *(see command write below)* |

Command write (`/commands/rooms/$room/tools/$device`):

- requires `owner == true`;
- enforces the room/device whitelist (the 10 devices in
  `command-protocol.md`);
- validates `state` (bool), `brightness` (int 0..100), `request_id` (string
  1..31), `issued_at` (number within freshness window);
- denies unknown fields.

## Firestore authorization

`/sensorLogs`:

| Operation | Rule |
|-----------|------|
| read (get/list/query) | `isOwner() || isController()` |
| create | `isOwner()` AND schema validation |
| update | denied (`false`) |
| delete | denied (`false`) |

`sensorLogs` create schema:

- allowed keys: `timestamp`, `power`, `environment`, `derived` (and nothing
  else);
- required keys: `timestamp`, `power`, `environment`;
- `timestamp` must be a Firestore timestamp;
- `power` and `environment` must be maps;
- `derived`, when present, must be a map.

All other Firestore documents are denied (`allow read, write: if false`).

## Sensor log writer ownership

The only writer of `sensorLogs` in the codebase is the Flutter application,
running with an `owner` claim (`SaveSensorLogUseCase` -> `FirebaseHistoryDataSource`).
No firmware component writes Firestore directly.

## Provisioning / token refresh flow

- Bootstrap: `apps/flutter/lib/main.dart` initializes Firebase and renders the
  app; there is **no** client-side auth gate in `main.dart` (the old gate was
  deliberately removed in Issue #5).
- `device_claim.dart` defines pure claim evaluation (`hasTrustedDeviceClaim`,
  `revalidateTrust`) so the trust decision is unit-testable without a live
  backend.
- `revalidateTrust` returns `null` on transient claim-load failure, meaning
  "keep current state" so a momentary network failure never bounces an
  already-trusted device.
- Custom claims are assigned out-of-band in the Firebase Auth console /
  Admin SDK; see `docs/PROVISIONING.md`.

> Do not change owner/controller role semantics as part of a migration; these
> roles are a settled contract.
