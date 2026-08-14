const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} = require("@firebase/rules-unit-testing");
const { doc, setDoc, getDoc, addDoc, collection, deleteDoc } = require("firebase/firestore");
const { ref, set, get } = require("firebase/database");
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
  test("controller can create a canonical sensor log with derived values", async () => {
    const ctx = testEnv.authenticatedContext("controller-user", makeToken(false, true));
    const db = ctx.firestore();
    await assertSucceeds(addDoc(collection(db, "sensorLogs"), validSensorLog));
  });

  test("owner can read sensor logs", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "sensorLogs", "seed"), validSensorLog);
    });
    const ctx = testEnv.authenticatedContext("owner-user", makeToken(true, false));
    await assertSucceeds(getDoc(doc(ctx.firestore(), "sensorLogs", "seed")));
  });

  test("unauthenticated user cannot create sensor logs", async () => {
    const ctx = testEnv.unauthenticatedContext();
    await assertFails(addDoc(collection(ctx.firestore(), "sensorLogs"), validSensorLog));
  });

  test("controller cannot update or delete sensor logs", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "sensorLogs", "seed"), validSensorLog);
    });
    const ctx = testEnv.authenticatedContext("controller-user", makeToken(false, true));
    await assertFails(setDoc(doc(ctx.firestore(), "sensorLogs", "seed"), { energy: 5 }));
    await assertFails(deleteDoc(doc(ctx.firestore(), "sensorLogs", "seed")));
  });

  test("sensor log missing required fields is rejected", async () => {
    const ctx = testEnv.authenticatedContext("controller-user", makeToken(false, true));
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
