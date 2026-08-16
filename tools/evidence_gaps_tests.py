#!/usr/bin/env python3
"""
Issue #2 evidence-gap closure: deterministic host-side mirror tests.

These tests transcribe, line-for-line, the pure decision logic extracted from
the revised firmware sources.  The firmware has no host test harness and no
native compiler is present in this environment, so each function below is a
faithful transcription of the exact C++ predicate/branching, with the source
location recorded above it.  The transcribed logic is identical in structure,
operators, and ordering to the C++ original; only hardware I/O (Serial, GPIO,
millis()) is replaced by deterministic fakes.

Sources referenced (read via `git show` on the corresponding revision):
  Master f8c960e : src/firebase_command_router.cpp
  Slave  6d306cf : src/room_device_routing.cpp

Run:  python tools/evidence_gaps_tests.py
"""

# ---------------------------------------------------------------------------
# TASK 1.2 — Master command freshness (commandIsFresh)
# src/firebase_command_router.cpp (Master f8c960e)
# ---------------------------------------------------------------------------
COMMAND_FUTURE_TOLERANCE_MS = 5000
COMMAND_MAX_AGE_MS = 15000


def command_is_fresh(issued_at_ms, now_ms):
    """
    Exact transcription of:
      bool commandIsFresh(int64_t issuedAtMs)
    (ignoring the NTP guard, which is a pre-condition, not the boundary math)
      if (issuedAtMs > nowMs + COMMAND_FUTURE_TOLERANCE_MS) return false;
      if (issuedAtMs <= nowMs - COMMAND_MAX_AGE_MS) return false;
      return true;
    """
    if issued_at_ms > now_ms + COMMAND_FUTURE_TOLERANCE_MS:
        return False
    if issued_at_ms <= now_ms - COMMAND_MAX_AGE_MS:
        return False
    return True


def master_freshness_offsets():
    """Return (offset_ms, accepted) for a fixed validator clock now_ms=0."""
    now_ms = 0
    offsets = [-15001, -15000, -14999, -1, 0, 1, 4999, 5000, 5001]
    return [(o, command_is_fresh(now_ms + o, now_ms)) for o in offsets]


# ---------------------------------------------------------------------------
# TASK 5 — Master shared-bedroom dimmer arbitration
# src/firebase_command_router.cpp (Master f8c960e)
# ---------------------------------------------------------------------------

# strcmp(a,b) > 0  <=>  a > b   for ASCII strings (byte lexicographic order).
def strcmp_gt(a, b):
    return a > b


SHARED_ROUTES = [("kamar_1", "lampu"), ("kamar_2", "lampu")]


class MasterRoute:
    def __init__(self, room, device):
        self.room = room
        self.device = device
        self.desired_known = False
        self.desired_state = False
        self.desired_brightness = 0
        self.desired_request_id = ""
        self.desired_issued_at_ms = 0
        self.actual_known = False
        self.actual_state = False
        self.actual_brightness = 0


class MasterDimmerArbiter:
    """Transcription of Master-side shared CH1 arbitration state."""

    def __init__(self):
        self.routes = {}
        for room, device in SHARED_ROUTES:
            self.routes[(room, device)] = MasterRoute(room, device)
        self.shared_desired_brightness = 0
        self.shared_issued_at_ms = 0
        self.shared_request_id = ""
        self.shared_owner_route = -1  # -1 = none

    def uses_shared(self, key):
        return key in self.routes

    # commandVersionIsNewer(int64_t issuedAtMs, const char* requestId, route)
    def command_version_is_newer(self, issued_at_ms, request_id, key):
        route = self.routes[key]
        return (not route.desired_known
                or issued_at_ms > route.desired_issued_at_ms
                or (issued_at_ms == route.desired_issued_at_ms
                    and strcmp_gt(request_id, route.desired_request_id)))

    # sharedBedroomVersionIsNewer(int64_t issuedAtMs, const char* requestId)
    def shared_version_is_newer(self, issued_at_ms, request_id):
        return (self.shared_owner_route < 0
                or issued_at_ms > self.shared_issued_at_ms
                or (issued_at_ms == self.shared_issued_at_ms
                    and strcmp_gt(request_id, self.shared_request_id)))

    # Transcription of the shared-brightness update inside acceptDesired():
    #   bool sharedBrightnessChanged = usesSharedBedroomDimmer(route) &&
    #       command.brightness > 0 &&
    #       sharedBedroomVersionIsNewer(issuedAt, requestId);
    #   if (sharedBrightnessChanged) { ...sharedBedroomOwnerRoute = idx; }
    # plus the per-route desired update (relay state independent).
    def accept_command(self, room, device, state, brightness,
                       issued_at_ms, request_id):
        key = (room, device)
        assert self.uses_shared(key), "only shared routes supported here"
        route = self.routes[key]
        # freshness is validated by commandIsFresh before this point.
        if not self.command_version_is_newer(issued_at_ms, request_id, key):
            return ("ignored (older/duplicate version)",)

        route.desired_known = True
        route.desired_state = state
        route.desired_brightness = brightness
        route.desired_request_id = request_id
        route.desired_issued_at_ms = issued_at_ms

        idx = SHARED_ROUTES.index(key)
        if (brightness > 0
                and self.shared_version_is_newer(issued_at_ms, request_id)):
            self.shared_desired_brightness = brightness
            self.shared_issued_at_ms = issued_at_ms
            self.shared_request_id = request_id
            self.shared_owner_route = idx
        return None  # accepted

    # desiredBrightnessForRoute(routeIndex)
    def reported_brightness(self, key):
        route = self.routes[key]
        if self.uses_shared(key):
            if self.shared_owner_route >= 0:
                return self.shared_desired_brightness
            return route.actual_brightness if route.actual_known \
                else route.desired_brightness
        return route.desired_brightness


# ---------------------------------------------------------------------------
# TASK 2 / 3 — Slave duplicate cache (room_device_routing.cpp, Slave 6d306cf)
# ---------------------------------------------------------------------------
DUPLICATE_CACHE_SIZE = 8


class DuplicateCache:
    """Exact transcription of the ring-buffer duplicate cache."""

    def __init__(self):
        self.entries = [None] * DUPLICATE_CACHE_SIZE
        self.index = 0

    def find(self, request_id, room_key, device_key):
        for e in self.entries:
            if e is not None and \
                    e["requestId"] == request_id and \
                    e["roomKey"] == room_key and \
                    e["deviceKey"] == device_key:
                return e
        return None

    def store(self, request_id, room_key, device_key, state, brightness,
              success, error_code):
        self.entries[self.index] = {
            "requestId": request_id,
            "roomKey": room_key,
            "deviceKey": device_key,
            "resultState": state,
            "resultBrightness": brightness,
            "resultSuccess": success,
            "resultErrorCode": error_code,
        }
        self.index = (self.index + 1) % DUPLICATE_CACHE_SIZE

    def used_count(self):
        return sum(1 for e in self.entries if e is not None)


# --- Slave hardware fake (deterministic stand-in for relay/dimmer GPIO) ----
# Slave route table (room_device_routing.cpp):
SLAVE_ROUTE_TABLE = [
    ("kamar_1", "lampu", "RELAY_KAMAR1_LAMPU", 1, True),
    ("kamar_2", "lampu", "RELAY_KAMAR2_LAMPU", 1, True),
    ("dapur", "lampu", "RELAY_DAPUR_LAMPU", 2, True),
    ("lorong", "stop_kontak", "RELAY_LORONG_STOP_KONTAK", 0, False),
    ("lorong", "blower", "RELAY_LORONG_BLOWER", 0, False),
    ("kamar_1", "stop_kontak", "RELAY_KAMAR1_STOP_KONTAK", 0, False),
    ("kamar_2", "stop_kontak", "RELAY_KAMAR2_STOP_KONTAK", 0, False),
    ("dapur", "blower", "RELAY_DAPUR_BLOWER", 0, False),
]

ESPNOW_STATE_OFF = 0
ESPNOW_STATE_ON = 1
ESPNOW_RESULT_OK = 1
ESPNOW_RESULT_ERROR = 0
ESPNOW_ERR_UNKNOWN_DEVICE = 1
ESPNOW_ERR_INVALID_STATE = 2
ESPNOW_ERR_INVALID_BRIGHTNESS = 3


class SlaveHardware:
    """Deterministic relay/dimmer chip + duplicate-cache state."""

    def __init__(self):
        self.relay = {}        # relayId -> bool
        self.dimmer = {}       # channel -> int brightness
        self.dimmer_enabled = {}
        for room, device, relay, chan, dim in SLAVE_ROUTE_TABLE:
            self.relay[relay] = False
        self.cache = DuplicateCache()
        self.drive_count = 0   # counts hardware-driving paths (statistics)

    def find_entry(self, room, device):
        for row in SLAVE_ROUTE_TABLE:
            if row[0] == room and row[1] == device:
                return row
        return None

    def relay_state(self, relay_id):
        return self.relay[relay_id]

    def set_relay_state(self, relay_id, on):
        self.relay[relay_id] = on

    def get_dimmer_brightness(self, channel):
        return self.dimmer.get(channel, 0)

    def set_dimmer_brightness(self, channel, brightness):
        self.dimmer[channel] = brightness

    def set_dimmer_enabled(self, channel, enabled):
        self.dimmer_enabled[channel] = enabled

    def has_other_active_relay_on_dimmer(self, current_entry):
        for row in SLAVE_ROUTE_TABLE:
            if row is not current_entry and \
                    row[3] == current_entry[3] and \
                    self.relay_state(row[2]):
                return True
        return False

    # `applyDeviceCommand` transcription — see room_device_routing.cpp.
    # Command has: roomKey, deviceKey, state (0/1), brightness, requestId.
    def apply_command(self, room, device, state, brightness, request_id):
        dup = self.cache.find(request_id, room, device)
        if dup is not None:
            return {
                "state": dup["resultState"],
                "brightness": dup["resultBrightness"],
                "success": dup["resultSuccess"],
                "errorCode": dup["resultErrorCode"],
                "duplicate": True,
            }

        entry = self.find_entry(room, device)
        if entry is None:
            self.cache.store(request_id, room, device, 0, 0,
                             ESPNOW_RESULT_ERROR, ESPNOW_ERR_UNKNOWN_DEVICE)
            return {"state": 0, "brightness": 0,
                    "success": ESPNOW_RESULT_ERROR,
                    "errorCode": ESPNOW_ERR_UNKNOWN_DEVICE, "duplicate": False}

        room_k, device_k, relay_id, channel, is_dimmable = entry

        if brightness > 100:
            self.cache.store(request_id, room, device, 0, 0,
                             ESPNOW_RESULT_ERROR, ESPNOW_ERR_INVALID_BRIGHTNESS)
            return {"state": 0, "brightness": 0,
                    "success": ESPNOW_RESULT_ERROR,
                    "errorCode": ESPNOW_ERR_INVALID_BRIGHTNESS,
                    "duplicate": False}

        if state == ESPNOW_STATE_OFF:
            final_state = ESPNOW_STATE_OFF
            if is_dimmable:
                final_brightness = \
                    self.get_dimmer_brightness(channel) \
                    if self.has_other_active_relay_on_dimmer(entry) \
                    else brightness
            else:
                final_brightness = 0
        elif state == ESPNOW_STATE_ON:
            final_state = ESPNOW_STATE_ON
            final_brightness = brightness
            if is_dimmable:
                if final_brightness == 0:
                    final_brightness = 1
            else:
                final_brightness = 100
        else:
            self.cache.store(request_id, room, device, 0, 0,
                             ESPNOW_RESULT_ERROR, ESPNOW_ERR_INVALID_STATE)
            return {"state": 0, "brightness": 0,
                    "success": ESPNOW_RESULT_ERROR,
                    "errorCode": ESPNOW_ERR_INVALID_STATE, "duplicate": False}

        # Apply hardware
        self.set_relay_state(relay_id, (final_state == ESPNOW_STATE_ON))
        self.drive_count += 1  # increment every hardware-driving invocation

        if channel > 0:
            channel_needed = (final_state == ESPNOW_STATE_ON
                              or self.has_other_active_relay_on_dimmer(entry))
            if not channel_needed:
                final_brightness = 0
            elif final_brightness == 0:
                final_brightness = self.get_dimmer_brightness(channel)
            if channel_needed and final_brightness == 0:
                final_brightness = 1
            if not channel_needed:
                self.set_dimmer_enabled(channel, False)
            self.set_dimmer_brightness(channel, final_brightness)
            if channel_needed:
                self.set_dimmer_enabled(channel, True)
            final_brightness = self.get_dimmer_brightness(channel)

        self.cache.store(request_id, room, device, final_state,
                         final_brightness, ESPNOW_RESULT_OK, 0)
        return {"state": final_state, "brightness": final_brightness,
                "success": ESPNOW_RESULT_OK, "errorCode": 0,
                "duplicate": False}


# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------
PASS = 0
FAIL = 0


def check(name, cond):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("PASS  %s" % name)
    else:
        FAIL += 1
        print("FAIL  %s" % name)


def eq(name, got, want):
    check("%s ==> %r" % (name, got), got == want)


def run_master_freshness():
    print("\n== TASK 1.3 Master commandIsFresh boundary (now fixed) ==")
    now_ms = 0
    expected = {
        -15001: False, -15000: False, -14999: True, -1: True, 0: True,
        1: True, 4999: True, 5000: True, 5001: False,
    }
    for o in [-15001, -15000, -14999, -1, 0, 1, 4999, 5000, 5001]:
        got = command_is_fresh(now_ms + o, now_ms)
        eq("Master offset %+d accepted" % o, got, expected[o])
    print("\nMaster boundary results (now_ms=0):")
    print("%-10s %s" % ("offset", "accepted"))
    for o in expected:
        print("%+7d  %s" % (o, command_is_fresh(now_ms + o, now_ms)))


def run_rtdb_table():
    print("\n== TASK 1.1 RTDB rule boundary (inclusive; from rule source) ==")
    # database.rules.json:  issued_at >= now-15000 && issued_at <= now+5000
    def rtdb_accept(offset):
        return offset >= -15000 and offset <= 5000
    print("%-10s %s" % ("offset", "accepted"))
    for o in [-15001, -15000, -14999, -1, 0, 1, 4999, 5000, 5001]:
        print("%+7d  %s" % (o, rtdb_accept(o)))


def run_duplicate():
    print("\n== TASK 2 request_id duplicate (exact replay) ==")
    hw = SlaveHardware()
    r1 = hw.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 30, "req-A")
    eq("first cmd applied (not duplicate)", r1["duplicate"], False)
    eq("first drive count == 1", hw.drive_count, 1)
    r2 = hw.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 30, "req-A")
    eq("second cmd recognized as duplicate", r2["duplicate"], True)
    eq("side-effect suppressed (drive count still 1)", hw.drive_count, 1)
    eq("cached result brightness consistent", r2["brightness"], 30)
    eq("cached result success consistent", r2["success"], ESPNOW_RESULT_OK)

    # TASK 3.1 same request_id, different route
    hw2 = SlaveHardware()
    hw2.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 30, "req-A")
    other = hw2.apply_command("dapur", "lampu", ESPNOW_STATE_ON, 50, "req-A")
    eq("same request_id different route NOT duplicate", other["duplicate"],
       False)
    eq("different route driven (dapur drive)", hw2.drive_count, 2)


def run_collision():
    print("\n== TASK 3 request_id collision (same id, same route, diff payload) ==")
    hw = SlaveHardware()
    r1 = hw.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 30, "req-A")
    r2 = hw.apply_command("kamar_1", "lampu", ESPNOW_STATE_OFF, 0, "req-A")
    eq("second treated as duplicate despite diff payload", r2["duplicate"],
       True)
    eq("stale cached brightness returned", r2["brightness"], 30)
    eq("stale cached state returned", r2["state"], ESPNOW_STATE_ON)
    eq("legit newer command suppressed (drive count 1)", hw.drive_count, 1)


def run_eviction():
    print("\n== TASK 2.2 duplicate cache eviction (ring of 8) ==")
    hw = SlaveHardware()
    ids = ["req-A", "req-B", "req-C", "req-D",
           "req-E", "req-F", "req-G", "req-H"]
    for i, rid in enumerate(ids):
        hw.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 10 + i, rid)
    eq("cache full at 8", hw.cache.used_count(), 8)
    check("all 8 entries present before eviction",
          all(hw.cache.find(rid, "kamar_1", "lampu") is not None
              for rid in ids))
    # replay A while still cached
    eq("replay A before eviction is duplicate",
       hw.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 10,
                        "req-A")["duplicate"], True)
    # 9th unique insert (I) evicts A (FIFO)
    hw.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 99, "req-I")
    check("A evicted after 9th unique insert",
          hw.cache.find("req-A", "kamar_1", "lampu") is None)
    check("B..H still present after single eviction",
          all(hw.cache.find(rid, "kamar_1", "lampu") is not None
              for rid in ids[1:]))
    check("I present (newest)",
          hw.cache.find("req-I", "kamar_1", "lampu") is not None)
    # behavioral: replaying an evicted request_id is NOT a duplicate and
    # re-drives hardware.
    before = hw.drive_count
    r = hw.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 10, "req-A")
    eq("replaying evicted A is no longer a duplicate", r["duplicate"], False)
    eq("evicted A re-drives hardware", hw.drive_count, before + 1)


def run_dimmer():
    print("\n== TASK 5 shared bedroom dimmer arbitration ==")

    # Scenario A
    hw = SlaveHardware()
    hw.apply_command("kamar_1", "lampu", ESPNOW_STATE_ON, 30, "A")
    a = {
        "k1_relay": hw.relay_state("RELAY_KAMAR1_LAMPU"),
        "k2_relay": hw.relay_state("RELAY_KAMAR2_LAMPU"),
        "ch1": hw.get_dimmer_brightness(1),
    }
    check("A: K1 relay ON", a["k1_relay"] is True)
    check("A: K2 relay unchanged OFF", a["k2_relay"] is False)
    eq("A: shared CH1 brightness == 30", a["ch1"], 30)

    # Scenario B (from K1 ON 30)
    hw.apply_command("kamar_2", "lampu", ESPNOW_STATE_ON, 80, "B")
    check("B: K1 relay remains ON", hw.relay_state("RELAY_KAMAR1_LAMPU") is True)
    check("B: K2 relay ON", hw.relay_state("RELAY_KAMAR2_LAMPU") is True)
    eq("B: shared CH1 brightness == 80", hw.get_dimmer_brightness(1), 80)

    # Scenario C (both ON 80, K1 OFF)
    hw.apply_command("kamar_1", "lampu", ESPNOW_STATE_OFF, 0, "C")
    check("C: K1 relay OFF", hw.relay_state("RELAY_KAMAR1_LAMPU") is False)
    check("C: K2 relay stays ON", hw.relay_state("RELAY_KAMAR2_LAMPU") is True)
    eq("C: shared CH1 brightness retained (80)", hw.get_dimmer_brightness(1), 80)

    # Scenario F (both OFF -> CH1 brightness 0)
    hw.apply_command("kamar_2", "lampu", ESPNOW_STATE_OFF, 0, "F")
    check("F: K2 relay OFF", hw.relay_state("RELAY_KAMAR2_LAMPU") is False)
    eq("F: shared CH1 brightness == 0", hw.get_dimmer_brightness(1), 0)

    # Scenario D (ordering, newest wins) via Master arbiter
    print("\n  -- Scenario D/E (Master 'newest wins' semantic arbitration) --")
    arb = MasterDimmerArbiter()
    # K2 newer (2000) applied first, then old K1 (1000) delivered late
    arb.accept_command("kamar_2", "lampu", True, 80, 2000, "B")
    arb.accept_command("kamar_1", "lampu", True, 30, 1000, "A")
    eq("D: shared brightness stays 80 (old K1 cannot overwrite)",
       arb.shared_desired_brightness, 80)
    eq("D: K1 reports shared brightness 80",
       arb.reported_brightness(("kamar_1", "lampu")), 80)
    eq("D: K2 reports shared brightness 80",
       arb.reported_brightness(("kamar_2", "lampu")), 80)

    # Scenario E (tie-break: identical issued_at, different request_id)
    arb2 = MasterDimmerArbiter()
    arb2.accept_command("kamar_1", "lampu", True, 30, 1000, "A")
    arb2.accept_command("kamar_2", "lampu", True, 80, 1000, "B")
    eq("E: lexicographically larger request_id ('B') wins tie",
       arb2.shared_request_id, "B")
    eq("E: shared brightness == 80", arb2.shared_desired_brightness, 80)
    # reverse order: A delivered after B at same timestamp must NOT win
    arb3 = MasterDimmerArbiter()
    arb3.accept_command("kamar_1", "lampu", True, 80, 1000, "B")
    arb3.accept_command("kamar_2", "lampu", True, 30, 1000, "A")
    eq("E: 'A' at same ts cannot displace 'B'", arb3.shared_request_id, "B")
    eq("E: shared brightness remains 80", arb3.shared_desired_brightness, 80)


def main():
    global PASS, FAIL
    run_master_freshness()
    run_rtdb_table()
    run_duplicate()
    run_collision()
    run_eviction()
    run_dimmer()
    print("\n==== SUMMARY: %d passed, %d failed ====" % (PASS, FAIL))
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
