# Refrigerant Pressure–Temperature (PT) Reference

Saturation temperatures and pressures come from the `domain_calc` tool, not from this file. Never quote a
saturation value from memory.

- `domain_calc` reads full saturation tables (dew and bubble, −40 °F to 150 °F and −40 °C to 65 °C) generated
  from CoolProp for R-22, R-32, R-134a, R-404A, R-407A, R-407C, R-410A, R-454B, R-507A, R-290, R-600a, R-744
  and R-1234yf. Its answer names the source; repeat it.
- Superheat uses the dew point and subcooling the bubble point. Blends with glide (R-407A, R-407C) differ by
  several degrees between the two.
- Gauge pressure is read against sea-level atmosphere unless an altitude is given.
- The refrigerant comes from the nameplate or the technician, never a guess. For a refrigerant with no table,
  give the pressures only.

## Quick rule-of-thumb pressures (R-410A, 70-75°F ambient, normal operation)

| Position | Expected gauge reading |
|----------|------------------------|
| Suction (low side) | 110-130 psig |
| Liquid (high side) | 250-300 psig |

Significant departure from these ranges (with the unit running, stabilized) suggests undercharge, overcharge, airflow restriction, or compressor issue. Diagnose with superheat + subcool — see `superheat_subcool.md`.

## Diagnostic interpretation

Read superheat and subcooling together — see the cheat sheet in `superheat_subcool.md`. Pressures alone are not a reliable diagnosis.
