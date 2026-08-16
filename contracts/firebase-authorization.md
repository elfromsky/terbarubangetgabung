# Firebase authorization contract

This document is the authoritative description of the Firebase authorization
model that resulted from Issues #3 (sensorLogs authorization) and #5
(custom-claim provisioning), and the product/security reconciliation recorded
in Issue #18.

Authoritative sources: `firebase/firestore.rules`,
`firebase/database.rules.json`, and `apps/flutter/lib/auth/device_claim.dart`.
The product-level user model decision lives in
`docs/PRD_AUTH_MODEL_DECISION.md`.

## 1. Scope and terminology

Two authorization layers exist and must not be conflated.

- **Product / human layer** — the three household users and their product
  experience. There is no login, no household-user account system, no
  household-user RBAC, and no permission differentiation among the three
  users. See `docs/PRD_AUTH_MODEL_DECISION.md`.
- **Firebase / security-principal layer** — the identities and custom claims
  evaluated by Firebase Security Rules. These authorize trusted software and
  device principals, not human household roles.

Throughout this document the word **principal** refers to a Firebase identity
(a client installation or the Master/controller identity), never to a human
household user. The literal claim names `owner` and `controller` are preserved;
they are security authorization claims, not human roles.

## 2. Product-level household user model

- Three household users.
- Same application; no login screen; no username/password entry.
- No household-user account selection; no household-user role selection.
- No household-user roles; no owner-vs-controller distinction between humans.
- All three household users have equal monitoring rights and equal control
  rights.

How equality is achieved: each trusted Flutter installation authenticates
invisibly with Firebase Anonymous Authentication and is provisioned out-of-band
with `owner == true`, so every installation carries the same monitoring/control
capability. See section 7.

## 3. Firebase security-principal model

Two custom claims are recognized; both must be strict booleans (`=== true`):

| Claim | Security principal | Meaning |
|-------|--------------------|---------|
| `owner` | trusted Flutter client principal | can write commands, read telemetry, create/read sensor logs |
| `controller` | trusted Master/controller principal | can read/write telemetry, read sensor logs |

A principal is trusted when its ID token carries `owner == true` or
`controller == true` (`hasTrustedDeviceClaim`). Any other value — a missing
claim, `false`, or a non-boolean — fails closed.

The Flutter household application gate is stricter: it requires
`owner == true` (`hasOwnerClaim`). `controller == true` alone does not unlock
the Flutter app, because the Flutter client must write `/commands` and create
Firestore `sensorLogs`, both reserved for `owner`. `controller` remains a valid
security principal for the Master/controller device, but must not become
equivalent to full Flutter owner access.

`owner` and `controller` are **not** household-user roles, not three-user RBAC,
and not human account types. They authorize the trusted Flutter client
installations and the Master/controller device identity respectively.

## 4. Principal-to-capability mapping

```text
Household user
    ↓
Flutter app installation (Firebase anonymous identity)
    ↓
out-of-band trusted provisioning (Admin SDK / Firebase Auth console)
    ↓
owner == true
    ↓
same monitoring/control capability
```

Each of the three household users uses a trusted Flutter installation
provisioned identically, so no human is granted more rights than another:

```text
Trusted Flutter installation A -> owner == true
Trusted Flutter installation B -> owner == true
Trusted Flutter installation C -> owner == true
```

The security identity belongs to the client installation, not to a human
account. If an anonymous identity changes (app data/auth state lost or the app
reinstalled), the new UID must be provisioned again before receiving trusted
access.

## 5. Realtime Database authorization

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

## 6. Firestore authorization

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

## 7. Flutter identity and owner provisioning

- The Flutter application authenticates invisibly with Firebase Anonymous
  Authentication. The household user never interacts with this mechanism.
- A generated anonymous Firebase UID identifies the app/client installation,
  not which household human holds the phone.
- A trusted Flutter application identity is provisioned out-of-band with
  `owner == true` via the established trusted provisioning mechanism (Firebase
  Auth console / Admin SDK), per `docs/PROVISIONING.md` and
  `apps/flutter/docs/firebase-security-provisioning.md`.
- Because all trusted Flutter installations carry the same `owner == true`
  capability, the three household users obtain equal rights. This is not three
  humans each holding an "Owner role"; the claim authorizes the trusted client
  principal.

## 8. Master/controller identity

- The `controller` claim is not a household-user role.
- It represents the trusted Master/controller principal used for
  machine-to-machine access: the ESP32 Master authenticates to Firebase with a
  configured device account (`FIREBASE_USER_EMAIL` / `FIREBASE_USER_PASSWORD`
  identity) and is provisioned with `controller == true`.
- The Master/controller writes telemetry/state to RTDB and reads commands;
  it does not write Firestore `sensorLogs` (see section 6).

## 9. Fail-closed behavior

A principal that:

- has no authenticated Firebase identity;
- lacks the required claim;
- has a `false` or malformed claim;

must not gain Firebase data access. The product fails closed. The exact runtime
UX / enrollment implementation belongs to Issue #17; this contract documents
the requirement, not the implementation.

## 10. Relationship to PRD

The PRD statement "no login / no user authentication / no role / no access
differentiation" is true at the household-user level (section 2). Firebase
Authentication and the `owner` / `controller` claims are infrastructure-level
security mechanisms (sections 3-9), invisible to the user. Reconciliation:

```text
no human-facing authentication != no backend authentication
```

The PRD wording is refined (see `docs/PRD_AUTH_MODEL_DECISION.md`), not
enforced by removing security. "Future authentication" in the PRD means future
human-user account authentication / account management / household-user RBAC if
product requirements expand; it does not forbid infrastructure authentication
today.

## 11. Current implementation status

- The authoritative/target security model is described above.
- `device_claim.dart` defines pure claim evaluation (`hasTrustedDeviceClaim`,
  `hasOwnerClaim`, `revalidateTrust`) so the trust decision is unit-testable
  without a live backend.
- `apps/flutter/lib/main.dart` runs an authorization bootstrap gate
  (`AuthGateController` + `FirebaseClaims`) before constructing `EshApp`:
  anonymous sign-in, owner-claim verification, fail-closed startup, an
  enrollment state for unprovisioned identities, forced token refresh on
  `Coba lagi` and on foreground/resume, and owner-specific (not
  controller-or-owner) gating of the operational app. Historical note: the
  anonymous-auth bootstrap that previously existed (commit `369fb82`, Issue #5
  / PR #10) was removed later (commit `8b9346e`, the pre-migration `clean`
  tip), and the Issue #8 monorepo migration imported the Flutter tree without
  restoring it. Issue #17 restores the runtime bootstrap consistent with this
  contract.

> Do not change `owner`/`controller` claim semantics as part of any migration;
> the strict-boolean security-principal contract is settled.
