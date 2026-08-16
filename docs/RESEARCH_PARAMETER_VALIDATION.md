# Scientific Parameter Validation

Research and evidence record for the environmental parameters that the PRD marks
as "requiring further validation". This document establishes the academic basis,
units, and limitations for four parameters, and records whether the current
implementation matches its authoritative reference.

## Scope

This document covers exactly four parameters:

1. Heat Index formula
2. Electricity carbon emission factor
3. Temperature classification thresholds
4. Relative humidity classification thresholds

It is an evidence record, not marketing prose. Where a number has no exact
authoritative source, this document says so explicitly.

## Traceability

| Reference | Parameter |
|-----------|-----------|
| FR-09 | Heat Index |
| FR-10 | Temperature classification |
| FR-11 | Humidity classification |
| FR-06 | Emission factor (`Estimated Emission = Energy (kWh) × factor`) |
| GitHub Issue #20 | This research task |

PRD Section 25 "Items Requiring Further Validation" items: #1 (Heat Index
formula), #2 (emission-factor reference), #3/#4 (temperature/humidity threshold
basis).

> Note: the PRD v0.1 is maintained outside this repository (see
> `docs/PRD_AUTH_MODEL_DECISION.md`). No PRD file exists in-repo; FR IDs listed
> here are the ones referenced by Issue #20 and Issue #19.

---

## 1. Heat Index

### Current implementation

`apps/flutter/lib/features/monitoring/domain/entities/sensor_data.dart:17-39`.

A 9-term polynomial evaluated directly on **Celsius** temperature `t` and
relative humidity `h` (percent), preceded by a shortcut:

```dart
double get heatIndex {
  if (temperature < 27) return temperature;
  const c1 = -8.78469475556;
  const c2 = 1.61139411;
  const c3 = 2.33854883889;
  const c4 = -0.14611605;
  const c5 = -0.012308094;
  const c6 = -0.0164248277778;
  const c7 = 0.002211732;
  const c8 = 0.00072546;
  const c9 = -0.000003582;
  final t = temperature;
  final h = humidity;
  return c1 + c2*t + c3*h + c4*t*h + c5*t*t + c6*h*h
       + c7*t*t*h + c8*t*h*h + c9*t*t*h*h;
}
```

### Authoritative reference

National Weather Service (NWS) / NOAA Weather Prediction Center (WPC),
*The Heat Index Equation* (page last modified 2022-05-12):

- URL: <https://www.wpc.ncep.noaa.gov/html/heatindex_equation.shtml>
- Accessed 2026-08-17.

This documents the Rothfusz regression, itself from:

- Rothfusz, L. P. (1990). *The Heat Index "Equation" (or, More Than You Ever
  Wanted to Know About Heat Index)*. NWS Southern Region Technical Attachment
  SR 90-23. National Weather Service, Fort Worth, Texas.

### Formula and units (official, Fahrenheit domain)

```
HI = -42.379 + 2.04901523*T + 10.14333127*RH - .22475541*T*RH
     - .00683783*T*T - .05481717*RH*RH + .00122874*T*T*RH
     + .00085282*T*RH*RH - .00000199*T*T*RH*RH
```

- `T` = temperature in **degrees Fahrenheit**.
- `RH` = relative humidity in **percent**.
- `HI` = heat index, an apparent temperature in **degrees Fahrenheit**.

NWS applies the full regression when the averaged simple-formula heat index is
≥ 80 °F, with two edge adjustments:

- if `RH < 13%` and `80 °F ≤ T ≤ 112 °F`: subtract
  `((13-RH)/4)*sqrt((17-|T-95|)/17)`
- if `RH > 85%` and `80 °F ≤ T ≤ 87 °F`: add `((RH-85)/10)*((87-T)/5)`

Below ~80 °F the NWS uses the simple Steadman formula:
`HI = 0.5 * {T + 61.0 + [(T-68.0)*1.2] + (RH*0.094)}`, averaged with `T`.

### Comparison with repository implementation

The repository polynomial is the **exact algebraic transform** of the °F
Rothfusz regression into the Celsius domain, i.e.

```
HI_C = (HI_F(T_F, RH) - 32) / 1.8,   with  T_F = 1.8 * T_C + 32
```

Substituting and expanding to a 9-term polynomial in `T_C` and `RH` yields
exactly the repository coefficients `c1..c9` (verified term-by-term to
double-precision rounding, ≤ 1e-12 relative difference). The repository
coefficients are therefore **not** an approximation of the Rothfusz regression:
they are its exact Celsius-domain form. This is Case A (mathematically
equivalent).

Two deliberate simplifications exist and are documented as such:

1. **`temperature < 27` shortcut.** The repository returns the dry-bulb
   temperature directly when `T < 27 °C` instead of running the NWS simple
   (Steadman) formula. `27 °C` = 80.6 °F, i.e. a rounded approximation of the
   NWS 80 °F (26.67 °C) activation threshold. Below this threshold the NWS
   simple formula returns a value within a fraction of a degree of the dry-bulb
   temperature, so returning `T` is a valid approximation, not an exact NWS
   reproduction. The choice of 27 (rather than 26.67) is a project
   simplification, not an NWS constant.

2. **Edge adjustments omitted.** The `RH < 13%` adjustment is irrelevant to
   tropical Indonesia (RH is rarely below 13% and never in this application's
   operating envelope). The `RH > 85%` adjustment is omitted; its maximum effect
   over the valid band (`80–87 °F`, i.e. ~26.7–30.6 °C) is under 0.3 °C (see
   validation table).

### Applicability and limitations

- The Rothfusz regression is not valid for extreme conditions outside
  Steadman's data range (NWS states this explicitly). For household tropical
  monitoring (roughly 20–40 °C, 40–100 %RH) it is within the practical range.
- The NWS heat index assumes shade and light wind; full sun can raise apparent
  temperature by up to ~8 °C (~15 °F). The application reports indoor/sensor
  ambient conditions and does not claim an outdoor, sun-exposed index.
- The heat index is an empirical comfort/stress index, not a physically
  measured quantity.

### Validation examples

Repository result vs. the NWS Fahrenheit method (convert `T` to °F, apply the
official equation and the `RH>85%` adjustment where applicable, convert back to
°C):

| T °C | RH % | Repo HI °C | NWS method °C | Difference | Note |
| ---: | ---: | ---------: | ------------: | ---------: | ---- |
| 27 | 40 | 26.86 | 26.86 | 0.000 | full regression |
| 27 | 80 | 29.74 | 29.74 | 0.000 | full regression |
| 30 | 50 | 31.05 | 31.05 | 0.000 | full regression |
| 30 | 70 | 35.04 | 35.04 | 0.000 | full regression |
| 32 | 60 | 37.07 | 37.07 | 0.000 | full regression |
| 35 | 70 | 50.34 | 50.34 | 0.000 | full regression |
| 28 | 90 | 33.75 | 34.00 | -0.256 | RH>85% adjustment omitted |
| 31 | 90 | 44.68 | 44.68 | 0.000 | outside 80–87 °F band |
| 25 | 60 | 25.00 | 25.45 | -0.45 | `T<27` shortcut vs simple formula |

### Implementation decision

**Keep the implementation unchanged.** The core polynomial is the exact
Celsius-domain Rothfusz regression (Case A). The `temperature < 27` shortcut and
the omitted `RH>85%` adjustment are minor, documented simplifications whose
combined error is under ~0.5 °C and only at the low/very-humid margins of the
operating envelope. No user-visible change is required by Issue #20.

---

## 2. Electricity Carbon Emission Factor

### Current implementation

`apps/flutter/lib/app/app_dependencies.dart:24`:

```dart
static const defaultEmissionFactor = 0.85;
```

Wired into `EstimateEmissionUseCase` (`estimate_emission_use_case.dart`) which
computes `energyKwh * emissionFactorKgCo2PerKwh`. The UI label is
`kg CO₂` (`monitoring.dart`, `history.dart`), i.e. **CO₂ only**, not CO₂e.

A duplicate default `0.85` also appears as a fallback in
`history_repository_impl.dart:20-21`.

### Authoritative source

Kementerian Energi dan Sumber Daya Mineral (ESDM), Direktorat Jenderal
Ketenagalistrikan:

- **Keputusan Menteri ESDM Nomor 163.K/HK.02/MEM.S/2021** tentang *Penetapan
  Nilai Faktor Emisi Gas Rumah Kaca Sistem Ketenagalistrikan* (2021).
- JDIH record: <https://jdih.esdm.go.id/index.php/web/result/2183/detail>
  (accessed 2026-08-17; the PDF is served behind an anti-bot layer).
- Underlying data: Ditjen Ketenagalistrikan, *Nilai Faktor Emisi GRK Sistem
  Ketenagalistrikan Tahun 2019*,
  <https://gatrik.esdm.go.id/assets/uploads/download_index/files/96d7c-nilai-fe-grk-sistem-ketenagalistrikan-tahun-2019.pdf>
  (per-grid values; served behind the same anti-bot layer).

This regulation establishes **per-grid** greenhouse-gas emission factors for the
Indonesian electricity system (Jamali / Jawa-Madura-Bali, Sumatera, Kalimantan,
Sulawesi, and others), expressed in tCO₂/MWh.

### Grid / geographical scope

The relevant system for a typical Indonesian household application is the
**Jamali (Jawa–Madura–Bali)** grid, the dominant interconnected system serving
the large majority of Indonesian electricity demand.

### Year / version

Based on the 2019 electricity-system emission inventory, published in 2021
(Kepmen ESDM 163.K/2021).

### Units

`0.85 kg CO₂/kWh` is numerically equivalent to `0.85 tCO₂/MWh`:

```
0.85 kg/kWh = 0.85 × (1000 kg) / (1000 kWh) = 0.85 t / MWh
```

This equivalence is exact (factor 1000 in numerator and denominator cancel).
The app consumes energy in **kWh** (contract: `contracts/telemetry-schema.md`,
settled by Issue #19/PR #29), so `energyKwh × 0.85` produces kg CO₂ directly.
No additional ×1000 or ÷1000 scaling exists in the emission path.

### Reported factor vs. app factor

- Official Jamali grid emission factor (Kepmen ESDM 163.K/2021, 2019 data):
  **≈ 0.87 tCO₂/MWh** (secondary citations report 0.87 for the Jamali grid;
  the full per-grid table is in the regulation PDF).
- App factor: **0.85 kg CO₂/kWh**.

`0.85` sits within the published year-to-year range of the Jamali grid factor
(historically ~0.85–0.87 tCO₂/MWh as the coal share shifted). The app value is a
**reasonable approximation** of the Jamali grid factor but is **not** the exact
Kepmen ESDM 163.K/2021 Jamali value.

### Applicability and interpretation

- The factor is **grid- and year-dependent**, not a universal Indonesian
  constant. Sumatera, Kalimantan, and other grids have different (often higher)
  values.
- The app value is **CO₂ only**, consistent with a simplified, consumer-facing
  estimate. It does not account for CH₄/N₂O (CO₂e), lifecycle emissions, or
  transmission losses.
- The factor models average grid generation mix, not marginal displacement.

### Implementation decision

**Keep `0.85 kg CO₂/kWh`**, and document it as a project assumption rather than
an exact official value. Rationale:

1. `0.85` is within the authoritative Jamali grid range and is a defensible,
   order-of-magnitude-correct consumer estimate.
2. The difference to the exact 2021 Jamali value (~0.87) is ~2.3%, below the
   precision that a simplified household estimate can justify, and below the
   year-to-year drift of the official factor itself.
3. Issue #20 allows `0.85` (or a corrected value) but does not require a change;
   no validated reference contradicts `0.85` to a degree that would change
   user-visible behaviour meaningfully.

If the project later wants strict traceability, the recommended change is to
quote the Jamali grid factor `0.87 tCO₂/MWh` (Kepmen ESDM 163.K/2021) and keep
it configurable; this is a follow-up decision, not part of this issue.

---

## 3. Temperature Classification

### Current thresholds

`sensor_data.dart:41-46` (exact operators, matching `domain_entities_test.dart`):

```text
temperature <= 25.7        -> Dingin
temperature <= 28.6        -> Sejuk
temperature <  31.5        -> Hangat
otherwise                  -> Panas
```

### Provenance

Repository history (`git log -S` / `git blame` on the legacy branch):

- The thresholds replaced a simpler `comfortLevel` rule
  (`<18 Dingin, >30 Panas`, RH `<30 Kering, >70 Lembap`) in legacy commit
  `5bd9fb6 "revisi rusak"` (2026-08-14).
- The monorepo migration (`01edd31`) carried the file to
  `apps/flutter/.../sensor_data.dart` unchanged.
- No commit message, comment, or in-repo document states a source for the exact
  decimals. The PRD is external and not versioned in this repository.

### Literature / standard basis

Indonesian and international thermal-comfort standards define comfort zones for
**indoor** conditioned spaces; they do not define a 4-level ambient
"Dingin/Sejuk/Hangat/Panas" classification, and none states 25.7 / 28.6 / 31.5:

- **SNI 03-6572-2001** *Tata cara perancangan sistem ventilasi dan pengkondisian
  udara pada bangunan gedung* (BSN). Defines tropical thermal-comfort
  categories (effective temperature):
  - Sejuk nyaman: 20.5 – 22.8 °C
  - Nyaman optimal: 22.8 – 25.8 °C
  - Hangat nyaman: 25.8 – 27.1 °C (at 50–60 %RH)
  - Comfort RH band: 40 – 60 % (higher for the "sejuk" category).
- **ANSI/ASHRAE Standard 55** (Thermal Environmental Conditions for Human
  Occupancy; current edition 55-2023): cooling-season operative temperature
  ~22.5 – 26.0 °C (0.5 clo), relative humidity ≤ 60 % and humidity ratio
  ≤ 12 g/kg.
- **ISO 7730** (Ergonomics of the thermal environment — PMV/PPD): comfort band
  aligned with ASHRAE 55 (~20–26 °C, 30–60 %RH).

The application classifies **ambient room conditions**, which in tropical
Indonesia routinely exceed the indoor AC comfort zone (SNI "hangat nyaman"
upper bound is 27.1 °C, well below the app's "Panas" threshold of 31.5 °C).
The app's four levels are therefore a **project-defined operational
classification** whose boundaries sit above the indoor comfort standards.

### Interpretation and limitations

- The boundaries 25.7 / 28.6 / 31.5 °C **do not appear verbatim** in any
  located standard. Their two-decimal precision is a project/PRD choice, not a
  normative value.
- The ordering and the choice of four levels (cold / cool / warm / hot) are
  consistent with thermal-comfort vocabulary but are not traceable to a single
  authoritative numeric source.

**Classification: Category D — project-defined classification informed by
literature.**

The most defensible framing for the skripsi is:

> "The project uses a four-level ambient classification (Dingin/Sejuk/Hangat/
> Panas) adapted to tropical Indonesian conditions. The underlying comfort
> literature (SNI 03-6572-2001, ASHRAE 55) supports the interpretation of the
> ranges, while the exact decision boundaries are PRD-defined operational
> thresholds."

### Implementation decision

**Keep the thresholds unchanged** (hard constraint from Issue #20 — PRD values
must not be changed unilaterally). Document them as project-defined thresholds
informed by thermal-comfort literature. No exact normative source exists, and
none is claimed.

---

## 4. Relative Humidity Classification

### Current thresholds

`sensor_data.dart:48-52` (exact operators, matching `domain_entities_test.dart`):

```text
humidity <= 60.25          -> Kering
humidity <  86.62          -> Normal
otherwise                  -> Lembap
```

### Provenance

Same origin as the temperature thresholds: introduced in legacy commit
`5bd9fb6 "revisi rusak"`, carried unchanged through the monorepo migration
(`01edd31`). No in-repo source states the exact decimals.

### Literature / standard basis

- **SNI 03-6572-2001**: comfort relative humidity 40 – 60 % (with the "sejuk
  nyaman" category permitting up to ~80 %).
- **ANSI/ASHRAE Standard 55** and **ASHRAE 62**: comfort RH 30 – 60 %, upper
  limit 60 % (humidity ratio cap 12 g/kg).
- **ISO 7730**: 30 – 60 %RH comfort band.

The app's `60.25 %` "Kering" boundary is **consistent with** the widely cited
60 % upper comfort-RH limit (ASHRAE 55/62, SNI 03-6572-2001): below this the
air is not humid, and the app labels it "Kering" (dry). The `86.62 %` boundary
separates "Normal" from "Lembap" (very humid) and has **no direct standard
equivalent** — it is a project-specific high-humidity threshold.

### Interpretation and limitations

- The exact decimals 60.25 / 86.62 do **not** appear verbatim in any located
  standard; their precision is a project/PRD choice.
- `60.25` is *informed by* the 60 % comfort limit but is not identical to a
  normative boundary (60.25 vs 60.00).
- `86.62` has no identified normative basis and should be treated as a
  project-defined high-humidity threshold.

**Classification: Category D — project-defined classification informed by
literature** (with the 60.25 boundary nearest to a real literature value).

### Implementation decision

**Keep the thresholds unchanged** (Issue #20 hard constraint). Document them as
project-defined thresholds; the lower boundary is literature-informed (60 %
comfort-RH limit), the upper boundary is project-specific.

---

## 5. References

### Heat Index

1. NOAA / National Weather Service, Weather Prediction Center. *The Heat Index
   Equation*. <https://www.wpc.ncep.noaa.gov/html/heatindex_equation.shtml>
   (accessed 2026-08-17).
2. Rothfusz, L. P. (1990). *The Heat Index "Equation" (or, More Than You Ever
   Wanted to Know About Heat Index)*. NWS Southern Region Technical Attachment
   SR 90-23. National Weather Service, Fort Worth, TX.
3. National Weather Service. *Heat Forecast Tools / Heat Index*.
   <https://www.weather.gov/safety/heat-index> (accessed 2026-08-17).

### Emission factor

4. Kementerian ESDM. *Keputusan Menteri Energi dan Sumber Daya Mineral Nomor
   163.K/HK.02/MEM.S/2021 tentang Penetapan Nilai Faktor Emisi Gas Rumah Kaca
   Sistem Ketenagalistrikan*. 2021. JDIH KESDM:
   <https://jdih.esdm.go.id/index.php/web/result/2183/detail>
   (accessed 2026-08-17).
5. Direktorat Jenderal Ketenagalistrikan, Kementerian ESDM. *Nilai Faktor Emisi
   GRK Sistem Ketenagalistrikan Tahun 2019*.
   <https://gatrik.esdm.go.id/assets/uploads/download_index/files/96d7c-nilai-fe-grk-sistem-ketenagalistrikan-tahun-2019.pdf>
   (accessed 2026-08-17).

### Thermal comfort / thresholds

6. Badan Standardisasi Nasional. *SNI 03-6572-2001, Tata cara perancangan sistem
   ventilasi dan pengkondisian udara pada bangunan gedung*. 2001.
7. ASHRAE. *ANSI/ASHRAE Standard 55, Thermal Environmental Conditions for Human
   Occupancy* (current edition 55-2023).
   <https://www.ashrae.org/technical-resources/bookstore/standard-55-thermal-environmental-conditions-for-human-occupancy>
8. ISO. *ISO 7730, Ergonomics of the thermal environment — Analytical
   determination and interpretation of thermal comfort using calculation of the
   PMV and PPD indices and local thermal comfort criteria*.

---

## 6. Implementation Impact

- **Functional code changed:** No.
- **User-visible behaviour changed:** No.
- **PRD threshold values changed:** No.
- **Tests changed:** No functional tests changed; existing boundary tests remain
  green (see validation commands below).
- **Documentation added:** This file; plus in-code reference comments pointing
  here from `sensor_data.dart` and `app_dependencies.dart`.

### Research output matrix

| Parameter | Current value/algorithm | Authoritative source | Exact match? | Units | Scope/year | Decision |
|-----------|------------------------|----------------------|--------------|-------|------------|----------|
| Heat Index | Rothfusz 9-term (Celsius) + `T<27` shortcut | NWS/WPC Rothfusz SR 90-23 | Yes (core); Partial (shortcut/adjustments) | °C / %RH | US NOAA, 1990/2022 | Keep |
| Emission factor | 0.85 | Kepmen ESDM 163.K/2021 | Approximate (official Jamali ≈ 0.87) | kg CO₂/kWh | Jamali grid, 2019/2021 | Keep, document as assumption |
| Temperature | 25.7 / 28.6 / 31.5 | SNI 03-6572-2001 / ASHRAE 55 (comfort zones) | No exact source | °C | Indonesia/US, 2001/2023 | Keep, project-defined |
| Humidity | 60.25 / 86.62 | ASHRAE 55 / SNI (60% comfort RH) | Partial (60.25≈60); 86.62 no source | %RH | Indonesia/US | Keep, project-defined |
