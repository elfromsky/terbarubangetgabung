# Telemetry schema (Master -> RTDB, Slave -> Master)

This document describes the telemetry and state paths published to Firebase
Realtime Database (RTDB) by the Master and Slave firmware, and how each field is
typed, timed, and consumed.

Authoritative source: `firmware/master/src/firebase_telemetry.cpp` and
`firebase_command_router.cpp`.

## RTDB telemetry paths (written by Master)

| Path | Writer | Type | Unit | Consumer | Notes |
|------|--------|------|------|----------|-------|
| `/device/sensorData/unix_time` | Master | int64 | epoch **seconds** | Flutter heartbeat | written only when NTP time is valid |
| `/device/sensorData/environment` | Master | object | mixed | Flutter monitoring | see below |
| `/device/sensorData/power` | Master | object | mixed | Flutter monitoring | see below |
| `/device/sensorData/timestamp` | Master | string | ISO timestamp | Flutter | only when time valid |
| `/device/sensorData/system` | Master | object | mixed | Flutter | diagnostics |
| `/rooms/<room>/tools/<device>` | Master | object | mixed | Flutter control/monitoring | actual reflected state |
| `/gateway/status/slave` | Master | object | mixed | Flutter availability | Slave link status |

## `environment` object

| Field | Type | Unit | Notes |
|-------|------|------|-------|
| `temperature` | number (float) | degC | rounded to 1 decimal; `null` when unavailable |
| `humidity` | number (float) | % | rounded to 1 decimal; `null` when unavailable |
| `connected` | bool | — | `true` only if both values finite and `sampled_at > 0` |
| `sampled_at` | int64 | epoch **seconds** | `null` when not connected |

## `power` object

| Field | Type | Unit | Notes |
|-------|------|------|-------|
| `voltage` | number | V | 1 decimal; `null` if unavailable |
| `current` | number | A | 2 decimals; `null` if unavailable |
| `power` | number | W | 1 decimal; `null` if unavailable |
| `energy` | number | kWh | 3 decimals; `null` if unavailable |
| `frequency` | number | Hz | 1 decimal; `null` if unavailable |
| `pf` | number | — | power factor, 2 decimals; `null` if unavailable |
| `connected` | bool | — | `true` only if PZEM connected and `sampled_at > 0` |
| `sampled_at` | int64 | epoch **seconds** | `null` when not connected |

### `power.energy` unit — kWh (authoritative)

`energy` is **kWh**, not Wh.

The PZEM-004T-v30 device's raw energy register (`REG_ENERGY_L`/`REG_ENERGY_H`)
has a resolution of 1 Wh, but the pinned `mandulaj/PZEM-004T-v30@1.1.2`
library already divides that raw register value by 1000 and returns kWh from
`PZEM004Tv30::energy()`:

```cpp
// PZEM004Tv30.cpp (v1.1.2), updateValues()
_currentValues.energy = ((uint32_t)response[13] << 8 |  // Raw Energy in 1Wh
                         (uint32_t)response[14] |
                         (uint32_t)response[15] << 24 |
                         (uint32_t)response[16] << 16) / 1000.0;
```

Master publishes that library value **unchanged**; Flutter consumes it **as kWh**
for display, cost, emission, and history. No additional Wh→kWh conversion exists
or is required anywhere in the runtime path.

## `system` object

| Field | Type | Notes |
|-------|------|-------|
| `wifi_connected` | bool | Wi-Fi state |
| `free_heap` | int | bytes |
| `rssi` | int | dBm |
| `ip` | string | local IP |

## Reflected room/device state

`/rooms/<room>/tools/<device>` carries the Master's **actual** (reported) state:

- relay device: `{ "state": <bool> }`
- dimmer device: `{ "state": <bool>, "brightness": <0..100> }`

## Slave availability

`/gateway/status/slave` written by Master:

| Field | Type | Unit | Notes |
|-------|------|------|-------|
| `online` | bool | — | true while a valid Slave packet was seen within 15000 ms |
| `last_seen` | int64 | epoch **seconds** | `null` until first valid packet; derived from Master NTP clock minus reception age |

## Firestore sensor logs (written by Flutter owner)

The Flutter application writes history records to Firestore `sensorLogs`:

| Field | Type | Notes |
|-------|------|-------|
| `timestamp` | Firestore timestamp | write/creation time |
| `power` | map | snapshot of power fields |
| `environment` | map | snapshot of environment fields |
| `derived` | map (optional) | estimated cost/emission |

`power.energy` inside `sensorLogs` carries the same **kWh** value as the RTDB
`power.energy` field above (the Flutter owner writes the domain value unchanged).
`derived.estimatedCost` and `derived.estimatedEmission` are computed from that
kWh value.

## Clock authority summary

Two distinct clock authorities coexist (see `time-and-freshness.md`):

- **Master firmware** publishes `..._sampled_at` and `unix_time` in **epoch
  seconds** sourced from NTP (`gettimeofday()` after NTP sync).
- **Firebase server time** is used for command `issued_at` (epoch
  **milliseconds**) and for RTDB rule `now`.
- **Flutter** derives `issued_at` from device clock + RTDB server-time offset.

Do not mix seconds and milliseconds across these paths.
