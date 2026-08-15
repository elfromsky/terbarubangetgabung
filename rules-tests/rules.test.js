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
  path.join(__dirname, "..", "firestore.rules"),
  "utf8"
);
const databaseRules = fs.readFileSync(
  path.join(__dirname, "..", "database.rules.json"),
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
