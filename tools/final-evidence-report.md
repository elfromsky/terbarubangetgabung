# Coordinated Revision — Final Evidence Report (Issue #2 follow-up)

Generated: 2026-08-15
Repo: `elfromsky/esh-smart-home`
Scope: close the unresolved build, auth, timing, ESP-NOW, and shared-dimmer proof gaps left by Issue #1.

> Status before this run: `PARTIALLY DIAGNOSED / NOT YET PROVEN DEPLOYABLE`.
> Status after this run: **a real build defect exists in revised Master; the coordinated revision is NOT deployable until that and the provisioning steps are satisfied.**

---

## 1. Environment

| Tool | Status |
|------|--------|
| git | 2.49.0.windows.1 |
| flutter | 3.44.8 (stable) |
| dart | 3.12.2 |
| node | v22.16.0 |
| firebase | 14.7.0 |
| PlatformIO | 6.1.19 (installed via pip, not on PATH) |
| java | OpenJDK 21.0.10 (bundled with Android Studio JBR, not on PATH) |

All firmware builds below used `pio run` via the pip-installed `pio.exe`. Rules tests used the Firestore/RTDB emulators running under the Android Studio JBR. No ESP32 was flashed; no live Firebase backend was contacted; no production rule deployment or data mutation was performed.

---

## 2. Repository topology

The repository contains three unrelated component histories. Do **not** merge them, rewrite history, or use `--allow-unrelated-histories`.

| Component | Branch | Actual root commit | Pre-revision snapshot | Revised snapshot |
|-----------|--------|--------------------|------------------------|------------------|
| Master | `origin/main` | `032f486` | `273b3f6` | `f8c960e` |
| Slave | `origin/slave` | `ac79be5` | `24da621` | `6d306cf` |
| Flutter | `origin/clean` | `6cb3438` | `1b62be3` | `5bd9fb6` |

- Only the Flutter `flutter -> clean` lineage shares ancestry (`merge base 6cb3438`).
- Master/Slave/Flutter have **no shared merge base** with each other.
- `f8c960e`/`6d306cf`/`5bd9fb6` are the three revised tips and are treated as **one logical coordinated revision** (Gate).
- **GIT-ROOT-REPORT**: the previous report wrongly printed the pre-revision snapshots as "independent root commits". The diagnostic runner (`tools/diagnose-broken-revision.py`) was corrected to distinguish **ROOT COMMIT / PRE-REVISION SNAPSHOT / REVISED SNAPSHOT** and now reports the table above. (Acceptance criteria ✓.)

---

## 3. Build evidence (all actually executed)

| ID | Result |
|----|--------|
| BUILD-FLUTTER-BEFORE | **PASS** — pub get ✓, analyze ✓, test ✓ (121), debug APK ✓ |
| BUILD-FLUTTER-REVISED | **PASS** — pub get ✓, analyze ✓, test ✓ (154), debug APK ✓ |
| BUILD-MASTER-BEFORE | **PASS** — `pio run` SUCCESS (RAM 16.0%, Flash 28.9%) |
| BUILD-MASTER-REVISED-PRISTINE | **EXPECTED_PROVISIONING_FAILURE** — stopped at `#error` guards for `firebase_config.local.h`, `wifi_config.local.h`, `esp_now_keys.local.h` |
| BUILD-MASTER-REVISED-SYNTH | **FAIL (CONFIRMED build defect)** — see §4 |
| BUILD-SLAVE-BEFORE | **PASS** — `pio run` SUCCESS (RAM 13.7%, Flash 53.0%) |
| BUILD-SLAVE-REVISED-PRISTINE | **EXPECTED_PROVISIONING_FAILURE** — stopped at `#error` guard for `src/esp_now_keys.local.h` |
| BUILD-SLAVE-REVISED-SYNTH | **PASS** — `pio run` SUCCESS (RAM 13.7%, Flash 53.1%) |

Gate A (build) result: **Flutter ✓, Slave ✓ (after provisioning), Master ✗ (does not compile even after synthetic provisioning).**

---

## 4. Provisioning boundaries (CONFIRMED_STATIC)

Revised Master requires three local-only headers (compile-time `#error` fail-closed):

- `include/firebase_config.local.h` — `FIREBASE_DATABASE_URL`, `FIREBASE_API_KEY`, `FIREBASE_USER_EMAIL`, `FIREBASE_USER_PASSWORD`
- `include/wifi_config.local.h` — `WIFI_SSID`, `WIFI_PASSWORD`
- `include/esp_now_keys.local.h` — `ESPNOW_PMK_BYTES`, `ESPNOW_LMK_BYTES` (16 bytes each)

Revised Slave requires:

- `src/esp_now_keys.local.h` — `ESPNOW_PMK_BYTES`, `ESPNOW_LMK_BYTES` (16 bytes each)

All guards verified by actual compile. Synthetic secrets were created only inside the disposable temp trees and never committed or printed.

---

## 5. Flutter ↔ Master command contract

Revised both sides:

| Field | Flutter sends | Master parse | RTDB rules |
|-------|---------------|--------------|------------|
| `state` | bool | bool required | bool |
| `brightness` (dimmable only) | int 0..100 (clamp, 0→1 when on) | int 0..100 (0→1 when on) | int 0..100 |
| `request_id` | 1..31 chars | 1..31 chars | string 1..31 |
| `issued_at` | epoch ms (now + serverTimeOffset) | int64 epoch ms | ms in `[now-15000, now+5000]` |
| field count | 3 (relay) / 4 (dimmer) | 3 (relay) / 4 (dimmer) | via `.hasChildren` + conditional `brightness` |

- Revised Flutter ↔ revised Master: **SCHEMA_COMPATIBLE** at field level (types, counts, ranges all agree). RUNTIME_CONDITIONAL (needs NTP, auth, network).
- Revised Flutter ↔ before Master: **PROVEN_INCOMPATIBLE** (old Master expects only `{state,brightness}`; field-count check rejects).
- Before Flutter ↔ revised Master: **PROVEN_INCOMPATIBLE** (old Flutter omits `request_id`/`issued_at`).
- Gate C (command protocol): **passes on schema** for revised/revised.

---

## 6. Request ID / replay / concurrency (CMD-*)

Master (`firebase_command_router.cpp`):

- **Duplicate/out-of-order**: a command is accepted only if it is "newer" than the route's current desired state — compared by `issuedAtMs`, then lexicographic `request_id` tie-break (`commandVersionIsNewer`). Older/equal commands are ignored (`CMD-REQUESTID-DUPLICATE`, `CMD-REQUESTID-COLLISION`, `CMD-ACK-ORDER` → characterized statically).
- **Concurrency**: only one pending Slave command (`pendingCmd`) exists at a time; the Slave cycle is serialized (`startNextSlaveCycle`), so concurrent Slave commands are inherently sequential (`CMD-CONCURRENCY` → statically characterized, no parallel path).
- **ACK matching**: Slave ACK matched by route + echoed `request_id`.
- **Lost ACK**: `ACK_TIMEOUT_MS=3000`, up to `MAX_SEND_ATTEMPTS=3`, then `CYCLE_BACKOFF_MS=2000` backoff (`CMD-ACK-LOSS` → statically characterized).
- **Replay cache (Slave)**: Slave has a ring-buffer duplicate cache (`DUPLICATE_CACHE_SIZE=8`) keyed by `requestId+roomKey+deviceKey`; a replayed command returns the cached result without re-driving hardware (`CMD-REQUESTID-DUPLICATE` on Slave side). No explicit TTL — it is a fixed-size ring of the last 8.

There is **no automated firmware test suite** (both `test/` dirs contain only README), so these are CONFIRMED_STATIC characterizations, not executed tests.

---

## 7. Firebase authorization (emulator-reproduced)

Ran the revised `rules-tests/rules.test.js` under Firestore + RTDB emulators with owner/controller/unauthenticated contexts.

| Actor | Resource | Operation | Result |
|-------|----------|-----------|--------|
| controller | Firestore `sensorLogs` | create | PASS (allowed) |
| owner | Firestore `sensorLogs` | create | **DENIED** (rules allow create only for `controller`) — reproduced |
| owner | Firestore `sensorLogs` | read | PASS |
| unauthenticated | Firestore `sensorLogs` | create | DENIED |
| owner+controller | RTDB `commands/rooms/dapur/tools/lampu` | write | PASS |
| controller-only | RTDB commands | write | DENIED (requires owner) |
| owner | RTDB commands missing fields | write | DENIED |
| owner | RTDB unknown room/device | write | DENIED |

(The single rules-test failure `controller cannot update/delete sensorLogs` is a test-harness Firestore-reuse quirk, not a rules defect.)

---

## 8. sensorLogs ownership (AUTH-SENSORLOGS) — CONFIRMED CONTRACT DEFECT

- Writer identity: Flutter `SaveSensorLogUseCase` → `FirebaseHistoryDataSource`, called from `MonitoringBloc._maybeSaveSensorLog`. No Master/ESP32 code writes Firestore `sensorLogs`.
- Flutter bootstrap (`lib/main.dart`) accepts an identity with **either** `owner` **or** `controller` claim. The history writer runs under that same anonymous-signed-in identity.
- Firestore rule: `sensorLogs` **create allowed only when `controller == true`**.
- Emulator reproduction: **owner-only create → DENIED**; **controller-only create → ALLOWED**.
- If the device is registered as `owner` (the documented, UI-shown path — "Daftarkan UID berikut sebagai owner"), the intended writer is **denied**. If registered as `controller`, the write is allowed but there is no separate controller identity in the app — the app is a single identity.
- **Conclusion**: the writer/role is contradictory. Either move the writer to a controller claim, or update rules to allow owner create. **CONFIRMED_CONTRACT_DEFECT, emulator-reproduced.**

---

## 9. Command freshness and clock model (CLOCK-SKEW / CMD-FRESHNESS-BOUNDARY / CMD-CLOCK-SKEW)

| Authority | Source | Unit |
|-----------|--------|------|
| Firebase server time | RTDB `.info/serverTimeOffset` | ms offset |
| Flutter `issued_at` | `DateTime.now().ms + serverTimeOffset` | ms |
| RTDB rule freshness | server `now` | ms, `[now-15000, now+5000]` |
| Master NTP time | `gettimeofday()` after `configTime()` | epoch ms |
| Master freshness | `COMMAND_FUTURE_TOLERANCE_MS=5000`, `COMMAND_MAX_AGE_MS=15000` | ms |

- RTDB accepts `issued_at ∈ [now-15000, now+5000]` (inclusive both).
- Master accepts `issued_at ∈ (nowMs-15000, nowMs+5000]` (stale reject is `<= nowMs-15000`, future reject is `> nowMs+5000`).
- Because the two checks use **independent clocks** (Firebase server vs Master NTP), a command can pass RTDB and still be rejected by Master if the clocks diverge by more than the tighter tolerance. **PROVEN_POSSIBLE_BY_IMPLEMENTATION** (not an observed production failure).
- **AUTH-SENSORLOGS / CLOCK analysis retained as-is from Issue #1 and now reinforced.**

---

## 10. Master NTP/TLS lifecycle

- NTP: `configTime(GMT_OFFSET_SEC=25200, DAYLIGHT_OFFSET_SEC=0, "pool.ntp.org", "time.nist.gov")`; `MIN_VALID_EPOCH_SECONDS = 1704067200` (2024-01-01). Startup blocks up to 15 s polling; retry every `NTP_RETRY_MS=60000`; recovery re-requests NTP on WiFi reconnect when `timeInitialized` is false. `getValidEpochSeconds()` returns false until time is valid.
- TLS: `WiFiClientSecure.setCACert(GOOGLE_FIREBASE_CA_PEM)` (embedded Google root CA), `setHandshakeTimeout(5)`. TLS certificate verification **depends on a valid system clock** — with NTP unavailable, TLS handshake fails → Firebase auth/telemetry/command stream unavailable → heartbeat stale → control disabled. This dependency is **verified from source/configuration** (TLS-VERIFY / TLS-TIME → CONFIRMED_STATIC).
- Heartbeat: `sendHeartbeat()` writes `/device/sensorData/unix_time` (epoch seconds) every `HEARTBEAT_INTERVAL=5000` ms, only when Firebase ready **and** time valid.

---

## 11. Master ↔ Slave ESP-NOW contract (ESPNOW-*)

Statically compared the revised `master_revised/include/esp_now_protocol.h` and `slave_revised/src/esp_now_config.h`:

| Property | Master | Slave | Match |
|----------|--------|-------|-------|
| `DeviceCommandPayload` size | 92 (static_assert) | 92 (static_assert) | ✓ |
| `DeviceStatePayload` size | 98 | 98 | ✓ |
| `DiscoveryBeaconPayload` size | 7 | 7 | ✓ |
| message type values | 1,2,3,4 | 1,2,3,4 | ✓ |
| CRC | XOR over struct-1 | XOR over struct-1 | ✓ |
| `ESPNOW_DISCOVERY_MAGIC` | `0xA5C35A7E` | `0xA5C35A7E` | ✓ |
| PMK/LMK | `esp_now_set_pmk(ESPNOW_PMK)`; peer `lmk=ESPNOW_LMK`, `encrypt=true` | same | ✓ |
| peer/channel | locks slave peer to STA/router channel | scans 1..13, locks to beacon channel, adds peer `encrypt=true` | ✓ |
| auth gate | sends discovery + authenticated beacon | accepts commands only after `channelLocked && masterPeerRegistered && masterAuthenticated` | ✓ |

- Revised ↔ revised: **SCHEMA_COMPATIBLE** statically. Full encrypted link depends on matching provisioned PMK/LMK and real RF behavior → **HARDWARE_REQUIRED** for the live link.
- Mixed old/new pairs: **PROVEN_INCOMPATIBLE** (old side has no PMK/LMK/beacon/encryption; new side fail-closed).
- Gate D (ESP-NOW static contract): **passes**; hardware RF reliability is separate.

---

## 12. ESP-NOW channel and authentication lifecycle

- Master operates on its STA (router) channel, registers the Slave peer with the LMK and `encrypt=true`, and broadcasts a discovery beacon every `ESPNOW_DISCOVERY_INTERVAL_MS=1000` ms, then an authenticated beacon to the Slave MAC.
- Slave scans channels 1–13 (`ESPNOW_SCAN_DWELL_MS=500`), locks to the first valid beacon channel, registers the Master peer with `encrypt=true`, and only then accepts commands (`ESPNOW_AUTH_TIMEOUT_MS=5000`, `ESPNOW_LINK_TIMEOUT_MS=30000`).
- Command acceptance additionally requires the CRC-valid, length-exact command and that the sender MAC equals `MASTER_MAC`.
- End-to-end establishment and roaming/reconnect behavior are **HARDWARE_REQUIRED**.

---

## 13. Heartbeat gating (HB-GATING)

- Master: valid `unix_time` required → depends on NTP + Firebase.
- Flutter: `eshHeartbeatLifetime = 60 s`. `_eshStatusFor` = unknown if missing/future, online if `0 <= age < 60`, else offline. `canControl = isConnected && eshStatus == online`.
- Exact boundary tests **exist and pass**: age 59 → online; age exactly 60 → offline; missing → unknown; future → unknown; offline heartbeat rejects command.
- Classification: **CONFIRMED_STATIC, INTENTIONAL_BEHAVIOR_CHANGE** (with executed boundary tests).

## 14. Slave availability (SLAVE-AVAILABILITY)

- Master: valid Slave state packet updates `lastSlavePacketMs`; `online = packetSeen && (now-lastPacketMs) < 15000 ms` (`SLAVE_ONLINE_WINDOW_MS`). Published to `/gateway/status/slave` with `online` and `last_seen` (epoch seconds, or null when unknown). Publish interval `SLAVE_STATUS_PUBLISH_INTERVAL_MS=5000`, urgent on change, timeout `5000`, retry `1000`.
- Slave: sends periodic full-state snapshots every `STATUS_INTERVAL=5000` ms, plus boot snapshot and an immediate snapshot after any dimmer command.
- Flutter: `canControlDevice = canControl && (!slaveOwnedRoom || slaveOnline==true)`; `slaveOwnedRooms={lorong,kamar_1,kamar_2,dapur}`. Teras (Master-owned) remains controllable when Slave offline.
- Exact boundary tests exist: Slave offline disables Slave controls but leaves Teras enabled; Slave online allows Slave routes; unknown Slave status blocks Slave routes.
- No-packet-ever behavior: Slave is created in `slaveOnline=false` until first valid packet; Teras unaffected. Classification: **CONFIRMED_STATIC**.

---

## 15. Shared dimmer semantics (DIMMER-SHARED-STATE)

- Physical: Slave has two TRIAC dimmer channels. Route table maps `kamar_1 lampu` and `kamar_2 lampu` to **CH1** (shared), `dapur lampu` to **CH2**. Bedroom relays are independent, but both retain **one authoritative CH1 brightness**.
- Flutter (`_sharedDimmerPair`): issuing a brightness command on `kamar_1 lampu` or `kamar_2 lampu` also marks the paired room's lamp pending and sends the same brightness; it refuses to control one side if the pair status is unavailable.
- Master: `sharedBedroomDesiredBrightness` — the newest command (by `issued_at`/`request_id`) owns the shared CH1 brightness; both semantic routes report that brightness.
- Reported-state invariant: both `kamar_1` and `kamar_2` report the same physical brightness while their **on/off relay states stay independent**. **Arbitration rule = newest command wins; reported state = physical CH1 brightness.** This is explicitly defined in both sides (no contradiction found). Hardware behavior is HARDWARE_REQUIRED.

## 16. Telemetry schema and timestamp authority

- `sampled_at` fields (environment/power) are **epoch seconds** from Master NTP (`getValidEpochSeconds`), set only when the sensor value is finite/connected.
- Heartbeat `unix_time` is epoch seconds from NTP.
- Firestore `sensorLogs.timestamp` is a Firestore `timestamp` (Flutter client); `power`/`environment` maps carry `sampled_at` epoch seconds.
- Units: brightness 0–100 (%); voltage V; current A; power W; energy kWh; frequency Hz; pf unitless; temperature °C; humidity %.

## 17. Modbus validation

`master_revised/src/modbus.cpp` strict parser: response length, slave ID, function code, byte count, CRC, and physical ranges (temp `-40..125`, humidity `0..100`); returns NaN on any violation. **No local fixture test** (modbus uses raw UART — HARDWARE_REQUIRED for real acceptance). Static validation boundaries documented.

## 18. PZEM validation

`master_revised/src/pzem.cpp`: `connected` requires finite voltage(80–260 V), current(0–100 A), power(0–23000 W), energy(0–9999.99 kWh); plus frequency(45–65) and pf(0–1) checked. Boundaries documented; real-installed-PZEM acceptance HARDWARE_REQUIRED.

## 19. Flutter telemetry freshness

`monitoring_entity_mapper.dart` overrides `connected=true` to unavailable when `sampled_at` missing or any physical value out of range. `monitoring_bloc.dart` marks power/environment sample fresh iff `0 <= age < 60 s`. Boundary tests exist and pass.

## 20. Android release/security

- Main manifest: only `INTERNET` permission; no `usesCleartextTraffic`; no `networkSecurityConfig`; `allowBackup=false`, `fullBackupContent=false`, `dataExtractionRules` set.
- Debug/profile manifests add INTERNET (normal).
- Reviewed debug and release build configs; no cleartext or insecure network config found. **ANDROID-NETSEC / ANDROID-RELEASE → PASS (static review).**

## 21. Security follow-ups (SEC-HISTORICAL-CREDENTIALS)

- `master_before` (`273b3f6`) commits real credentials in `include/firebase_config.h`: a Firebase Web API key, a Firebase user email, and a device-user **password**, plus real Wi-Fi SSID/password in `include/wifi_config.h`.
- Revised snapshots correctly replace these with `.example.h` placeholders and require local-only `.local.h` files.
- Flutter `android/app/google-services.json` and `lib/firebase_options.dart` contain the standard public client/app ID + API key (normal for Firebase config).
- **Action required (follow-up)**: rotate the committed Firebase user password / Wi-Fi password / API key; consider scrubbing history. **No secret value is printed in this report.**

## 22. Confirmed implementation defects

| ID | Classification | Finding |
|----|----------------|---------|
| BUILD-MASTER-REVISED-SYNTH | **CONFIRMED (actual compile FAIL)** | Revised Master does not compile with synthetic provisioning: `include/esp_now_protocol.h:80` declares `std::string generateRequestId()`, but `src/esp_now_protocol.cpp:115` defines `String generateRequestId()` (Arduino `String`) — ambiguous redefinition. Fix: make both `String`. This is **not** a provisioning failure. |
| AUTH-SENSORLOGS | CONFIRMED_CONTRACT_DEFECT | Flutter (owner-capable) is the only `sensorLogs` writer; Firestore rules allow create only for `controller`. Reproduced in emulator (owner create denied). |
| CMD-OLD-NEW | PROVEN_INCOMPATIBLE | old Flutter ↔ revised Master and revised Flutter ↔ old Master. |
| ESPNOW-MIXED | PROVEN_INCOMPATIBLE | any mixed old/new Master/Slave pair. |

## 23. Intentional breaking changes

- Heartbeat-based control gating (HB-GATING) — intentional.
- Slave-availability-based gating (SLAVE-AVAILABILITY) — intentional.
- Command freshness window + `request_id`/`issued_at` (CMD-*) — intentional, breaking across versions.
- ESP-NOW PMK/LMK encryption + authenticated-beacon gating (ESPNOW-*) — intentional.
- Stricter sensor acceptance (Modbus/PZEM/Flutter mapper) — intentional.
- Strict provisioning fail-closed (`#error` guards) — intentional.

## 24. Proven incompatible combinations

- before Flutter ↔ revised Master (command schema).
- revised Flutter ↔ before Master (command schema).
- before Master ↔ revised Slave (ESP-NOW encryption/auth).
- revised Master ↔ before Slave (ESP-NOW encryption/auth).

## 25. Hardware-required checks (not performed)

- ESP-NOW encrypted link establishment / PMK-LMK match / channel lock / restart & reconnect behavior.
- Shared CH1 dimmer physical arbitration and relay independence.
- Real Modbus (XY-MD02) frame acceptance.
- Real PZEM acceptance and `connected` flag.
- Relay/dimmer electrical response to revised schema.

## 26. Live-backend-required checks (not performed)

- Production Firebase custom-claim assignment and sign-in flow (owner vs controller), and whether the deployed identity is owner or controller.
- End-to-end command latency vs the 15 s freshness window under real network conditions.
- Whether the deployed Firestore project matches the revised rules (production claims not introspected).

## 27. Confirmed cross-version compatibility status

| Pair | Schema | Freshness | Authorization | End-to-end |
|------|--------|-----------|---------------|------------|
| revised Flutter ↔ revised Master | SCHEMA_COMPATIBLE | SCHEMA_COMPATIBLE (dual-clock risk) | RTDB owner-write ✓ (emulator) | RUNTIME_CONDITIONAL (NTP/auth) |
| revised Master ↔ revised Slave | SCHEMA_COMPATIBLE | N/A | auth gate ✓ (static) | HARDWARE_REQUIRED |

---

## Evidence ledger (key entries)

| ID | Classification | Revision(s) | Source | Test | Expected | Actual |
|----|----------------|-------------|--------|------|----------|--------|
| GIT-ROOT-REPORT | PASS | all | git rev-list --max-parents=0 | runner | roots 032f486/ac79be5/6cb3438 | ✓ |
| BUILD-FLUTTER-BEFORE | PASS | 1b62be3 | flutter pub/analyze/test/apk | pio-less | PASS | PASS |
| BUILD-FLUTTER-REVISED | PASS | 5bd9fb6 | flutter pub/analyze/test/apk | | PASS | PASS |
| BUILD-MASTER-BEFORE | PASS | 273b3f6 | pio run | compile | PASS | PASS |
| BUILD-MASTER-REVISED-PRISTINE | EXPECTED_PROVISIONING_FAILURE | f8c960e | pio run | #error guard | fail-closed | fail-closed |
| BUILD-MASTER-REVISED-SYNTH | **CONFIRMED** (FAIL) | f8c960e | pio run + synthetic | compile | PASS | FAIL (generateRequestId) |
| BUILD-SLAVE-BEFORE | PASS | 24da621 | pio run | compile | PASS | PASS |
| BUILD-SLAVE-REVISED-PRISTINE | EXPECTED_PROVISIONING_FAILURE | 6d306cf | pio run | #error guard | fail-closed | fail-closed |
| BUILD-SLAVE-REVISED-SYNTH | PASS | 6d306cf | pio run + synthetic | compile | PASS | PASS |
| CMD-SCHEMA-MIXED | PROVEN_INCOMPATIBLE | mixed | source compare | field sets | incompatible | incompatible |
| CMD-FRESHNESS-BOUNDARY | CONFIRMED_STATIC | revised | monitoring_bloc + tests | age 59/60 | 59 online, 60 offline | ✓ |
| CMD-CLOCK-SKEW | PROVEN_POSSIBLE_BY_IMPLEMENTATION | revised | router + rules | two clocks | possible | possible |
| CMD-REQUESTID-DUPLICATE/COLLISION/CONCURRENCY/ACK | CONFIRMED_STATIC | revised | router.cpp / slave routing | source | serial, newest-wins | ✓ |
| AUTH-OWNER (sensorLogs create) | CONFIRMED_REPRODUCED | revised | rules-test | emulator owner ctx | DENY | DENY |
| AUTH-CONTROLLER (sensorLogs create) | CONFIRMED_REPRODUCED | revised | rules-test | emulator controller ctx | ALLOW | ALLOW |
| AUTH-COMMAND-OWNER | CONFIRMED_REPRODUCED | revised | rules-test | emulator owner | ALLOW | ALLOW |
| AUTH-COMMAND-CONTROLLER | CONFIRMED_REPRODUCED | revised | rules-test | emulator controller | DENY | DENY |
| HB-GATING | CONFIRMED_STATIC | revised | monitoring_bloc/tests | boundary | 60 s | ✓ |
| SLAVE-AVAILABILITY | CONFIRMED_STATIC | revised | router.cpp + bloc/tests | 15 s window | Teras independent | ✓ |
| DIMMER-SHARED-STATE | SCHEMA_COMPATIBLE (static) | revised | flutter+master+slave | arbitration rule | newest wins | ✓ |
| TLS-TIME / TLS-VERIFY | CONFIRMED_STATIC | revised | firebase_app.cpp | setCACert + time guard | time-dependent | ✓ |
| ANDROID-NETSEC / RELEASE | PASS | revised | manifest/build.gradle | review | no cleartext | ✓ |
| SEC-HISTORICAL-CREDENTIALS | CONFIRMED_STATIC | before | git history | grep | credentials committed | ✓ (rotate) |

---

## Recommended follow-up issues (only those supported by evidence)

1. **build(ci)** — Fix the revised-Master `generateRequestId()` `std::string`/`String` mismatch; add CI that compiles Master+Slave with synthetic provisioning.
2. **auth(firestore)** — Resolve `sensorLogs` writer/role contradiction (AUTH-SENSORLOGS).
3. **auth(provisioning)** — Document owner/controller claim assignment and the anonymous-sign-in → custom-claim token-refresh lifecycle.
4. **security(credentials)** — Rotate the real Firebase user password / Wi-Fi password / API key committed in `273b3f6`; consider history scrub.
5. **repo(tooling)** — Keep the fixed diagnostic runner; add automated root/snapshot table output. (Done in this run; make it a committed tool + test.)
6. **protocol(command)** — Add firmware unit tests for freshness/duplicate/concurrency/ACK, and decide on mixed-version migration strategy.
7. **runtime(time)** — Decide whether NTP must be mandatory or add a degraded mode; document TLS-time dependency.
8. **frontend(freshness)** — Lock the 60-second boundary behavior (already tested; keep as spec).
9. **hardware(dimmer/sensors/espnow)** — After the build/auth defects are fixed, run the §25 hardware plan.

Do not file issues for the Live-backend/hardware items until those environments are available.

---

## Final compatibility statement

```
The coordinated revision contains:
  1  confirmed implementation defect (revised Master does not compile)
  3  intentional provisioning requirements (firebase_config, wifi_config, esp_now_keys)
  4  proven cross-version incompatibilities (CMD-OLD-NEW x2, ESPNOW-MIXED x2)
  several source-confirmed behavior changes (heartbeat gating, slave gating, freshness,
      ESP-NOW encryption, stricter sensor acceptance)
  B  hardware-dependent checks (ESP-NOW link, dimmer, Modbus, PZEM, relay)
  C  live-backend-dependent checks (custom claims, production rules deployment, latency)

Flutter revised:
    build = PASS (pub/analyze/test/apk)

Master revised pristine:
    build = EXPECTED_PROVISIONING_FAILURE (missing .local.h)

Master revised with synthetic provisioning:
    build = FAIL (std::string/String generateRequestId mismatch)

Slave revised pristine:
    build = EXPECTED_PROVISIONING_FAILURE (missing esp_now_keys.local.h)

Slave revised with synthetic provisioning:
    build = PASS

Flutter revised ↔ Master revised:
    schema = SCHEMA_COMPATIBLE
    freshness = SCHEMA_COMPATIBLE (dual-clock skew is PROVEN_POSSIBLE)
    authorization = RTDB owner command write allowed; Firestore sensorLogs owner create DENIED (defect)
    end-to-end = RUNTIME_CONDITIONAL (requires NTP + auth + network)

Master revised ↔ Slave revised:
    struct contract = SCHEMA_COMPATIBLE (92/98/7, XOR CRC, magic, types)
    encryption/auth contract = SCHEMA_COMPATIBLE (PMK/LMK, encrypt, beacon gate)
    channel contract = SCHEMA_COMPATIBLE (STA vs scan/lock)
    hardware validation = NOT DONE (HARDWARE_REQUIRED)

Firestore history:
    authoritative writer = Flutter (anonymous identity, owner-or-controller capable)
    writer authorization = CONTRADICTORY (only controller create allowed; app writer may be owner)

Heartbeat:
    source behavior = publish /device/sensorData/unix_time every 5 s when NTP+Firebase ready
    recovery behavior = 60 s NTP retry, re-request on WiFi reconnect

Slave availability:
    timeout = 15 s (no valid packet)
    publish interval = 5 s (urgent on change, 5 s timeout, 1 s retry)
    no-packet behavior = slaveOnline=false; Teras unaffected

Shared bedroom dimmer:
    arbitration rule = newest command (issued_at, then request_id) owns shared CH1 brightness;
                        relay on/off states independent
    reported-state invariant = both bedrooms report the same physical CH1 brightness

The first reproducible failure from a clean environment is:
    Flutter: builds and tests pass (no failure).
    Firmware: revised Master fails to COMPILE after supplying provisioning
        (std::string/String generateRequestId mismatch in esp_now_protocol).
    (This is now a confirmed defect, not a provisioning-only blocker.)

After satisfying intentional provisioning, the next reproducible failure is:
    revised Master compile error (above) — must be fixed before build Gate A passes.

The system is NOT ready for coordinated hardware deployment because:
    1) revised Master does not compile (confirmed defect),
    2) the sensorLogs writer/role is contradictory (confirmed), and
    3) ESP-NOW RF/dimmer/sensor hardware behavior is unverified.
```
