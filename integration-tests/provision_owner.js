/**
 * Issue #24 integration harness — owner/controller principal provisioning.
 *
 * Creates (idempotently) the deterministic email/password test user used by the
 * Flutter integration suite and sets the `owner` + `controller` custom claims
 * that the production security rules require. This mirrors the out-of-band
 * trusted-provisioning model described in contracts/firebase-authorization.md:
 * the Flutter installation signs in and carries `owner == true`, and the
 * read-back of `/commands` relies on `controller == true` (the Master
 * principal).
 *
 * The Admin SDK talks to the local Auth emulator, never a production project:
 * `FIREBASE_AUTH_EMULATOR_HOST` is required and the project id is the synthetic
 * `esh-integration-test` id. No service-account key or real credential is used
 * or required (the Auth emulator accepts the Admin SDK without real credentials
 * once `FIREBASE_AUTH_EMULATOR_HOST` is set).
 */

"use strict";

const admin = require("firebase-admin");

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || "esh-integration-test";
const TEST_UID = "esh-integration-owner";
const TEST_EMAIL = process.env.ESH_TEST_EMAIL || "owner@esh.test";
const TEST_PASSWORD = process.env.ESH_TEST_PASSWORD || "esh-test-password";

function fail(message) {
  console.error(message);
  process.exit(1);
}

if (!process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  fail(
    "FIREBASE_AUTH_EMULATOR_HOST is not set. Refusing to provision against a " +
      "non-emulator environment (this guard prevents accidental production " +
      "access)."
  );
}

if (PROJECT_ID !== "esh-integration-test") {
  fail(
    "Refusing to provision for project '" + PROJECT_ID + "'. The integration " +
      "harness only targets the synthetic 'esh-integration-test' project."
  );
}

async function main() {
  const app = admin.initializeApp({ projectId: PROJECT_ID });
  const auth = admin.auth(app);

  let user;
  try {
    user = await auth.getUser(TEST_UID);
    console.log("Reusing existing test user: " + TEST_UID);
  } catch (err) {
    if (err.code !== "auth/user-not-found") {
      throw err;
    }
    user = await auth.createUser({
      uid: TEST_UID,
      email: TEST_EMAIL,
      password: TEST_PASSWORD,
      emailVerified: true,
    });
    console.log("Created test user: " + TEST_UID);
  }

  await auth.setCustomUserClaims(TEST_UID, { owner: true, controller: true });
  console.log(
    "Provisioned " + TEST_UID + " with owner=true, controller=true"
  );
  console.log(
    "Flutter integration suite signs in with email='" + TEST_EMAIL +
      "' password='" + TEST_PASSWORD + "'"
  );

  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
