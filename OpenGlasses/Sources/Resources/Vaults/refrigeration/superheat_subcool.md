# Superheat and Subcool — Measurement and Interpretation

Superheat and subcool are the two most useful diagnostic measurements for charge and system health. Always measure with the system stabilized (10+ minutes runtime after startup, steady ambient).

## Definitions

- **Superheat**: How much the suction-line refrigerant has warmed above its saturation temperature.
  `superheat_F = actual_suction_temp_F − saturation_temp_F_at_suction_pressure`
- **Subcool (Subcooling)**: How much the liquid-line refrigerant has cooled below its saturation temperature.
  `subcool_F = saturation_temp_F_at_liquid_pressure − actual_liquid_temp_F`

Both use the saturation temperature for the refrigerant in question, from `domain_calc` (see `pt_charts.md`): the dew point for superheat, the bubble point for subcool.

## Measurement procedure (TXV / EEV systems — target subcool)

1. Confirm refrigerant type from nameplate. Pull up the right PT column.
2. Ensure the unit is in cooling, with stable load (10+ min runtime).
3. Connect gauge manifold:
   - Low-side hose on suction service port.
   - High-side hose on liquid-line service port.
4. Clamp a calibrated pipe thermometer on the liquid line within 6 inches of the condenser exit.
5. Read liquid-line pressure → convert to saturation temp via PT chart.
6. `subcool = saturation_temp − measured_liquid_line_temp`.
7. Target: the unit's own specification, from the nameplate or installation manual. Commonly 8–14°F, but specifications vary widely (one manufacturer lists 5–7°F for a TXV condenser), so never charge to a generic number when the unit's figure is available.

## Measurement procedure (fixed-orifice / cap-tube systems — target superheat)

1. Same setup as above, but clamp thermometer on the suction line 6 inches from the compressor.
2. Read suction pressure → saturation temp via PT chart.
3. `superheat = measured_suction_line_temp − saturation_temp`.
4. Target superheat comes from a chart: indoor return-air wet-bulb and outdoor dry-bulb (in the shade, at the condenser inlet) give the target. Use the manufacturer's chart for the unit; generic charts are a fallback only. Targets are typically 5–25°F and rise as indoor wet-bulb rises. A blank cell in the chart means the system is outside its design range and no target applies.
5. Measured superheat above target → add refrigerant; below target → recover. The target moves as indoor wet-bulb changes during charging, so re-check it.

## Interpretation cheat sheet

Check airflow, filters, coils and your instruments first: poor airflow makes every number below misleading. A TXV/EEV holds superheat roughly constant, so read charge from **subcooling**. A fixed orifice lets superheat float with load and charge, so read charge from **superheat**; its subcooling swings with load.

| Superheat | Subcooling | Points to | Then check |
|-----------|------------|-----------|------------|
| High | Low | Undercharge / leak | Find the leak before adding refrigerant |
| High | High | Restriction on the high side: liquid-line restriction (drier, screen, kinked copper) or a metering device restricting (small or blocked piston, TXV closed or bulb lost its charge). Suction reads low, so it mimics undercharge | Temperature drop across the drier; don't add refrigerant |
| Low | High | Overcharge (on a TXV it shows mainly as high subcooling and high head) | Rule out a dirty or blocked condenser and low condenser airflow before recovering any charge |
| Low | Low | Metering device overfeeding (TXV stuck open, oversized or unseated piston); also an inefficient compressor or reversing-valve bypass | Suction and head pressure, compressor amps |
| Normal | Normal | Charge is probably right — look at airflow, controls and sensors | — |

Low suction pressure with **low** superheat usually means the evaporator is starved of heat — low airflow or load (dirty filter or coil, restricted return, wrong blower speed, low return-air temperature) — not a charge problem. High head pressure with **high** subcooling points to overcharge, a dirty or blocked condenser, or non-condensables. Suction pressure alone is not a reliable sign of low charge.

## Common mistakes

- Reading subcool on a fixed-orifice system. Subcool only diagnoses charge on TXV/EEV systems. On fixed orifice, use superheat.
- Adjusting charge without 10+ minutes of stable runtime. Numbers will be misleading.
- Forgetting to compensate for line set length on long pipe runs.
- Using an uncalibrated clamp thermometer — they drift; check against ice water (32°F) periodically.

## Safety reminder

Charging adjustments require connecting a refrigerant cylinder. Before opening the refrigerant circuit:
- Confirm proper PPE (refrigerant gloves, eye protection).
- Verify refrigerant in the cylinder matches the unit nameplate.
- Recover refrigerant per EPA 608 if the circuit must be opened for component access (see `epa_608.md`).

## Sources (checked 2026-10-17; next review 2027-04)

HVAC School (circuit diagnosis, overcharge, target superheat); Contracting Business (superheat and subcooling diagnostics); ACCA (non-condensables case); Goodman IO-348M. The unit's own documentation takes precedence.
