# ESH Real-Hardware Acceptance Runbook

Issue #26 — `test(hardware): validate PRD acceptance criteria on real ESH hardware`.

This document is the **reusable procedure** for the final real-hardware
acceptance gate. It is separate from the automated/deterministic gates that CI
already runs (Flutter analyze/test/build, Master/Slave firmware build,
Firebase rules emulator tests, cross-component contract tests, command-lifecycle
E2E, offline/freshness integration). Those gates prove the software contracts;
this runbook proves the **physical** system.

## 1. Purpose

Deterministic CI and emulator tests prove, by source inspection and simulation,
that the coordinated software is internally consistent. They cannot prove that:

- the PZEM-004T-v30 actually measures real mains voltage/current/power and that
  the `energy` value is numerically in **kWh** (a historical Wh/kWh defect, Issue #19);
- the XY-MD02 / SHT20 actually reports plausible temperature/humidity over RS-485;
- the 10 relay channels and 2 RobotDyn AC dimmer channels physically actuate the
  correct loads;
- ESP-NOW actually carries encrypted commands from Master to Slave and ACKs back;
- a real network outage leaves hardware in its last state instead of toggling it;
- the real APK against real Firebase shows correct units and classifications.

This runbook is the only gate that can convert those items from "source-inspected"
to "observed on real hardware".

## 2. Scope

### System under test

```text
Flutter APK (owner principal)
   |
   v
Real Firebase (RTDB rules + Firestore rules)
   |
   v
ESP32-S3 Master (Wi-Fi + Firebase + NTP)
   | ESP-NOW (encrypted, PMK/LMK)
   v
ESP32-S3 Slave
   |
   +--> 8 relay channels (active-low, NC-COM wiring)
   +--> 2 RobotDyn AC dimmer channels (zero-cross)

Master   +--> PZEM-004T-v30 (UART1: V/A/W/kWh/Hz/PF)
         +--> XY-MD02 / SHT20 (RS-485 Modbus: temperature/humidity)
         +--> heartbeat (/device/sensorData/unix_time)
         +--> /gateway/status/slave (module availability)
```

### Authoritative device table (from `contracts/command-protocol.md` and
`firmware/master/src/firebase_command_router.cpp`, `firmware/slave/src/relay.h`,
`firmware/slave/src/dimmer.h`)

10 routes (7 relay-only + 3 dimmer lamps). Physical channel mapping:

| Room | Device | Owner | Kind | Physical |
|------|--------|-------|------|----------|
| `teras` | `lampu` | Master | relay | Master relay pin 13 |
| `teras` | `sanyo` | Master | relay | Master relay pin 14 |
| `lorong` | `stop_kontak` | Slave | relay | Slave RELAY_1 (pin 4) |
| `lorong` | `blower` | Slave | relay | Slave RELAY_2 (pin 5) |
| `kamar_1` | `stop_kontak` | Slave | relay | Slave RELAY_3 (pin 6) |
| `kamar_1` | `lampu` | Slave | dimmer | RELAY_4 (pin 7) + CH1 (pin 16) |
| `kamar_2` | `stop_kontak` | Slave | relay | Slave RELAY_5 (pin 8) |
| `kamar_2` | `lampu` | Slave | dimmer | RELAY_6 (pin 9) + CH1 (pin 16) |
| `dapur` | `lampu` | Slave | dimmer | RELAY_7 (pin 10) + CH2 (pin 15) |
| `dapur` | `blower` | Slave | relay | Slave RELAY_8 (pin 11) |

- **10 physical relay channels** = 2 Master + 8 Slave.
- **2 physical dimmer channels** = CH1 (shared `kamar_1/lampu` + `kamar_2/lampu`)
  and CH2 (dedicated `dapur/lampu`). Each dimmer lamp also has its own relay for
  independent ON/OFF.
- Master devices are controlled directly; Slave devices go over ESP-NOW.

### Environment sensors

- **Power**: PZEM-004T-v30 via UART1. Fields: voltage (V, 1 dp), current (A,
  2 dp), power (W, 1 dp), energy (kWh, 3 dp), frequency (Hz, 1 dp), pf (2 dp).
  Pins `PZEM_RX_PIN`/`PZEM_TX_PIN` (see `firmware/master/src/pzem.cpp`).
- **Environment**: XY-MD02 / SHT20 via RS-485 Modbus, slave id `0x01`, function
  `0x04` (read input registers), register `0x0001` = temperature (int16, /10 °C),
  register `0x0002` = humidity (uint16, /10 %RH), CRC16-Modbus. See
  `firmware/master/src/modbus.cpp`.

## 3. Safety constraints

- **No unsafe mains rewiring.** Do not rewire, bypass protection, expose live
  conductors, hot-plug, or defeat isolation of any mains-connected component
  (PZEM, RobotDyn dimmer, NC-COM relay loads).
- **No live measurements by hand.** Use the PZEM's own telemetry and safe, already
  assembled fixtures. Visual observation (lamp/load) or safe isolation is
  sufficient for actuator tests unless a PRD criterion requires a quantitative
  output.
- **Physical work only by a competent operator.**
- If a test would require unsafe intervention, record `BLOCKED — SAFE PHYSICAL
  OPERATOR ACTION REQUIRED`; do not improvise.
- Software/network actions (disable test AP, reboot a dev board, deploy rules) are
  allowed when safe and supported. Never alter mains wiring automatically.
- **Never store or screenshot secrets** (Wi-Fi, Firebase passwords, ESP-NOW
  PMK/LMK key bytes, service-account keys). Sanitize all serial/Firebase evidence.

## 4. Hardware inventory template

```text
Test run ID        :
Date/time          :
Operator           :
Git SHA            :
Release tag (if)   :
APK version/build  :
APK SHA-256        :
Master firmware rev:
Slave firmware rev :
Firebase env id    :
Android device     :
ESP32 Master board :
ESP32 Slave board  :
PZEM-004T          :
XY-MD02/SHT20      :
Relay hardware     :
Dimmer hardware    :
Load/test fixture  :
Network/AP         :
Notes              :
```

Never record credentials here.

## 5. Result vocabulary

| State | Meaning |
|-------|---------|
| `PASS` | Required physical behavior actually observed. |
| `FAIL` | Required physical behavior contradicted by observation. |
| `BLOCKED` | Hardware unavailable / disconnected / unsafe / requires operator action not performed. Never converted to PASS. |
| `NOT RUN` | Test defined but not executed this run (toolchain, time, or dependency). |
| `NOT APPLICABLE` | Requirement has no real-hardware component and is already covered elsewhere. |

A `PASS` may never come from unit tests, emulator, mocks, source inspection, CI,
or generated fixtures. Those are **preflight** evidence only and are recorded
separately (see `HARDWARE_ACCEPTANCE_RESULTS.md`).

## 6. Evidence requirements

Each executed test records:

```text
test ID
requirement
precondition
procedure
expected result
observed result
result  (PASS/FAIL/BLOCKED/NOT RUN/NOT APPLICABLE)
timestamp
evidence reference
notes
```

Evidence kinds: sanitized serial excerpts, Firebase value snapshots (no
credentials), result tables, timestamps, small screenshots (no credentials),
APK/firmware hashes. Store in
`docs/testing/evidence/hardware-acceptance/<run-id>/` only if useful and within
repo policy. Do not commit private media as sole evidence; keep a neutral
reference when evidence is external.

## 7. Requirement matrix

PRD v0.1 is maintained outside the repository (see
`docs/PRD_AUTH_MODEL_DECISION.md`). FR IDs below are the ones enumerated by Issue
#16 (the PRD-compliance tracker) and referenced by Issues #19/#20/#24. The
authoritative PRD **text** is not stored in-repo; treat these as the in-repo
traceability baseline, not a reconstruction of the PRD.

| FR / NFR | Requirement | Component | Real HW? | Observable behavior | Evidence |
|----------|-------------|-----------|----------|---------------------|----------|
| FR-01 | voltage | Master + PZEM | yes | real V, correct unit, non-placeholder | `HA-PWR-01` |
| FR-02 | current | Master + PZEM | yes | real A, responds to load | `HA-PWR-02` |
| FR-03 | power | Master + PZEM | yes | real W | `HA-PWR-03` |
| FR-04 | energy (**kWh**) | Master + PZEM + Flutter | yes | numerically kWh, no ×/÷1000 error | `HA-PWR-04` |
| FR-05 | estimated cost | Flutter | partial | energy_kWh × tariff(Rp/kWh) | `HA-PWR-05` |
| FR-06 | estimated emission | Flutter | partial | energy_kWh × 0.85 kg CO₂/kWh | `HA-PWR-06` |
| FR-07 | temperature | Master + SHT20 | yes | real °C | `HA-ENV-01` |
| FR-08 | humidity | Master + SHT20 | yes | real %RH | `HA-ENV-02` |
| FR-09 | Heat Index | Flutter | partial | Rothfusz °C-form from real T/RH | `HA-ENV-03` |
| FR-10 | temperature classification | Flutter | partial | Dingin/Sejuk/Hangat/Panas | `HA-ENV-04` |
| FR-11 | humidity classification | Flutter | partial | Kering/Normal/Lembap | `HA-ENV-05` |
| FR-12 | 10-relay control | Master + Slave | yes | each of 10 channels ON/OFF | `HA-RLY-01..10` |
| FR-13 | brightness 0–100% | Slave dimmer | yes | 0/25/50/75/100 distinguishable | `HA-DIM-01/02` |
| FR-14 | shared CH1 | Slave dimmer | yes | CH1 arbitration siblings | `HA-DIM-01` |
| FR-15 | CH2 | Slave dimmer | yes | dedicated CH2 | `HA-DIM-02` |
| FR-16 | OFF → brightness 0 | Slave dimmer | yes | dedicated OFF→0, shared retained | `HA-DIM-01/02` |
| FR-17 | history (sensorLogs) | Flutter + Firestore | partial | real samples persisted | `HA-HIST-01` |
| FR-18 | heartbeat read | Master + RTDB | yes | `unix_time` advances | `HA-OFF-01` |
| FR-19 | ≥60s → offline | Flutter | partial | freshness boundary | `HA-OFF-02` |
| FR-20 | offline disables control | Flutter + rules | partial | no command emitted | `HA-OFF-03` |
| FR-21 | last-state retention | firmware + Flutter | yes | no unintended toggle on loss | `HA-OFF-04` |
| FR-22 | environment=false offline | Master + Flutter | partial | env null/`#` when unavailable | `HA-OFF-02`, `HA-MOD-02` |
| FR-23 | power=false offline | Master + Flutter | partial | power null/`#` when unavailable | `HA-OFF-02`, `HA-MOD-01` |
| FR-24 | offline renders `#` | Flutter | partial | hashes, not stale numbers | `HA-OFF-02` |
| FR-25 | system vs connection status | Flutter | partial | ESH Offline ≠ Firebase status | `HA-OFF-02` |
| FR-26/Fr-27 | connection available/unavailable | Flutter | partial | connect state gating | `HA-OFF-02` |
| FR-28 | Can Control truth table | Flutter + rules | partial | safe command gating | `HA-OFF-03` |
| NFR-01 | usability | Flutter (users) | yes | real-user task completion | `HA-USR-01` |
| NFR-03 | failure safety | whole system | yes | no unsafe actuation on failure | `HA-SAF-01` |
| Section 23 | PRD acceptance criteria | — | — | external PRD text absent; covered by FRs above | — |

NFR-02 (status visibility), NFR-04 (data validity), and the NFR-05 unit
consistency items are deterministic/software criteria already pinned by CI; they
are listed here for completeness but have no extra hardware procedure beyond the
unit table (`HA-UNIT-*`).

## 8. Test procedures

### 8.1 Power (PZEM-004T)

- **HA-PWR-01 Voltage.** Precondition: Master powered, Provisioned, NTP synced,
  Firebase connected, PZEM wired in a safe, already-assembled fixture.
  Read `apps/flutter` monitoring screen and `/device/sensorData/power/voltage`.
  Expected: finite value in V, correct `V` label, changes plausibly; `null`/`#`
  when PZEM unavailable. If a trusted reference meter exists, record it and the
  deviation (define no tolerance unless the spec/PRD does).
- **HA-PWR-02 Current.** Same path, `/power/current`. Expected A, 2 dp, responds
  to a safe load change (idle vs active). Record RTDB vs UI agreement.
- **HA-PWR-03 Power.** `/power/power` in W. Expected plausible given V, A (power
  factor may prevent exact V×A).
- **HA-PWR-04 Energy/kWh.** The critical numeric check. Raw PZEM energy register
  is 1 Wh; the pinned library `mandulaj/PZEM-004T-v30@1.1.2` divides by 1000 and
  returns **kWh**; Master publishes unchanged; Flutter consumes as kWh. Verify no
  factor-of-1000 error: record `delta raw energy`, `delta app energy`, compare
  conversion. Numbers, not labels.
- **HA-PWR-05 Cost.** Tariff `defaultElectricityRate = 1440.70` Rp/kWh
  (`apps/flutter/lib/app/app_dependencies.dart:23`). Expected
  `cost = energy_kWh × 1440.70` (Rp). Compare against UI, using display rounding.
- **HA-PWR-06 Emission.** Factor `defaultEmissionFactor = 0.85` kg CO₂/kWh
  (`app_dependencies.dart:26`). Expected `emission = energy_kWh × 0.85` kg CO₂.

### 8.2 Environment (XY-MD02 / SHT20)

- **HA-ENV-01 Temperature.** `/device/sensorData/environment/temperature`, °C,
  1 dp, −40..125 range (firmware clamp). Plausible room value; RTDB vs UI agree.
- **HA-ENV-02 Humidity.** `/environment/humidity`, %RH, 1 dp, 0..100 clamp.
- **HA-ENV-03 Heat Index.** Recompute independently from observed T, RH using the
  Rothfusz Celsius form in `apps/flutter/lib/features/monitoring/domain/entities/sensor_data.dart:19-41`
  (with the `temperature < 27 → temperature` shortcut). Compare against UI.
- **HA-ENV-04 Temperature classification.** Current thresholds
  (`sensor_data.dart:45-50`): `<=25.7` Dingin, `<=28.6` Sejuk, `<31.5` Hangat,
  else Panas. Confirm the observed T classifies consistently.
- **HA-ENV-05 Humidity classification.** `sensor_data.dart:54-58`: `<=60.25`
  Kering, `<86.62` Normal, else Lembap.

### 8.3 Relay control (10 channels)

For **each** of the 10 routes in §2: record initial physical state → send ON →
confirm the correct physical relay actuates and no other does → confirm state
returns to app (`/rooms/<room>/tools/<device>` `state:true`) → send OFF → confirm
physical OFF and reported OFF. Detect swapped channels, wrong routing, stale UI,
missing ACK, or unintended simultaneous actuation.

| Test | Route | Owner |
|------|-------|-------|
| HA-RLY-01 | `teras/lampu` | Master |
| HA-RLY-02 | `teras/sanyo` | Master |
| HA-RLY-03 | `lorong/stop_kontak` | Slave |
| HA-RLY-04 | `lorong/blower` | Slave |
| HA-RLY-05 | `kamar_1/stop_kontak` | Slave |
| HA-RLY-06 | `kamar_1/lampu` (relay) | Slave |
| HA-RLY-07 | `kamar_2/stop_kontak` | Slave |
| HA-RLY-08 | `kamar_2/lampu` (relay) | Slave |
| HA-RLY-09 | `dapur/lampu` (relay) | Slave |
| HA-RLY-10 | `dapur/blower` | Slave |

### 8.4 Dimmer control (2 channels)

- **HA-DIM-01 (CH1, shared `kamar_1/lampu` + `kamar_2/lampu`).** Levels 0 / 25 /
  50 / 75 / 100 (follow PRD if different). Verify: 0 behaves OFF; 100 = max
  configured output; intermediate levels physically distinguishable; no wrong
  channel moves; reported state matches commanded. Verify FR-14 arbitration:
  turning one lamp OFF keeps the sibling lamp's retained brightness; last ON
  turning OFF drives CH1 to 0 (FR-16 with shared-CH1 exception).
- **HA-DIM-02 (CH2, `dapur/lampu`).** Same levels; OFF → brightness 0 (FR-16,
  dedicated channel).

### 8.5 ESP-NOW

- **HA-NOW-01.** Send command to a Slave-owned device; observe Master handling →
  ESP-NOW tx → Slave rx → physical actuation → Slave ACK (`requestId` echo,
  `success=1`, `errorCode=0`) → Master `updateActual` → Firebase/Flutter state.
  Capture sanitized serial logs (never print PMK/LMK bytes).
- **HA-NOW-02 (recovery).** Make Slave unavailable (safe), observe command/state
  behavior; restore Slave; observe communication recovery.
  Do not substitute `command_lifecycle_e2e_tests.py` for this.

### 8.6 Heartbeat / offline

- **HA-OFF-01 Healthy heartbeat.** `/device/sensorData/unix_time` advances; UI
  shows healthy/fresh state.
- **HA-OFF-02 Network loss.** Safe interruption (disable test AP / isolate
  device network; do not touch mains). Observe network lost → heartbeat stops →
  freshness timeout → Flutter status change → controls become unavailable →
  telemetry `#`/null. Record elapsed transition timestamps; do not "wait ~60s"
  and write PASS. Compare with the 60 s freshness spec.
- **HA-OFF-03 No control while offline.** After offline, attempt control; verify
  the command is not physically executed and RTDB rules suppress an unsafe write.
- **HA-OFF-04 Last-state retention.** Set a safe load to a known state; lose
  network; wait through offline detection; confirm hardware did not change state.
  Record before/after physical state.
- **HA-OFF-05 Reconnection.** Restore connectivity; heartbeat resumes; app
  reports healthy; no surprise toggle during reconnect; state syncs; commands
  available only under intended conditions.

### 8.7 Module availability

- **HA-MOD-01 Power module unavailable.** Use a safe way to make PZEM unavailable
  (or mark `BLOCKED — SAFE SENSOR ISOLATION NOT AVAILABLE`). Verify
  `connected=false`/null, Flutter `#`/empty, cost/emission/derived hidden.
- **HA-MOD-02 Environment module unavailable.** Same for SHT20; Heat Index and
  categories hidden. Verify unaffected module still reports normally.

### 8.8 Failure safety (NFR-03)

- **HA-SAF-01.** Reuse evidence from HA-OFF-02..05 and HA-MOD-*: verify network/
  Firebase failure caused no unintended relay change; stale system blocked
  control; reconnect introduced no surprise command; unavailable-module data is
  not shown as healthy. Reference prior test IDs rather than repeating.

### 8.9 Usability (NFR-01)

- **HA-USR-01.** If no formal PRD threshold exists, run a modest reproducible
  task-based check (open monitoring; identify V/A/W; identify environment status;
  control one relay; set dimmer brightness; identify offline state; explain why
  control is unavailable). Record per participant (no sensitive data):
  participant ID, task, success/failure, confusion, completion observation.
  If no representative real user is available, mark
  `BLOCKED — REAL USER ACCEPTANCE NOT PERFORMED`. Do not fake participants.

### 8.10 Units end-to-end

| Metric | Raw/sensor | Wire (RTDB) | Domain | UI | Expected |
|--------|------------|-------------|--------|----|----------|
| Voltage | V | number | V | `V` | V |
| Current | A | number | A | `A` | A |
| Power | W | number | W | `W` | W |
| Energy | kWh (lib /1000) | number kWh | kWh | `kWh` | kWh (magnitude, not just label) |
| Temperature | /10 °C | °C 1 dp | °C | `°C` | °C |
| Humidity | /10 %RH | % 1 dp | % | `%RH` | %RH |
| Cost | — | — | Rp | `Rp` | energy_kWh × 1440.70 |
| Emission | — | — | kg | `kg CO₂` | energy_kWh × 0.85 |

## 9. Evidence storage

Safe evidence may be committed under
`docs/testing/evidence/hardware-acceptance/<run-id>/`: sanitized serial excerpts,
result tables, sanitized Firebase snapshots, hashes, timestamps, small
credential-free screenshots. Never commit keys, credentials, SSIDs, passwords,
tokens, service-account files, or raw logs containing them.

## 10. Overall acceptance classification

- **PASS** — every mandatory hardware criterion executed and observed, no FAIL,
  NFR validation complete, evidence present.
- **PARTIAL / BLOCKED** — hardware missing/partial, operator action still needed,
  or user acceptance not performed.
- **FAIL** — physical behavior contradicts a requirement.

A `BLOCKED`/`NOT RUN` item can never be reported as `PASS`.