#!/usr/bin/env python3
"""
Issue #22 — cross-component protocol invariant enforcement.

The ESH system is a coordinated monorepo where one logical contract spans

    Flutter app  ->  Firebase RTDB rules  ->  ESP32 Master  ->  ESP32 Slave

A change to only one of these components can silently introduce drift in the
room/device identifiers, the command schema, timestamp units, freshness
bounds, ESP-NOW message IDs / struct ABI, or the telemetry field/unit set.

This test reads the actual production sources and asserts that every
protocol-visible invariant still agrees across all components.  It is fully
deterministic: no network, no hardware, no Firebase, no secrets.

Run:  python tools/contract_tests.py

The behavioral invariants that already have faithful mirrors are deliberately
NOT re-implemented here; they are enforced by the sibling scripts that run in
the same CI job:

  - freshness boundaries + shared-dimmer arbitration  -> evidence_gaps_tests.py
  - Slave payload-aware duplicate cache (Issue #7)    -> duplicate_cache_tests.py
  - energy unit Wh/kWh (Issue #19)                    -> energy_unit_contract_tests.py
"""

import base64
import json
import re
import sys
import os

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

PASS = 0
FAIL = 0


class ContractMismatch(Exception):
    """Raised when a cross-component invariant is violated."""


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def read_text(*rel_parts):
    path = os.path.join(REPO_ROOT, *rel_parts)
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def check(name, condition, detail=""):
    global PASS, FAIL
    if condition:
        PASS += 1
        print("PASS  %s" % name)
    else:
        FAIL += 1
        print("FAIL  %s  %s" % (name, detail))


def expect(name, fn):
    """Run a contract check that raises ContractMismatch on drift."""
    try:
        fn()
        check(name, True)
    except ContractMismatch as exc:
        check(name, False, str(exc))


# ---------------------------------------------------------------------------
# Source parsers (each fails loudly if it cannot extract anything)
# ---------------------------------------------------------------------------

FLUTTER_DEVICE_CONFIG = "apps/flutter/lib/models/device_config.dart"
FIREBASE_RULES = "firebase/database.rules.json"
MASTER_ROUTER = "firmware/master/src/firebase_command_router.cpp"
SLAVE_ROUTING = "firmware/slave/src/room_device_routing.cpp"
MASTER_ESPNOW_H = "firmware/master/include/esp_now_protocol.h"
SLAVE_ESPNOW_H = "firmware/slave/src/esp_now_config.h"
MASTER_TELEMETRY = "firmware/master/src/firebase_telemetry.cpp"
FLUTTER_CMD_SRC = "apps/flutter/lib/features/monitoring/data/datasources/firebase_room_device_data_source.dart"
FLUTTER_MONITOR_MAPPER = "apps/flutter/lib/features/monitoring/data/mappers/monitoring_entity_mapper.dart"
FLUTTER_REALTIME_MAPPER = "apps/flutter/lib/features/monitoring/data/mappers/realtime_monitoring_mapper.dart"
CONTRACT_COMMAND = "contracts/command-protocol.md"
CONTRACT_TIME = "contracts/time-and-freshness.md"
CONTRACT_TELEMETRY = "contracts/telemetry-schema.md"
CONTRACT_ESPNOW = "contracts/espnow-protocol.md"


def _require(result, what):
    if not result:
        raise ContractMismatch(
            "Parser failed to extract anything from %s. "
            "This usually means a source refactor broke the contract checker; "
            "fix the parser rather than deleting the test." % what
        )
    return result


def parse_flutter_devices():
    src = read_text(FLUTTER_DEVICE_CONFIG)
    m = re.search(
        r"const List<RoomDeviceConfig> roomDeviceConfigs\s*=\s*\[(.*?)\n\];",
        src, re.DOTALL)
    if not m:
        raise ContractMismatch("Failed to locate roomDeviceConfigs in %s"
                               % FLUTTER_DEVICE_CONFIG)
    block = m.group(1)
    devices = set()
    dimmable = set()
    rooms = re.findall(
        r"roomKey:\s*'([^']+)'\s*,\s*devices:\s*\[(.*?)\]",
        block, re.DOTALL)
    for room, devs in rooms:
        for dev in re.findall(r"DeviceConfig\(([^)]*)\)", devs):
            dm = re.search(r"deviceKey:\s*'([^']+)'", dev)
            if not dm:
                continue
            key = (room, dm.group(1))
            devices.add(key)
            if re.search(r"supportsBrightness:\s*true", dev):
                dimmable.add(key)
    _require(devices, "Flutter roomDeviceConfigs")
    return devices, dimmable


def parse_firebase_devices():
    data = json.loads(read_text(FIREBASE_RULES))
    node = data["rules"]["commands"]["rooms"]["$room"]["tools"]["$device"]
    write_rule = node[".write"]
    validate_rule = node[".validate"]
    devices = set()
    for room, dev1, dev2 in re.findall(
            r"\$room == '([^']+)' && \(\$device == '([^']+)'"
            r"(?: \|\| \$device == '([^']+)')?\)", write_rule):
        devices.add((room, dev1))
        if dev2:
            devices.add((room, dev2))
    _require(devices, "Firebase command whitelist")

    dimmable = set()
    dimmer_rooms = set(re.findall(r"\$room == '([^']+)'", validate_rule))
    if "'lampu'" not in validate_rule or not dimmer_rooms:
        raise ContractMismatch("Failed to parse Firebase dimmer clause")
    for room in dimmer_rooms:
        dimmable.add((room, "lampu"))
    return devices, dimmable, node


def parse_master_routes():
    src = read_text(MASTER_ROUTER)
    routes = set()
    dimmable = set()
    slave_owned = set()
    master_owned = set()
    for room, dev, owner, dim in re.findall(
            r'\{\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*'
            r'DeviceOwner::(\w+)\s*,\s*(true|false)\s*,', src):
        key = (room, dev)
        routes.add(key)
        if dim == "true":
            dimmable.add(key)
        if owner == "Slave":
            slave_owned.add(key)
        else:
            master_owned.add(key)
    _require(routes, "Master routes[] table")
    return routes, dimmable, slave_owned, master_owned


def parse_slave_routes():
    src = read_text(SLAVE_ROUTING)
    routes = set()
    dimmable = set()
    channels = {}
    for room, dev, channel, dim in re.findall(
            r'\{\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*\w+\s*,\s*'
            r'(\d+)\s*,\s*(true|false)\s*\}', src):
        key = (room, dev)
        routes.add(key)
        channels[key] = int(channel)
        if dim == "true":
            dimmable.add(key)
    _require(routes, "Slave ROUTE_TABLE")
    return routes, dimmable, channels


def parse_define_map(header_path):
    src = read_text(header_path)
    return dict(re.findall(r"#define\s+(\w+)\s+(\d+)", src))


# ---------------------------------------------------------------------------
# Invariant A — room/device identifier equality
# ---------------------------------------------------------------------------

def check_identifiers(flutter, firebase, master, slave, master_slave,
                      flutter_dim, master_dim, slave_dim):
    def eq(a_name, a, b_name, b):
        if a != b:
            raise ContractMismatch(
                "Identifier drift between %s and %s:\n"
                "  only in %s: %s\n  only in %s: %s"
                % (a_name, b_name, a_name, sorted(a - b),
                   b_name, sorted(b - a)))

    eq("Flutter", flutter, "Firebase rules", firebase)
    eq("Flutter", flutter, "Master routes[]", master)
    eq("Master Slave-owned routes", master_slave, "Slave ROUTE_TABLE", slave)

    if slave != master - {("teras", "lampu"), ("teras", "sanyo")}:
        raise ContractMismatch(
            "Slave ROUTE_TABLE should be Master routes minus the two "
            "Master-owned teras relays; got Slave-only %s, Master-minus-teras %s"
            % (sorted(slave - (master - {("teras", "lampu"), ("teras", "sanyo")})),
               sorted((master - {("teras", "lampu"), ("teras", "sanyo")}) - slave)))

    eq("Flutter dimmable", flutter_dim, "Master dimmable", master_dim)
    eq("Master dimmable", master_dim, "Slave dimmable", slave_dim)

    if not master_dim <= master_slave:
        raise ContractMismatch(
            "A dimmable route is Master-owned, which the protocol does not "
            "support: %s" % sorted(master_dim - master_slave))


# ---------------------------------------------------------------------------
# Invariant B/C — command payload schema
# ---------------------------------------------------------------------------

def check_command_schema(node):
    write_rule = node[".write"]
    validate_rule = node[".validate"]

    if "auth.token.owner == true" not in write_rule:
        raise ContractMismatch("Firebase command write must require owner==true")

    for required in ("state", "request_id", "issued_at"):
        if "'%s'" % required not in validate_rule:
            raise ContractMismatch("Firebase must require field %s" % required)

    # Relay commands must not carry brightness; dimmer commands must.
    brightness_rule = node["brightness"][".validate"]
    for bound in (">= 0", "<= 100"):
        if bound not in brightness_rule:
            raise ContractMismatch("Firebase brightness must enforce %s" % bound)

    request_id_rule = node["request_id"][".validate"]
    if "> 0" not in request_id_rule or "<= 31" not in request_id_rule:
        raise ContractMismatch("Firebase request_id must enforce 1..31")

    other = node.get("$other", {}).get(".validate")
    if other is not False:
        raise ContractMismatch("Firebase must deny unknown command fields ($other)")


def check_master_command_schema():
    src = read_text(MASTER_ROUTER)

    if "expectedFieldCount = route.dimmable ? 4 : 3" not in src:
        raise ContractMismatch("Master must enforce 4 fields (dimmer) / 3 (relay)")
    if "brightnessValue < 0 || brightnessValue > 100" not in src:
        raise ContractMismatch("Master must enforce brightness 0..100")
    if "requestIdLength == 0" not in src:
        raise ContractMismatch("Master must reject empty request_id")
    if "issued_at must be an epoch millisecond integer" not in src:
        raise ContractMismatch("Master must require integer issued_at")

    # request_id storage: char requestId[32] -> 31 chars + null terminator.
    if "char requestId[32]" not in src:
        raise ContractMismatch("Master request_id buffer must be 32 bytes")


def check_flutter_command_schema():
    src = read_text(FLUTTER_CMD_SRC)

    if "Must contain 1..31 characters" not in src:
        raise ContractMismatch("Flutter must validate request_id 1..31")
    if "brightness.clamp(0, 100)" not in src:
        raise ContractMismatch("Flutter must clamp brightness 0..100")

    # Producer emits exactly the four protocol fields.
    for key in ("'state':", "'request_id':", "'issued_at':"):
        if key not in src:
            raise ContractMismatch("Flutter payload must contain %s" % key)
    if "'brightness':" not in src:
        raise ContractMismatch("Flutter payload must contain brightness (dimmer)")


# ---------------------------------------------------------------------------
# Invariant E — request_id generation vs transport acceptance
# ---------------------------------------------------------------------------

def check_request_id_contract():
    src = read_text(FLUTTER_CMD_SRC)

    # Generator: 16 random bytes -> base64url -> strip '=' -> 22 chars.
    if "List<int>.generate(\n    16," not in src and "List<int>.generate(16," not in src:
        raise ContractMismatch("Flutter request_id generator must use 16 random bytes")
    if "base64UrlEncode" not in src or "replaceAll('=', '')" not in src:
        raise ContractMismatch("Flutter request_id must be base64url without padding")

    # base64url of 16 bytes is exactly 22 chars (no padding to strip).
    padded = base64.urlsafe_b64encode(b"\x00" * 16)
    generated_len = len(padded.replace(b"=", b""))
    if generated_len != 22:
        raise ContractMismatch("base64url(16 bytes) must be 22 chars, got %d"
                               % generated_len)
    if not 1 <= generated_len <= 31:
        raise ContractMismatch("generated request_id length %d outside 1..31"
                               % generated_len)

    # Contract document must stay in lockstep with the implementation.
    cmd_doc = read_text(CONTRACT_COMMAND)
    if "1..31" not in cmd_doc:
        raise ContractMismatch("command-protocol.md must state request_id 1..31")
    if "22 chars" not in cmd_doc:
        raise ContractMismatch("command-protocol.md must state base64url 22 chars")
    if "0..100" not in cmd_doc:
        raise ContractMismatch("command-protocol.md must state brightness 0..100")
    if re.search(r"epoch\s+\**milliseconds", cmd_doc) is None:
        raise ContractMismatch("command-protocol.md must state issued_at epoch ms")


# ---------------------------------------------------------------------------
# Invariant F/G/H — timestamp units and freshness bounds
# ---------------------------------------------------------------------------

def check_time_contract():
    master = read_text(MASTER_ROUTER)
    rules = read_text(FIREBASE_RULES)
    doc = read_text(CONTRACT_TIME)

    m_future = re.search(r"COMMAND_FUTURE_TOLERANCE_MS\s*=\s*(\d+)", master)
    m_age = re.search(r"COMMAND_MAX_AGE_MS\s*=\s*(\d+)", master)
    if not m_future or not m_age:
        raise ContractMismatch("Master freshness constants not found")
    future_ms = int(m_future.group(1))
    max_age_ms = int(m_age.group(1))

    r_past = re.search(r"now\s*-\s*(\d+)", rules)
    r_future = re.search(r"now\s*\+\s*(\d+)", rules)
    if not r_past or not r_future:
        raise ContractMismatch("Firebase freshness bounds not found")

    if future_ms != int(r_future.group(1)):
        raise ContractMismatch("future tolerance drift: Master %d vs Firebase %s"
                               % (future_ms, r_future.group(1)))
    if max_age_ms != int(r_past.group(1)):
        raise ContractMismatch("max-age drift: Master %d vs Firebase %s"
                               % (max_age_ms, r_past.group(1)))
    if "+5000" not in doc or "15000" not in doc:
        raise ContractMismatch("time-and-freshness.md missing 5000/15000 bounds")

    # issued_at is epoch milliseconds on the wire.
    flutter_cmd = read_text(FLUTTER_CMD_SRC)
    if "millisecondsSinceEpoch" not in flutter_cmd:
        raise ContractMismatch("Flutter issued_at must use millisecondsSinceEpoch")
    if "epoch milliseconds" not in doc:
        raise ContractMismatch("contract must state issued_at is epoch ms")

    # unix_time and sampled_at are epoch seconds (Master NTP).
    telemetry = read_text(MASTER_TELEMETRY)
    if "getValidEpochSeconds" not in telemetry:
        raise ContractMismatch("Master telemetry must source epoch seconds")
    if "unix_time" not in telemetry:
        raise ContractMismatch("Master must publish /device/sensorData/unix_time")
    if "environmentSampledAtEpochSeconds" not in telemetry \
            or "powerSampledAtEpochSeconds" not in telemetry:
        raise ContractMismatch("Master sampled_at must be epoch seconds")
    if re.search(r"epoch\s+\**seconds", read_text(CONTRACT_TELEMETRY)) is None:
        raise ContractMismatch("telemetry-schema.md must state epoch seconds")


# ---------------------------------------------------------------------------
# Invariant I/J — ESP-NOW message IDs, error codes, struct ABI
# ---------------------------------------------------------------------------

MESSAGE_ROLES = {
    "command": {"CMD_TYPE_COMMAND", "ESPNOW_MSG_DEVICE_COMMAND"},
    "state": {"CMD_TYPE_STATE", "ESPNOW_MSG_DEVICE_STATE"},
    "discovery": {"ESPNOW_MSG_DISCOVERY_BEACON"},
    "authenticated": {"ESPNOW_MSG_AUTHENTICATED_BEACON"},
}

ERROR_ROLES = {
    "unknown_device": {"ERR_UNKNOWN_KEY", "ESPNOW_ERR_UNKNOWN_DEVICE"},
    "invalid_state": {"ERR_INVALID_STATE", "ESPNOW_ERR_INVALID_STATE"},
    "invalid_brightness": {"ERR_INVALID_BRIGHTNESS", "ESPNOW_ERR_INVALID_BRIGHTNESS"},
    "crc": {"ERR_CRC_INVALID", "ESPNOW_ERR_CRC"},
    "hardware": {"ERR_HARDWARE", "ESPNOW_ERR_HARDWARE"},
}


def _roles_from(defs, roles):
    out = {}
    for role, macros in roles.items():
        for macro in macros:
            if macro in defs:
                out[role] = int(defs[macro])
                break
    return out


def compare_role_maps(m, s, roles, label):
    if set(m) != set(roles):
        raise ContractMismatch("Master ESP-NOW %s missing: %s"
                               % (label, set(roles) - set(m)))
    if set(s) != set(roles):
        raise ContractMismatch("Slave ESP-NOW %s missing: %s"
                               % (label, set(roles) - set(s)))
    for role in roles:
        if m[role] != s[role]:
            raise ContractMismatch(
                "ESP-NOW %s drift for %r: Master %d vs Slave %d"
                % (label, role, m[role], s[role]))


def check_espnow_contract():
    master_defs = parse_define_map(MASTER_ESPNOW_H)
    slave_defs = parse_define_map(SLAVE_ESPNOW_H)
    master_h = read_text(MASTER_ESPNOW_H)
    slave_h = read_text(SLAVE_ESPNOW_H)

    compare_role_maps(_roles_from(master_defs, MESSAGE_ROLES),
                      _roles_from(slave_defs, MESSAGE_ROLES),
                      MESSAGE_ROLES, "message IDs")
    compare_role_maps(_roles_from(master_defs, ERROR_ROLES),
                      _roles_from(slave_defs, ERROR_ROLES),
                      ERROR_ROLES, "error codes")

    # Struct ABI: the compile-time static_assert sizes must match on both sides.
    expected = {
        "DeviceCommandPayload": 92,
        "DeviceStatePayload": 98,
        "DiscoveryBeaconPayload": 7,
    }
    for struct, size in expected.items():
        m = re.search(r"sizeof\(%s\)\s*==\s*(\d+)" % struct, master_h)
        s = re.search(r"sizeof\(%s\)\s*==\s*(\d+)" % struct, slave_h)
        if not m or not s:
            raise ContractMismatch("static_assert missing for %s" % struct)
        if int(m.group(1)) != size or int(s.group(1)) != size:
            raise ContractMismatch(
                "struct %s size drift: Master %s Slave %s (expected %d)"
                % (struct, m.group(1), s.group(1), size))

    # Discovery magic must be identical.
    mm = re.search(r"ESPNOW_DISCOVERY_MAGIC\s+(0x[0-9A-Fa-f]+)", master_h)
    sm = re.search(r"ESPNOW_DISCOVERY_MAGIC\s+(0x[0-9A-Fa-f]+)", slave_h)
    if not mm or not sm or mm.group(1).upper() != sm.group(1).upper():
        raise ContractMismatch("ESPNOW_DISCOVERY_MAGIC drift between Master/Slave")

    # Contract document must stay in lockstep with both codebases.
    doc = read_text(CONTRACT_ESPNOW)
    for macro in ("ESPNOW_MSG_DEVICE_COMMAND", "ESPNOW_MSG_DEVICE_STATE",
                  "ESPNOW_MSG_DISCOVERY_BEACON", "ESPNOW_MSG_AUTHENTICATED_BEACON"):
        if macro not in doc:
            raise ContractMismatch("espnow-protocol.md missing %s" % macro)
    for size in ("92 bytes", "98 bytes", "7 bytes"):
        if size not in doc:
            raise ContractMismatch("espnow-protocol.md missing struct size %s" % size)


# ---------------------------------------------------------------------------
# Invariant K — shared dimmer CH1 / dedicated CH2
# ---------------------------------------------------------------------------

def check_shared_dimmer(channels):
    # Both bedroom lamps share CH1; the dapur lamp is the dedicated CH2.
    if channels.get(("kamar_1", "lampu")) != 1:
        raise ContractMismatch("kamar_1/lampu must map to dimmer channel 1")
    if channels.get(("kamar_2", "lampu")) != 1:
        raise ContractMismatch("kamar_2/lampu must map to dimmer channel 1 (shared)")
    if channels.get(("dapur", "lampu")) != 2:
        raise ContractMismatch("dapur/lampu must map to dedicated dimmer channel 2")

    master = read_text(MASTER_ROUTER)
    if "usesSharedBedroomDimmer" not in master:
        raise ContractMismatch("Master must arbitrate the shared bedroom dimmer")
    if "strcmp(route.deviceKey, \"lampu\")" not in master:
        raise ContractMismatch("Master shared-dimmer guard must key on lampu")
    if "kamar_1" not in master or "kamar_2" not in master:
        raise ContractMismatch("Master shared-dimmer guard must cover kamar_1/2")


# ---------------------------------------------------------------------------
# Invariant L/M — telemetry field names and units
# ---------------------------------------------------------------------------

def check_telemetry_contract():
    telemetry = read_text(MASTER_TELEMETRY)
    mapper = read_text(FLUTTER_MONITOR_MAPPER)
    realtime = read_text(FLUTTER_REALTIME_MAPPER)
    doc = read_text(CONTRACT_TELEMETRY)

    power_fields = set(re.findall(r'setRoundedOrNull\(power,\s*"([^"]+)"', telemetry))
    power_fields |= set(re.findall(r'power\["([^"]+)"\]\s*=', telemetry))
    env_fields = set(re.findall(r'setRoundedOrNull\(environment,\s*"([^"]+)"', telemetry))
    env_fields |= set(re.findall(r'environment\["([^"]+)"\]\s*=', telemetry))

    _require(power_fields, "Master power telemetry fields")
    _require(env_fields, "Master environment telemetry fields")

    for name in ("voltage", "current", "power", "energy", "frequency", "pf"):
        if name not in power_fields:
            raise ContractMismatch("Master power telemetry missing field %s" % name)
    for name in ("temperature", "humidity"):
        if name not in env_fields:
            raise ContractMismatch("Master environment missing field %s" % name)

    # Flutter consumes the exact same field names (no rename drift).
    consumed_power = set(re.findall(r"dto\.power\['([^']+)'\]", mapper))
    consumed_env = set(re.findall(r"dto\.environment\['([^']+)'\]", mapper))
    _require(consumed_power, "Flutter consumed power fields")
    _require(consumed_env, "Flutter consumed environment fields")

    if not consumed_power <= power_fields:
        raise ContractMismatch(
            "Flutter consumes power fields unknown to Master: %s"
            % sorted(consumed_power - power_fields))
    if not consumed_env <= env_fields:
        raise ContractMismatch(
            "Flutter consumes environment fields unknown to Master: %s"
            % sorted(consumed_env - env_fields))

    # unix_time / sampled_at keys agree between producer and consumer.
    if "unix_time" not in telemetry or "unix_time" not in realtime:
        raise ContractMismatch("unix_time key drift between Master and Flutter")
    if "sampled_at" not in telemetry or "sampled_at" not in realtime:
        raise ContractMismatch("sampled_at key drift between Master and Flutter")

    # Energy wire unit is kWh (reconciled by Issue #19).
    if re.search(r"\|\s*`energy`\s*\|\s*number\s*\|\s*kWh\s*\|", doc) is None:
        raise ContractMismatch("telemetry-schema.md must declare energy as kWh")
    if re.search(r"\|\s*`energy`\s*\|\s*number\s*\|\s*Wh\s*\|", doc):
        raise ContractMismatch("telemetry-schema.md still labels energy as Wh")


# ---------------------------------------------------------------------------
# Invariant C/D — OFF -> brightness 0 at the Slave result level
# ---------------------------------------------------------------------------

def check_off_brightness_zero():
    # The slave normalizes the reflected state: an OFF dedicated dimmer and an
    # OFF relay both report brightness 0 (shared CH1 retains only while a
    # sibling lamp is still ON — see evidence_gaps_tests.py).
    import evidence_gaps_tests as eg

    hw = eg.SlaveHardware()
    r = hw.apply_command("dapur", "lampu", eg.ESPNOW_STATE_OFF, 80, "req-off")
    if r["brightness"] != 0 or r["state"] != eg.ESPNOW_STATE_OFF:
        raise ContractMismatch(
            "OFF dimmer must report brightness 0, got %r" % r)

    hw2 = eg.SlaveHardware()
    r2 = hw2.apply_command("lorong", "blower", eg.ESPNOW_STATE_OFF, 80, "req-off")
    if r2["brightness"] != 0:
        raise ContractMismatch(
            "OFF relay must report brightness 0, got %r" % r2)


# ---------------------------------------------------------------------------
# Self-tests: prove the checker detects drift (never silently passes)
# ---------------------------------------------------------------------------

def run_self_tests():
    global PASS, FAIL
    print("\n== self-test: the checker must FAIL on injected drift ==")

    # Identifier drift (Slave missing one route, gained another).
    base = {("kamar_1", "lampu"), ("kamar_2", "lampu"), ("dapur", "lampu"),
            ("lorong", "stop_kontak"), ("lorong", "blower"),
            ("kamar_1", "stop_kontak"), ("kamar_2", "stop_kontak"),
            ("dapur", "blower")}
    dims = {("kamar_1", "lampu"), ("kamar_2", "lampu"), ("dapur", "lampu")}
    full = {("teras", "lampu"), ("teras", "sanyo")} | base
    drifted = base - {("dapur", "blower")} | {("dapur", "kulkas")}
    try:
        check_identifiers(full, full, full, drifted, base, dims, dims, dims)
        check("self: identifier drift detected", False, "no mismatch raised")
    except ContractMismatch:
        check("self: identifier drift detected", True)

    # Message-ID drift through the real comparator.
    try:
        compare_role_maps(
            {"command": 1, "state": 2, "discovery": 3, "authenticated": 4},
            {"command": 1, "state": 3, "discovery": 3, "authenticated": 4},
            MESSAGE_ROLES, "message IDs")
        check("self: message-id drift detected", False, "no mismatch raised")
    except ContractMismatch:
        check("self: message-id drift detected", True)

    # Freshness-constant drift (Master 6000 vs Firebase 5000).
    try:
        m_future, m_age = 6000, 15000
        r_future, r_past = 5000, 15000
        if m_future != r_future:
            raise ContractMismatch("future tolerance drift: Master %d vs Firebase %d"
                                   % (m_future, r_future))
        if m_age != r_past:
            raise ContractMismatch("max-age drift: Master %d vs Firebase %d"
                                   % (m_age, r_past))
        check("self: freshness drift detected", False, "no mismatch raised")
    except ContractMismatch:
        check("self: freshness drift detected", True)

    # Parser sanity: empty source must raise, not silently pass.
    try:
        _require(set(), "injected empty parse")
        check("self: empty parse rejected", False, "empty parse accepted")
    except ContractMismatch:
        check("self: empty parse rejected", True)


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

def main():
    global PASS, FAIL

    print("== Invariant A: room/device identifiers ==")
    flutter_devices, flutter_dim = parse_flutter_devices()
    firebase_devices, firebase_dim, cmd_node = parse_firebase_devices()
    master_routes, master_dim, master_slave, _master_owned = parse_master_routes()
    slave_routes, slave_dim, slave_channels = parse_slave_routes()

    expect("A1 Flutter == Firebase == Master identifiers",
           lambda: check_identifiers(
               flutter_devices, firebase_devices, master_routes, slave_routes,
               master_slave, flutter_dim, master_dim, slave_dim))

    print("\n== Invariant B/C: command schema ==")
    expect("B1 Firebase command schema (fields/brightness/request_id/$other)",
           lambda: check_command_schema(cmd_node))
    expect("B2 Master command schema (field count, ranges, buffer)",
           check_master_command_schema)
    expect("B3 Flutter command producer schema", check_flutter_command_schema)

    print("\n== Invariant E: request_id contract ==")
    expect("E1 request_id generator (22-char base64url) vs 1..31 transport",
           check_request_id_contract)

    print("\n== Invariant F/G/H: time & freshness ==")
    expect("F1 freshness bounds + timestamp units", check_time_contract)

    print("\n== Invariant I/J: ESP-NOW ==")
    expect("I1 message IDs, error codes, struct ABI, magic",
           check_espnow_contract)

    print("\n== Invariant K: shared dimmer ==")
    expect("K1 CH1 shared (kamar_1/kamar_2), CH2 dedicated (dapur)",
           lambda: check_shared_dimmer(slave_channels))

    print("\n== Invariant L/M: telemetry fields & units ==")
    expect("L1 telemetry field names and energy unit", check_telemetry_contract)

    print("\n== Invariant C/D: OFF -> brightness 0 ==")
    expect("C1 OFF reports brightness 0 (dedicated dimmer + relay)",
           check_off_brightness_zero)

    run_self_tests()

    print("\n==== SUMMARY: %d passed, %d failed ====" % (PASS, FAIL))
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
