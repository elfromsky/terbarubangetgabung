# Firebase Security Provisioning

ESH uses two explicit Firebase roles:

- `owner: true` for the three approved anonymous Flutter installations.
- `controller: true` for the ESP32 Master Firebase Authentication user.

Unclaimed authenticated users cannot read telemetry, history, or reported state and cannot send commands.

## Prerequisites

1. Enable `Anonymous` under Firebase Console > Authentication > Sign-in method.
2. Rotate the firmware Firebase password and Wi-Fi password that previously existed in Git history.
3. Keep Admin SDK credentials outside this repository.

## Enroll Flutter Owners

1. Install and open the APK on an approved phone.
2. Copy the UID shown on the `Perangkat belum terdaftar` screen.
3. Set `owner: true` for that UID from a trusted Admin SDK environment.
4. Tap `Coba lagi` to force an ID-token refresh.
5. Repeat for the other approved phones. Reinstallation creates a new anonymous UID and requires enrollment again.

## Enroll Controller

Set `controller: true` on the Firebase Authentication user configured in the ESP32 Master local configuration. Restart the firmware after changing claims so it obtains a new ID token.

Use this Admin SDK script from a trusted environment:

```js
const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

async function addClaim(uid, claim) {
  const user = await admin.auth().getUser(uid);
  await admin.auth().setCustomUserClaims(uid, {
    ...(user.customClaims ?? {}),
    [claim]: true,
  });
}

async function main() {
  await addClaim(process.env.ESH_OWNER_UID, 'owner');

  const controller = await admin.auth().getUserByEmail(
    process.env.ESH_CONTROLLER_EMAIL,
  );
  await addClaim(controller.uid, 'controller');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
```

## Deployment Order

1. Enable Anonymous Authentication.
2. Enroll all owner UIDs and controller user.
3. Restart app and firmware; verify refreshed claims.
4. Deploy `database.rules.json` and `firestore.rules`.
5. Verify unclaimed accounts are denied and owner/controller operations match their roles.

Rules are not deployed automatically by source changes.
