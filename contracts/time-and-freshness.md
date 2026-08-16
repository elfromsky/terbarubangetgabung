# Time and freshness model

This document centralizes the time semantics used across the coordinated
system. It is derived from the firmware (`firebase_command_router.cpp`), the
RTDB rules (`database.rules.json`), and the Flutter command generation
(`firebase_room_device_data_source.dart`).

## Clock authorities

| Authority | Source | Unit | Used for |
|-----------|--------|------|----------|
| Firebase server time | RTDB `.info/serverTimeOffset` + device clock | epoch ms | command `issued_at`; RTDB rule `now` |
| Master NTP time | `gettimeofday()` after NTP sync | epoch s (and derived ms) | heartbeat `unix_time`, `sampled_at`, `last_seen`, command freshness |
| Slave `millis()` | device uptime | ms | ESP-NOW state `timestamp` |

## Field timing

| Field | Unit | Authority |
|-------|------|-----------|
| `issued_at` | epoch **milliseconds** | Firebase server time (estimated by Flutter) |
| `unix_time` | epoch **seconds** | Master NTP |
| `environment.sampled_at` | epoch **seconds** | Master NTP |
| `power.sampled_at` | epoch **seconds** | Master NTP |
| `last_seen` | epoch **seconds** | Master NTP (minus reception age) |
| ESP-NOW `timestamp` | `millis()` ms | Slave uptime (not wall-clock) |

## Command freshness

### RTDB (write-time) rule

```text
issued_at >= now - 15000  AND  issued_at <= now + 5000
```

where `now` is Firebase server time in milliseconds. Both bounds are
**inclusive**.

### Master (consume-time) check

```cpp
if (issuedAtMs >  nowMs + COMMAND_FUTURE_TOLERANCE_MS) reject; // +5000
if (issuedAtMs <= nowMs - COMMAND_MAX_AGE_MS)         reject; // -15000
```

where `nowMs` is Master NTP epoch milliseconds. This accepts
`(now - 15000, now + 5000]` (future exclusive is strict at `>`, stale
inclusive at `<=`).

> The two checks use independent clocks (Firebase server vs Master NTP), so a
> command can pass the RTDB rule and still be rejected by the Master if the two
> clocks disagree by more than the overlapping tolerance. This is a pre-existing
> property of the system, not a bug introduced by the monorepo migration.

## Heartbeat / gateway freshness

- Master publishes `unix_time` only when NTP is synchronized.
- Flutter heartbeat "online" gating uses the freshness of `unix_time`
  (see `_eshStatusFor` in the monitoring feature).

## Slave availability

- A Slave is considered `online` while a valid ESP-NOW state packet was seen
  within the last `15000 ms` (`SLAVE_ONLINE_WINDOW_MS`).
- Master publishes Slave status at most every `5000 ms`
  (`SLAVE_STATUS_PUBLISH_INTERVAL_MS`) and retries after `1000 ms`
  (`SLAVE_STATUS_RETRY_MS`).

## Sensor freshness

- `connected` for `environment`/`power` requires `sampled_at > 0` (a
  wall-clock timestamp was recorded) in addition to finite values.
- Flutter further overrides `connected` to unavailable when `sampled_at` is
  missing or any physical value is outside the accepted range.

## Future / stale tolerance

- Command future tolerance: `+5000 ms`.
- Command max age (stale): `15000 ms`.
- These constants live in `firmware/master/src/firebase_command_router.cpp`
  (`COMMAND_FUTURE_TOLERANCE_MS`, `COMMAND_MAX_AGE_MS`) and are pinned by
  `tools/evidence_gaps_tests.py`.
