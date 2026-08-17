# ESH — e-Smart Home

A coordinated monorepo for the ESH (e-smart-home) system: a Flutter mobile app,
an ESP32 Master gateway, an ESP32 Slave device controller, Firebase backend
rules, and the contracts that bind them together.

## Repository

Canonical repository: <https://github.com/elfromsky/esh-smart-home>

```bash
git clone https://github.com/elfromsky/esh-smart-home.git
```

The canonical development branch is `main`. Feature, fix, and repository
changes branch from `main` and are merged back through pull requests. See
`docs/DEVELOPMENT.md`.

## What this system does

```text
Flutter app
   | command
   v
Firebase RTDB rules
   v
ESP32 Master (Wi-Fi + Firebase + NTP)
   | ESP-NOW
   v
ESP32 Slave
   v
relay / dimmer
```

Telemetry travels the reverse path (Slave -> Master -> RTDB -> Flutter).

## Repository layout

```text
.
├── apps/flutter/        Flutter application
├── firmware/master/     ESP32 Master firmware (PlatformIO)
├── firmware/slave/      ESP32 Slave firmware (PlatformIO)
├── firebase/            Firebase RTDB/Firestore rules and config
├── contracts/           canonical cross-component contracts
├── rules-tests/         Firebase rules emulator tests
├── tools/               deterministic contract/evidence tests and diagnostics
├── docs/                architecture, development, provisioning docs
├── scripts/ci/          CI helper scripts (synthetic provisioning, hygiene)
└── .github/workflows/   coordinated CI
```

Directories define components; branches define changes; commits define
coordinated system revisions.

## Validating each component

### Flutter

```bash
cd apps/flutter
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

### Flutter integration (Firebase emulator-backed, Issue #24)

Runs on an Android emulator against the Firebase Auth + Realtime Database
emulators and exercises FR-18..FR-28 (heartbeat freshness, module-offline `#`
rendering, command suppression, last-state retention). See
`docs/testing/FR18-FR28-INTEGRATION.md` for the traceability matrix.

```bash
cd integration-tests && npm ci
# from the repo root, with an Android emulator running:
firebase emulators:exec \
  --config firebase/firebase.json \
  --only auth,database \
  --project esh-integration-test \
  "node integration-tests/provision_owner.js && cd apps/flutter && flutter test integration_test --dart-define=ESH_INTEGRATION=true --dart-define=ESH_EMULATOR_HOST=10.0.2.2"
```

### Master firmware

```bash
bash scripts/ci/prepare-synthetic-provisioning.sh master firmware/master
cd firmware/master
pio run -e esp32-s3-devkitc-1
```

### Slave firmware

```bash
bash scripts/ci/prepare-synthetic-provisioning.sh slave firmware/slave
cd firmware/slave
pio run -e esp32-s3-devkitc-1
```

### Firebase rules

```bash
cd rules-tests
npm ci
npm run test:emulator
```

### Deterministic contract tests

```bash
python tools/contract_tests.py          # cross-component protocol invariants (Issue #22)
python tools/evidence_gaps_tests.py     # freshness boundaries + shared-dimmer mirror
python tools/duplicate_cache_tests.py   # Slave payload-aware duplicate cache (Issue #7)
python tools/energy_unit_contract_tests.py  # energy wire unit (Issue #19)
python tools/command_lifecycle_e2e_tests.py  # full command lifecycle simulation (Issue #23)
```

`tools/contract_tests.py` is the executable cross-component gate: it reads the
actual Flutter, Firebase rules, Master, and Slave sources and asserts that the
room/device identifiers, command schema, `request_id`/`issued_at` contract,
timestamp units, freshness bounds, ESP-NOW message IDs/struct ABI, shared-dimmer
channels, and telemetry field names/units all agree. A change to only one
component that breaks one of these invariants fails CI with a diagnostic naming
the exact disagreement.

## Contracts

Cross-component interfaces are documented in `contracts/`. See
`contracts/README.md` for the index. Rationale: a contract change spans
Flutter, Firebase rules, Master, and Slave simultaneously, so it is one
coordinated pull request.

## Security

Real credentials and keys are never committed. Firmware provisioning is
local-only (`*.local.h`, git-ignored) and CI uses synthetic placeholder
credentials only. See `docs/PROVISIONING.md` and `docs/ARCHITECTURE.md`.

## Historical note

This repository was migrated (Issue #8) from a branch-as-component model
(`main` = Master, `slave` = Slave, `clean` = revised Flutter) into a single
coordinated monorepo. The legacy histories are preserved via annotated tags
`legacy/master-final`, `legacy/slave-final`, `legacy/flutter-final` and the
read-only branches `slave`/`clean`/`flutter`. See `docs/MONOREPO_MIGRATION.md`.

The repository was originally maintained under the working name
`terbarubangetgabung` and was renamed to `esh-smart-home` after the monorepo
migration (Issue #21). GitHub redirects the old URL to the new one.
