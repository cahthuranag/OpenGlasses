# Plan IS — Refrigerant Toolkit (gauges to an answer, full P-T tables, EPA 608 flags, a door-sticker diagram)

**Status:** 📝 Drafted 2026-10-17 — nothing implemented. The EPA 608 reference was corrected
separately, in [#753](https://github.com/straff2002/OpenGlasses/pull/753).
**Track:** Field Assist (B2B), HVAC/R.
**Related:** Plan [structured vision](structured-vision-assessment.md) (AD: `instrument_reading`,
`InstrumentPlausibility`), Plan [GB](GB-field-test-round-3.md) P3 (`SpokenReading`), Plan
[EL](EL-equipment-identity.md) (equipment identity from the nameplate), Plan
[HU](HU-service-history-and-maintenance-flags.md) (the office's history by serial), Plan
[IF](IF-photographed-manuals.md) (`manual_capture`), Plan [IR](IR-test-sheets-from-a-photo.md) (the
electrical sibling: readings from a photo, limits only from a loaded source), Plan
[IQ](IQ-closeout-unknown-units-and-calling-base.md) (close-out), Plan
[IP](IP-organisation-feature-switches.md) (organisation switches).
**Origin:** The October 2026 competitor review. A new HVAC voice copilot markets gauge reading,
P-T charts, wiring diagrams and EPA 608 flags. We build our own versions, from public property
data and the regulation text, and copy none of theirs. Checking our own EPA 608 file for this plan
found it wrong. That fix is #753.

---

## Verified starting point (`main` @ `300047438`, 2026-10-17)

- **Superheat and subcooling exist, from a small table.** `domain_calc` (`DomainCalcTool`) does
  `pt_lookup`, `superheat` and `subcool` by linear interpolation over anchor points kept identical
  to the vault's `pt_charts.md`. That covers four refrigerants (R-410A, R-32, R-454B, R-22) at 8–12
  points each, single column (°F at psig). There is no dew/bubble distinction. Superheat should use
  the dew point and subcooling the bubble point, which matters for blends with glide (R-407C,
  R-448A, R-449A; R-454B a little). Any other refrigerant is refused: "No PT data for…".
- **The camera reads several gauges at once.** `vision_assess kind:"instrument_reading"` returns a
  `readings` array (quantity, instrument, value, unit, confidence, region). `UnitNormalizer` handles
  psi, kPa, bar, inHg and °F/°C. `InstrumentPlausibility` holds bands per quantity, and an
  implausible reading asks for a re-capture. A reading can fill a capture-flow step. Nothing chains
  a gauge reading into `domain_calc`, and nothing tells suction from liquid.
- **Refrigerant quantities are not tracked.** Nothing in `Services/FieldAssist` records
  refrigerant added or recovered, a unit's full charge, or a leak rate. EPA 608 exists only as
  vault text (`epa_608.md`), cited by the leak-check and start-up procedures' safety notes.
- **Wiring diagrams come from manuals.** A diagram passage in a loaded manual is staged and shown
  (`FigureAutoOpenPolicy`, `ManualFigureSheet`). A diagram printed inside a unit's panel door is
  only reachable by photographing it as a one-off or as a captured manual (`manual_capture`, built).
- **Equipment identity has the nameplate text.** `EquipmentIdentity.nameplateText` is kept on
  device. Nameplates usually print the refrigerant and the factory charge, which `equipment_lookup`
  does not yet extract as fields.

## Decisions proposed (owner to confirm)

1. **P-T data is generated from an open property library, not copied from anyone's chart.** A
   script runs CoolProp (MIT licence) offline at a pinned version and writes saturation tables
   (dew and bubble, 1 °F steps, psig at sea level) into the bundle. Property data are facts, but
   the source matters: an equation of state is citable and reproducible. Blends CoolProp does not
   define (R-454B, R-448A, R-449A may be among them) are added only from a published
   manufacturer table, with that table cited, or not at all. Every table carries its source line.
2. **The tool, not the prompt, is the authority.** The full tables live in a resource the tool
   reads, never in the vault's prompt core. `pt_charts.md` shrinks to a short note pointing at
   `domain_calc`, which saves prompt characters on every refrigeration turn. Every number spoken
   carries its source ("CoolProp 6.x, dew point").
3. **The refrigerant is never assumed.** It comes from the nameplate (identity), from the
   technician, or from a question. A gauge reading without a refrigerant gives pressures, not
   saturation temperatures.
4. **EPA flags inform; they never accuse or block.** Leak repair is the owner's duty under the
   rules. The app says what the rules say for this unit and records it: the applicable rule, the
   evacuation level, the leak rate and the threshold. It never stops a job, and it never tells a
   customer they are in breach.
5. **EPA flags are US-only.** They follow the organisation's jurisdiction (a CT profile key,
   `organizationJurisdiction`, defaulting to the store region for a solo technician). Canada
   (federal halocarbon regulations and provincial rules), Australia and New Zealand have their own
   refrigerant rules, out of scope until someone asks.

## Phases (one PR each)

### P0 — Saturation tables, generated and checked

- `Scripts/generate-pt-tables.py` (CoolProp pinned; run by hand, output committed):
  `Resources/Refrigerants/<designation>.json` with `dew` and `bubble` arrays from −40 °F to 150 °F
  in 1 °F steps, `source`, `generatedWith` and the library version. The first set: R-22, R-32,
  R-134a, R-404A, R-407A, R-407C, R-410A, R-507A, R-290, R-600a, R-744 (to its critical point) and
  R-1234yf. Then any blend with a cited manufacturer table (decision 1).
- `SaturationTable` (pure): psig ↔ °F for dew and bubble, interpolated, refusing out of range by
  name. `domain_calc` reads it. `superheat` uses dew, `subcool` uses bubble, and the answer says
  which and how much glide there is. `pt_charts.md` is reduced (decision 2), and the anchor points
  move into a test.
- Altitude: psig assumes sea-level atmospheric pressure. The answer says so, and an optional
  `altitude_ft` corrects it.
- **Exit tests:** every table's points against CoolProp's own values at a dozen temperatures; the
  four old anchor tables within ±1 °F (or the difference explained in the test); glide
  correct for R-407C (≈ 10 °F) and zero for R-410A within tolerance; licence and attribution in
  the third-party notices.

### P1 — Gauges to an answer, in one step

- "What's my superheat?" with the camera on the manifold or a digital gauge set:
  `instrument_reading` returns the readings, and a pure `GaugeRoleResolver` assigns suction, liquid
  and discharge from the instrument's own labels (LOW/HIGH, blue/red where the model reports
  them, "suction"/"liquid" on digital units). The line temperature comes from a probe reading in
  the same frame or by voice. `domain_calc` runs, and the answer is "Superheat 11 °F: suction
  118 psig is 39 °F dew for R-410A, line 50 °F."
- Each reading is recorded as a `SpokenReading`-shaped entry with method `instrument_reading`, the
  photo id, and the refrigerant and its source. `InstrumentPlausibility` gains per-refrigerant
  pressure bands, so a 30 psig "suction" on an R-410A system in cooling asks for a re-look instead
  of a confident answer.
- A role it cannot tell is asked: "Is the left gauge suction?" It is never guessed.
- **Exit tests:** role resolution over fixture readings (analog manifold, digital manifold, a
  single gauge); the chain to superheat and subcool; refrigerant missing → pressures only;
  out-of-band → re-capture line.

### P2 — Refrigerant log and EPA 608 flags (US)

- `refrigerant` tool: `added`, `recovered`, `charge`. Each entry has a quantity (lb/oz), the
  refrigerant and an optional cylinder, bound to the unit and the task. The unit's full charge comes
  from the nameplate (identity extraction gains `refrigerant` and `factory_charge`) or from the
  technician. The appliance category (comfort cooling, commercial refrigeration, industrial
  process, residential or light commercial AC) is asked once per unit.
- `EPA608Policy` (pure, from §§ 82.152, 82.156, 82.157 and 84.106 as of October 2026):
  - which rule applies, if any: 82.157 (ODS, ≥ 50 lb), 84.106 (HFC or substitute with GWP > 53,
    ≥ 15 lb, not residential or light commercial AC), or neither;
  - the pressure class and the Table 1 evacuation level;
  - the leak rate by the annualizing method. The last addition's date comes from this phone's
    history or the office's (HU). The first calculation after 1 January 2026 uses 365 days, as the
    rule says. With neither, the rate is shown as unknown, not assumed;
  - the threshold (20 / 30 / 10%) and whether it is exceeded.
- Flags, spoken once and recorded on the work order:
  - "before opening: recover to 10 in Hg" when a procedure step's safety note opens the circuit;
  - "this addition puts the leak rate at about 34%, over the 10% comfort-cooling threshold: the
    owner has 30 days to repair" when refrigerant is added;
  - the owner documentation of refrigerant added or removed, on the work order (84.106(b)).
  Decision 4 governs the wording.
- **Exit tests:** the policy table for a dozen units (R-22 60 lb comfort cooling; R-410A 20 lb
  rooftop; R-410A residential split, which is exempt; R-404A 40 lb walk-in; R-290 self-contained,
  which is not covered; and others); the annualizing calculation and its first-time rule; "unknown"
  when no history exists; jurisdiction other than US → no EPA flags; the wording guard (no
  "violation", "illegal", "fine").

### P3 — A wiring diagram from the unit's door

- "Photograph the wiring diagram" captures the panel-door sticker as a one-page, job-scoped capture
  (`manual_capture`, kind diagram, bound to the unit). It opens in the figure viewer and is attached
  to the next turns as an image, so "what does the black wire on terminal 4 go to?" is answered
  from the sticker, with "from the diagram you photographed" as the source.
- Captured diagrams travel with the job like other captures and may be offered to the office for
  that model (IF's review).
- **Exit tests:** capture scoped to the unit and the job; the source line; nothing kept after the
  job unless the office approves it.

## Acceptance

- With the camera on a manifold on an R-410A rooftop unit, "what's my superheat and subcool?" gives
  both numbers with their pressures, saturation temperatures (dew and bubble) and source, in one
  turn.
- An R-407C system's superheat uses the dew point and says the glide.
- Recording "added 4 pounds" on a 20 lb R-410A rooftop unit last topped up in March flags the leak
  rate against 10% and names the 30 days. On a residential split it says the leak-repair rule
  doesn't apply.
- No P-T number is spoken without a source, and no refrigerant is assumed.

## Open questions for the owner

1. Decision 5: the US only at first, or should Canada's federal halocarbon rules come with it for
   the partner's market?
2. Which blends matter most beyond the P0 set? It decides which manufacturer tables to cite
   (decision 1).
3. Should the refrigerant log feed the customer close-out (Plan IQ), for example "4 lb R-410A added",
   or stay on the organisation's work order only?
