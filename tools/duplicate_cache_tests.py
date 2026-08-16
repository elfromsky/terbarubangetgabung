#!/usr/bin/env python3
"""Issue #7 — Slave duplicate cache payload-aware key: host-side tests.

Scope / honesty
---------------
These are HOST tests. They do not run on ESP32 hardware and do not claim
hardware validation.

They combine two layers:

1. Static source checks: the production file ``src/room_device_routing.cpp``
   is read and asserted to (a) store ``commandState``/``commandBrightness``
   in ``DuplicateCacheEntry`` and (b) compare them in ``duplicateFind``.
   This pins the production key definition so the behavioral mirror below
   cannot silently drift away from the real implementation.

2. Behavioral mirror: a faithful line-by-line port of the duplicate-cache
   logic (key fields, ring buffer of 8, FIFO eviction, no TTL, result
   caching) plus the ``applyDeviceCommand`` decision structure (duplicate
   check -> route lookup -> validation -> drive + store). The mirror is kept
   deliberately small so each scenario in the Issue #7 failure-mode table
   is exercised against the same decisions the firmware makes.

Run:  python tools/duplicate_cache_tests.py
Exit code 0 = all passed, 1 = failures.
"""

import os
import re
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROUTING_SRC = os.path.join(REPO_ROOT, "firmware", "slave", "src", "room_device_routing.cpp")

ESPNOW_STATE_OFF = 0
ESPNOW_STATE_ON = 1
ESPNOW_RESULT_OK = 1
ESPNOW_RESULT_ERROR = 0
ESPNOW_ERR_UNKNOWN_DEVICE = 1
ESPNOW_ERR_INVALID_STATE = 2
ESPNOW_ERR_INVALID_BRIGHTNESS = 3
DUPLICATE_CACHE_SIZE = 8

_passed = 0
_failed = 0


def check(name, condition):
    global _passed, _failed
    if condition:
        _passed += 1
        print("PASS  %s" % name)
    else:
        _failed += 1
        print("FAIL  %s" % name)


# ---------------------------------------------------------------------------
# Layer 1: static source checks (anti-drift between mirror and production)
# ---------------------------------------------------------------------------

def run_static_source_checks():
    with open(ROUTING_SRC, "r", encoding="utf-8") as handle:
        src = handle.read()

    entry_match = re.search(
        r"struct DuplicateCacheEntry \{(?P<body>.*?)\};", src, re.DOTALL)
    check("static: DuplicateCacheEntry exists", entry_match is not None)
    body = entry_match.group("body") if entry_match else ""
    check("static: entry stores commandState",
          re.search(r"uint8_t\s+commandState\s*;", body) is not None)
    check("static: entry stores commandBrightness",
          re.search(r"uint8_t\s+commandBrightness\s*;", body) is not None)

    find_match = re.search(
        r"duplicateFind\s*\([^)]*\)\s*\{(?P<body>.*?)\n\}", src, re.DOTALL)
    check("static: duplicateFind exists", find_match is not None)
    find_body = find_match.group("body") if find_match else ""
    check("static: duplicateFind compares commandState",
          "commandState == state" in find_body)
    check("static: duplicateFind compares commandBrightness",
          "commandBrightness == brightness" in find_body)
    check("static: duplicateFind still compares requestId",
          'strcmp(duplicateCache[i].requestId, requestId)' in find_body)
    check("static: duplicateFind still compares roomKey",
          'strcmp(duplicateCache[i].roomKey, roomKey)' in find_body)
    check("static: duplicateFind still compares deviceKey",
          'strcmp(duplicateCache[i].deviceKey, deviceKey)' in find_body)

    check("static: ring buffer size stays 8",
          "DUPLICATE_CACHE_SIZE = 8" in src)
    check("static: FIFO eviction kept",
          "(duplicateCacheIndex + 1) % DUPLICATE_CACHE_SIZE" in src)
    check("static: no issued_at in payload key",
          "issued_at" not in body and "issuedAt" not in body)


# ---------------------------------------------------------------------------
# Layer 2: behavioral mirror of the production duplicate cache
# ---------------------------------------------------------------------------

class CacheEntry:
    __slots__ = ("used", "requestId", "roomKey", "deviceKey",
                 "commandState", "commandBrightness",
                 "resultState", "resultBrightness",
                 "resultSuccess", "resultErrorCode")


class SlaveMirror:
    """Faithful port of room_device_routing.cpp duplicate handling.

    Hardware drive is reduced to a counter: every non-duplicate, valid,
    known-device command increments ``drive_count`` exactly once.
    """

    def __init__(self):
        self.cache = [None] * DUPLICATE_CACHE_SIZE
        for i in range(DUPLICATE_CACHE_SIZE):
            self.cache[i] = CacheEntry()
            self.cache[i].used = False
        self.cache_index = 0
        self.drive_count = 0
        self.routes = {
            ("kamar_1", "lampu"): {"dimmable": True},
            ("kamar_2", "lampu"): {"dimmable": True},
            ("dapur", "lampu"): {"dimmable": True},
            ("lorong", "stop_kontak"): {"dimmable": False},
            ("lorong", "blower"): {"dimmable": False},
            ("kamar_1", "stop_kontak"): {"dimmable": False},
            ("kamar_2", "stop_kontak"): {"dimmable": False},
            ("dapur", "blower"): {"dimmable": False},
        }

    def duplicate_find(self, requestId, roomKey, deviceKey, state, brightness):
        for entry in self.cache:
            if (entry.used and
                    entry.requestId == requestId and
                    entry.roomKey == roomKey and
                    entry.deviceKey == deviceKey and
                    entry.commandState == state and
                    entry.commandBrightness == brightness):
                return entry
        return None

    def duplicate_store(self, requestId, roomKey, deviceKey,
                        commandState, commandBrightness,
                        state, brightness, success, errorCode):
        entry = self.cache[self.cache_index]
        entry.used = True
        entry.requestId = requestId
        entry.roomKey = roomKey
        entry.deviceKey = deviceKey
        entry.commandState = commandState
        entry.commandBrightness = commandBrightness
        entry.resultState = state
        entry.resultBrightness = brightness
        entry.resultSuccess = success
        entry.resultErrorCode = errorCode
        self.cache_index = (self.cache_index + 1) % DUPLICATE_CACHE_SIZE

    def apply_command(self, roomKey, deviceKey, state, brightness, requestId):
        """Returns (treated_as_duplicate, success, result_state,
        result_brightness, error_code)."""
        dup = self.duplicate_find(requestId, roomKey, deviceKey,
                                  state, brightness)
        if dup is not None:
            return (True, dup.resultSuccess == ESPNOW_RESULT_OK,
                    dup.resultState, dup.resultBrightness,
                    dup.resultErrorCode)

        route = self.routes.get((roomKey, deviceKey))
        if route is None:
            self.duplicate_store(requestId, roomKey, deviceKey,
                                 state, brightness,
                                 ESPNOW_STATE_OFF, 0,
                                 ESPNOW_RESULT_ERROR,
                                 ESPNOW_ERR_UNKNOWN_DEVICE)
            return (False, False, ESPNOW_STATE_OFF, 0,
                    ESPNOW_ERR_UNKNOWN_DEVICE)

        if brightness > 100:
            self.duplicate_store(requestId, roomKey, deviceKey,
                                 state, brightness,
                                 ESPNOW_STATE_OFF, 0,
                                 ESPNOW_RESULT_ERROR,
                                 ESPNOW_ERR_INVALID_BRIGHTNESS)
            return (False, False, ESPNOW_STATE_OFF, 0,
                    ESPNOW_ERR_INVALID_BRIGHTNESS)

        if state not in (ESPNOW_STATE_OFF, ESPNOW_STATE_ON):
            self.duplicate_store(requestId, roomKey, deviceKey,
                                 state, brightness,
                                 ESPNOW_STATE_OFF, 0,
                                 ESPNOW_RESULT_ERROR,
                                 ESPNOW_ERR_INVALID_STATE)
            return (False, False, ESPNOW_STATE_OFF, 0,
                    ESPNOW_ERR_INVALID_STATE)

        final_state = state
        if state == ESPNOW_STATE_ON:
            if route["dimmable"]:
                final_brightness = brightness if brightness > 0 else 1
            else:
                final_brightness = 100
        else:
            final_brightness = brightness if route["dimmable"] else 0

        self.drive_count += 1  # setRelayState / dimmer drive happens here
        self.duplicate_store(requestId, roomKey, deviceKey,
                             state, brightness,
                             final_state, final_brightness,
                             ESPNOW_RESULT_OK, 0)
        return (False, True, final_state, final_brightness, 0)


def run_behavioral_tests():
    # 1. Exact Master retry (identical requestId/route/state/brightness)
    #    -> single physical drive, cached result replayed.
    s = SlaveMirror()
    r1 = s.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 30, "req-A")
    r2 = s.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 30, "req-A")
    check("retry: first command processed (not dup)", r1[0] is False)
    check("retry: replay is a cache hit", r2[0] is True)
    check("retry: hardware driven exactly once", s.drive_count == 1)
    check("retry: cached result replayed (brightness 30, OK)",
          r2[1] is True and r2[2] == ESPNOW_STATE_ON and r2[3] == 30)

    # 2. Same requestId, same route, different state -> NOT a duplicate.
    s = SlaveMirror()
    s.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 30, "req-B")
    r = s.apply_command("kamar_1", "lampu", ESPNOW_STATE_OFF, 30, "req-B")
    check("collision-state: second command NOT suppressed", r[0] is False)
    check("collision-state: second command drove hardware",
          s.drive_count == 2)

    # 3. Same requestId, same route, same state, different brightness
    #    (dimmable) -> NOT a duplicate.
    s = SlaveMirror()
    s.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 30, "req-C")
    r = s.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 80, "req-C")
    check("collision-brightness: NOT suppressed", r[0] is False)
    check("collision-brightness: drove hardware", s.drive_count == 2)
    check("collision-brightness: new result brightness 80", r[3] == 80)

    # 4. New requestId, identical payload -> processed normally.
    s = SlaveMirror()
    s.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 30, "req-D1")
    r = s.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 30, "req-D2")
    check("new-id: NOT suppressed", r[0] is False)
    check("new-id: drove hardware", s.drive_count == 2)

    # 5. Same requestId + payload on a different route -> no cross-hit.
    s = SlaveMirror()
    s.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 30, "req-E")
    r = s.apply_command("dapur", "lampu", ESPNOW_STATE_ON, 30, "req-E")
    check("cross-route: NOT suppressed", r[0] is False)
    check("cross-route: drove hardware", s.drive_count == 2)

    # 6. Eviction boundary: 9th distinct key evicts the oldest; replaying
    #    an evicted key re-executes; retained keys still deduplicate.
    s = SlaveMirror()
    for i in range(8):
        s.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 10 + i,
                        "req-F%d" % i)
    drives_after_8 = s.drive_count
    r = s.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 10, "req-F0")
    check("eviction: oldest still cached at 8 entries", r[0] is True)
    check("eviction: no extra drive on cached replay",
          s.drive_count == drives_after_8)
    s.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 99, "req-F8")
    r = s.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 10, "req-F0")
    check("eviction: evicted key re-executes (not dup)", r[0] is False)
    check("eviction: evicted key re-drives hardware",
          s.drive_count == drives_after_8 + 2)
    # Note: re-executing evicted F0 stored it again, evicting F1 (FIFO).
    # F2..F7 are still resident and must still deduplicate.
    r = s.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 12, "req-F2")
    check("eviction: surviving key still deduplicates", r[0] is True)

    # 7. Failure paths are cached with their transmitted payload key, and a
    #    malformed/unknown-device entry does not corrupt later traffic.
    s = SlaveMirror()
    r1 = s.apply_command("kamar_9", "lampu", ESPNOW_STATE_ON, 50, "req-G")
    r2 = s.apply_command("kamar_9", "lampu", ESPNOW_STATE_ON, 50, "req-G")
    check("failure: unknown device errors", r1[1] is False and
          r1[4] == ESPNOW_ERR_UNKNOWN_DEVICE)
    check("failure: exact replay of failure is cached", r2[0] is True)
    check("failure: cached replay keeps error code",
          r2[1] is False and r2[4] == ESPNOW_ERR_UNKNOWN_DEVICE)
    r3 = s.apply_command("kamar_9", "lampu", ESPNOW_STATE_ON, 51, "req-G")
    check("failure: changed payload on failed id is new", r3[0] is False)
    r4 = s.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 30, "req-G")
    check("failure: other routes unaffected after errors", r4[0] is False
          and r4[1] is True)

    # 8. Non-dimmable exact retry with Master normalization
    #    (state-only device: Master transmits brightness=100 for ON,
    #    0 for OFF) -> still a cache hit.
    s = SlaveMirror()
    s.apply_command("lorong", "blower", ESPNOW_STATE_ON, 100, "req-H")
    r = s.apply_command("lorong", "blower", ESPNOW_STATE_ON, 100, "req-H")
    check("non-dimmable retry: cache hit", r[0] is True)
    check("non-dimmable retry: single drive", s.drive_count == 1)

    # 9. Dimmable ON with transmitted brightness 0 (normalized to 1 by the
    #    firmware result, but keyed by the transmitted 0) -> retry hits.
    s = SlaveMirror()
    r1 = s.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 0, "req-I")
    r2 = s.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 0, "req-I")
    check("normalize: result brightness clamped to 1", r1[3] == 1)
    check("normalize: retry with transmitted 0 still hits", r2[0] is True)
    check("normalize: single drive", s.drive_count == 1)


def main():
    run_static_source_checks()
    run_behavioral_tests()
    print("\n%d passed, %d failed" % (_passed, _failed))
    return 0 if _failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
