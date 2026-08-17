# Coordinated Revision Diagnostic Report

Generated: 2026-08-14 23:56:16 +0700
Repository: C:\Users\Advan\Documents\MEKATRONIKA\PROGRAM\terbarugabungarch\newflutbaruarch
Issue: https://github.com/elfromsky/esh-smart-home/issues/1

## Environment

| Tool | Status |
|------|--------|
| git | git version 2.49.0.windows.1 |
| flutter | Flutter 3.44.8 • channel stable • https://github.com/flutter/flutter.git |
| dart | Dart SDK version: 3.12.2 (stable) (Tue Jun 9 01:11:39 2026 -0700) on "windows_x64" |
| node | v22.16.0 |
| npm | 10.9.2 |
| firebase | 14.7.0 |
| pio | MISSING |
| platformio | MISSING |
| java | MISSING |


## Repository topology

| Pair | Merge base |
|------|------------|
| main <-> slave | (none / unrelated) |
| main <-> clean | (none / unrelated) |
| slave <-> clean | (none / unrelated) |
| flutter -> clean | 6cb3438d409bb0759738224a0c89e3050348c0a4 |

**Root vs pre-revision vs revised snapshot table:**
| Component | Root | Pre-revision | Revised |
|-----------|------|--------------|---------|
| Master | `032f486dc41bb35318b3f501a4cd70321d73985a` | `273b3f6` | `f8c960e` |
| Slave | `ac79be592daf1a36a762a94e2332a0e24a5ed851` | `24da621` | `6d306cf` |
| Flutter | `6cb3438d409bb0759738224a0c89e3050348c0a4` | `1b62be3` | `5bd9fb6` |

The roots above are the true independent roots of each lineage, distinct from the selected pre-revision snapshots. Only the Flutter `flutter -> clean` lineage shares ancestry (merge base `6cb3438d409bb0759738224a0c89e3050348c0a4`). The three component lineages are unrelated.


## Build results

| Component | Revision | Pristine | Synthetic-provisioned | Classification |
|-----------|----------|----------|-----------------------|----------------|
| Flutter | `1b62be3` | pub:PASS analyze:PASS test:PASS apk:PASS | N/A | see below |
| Flutter | `5bd9fb6` | pub:PASS analyze:PASS test:PASS apk:FAIL
```
Resolving dependencies...
Downloading packages...
  _flutterfire_internals 1.3.35 (1.3.76 available)
  async 2.13.0 (2.13.1 available)
  bloc 9.0.0 (9.2.1 available)
  cloud_firestore 4.17.5 (6.8.0 available)
  cloud_firestore_platform_interface 6.2.5 (8.0.6 available)
  cloud_firestore_web 3.12.5 (5.7.2 available)
  cupertino_icons 1.0.8 (1.0.9 available)
  equatable 2.0.7 (2.1.0 available)
  firebase_auth 4.20.0 (6.5.7 available)
  firebase_auth_platform_interface 7.3.0 (9.0.6 available)
  firebase_auth_web 5.12.0 (6.2.6 available)
  firebase_core 2.32.0 (4.13.0 available)
  firebase_core_platform_interface 5.4.0 (8.1.0 available)
  firebase_core_web 2.17.5 (3.10.0 available)
  firebase_database 10.5.7 (12.4.7 available)
  firebase_database_platform_interface 0.2.5+35 (0.4.0+6 available)
  firebase_database_web 0.2.5+7 (0.2.7+13 available)
  fl_chart 0.70.2 (1.2.0 available)
  flutter_lints 5.0.0 (6.0.0 available)
  go_router 15.2.3 (retracted, 17.5.0 available)
  intl 0.20.2 (0.20.3 available)
  lints 5.1.1 (6.1.0 available)
  matcher 0.12.19 (0.12.20 available)
  material_color_utilities 0.13.0 (0.13.1 available)
  meta 1.18.0 (1.19.0 available)
  provider 6.1.5 (6.1.5+1 available)
  source_span 1.10.1 (1.10.2 available)
  syncfusion_flutter_core 28.2.12 (34.2.3 available)
  syncfusion_flutter_gauges 28.2.12 (34.2.3 available)
  test_api 0.7.11 (0.7.13 available)
  vector_math 2.2.0 (2.4.2 available)
  vm_service 15.0.0 (15.2.0 available)
  web 0.5.1 (1.1.1 available)
Got dependencies!
33 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Running Gradle task 'assembleDebug'...                          
Running Gradle task 'assembleDebug'...                             53.2s

Warning: Flutter support for your project's Gradle version (8.12.0) will soon be dropped. Please upgrade your Gradle version to a version of at least 8.14.0 soon.
Alternatively, use the flag "--android-skip-build-dependency
... (truncated)
``` | N/A | see below |
| Master | `273b3f6` | SKIP (pio missing) | N/A | SKIPPED_ENVIRONMENT |
| Master | `f8c960e` | expected fail-closed | SKIP (pio missing) | EXPECTED_PROVISIONING_FAILURE |
| Slave | `24da621` | SKIP (pio missing) | N/A | SKIPPED_ENVIRONMENT |
| Slave | `6d306cf` | expected fail-closed | SKIP (pio missing) | EXPECTED_PROVISIONING_FAILURE |


## Flutter <-> Master protocol compatibility

| Flutter | Master | Compatible | Evidence |
|---------|--------|------------|----------|
| before | before | YES | Both use `{ state, brightness? }` with no request_id/issued_at. |
| before | revised | NO | Old Flutter omits `request_id` and `issued_at`; revised Master rejects with field-count check. |
| revised | before | NO | Revised Flutter emits `request_id`/`issued_at`; old Master expects only `state`/`brightness` and rejects extra fields. |
| revised | revised | YES | Both use `{ state, brightness?, request_id, issued_at }` with matching validation ranges. |


## Master <-> Slave protocol compatibility

| Master | Slave | Compatible | Evidence |
|--------|-------|------------|----------|
| before | before | YES | Both use legacy unencrypted struct without PMK/LMK/auth beacon; struct sizes match legacy build. |
| before | revised | NO | Revised Slave requires PMK/LMK and authenticated beacon before accepting commands; old Master does not send them. |
| revised | before | NO | Revised Master sends encrypted commands and expects auth beacon handshake; old Slave has no PMK/LMK/auth state. |
| revised | revised | CONDITIONAL | Compatible only when both are provisioned with matching 16-byte PMK/LMK and channel lock/auth handshake completes. |


## Firebase authorization matrix

| Actor | Resource | Operation | Rules allow | Application performs | Notes |
|-------|----------|-----------|-------------|----------------------|-------|
| owner | RTDB telemetry/rooms/gateway | read | YES | YES | owner OR controller. |
| controller | RTDB telemetry/rooms/gateway | read/write | YES | YES | controller only. |
| owner | RTDB commands/rooms/.../tools/... | write | YES | YES | owner only; device whitelist enforced. |
| controller | RTDB commands/rooms/.../tools/... | write | NO | NO | rules require owner. |
| owner | Firestore sensorLogs | read | YES | YES | owner OR controller. |
| owner | Firestore sensorLogs | create | NO | YES | **CONTRACT DEFECT** (see below). |
| controller | Firestore sensorLogs | create | YES | UNKNOWN | No controller-side writer found in source. |
| unauthenticated | any | any | NO | N/A | denied by default. |


## History persistence ownership

Runtime components searched for Firestore `sensorLogs` writers:

- `SaveSensorLogUseCase` is instantiated in `lib/app/app_dependencies.dart` and called from `MonitoringBloc._maybeSaveSensorLog`.
- The only implementation found is `FirebaseHistoryDataSource` / `HistoryRepositoryImpl` on the Flutter side.
- No Master/ESP32 firmware code writes to Firestore `sensorLogs`.

**WRITER = Flutter owner**

Because the Flutter auth identity is `owner: true` and Firestore rules require `controller == true` for create, this is a **CONFIRMED_CONTRACT_DEFECT**.


## Heartbeat/control-gating trace

```text
Master NTP synchronized
    |
    v
sendHeartbeat() -> /device/sensorData/unix_time (epoch seconds)
    |
    v
Flutter MonitoringBloc reads heartbeatEpochSeconds
    |
    v
_eshStatusFor(heartbeat, now)
    ageSeconds = now.epochSeconds - heartbeat
    online if 0 <= ageSeconds < 60
    |
    v
canControl = isConnected && eshStatus == online
```

Failure chain (source-proven):

```text
NTP unavailable
    -> Master cannot publish valid unix_time
    -> Flutter heartbeatEpochSeconds null/stale
    -> eshStatus != online
    -> canControl = false
```

Evidence classification: CONFIRMED_STATIC.


## Slave availability trace

```text
Valid Slave ESP-NOW state packet
    |
    v
noteValidSlavePacket() updates lastSlavePacketMs
    |
    v
refreshSlaveAvailability(): online = packetSeen && (now - lastPacketMs) < 15000 ms
    |
    v
publishSlaveAvailability() -> /gateway/status/slave { online, last_seen? }
    |
    v
Flutter WatchSlaveAvailabilityUseCase / MonitoringBloc
    |
    v
canControlDevice = canControl && (not slave-owned || slaveOnline == true)
```

Slave-owned rooms: `lorong`, `kamar_1`, `kamar_2`, `dapur`. Master-owned: `teras`.

Failure chain (source-proven):

```text
ESP-NOW link down or Slave unprovisioned
    -> no valid Slave packet within 15 s
    -> slaveOnline = false
    -> canControlDevice false for lorong/kamar_1/kamar_2/dapur
    -> Teras (Master-owned) may remain controllable if canControl is true
```

Evidence classification: CONFIRMED_STATIC.


## Clock/freshness analysis

Time authorities:

| Authority | Source | Unit |
|-----------|--------|------|
| Firebase server time | RTDB `.info/serverTimeOffset` | ms offset |
| Flutter command timestamp | `DateTime.now().ms + serverTimeOffset` | ms |
| RTDB rules freshness | `now` (server ms) | ms |
| Master NTP time | `gettimeofday()` after NTP sync | s + us |
| Master freshness window | `COMMAND_MAX_AGE_MS = 15000`, `COMMAND_FUTURE_TOLERANCE_MS = 5000` | ms |

RTDB rules accept `issued_at` in `[now - 15000, now + 5000]`.
Master accepts `issued_at` in `(nowMs - 15000, nowMs + 5000]` (strict future check, non-strict stale check in code: `issuedAtMs > nowMs + 5000` rejects; `issuedAtMs <= nowMs - 15000` rejects).

Because the two freshness checks use independent clocks (Firebase server vs Master NTP), a command can pass RTDB and fail Master if clocks differ by more than the tighter tolerance. The condition is **PROVEN POSSIBLE** when NTP is skewed or unavailable.

Evidence classification: CONFIRMED_STATIC.


## Sensor validation changes

Revised Master (`src/modbus.cpp`, `src/pzem.cpp`) introduces stricter validation:

- Modbus: response length, slave ID, function code, byte count, CRC, physical ranges.
- PZEM: connected flag requires finite values in accepted ranges.

Revised Flutter (`monitoring_entity_mapper.dart`) further overrides `connected=true` to unavailable when:

- `sampled_at` is missing/null, OR
- any required physical value is out of range (voltage 80-260, current 0-100, power 0-23000, energy 0-9999.99, temperature -40-125, humidity 0-100).

This is a **SOURCE-CONFIRMED BEHAVIOR CHANGE**. Whether real hardware now appears disconnected requires hardware validation.


## Confirmed defects

- **CMD-OLD-NEW** [PROVEN_INCOMPATIBLE]: Old Flutter <-> revised Master and revised Flutter <-> old Master are incompatible because of command field-count check and required request_id/issued_at.
- **ESPNOW-MIXED** [PROVEN_INCOMPATIBLE]: Any mixed old/new Master/Slave pair is incompatible due to PMK/LMK encryption and authenticated-beacon gating.
- **AUTH-SENSORLOGS** [CONFIRMED_CONTRACT_DEFECT]: Flutter owner role attempts Firestore sensorLogs create, but Firestore rules permit create only for controller role.


## Expected provisioning requirements

Revised Master requires these local-only headers (intentional fail-closed):

- `include/firebase_config.local.h` (FIREBASE_DATABASE_URL, FIREBASE_API_KEY, FIREBASE_USER_EMAIL, FIREBASE_USER_PASSWORD)
- `include/wifi_config.local.h` (WIFI_SSID, WIFI_PASSWORD)
- `include/esp_now_keys.local.h` (ESPNOW_PMK_BYTES, ESPNOW_LMK_BYTES, 16 bytes each)

Revised Slave requires:

- `src/esp_now_keys.local.h` (ESPNOW_PMK_BYTES, ESPNOW_LMK_BYTES, 16 bytes each)

Classification: EXPECTED_PROVISIONING_FAILURE.


## Hardware-dependent unknowns

- Whether revised Modbus/PZEM parsing accepts the real installed sensors (HARDWARE_REQUIRED).
- Whether Master/Slave ESP-NOW encrypted link establishes reliably with matching PMK/LMK (HARDWARE_REQUIRED).
- Whether actual relay/dimmer hardware responds correctly to revised command schema (HARDWARE_REQUIRED).


## Live-backend-dependent unknowns

- Real Firebase Auth custom claims (`owner` vs `controller`) assignment and sign-in flow (LIVE_BACKEND_REQUIRED).
- End-to-end command latency under real network conditions and its effect on the 15 s freshness window (LIVE_BACKEND_REQUIRED).
- Firestore `sensorLogs` write behavior against the live project; local emulator/rules tests can confirm rules but not production claim configuration (LIVE_BACKEND_REQUIRED).


## Recommended follow-up issues

1. **Build/provisioning UX** - Document/copy commands for creating `.local.h` files from `.example.h`; add CI step that builds revised firmware with synthetic provisioning.
2. **Flutter <-> Master protocol migration** - Decide whether to support a version-negotiation/graceful period or require simultaneous deployment of both sides.
3. **Master <-> Slave ESP-NOW migration** - Provide provisioning procedure to ensure matching PMK/LMK; confirm channel-lock/auth handshake timing.
4. **Firebase role provisioning** - Document how to assign `owner` and `controller` custom claims and which devices need which role.
5. **Firestore sensorLogs ownership** - Resolve the Flutter-owner-writer vs controller-only-rule contradiction; either move writer to controller or update rules.
6. **Heartbeat/NTP resilience** - Add UI messaging and Master fallback behavior when NTP/time is unavailable.
7. **Command timestamp design** - Re-evaluate dual freshness checks (RTDB + Master) and clock-sensitivity risk.
8. **Slave availability semantics** - Confirm 15 s online window and status publish interval match user expectations.
9. **Sensor validation hardware check** - Validate real sensor ranges against new acceptance rules.
10. **Historical credential rotation** - Rotate any credentials previously committed to Git history.


## All findings

| Id | Classification | Description |
|----|----------------|-------------|
| BUILD-FLUTTER-BEFORE | PASS | Flutter before: pub=PASS, analyze=PASS, test=PASS, buildApk=PASS |
| BUILD-FLUTTER-REVISED | PASS | Flutter revised: pub=PASS, analyze=PASS, test=PASS, buildApk=FAIL ``` Resolving dependencies... Downloading packages...   _flutterfire_internals 1.3.35 (1.3.76 available)   async 2.13.0 (2.13.1 available)   bloc 9.0.0 (9.2.1 available)   cloud_firestore 4.17.5 (6.8.0 available)   cloud_firestore_platform_interface 6.2.5 (8.0.6 available)   cloud_firestore_web 3.12.5 (5.7.2 available)   cupertino_icons 1.0.8 (1.0.9 available)   equatable 2.0.7 (2.1.0 available)   firebase_auth 4.20.0 (6.5.7 available)   firebase_auth_platform_interface 7.3.0 (9.0.6 available)   firebase_auth_web 5.12.0 (6.2.6 available)   firebase_core 2.32.0 (4.13.0 available)   firebase_core_platform_interface 5.4.0 (8.1.0 available)   firebase_core_web 2.17.5 (3.10.0 available)   firebase_database 10.5.7 (12.4.7 available)   firebase_database_platform_interface 0.2.5+35 (0.4.0+6 available)   firebase_database_web 0.2.5+7 (0.2.7+13 available)   fl_chart 0.70.2 (1.2.0 available)   flutter_lints 5.0.0 (6.0.0 available)   go_router 15.2.3 (retracted, 17.5.0 available)   intl 0.20.2 (0.20.3 available)   lints 5.1.1 (6.1.0 available)   matcher 0.12.19 (0.12.20 available)   material_color_utilities 0.13.0 (0.13.1 available)   meta 1.18.0 (1.19.0 available)   provider 6.1.5 (6.1.5+1 available)   source_span 1.10.1 (1.10.2 available)   syncfusion_flutter_core 28.2.12 (34.2.3 available)   syncfusion_flutter_gauges 28.2.12 (34.2.3 available)   test_api 0.7.11 (0.7.13 available)   vector_math 2.2.0 (2.4.2 available)   vm_service 15.0.0 (15.2.0 available)   web 0.5.1 (1.1.1 available) Got dependencies! 33 packages have newer versions incompatible with dependency constraints. Try `flutter pub outdated` for more information. Running Gradle task 'assembleDebug'...                           Running Gradle task 'assembleDebug'...                             53.2s  Warning: Flutter support for your project's Gradle version (8.12.0) will soon be dropped. Please upgrade your Gradle version to a version of at least 8.14.0 soon. Alternatively, use the flag "--android-skip-build-dependency ... (truncated) ``` |
| BUILD-MASTER-REVISED | EXPECTED_PROVISIONING_FAILURE | Revised Master requires local provisioning files (firebase_config.local.h, wifi_config.local.h, esp_now_keys.local.h). PlatformIO not available for compile verification. |
| BUILD-SLAVE-REVISED | EXPECTED_PROVISIONING_FAILURE | Revised Slave requires local provisioning file src/esp_now_keys.local.h. PlatformIO not available for compile verification. |
| CMD-OLD-NEW | PROVEN_INCOMPATIBLE | Old Flutter <-> revised Master and revised Flutter <-> old Master are incompatible because of command field-count check and required request_id/issued_at. |
| ESPNOW-MIXED | PROVEN_INCOMPATIBLE | Any mixed old/new Master/Slave pair is incompatible due to PMK/LMK encryption and authenticated-beacon gating. |
| AUTH-SENSORLOGS | CONFIRMED_CONTRACT_DEFECT | Flutter owner role attempts Firestore sensorLogs create, but Firestore rules permit create only for controller role. |
| HB-GATING | CONFIRMED_STATIC | Master heartbeat failure disables Flutter control even when Firebase connectivity exists. |
| SLAVE-GATING | CONFIRMED_STATIC | Master/Slave link failure disables Slave-owned rooms while Master-owned control may remain available. |
| CLOCK-SKEW | CONFIRMED_STATIC | A command may pass RTDB freshness validation and still fail Master freshness validation if Firebase server time and Master NTP time disagree sufficiently. |
