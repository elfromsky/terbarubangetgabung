# ESH Hardware Acceptance Results

Issue #26 — real-hardware acceptance **run record**. This file records the
specific acceptance attempt, not the reusable procedure (see
`docs/testing/HARDWARE_ACCEPTANCE.md`).

## Tested revision

```text
Repository       : https://github.com/elfromsky/esh-smart-home
Branch           : main
Git SHA          : 18d8d11c2fefc866aa1b3705c1e3ee382ab98c69
Release tag      : (none — first production tag not yet cut)
Version (VERSION): 1.0.0
Flutter version  : 3.44.8 (Dart 3.12.2) — pubspec version 1.0.0+1
APK              : app-debug.apk (debug)
APK SHA-256      : DFDAB4D028BADC6BBDF0E752EFB3A8735ACF65B48FE9473DB281CE1BE982ABFD
APK bytes        : 171,094,392
Master firmware  : SUCCESS esp32-s3-devkitc-1 (RAM 16.6%, Flash 29.4%) — ESH_VERSION 1.0.0
Slave firmware   : SUCCESS esp32-s3-devkitc-1 (RAM 13.7%, Flash 53.1%) — ESH_VERSION 1.0.0
Firebase env id  : e-smarthome-62391 (production) / esh-integration-test & esh-rules-test (emulators)
Acceptance run date : 2026-08-17
Operator         : elfromsky (automated agent; no physical operator)
Overall status   : BLOCKED (real hardware unavailable in execution environment)
```

The local `.local.h` provisioning files (`firmware/master/include/*.local.h`,
`firmware/slave/src/esp_now_keys.local.h`) exist, remain git-ignored, and were
**not** overwritten by synthetic provisioning; firmware was built against them
without modification.

## Hardware environment (actual)

| Item | Status |
|------|--------|
| Android device / adb | NOT AVAILABLE (`adb` not installed, no device) |
| ESP32-S3 Master (COM17) | NOT CONNECTED (no such serial port on host) |
| ESP32-S3 Slave (COM19) | NOT CONNECTED (no such serial port on host) |
| PZEM-004T | NOT AVAILABLE |
| XY-MD02 / SHT20 | NOT AVAILABLE |
| 10 relay channels | NOT AVAILABLE |
| 2 dimmer channels | NOT AVAILABLE |
| Real Firebase runtime | NOT EXERCISED (no device to drive it) |
| Physical network control | NOT AVAILABLE |
| PlatformIO/serial | PlatformIO CLI present but no target boards attached |

Host serial enumeration shows only Bluetooth virtual COM ports and a USB camera;
the firmware `upload_port` targets (COM17/COM19) are absent. Therefore no
physical observation was possible. This is the documented **no-hardware-access**
case.

## Automated / deterministic preflight (software gates)

| Command | Result | Evidence |
|---------|--------|----------|
| `python tools/evidence_gaps_tests.py` | PASS (47/47) | local run |
| `python tools/duplicate_cache_tests.py` | PASS (40/40) | local run |
| `python tools/energy_unit_contract_tests.py` | PASS (10/10) | local run |
| `python tools/contract_tests.py` | PASS (14/14) | local run |
| `python tools/command_lifecycle_e2e_tests.py` | PASS (92/92) | local run |
| `python scripts/release/test_release.py` | PASS (11/11) | local run |
| `python scripts/release/release.py validate` | OK `1.0.0` | local run |
| `flutter analyze` | PASS "No issues found" | local run |
| `flutter test` | PASS (204 tests) | local run |
| `flutter build apk --debug` | PASS (non-fatal NDK/KGP warning) | local run |
| Master `pio run -e esp32-s3-devkitc-1` | PASS | local run (no synthetic provisioning) |
| Slave `pio run -e esp32-s3-devkitc-1` | PASS | local run (no synthetic provisioning) |
| `npm run test:emulator` (rules-tests) | NOT RUN (Java 21 missing locally) | deferred to CI |
| Flutter emulator integration (Issue #24) | NOT RUN (needs Android emulator/Java) | deferred to CI |

These prove software contracts only. They are **not** hardware evidence and
cannot satisfy Issue #26's acceptance criteria.

## Hard-point test IDs

Point IDs follow `docs/testing/HARDWARE_ACCEPTANCE.md`.

## Real hardware test results

| ID | Requirement | Result | Observation | Evidence |
|----|-------------|--------|-------------|----------|
| HA-PWR-01 | FR-01 voltage | BLOCKED — REAL HARDWARE REQUIRED | no PZEM | — |
| HA-PWR-02 | FR-02 current | BLOCKED — REAL HARDWARE REQUIRED | no PZEM | — |
| HA-PWR-03 | FR-03 power | BLOCKED — REAL HARDWARE REQUIRED | no PZEM | — |
| HA-PWR-04 | FR-04 energy kWh | BLOCKED — REAL HARDWARE REQUIRED | kWh confirmed only by inspection/CI | contract test PASS is not HW proof |
| HA-PWR-05 | FR-05 cost | BLOCKED — REAL HARDWARE REQUIRED | tariff 1440.70 Rp/kWh by inspection | — |
| HA-PWR-06 | FR-06 emission | BLOCKED — REAL HARDWARE REQUIRED | 0.85 kg CO₂/kWh by inspection | — |
| HA-ENV-01 | FR-07 temperature | BLOCKED — REAL HARDWARE REQUIRED | no SHT20 | — |
| HA-ENV-02 | FR-08 humidity | BLOCKED — REAL HARDWARE REQUIRED | no SHT20 | — |
| HA-ENV-03 | FR-09 Heat Index | BLOCKED — REAL HARDWARE REQUIRED | formula verified by research doc only | — |
| HA-ENV-04 | FR-10 temp classification | BLOCKED — REAL HARDWARE REQUIRED | thresholds verified by inspection only | — |
| HA-ENV-05 | FR-11 humidity classification | BLOCKED — REAL HARDWARE REQUIRED | thresholds verified by inspection only | — |
| HA-RLY-01..10 | FR-12 (10 relays) | BLOCKED — REAL HARDWARE REQUIRED | no relay hardware | — |
| HA-DIM-01/02 | FR-13/14/15/16 (dimmers) | BLOCKED — REAL HARDWARE REQUIRED | no dimmer hardware | — |
| HA-HIST-01 | FR-17 history | BLOCKED — REAL HARDWARE REQUIRED | no live telemetry source | — |
| HA-OFF-01 | FR-18 heartbeat | BLOCKED — REAL HARDWARE REQUIRED | no Master | — |
| HA-OFF-02 | FR-19/22-27 offline/freshness | BLOCKED — REAL HARDWARE REQUIRED | — | integration test is emulator, not HW |
| HA-OFF-03 | FR-20/28 offline blocks control | BLOCKED — REAL HARDWARE REQUIRED | — | — |
| HA-OFF-04 | FR-21 last-state retention | BLOCKED — REAL HARDWARE REQUIRED | — | — |
| HA-OFF-05 | reconnection | BLOCKED — REAL HARDWARE REQUIRED | — | — |
| HA-MOD-01 | power module availability | BLOCKED — SAFE SENSOR ISOLATION NOT PERFORMED | — | — |
| HA-MOD-02 | environment module availability | BLOCKED — SAFE SENSOR ISOLATION NOT PERFORMED | — | — |
| HA-SAF-01 | NFR-03 failure safety | BLOCKED — REAL HARDWARE REQUIRED | depends on HA-OFF-* | — |
| HA-USR-01 | NFR-01 usability | BLOCKED — REAL USER ACCEPTANCE NOT PERFORMED | no participants | — |
| HA-NOW-01/02 | real ESP-NOW | BLOCKED — REAL HARDWARE REQUIRED | no Master/Slave radio link | — |
| HA-UNIT-* | units end-to-end | BLOCKED — REAL HARDWARE REQUIRED | labels verified by inspection/CI only | — |

### Totals

```text
PASS           : 0
FAIL           : 0
BLOCKED        : 26 test groups (all hardware-only)
NOT RUN        : 0 (hardware tests blocked rather than run without evidence)
NOT APPLICABLE : 0
```

## Sensor validation summary

Not executed — no PZEM-004T, no XY-MD02/SHT20 connected.

## Actuator validation summary

Not executed — no relays, no dimmers, no ESP-NOW radio link connected.

## Offline / failure-safety validation summary

Not executed on hardware. Deterministic equivalents (Issue #24 integration) pass
on the emulator but are explicitly transport-simulation, not physical outage.

## Unit validation summary

Wire/domain/UI units verified by inspection and by
`energy_unit_contract_tests.py` + `contract_tests.py` (energy = kWh, no factor
of 1000 in the runtime path). Hardware magnitude confirmation remains BLOCKED.

## Defects found

No new implementation defect was discovered among the tests actually executed.
All deterministic gates are green on `18d8d11`. The energy Wh/kWh defect
(Issue #19) remains corrected in source; its hardware-numeric confirmation is
still pending (HA-PWR-04 BLOCKED).

## Overall

**BLOCKED — REAL HARDWARE REQUIRED.**

Issue #26 must remain open until the runbook in
`docs/testing/HARDWARE_ACCEPTANCE.md` is executed against the physical system by
an operator with access to the assembled ESH hardware (PZEM, SHT20, 10 relays,
2 dimmers, real ESP-NOW, real AP, Android device against real Firebase).