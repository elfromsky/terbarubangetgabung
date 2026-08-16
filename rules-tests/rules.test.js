const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} = require("@firebase/rules-unit-testing");
const { doc, setDoc, getDoc, addDoc, collection, deleteDoc } = require("firebase/firestore");
const { ref, set, get } = require("firebase/database");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const fs = require("fs");
const path = require("path");

const PROJECT_ID = "esh-rules-test";
const firestoreRules = fs.readFileSync(
  path.join(__dirname, "..", "firebase", "firestore.rules"),
  "utf8"
);
const databaseRules = fs.readFileSync(
  path.join(__dirname, "..", "firebase", "database.rules.json"),
  "utf8"
);

/** @type {RulesTestEnvironment} */
let testEnv;

beforeAll(async () => {
  process.env.FIRESTORE_EMULATOR_HOST = "localhost:8080";
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: firestoreRules },
    database: { rules: databaseRules },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearDatabase();
});

// Admin SDK client used only to seed documents while bypassing security rules.
// It runs against the local Firestore emulator, never a production project.
function adminSeedDb() {
  const app = initializeApp(
    { projectId: PROJECT_ID },
    `admin-seed-${Math.random().toString(36).slice(2)}`
  );
  return getFirestore(app);
}

function makeToken(owner = false, controller = false) {
  return { owner, controller };
}

const validSensorLog = {
  timestamp: new Date(),
  power: {
    connected: true,
    voltage: 220,
    current: 1.5,
    power: 330,
    energy: 4.25,
  },
  environment: {
    connected: true,
    temperature: 27.5,
    humidity: 60,
  },
  derived: {
    estimatedCost: 6123.5,
    estimatedEmission: 3.6125,
  },
};

const canonicalCommand = {
  state: true,
  brightness: 75,
  request_id: "req-123",
  issued_at: Date.now(),
};

describe("Firestore sensorLogs rules", () => {
  test("owner can create a canonical sensor log with derived values", async () => {
    const ctx = testEnv.authenticatedContext("owner-user", makeToken(true, false));
    const db = ctx.firestore();
    await assertSucceeds(addDoc(collection(db, "sensorLogs"), validSensorLog));
  });

  test("owner can create a canonical sensor log without derived values", async () => {
    const ctx = testEnv.authenticatedContext("owner-user", makeToken(true, false));
    const db = ctx.firestore();
    const { derived, ...withoutDerived } = validSensorLog;
    await assertSucceeds(addDoc(collection(db, "sensorLogs"), withoutDerived));
  });

  test("controller cannot create sensor logs", async () => {
    const ctx = testEnv.authenticatedContext("controller-user", makeToken(false, true));
    const db = ctx.firestore();
    await assertFails(addDoc(collection(db, "sensorLogs"), validSensorLog));
  });

  test("authenticated user with no custom claim cannot create sensor logs", async () => {
    const ctx = testEnv.authenticatedContext("no-claim-user", makeToken(false, false));
    const db = ctx.firestore();
    await assertFails(addDoc(collection(db, "sensorLogs"), validSensorLog));
  });

  test("owner=false claim cannot create sensor logs", async () => {
    const ctx = testEnv.authenticatedContext("false-owner", makeToken(false, false));
    const db = ctx.firestore();
    await assertFails(addDoc(collection(db, "sensorLogs"), validSensorLog));
  });

  test("owner string-true claim cannot create sensor logs (strict boolean)", async () => {
    const ctx = testEnv.authenticatedContext(
      "string-owner",
      { owner: "true", controller: false }
    );
    const db = ctx.firestore();
    await assertFails(addDoc(collection(db, "sensorLogs"), validSensorLog));
  });

  test("controller string-true claim cannot create sensor logs (strict boolean)", async () => {
    const ctx = testEnv.authenticatedContext(
      "string-controller",
      { owner: false, controller: "true" }
    );
    const db = ctx.firestore();
    await assertFails(addDoc(collection(db, "sensorLogs"), validSensorLog));
  });

  test("owner can read sensor logs", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "sensorLogs", "seed"), validSensorLog);
    });
    const ctx = testEnv.authenticatedContext("owner-user", makeToken(true, false));
    await assertSucceeds(getDoc(doc(ctx.firestore(), "sensorLogs", "seed")));
  });

  test("controller can read sensor logs", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "sensorLogs", "seed"), validSensorLog);
    });
    const ctx = testEnv.authenticatedContext("controller-user", makeToken(false, true));
    await assertSucceeds(getDoc(doc(ctx.firestore(), "sensorLogs", "seed")));
  });

  test("unauthenticated user cannot create sensor logs", async () => {
    const ctx = testEnv.unauthenticatedContext();
    await assertFails(addDoc(collection(ctx.firestore(), "sensorLogs"), validSensorLog));
  });

  test("unauthenticated user cannot read sensor logs", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "sensorLogs", "seed"), validSensorLog);
    });
    const ctx = testEnv.unauthenticatedContext();
    await assertFails(getDoc(doc(ctx.firestore(), "sensorLogs", "seed")));
  });

  test("owner cannot update or delete sensor logs", async () => {
    await adminSeedDb().collection("sensorLogs").doc("seed").set(validSensorLog);
    const ctx = testEnv.authenticatedContext("owner-upd-del", makeToken(true, false));
    const db = ctx.firestore();
    await assertFails(setDoc(doc(db, "sensorLogs", "seed"), { energy: 5 }));
    await assertFails(deleteDoc(doc(db, "sensorLogs", "seed")));
  });

  test("controller cannot update or delete sensor logs", async () => {
    await adminSeedDb().collection("sensorLogs").doc("seed").set(validSensorLog);
    const ctx = testEnv.authenticatedContext("controller-upd-del", makeToken(false, true));
    const db = ctx.firestore();
    await assertFails(setDoc(doc(db, "sensorLogs", "seed"), { energy: 5 }));
    await assertFails(deleteDoc(doc(db, "sensorLogs", "seed")));
  });

  test("sensor log missing required fields is rejected", async () => {
    const ctx = testEnv.authenticatedContext("owner-user", makeToken(true, false));
    const db = ctx.firestore();
    await assertFails(addDoc(collection(db, "sensorLogs"), { timestamp: new Date() }));
    await assertFails(
      addDoc(collection(db, "sensorLogs"), {
        timestamp: new Date(),
        power: validSensorLog.power,
        environment: "not-a-map",
      })
    );
  });

  test("sensor log with unexpected top-level field is rejected", async () => {
    const ctx = testEnv.authenticatedContext("owner-user", makeToken(true, false));
    const db = ctx.firestore();
    await assertFails(
      addDoc(collection(db, "sensorLogs"), {
        ...validSensorLog,
        unexpected: "field",
      })
    );
  });

  test("sensor log with wrong timestamp type is rejected", async () => {
    const ctx = testEnv.authenticatedContext("owner-user", makeToken(true, false));
    const db = ctx.firestore();
    await assertFails(
      addDoc(collection(db, "sensorLogs"), {
        ...validSensorLog,
        timestamp: 1234567890,
      })
    );
  });

  test("sensor log with wrong power type is rejected", async () => {
    const ctx = testEnv.authenticatedContext("owner-user", makeToken(true, false));
    const db = ctx.firestore();
    await assertFails(
      addDoc(collection(db, "sensorLogs"), {
        ...validSensorLog,
        power: "not-a-map",
      })
    );
  });

  test("sensor log with wrong environment type is rejected", async () => {
    const ctx = testEnv.authenticatedContext("owner-user", makeToken(true, false));
    const db = ctx.firestore();
    await assertFails(
      addDoc(collection(db, "sensorLogs"), {
        ...validSensorLog,
        environment: 42,
      })
    );
  });

  test("sensor log with wrong derived type when provided is rejected", async () => {
    const ctx = testEnv.authenticatedContext("owner-user", makeToken(true, false));
    const db = ctx.firestore();
    await assertFails(
      addDoc(collection(db, "sensorLogs"), {
        ...validSensorLog,
        derived: "not-a-map",
      })
    );
  });
});

describe("RTDB commands rules", () => {
  test("owner controller can write a valid room command", async () => {
    const ctx = testEnv.authenticatedContext("owner-ctrl", makeToken(true, true));
    const db = ctx.database();
    await assertSucceeds(
      set(ref(db, "commands/rooms/dapur/tools/lampu"), canonicalCommand)
    );
  });

  test("controller-only cannot write commands (must be owner)", async () => {
    const ctx = testEnv.authenticatedContext("controller-only", makeToken(false, true));
    const db = ctx.database();
    await assertFails(
      set(ref(db, "commands/rooms/dapur/tools/lampu"), canonicalCommand)
    );
  });

  test("command missing required fields is rejected", async () => {
    const ctx = testEnv.authenticatedContext("owner-ctrl", makeToken(true, true));
    const db = ctx.database();
    await assertFails(
      set(ref(db, "commands/rooms/dapur/tools/lampu"), { state: true })
    );
  });

  test("command for unknown room/device is rejected", async () => {
    const ctx = testEnv.authenticatedContext("owner-ctrl", makeToken(true, true));
    const db = ctx.database();
    await assertFails(
      set(ref(db, "commands/rooms/garasi/tools/lampu"), canonicalCommand)
    );
  });

  test("non-dimmable command must not include brightness", async () => {
    const ctx = testEnv.authenticatedContext("owner-ctrl", makeToken(true, true));
    const db = ctx.database();
    await assertFails(
      set(ref(db, "commands/rooms/teras/tools/sanyo"), canonicalCommand)
    );
  });
});

describe("RTDB telemetry read rules", () => {
  async function seedTelemetry() {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.database();
      await set(ref(db, "device"), { mcb: { status: "on" } });
      await set(ref(db, "rooms/dapur/tools/lampu"), { state: true });
      await set(ref(db, "gateway/connected"), true);
      await set(ref(db, "commands/rooms/dapur/tools/lampu"), {
        state: true,
        request_id: "req-read",
        issued_at: Date.now(),
      });
    });
  }

  test("owner can read device, rooms, and gateway", async () => {
    await seedTelemetry();
    const ctx = testEnv.authenticatedContext("owner-read", makeToken(true, false));
    const db = ctx.database();
    await assertSucceeds(get(ref(db, "device")));
    await assertSucceeds(get(ref(db, "rooms")));
    await assertSucceeds(get(ref(db, "gateway")));
  });

  test("controller can read device, rooms, and gateway", async () => {
    await seedTelemetry();
    const ctx = testEnv.authenticatedContext("controller-read", makeToken(false, true));
    const db = ctx.database();
    await assertSucceeds(get(ref(db, "device")));
    await assertSucceeds(get(ref(db, "rooms")));
    await assertSucceeds(get(ref(db, "gateway")));
  });

  test("unauthenticated user cannot read telemetry", async () => {
    await seedTelemetry();
    const ctx = testEnv.unauthenticatedContext();
    const db = ctx.database();
    await assertFails(get(ref(db, "device")));
    await assertFails(get(ref(db, "rooms")));
    await assertFails(get(ref(db, "gateway")));
  });

  test("authenticated user with no claim cannot read telemetry", async () => {
    await seedTelemetry();
    const ctx = testEnv.authenticatedContext("no-claim-read", makeToken(false, false));
    const db = ctx.database();
    await assertFails(get(ref(db, "device")));
  });

  test("owner cannot read commands (commands read is controller-only)", async () => {
    await seedTelemetry();
    const ctx = testEnv.authenticatedContext("owner-read-cmd", makeToken(true, false));
    await assertFails(get(ref(ctx.database(), "commands")));
  });
});

describe("RTDB command issued_at freshness boundaries", () => {
  // Reference: database.rules.json
  //   "issued_at": ".validate": "newData.isNumber() &&
  //     newData.val() >= now - 15000 && newData.val() <= now + 5000"
  // Both bounds are INCLUSIVE (>= and <=).
  //
  // NOTE: the emulator's `now` is a live millisecond clock that advances
  // between test construction and rule evaluation by a few ms. Regressions
  // near the exact +-1ms edge are therefore asserted at safe margins;
  // the exact inclusive boundary semantics are documented from the
  // operator level and reproduced in the deterministic Master mirror test
  // (tools/evidence_gaps_test.py), not from a frozen emulator clock.

  let seq = 0;
  function freshCommand(issuedAt) {
    seq += 1;
    return {
      state: true,
      request_id: "freshtest-" + seq,
      issued_at: issuedAt,
    };
  }

  async function writeIssuedAt(ctx, issuedAt) {
    return set(
      ref(ctx.database(), "commands/rooms/teras/tools/sanyo"),
      freshCommand(issuedAt)
    );
  }

  const now = () => Math.floor(Date.now());

  test("issued_at far in the past is rejected (stale)", async () => {
    const ctx = testEnv.authenticatedContext("owner-ctrl", makeToken(true, true));
    await assertFails(writeIssuedAt(ctx, now() - 20000));
  });

  test("issued_at within the 15s stale window is accepted", async () => {
    const ctx = testEnv.authenticatedContext("owner-ctrl", makeToken(true, true));
    await assertSucceeds(writeIssuedAt(ctx, now() - 14000));
  });

  test("issued_at equal to now is accepted", async () => {
    const ctx = testEnv.authenticatedContext("owner-ctrl", makeToken(true, true));
    await assertSucceeds(writeIssuedAt(ctx, now()));
  });

  test("issued_at within the 5s future tolerance is accepted", async () => {
    const ctx = testEnv.authenticatedContext("owner-ctrl", makeToken(true, true));
    await assertSucceeds(writeIssuedAt(ctx, now() + 4000));
  });

  test("issued_at beyond the 5s future tolerance is rejected", async () => {
    const ctx = testEnv.authenticatedContext("owner-ctrl", makeToken(true, true));
    await assertFails(writeIssuedAt(ctx, now() + 6000));
  });
});
