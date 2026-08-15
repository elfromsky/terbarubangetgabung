# Firebase Security Provisioning

ESH uses two explicitly scoped Firebase custom claims (`owner`, `controller`).
This document is the operator contract for assigning, changing, removing, and
propagating those claims. It does **not** contain credentials; all values are
placeholders and all secrets stay outside the repository.

## Role contract

| Claim | Grant | Assigned to |
| ----- | ----- | ----------- |
| `owner: true` | Read telemetry/state, **write commands** (`/commands`), read Firestore history, **create Firestore `sensorLogs`** | Each approved Flutter application installation |
| `controller: true` | **Write** telemetry/state (`/device`, `/rooms`, `/gateway`), read commands, read Firestore history | The ESP32 Master Firebase Authentication user |

The Flutter bootstrap gate (`hasTrustedDeviceClaim`) trusts an identity that
holds **either** `owner: true` **or** `controller: true`. Both are valid at the
same time, and a single identity may hold both, but the intended model is one
role per identity:

- Flutter device → `owner` (so it may write `/commands`).
- ESP32 Master → `controller` (so it may write reported state and telemetry).

A missing claim, a `false` value, or any non-boolean value is **rejected**
(authorization fails closed).

> Note: the Flutter application is the authoritative writer of Firestore
> `sensorLogs`, and `firestore.rules` permits `create` for `owner`. The ESP32
> Master/`controller` is a different trusted role that does **not** write
> Firestore `sensorLogs` (it only writes RTDB telemetry/state); it retains
> read access to Firestore history.

## Prerequisites

1. Enable `Anonymous` under Firebase Console > Authentication > Sign-in method.
2. Rotate the firmware Firebase password and Wi-Fi password that previously
   existed in Git history (tracked separately as a security task).
3. Keep Admin SDK credentials outside this repository.

Firebase **Console** does not provide a UI for editing custom claims. Custom
claims must be assigned through the Firebase Admin SDK (or the Identity Toolkit
REST API). The procedures below use the Admin SDK only.

## Enroll Flutter owners

For each approved phone:

1. Install and open the APK. The `Perangkat belum terdaftar` screen shows the
   device's anonymous UID under `ID perangkat:`.
2. Copy `<USER_UID>` from that screen.
3. Assign `owner: true` from a trusted Admin SDK environment (see script below).
4. Return to the app. The claim is re-read automatically when the app resumes,
   or tap `Coba lagi` to force an immediate refresh.

Reinstalling the app creates a new anonymous UID and requires enrollment again.

## Enroll controller

Set `controller: true` on the Firebase Authentication user configured in the
ESP32 Master local configuration (the `FIREBASE_USER_EMAIL` /
`FIREBASE_USER_PASSWORD` identity). Restart the firmware after changing claims
so it obtains a new ID token.

## Assigning claims (Admin SDK)

Run from a trusted environment; never commit the service account key.

```bash
set GOOGLE_APPLICATION_CREDENTIALS=<SERVICE_ACCOUNT_PATH>
```

```js
const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

// setClaim preserves any unrelated custom claims already present on the user,
// then sets or overwrites a single role claim.
async function setClaim(uid, claim, value) {
  const user = await admin.auth().getUser(uid);
  await admin.auth().setCustomUserClaims(uid, {
    ...(user.customClaims ?? {}),
    [claim]: value,
  });
}

async function main() {
  // Flutter owners
  await setClaim(process.env.ESH_OWNER_UID, 'owner', true);

  // ESP32 controller
  const controller = await admin.auth().getUserByEmail(
    process.env.ESH_CONTROLLER_EMAIL,
  );
  await setClaim(controller.uid, 'controller', true);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
```

`setCustomUserClaims` **replaces** the *entire* custom-claims object for the
user. Always spread the existing `customClaims` before applying a change, or you
will silently erase unrelated claims on that user.

## Changing or removing a claim

- **Add** a claim: `setClaim(uid, 'owner', true)`.
- **Switch role** (for example owner → controller):
  `setClaim(uid, 'owner', false); setClaim(uid, 'controller', true);`
- **Revoke / remove** a claim: set it to `false`, or drop it by rebuilding the
  object without that key (while preserving the rest):

  ```js
  // Remove the owner claim while preserving every other claim.
  const { owner, ...rest } = user.customClaims ?? {};
  await admin.auth().setCustomUserClaims(uid, rest);
  ```

Never pass only `{ owner: true }` to `setCustomUserClaims` if the user holds
other claims you intend to keep.

## Token propagation

Changing server-side custom claims does **not** rewrite a token that has already
been issued to a client. Propagation is:

```text
administrator changes claim
        ↓
client still holds the previously issued token (up to ~1 hour, cached)
        ↓
client refreshes / requests a fresh ID token
        ↓
new token contains the updated claims
        ↓
application re-evaluates authorization
```

In this application the refresh happens in one of two ways:

- **Automatic**: when the app returns to the foreground (`AppLifecycleState
  resumed`), it requests a fresh ID token (`getIdTokenResult(forceRefresh:
  true)`) and re-evaluates the claims. A newly-granted claim becomes effective
  on the next resume, and a newly-revoked claim is enforced on the next resume.
- **Manual fallback**: the `Coba lagi` button forces an immediate
  `getIdTokenResult(forceRefresh: true)`.

There is no background polling timer; refresh is driven deterministically by
foreground/resume plus an explicit retry, which is fail-closed on network
errors (a transient refresh failure leaves the previous verdict in place).

## Deployment order

1. Enable Anonymous Authentication.
2. Enroll all owner UIDs and the controller user.
3. Restart app and firmware; verify refreshed claims.
4. Deploy `database.rules.json` and `firestore.rules`.
5. Verify unclaimed accounts are denied and owner/controller operations match
   their roles.

Rules are not deployed automatically by source changes.
