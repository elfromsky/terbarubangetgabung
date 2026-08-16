#!/usr/bin/env python3
"""
Issue #19 energy-unit contract: deterministic host-side guard.

The PZEM-004T-v30 raw energy register has a 1-Wh resolution, but the pinned
library (mandulaj/PZEM-004T-v30@1.1.2) divides that raw register value by 1000
in PZEM004Tv30::updateValues() and returns kWh from PZEM004Tv30::energy().
Master publishes the library value unchanged and Flutter consumes it as kWh.

This test pins the end-to-end unit contract so a second Wh->kWh conversion is
never introduced. It reads the actual repository sources and asserts that:

  1. the telemetry contract declares power.energy in kWh (not Wh);
  2. firmware publishes pzem.energy() unchanged (no /1000 on the energy path);
  3. Flutter ingestion consumes the wire value unchanged (no /1000);
  4. cost/emission use cases consume kWh (no hidden division).

Run:  python tools/energy_unit_contract_tests.py
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

PASS = 0
FAIL = 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("PASS  %s" % name)
    else:
        FAIL += 1
        print("FAIL  %s  %s" % (name, detail))


def read_text(rel):
    return (REPO_ROOT / rel).read_text(encoding="utf-8")


def has_kwh_integer_division_on_energy(source, symbol):
    """True if a suspicious /1000 (or / 1000) is applied to the energy symbol."""
    pattern = re.compile(
        r"%s\b.*?/\s*1000(?:\.0)?\b|/\s*1000(?:\.0)?\b.*?%s\b" % (symbol, symbol)
    )
    return bool(pattern.search(source))


def run_contract():
    print("== Issue #19 energy-unit contract ==")

    # 1. Telemetry schema declares kWh.
    schema = read_text("contracts/telemetry-schema.md")
    check(
        "telemetry-schema declares power.energy as kWh",
        re.search(r"\|\s*`energy`\s*\|\s*number\s*\|\s*kWh\s*\|", schema) is not None,
        "energy row must be '| `energy` | number | kWh | ...'",
    )
    check(
        "telemetry-schema no longer labels energy as Wh",
        re.search(r"\|\s*`energy`\s*\|\s*number\s*\|\s*Wh\s*\|", schema) is None,
        "stale Wh label remains in telemetry-schema.md",
    )

    # 2. Firmware publishes pzem.energy() unchanged.
    pzem = read_text("firmware/master/src/pzem.cpp")
    check(
        "firmware reads pzem.energy() directly",
        "pzem.energy()" in pzem,
        "pzem.energy() not found in firmware/master/src/pzem.cpp",
    )
    check(
        "firmware applies no /1000 to the energy value",
        not has_kwh_integer_division_on_energy(pzem, "energy"),
        "energy path must not divide by 1000",
    )

    telemetry = read_text("firmware/master/src/firebase_telemetry.cpp")
    check(
        "firmware publishes pzemData.energy unchanged",
        '"energy"' in telemetry and "pzemData.energy" in telemetry,
        "power.energy must be published from pzemData.energy",
    )
    check(
        "firmware telemetry applies no /1000 to energy",
        not has_kwh_integer_division_on_energy(telemetry, "energy"),
        "telemetry energy path must not divide by 1000",
    )

    # 3. Flutter ingestion consumes the wire value unchanged.
    mapper = read_text(
        "apps/flutter/lib/features/monitoring/data/mappers/"
        "monitoring_entity_mapper.dart"
    )
    check(
        "Flutter ingestion parses power['energy'] directly",
        "dto.power['energy']" in mapper,
        "energy must be read from power['energy']",
    )
    check(
        "Flutter ingestion applies no /1000 to energy",
        not has_kwh_integer_division_on_energy(mapper, "energy"),
        "ingestion must not divide energy by 1000",
    )

    # 4. Cost and emission use cases consume kWh (multiply only).
    cost = read_text(
        "apps/flutter/lib/features/monitoring/domain/usecases/"
        "estimate_energy_cost_use_case.dart"
    )
    check(
        "cost use case multiplies kWh by rate (no division)",
        "energyKwh * ratePerKwh" in cost,
        "cost must be energyKwh * ratePerKwh",
    )

    emission = read_text(
        "apps/flutter/lib/features/monitoring/domain/usecases/"
        "estimate_emission_use_case.dart"
    )
    check(
        "emission use case multiplies kWh by factor (no division)",
        "energyKwh * emissionFactorKgCo2PerKwh" in emission,
        "emission must be energyKwh * emissionFactorKgCo2PerKwh",
    )


def main():
    run_contract()
    print("\n==== SUMMARY: %d passed, %d failed ====" % (PASS, FAIL))
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
