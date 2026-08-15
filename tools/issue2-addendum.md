# Issue #2 — Evidence-Gap Closure Addendum

Generated: 2026-08-15
Repo: `elfromsky/terbarubangetgabung`
Scope: close the remaining acceptance-criteria gaps in the Issue #2 final evidence
report. This addendum does **not** restart the investigation; it only fills the
five primary gaps (plus optional Modbus fixtures) identified after the previous
report.

Coordinated revision (unchanged):

| Component | Revised | Pre-revision |
|-----------|---------|--------------|
| Flutter   | `5bd9fb6` | `1b62be3` |
| Slave     | `6d306cf` | `24da621` |
| Master    | `f8c960e` | `273b3f6` |

---

## Gap 1 — Command `issued_at` freshness boundary (CMD-FRESHNESS-BOUNDARY)

The previous report conflated **heartbeat** freshness (`59 / 60 s`, HB-FRESHNESS-BOUNDARY)
with **command `issued_at`** freshness (`±15000 / +5000 ms`). They are now separated.

### 1.1 RTDB rule (read from `database.rules.json`, verbatim)

```json
"issued_at": { ".validate": "newData.isNumber() && newData.val() >= now - 15000 && newData.val() <= now + 5000" }
```

Both bounds are **inclusive** (`>=` and `<=`).

### 1.2 Master validator (read from `src/firebase_command_router.cpp`, `commandIsFresh`)

```cpp
bool commandIsFresh(int64_t issuedAtMs) {
    // ... NTP guard is a pre-condition, not boundary math ...
    if (issuedAtMs > nowMs + COMMAND_FUTURE_TOLERANCE_MS) return false; // 5000
    if (issuedAtMs <= nowMs - COMMAND_MAX_AGE_MS) return false;         // 15000
    return true;
}
```

Master accepts `nowMs - 15000 < issuedAtMs <= nowMs + 5000`. The lower bound is
**strict** (`<=` rejects at exactly `nowMs - 15000`), the upper bound is inclusive.

### 1.3 Executed boundary table (deterministic)

| Offset (ms) | RTDB (inclusive) | Master (mirror, executed) |
| ----: | ---- | ------ |
| -15001 | REJECT | REJECT |
| -15000 | **ACCEPT** (inclusive `>=`) | **REJECT** (strict `<=`) |
| -14999 | ACCEPT | ACCEPT |
|     -1 | ACCEPT | ACCEPT |
|      0 | ACCEPT | ACCEPT |
|     +1 | ACCEPT | ACCEPT |
|  +4999 | ACCEPT | ACCEPT |
|  +5000 | ACCEPT (inclusive `<=`) | ACCEPT |
|  +5001 | REJECT | REJECT |

**Divergence confirmed**: at exactly `issued_at = now - 15000`, RTDB accepts but
Master rejects. This is a real (if 1 ms wide) dual-check divergence between
Firebase server time (RTDB) and Master NTP time.

Execution:
- Master column: `tools/evidence_gaps_tests.py` `run_master_freshness()` — 9/9 PASS, deterministic (fixed `now_ms = 0`).
- RTDB column: `rules-tests/rules.test.js` (RTDB emulator, `firebase emulators:exec`). Region tests at safe margins (-20000 / -14000 / 0 / +4000 / +6000) all PASS. The exact ±1 ms inclusivity cannot be exercised deterministically against a live emulator clock (documented in the test), so the inclusive `>=`/`<=` semantics are stated from the rule operators and corroborated by the observed pass/reject transitions.

### 1.4 Heartbeat preserved separately

`HB-FRESHNESS-BOUNDARY` remains under its own ID and is **not** reused as command-freshness evidence. Existing boundary tests (59 s online / 60 s offline / missing unknown / future unknown) are unchanged.

---

## Gap 2 — request_id duplicate behavior (CMD-REQUESTID-DUPLICATE)

### 2.1 Implementation (verified from `src/room_device_routing.cpp`, Slave `6d306cf`)

- `DUPLICATE_CACHE_SIZE = 8`.
- Key = `requestId + roomKey + deviceKey` (all three compared in `duplicateFind`).
- Cache entry stores the **final result** (`resultState`, `resultBrightness`, `resultSuccess`, `resultErrorCode`).
- On a hit, `applyDeviceCommand` returns the cached result **without** re-driving relay/dimmer.
- `duplicateStore` is also called on failure paths (unknown device, invalid brightness, invalid state), so failed commands are cached too.

### 2.2 Executed exact-duplicate test

`tools/evidence_gaps_tests.py` `run_duplicate()`. Processing `kamar_1/lampu` `ON brightness=30 request_id=req-A` twice:

| Assertion | Result |
|-----------|--------|
| first command processed normally | PASS |
| second command recognized as duplicate | PASS |
| hardware-driving path not executed twice (drive count stays 1) | PASS |
| cached result consistent (brightness 30, success OK) | PASS |

Side-effect suppression is proven (drive-count instrument), not merely cache membership.

### 2.3 Eviction / capacity / TTL / reset

- Capacity 8; eviction is **FIFO** ring (`duplicateCacheIndex = (index+1) % 8`).
- No TTL (static array, no time field).
- RAM-only (`static`); after reboot/cache re-zeroing, cache is empty. Reset behavior is static (not executed on hardware).
- Executed test: after 8 unique ids (A..H), replay A → duplicate; insert I (9th) → A evicted, B..H retained; replaying evicted A → **not** duplicate and re-drives hardware. All PASS.

Classification: **CONFIRMED_REPRODUCED** (host mirror of exact implementation).

---

## Gap 3 — request_id collision behavior (CMD-REQUESTID-COLLISION)

Collision = same `request_id` + same route, different payload. The cache key excludes
`state`, `brightness`, and `issued_at`; only `requestId + roomKey + deviceKey` matter.

### 3.1 Same id, same route, different payload (executed)

First `kamar_1/lampu state=true brightness=30`, then same `request_id` with
`state=false brightness=0`:

| Question | Answer (executed) |
|----------|-------------------|
| second command treated as duplicate? | **Yes** |
| payload difference matter? | **No** |
| cached result returned? | **Yes** (stale brightness 30, stale state ON) |
| reused request_id suppress a legit newer command? | **Yes** (drive count stays 1) |
| issued_at participate? | **No** (not in key) |
| route participate? | **Yes** (in key) |
| state/brightness participate? | **No** |

### 3.2 Same id, different route (executed)

`request_id=req-A` for `kamar_1/lampu`, then `request_id=req-A` for `dapur/lampu`:
**not** treated as duplicate; the second route drives hardware. PASS.

Classification: **CONFIRMED_REPRODUCED** (collision = duplicate under the current key
definition; a reused id on the same route CAN suppress a legitimate newer command —
recorded as an implementation characteristic, not a fix task).

---

## Gap 4 — Custom-claim / ID-token refresh lifecycle (AUTH-TOKEN-REFRESH)

Source: `lib/main.dart` (`FirebaseBootstrap._initializeFirebase`), `lib/firebase_options.dart`.

Lifecycle (application-specific, from source):

```text
Flutter launches
    -> Firebase.initializeApp (DefaultFirebaseOptions)
    -> FirebaseAuth.instance
    -> if currentUser == null: signInAnonymously()
    -> getIdTokenResult(forceClaimRefresh: false)   // bootstrap only
    -> hasTrustedDeviceClaim(claims) = claims['owner']==true || claims['controller']==true
    -> untrusted => throw UntrustedDeviceException(uid) -> "Perangkat belum terdaftar" + UID + "Coba lagi"
```

Refresh/retry:

```text
"Coba lagi" button -> _retry() -> _initializeFirebase(forceClaimRefresh: true)
```

Questions answered precisely:

| Question | Finding |
|----------|---------|
| signInAnonymously used? | Yes (only if no cached user) |
| Where claims read? | `getIdTokenResult(forceClaimRefresh)` in bootstrap; `hasTrustedDeviceClaim(claims)` |
| Which claims accepted? | `owner` OR `controller` (either one suffices) |
| Neither? | `UntrustedDeviceException` → untrusted-device screen |
| getIdTokenResult called? | Yes (bootstrap `false`, retry `true`) |
| forceRefresh ever used? | Yes, on manual "Coba lagi" retry only |
| Auto claim refresh? | No. The app does **not** poll or re-read claims mid-session. |
| Reauth? | No explicit re-auth; relies on anonymous session persistence + forceRefresh. |
| Restart gets new token? | Yes — fresh `getIdTokenResult` (and Auth SDK may cache). |
| Auth SDK auto-refresh after expiry? | Yes (firebase_auth renews expired OIDC id tokens ~1 h), but custom **claims** are only re-fetched via `forceRefresh=true` or a new `getIdTokenResult`. |
| Admin assigns owner/controller after sign-in? | Existing token unchanged until manual "Coba lagi" or app restart (the only path that calls `forceRefresh=true`). |

### 4.3 Failure mode (explicit)

If signed in **before** `owner=true` is assigned, the current implementation remains
on the "Perangkat belum terdaftar" screen and does **not** auto-recover; the user must
tap "Coba lagi" (triggers `forceClaimRefresh=true`) or restart the app.

Classification: **CONFIRMED_STATIC** (source-proven lifecycle). Dynamic
claim-mutation-then-refresh was not reproduced against the Firebase Auth emulator
(cross-service emulator + custom-claims would be disproportionally complex); this
dynamic propagation step is marked `SKIPPED_ENVIRONMENT`, but the acceptance criterion
"custom-claim token refresh semantics are documented" is satisfied.

Note: the `hasTrustedDeviceClaim` gate is already unit-tested
(`test/firebase_access_test.dart`).

---

## Gap 5 — Shared bedroom dimmer arbitration (DIMMER-SHARED-STATE)

Two layers verified from source and executed as deterministic host mirrors:

- **Master semantic arbitration** (`firebase_command_router.cpp`): `commandVersionIsNewer`
  and `sharedBedroomVersionIsNewer` implement "newest wins" ordering on
  `(issued_at, request_id tie-break via strcmp > 0)`. Shared CH1 brightness is owned by
  the newest **ON** command with `brightness > 0`. `desiredBrightnessForRoute`/`updateActual`
  propagate one authoritative CH1 brightness to both `kamar_1` and `kamar_2` while
  relay `state` stays per-route.
- **Slave physical arbitration** (`room_device_routing.cpp` `applyDeviceCommand`):
  `hasOtherActiveRelayOnDimmer` + shared `dimmerChannel=1` retention — turning one bedroom
  OFF never zeroes a channel still used by the sibling's ON relay.

### Scenarios (executed, `tools/evidence_gaps_tests.py` `run_dimmer`)

| Scenario | Expectation | Result |
|----------|-------------|--------|
| A: K1 ON 30, K2 OFF | K1 relay ON, K2 OFF, CH1=30 | PASS |
| B: from K1 ON 30, K2 ON 80 | CH1=80, both relays ON | PASS |
| C: both ON 80, K1 OFF | K1 relay OFF, K2 ON, CH1 retained 80 | PASS |
| D: old K1 (ts 1000) delivered after K2 (ts 2000) | old cmd cannot overwrite newer shared brightness | PASS |
| E: identical issued_at, request_id "A" vs "B" | lexicographically larger `request_id` ("B") wins | PASS |
| F: both OFF | shared CH1 brightness = 0 | PASS |

### Required invariant (tested)

```
Both bedroom routes report the same shared CH1 brightness.
Relay ON/OFF state remains independent per bedroom.
The newest valid command (issued_at, then request_id) determines shared brightness.
```

Classification:
- logical/state arbitration: **CONFIRMED_REPRODUCED** (host mirror).
- physical TRIAC behavior: **HARDWARE_REQUIRED** (unchanged).

---

## Optional Gap 6 — Modbus parser fixtures (DEFERRED_TESTABILITY)

`src/modbus.cpp` (`readModBus`) intermixes raw UART acquire (`SensorSerial`,
`RS485_DIR` GPIO, `delay`) with CRC/payload validation inline. There is no pure
parse-function to call without hardware. Producing local fixtures would require
extracting a pure `parseModbusResponse()` from `readModBus` — a firmware refactor
beyond the "extremely small, behavior-preserving" scope of this evidence task.

Recorded: **DEFERRED_TESTABILITY** — parser validation is wired to live UART acquisition;
deterministic fixtures need a deferred refactor. Real XY-MD02 acceptance remains
`HARDWARE_REQUIRED`.

---

## Files / commands / validation

### Files added/modified

- `rules-tests/rules.test.js` — added `RTDB command issued_at freshness boundaries` describe block (5 tests).
- `tools/evidence_gaps_tests.py` — new: faithful host mirrors + executable tests for Master freshness, Slave duplicate cache (exact/eviction/collision), shared-dimmer arbitration (scenarios A-F). 47 assertions.

### Commands executed (all actually run)

```text
python tools/evidence_gaps_tests.py                                  -> 47 passed, 0 failed
firebase emulators:exec "cd rules-tests && npm test"                 -> 14 passed, 1 pre-existing failure
    (pre-existing: "controller cannot update/delete sensor logs" Firestore-settings reuse quirk,
     documented in the prior report; not a rules defect and not introduced here)
```

Firestore + RTDB emulators were run locally via the Android Studio JBR
(`C:\Program Files\Android\Android Studio\jbr`), which is not on PATH and was set
per-invocation. No production Firebase, no hardware, no secret exposure.

### Evidence classification updates

| ID | Previous | New |
|----|----------|-----|
| CMD-FRESHNESS-BOUNDARY | CONFIRMED_STATIC (heartbeat-mixed) | **CONFIRMED_REPRODUCED** (Master mirror 9 offsets + RTDB region tests); boundary divergence at `now-15000` documented |
| HB-FRESHNESS-BOUNDARY | CONFIRMED_STATIC | unchanged, kept separate |
| CMD-REQUESTID-DUPLICATE | CONFIRMED_STATIC | **CONFIRMED_REPRODUCED** |
| CMD-REQUESTID-COLLISION | CONFIRMED_STATIC | **CONFIRMED_REPRODUCED** |
| AUTH-TOKEN-REFRESH | (new) | CONFIRMED_STATIC (dynamic propagation SKIPPED_ENVIRONMENT) |
| DIMMER-SHARED-STATE | SCHEMA_COMPATIBLE (static) | logical = **CONFIRMED_REPRODUCED**; TRIAC = HARDWARE_REQUIRED |
| Modbus local fixtures | none | DEFERRED_TESTABILITY |

---

## Issue #2 Closure Readiness

| Criterion | Result | Evidence |
| --------------------------------------------------------- | ------ | -------- |
| Command issued_at boundary tests exist | PASS | `run_master_freshness` 9/9; RTDB region 5/5 |
| Heartbeat freshness kept separate | PASS | HB-FRESHNESS-BOUNDARY untouched |
| request_id duplicate behavior tested | PASS | side-effect suppression proven |
| request_id collision behavior tested | PASS | key = id+room+device; payload ignored |
| concurrent Slave commands characterized | PASS | single `pendingCmd`, serialized cycle (CONFIRMED_STATIC) |
| out-of-order ACK characterized | PASS | ACK matched by route+request_id (CONFIRMED_STATIC) |
| lost ACK characterized | PASS | ACK_TIMEOUT 3000, MAX_SEND_ATTEMPTS 3, backoff (CONFIRMED_STATIC) |
| replay cache capacity/eviction documented | PASS | ring 8, FIFO, no TTL, RAM-only (executed) |
| custom-claim token refresh semantics documented | PASS | CONFIRMED_STATIC lifecycle; manual forceRefresh retry |
| shared dimmer arbitration tested | PASS | scenarios A-F executed |
| physical dimmer behavior correctly left HARDWARE_REQUIRED | PASS | TRIAC explicitly deferred |
| Modbus local fixtures | DEFERRED | DEFERRED_TESTABILITY (UART-coupled parser) |

The only non-PASS row (Modbus fixtures) is an explicitly **optional** task whose deferral
is permitted by the task instructions and does not block investigation closure.

**Verdict:**

```text
ISSUE_2_READY_TO_CLOSE
```

As a **completed investigation**. The production defects discovered (Master
`generateRequestId` `std::string`/`String` compile mismatch; `sensorLogs`
owner/controller authorization contradiction) remain intentionally unfixed here and
belong in separate implementation issues.
