# FR-18..FR-28 integration coverage

Issue #24 — emulator-backed integration tests for heartbeat freshness,
module-offline, and Firebase connection behavior.

## What is covered and where

Two layers pin the failure-safety invariants of FR-18..FR-28:

1. **Unit layer** (`apps/flutter/test/monitoring_bloc_test.dart`,
   `monitoring_device_widget_test.dart`) — fast, deterministic regression tests
   using a fake repository and a fixed clock. These already pin the freshness
   boundary, command blocking, sensor-log gating, and `#` rendering logic.

2. **Integration layer** (`apps/flutter/integration_test/`) — drives the
   *production* Firebase path against the emulator suite: real Realtime
   Database emulator, real security rules, a provisioned `owner`/`controller`
   principal, `FirebaseMonitoringDataSource` -> mapper ->
   `MonitoringRepositoryImpl` -> `MonitoringBloc` -> `MonitoringPage`.

The integration layer is what Issue #24 adds. It proves, with real Firebase
round-trips, that:

- freshness is computed correctly (FR-18/FR-19);
- unavailable data is visibly marked `#` including derived cost/emission and
  Heat Index/categories (FR-22/FR-23/FR-24);
- unsafe commands are suppressed at the RTDB level (FR-20/FR-28);
- the last confirmed actual hardware state survives connection/heartbeat loss
  (FR-21).

## Emulator safety

The integration suite cannot reach a production project:

- it runs only under `--dart-define=ESH_INTEGRATION=true` (hard fail otherwise);
- it initializes a **named** Firebase app (`esh-integration-test`) so the
  `google-services.json`-registered production project is never selected;
- `FirebaseAuth.useAuthEmulator` / `FirebaseDatabase.useDatabaseEmulator`
  redirect every SDK call to the local emulator suite;
- the Node provisioning harness refuses to run without
  `FIREBASE_AUTH_EMULATOR_HOST` and against any project other than
  `esh-integration-test`.

## Test principal

The integration suite signs in with a deterministic email/password principal
(`owner@esh.test`) provisioned out-of-band with `owner == true` and
`controller == true` custom claims (see
`integration-tests/provision_owner.js`). This mirrors the production model in
`contracts/firebase-authorization.md`: `owner` authorizes the Flutter client
(command writes + telemetry reads), and `controller` is the Master principal
used here only for the legitimate read-back of `/commands` when asserting that
no command was emitted.

## Deterministic clock

Freshness is wall-clock independent: the bloc's `now` clock is pinned to
`fixedNowEpochSeconds = 2000000000` and every seeded `unix_time`/`sampled_at`
is relative to it, so the exact 59s/60s boundary cannot drift. The bloc's
freshness expiry timer is replaced by an inert timer; the automatic-expiry
path itself is already pinned deterministically in the unit layer
(`online heartbeat expires without new telemetry`).

## Traceability

| FR | Scenario | Test |
|----|----------|------|
| FR-18 | heartbeat read / fresh heartbeat stays online | `heartbeat age 0 seconds keeps ESH online`, `heartbeat age 59 seconds keeps ESH online` |
| FR-19 | heartbeat >= 60s marks ESH offline | `heartbeat age exactly 60 seconds marks ESH offline`, `heartbeat age 61 seconds marks ESH offline` |
| FR-20 | offline disables control | `control intent while heartbeat stale does not write command`, `heartbeat age exactly 60 seconds marks ESH offline` |
| FR-21 | connection/heartbeat loss preserves last hardware state | `last confirmed device state is retained through connection loss`, `...through heartbeat expiry` |
| FR-22 | environment module offline | `environment module explicit offline hides environment data`, `environment sample stale hides environment data` |
| FR-23 | power module offline | `power module explicit offline hides power data`, `power sample stale hides power data` |
| FR-24 | offline values render `#` | `stale heartbeat hides power data and derived cost/emission as hash`, `environment module offline hides heat index and categories as hash` |
| FR-25 | Firebase connection state distinguished | `Firebase disconnect retains ESH status as stale and blocks control` |
| FR-26 | ESH system status distinguished from Firebase | `stale heartbeat hides power data and derived cost/emission as hash` (ESH `Offline` vs Firebase `Terhubung`) |
| FR-27 | module/Slave availability | `Slave offline blocks command to Slave-owned device`, `Master-owned device is not disabled solely by Slave offline` |
| FR-28 | Can Control truth table / no unsafe command | `command is emitted when Firebase and ESH are online`, `control intent while ESH status unknown does not write command`, `control intent while Firebase disconnected does not write command` |
| NFR-03 | determinism (fixed clock, no wall-clock waits) | every freshness test uses `fixedNowEpochSeconds` |
| NFR-04 | no production access (named app + emulator hosts) | `emulator_env.dart` guard + `integration-tests/provision_owner.js` guard |

## Running locally

```bash
# 1. install the harness deps
cd integration-tests && npm ci

# 2. boot an Android emulator (or any Firebase-supported device)

# 3. run emulators + provisioning + integration suite from the repo root
firebase emulators:exec \
  --config firebase/firebase.json \
  --only auth,database \
  --project esh-integration-test \
  "node integration-tests/provision_owner.js && cd apps/flutter && flutter test integration_test --dart-define=ESH_INTEGRATION=true --dart-define=ESH_EMULATOR_HOST=10.0.2.2"
```

CI executes the same path via `.github/workflows/integration.yml`.
