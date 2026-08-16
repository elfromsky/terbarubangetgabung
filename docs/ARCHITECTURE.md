# Architecture

## System flow

### Command path

```text
Flutter (owner)
   -> writes /commands/rooms/<room>/tools/<device>  { state, [brightness], request_id, issued_at }
   -> Firebase RTDB (validated by database.rules.json)
   -> ESP32 Master (Firebase stream; parses, validates freshness)
   -> ESP-NOW encrypted command (DeviceCommandPayload)
   -> ESP32 Slave (validates CRC, dedup, drives relay/dimmer)
   -> ESP-NOW state/ACK (DeviceStatePayload)
```

### Telemetry path

```text
ESP32 Slave
   -> ESP-NOW periodic state report
   -> ESP32 Master (noteValidSlavePacket -> Slave availability)
   -> publishes /device/sensorData/*, /rooms/*/tools/*, /gateway/status/slave
   -> Firebase RTDB
   -> Flutter (monitoring + history + control gating)
```

### History path

```text
Flutter (owner) -> Firestore sensorLogs (create only, schema-validated)
```

## Components

### `apps/flutter/`
Flutter UI, state management (BLoC), Firebase client interaction, command
generation, telemetry mapping, and Firestore history persistence.

### `firmware/master/`
Wi-Fi, NTP, Firebase connectivity, heartbeat, command parsing, freshness
checks, Master-owned relays (`teras/lampu`, `teras/sanyo`), ESP-NOW
coordination, Slave availability, and gateway status publication.

### `firmware/slave/`
ESP-NOW receive/auth, command execution, relay/dimmer hardware, duplicate/replay
handling, state acknowledgements, and state reporting.

### `firebase/`
Declarative backend contracts: RTDB rules (`database.rules.json`), Firestore
rules (`firestore.rules`), indexes, and emulator config (`firebase.json`).
No production credentials live here.

### `contracts/`
Canonical human-readable cross-component contracts. See `contracts/README.md`.

## Backend

- Realtime Database: `/commands`, `/rooms`, `/device/sensorData`,
  `/gateway/status`.
- Firestore: `sensorLogs` (history).

## Authorization model

Two strict-boolean custom claims, `owner` and `controller`, gate all Firebase
access. See `contracts/firebase-authorization.md`. These are settled contracts;
the monorepo migration does not change them.
