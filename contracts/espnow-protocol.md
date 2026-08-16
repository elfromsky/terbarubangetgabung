# ESP-NOW protocol (Master <-> Slave)

This document describes the ESP-NOW wire contract between the ESP32 Master and
ESP32 Slave firmware.

Authoritative source: `firmware/master/include/esp_now_protocol.h` and
`firmware/slave/src/esp_now_config.h`. Both files carry `static_assert`s that
pin the struct sizes below; a size mismatch is a compile-time error.

## Message types

| ID | Name | Direction | Purpose |
|----|------|-----------|---------|
| 1 | `ESPNOW_MSG_DEVICE_COMMAND` | Master -> Slave | device command |
| 2 | `ESPNOW_MSG_DEVICE_STATE` | Slave -> Master | ACK / periodic state report |
| 3 | `ESPNOW_MSG_DISCOVERY_BEACON` | Master (broadcast) | channel discovery |
| 4 | `ESPNOW_MSG_AUTHENTICATED_BEACON` | Slave -> Master | authenticated discovery reply |

## Device command payload (Master -> Slave)

`DeviceCommandPayload` — packed, **92 bytes** (`static_assert` enforced):

| Field | Type | Bytes | Notes |
|-------|------|-------|-------|
| `type` | `uint8_t` | 1 | `1` (command) |
| `roomKey` | `char[24]` | 24 | null-terminated |
| `deviceKey` | `char[32]` | 32 | null-terminated |
| `state` | `uint8_t` | 1 | `0`=OFF, `1`=ON |
| `brightness` | `uint8_t` | 1 | `0..100` |
| `requestId` | `char[32]` | 32 | opaque id echoed in ACK |
| `crc` | `uint8_t` | 1 | XOR CRC |

## Device state payload (Slave -> Master)

`DeviceStatePayload` — packed, **98 bytes** (`static_assert` enforced):

| Field | Type | Bytes | Notes |
|-------|------|-------|-------|
| `type` | `uint8_t` | 1 | `2` (state) |
| `roomKey` | `char[24]` | 24 | null-terminated |
| `deviceKey` | `char[32]` | 32 | null-terminated |
| `state` | `uint8_t` | 1 | final state |
| `brightness` | `uint8_t` | 1 | final brightness |
| `requestId` | `char[32]` | 32 | echoed; empty for periodic report |
| `success` | `uint8_t` | 1 | `1`=OK, `0`=error |
| `errorCode` | `uint8_t` | 1 | `0`=OK, nonzero reason |
| `timestamp` | `uint32_t` | 4 | `millis()` |
| `crc` | `uint8_t` | 1 | XOR CRC |

## Discovery beacon payload

`DiscoveryBeaconPayload` — packed, **7 bytes** (`static_assert` enforced):

| Field | Type | Bytes |
|-------|------|-------|
| `type` | `uint8_t` | 1 |
| `channel` | `uint8_t` | 1 |
| `magic` | `uint32_t` | 4 |
| `crc` | `uint8_t` | 1 |

## CRC

A single-byte XOR CRC is computed over all bytes of the payload **except** the
trailing `crc` byte itself (`computeXorCRC` / `computeCRC`). Slaves validate the
CRC (`validateCommandCRC`) and discard invalid frames.

## Discovery & channel

- Discovery magic: `0xA5C35A7E` (`ESPNOW_DISCOVERY_MAGIC`).
- Discovery beacon broadcast interval: `1000 ms`.
- Channel scan range `1..13`, dwell `500 ms` per channel.
- Link timeout: `30000 ms`; auth timeout: `5000 ms`.

## Encryption

- Encryption between Master and Slave is required; real keys are **never**
  committed.
- `PMK` (primary) and `LMK` (local) are each exactly **16 bytes**
  (`static_assert(sizeof == ESP_NOW_KEY_LEN)` with `ESP_NOW_KEY_LEN == 16`).
- Keys are supplied only through the ignored local provisioning header
  (`esp_now_keys.local.h`), never in tracked source. See `docs/PROVISIONING.md`.

> Do not document actual PMK/LMK key bytes here; they are secrets and must stay
> outside the repository.

## ACK / state report behavior

- On a successful command, the Slave replies with a state payload whose
  `requestId` echoes the command `requestId`, `success = 1`, `errorCode = 0`.
- On failure, `success = 0` and a nonzero `errorCode` is returned.
- A periodic full-state report uses an empty `requestId`.
- Error codes: `0` OK, `1` unknown device, `2` invalid state, `3` invalid
  brightness, `4` CRC invalid, `5` hardware.

## Master send retry

- Maximum send attempts per command: `3`.
- Retry delay: `300 ms`; ACK timeout: `3000 ms`; cycle backoff: `2000 ms`.

## Duplicate / replay handling (Slave)

The Slave keeps a fixed ring buffer of 8 duplicate-cache entries (FIFO
eviction, no TTL). The key is **payload-aware**: `roomKey + deviceKey +
requestId + state + brightness`. An exact retry (same key) replays the cached
result without driving hardware again. A change to any key field (including
`state` or `brightness`) is treated as a new command (Issue #7). `issued_at` is
**not** part of the payload key (Slave does not perform freshness checks; that
is the Master's responsibility).

See `tools/duplicate_cache_tests.py` for the executable specification.

## MAC assumptions

- The Master knows the Slave's fixed MAC (`SLAVE_MAC_ADDRESS`) and registers it
  as a peer.
- The Slave knows the Master's fixed MAC (`MASTER_MAC`) and only accepts
  authenticated/encrypted discovery from it.
