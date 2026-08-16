# Contracts

This directory is the canonical, human-readable description of the
cross-component contracts that the ESH (e-smart-home) system relies on.

A "contract" here means an interface that more than one component must agree
on for the coordinated system to work. These contracts existed implicitly in
the Flutter application, the Firebase rules, the ESP32 Master firmware, and the
ESP32 Slave firmware before the monorepo migration (Issue #8). This directory
makes them explicit and gives each one a single source of truth.

These documents describe **the behavior that actually exists in the migrated
code**, not a desired redesign. They were derived from the authoritative
sources at the migration baseline (see `docs/MONOREPO_MIGRATION.md` for the
exact SHAs).

## Contents

| Document | Contract | Legacy evidence |
|----------|----------|-----------------|
| `command-protocol.md` | Flutter -> RTDB -> Master command schema | `firebas*.rules`, `firebase_command_router.cpp`, `firebase_room_device_data_source.dart` |
| `espnow-protocol.md` | Master <-> Slave ESP-NOW frame layout | `esp_now_protocol.h`, `esp_now_config.h` |
| `telemetry-schema.md` | Master -> RTDB / Slave -> Master telemetry paths | `firebase_telemetry.cpp`, `firebase_command_router.cpp` |
| `firebase-authorization.md` | Firebase Auth custom claims + rules (two-layer model: product vs security principal) | `firestore.rules`, `database.rules.json`, `device_claim.dart` |
| `time-and-freshness.md` | Clock authorities, units, freshness windows | `firebase_command_router.cpp`, `database.rules.json` |
| `shared-dimmer.md` | Shared CH1 dimmer arbitration | `firebase_command_router.cpp`, `room_device_routing.cpp`, `monitoring_repository_impl.dart` |

## Guiding rule

A contract change is a coordinated change: the same pull request should update
the producers, the consumers, the Firebase rules, these contract documents, and
the corresponding tests together. One Git revision should represent one
coordinated system revision.
