# Field Safety Reference

Field-service safety prompts the AI should weave into responses whenever they apply.

## Electrical safety — Lockout/Tagout (LOTO)

Before opening any electrical panel, control box, or accessing energized components:

1. Identify all electrical sources feeding the unit (utility power, control transformer, separate disconnect for fan, etc.).
2. De-energize each source at its disconnect.
3. Lock and tag each disconnect with the technician's personal lock and tag.
4. Verify zero-energy state with a known-good meter on a known-live source first, then the de-energized circuit, then the known-live source again.
5. Test before touch.
6. PPE: insulated gloves, arc-rated clothing for the calculated incident energy level, safety glasses.

Never work on energized equipment unless required for diagnostic measurement and you have:
- Energized-work permit (employer policy).
- Voltage-rated PPE for the panel's incident energy.
- A second qualified person present.

## Refrigerant handling

- Wear refrigerant-rated gloves and ANSI Z87.1 eye protection any time you connect/disconnect gauges or open the circuit.
- Never vent refrigerant — recover per `epa_608.md`.
- A2L refrigerants (R-32, R-454B) are mildly flammable. Eliminate ignition sources before opening the circuit. Verify ventilation in mechanical rooms. See **A2L refrigerants** below.
- Never use a torch on a pressurized refrigerant line. Recover to 0 psig minimum before brazing.
- After brazing, nitrogen purge then pressure test before charging.

## A2L refrigerants (R-32, R-454B)

EPA 608 certification still applies; A2L practice comes from the equipment listing, the manufacturer's instructions and safety standards. Follow the unit's installation manual where it differs from anything here — manufacturers disagree on details (for example, one lists evacuation as required for A2L service and another as optional).

- **Equipment:** A2L systems are new equipment built for them (EPA SNAP Rule 23, May 2021). They are not drop-in or retrofit refrigerants for A1 systems. Never exceed the unit's maximum allowable charge.
- **Markings:** service ports, piping and hoses on A2L equipment are marked red. Look for them before connecting.
- **Tools:** use gauges, recovery machine, leak detector and gas detector rated for A2L; check that the vacuum pump is A2L-compatible and run its exhaust away from ignition sources.
- **Leak checks:** never use a flame or halide torch. An electronic detector should alarm at 25% of the lower flammable limit or lower, calibrated in refrigerant-free air.
- **Before breaking in or hot work:** ventilate the area and keep it ventilated; check with a combustible-gas detector; keep ignition sources (open flame, gas appliance, electric heater) out of the space.
- **Brazing:** recover the refrigerant (or isolate the section), purge with oxygen-free nitrogen — never compressed air or oxygen — and braze with nitrogen flowing. Never use a torch to remove a compressor; cut the tubing.
- **Cylinders:** A2L cylinders carry a red band or top and a resealable relief valve. A2L cylinders and recovery cylinders commonly use left-hand valve threads (an industry guideline, not a federal rule). Use dedicated recovery cylinders; never mix refrigerants.
- **Equipment sensors** lock out the compressor and run the blower on a leak. Don't defeat them.
- Keep a Class B fire extinguisher at hand.

Sources (checked 2026-10-17; next review 2027-04): EPA SNAP Rule 23; UL 60335-2-40 4th ed. detection requirements; Copeland AE4-1387; Lennox 508447-01; Arkema and ACCA cylinder notes.

## Heights and confined spaces

- Roof access requires fall-protection assessment. Parapet edges < 39 inches require either railings or a personal fall arrest system tied to a rated anchor point.
- Mechanical pits and tank rooms may be confined spaces. Test atmosphere (O₂, LEL, CO, H₂S) before entry.

## Heat

- Roof surface temperatures can exceed 150°F in summer. Hydrate. Limit continuous roof time on extreme heat days.
- Hot work in attics or boiler rooms requires elevated heat-stress awareness.

## When the AI should remind the technician

The Field Assist AI should proactively include relevant safety steps before recommending any action that involves:

- Opening an electrical panel or accessing any wiring → **LOTO + PPE**.
- Connecting gauges or opening the refrigerant circuit → **PPE + recovery (if circuit opens) + A2L caution (if applicable)**.
- Brazing or other hot work → **circuit must be at atmospheric pressure, nitrogen purge required**.
- Working on a roof → **fall-protection check**.

These reminders should be terse — one sentence per applicable hazard, not a lecture. The technician already knows the rules; the AI's job is to surface the right one at the right moment.
