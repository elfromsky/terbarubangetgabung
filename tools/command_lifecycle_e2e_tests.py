#!/usr/bin/env python3
"""
Issue #23 - deterministic command-lifecycle E2E simulation.

This test drives a logical command across every stage of the real lifecycle

    Flutter producer
        -> Firebase RTDB representation (rules-equivalent validation)
        -> ESP32 Master (parse / freshness / ordering / shared-dimmer)
        -> Master-local relay execution  (teras/lampu, teras/sanyo)
        -> Master -> Slave ESP-NOW command (Slave-owned routes)
        -> Slave execution (relay / dimmer, payload-aware dedup)
        -> Slave ACK / state report
        -> Master state publication (/rooms/...)
        -> Flutter state consumption (mapper-equivalent)

without any physical ESP32 hardware.  It is a *behavioral* mirror of the
production decision logic, transcribed line-for-line from the current sources:

  - Flutter producer:
      apps/flutter/lib/features/monitoring/data/datasources/firebase_room_device_data_source.dart
      apps/flutter/lib/features/monitoring/data/repositories/monitoring_repository_impl.dart
  - Firebase RTDB rules:
      firebase/database.rules.json
  - Master:
      firmware/master/src/firebase_command_router.cpp
      firmware/master/src/relay.cpp
  - Slave:
      firmware/slave/src/room_device_routing.cpp
  - Flutter consumer:
      apps/flutter/lib/features/monitoring/data/mappers/room_device_mapper.dart

The route tables and freshness constants are *parsed from those sources at
runtime*, not hardcoded, so the simulator cannot silently drift from the real
route/freshness configuration (the same anti-drift approach used by
tools/contract_tests.py).  A refactor that renames a route or changes a
freshness bound fails this test loudly rather than passing against stale
assumptions.

This is intentionally NOT a re-implementation of the Issue #22 contract checks.
Issue #22 pins that the *components agree with each other*; this test pins that
a *contract-consistent set of components behaves correctly end-to-end*.

Determinism guarantees:
  - no time.time()/datetime.now()/random/secrets - a SimClock and fixed
    deterministic request ids are used throughout;
  - no network, no Firebase, no secrets, no hardware.

Run:  python tools/command_lifecycle_e2e_tests.py
Exit code 0 = all E2E scenarios pass, non-zero = failure.
"""

import os
import re
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MASTER_ROUTER_SRC = os.path.join(
    REPO_ROOT, "firmware", "master", "src", "firebase_command_router.cpp")
MASTER_RELAY_SRC = os.path.join(
    REPO_ROOT, "firmware", "master", "src", "relay.cpp")
SLAVE_ROUTING_SRC = os.path.join(
    REPO_ROOT, "firmware", "slave", "src", "room_device_routing.cpp")
FIREBASE_RULES_SRC = os.path.join(REPO_ROOT, "firebase", "database.rules.json")
FLUTTER_CMD_SRC = os.path.join(
    REPO_ROOT, "apps", "flutter", "lib", "features", "monitoring", "data",
    "datasources", "firebase_room_device_data_source.dart")
FLUTTER_REPO_SRC = os.path.join(
    REPO_ROOT, "apps", "flutter", "lib", "features", "monitoring", "data",
    "repositories", "monitoring_repository_impl.dart")
FLUTTER_MAPPER_SRC = os.path.join(
    REPO_ROOT, "apps", "flutter", "lib", "features", "monitoring", "data",
    "mappers", "room_device_mapper.dart")


class ConfigError(RuntimeError):
    """Raised when the simulator cannot read a required source invariant."""


def _read(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def _require(cond, what):
    if not cond:
        raise ConfigError(
            "Simulator could not extract %s from source. A refactor likely "
            "changed the production format; fix this parser rather than "
            "hardcoding." % what)


# ---------------------------------------------------------------------------
# Source-anchored configuration (parsed, never hardcoded)
# ---------------------------------------------------------------------------

def parse_master_routes():
    """(room, device, owner, dimmable) in source order."""
    src = _read(MASTER_ROUTER_SRC)
    rows = re.findall(
        r'\{\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*'
        r'DeviceOwner::(\w+)\s*,\s*(true|false)\s*,', src)
    _require(rows, "Master routes[] table")
    return [(r, d, o, dim == "true") for r, d, o, dim in rows]


def parse_slave_routes():
    """(room, device, relay_id, channel, dimmable) in source order."""
    src = _read(SLAVE_ROUTING_SRC)
    rows = re.findall(
        r'\{\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*'
        r'(\w+)\s*,\s*(\d+)\s*,\s*(true|false)\s*\}', src)
    _require(rows, "Slave ROUTE_TABLE")
    return [(r, d, relay, int(ch), dim == "true")
            for r, d, relay, ch, dim in rows]


def parse_freshness_constants():
    src = _read(MASTER_ROUTER_SRC)
    future = re.search(r"COMMAND_FUTURE_TOLERANCE_MS\s*=\s*(\d+)", src)
    age = re.search(r"COMMAND_MAX_AGE_MS\s*=\s*(\d+)", src)
    _require(future and age, "Master freshness constants")
    return int(future.group(1)), int(age.group(1))


def parse_rtdb_freshness_bounds():
    src = _read(FIREBASE_RULES_SRC)
    past = re.search(r"now\s*-\s*(\d+)", src)
    future = re.search(r"now\s*\+\s*(\d+)", src)
    _require(past and future, "RTDB freshness bounds")
    return int(past.group(1)), int(future.group(1))


def parse_rtdb_device_whitelist():
    """(room, device) pairs admitted by the command .write rule."""
    src = _read(FIREBASE_RULES_SRC)
    pairs = set(re.findall(
        r"\$room == '([^']+)' && \(\$device == '([^']+)'"
        r"(?: \|\| \$device == '([^']+)')?\)", src))
    _require(pairs, "RTDB command whitelist")
    out = set()
    for room, d1, d2 in pairs:
        out.add((room, d1))
        if d2:
            out.add((room, d2))
    return out


COMMAND_FUTURE_TOLERANCE_MS, COMMAND_MAX_AGE_MS = parse_freshness_constants()
RTDB_MAX_AGE_MS, RTDB_FUTURE_TOLERANCE_MS = parse_rtdb_freshness_bounds()
MASTER_ROUTES = parse_master_routes()
SLAVE_ROUTES = parse_slave_routes()
RTDB_WHITELIST = parse_rtdb_device_whitelist()

# Cross-check the two route tables agree (Slave table == Master Slave-owned).
_master_slave = {(r, d) for r, d, o, _ in MASTER_ROUTES if o == "Slave"}
_slave = {(r, d) for r, d, _, _, _ in SLAVE_ROUTES}
_require(_master_slave == _slave,
         "Master Slave-owned routes vs Slave ROUTE_TABLE mismatch: master-only "
         "%s, slave-only %s"
         % (sorted(_master_slave - _slave), sorted(_slave - _master_slave)))


# ---------------------------------------------------------------------------
# Deterministic clock
# ---------------------------------------------------------------------------

EPOCH_BASE_MS = 1_800_000_000_000


class SimClock:
    def __init__(self, epoch_ms=EPOCH_BASE_MS):
        self.now_ms = epoch_ms

    def now(self):
        return self.now_ms

    def advance_ms(self, ms):
        self.now_ms += ms
        return self.now_ms


# ---------------------------------------------------------------------------
# Stage: Flutter command producer
# (firebase_room_device_data_source.dart + monitoring_repository_impl.dart)
# ---------------------------------------------------------------------------

class FlutterProducer:
    """Mirrors roomDeviceCommandPayload + controlRoomDevice pairing.

    ``server_offset_ms`` is pinned to 0 (deterministic).  ``issued_at`` is
    therefore exactly ``clock.now()`` in epoch milliseconds.
    """

    def __init__(self, clock):
        self.clock = clock
        self.server_offset_ms = 0
        self._seq = 0

    def issued_at_now(self):
        return self.clock.now() + self.server_offset_ms

    def next_request_id(self):
        self._seq += 1
        return "req-%08d" % self._seq

    @staticmethod
    def make_payload(is_on, brightness, supports_brightness, request_id,
                     issued_at):
        # roomDeviceCommandPayload
        if not isinstance(request_id, str) or not (1 <= len(request_id) <= 31):
            raise ValueError("requestId must be 1..31 characters")
        normalized = max(0, min(100, int(brightness)))
        if supports_brightness and is_on and normalized == 0:
            normalized = 1
        payload = {"state": is_on, "request_id": request_id,
                   "issued_at": issued_at}
        if supports_brightness:
            payload["brightness"] = normalized
        return payload

    @staticmethod
    def paired_room(room, device, supports_brightness):
        # _pairedBedroomRoomKey
        if not supports_brightness or device != "lampu":
            return None
        if room == "kamar_1":
            return "kamar_2"
        if room == "kamar_2":
            return "kamar_1"
        return None

    def control(self, room, device, is_on, brightness, supports_brightness,
                latest_states, issued_at, request_ids=None):
        """Returns [(room, device, payload), ...] (primary + companion)."""
        normalized = max(0, min(100, int(brightness)))
        if supports_brightness and is_on and normalized == 0:
            normalized = 1

        entries = [(room, device, is_on, normalized, supports_brightness)]
        paired = self.paired_room(room, device, supports_brightness)
        if paired is not None:
            paired_state = latest_states.get((paired, device))
            if paired_state is None:
                raise RuntimeError("Status lampu pasangan belum tersedia")
            entries.append((paired, device, paired_state[0], normalized, True))

        out = []
        used = set()
        for i, (r, d, on, b, sb) in enumerate(entries):
            if request_ids and i < len(request_ids):
                rid = request_ids[i]
            else:
                rid = self.next_request_id()
            if rid in used:
                raise RuntimeError("duplicate request id in batch")
            used.add(rid)
            out.append((r, d, self.make_payload(on, b, sb, rid, issued_at)))
        return out


# ---------------------------------------------------------------------------
# Stage: Firebase RTDB representation (rules-equivalent)
# ---------------------------------------------------------------------------

class InMemoryRTDB:
    """Mirrors database.rules.json command write validation + state storage."""

    def __init__(self):
        self.commands = {}   # room -> device -> payload (command tree)
        self.rooms = {}      # room -> tools -> device -> state payload

    def validate_command_write(self, room, device, payload, now_ms):
        # .write whitelist
        if (room, device) not in RTDB_WHITELIST:
            return False, "unknown room/device"
        # hasChildren(['state','request_id','issued_at'])
        if not isinstance(payload, dict):
            return False, "payload not object"
        for required in ("state", "request_id", "issued_at"):
            if required not in payload:
                return False, "missing %s" % required
        # dimmer must have brightness, relay must not
        dimmer = (room in ("kamar_1", "kamar_2", "dapur")
                  and device == "lampu")
        if dimmer and "brightness" not in payload:
            return False, "dimmer missing brightness"
        if not dimmer and "brightness" in payload:
            return False, "relay must not carry brightness"
        if set(payload) - {"state", "brightness", "request_id", "issued_at"}:
            return False, "unknown field ($other)"
        # state bool
        if not isinstance(payload["state"], bool):
            return False, "state must be bool"
        # brightness 0..100 integer
        if "brightness" in payload:
            b = payload["brightness"]
            if isinstance(b, bool) or not isinstance(b, int) \
                    or not (0 <= b <= 100):
                return False, "brightness must be 0..100 integer"
        # request_id string 1..31
        rid = payload["request_id"]
        if not isinstance(rid, str) or not (1 <= len(rid) <= 31):
            return False, "request_id must be 1..31 string"
        # issued_at integer within [now-15000, now+5000]
        issued = payload["issued_at"]
        if isinstance(issued, bool) or not isinstance(issued, int):
            return False, "issued_at must be number"
        if not (now_ms - RTDB_MAX_AGE_MS <= issued
                <= now_ms + RTDB_FUTURE_TOLERANCE_MS):
            return False, "issued_at outside freshness window"
        return True, "ok"

    def accept_command(self, room, device, payload, now_ms):
        ok, reason = self.validate_command_write(room, device, payload, now_ms)
        if ok:
            self.commands.setdefault(room, {})[device] = payload
        return ok, reason

    def publish_state(self, room, device, payload):
        self.rooms.setdefault(room, {}).setdefault("tools", {})[device] = payload

    def state_snapshot(self):
        return self.rooms


# ---------------------------------------------------------------------------
# Stage: Master
# (firebase_command_router.cpp + relay.cpp)
# ---------------------------------------------------------------------------

class MasterRoute:
    def __init__(self, room, device, owner, dimmable):
        self.room = room
        self.device = device
        self.owner = owner            # "Master" or "Slave"
        self.dimmable = dimmable
        self.desired_known = False
        self.desired_state = False
        self.desired_brightness = 0
        self.desired_request_id = ""
        self.desired_issued_at_ms = 0
        self.actual_known = False
        self.actual_state = False
        self.actual_brightness = 0
        self.dirty = False
        self.publish_pending = False


class ParsedCommand:
    def __init__(self, valid, state=False, brightness=0, request_id="",
                 issued_at=0, reason=""):
        self.valid = valid
        self.state = state
        self.brightness = brightness
        self.request_id = request_id
        self.issued_at = issued_at
        self.reason = reason


class MasterRouter:
    def __init__(self, clock, rtdb, link):
        self.clock = clock
        self.rtdb = rtdb
        self.link = link
        self.routes = [MasterRoute(r, d, o, dim)
                       for r, d, o, dim in MASTER_ROUTES]
        self.master_relay_state = {}   # (room, device) -> bool (local relays)
        # shared bedroom dimmer arbitration
        self.shared_desired_brightness = 0
        self.shared_issued_at_ms = 0
        self.shared_request_id = ""
        self.shared_owner_key = None
        # side-effect counters (for duplicate/stale observability)
        self.master_local_execution_count = 0
        self.espnow_send_count = 0
        self.state_publish_count = 0

    # -- helpers ------------------------------------------------------------

    def find_route(self, room, device):
        for route in self.routes:
            if route.room == room and route.device == device:
                return route
        return None

    def uses_shared(self, route):
        # usesSharedBedroomDimmer
        return (route.owner == "Slave" and route.dimmable
                and route.device == "lampu"
                and route.room in ("kamar_1", "kamar_2"))

    def command_is_fresh(self, issued_at_ms):
        now_ms = self.clock.now()
        if issued_at_ms > now_ms + COMMAND_FUTURE_TOLERANCE_MS:
            return False
        if issued_at_ms <= now_ms - COMMAND_MAX_AGE_MS:
            return False
        return True

    def command_version_is_newer(self, issued_at_ms, request_id, route):
        return (not route.desired_known
                or issued_at_ms > route.desired_issued_at_ms
                or (issued_at_ms == route.desired_issued_at_ms
                    and request_id > route.desired_request_id))

    def shared_version_is_newer(self, issued_at_ms, request_id):
        return (self.shared_owner_key is None
                or issued_at_ms > self.shared_issued_at_ms
                or (issued_at_ms == self.shared_issued_at_ms
                    and request_id > self.shared_request_id))

    def desired_brightness_for_route(self, route):
        if not self.uses_shared(route):
            return route.desired_brightness
        if self.shared_owner_key is not None:
            return self.shared_desired_brightness
        return route.actual_brightness if route.actual_known \
            else route.desired_brightness

    # -- freshness of an already-accepted desired command -------------------

    def disable_desired(self, route, reason):
        if self.shared_owner_key == (route.room, route.device):
            self.shared_owner_key = None
            self.shared_desired_brightness = \
                route.actual_brightness if route.actual_known else 0
            self.shared_issued_at_ms = 0
            self.shared_request_id = ""
        route.desired_known = False
        route.desired_state = False
        route.desired_brightness = 0
        route.dirty = False
        route.desired_request_id = ""
        route.desired_issued_at_ms = 0

    def ensure_desired_fresh(self, route):
        if not route.desired_known:
            route.dirty = False
            return False
        if route.desired_issued_at_ms <= self.clock.now() - COMMAND_MAX_AGE_MS:
            self.disable_desired(route, "command expired")
            return False
        return True

    def actual_matches_desired(self, route):
        if not route.desired_known or not route.actual_known \
                or route.desired_state != route.actual_state:
            return False
        if not route.dimmable:
            return True
        if self.uses_shared(route):
            return self.shared_owner_key != (route.room, route.device) \
                or self.shared_desired_brightness == route.actual_brightness
        return ((not route.desired_state and route.desired_brightness == 0)
                or route.desired_brightness == route.actual_brightness)

    def refresh_dirty(self, route):
        route.dirty = self.ensure_desired_fresh(route) \
            and not self.actual_matches_desired(route)

    # -- parseCommand -------------------------------------------------------

    def parse_command(self, route, payload):
        if not isinstance(payload, dict):
            return ParsedCommand(False, reason="expected object")
        expected = 4 if route.dimmable else 3
        if len(payload) != expected:
            return ParsedCommand(False, reason="field count")
        state = payload.get("state")
        if not isinstance(state, bool):
            return ParsedCommand(False, reason="state must be bool")
        rid = payload.get("request_id")
        if not isinstance(rid, str) or not (1 <= len(rid) <= 31):
            return ParsedCommand(False, reason="request_id 1..31")
        issued_at = payload.get("issued_at")
        if isinstance(issued_at, bool) or not isinstance(issued_at, int):
            return ParsedCommand(False, reason="issued_at int")
        if not self.command_is_fresh(issued_at):
            return ParsedCommand(False, reason="stale_or_future")
        if not route.dimmable:
            return ParsedCommand(True, state=state, brightness=0,
                                 request_id=rid, issued_at=issued_at)
        brightness = payload.get("brightness")
        if isinstance(brightness, bool) or not isinstance(brightness, int):
            return ParsedCommand(False, reason="brightness int")
        if brightness < 0 or brightness > 100:
            return ParsedCommand(False, reason="brightness range")
        b = 1 if (state and brightness == 0) else brightness
        return ParsedCommand(True, state=state, brightness=b,
                             request_id=rid, issued_at=issued_at)

    # -- acceptDesired ------------------------------------------------------

    def accept_command(self, room, device, payload):
        route = self.find_route(room, device)
        if route is None:
            return {"outcome": "unknown_route"}
        cmd = self.parse_command(route, payload)
        if not cmd.valid:
            return {"outcome": cmd.reason}
        if not self.command_version_is_newer(cmd.issued_at, cmd.request_id,
                                             route):
            return {"outcome": "older_duplicate"}
        route.desired_known = True
        route.desired_state = cmd.state
        route.desired_brightness = cmd.brightness
        route.desired_request_id = cmd.request_id
        route.desired_issued_at_ms = cmd.issued_at

        shared_changed = (self.uses_shared(route) and cmd.brightness > 0
                          and self.shared_version_is_newer(cmd.issued_at,
                                                           cmd.request_id))
        if shared_changed:
            self.shared_desired_brightness = cmd.brightness
            self.shared_issued_at_ms = cmd.issued_at
            self.shared_request_id = cmd.request_id
            self.shared_owner_key = (room, device)
        self.refresh_dirty(route)
        return {"outcome": "accepted"}

    # -- reconcileMasterRoutes (Master-local relays) ------------------------

    def set_master_relay_state(self, room, device, on):
        if room == "teras" and device in ("lampu", "sanyo"):
            self.master_relay_state[(room, device)] = on
            return True
        return False

    def get_master_relay_state(self, room, device):
        return self.master_relay_state.get((room, device), False)

    def reconcile_local(self):
        for route in self.routes:
            if route.owner != "Master":
                continue
            if not self.ensure_desired_fresh(route) or not route.dirty:
                continue
            if not self.set_master_relay_state(route.room, route.device,
                                               route.desired_state):
                continue
            route.actual_known = True
            route.actual_state = self.get_master_relay_state(route.room,
                                                             route.device)
            route.actual_brightness = 0
            route.publish_pending = True
            self.master_local_execution_count += 1
            self.refresh_dirty(route)

    # -- startPendingCycle / sendCommandToSlave -----------------------------

    def build_espnow_command(self, route):
        state = 1 if route.desired_state else 0
        brightness = (self.desired_brightness_for_route(route)
                      if route.dimmable
                      else (100 if route.desired_state else 0))
        return {"type": 1, "roomKey": route.room, "deviceKey": route.device,
                "state": state, "brightness": brightness,
                "requestId": route.desired_request_id}

    def forward_slave(self):
        for route in self.routes:
            if route.owner != "Slave":
                continue
            if not self.ensure_desired_fresh(route) or not route.dirty:
                continue
            cmd = self.build_espnow_command(route)
            self.espnow_send_count += 1
            ack = self.link.send(cmd)
            self.handle_ack(route, ack)

    def handle_ack(self, route, ack):
        if ack["success"]:
            self.update_actual(route, ack["state"] != 0, ack["brightness"])
        else:
            # error: mark dirty so the cycle can retry later
            route.dirty = True

    # -- updateActual (including shared CH1 propagation) --------------------

    def update_actual(self, route, state, brightness):
        normalized = brightness if route.dimmable else 0
        changed = (not route.actual_known or route.actual_state != state
                   or route.actual_brightness != normalized)
        route.actual_known = True
        route.actual_state = state
        route.actual_brightness = normalized
        route.publish_pending = route.publish_pending or changed
        self.refresh_dirty(route)

        if not self.uses_shared(route):
            return
        for other in self.routes:
            if other is route or not self.uses_shared(other):
                continue
            brightness_changed = other.actual_brightness != normalized
            other.actual_brightness = normalized
            if other.actual_known:
                other.publish_pending = other.publish_pending \
                    or brightness_changed
            self.refresh_dirty(other)

    # -- publishActual ------------------------------------------------------

    def publish(self):
        for route in self.routes:
            if not route.publish_pending or not route.actual_known:
                continue
            if route.dimmable:
                payload = {"state": route.actual_state,
                           "brightness": route.actual_brightness}
            else:
                payload = {"state": route.actual_state}
            self.rtdb.publish_state(route.room, route.device, payload)
            route.publish_pending = False
            self.state_publish_count += 1


# ---------------------------------------------------------------------------
# Stage: ESP-NOW link (Master <-> Slave transport)
# ---------------------------------------------------------------------------

class EspNowLink:
    def __init__(self, slave):
        self.slave = slave
        self.send_count = 0
        self.sent_commands = []
        self.last_ack = None

    def send(self, command_payload):
        self.send_count += 1
        self.sent_commands.append(dict(command_payload))
        ack = self.slave.handle_command(command_payload)
        self.last_ack = ack
        return ack


# ---------------------------------------------------------------------------
# Stage: Slave
# (room_device_routing.cpp)
# ---------------------------------------------------------------------------

ESPNOW_STATE_OFF = 0
ESPNOW_STATE_ON = 1
ESPNOW_RESULT_OK = 1
ESPNOW_RESULT_ERROR = 0
ESPNOW_ERR_UNKNOWN_DEVICE = 1
ESPNOW_ERR_INVALID_STATE = 2
ESPNOW_ERR_INVALID_BRIGHTNESS = 3
DUPLICATE_CACHE_SIZE = 8


class SlaveRouter:
    def __init__(self):
        self.relay = {row[2]: False for row in SLAVE_ROUTES}
        self.dimmer = {}          # channel -> brightness
        self.dimmer_enabled = {}  # channel -> bool
        self.cache = [None] * DUPLICATE_CACHE_SIZE
        self.cache_index = 0
        self.drive_count = 0
        self.ack_count = 0
        self.millis_val = 0

    def find_entry(self, room, device):
        for row in SLAVE_ROUTES:
            if row[0] == room and row[1] == device:
                return row
        return None

    def get_dimmer_brightness(self, channel):
        return self.dimmer.get(channel, 0)

    def set_dimmer_brightness(self, channel, brightness):
        self.dimmer[channel] = brightness

    def set_dimmer_enabled(self, channel, enabled):
        self.dimmer_enabled[channel] = enabled

    def has_other_active_relay_on_dimmer(self, entry):
        for row in SLAVE_ROUTES:
            if row is not entry and row[3] == entry[3] and self.relay[row[2]]:
                return True
        return False

    def _dup_find(self, request_id, room, device, state, brightness):
        for e in self.cache:
            if (e is not None and e["requestId"] == request_id
                    and e["roomKey"] == room and e["deviceKey"] == device
                    and e["commandState"] == state
                    and e["commandBrightness"] == brightness):
                return e
        return None

    def _dup_store(self, request_id, room, device, cstate, cbright,
                   rstate, rbright, success, error_code):
        self.cache[self.cache_index] = {
            "requestId": request_id, "roomKey": room, "deviceKey": device,
            "commandState": cstate, "commandBrightness": cbright,
            "resultState": rstate, "resultBrightness": rbright,
            "resultSuccess": success, "resultErrorCode": error_code,
        }
        self.cache_index = (self.cache_index + 1) % DUPLICATE_CACHE_SIZE

    def handle_command(self, cmd):
        room = cmd["roomKey"]
        device = cmd["deviceKey"]
        state = cmd["state"]
        brightness = cmd["brightness"]
        rid = cmd["requestId"]

        out = {"type": 2, "roomKey": room, "deviceKey": device,
               "requestId": rid, "state": 0, "brightness": 0,
               "success": 0, "errorCode": 0, "timestamp": self.millis_val}

        dup = self._dup_find(rid, room, device, state, brightness)
        if dup is not None:
            out["state"] = dup["resultState"]
            out["brightness"] = dup["resultBrightness"]
            out["success"] = dup["resultSuccess"]
            out["errorCode"] = dup["resultErrorCode"]
            self.ack_count += 1
            return out

        entry = self.find_entry(room, device)
        if entry is None:
            out["success"] = ESPNOW_RESULT_ERROR
            out["errorCode"] = ESPNOW_ERR_UNKNOWN_DEVICE
            self._dup_store(rid, room, device, state, brightness,
                            0, 0, ESPNOW_RESULT_ERROR,
                            ESPNOW_ERR_UNKNOWN_DEVICE)
            self.ack_count += 1
            return out

        relay_id = entry[2]
        channel = entry[3]
        dimmable = entry[4]

        if brightness > 100:
            out["success"] = ESPNOW_RESULT_ERROR
            out["errorCode"] = ESPNOW_ERR_INVALID_BRIGHTNESS
            self._dup_store(rid, room, device, state, brightness,
                            0, 0, ESPNOW_RESULT_ERROR,
                            ESPNOW_ERR_INVALID_BRIGHTNESS)
            self.ack_count += 1
            return out

        if state == ESPNOW_STATE_OFF:
            final_state = ESPNOW_STATE_OFF
            if dimmable:
                final_brightness = self.get_dimmer_brightness(channel) \
                    if self.has_other_active_relay_on_dimmer(entry) \
                    else brightness
            else:
                final_brightness = 0
        elif state == ESPNOW_STATE_ON:
            final_state = ESPNOW_STATE_ON
            final_brightness = brightness
            if dimmable:
                if final_brightness == 0:
                    final_brightness = 1
            else:
                final_brightness = 100
        else:
            out["success"] = ESPNOW_RESULT_ERROR
            out["errorCode"] = ESPNOW_ERR_INVALID_STATE
            self._dup_store(rid, room, device, state, brightness,
                            0, 0, ESPNOW_RESULT_ERROR,
                            ESPNOW_ERR_INVALID_STATE)
            self.ack_count += 1
            return out

        # apply hardware
        self.relay[relay_id] = (final_state == ESPNOW_STATE_ON)
        self.drive_count += 1

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

        out["state"] = final_state
        out["brightness"] = final_brightness
        out["success"] = ESPNOW_RESULT_OK
        out["errorCode"] = 0
        self._dup_store(rid, room, device, state, brightness,
                        final_state, final_brightness, ESPNOW_RESULT_OK, 0)
        self.ack_count += 1
        return out


# ---------------------------------------------------------------------------
# Stage: Flutter state consumer
# (room_device_mapper.dart)
# ---------------------------------------------------------------------------

def _parse_brightness(raw):
    if isinstance(raw, bool):
        return None
    if isinstance(raw, int):
        numeric = raw
    elif isinstance(raw, float):
        numeric = raw
    elif isinstance(raw, str):
        try:
            numeric = float(raw)
        except ValueError:
            return None
    else:
        return None
    return max(0, min(100, int(numeric)))


def _map_device_value(raw):
    if not isinstance(raw, dict):
        return None
    state = raw.get("state")
    if not isinstance(state, bool):
        return None
    if "brightness" not in raw:
        return (state, None)
    b = _parse_brightness(raw.get("brightness"))
    if b is None:
        return None
    return (state, b)


def flutter_consume_state(rooms_tree):
    """Returns {(room, device): (is_on, brightness_or_None)}."""
    values = {}
    if not isinstance(rooms_tree, dict):
        return values
    for room_key, room_value in rooms_tree.items():
        if not isinstance(room_value, dict):
            continue
        tools = room_value.get("tools")
        if not isinstance(tools, dict):
            continue
        for dev_key, raw in tools.items():
            mapped = _map_device_value(raw)
            if mapped is not None:
                values[(room_key, dev_key)] = mapped
    return values


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

class Harness:
    def __init__(self):
        self.firebase_clock = SimClock()
        self.master_clock = SimClock()
        self.rtdb = InMemoryRTDB()
        self.slave = SlaveRouter()
        self.link = EspNowLink(self.slave)
        self.master = MasterRouter(self.master_clock, self.rtdb, self.link)
        self.flutter = FlutterProducer(self.firebase_clock)
        self.flutter_states = {}  # (room, device) -> (is_on, brightness|None)

    def tick(self):
        self.master.reconcile_local()
        self.master.forward_slave()
        self.master.publish()

    def emit_explicit(self, room, device, is_on, brightness,
                      supports_brightness, request_id, issued_at):
        """Emit a single command (no pairing) through RTDB + Master + tick."""
        payload = self.flutter.make_payload(is_on, brightness,
                                            supports_brightness, request_id,
                                            issued_at)
        ok, reason = self.rtdb.accept_command(room, device, payload,
                                              self.firebase_clock.now())
        if not ok:
            return {"stage": "rtdb", "accepted": False, "reason": reason}
        res = self.master.accept_command(room, device, payload)
        self.tick()
        return {"stage": "master", "accepted": res["outcome"] == "accepted",
                "outcome": res["outcome"]}

    def control_and_run(self, room, device, is_on, brightness,
                        supports_brightness, issued_at=None, request_ids=None):
        """Flutter-level control (with pairing) through RTDB + Master + tick."""
        if issued_at is None:
            issued_at = self.flutter.issued_at_now()
        commands = self.flutter.control(room, device, is_on, brightness,
                                        supports_brightness,
                                        self.flutter_states, issued_at,
                                        request_ids=request_ids)
        results = []
        for (r, d, payload) in commands:
            ok, reason = self.rtdb.accept_command(r, d, payload,
                                                  self.firebase_clock.now())
            if not ok:
                results.append((r, d, False, reason))
                continue
            res = self.master.accept_command(r, d, payload)
            results.append((r, d, res["outcome"] == "accepted",
                            res["outcome"]))
        self.tick()
        return commands, results

    def sync_flutter(self):
        return flutter_consume_state(self.rtdb.state_snapshot())


# ---------------------------------------------------------------------------
# Test scaffolding
# ---------------------------------------------------------------------------

PASS = 0
FAIL = 0


def check(name, condition, detail=""):
    global PASS, FAIL
    if condition:
        PASS += 1
        print("PASS  %s" % name)
    else:
        FAIL += 1
        print("FAIL  %s  %s" % (name, detail))


def eq(name, got, want):
    check("%s ==> %r" % (name, got), got == want,
          "want %r" % (want,))


# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------

def scenario_a_master_local_relay():
    print("\n== Scenario A - Master-owned relay full lifecycle (teras/lampu) ==")
    h = Harness()
    t = h.master_clock.now()

    r_on = h.emit_explicit("teras", "lampu", True, 0, False,
                           "req-TERAS-ON", t)
    check("A: RTDB accepts fresh relay command", r_on["accepted"],
          r_on.get("reason", r_on.get("outcome")))
    check("A: no ESP-NOW for Master-owned route",
          h.master.espnow_send_count == 0)
    eq("A: local relay executed exactly once",
       h.master.master_local_execution_count, 1)
    eq("A: local relay hardware ON",
       h.master.get_master_relay_state("teras", "lampu"), True)

    states = h.sync_flutter()
    eq("A: Flutter sees teras/lampu ON",
       states.get(("teras", "lampu")), (True, None))

    # request_id + issued_at preserved into command tree
    cmd = h.rtdb.commands["teras"]["lampu"]
    eq("A: request_id preserved", cmd["request_id"], "req-TERAS-ON")
    eq("A: issued_at preserved", cmd["issued_at"], t)

    # OFF
    r_off = h.emit_explicit("teras", "lampu", False, 0, False,
                            "req-TERAS-OFF", t + 1)
    check("A: OFF accepted", r_off["accepted"],
          r_off.get("reason", r_off.get("outcome")))
    eq("A: local relay executed again (2 total)",
       h.master.master_local_execution_count, 2)
    eq("A: local relay hardware OFF",
       h.master.get_master_relay_state("teras", "lampu"), False)
    states = h.sync_flutter()
    eq("A: Flutter sees teras/lampu OFF",
       states.get(("teras", "lampu")), (False, None))
    eq("A: no ESP-NOW traffic at all", h.master.espnow_send_count, 0)


def scenario_b_slave_relay():
    print("\n== Scenario B - Slave-owned relay (lorong/blower) ==")
    h = Harness()
    t = h.master_clock.now()

    r = h.emit_explicit("lorong", "blower", True, 0, False,
                        "req-LORONG-ON", t)
    check("B: command accepted", r["accepted"],
          r.get("reason", r.get("outcome")))
    eq("B: exactly one ESP-NOW command", h.master.espnow_send_count, 1)
    cmd = h.link.sent_commands[-1]
    eq("B: roomKey preserved", cmd["roomKey"], "lorong")
    eq("B: deviceKey preserved", cmd["deviceKey"], "blower")
    eq("B: requestId preserved", cmd["requestId"], "req-LORONG-ON")
    eq("B: relay ON normalized brightness 100", cmd["brightness"], 100)
    eq("B: relay state 1", cmd["state"], 1)

    eq("B: Slave relay hardware ON", h.slave.relay["RELAY_LORONG_BLOWER"],
       True)
    eq("B: Slave hardware driven exactly once", h.slave.drive_count, 1)

    # ACK assertions: success=1, errorCode=0, requestId echoed.
    ack = h.link.last_ack
    eq("B: ACK requestId echoes command", ack["requestId"], "req-LORONG-ON")
    eq("B: ACK success == 1", ack["success"], 1)
    eq("B: ACK errorCode == 0", ack["errorCode"], 0)
    eq("B: ACK state reflects executed ON", ack["state"], 1)
    eq("B: Slave ack_count == 1", h.slave.ack_count, 1)

    states = h.sync_flutter()
    eq("B: Flutter sees blower ON",
       states.get(("lorong", "blower")), (True, None))


def scenario_c_ch2_on():
    print("\n== Scenario C - Dedicated dimmer CH2 ON (dapur/lampu) ==")
    h = Harness()
    t = h.master_clock.now()

    r = h.emit_explicit("dapur", "lampu", True, 60, True,
                        "req-DAPUR-ON", t)
    check("C: dimmer command accepted", r["accepted"],
          r.get("reason", r.get("outcome")))
    cmd = h.link.sent_commands[-1]
    eq("C: ESP-NOW brightness 60", cmd["brightness"], 60)
    eq("C: ESP-NOW state ON", cmd["state"], 1)
    eq("C: physical CH2 == 60", h.slave.get_dimmer_brightness(2), 60)
    eq("C: dapur relay ON", h.slave.relay["RELAY_DAPUR_LAMPU"], True)
    states = h.sync_flutter()
    eq("C: Flutter sees dapur/lampu (ON, 60)",
       states.get(("dapur", "lampu")), (True, 60))


def scenario_d_ch2_off():
    print("\n== Scenario D - Dedicated dimmer CH2 OFF (from ON) ==")
    h = Harness()
    t = h.master_clock.now()

    h.emit_explicit("dapur", "lampu", True, 60, True, "req-DAPUR-ON", t)
    h.emit_explicit("dapur", "lampu", False, 0, True, "req-DAPUR-OFF", t + 1)

    eq("D: physical CH2 == 0 after OFF",
       h.slave.get_dimmer_brightness(2), 0)
    eq("D: dapur relay OFF", h.slave.relay["RELAY_DAPUR_LAMPU"], False)
    states = h.sync_flutter()
    eq("D: Flutter sees dapur/lampu (OFF, 0)",
       states.get(("dapur", "lampu")), (False, 0))


def scenario_e_shared_ch1():
    print("\n== Scenario E - Shared bedroom CH1 arbitration ==")
    h = Harness()
    t = h.master_clock.now()

    # 1. kamar_1 ON 30
    h.emit_explicit("kamar_1", "lampu", True, 30, True, "req-K1-ON30", t)
    eq("E1: CH1 == 30", h.slave.get_dimmer_brightness(1), 30)
    eq("E1: kamar_1 relay ON", h.slave.relay["RELAY_KAMAR1_LAMPU"], True)

    # 2. kamar_2 ON 70 (newest owns CH1)
    h.emit_explicit("kamar_2", "lampu", True, 70, True, "req-K2-ON70", t + 1)
    eq("E2: CH1 == 70 (newest wins)",
       h.slave.get_dimmer_brightness(1), 70)
    eq("E2: kamar_2 relay ON", h.slave.relay["RELAY_KAMAR2_LAMPU"], True)

    # 3. kamar_1 OFF while kamar_2 still ON -> CH1 retained at 70
    h.emit_explicit("kamar_1", "lampu", False, 0, True, "req-K1-OFF", t + 2)
    eq("E3: kamar_1 relay OFF", h.slave.relay["RELAY_KAMAR1_LAMPU"], False)
    eq("E3: kamar_2 relay still ON", h.slave.relay["RELAY_KAMAR2_LAMPU"], True)
    eq("E3: shared CH1 retained at 70 (NOT zeroed)",
       h.slave.get_dimmer_brightness(1), 70)

    states = h.sync_flutter()
    eq("E3: kamar_1 logical state OFF", states.get(("kamar_1", "lampu"))[0],
       False)
    eq("E3: kamar_1 reported brightness is retained shared value 70",
       states.get(("kamar_1", "lampu"))[1], 70)

    # 4. kamar_2 OFF (last CH1 user) -> CH1 -> 0
    h.emit_explicit("kamar_2", "lampu", False, 0, True, "req-K2-OFF", t + 3)
    eq("E4: kamar_2 relay OFF", h.slave.relay["RELAY_KAMAR2_LAMPU"], False)
    eq("E4: shared CH1 == 0", h.slave.get_dimmer_brightness(1), 0)

    states = h.sync_flutter()
    eq("E4: kamar_1 final (OFF, 0)",
       states.get(("kamar_1", "lampu")), (False, 0))
    eq("E4: kamar_2 final (OFF, 0)",
       states.get(("kamar_2", "lampu")), (False, 0))


def scenario_f_paired_bedroom():
    print("\n== Scenario F - Flutter paired bedroom companion command ==")
    h = Harness()
    t = h.firebase_clock.now()
    # latest known: kamar_2/lampu is ON at brightness 40
    h.flutter_states[("kamar_2", "lampu")] = (True, 40)

    commands, results = h.control_and_run(
        "kamar_1", "lampu", True, 60, True, issued_at=t,
        request_ids=["req-PAIR-1", "req-PAIR-2"])

    check("F: producer emitted two commands", len(commands) == 2,
          "got %d" % len(commands))
    rids = [c[2]["request_id"] for c in commands]
    eq("F: paired commands use distinct request ids", len(set(rids)), 2)
    eq("F: paired commands share the same issued_at",
       len({c[2]["issued_at"] for c in commands}), 1)

    by_device = {(c[0], c[1]): c[2] for c in commands}
    eq("F: kamar_1 command ON 60",
       by_device[("kamar_1", "lampu")]["state"], True)
    eq("F: kamar_1 command brightness 60",
       by_device[("kamar_1", "lampu")]["brightness"], 60)
    # companion copies kamar_2 relay state (ON) with shared brightness 60
    companion = by_device[("kamar_2", "lampu")]
    eq("F: companion keeps kamar_2 relay ON", companion["state"], True)
    eq("F: companion brightness matches primary 60", companion["brightness"], 60)

    states = h.sync_flutter()
    eq("F: kamar_1 final (ON, 60)", states.get(("kamar_1", "lampu")),
       (True, 60))
    eq("F: kamar_2 final (ON, 60)", states.get(("kamar_2", "lampu")),
       (True, 60))
    eq("F: shared CH1 == 60", h.slave.get_dimmer_brightness(1), 60)


def scenario_g_master_duplicate_and_order():
    print("\n== Scenario G - Master duplicate / ordering rejection ==")
    h = Harness()
    t = h.master_clock.now()

    # B delivered first (newer), then A (older) - A must not roll state back.
    r_b = h.emit_explicit("lorong", "blower", True, 0, False,
                          "req-B", t + 1000)
    r_a = h.emit_explicit("lorong", "blower", False, 0, False,
                          "req-A", t)
    check("G: newer B accepted", r_b["accepted"], r_b.get("outcome"))
    check("G: older A rejected (older_duplicate)", not r_a["accepted"]
          and r_a.get("outcome") == "older_duplicate",
          r_a.get("outcome"))

    sends_after_ab = h.master.espnow_send_count
    eq("G: only one ESP-NOW command for A+B", sends_after_ab, 1)
    eq("G: final relay stays ON (B wins)", h.slave.relay["RELAY_LORONG_BLOWER"],
       True)

    # Duplicate: re-deliver exact B -> ignored, no new execution.
    r_dup = h.emit_explicit("lorong", "blower", True, 0, False,
                            "req-B", t + 1000)
    check("G: duplicate B ignored", not r_dup["accepted"]
          and r_dup.get("outcome") == "older_duplicate", r_dup.get("outcome"))
    eq("G: no extra ESP-NOW on duplicate", h.master.espnow_send_count,
       sends_after_ab)
    eq("G: Slave still driven once", h.slave.drive_count, 1)

    # Tie-break: same issued_at, lexicographically larger request_id wins.
    r_c = h.emit_explicit("lorong", "blower", False, 0, False,
                          "req-C", t + 1000)
    check("G: same-ts larger request_id accepted (tie-break)", r_c["accepted"],
          r_c.get("outcome"))
    eq("G: relay flips OFF via lexicographic winner",
       h.slave.relay["RELAY_LORONG_BLOWER"], False)
    # req-B again at same ts must NOT displace req-C.
    r_b2 = h.emit_explicit("lorong", "blower", True, 0, False,
                           "req-B", t + 1000)
    check("G: req-B cannot displace req-C at equal ts", not r_b2["accepted"]
          and r_b2.get("outcome") == "older_duplicate", r_b2.get("outcome"))
    eq("G: relay stays OFF", h.slave.relay["RELAY_LORONG_BLOWER"], False)


def scenario_h_slave_retry_replay():
    print("\n== Scenario H - Slave ESP-NOW retry replay (transport dedup) ==")
    h = Harness()
    t = h.master_clock.now()

    h.emit_explicit("dapur", "lampu", True, 60, True, "req-RETRY", t)
    eq("H: first drive count 1", h.slave.drive_count, 1)
    eq("H: first ack count 1", h.slave.ack_count, 1)
    eq("H: CH2 == 60", h.slave.get_dimmer_brightness(2), 60)

    # Transport retry: Master resends the identical frame (same requestId,
    # state, brightness) because an ACK was lost.
    frame = h.link.sent_commands[-1]
    ack = h.link.send(frame)
    eq("H: retry ack echoes requestId", ack["requestId"], "req-RETRY")
    eq("H: retry ack success", ack["success"], 1)
    eq("H: retry ack brightness 60", ack["brightness"], 60)
    eq("H: hardware NOT re-driven (drive count stays 1)",
       h.slave.drive_count, 1)
    eq("H: cached ACK replayed (ack count 2)", h.slave.ack_count, 2)
    eq("H: resulting CH2 unchanged 60", h.slave.get_dimmer_brightness(2), 60)


def scenario_i_stale_at_rtdb():
    print("\n== Scenario I - stale rejected at RTDB representation ==")
    h = Harness()
    now = h.firebase_clock.now()
    payload = FlutterProducer.make_payload(True, 0, False, "req-STALE-RTDB",
                                           now - 16000)
    ok, reason = h.rtdb.accept_command("teras", "lampu", payload, now)
    check("I: RTDB rejects stale command", not ok, reason)
    check("I: no command stored", "teras" not in h.rtdb.commands
          or "lampu" not in h.rtdb.commands.get("teras", {}))
    # no Master consumption, no hardware
    eq("I: no local execution", h.master.master_local_execution_count, 0)


def scenario_j_stale_at_master_after_delay():
    print("\n== Scenario J - stale at Master after transport delay ==")
    h = Harness()
    t0 = h.firebase_clock.now()
    issued_at = t0 - 10000  # RTDB accepts (>= now-15000)

    payload = FlutterProducer.make_payload(True, 60, True,
                                           "req-STALE-MASTER", issued_at)
    ok, reason = h.rtdb.accept_command("dapur", "lampu", payload, t0)
    check("J: RTDB accepts (age 10000 <= 15000)", ok, reason)

    # Master clock advances 6000ms before consumption -> effective age 16000.
    h.master_clock.advance_ms(6000)
    res = h.master.accept_command("dapur", "lampu", payload)
    check("J: Master rejects as stale", res["outcome"] == "stale_or_future",
          res["outcome"])
    h.tick()
    eq("J: no ESP-NOW command", h.master.espnow_send_count, 0)
    eq("J: no dimmer mutation", h.slave.get_dimmer_brightness(2), 0)
    eq("J: no state published for dapur",
       ("dapur" in h.rtdb.rooms
        and "lampu" in h.rtdb.rooms["dapur"].get("tools", {})), False)


def scenario_k_future_timestamp():
    print("\n== Scenario K - future timestamp rejected ==")
    h = Harness()
    now = h.firebase_clock.now()
    payload = FlutterProducer.make_payload(True, 0, False, "req-FUTURE",
                                           now + 6000)
    ok, reason = h.rtdb.accept_command("teras", "lampu", payload, now)
    check("K: RTDB rejects future command", not ok, reason)

    # Master also rejects a within-RTDB-window future command at +6000.
    payload2 = FlutterProducer.make_payload(True, 0, False, "req-FUTURE-M",
                                            now + 6000)
    res = h.master.accept_command("teras", "lampu", payload2)
    check("K: Master rejects future command", res["outcome"] == "stale_or_future",
          res["outcome"])


def scenario_l_ordering_tie_break():
    print("\n== Scenario L - request ordering / tie-break (state cannot rollback) ==")
    h = Harness()
    t = h.master_clock.now()

    # Deliver newer first, then older; final state must remain from newer.
    h.emit_explicit("teras", "sanyo", True, 0, False, "req-S-NEW", t + 5)
    h.emit_explicit("teras", "sanyo", False, 0, False, "req-S-OLD", t)
    eq("L: newer ON wins over delayed older OFF",
       h.master.get_master_relay_state("teras", "sanyo"), True)
    states = h.sync_flutter()
    eq("L: Flutter sees sanyo ON", states.get(("teras", "sanyo")), (True, None))

    # Tie-break at equal issued_at: larger request_id wins.
    h.emit_explicit("teras", "sanyo", True, 0, False, "req-S-B", t + 100)
    h.emit_explicit("teras", "sanyo", False, 0, False, "req-S-A", t + 100)
    eq("L: lexicographically larger request_id (B) wins at equal ts",
       h.master.get_master_relay_state("teras", "sanyo"), True)


def main():
    global PASS, FAIL
    print("Issue #23 command-lifecycle E2E simulation")
    print("future tolerance=%dms  max age=%dms"
          % (COMMAND_FUTURE_TOLERANCE_MS, COMMAND_MAX_AGE_MS))
    print("Master routes=%d  Slave routes=%d"
          % (len(MASTER_ROUTES), len(SLAVE_ROUTES)))

    scenario_a_master_local_relay()
    scenario_b_slave_relay()
    scenario_c_ch2_on()
    scenario_d_ch2_off()
    scenario_e_shared_ch1()
    scenario_f_paired_bedroom()
    scenario_g_master_duplicate_and_order()
    scenario_h_slave_retry_replay()
    scenario_i_stale_at_rtdb()
    scenario_j_stale_at_master_after_delay()
    scenario_k_future_timestamp()
    scenario_l_ordering_tie_break()

    print("\n==== SUMMARY: %d passed, %d failed ====" % (PASS, FAIL))
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
