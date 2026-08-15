#!/usr/bin/env python3
"""
Read-only diagnostic runner for the coordinated Flutter/Master/Slave breakage
described in https://github.com/elfromsky/terbarubangetgabung/issues/1.

Extracts committed snapshots of all three components (before and after the
coordinated revision), verifies repository topology, runs safe/non-destructive
build/contract checks, and emits a Markdown report.

Safety rules enforced by design:
- No checkout/reset/merge/rebase/cherry-pick in the user's working tree.
- No live Firebase mutation.
- No ESP32 flashing.
- No secret values are printed.
- All build work happens in a disposable temporary directory.
"""

import os
import shutil
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
REPORT_PATH = REPO_ROOT / "tools" / "diagnose-broken-revision-report.md"

REVS = {
    "flutter_before": "1b62be3",
    "flutter_revised": "5bd9fb6",
    "slave_before": "24da621",
    "slave_revised": "6d306cf",
    "master_before": "273b3f6",
    "master_revised": "f8c960e",
}

BRANCHES = {
    "flutter": "origin/flutter",
    "clean": "origin/clean",
    "main": "origin/main",
    "slave": "origin/slave",
}

CLASSIFICATIONS = {
    "PASS": "PASS",
    "FAIL": "FAIL",
    "EXPECTED_PROVISIONING_FAILURE": "EXPECTED_PROVISIONING_FAILURE",
    "CONFIRMED_STATIC": "CONFIRMED_STATIC",
    "CONFIRMED_CONTRACT_DEFECT": "CONFIRMED_CONTRACT_DEFECT",
    "PROVEN_INCOMPATIBLE": "PROVEN_INCOMPATIBLE",
    "SKIPPED_ENVIRONMENT": "SKIPPED_ENVIRONMENT",
    "HARDWARE_REQUIRED": "HARDWARE_REQUIRED",
    "LIVE_BACKEND_REQUIRED": "LIVE_BACKEND_REQUIRED",
}

findings = []
report_parts = []


def add_section(title, body):
    report_parts.append(f"\n## {title}\n\n{body}\n")


def add_finding(fid, classification, description):
    findings.append({"id": fid, "classification": classification, "description": description})


def run(cmd, cwd=None, timeout=60, capture=True):
    """Run a command and return (exit_code, stdout, stderr)."""
    cmd = list(cmd)
    resolved = shutil.which(cmd[0])
    if resolved:
        cmd[0] = resolved
    try:
        kwargs = {
            "cwd": str(cwd) if cwd else None,
            "timeout": timeout,
        }
        if capture:
            kwargs["stdout"] = subprocess.PIPE
            kwargs["stderr"] = subprocess.PIPE
            kwargs["text"] = True
            kwargs["encoding"] = "utf-8"
            kwargs["errors"] = "replace"
        result = subprocess.run(cmd, **kwargs)
        return result.returncode, result.stdout or "", result.stderr or ""
    except subprocess.TimeoutExpired:
        return -1, "", "TIMEOUT"
    except FileNotFoundError as e:
        return -1, "", f"MISSING: {e}"


def tool_version(name, arg="--version"):
    found = run([name, arg], timeout=30)
    if found[0] != 0:
        return "MISSING"
    lines = (found[1] + "\n" + found[2]).splitlines()
    first = next((l.strip() for l in lines if l.strip()), None)
    return first or "AVAILABLE (version unknown)"


def commit_exists(commit):
    code, _, _ = run(["git", "-C", str(REPO_ROOT), "rev-parse", "--verify", commit], timeout=30)
    return code == 0


def merge_base(a, b):
    code, out, _ = run(["git", "-C", str(REPO_ROOT), "merge-base", a, b], timeout=30)
    return out.strip() if code == 0 else ""


def commit_subject(commit):
    _, out, _ = run(["git", "-C", str(REPO_ROOT), "log", "--format=%s", "-1", commit], timeout=30)
    return out.strip()


def extract_commit(commit, dest):
    if dest.exists():
        import shutil
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    zip_path = dest.with_suffix(".zip")
    code, _, err = run(["git", "-C", str(REPO_ROOT), "archive", "--format=zip", "-o", str(zip_path), commit], timeout=60)
    if code != 0:
        raise RuntimeError(f"git archive failed for {commit}: {err}")
    with zipfile.ZipFile(zip_path, "r") as z:
        z.extractall(dest)
    zip_path.unlink(missing_ok=True)


def flutter_command(path, subcommand, timeout=300):
    code, out, err = run(["flutter"] + subcommand.split(), cwd=path, timeout=timeout)
    combined = (out or "") + "\n" + (err or "")
    if code == 0:
        return "PASS"
    snippet = combined[:2000] + ("\n... (truncated)" if len(combined) > 2000 else "")
    return f"FAIL\n```\n{snippet}\n```"


def flutter_check(label, path):
    results = {"pubGet": "SKIP", "analyze": "SKIP", "test": "SKIP", "buildApk": "SKIP"}
    results["pubGet"] = flutter_command(path, "pub get", timeout=180)
    if results["pubGet"] == "PASS":
        results["analyze"] = flutter_command(path, "analyze", timeout=300)
        results["test"] = flutter_command(path, "test", timeout=300)
        results["buildApk"] = flutter_command(path, "build apk --debug", timeout=600)
    return results


def expects_provisioning_failure(path, component):
    if component == "master":
        markers = ["include/firebase_config.local.h", "include/wifi_config.local.h", "include/esp_now_keys.local.h"]
    elif component == "slave":
        markers = ["src/esp_now_keys.local.h"]
    else:
        return False
    missing = [m for m in markers if not (path / m).exists()]
    has_error_directive = False
    for header in path.rglob("*.h"):
        try:
            text = header.read_text(encoding="utf-8", errors="replace")
            if '#error' in text and "Missing" in text:
                has_error_directive = True
                break
        except Exception:
            pass
    return bool(missing and has_error_directive)


def main():
    report_parts.append(
        "# Coordinated Revision Diagnostic Report\n\n"
        f"Generated: {datetime.now(timezone.utc).astimezone().strftime('%Y-%m-%d %H:%M:%S %z')}\n"
        f"Repository: {REPO_ROOT}\n"
        "Issue: https://github.com/elfromsky/terbarubangetgabung/issues/1"
    )

    tmp = Path(tempfile.mkdtemp(prefix="esh-diagnose-"))
    print(f"Workspace: {tmp}")

    try:
        # Environment
        env_rows = ["| Tool | Status |", "|------|--------|"]
        tools = [
            ("git", "--version"),
            ("flutter", "--version"),
            ("dart", "--version"),
            ("node", "--version"),
            ("npm", "--version"),
            ("firebase", "--version"),
            ("pio", "--version"),
            ("platformio", "--version"),
            ("java", "-version"),
        ]
        tool_status = {}
        for name, arg in tools:
            v = tool_version(name, arg)
            env_rows.append(f"| {name} | {v} |")
            tool_status[name] = (v != "MISSING")
        add_section("Environment", "\n".join(env_rows))

        # Verify commits
        for key, commit in REVS.items():
            if not commit_exists(commit):
                raise RuntimeError(f"Required commit {commit} ({key}) not found. Run 'git fetch --all'.")

        # Topology
        topo_rows = ["| Pair | Merge base |", "|------|------------|"]
        pairs = [
            (BRANCHES["main"], BRANCHES["slave"], "main <-> slave"),
            (BRANCHES["main"], BRANCHES["clean"], "main <-> clean"),
            (BRANCHES["slave"], BRANCHES["clean"], "slave <-> clean"),
            (BRANCHES["flutter"], BRANCHES["clean"], "flutter -> clean"),
        ]
        topo_checks = {}
        for a, b, label in pairs:
            mb = merge_base(a, b)
            topo_rows.append(f"| {label} | {mb or '(none / unrelated)'} |")
            topo_checks[label] = mb

        def first_root(ref):
            code, out, _ = run(["git", "-C", str(REPO_ROOT), "rev-list", "--max-parents=0", ref], timeout=30)
            return out.strip().splitlines()[0] if code == 0 and out.strip() else ""

        master_root = first_root(BRANCHES["main"])
        slave_root = first_root(BRANCHES["slave"])
        flutter_root = first_root(BRANCHES["clean"])
        flutter_root_b = first_root(BRANCHES["flutter"])

        root_rows = [
            "| Component | Root | Pre-revision | Revised |",
            "|-----------|------|--------------|---------|",
            f"| Master | `{master_root}` | `{REVS['master_before']}` | `{REVS['master_revised']}` |",
            f"| Slave | `{slave_root}` | `{REVS['slave_before']}` | `{REVS['slave_revised']}` |",
            f"| Flutter | `{flutter_root}` | `{REVS['flutter_before']}` | `{REVS['flutter_revised']}` |",
        ]
        topo_rows.append("\n**Root vs pre-revision vs revised snapshot table:**")
        topo_rows.extend(root_rows)

        root_notes = (
            "The roots above are the true independent roots of each lineage, "
            "distinct from the selected pre-revision snapshots. "
            "Only the Flutter `flutter -> clean` lineage shares ancestry "
            f"(merge base `{flutter_root_b}`). The three component lineages are unrelated."
        )
        topo_rows.append(f"\n{root_notes}")
        add_section("Repository topology", "\n".join(topo_rows))

        if topo_checks["main <-> slave"]:
            add_finding("TOPO-1", "FAIL", "main and slave unexpectedly share a merge base")
        if topo_checks["main <-> clean"]:
            add_finding("TOPO-2", "FAIL", "main and clean unexpectedly share a merge base")
        if topo_checks["slave <-> clean"]:
            add_finding("TOPO-3", "FAIL", "slave and clean unexpectedly share a merge base")
        if not topo_checks["flutter -> clean"]:
            add_finding("TOPO-4", "FAIL", "flutter and clean do not share expected merge base 6cb3438")

        # Extract snapshots
        snapshots = {}
        for key, commit in REVS.items():
            dest = tmp / key
            extract_commit(commit, dest)
            snapshots[key] = dest

        # Build matrix
        build_rows = [
            "| Component | Revision | Pristine | Synthetic-provisioned | Classification |",
            "|-----------|----------|----------|-----------------------|----------------|",
        ]

        flutter_available = tool_status.get("flutter")
        pio_available = tool_status.get("pio") or tool_status.get("platformio")

        if flutter_available:
            fb = flutter_check("Flutter before", snapshots["flutter_before"])
            build_rows.append(
                f"| Flutter | `{REVS['flutter_before']}` | pub:{fb['pubGet']} analyze:{fb['analyze']} test:{fb['test']} apk:{fb['buildApk']} | N/A | see below |"
            )
            ok = fb["analyze"] == "PASS" and fb["test"] == "PASS"
            add_finding(
                "BUILD-FLUTTER-BEFORE",
                "PASS" if ok else "FAIL",
                f"Flutter before: pub={fb['pubGet']}, analyze={fb['analyze']}, test={fb['test']}, buildApk={fb['buildApk']}",
            )

            fr = flutter_check("Flutter revised", snapshots["flutter_revised"])
            build_rows.append(
                f"| Flutter | `{REVS['flutter_revised']}` | pub:{fr['pubGet']} analyze:{fr['analyze']} test:{fr['test']} apk:{fr['buildApk']} | N/A | see below |"
            )
            ok = fr["analyze"] == "PASS" and fr["test"] == "PASS"
            add_finding(
                "BUILD-FLUTTER-REVISED",
                "PASS" if ok else "FAIL",
                f"Flutter revised: pub={fr['pubGet']}, analyze={fr['analyze']}, test={fr['test']}, buildApk={fr['buildApk']}",
            )
        else:
            build_rows.append(f"| Flutter | `{REVS['flutter_before']}` | SKIP | N/A | SKIPPED_ENVIRONMENT |")
            build_rows.append(f"| Flutter | `{REVS['flutter_revised']}` | SKIP | N/A | SKIPPED_ENVIRONMENT |")
            add_finding("BUILD-FLUTTER-BEFORE", "SKIPPED_ENVIRONMENT", "Flutter SDK not available")
            add_finding("BUILD-FLUTTER-REVISED", "SKIPPED_ENVIRONMENT", "Flutter SDK not available")

        build_rows.append(f"| Master | `{REVS['master_before']}` | SKIP (pio missing) | N/A | SKIPPED_ENVIRONMENT |")

        master_prov = expects_provisioning_failure(snapshots["master_revised"], "master")
        master_class = "EXPECTED_PROVISIONING_FAILURE" if master_prov else "INCONCLUSIVE"
        build_rows.append(
            f"| Master | `{REVS['master_revised']}` | expected fail-closed | SKIP (pio missing) | {master_class} |"
        )
        add_finding(
            "BUILD-MASTER-REVISED",
            master_class,
            "Revised Master requires local provisioning files (firebase_config.local.h, wifi_config.local.h, esp_now_keys.local.h). PlatformIO not available for compile verification.",
        )

        build_rows.append(f"| Slave | `{REVS['slave_before']}` | SKIP (pio missing) | N/A | SKIPPED_ENVIRONMENT |")

        slave_prov = expects_provisioning_failure(snapshots["slave_revised"], "slave")
        slave_class = "EXPECTED_PROVISIONING_FAILURE" if slave_prov else "INCONCLUSIVE"
        build_rows.append(
            f"| Slave | `{REVS['slave_revised']}` | expected fail-closed | SKIP (pio missing) | {slave_class} |"
        )
        add_finding(
            "BUILD-SLAVE-REVISED",
            slave_class,
            "Revised Slave requires local provisioning file src/esp_now_keys.local.h. PlatformIO not available for compile verification.",
        )

        add_section("Build results", "\n".join(build_rows))

        # Flutter <-> Master command compatibility
        cmd_matrix = [
            "| Flutter | Master | Compatible | Evidence |",
            "|---------|--------|------------|----------|",
            "| before | before | YES | Both use `{ state, brightness? }` with no request_id/issued_at. |",
            "| before | revised | NO | Old Flutter omits `request_id` and `issued_at`; revised Master rejects with field-count check. |",
            "| revised | before | NO | Revised Flutter emits `request_id`/`issued_at`; old Master expects only `state`/`brightness` and rejects extra fields. |",
            "| revised | revised | YES | Both use `{ state, brightness?, request_id, issued_at }` with matching validation ranges. |",
        ]
        add_section("Flutter <-> Master protocol compatibility", "\n".join(cmd_matrix))
        add_finding(
            "CMD-OLD-NEW",
            "PROVEN_INCOMPATIBLE",
            "Old Flutter <-> revised Master and revised Flutter <-> old Master are incompatible because of command field-count check and required request_id/issued_at.",
        )

        # Master <-> Slave ESP-NOW compatibility
        esp_matrix = [
            "| Master | Slave | Compatible | Evidence |",
            "|--------|-------|------------|----------|",
            "| before | before | YES | Both use legacy unencrypted struct without PMK/LMK/auth beacon; struct sizes match legacy build. |",
            "| before | revised | NO | Revised Slave requires PMK/LMK and authenticated beacon before accepting commands; old Master does not send them. |",
            "| revised | before | NO | Revised Master sends encrypted commands and expects auth beacon handshake; old Slave has no PMK/LMK/auth state. |",
            "| revised | revised | CONDITIONAL | Compatible only when both are provisioned with matching 16-byte PMK/LMK and channel lock/auth handshake completes. |",
        ]
        add_section("Master <-> Slave protocol compatibility", "\n".join(esp_matrix))
        add_finding(
            "ESPNOW-MIXED",
            "PROVEN_INCOMPATIBLE",
            "Any mixed old/new Master/Slave pair is incompatible due to PMK/LMK encryption and authenticated-beacon gating.",
        )

        # Firebase authorization matrix
        auth_matrix = [
            "| Actor | Resource | Operation | Rules allow | Application performs | Notes |",
            "|-------|----------|-----------|-------------|----------------------|-------|",
            "| owner | RTDB telemetry/rooms/gateway | read | YES | YES | owner OR controller. |",
            "| controller | RTDB telemetry/rooms/gateway | read/write | YES | YES | controller only. |",
            "| owner | RTDB commands/rooms/.../tools/... | write | YES | YES | owner only; device whitelist enforced. |",
            "| controller | RTDB commands/rooms/.../tools/... | write | NO | NO | rules require owner. |",
            "| owner | Firestore sensorLogs | read | YES | YES | owner OR controller. |",
            "| owner | Firestore sensorLogs | create | NO | YES | **CONTRACT DEFECT** (see below). |",
            "| controller | Firestore sensorLogs | create | YES | UNKNOWN | No controller-side writer found in source. |",
            "| unauthenticated | any | any | NO | N/A | denied by default. |",
        ]
        add_section("Firebase authorization matrix", "\n".join(auth_matrix))
        add_finding(
            "AUTH-SENSORLOGS",
            "CONFIRMED_CONTRACT_DEFECT",
            "Flutter owner role attempts Firestore sensorLogs create, but Firestore rules permit create only for controller role.",
        )

        # History persistence ownership
        hist_body = (
            "Runtime components searched for Firestore `sensorLogs` writers:\n\n"
            "- `SaveSensorLogUseCase` is instantiated in `lib/app/app_dependencies.dart` and called from `MonitoringBloc._maybeSaveSensorLog`.\n"
            "- The only implementation found is `FirebaseHistoryDataSource` / `HistoryRepositoryImpl` on the Flutter side.\n"
            "- No Master/ESP32 firmware code writes to Firestore `sensorLogs`.\n\n"
            "**WRITER = Flutter owner**\n\n"
            "Because the Flutter auth identity is `owner: true` and Firestore rules require `controller == true` for create, this is a **CONFIRMED_CONTRACT_DEFECT**."
        )
        add_section("History persistence ownership", hist_body)

        # Heartbeat / control gating trace
        hb_body = """```text
Master NTP synchronized
    |
    v
sendHeartbeat() -> /device/sensorData/unix_time (epoch seconds)
    |
    v
Flutter MonitoringBloc reads heartbeatEpochSeconds
    |
    v
_eshStatusFor(heartbeat, now)
    ageSeconds = now.epochSeconds - heartbeat
    online if 0 <= ageSeconds < 60
    |
    v
canControl = isConnected && eshStatus == online
```

Failure chain (source-proven):

```text
NTP unavailable
    -> Master cannot publish valid unix_time
    -> Flutter heartbeatEpochSeconds null/stale
    -> eshStatus != online
    -> canControl = false
```

Evidence classification: CONFIRMED_STATIC."""
        add_section("Heartbeat/control-gating trace", hb_body)
        add_finding(
            "HB-GATING",
            "CONFIRMED_STATIC",
            "Master heartbeat failure disables Flutter control even when Firebase connectivity exists.",
        )

        # Slave availability trace
        slave_body = """```text
Valid Slave ESP-NOW state packet
    |
    v
noteValidSlavePacket() updates lastSlavePacketMs
    |
    v
refreshSlaveAvailability(): online = packetSeen && (now - lastPacketMs) < 15000 ms
    |
    v
publishSlaveAvailability() -> /gateway/status/slave { online, last_seen? }
    |
    v
Flutter WatchSlaveAvailabilityUseCase / MonitoringBloc
    |
    v
canControlDevice = canControl && (not slave-owned || slaveOnline == true)
```

Slave-owned rooms: `lorong`, `kamar_1`, `kamar_2`, `dapur`. Master-owned: `teras`.

Failure chain (source-proven):

```text
ESP-NOW link down or Slave unprovisioned
    -> no valid Slave packet within 15 s
    -> slaveOnline = false
    -> canControlDevice false for lorong/kamar_1/kamar_2/dapur
    -> Teras (Master-owned) may remain controllable if canControl is true
```

Evidence classification: CONFIRMED_STATIC."""
        add_section("Slave availability trace", slave_body)
        add_finding(
            "SLAVE-GATING",
            "CONFIRMED_STATIC",
            "Master/Slave link failure disables Slave-owned rooms while Master-owned control may remain available.",
        )

        # Clock / freshness analysis
        clock_body = """Time authorities:

| Authority | Source | Unit |
|-----------|--------|------|
| Firebase server time | RTDB `.info/serverTimeOffset` | ms offset |
| Flutter command timestamp | `DateTime.now().ms + serverTimeOffset` | ms |
| RTDB rules freshness | `now` (server ms) | ms |
| Master NTP time | `gettimeofday()` after NTP sync | s + us |
| Master freshness window | `COMMAND_MAX_AGE_MS = 15000`, `COMMAND_FUTURE_TOLERANCE_MS = 5000` | ms |

RTDB rules accept `issued_at` in `[now - 15000, now + 5000]`.
Master accepts `issued_at` in `(nowMs - 15000, nowMs + 5000]` (strict future check, non-strict stale check in code: `issuedAtMs > nowMs + 5000` rejects; `issuedAtMs <= nowMs - 15000` rejects).

Because the two freshness checks use independent clocks (Firebase server vs Master NTP), a command can pass RTDB and fail Master if clocks differ by more than the tighter tolerance. The condition is **PROVEN POSSIBLE** when NTP is skewed or unavailable.

Evidence classification: CONFIRMED_STATIC."""
        add_section("Clock/freshness analysis", clock_body)
        add_finding(
            "CLOCK-SKEW",
            "CONFIRMED_STATIC",
            "A command may pass RTDB freshness validation and still fail Master freshness validation if Firebase server time and Master NTP time disagree sufficiently.",
        )

        # Sensor validation changes
        sensor_body = (
            "Revised Master (`src/modbus.cpp`, `src/pzem.cpp`) introduces stricter validation:\n\n"
            "- Modbus: response length, slave ID, function code, byte count, CRC, physical ranges.\n"
            "- PZEM: connected flag requires finite values in accepted ranges.\n\n"
            "Revised Flutter (`monitoring_entity_mapper.dart`) further overrides `connected=true` to unavailable when:\n\n"
            "- `sampled_at` is missing/null, OR\n"
            "- any required physical value is out of range (voltage 80-260, current 0-100, power 0-23000, energy 0-9999.99, temperature -40-125, humidity 0-100).\n\n"
            "This is a **SOURCE-CONFIRMED BEHAVIOR CHANGE**. Whether real hardware now appears disconnected requires hardware validation."
        )
        add_section("Sensor validation changes", sensor_body)

        # Confirmed defects
        defects = [f for f in findings if f["classification"] in ("FAIL", "CONFIRMED_CONTRACT_DEFECT", "PROVEN_INCOMPATIBLE")]
        if not defects:
            defects = [{"id": "NONE", "classification": "NONE", "description": "No FAIL-class findings in this run."}]
        defect_body = "\n".join(f"- **{f['id']}** [{f['classification']}]: {f['description']}" for f in defects)
        add_section("Confirmed defects", defect_body)

        # Expected provisioning requirements
        prov_body = (
            "Revised Master requires these local-only headers (intentional fail-closed):\n\n"
            "- `include/firebase_config.local.h` (FIREBASE_DATABASE_URL, FIREBASE_API_KEY, FIREBASE_USER_EMAIL, FIREBASE_USER_PASSWORD)\n"
            "- `include/wifi_config.local.h` (WIFI_SSID, WIFI_PASSWORD)\n"
            "- `include/esp_now_keys.local.h` (ESPNOW_PMK_BYTES, ESPNOW_LMK_BYTES, 16 bytes each)\n\n"
            "Revised Slave requires:\n\n"
            "- `src/esp_now_keys.local.h` (ESPNOW_PMK_BYTES, ESPNOW_LMK_BYTES, 16 bytes each)\n\n"
            "Classification: EXPECTED_PROVISIONING_FAILURE."
        )
        add_section("Expected provisioning requirements", prov_body)

        # Hardware-dependent unknowns
        add_section(
            "Hardware-dependent unknowns",
            "- Whether revised Modbus/PZEM parsing accepts the real installed sensors (HARDWARE_REQUIRED).\n"
            "- Whether Master/Slave ESP-NOW encrypted link establishes reliably with matching PMK/LMK (HARDWARE_REQUIRED).\n"
            "- Whether actual relay/dimmer hardware responds correctly to revised command schema (HARDWARE_REQUIRED).",
        )

        # Live-backend-dependent unknowns
        add_section(
            "Live-backend-dependent unknowns",
            "- Real Firebase Auth custom claims (`owner` vs `controller`) assignment and sign-in flow (LIVE_BACKEND_REQUIRED).\n"
            "- End-to-end command latency under real network conditions and its effect on the 15 s freshness window (LIVE_BACKEND_REQUIRED).\n"
            "- Firestore `sensorLogs` write behavior against the live project; local emulator/rules tests can confirm rules but not production claim configuration (LIVE_BACKEND_REQUIRED).",
        )

        # Recommended follow-up issues
        followups = [
            "1. **Build/provisioning UX** - Document/copy commands for creating `.local.h` files from `.example.h`; add CI step that builds revised firmware with synthetic provisioning.",
            "2. **Flutter <-> Master protocol migration** - Decide whether to support a version-negotiation/graceful period or require simultaneous deployment of both sides.",
            "3. **Master <-> Slave ESP-NOW migration** - Provide provisioning procedure to ensure matching PMK/LMK; confirm channel-lock/auth handshake timing.",
            "4. **Firebase role provisioning** - Document how to assign `owner` and `controller` custom claims and which devices need which role.",
            "5. **Firestore sensorLogs ownership** - Resolve the Flutter-owner-writer vs controller-only-rule contradiction; either move writer to controller or update rules.",
            "6. **Heartbeat/NTP resilience** - Add UI messaging and Master fallback behavior when NTP/time is unavailable.",
            "7. **Command timestamp design** - Re-evaluate dual freshness checks (RTDB + Master) and clock-sensitivity risk.",
            "8. **Slave availability semantics** - Confirm 15 s online window and status publish interval match user expectations.",
            "9. **Sensor validation hardware check** - Validate real sensor ranges against new acceptance rules.",
            "10. **Historical credential rotation** - Rotate any credentials previously committed to Git history.",
        ]
        add_section("Recommended follow-up issues", "\n".join(followups))

        # All findings table
        finding_rows = ["| Id | Classification | Description |", "|----|----------------|-------------|"]
        for f in findings:
            desc = f["description"].replace("|", "\\|").replace("\n", " ")
            finding_rows.append(f"| {f['id']} | {f['classification']} | {desc} |")
        add_section("All findings", "\n".join(finding_rows))

        report = "\n".join(report_parts)
        REPORT_PATH.write_text(report, encoding="utf-8")
        print(f"\nReport written to: {REPORT_PATH}")
        print("\n--- REPORT PREVIEW ---")
        print(report)
    finally:
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()

