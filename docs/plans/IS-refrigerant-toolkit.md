# Plan IS — Refrigerant Toolkit (gauges to an answer, full P-T tables, refrigerant-rule flags, a door-sticker diagram)

**Status:** 🚧 **P0 built 2026-10-19** — saturation tables generated with CoolProp 8.0.0 (pinned in
`Scripts/generate-pt-tables.py`, run by hand): 13 bundled tables (the planned twelve plus R-454B, which
CoolProp defines as a predefined mixture), dew and bubble series on the −40…150 °F (1 °F) and −40…65 °C
(0.5 °C) grids, absolute kPa; pure `SaturationTable`, `Atmosphere` (ISA altitude correction) and
`RefrigerantPressure`; `domain_calc` reads them (superheat on dew, subcool on bubble, glide, the source
line and the sea-level line; psig/°F or kPa/bar with °C); `pt_charts.md` reduced to a pointer; CoolProp in
Settings › About › Attributions. P1–P6 not started. Drafted 2026-10-17, P4–P6 added the same day. The EPA 608 reference was corrected
separately, in [#753](https://github.com/straff2002/OpenGlasses/pull/753). **Amended 2026-10-19
([below](#amendment-2026-10-19-canada-australia-and-new-zealand-first)):** Canada, Australia and New Zealand rules come
first and the US EPA 608 flags become a deferred phase (P2-US); metric units are first-class throughout.
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
   (dew and bubble, 1 °F steps, psig at sea level) into the bundle. *(Amended 2026-10-19: both a °C and
   a °F grid, pressures stored absolute — see the amendment's "Metric is first-class".)* Property data are facts, but
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
5. ~~**EPA flags are US-only.** They follow the organisation's jurisdiction (a CT profile key,
   `organizationJurisdiction`, defaulting to the store region for a solo technician). Canada
   (federal halocarbon regulations and provincial rules), Australia and New Zealand have their own
   refrigerant rules, out of scope until someone asks.~~ **Replaced 2026-10-19** by the amendment's
   decision 5: flags follow the jurisdiction, Canada, Australia and New Zealand come first, and the US
   is deferred. Decision 4 applies to every jurisdiction's flags, not only the EPA's.

## Phases (one PR each)

### P0 — Saturation tables, generated and checked

- `Scripts/generate-pt-tables.py` (CoolProp pinned; run by hand, output committed):
  `Resources/Refrigerants/<designation>.json` with `dew` and `bubble` arrays from −40 °F to 150 °F
  in 1 °F steps *(and a −40 °C to 65 °C grid in 0.5 °C steps, pressures absolute: amendment 2026-10-19)*, `source`, `generatedWith` and the library version. The first set: R-22, R-32,
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

### P2-US (deferred) — EPA 608 flags (US)

*(Relabelled 2026-10-19. The `refrigerant` tool in the first bullet is now the jurisdiction-neutral
log of the amendment's P2, in kilograms as well as pounds; the `EPA608Policy` and its flags below
are unchanged in substance and ship later, as one more policy behind the same log.)*

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

### P4 — Superheat and subcooling read together, and the other calculations

*(Added 2026-10-17 from a review of the topics HVAC technicians look up most.)*

- `RefrigerantCircuitDiagnosis` (pure): given superheat and subcooling (and, where known, suction
  and head pressure, metering type TXV/EEV or fixed orifice, and the evaporator's airflow), it
  returns the quadrant and the vault's candidate causes in order. The quadrants are high or low
  superheat crossed with high or low subcooling, plus normal. Each cause carries the next
  measurement that tells it from its neighbours. `domain_calc` appends it whenever it has computed
  both numbers.
  It never names one cause as *the* fault. It says "points to", lists the alternatives, and names
  the check that would decide.
- The table of quadrants and causes is vault content (`superheat_subcool.md`), not code, so a
  partner or an organisation can correct it. The vault-content review that started this phase
  rewrites that table from cited sources.
- New `domain_calc` operations, each with its formula and source in the answer:
  - `target_superheat` (fixed orifice): from indoor wet bulb and outdoor dry bulb, by the
    manufacturer's chart where the vault carries it. A generic chart is used only if a cited,
    redistributable one is found, and the answer says which.
  - `condensing_split`: saturated condensing temperature from head pressure (P0's bubble
    point), minus outdoor air temperature, compared with the unit's design split when the vault
    has it.
  - `delta_t`: return minus supply air temperature, judged against a target only from the
    manufacturer's data or a calculation from the sensible heat ratio and airflow, never against
    a fixed 20 °F.
- **Exit tests:** every quadrant with TXV and fixed-orifice variants; "unknown metering type" asks;
  the calculations against worked examples; no fixed delta-T target anywhere in the output.

### P5 — More instrument readings

- `UnitNormalizer` and `InstrumentPlausibility` gain microns (vacuum), inches of water column
  (static pressure), microamps (flame rectification), microfarads (capacitance, judged against
  the rated value and its printed tolerance) and ppm (CO, from a combustion analyser).
- An evacuation reading sequence: the micron reading at isolation, then again after a timed
  standing period, judged against the procedure's own pass figure (the vault's, never a number the
  model supplies).
- A CO reading above the vault's action threshold is a safety flag, spoken at once and recorded,
  like the vault's other safety reminders.
- **Exit tests:** normaliser corpus ("500 microns", "0.5 in wc", "2.1 µA", "45/5 µF", "CO 120
  ppm"); capacitor tolerance; the decay sequence; the CO flag.

### P6 — A starter set of diagnostic procedures

- New bundled procedures for the refrigeration vault, written by us and reviewed by a working HVAC
  technician before they ship. None are copied from anyone's articles, and each cites the vault
  files it uses:
  - evacuation and vacuum decay test;
  - run capacitor test (bench and under load);
  - flame sensor (microamps first, then clean);
  - contactor test;
  - control board inputs and outputs, before replacement;
  - short cycling;
  - frozen evaporator coil;
  - heat pump defrost;
  - thermostat wiring and the C wire.
- Each uses P4's and P5's readings and calculations where they fit, and ends in the work record
  like today's procedures.
- **Exit tests:** every procedure passes `validateProcedureGraph`; every step that opens the
  refrigerant circuit carries the recovery safety note; every citation resolves to a vault file.

## Acceptance

- With the camera on a manifold on an R-410A rooftop unit, "what's my superheat and subcool?" gives
  both numbers with their pressures, saturation temperatures (dew and bubble) and source, in one
  turn.
- An R-407C system's superheat uses the dew point and says the glide.
- *(P2-US, deferred)* Recording "added 4 pounds" on a 20 lb R-410A rooftop unit last topped up in March flags the leak
  rate against 10% and names the 30 days. On a residential split it says the leak-repair rule
  doesn't apply.
- No P-T number is spoken without a source, and no refrigerant is assumed.
- With superheat 22 °F and subcooling 4 °F on a TXV system, the answer names the likely low charge,
  the alternatives, and the check that decides between them.
- "500 microns, then 1,400 after ten minutes" is judged against the evacuation procedure's own
  pass figure and recorded.

## Open questions for the owner

1. ~~Decision 5: the US only at first, or should Canada's federal halocarbon rules come with it for
   the partner's market?~~ **Answered 2026-10-19:** Canada, Australia and New Zealand first; the US
   can wait (see the amendment).
2. Which blends matter most beyond the P0 set? It decides which manufacturer tables to cite
   (decision 1).
3. Should the refrigerant log feed the customer close-out (Plan IQ), for example "4 lb R-410A added"
   (or "1.8 kg"), or stay on the organisation's work order only?
4. Which Canadian provinces first? The amendment proposes Ontario and British Columbia, with
   Alberta as a thin third, and Quebec later. Which province is the partner's market in?
5. Should licence and certificate numbers go on the work order: the Ontario certificate number and
   expiry, the BC registration number, the federal certificate number, the Australian refrigerant
   handling licence and trading authorisation numbers, the New Zealand approved filler certificate?
   The rules name them as fields, but the app would then hold them in the technician's profile.
6. Should the app draft the notice text the technician writes on the equipment (Ontario's leak test
   notice, BC's label or tag, the federal withdrawal notice), or only list the fields?
7. Canada's default units: the amendment proposes °F and psig for gauge work and kilograms for the
   log, as a setting. Does the partner's crew work that way?
8. Is a Canadian site's federal status asked per site, or set once for the organisation (a crew
   that works on federal sites or First Nations reserve lands)?


---

## Amendment 2026-10-19: Canada, Australia and New Zealand first

The owner's direction, 2026-10-19: Canada, New Zealand and Australian rules first; the USA can
wait. Decision 5 is reversed, P2 is rebuilt around a jurisdiction-neutral log with one pure policy
per jurisdiction, and metric units become first-class in every phase that shows a number. Status is
unchanged: 📝 drafted, nothing built. P3, P6 and the rest of P0, P1, P4 and P5 stand as written,
apart from the unit changes below.

What was checked on `main` @ `e364e24bd` (2026-10-19): `organizationJurisdiction` does not exist
in code or in the CT plan yet. It is proposed here as a new CT profile key. `DomainCalcTool` knows
only °F and psig. `StorefrontReader` (Plan HP) already reads the App Store country as ISO 3166-1
alpha-2, and that is the solo technician's default.

**One correction to the brief:** the Federal Halocarbon Regulations, 2003 (SOR/2003-289) are
repealed. The **Federal Halocarbon Regulations, 2022** (SOR/2022-110, registered 2022-05-20,
s. 29 repeals the 2003 text) replace them, with the same scope. Everything below cites the 2022
text.

### Decision 5 (replaced)

5. **Flags follow the jurisdiction. Canada, Australia and New Zealand come first, and the US is
   deferred.**
   - The jurisdiction comes from `organizationJurisdiction` (a CT profile key, ISO 3166-1 alpha-2,
     with an ISO 3166-2 subdivision for Canada: `CA-ON`, `CA-BC`, `CA-AB`, `CA-QC`, …).
     A solo technician without a profile defaults to the storefront country (`StorefrontReader`).
     A storefront of `CA` has no province, so the province is asked once and kept as a setting.
   - Canada has two layers, and which one applies is a fact about the site, not the province. The
     federal regulations apply to systems owned by the federal Crown, a federal board, agency or
     Crown corporation, or a federal work or undertaking, and to systems on federal lands or
     Aboriginal lands (SOR/2022-110 s. 2). Most residential and commercial work is under the
     province's rules instead. So a Canadian site carries `federalSite: Bool?`, asked once per site
     ("Is this a federal site or on reserve land?"). When it is unanswered, the provincial policy
     runs and the answer carries one line: "If this is a federal site, other rules apply."
   - First policies: Canada federal; Ontario and British Columbia; Alberta as a thin third (it
     sets few technician-level duties of its own, so it is cheap). Quebec comes later: its official
     text could not be read for this amendment (see Unconfirmed). Australia. New Zealand.
   - The US EPA 608 policy is P2-US (deferred), unchanged in substance.
   - **A unit or site with no known jurisdiction gets no regulatory flags**, only the calculations
     and the neutral log. The same holds for a jurisdiction with no policy yet (the US until P2-US,
     Quebec, other provinces and territories, any other country). The answer never guesses a
     neighbouring jurisdiction's rules.
   - A policy only speaks about refrigerants inside its own scope. Each policy's scope table says
     which designations it covers, and every policy below leaves out R-290, R-600a, R-1270, R-744 and
     R-717 for its halocarbon duties (they are not halocarbons). Pure HFOs (R-1234yf, R-1234ze(E))
     are out of scope where the instrument lists substances and does not list them (Australia, New
     Zealand). They are marked unconfirmed for Canada, where the federal schedule names the class
     "Hydrofluorocarbons (HFC)" without a list. Blends are in scope wherever one component is:
     every instrument here covers a listed substance "alone or in a mixture", or says the same in
     other words. That puts R-454B (R-32 with R-1234yf) in scope everywhere.

Decision 4 applies to every policy: flags inform and never accuse or block, and they never tell a
customer they are in breach. The duty belongs to whoever the rule names: technician, owner or
business. The flag says whose it is.

### Metric is first-class

- **P0 tables, both unit sets.** The generator writes two temperature grids per refrigerant, each
  computed directly by CoolProp rather than converted from the other: −40 °F to 150 °F in 1 °F
  steps (191 points, as before) and −40 °C to 65 °C in 0.5 °C steps (211 points). Pressures are
  stored **absolute, in kPa**, to 0.01 kPa. Gauge values are derived at read time:
  `P(g) = P(abs) − P(atm)`, and the output is shown in kPa(g), bar(g) or psig. The tables carry
  no gauge column, so there is one source and no sea-level value baked in.
- **Atmospheric pressure and altitude.** A gauge reads relative to local atmosphere. A sea-level
  chart is wrong at altitude because the chart, not the gauge, assumed 101.325 kPa. The answer says
  "assuming sea level" unless it has an altitude (`altitude_m` or `altitude_ft`). With an altitude it
  uses the ISA barometric formula, `P(atm) = 101.325 × (1 − 2.25577×10⁻⁵ × h)^5.25588` kPa with h
  in metres. A reading the instrument reports as absolute (kPa abs, bar abs, psia) skips the
  correction. The P0 altitude bullet stands, now in either unit.
- **No change to the CoolProp decision.** Decision 1 needs only the second grid and absolute
  storage. Same library, same pinned version, same source line. The anchor-point test checks the
  old °F/psig anchors against the °F grid converted to psig at 101.325 kPa.
- **P1 and P4 accept and speak either.** Inputs are normalised to SI (kPa abs, K) inside the
  calculation, and the answer is rendered in the technician's units: "Superheat 6 K: suction
  820 kPa is 4 °C dew for R-410A, line 10 °C" or the existing °F sentence. A temperature difference
  is shown as K (metric) or °F (imperial) and spoken as "degrees". `InstrumentPlausibility`'s
  per-refrigerant bands are stored in SI. P4's `delta_t` and `condensing_split` follow suit. A
  manufacturer's target-superheat chart in °F is converted for display and cited as printed.
- **P5 gains metric vacuum units:** Pa and mbar next to microns, and `UnitNormalizer` learns
  "67 Pa" and "0.67 mbar" (≈ 500 microns). Static pressure in Pa as well as in. w.c.
- **Defaults by jurisdiction, always a setting.** `refrigerationUnits` holds pressure (kPa / bar /
  psi), temperature (°C / °F) and mass (kg / lb). An organisation profile can set the default.
  Defaults: Australia and New Zealand use kPa, °C and kg. Canada uses psig and °F for gauge work
  and kg for the log. The Canadian rules state quantities in kilograms (SOR/2022-110 Sch. 2 Part 5;
  BC and Ontario name amounts without units), and US-built equipment and gauge sets dominate. What
  Canadian technicians actually use day to day is **unconfirmed** by any official source, so it is
  open question 7. The US uses psig, °F and lb/oz.
- **Log quantities.** The log stores grams as an integer and accepts "1.8 kg", "1800 g", "4 lb" and
  "4 lb 6 oz" (1 lb = 0.45359237 kg exactly, 1 oz = 28.349523125 g). Records show kilograms to two
  decimals where a rule asks for kilograms, next to the quantity as it was said.

### P2 (restructured) — refrigerant log and jurisdiction policies

**The log (jurisdiction-neutral; the old P2's first bullet, kept).** The `refrigerant` tool records
`added`, `recovered` and `charge`, plus `leak_test` (date, result, method) and `released` (an
estimate, with a reason). Entries are bound to the unit and the task, with an optional cylinder.
The unit's facts:

- refrigerant and **design refrigerant** (from the nameplate or compliance plate via identity
  extraction, or from the technician; Australia and New Zealand turn on the difference);
- full charge, **per circuit** where there is more than one (the Canadian federal size test is per
  circuit);
- equipment kind (split or ducted AC or heat pump, rooftop, chiller, commercial refrigeration,
  commercial stand-alone, domestic appliance, vehicle AC), asked once per unit;
- for Canada, the site's `federalSite`.

The technician's profile can hold licence and certificate numbers (open question 5).

**The policies.** There is one pure, table-driven function per jurisdiction:
`(RefrigerantUnitFacts, [RefrigerantLogEntry], RefrigerantEvent, today) → [RefrigerantRuleFlag]`.
A `RefrigerantJurisdictionResolver` (pure) picks the policy from the profile key, the storefront and
the site. Each flag carries its kind (licence, recovery, charging precondition, leak deadline, leak
test due, record fields, notice, flammable, report), the person whose duty it is, any due date, and
a citation (instrument, section, as-at date). The facts live in a per-jurisdiction table with
their citations, so a rule change is a data change with a test. A flag is spoken once per job and
written to the work order. The events are: opening a circuit (a procedure step with the recovery
safety note), adding, recovering, a leak test, a recorded release, and decommissioning.

#### `CanadaFederalHalocarbonPolicy` — SOR/2022-110 (current to 2026-09-30)

Scope: air-conditioning or refrigeration systems (compressor, condenser, evaporator and expansion
valve, containing a halocarbon refrigerant) on a federal site. Halocarbons are Schedule 1 (CFCs,
HCFCs, HFCs, PFCs, halons and others), "whether existing alone or in a mixture" (s. 1). A system is
**large** if any circuit contains or is designed to contain more than 10 kg, and **small** otherwise
(s. 1).

| Event | Flag | Source |
|---|---|---|
| Any work | Only a certified person may install, service or recover. That means a provincially recognised environmental-awareness certificate plus trade recognition. The work order carries the certificate number. | ss. 1, 14; Sch. 2 Pt 5 item 8(e) |
| Opening a circuit | Recover into a container designed for that halocarbon; no release. | ss. 3(1), 15(1), 6 |
| Adding | Charging needs a previous leak test, and any leak found must have been reported to the owner and repaired. If the log has no leak test, or has an unrepaired leak, the flag says so. Charging for a leak test is not allowed. | ss. 9, 10 |
| Adding to prevent immediate danger | Allowed while the danger lasts. The owner must be told at once, and the owner reports to the Minister within 7 days. | s. 11 |
| Leak found | Repair it, isolate the leaking part and recover, or recover the system, as soon as possible and within 7 days. The flag names the date. | s. 18 |
| Large system, any visit | A leak test is due at least once every calendar year and no more than 15 months after the last one. The flag reads the log or the office's history (HU) and says when the next one is due; with no history it says the date is unknown. | s. 17 |
| Any service | Activity log fields go on the work order, in kilograms: equipment type, owner name and address, responsible person, location, serial or owner's identifier, halocarbon type, charging capacity (kg), date, activity type, description, technician and employer, certificate number, kg recovered, and type and kg charged. A large system logs installation, service, withdrawal and transfer of ownership; a small system logs each service. The owner keeps it for 5 years. | s. 23; Sch. 2 Pt 5; s. 26 |
| Decommissioning | Recover everything first, and fix a notice to the system: owner, location, identifier, halocarbon type and kg recovered, charging capacity, technician, employer and certificate number. | s. 16; Sch. 2 Pt 2 |
| Release recorded | 100 kg or more: the owner reports within 24 hours and in writing within 30 days. More than 10 kg and under 100 kg: the owner reports by 31 July (January to June releases) or by 31 January (July to December releases). | ss. 24, 25 |

There is no leak-rate threshold in the federal rules, so the policy computes none.

#### `CanadaProvincialHalocarbonPolicy` — Ontario, British Columbia, Alberta (Quebec later)

The provincial rules that matter here are Ontario's leak-test notice, BC's label or tag, and their
logs. They are why Ontario and BC come first. Both reach HFCs as well as ODS, both set a
leak-test-before-charging rule, and both set record fields a work order can carry. Alberta's
regulation is mostly a release ban and a pointer to the federal code of practice, so its policy is
three lines.

**Ontario — O. Reg. 463/10, Ozone Depleting Substances and Other Halocarbons** (consolidation from
2024-08-30, e-Laws currency 2026-10-14, last amendment O. Reg. 336/24). Scope: "refrigeration
equipment" (air conditioning, heat pump, refrigeration or freezer units, including vehicle AC) with
a class 1 or class 2 ODS or a "halocarbon" (listed HFCs and PFCs, any other HFC or PFC, and
mixtures) (s. 1).

| Event | Flag | Source |
|---|---|---|
| Any service or test | Needs an Ontario refrigerant certificate (valid 5 years), and the technician or employer must own, or have immediate contracted access to, recovery equipment. | ss. 22(1), 34 |
| Opening a circuit, or a release recorded | No discharge into the environment or within a building. A discharge of 100 kg or more is reported to the Ministry as soon as reasonably possible. | s. 19 |
| Adding | A refill needs the technician's certificate, a **no-leak notice on the equipment no more than six months old**, and no apparent damage. The flag reads the log's last leak test and its result. Filling for the purpose of testing is not allowed (vehicle AC aside). | ss. 22(2), 25(1) |
| Refill without those, for immediate danger to life or health, or to crops, animals or food at a farm or food facility | Allowed. The owner reports to the Director promptly, has the equipment leak tested and any leak repaired within 7 days, and reports the result. | s. 25(2)–(3) |
| Leak test | Follow the federal code of practice named in the regulation. Tell the owner the result. Fix a notice to the equipment with the date, name, certificate number and expiry, employer, the result, and, if it leaks, a statement that no refrigerant may be added until the leak is repaired. The notice is not removed except to replace it. | ss. 22(4)–(5), 23(3)–(6) |
| Any service or test | Record refrigerant bought for the job and its supplier; any discharge and why; date, technician and employer; and a description, with amount and type used and type and estimated amount recovered. Name the type by the regulation's own terms. The employer, or a self-employed technician, keeps it for 2 years. | s. 23(1), (2), (7) |
| Determined empty | Fix a "no refrigerant" notice: date, name, certificate number and expiry, employer, statement. Keep a copy for 2 years. | s. 32 |

**British Columbia — B.C. Reg. 387/99, Ozone Depleting Substances and Other Halocarbons Regulation**
(current to 2026-10-13, last amended by B.C. Reg. 171/2025, 2025-10-27). Scope: Class I and II ODS
and, through s. 3, "other halocarbons" (Class III, HFCs and PFCs) for most of the servicing
provisions.

| Event | Flag | Source |
|---|---|---|
| Any service | Only an "approved person" may service AC, refrigeration or vehicle AC equipment: trade credentials or an apprenticeship, plus an approved environmental awareness course. Supervised trainees are allowed. | ss. 1, 7 |
| Opening a circuit | No release unless the regulation or its codes allow it. Recovery devices must meet Schedule B. | ss. 4(1), 13 |
| Adding | Leak test before charging or recharging. Do not add to leaking equipment. Do not add refrigerant for the purpose of leak testing. | ss. 4(3), 11(1)–(2) |
| Evacuating, charging or recharging | Record on a permanent label or tag on the equipment **and** in the service log: leak test results, type and amount added or removed, whether it is now evacuated, the date, and the technician's name and registration number (and the business). The log keeps 36 months, in order, at the place of business. | s. 10(2)–(3) |
| Release recorded | More than 10 kg is reported under the Spill Reporting Regulation. | s. 28 |

Schedule B's Table 1 sets recovery vacuum levels by equipment type and charge, with 23 kg as a
break point. That is regulation text, so it can become a table like EPA Table 1. The values were
not read for this amendment, and they are read and cited when the policy is built.

**Alberta — Alta Reg 181/2000, Ozone-depleting Substances and Halocarbons Regulation** (office
consolidation current as of 2022-07-20, amendments to AR 157/2022). It covers ODS, HFCs (Schedule
3) and PFCs (Schedule 4) "where used as a refrigerant", including mixtures. Its flags: no release
(s. 2(1)); servicing follows the Environment Canada *Environmental Code of Practice for Elimination
of Fluorocarbon Emissions from Refrigeration and Air Conditioning Systems* (s. 5); and servicing
only by a person authorised under the Skilled Trades and Apprenticeship Education Act (s. 7). It
sets no leak-test notice, log fields or deadlines of its own. The code of practice is a government
publication, but this plan does not model it. It is cited by title, as the regulation cites it.

**Quebec — Regulation respecting halocarbons, CQLR c. Q-2, r. 29.** Deferred: LegisQuébec refused
automated access for this amendment, so nothing about it is modelled. It is known from official
secondary pages only: technicians need the CCQ-recognised "environmental qualification:
halocarbons". Everything else is unconfirmed.

#### `AustraliaOzoneSGGPolicy` — Ozone Protection and Synthetic Greenhouse Gas Management Act 1989 and Regulations 1995

Act: compilation C36, 2026-07-01. Regulations: compilation No. 48, 2026-07-01. Scope: "RAC
equipment", meaning equipment for cooling or heating anything that uses CFC, HCFC, HFC, PFC or halon
(reg 110). HFCs are the substances listed in clause 9 of Schedule 1 to the Act, alone or in a
mixture (Act s. 7). HFOs and hydrocarbons are not listed. The licences and authorisations are
administered by the RAC Industry Board, the Australian Refrigeration Council.

| Event | Flag | Source |
|---|---|---|
| Any work that risks a release (decanting; installing, commissioning, servicing, maintaining; decommissioning with refrigerant present) | Needs a refrigerant handling licence that covers the work. The flag compares the work with the licence type recorded in the profile. A full RAC licence covers all but automotive work. An automotive AC licence covers cabin AC. A restricted heat pump licence covers **installation and decommissioning only** of single-head splits and two-part water or pool heat pumps under 18 kW. A restricted domestic licence covers domestic appliances and commercial stand-alone equipment. Example: "A restricted heat pump licence covers installing and decommissioning this unit, not servicing it." | regs 111, 131 (Table 131) |
| Opening a circuit | No discharge of a scheduled substance where it is likely to reach the atmosphere. Use refillable containers only. Recovered refrigerant goes to a refrigerant trading authorisation holder or a destruction facility. | Act s. 45B; reg 135(1)(b)–(c) |
| Adding | **Prohibited refrigerant charging:** charging with an HFC or HCFC other than the design refrigerant on the compliance plate (or in the manual, if the plate names none) is caught when the design refrigerant is not scheduled (for example R-1234yf or R-290) or the new one has a higher 100-year GWP. It is not caught when the design refrigerant is an HCFC, when the new refrigerant's GWP is lower or equal, or when the equipment is essential for health or public safety and no alternative is available (the reason is recorded). Examples from the department's guidance: R-410A into an R-32 system is caught; R-452A into an R-404A system is not; R-427A into an R-22 system is not. | regs 2AAA, 111A, 135(1)(ba), 141(1)(ba) |
| Adding a refrigerant of a higher flammability class than the design one | A note, from the department's guidance rather than the regulation: such a change needs the system converted under the relevant codes, standards and state or territory laws, with full recovery and a leak test first. | DCCEEW charging-rules page |
| Any job | Work-order fields: the technician's licence number on invoices, receipts and quotes when they are not employed by an authorisation holder, and the business's trading authorisation number on the same documents. | regs 135(1)(e), 141(1)(o) |
| Quarter end (office) | An authorisation holder keeps quarterly records of refrigerant bought, recovered, sold and otherwise disposed of. The log's totals by quarter feed that record and do not replace it. | reg 141(1)(a) |

The Australian regulations set **no leak-test interval, leak-rate threshold or repair deadline** of
their own. A licence requires work to follow standards the department's CEO determines (reg
135(1)(a), (5)), and those incorporate licensed industry standards and codes. The policy does not
model those standards and flags no leak timelines for Australia. For the GWP comparison, the GWP of a
listed HFC is taken from the Act's Schedule 1. Blend GWPs are computed from composition. The method
is unconfirmed (see Unconfirmed).

#### `NewZealandRefrigerantPolicy` — Ozone Layer Protection Act 1996 and Regulations; HSW (Hazardous Substances) Regulations 2017

New Zealand has **no refrigerant technician licence**. The Ozone Layer Protection Act lets
regulations require accreditation (s. 11), but the Ozone Layer Protection Regulations 1996 contain
no accreditation provisions. They control imports, exports, manufacture and sale, and since 2019
they list HFCs as controlled substances (Schedule 1 Part 10). The duties that reach a technician are
few, and the policy says only these:

| Event | Flag | Source |
|---|---|---|
| Opening a circuit | Do not knowingly release a controlled substance (CFC, HCFC, HFC and the others in Schedule 1) while installing, operating, servicing, modifying or dismantling refrigeration or AC equipment: recover it. A release that could not reasonably be avoided while connecting or disconnecting transfer equipment is excused. | Act ss. 13(f), 14; Regs r. 2 and Sch. 1 Pt 10 |
| Recovering into a cylinder | Charging a gas container needs an **approved filler** certificate covering that gas class (or a trainee supervised by an approved filler). WorkSafe has said that recovery from a system into a cylinder counts. The PCBU must ensure it. | HSW(HS) Regs 15.64, 15.65, 15.66 |
| Hydrocarbon refrigerant (R-290, R-600a, R-1270) | The equipment must be designed and installed for a flammable refrigerant. WorkSafe states that the Hazardous Substances Regulations require hydrocarbon RAC equipment to comply with AS/NZS 5149 (cited by number only; domestic fridges, domestic heat pumps and room ACs fall under their appliance standard instead). | WorkSafe technical bulletin, October 2022 |
| Adding a refrigerant other than the design one | A note: WorkSafe states that under the Electricity (Safety) Regulations 2010 an installation retrofitted with a refrigerant other than its design refrigerant is deemed unsafe, and a non-flammable to flammable change makes it unsafe unless properly converted. | Same bulletin (regulation number unconfirmed) |

There is no leak-test, record-keeping or leak-repair duty on a New Zealand technician in these
instruments, so the log stays neutral there. Two things are on watch. The Climate Change Response
Act's synthetic greenhouse gas levy falls on importers, not technicians, and is not modelled.
Refrigerants have been a priority product under the Waste Minimisation Act since 2020, and
regulations for a mandatory stewardship scheme were agreed for drafting in 2024. Their status at
October 2026 is unconfirmed. A later tranche was proposed to limit recovery and decommissioning to
qualified technicians, which would add a licence-style flag when it lands.

#### Flammable refrigerants (A2L, A3) in every jurisdiction

Only legislation creates a flag. The safety class shown for a refrigerant comes from its
manufacturer's safety data sheet, cited per refrigerant, not from a licensed standard. AS/NZS 5149,
AS/NZS ISO 817, AS/NZS 60335 and CSA B52 are cited by number and title where an official source
names them, and they are never quoted or turned into thresholds. Charge limits, room-size rules and
ventilation are not computed for any jurisdiction.

#### Exit tests (P2)

- **Canada federal** (`federalSite: true`): R-410A rooftop, 25 kg on one circuit, last leak test 16
  months ago, so a test is due (s. 17). An R-410A split of 8 kg is small: no annual test, and one
  log entry per service (s. 23(2)). R-404A, 40 kg, leak found today: deadline today + 7 days
  (s. 18). Adding to a unit whose log shows an unrepaired leak gets the s. 10 flag, and the
  emergency path gets the s. 11 owner duties. An R-290 self-contained unit gets no flags. Release
  estimates of 120 kg (24 h + 30 days) and 40 kg (31 July or 31 January by detection date).
  Decommissioning lists the Part 2 notice fields. A multi-circuit system with circuits of 6 kg and
  12 kg is large.
- **Ontario** (`CA-ON`, not federal): an R-410A refill with no leak-test notice in the log, or a
  no-leak notice seven months old, gets the s. 25(1)(b) flag; a five-month-old notice gets none. A
  leak test with a leak found produces notice fields that include the "no refrigerant may be added"
  statement. An emergency refill at a farm cooler gets the s. 25(3) owner duties. R-22 is in scope
  (class 2 ODS). R-744 and R-290 are not. A vehicle AC is in scope.
- **British Columbia** (`CA-BC`): a recharge with no leak test recorded gets the s. 11(2) flag. An
  evacuation lists the s. 10(2) tag and log fields. R-290 gets no flags.
- **Alberta** (`CA-AB`): an R-410A service gets the three Alberta lines and no deadlines.
- **Canada, federal status unanswered:** the provincial policy runs and the "If this is a federal
  site" line appears once. **Quebec, other provinces and territories:** no flags.
- **Australia:** R-32 design charged with R-410A, caught. R-404A design charged with R-452A, not
  caught. R-22 design charged with R-427A, not caught. R-1234yf design charged with R-134a, caught.
  R-290 charged with R-290, no flags. The health and public safety exception recorded, not caught,
  with the reason on the work order. A restricted heat pump licence recorded against a service of a
  7 kW split gets the entitlement note; against an installation, none. A self-employed licensee
  gets the licence-number field. No leak-deadline flag for any Australian unit.
- **New Zealand:** an R-410A heat pump, opening the circuit, gets the release line and the approved
  filler line at recovery. A commercial R-290 unit gets the hydrocarbon note; a domestic R-600a
  fridge does not. An R-134a system topped up with R-600a gets the design-refrigerant note. R-744
  gets no ozone-layer flags. No leak-deadline flag for any New Zealand unit.
- **Jurisdiction unknown, or no policy (US before P2-US ships):** no flags, the calculations
  unchanged, and the log still records.
- **Units:** kPa(g) ↔ psig ↔ bar(g) ↔ kPa abs round-trips at 0 m and 1,500 m. °C ↔ °F, and K ↔ °F
  differences. kg ↔ lb/oz ↔ g with exact constants, so "4 lb 6 oz" is stored as 1984 g and shown
  as 1.98 kg. The −40 °C and −40 °F rows agree exactly. Interpolating the °C grid at 10 °C and the
  °F grid at 50 °F agree within 0.1 kPa. The same superheat in either unit set gives the same
  answer in K.
- **Wording guard** across every policy's flag text: no "violation", "illegal", "fine", "offence",
  "breach", "penalty" or "contravene". The legislation uses these words, and the flags must not.
- **Citations:** every flag carries an instrument, a section and an as-at date. A test fails if a
  policy's facts table has a row without one.

### Acceptance (added to the plan's list)

- On an Ontario site, "added 1.5 kilos of R-410A" on a unit whose last leak test notice is eight
  months old says a refill needs a no-leak notice no more than six months old. It records the
  amount in kilograms, and the technician can say it in pounds.
- In Australia, recording R-410A added to a unit whose compliance plate says R-32 says that
  charging a higher-GWP refrigerant than the design one is not allowed, and why.
- In New Zealand, opening an R-410A circuit reminds the technician to recover and that recovery into
  a cylinder needs an approved filler certificate.
- With the units set to metric, "what's my superheat?" on an R-410A system answers in K, kPa and
  °C, with the dew point and the source, and "assuming sea level" unless an altitude is known.
- A unit with no known jurisdiction gets the calculations and no regulatory flags.

### Phases

- **P0:** both grids and absolute storage (above). Otherwise unchanged.
- **P1, P4, P5:** units as above. Otherwise unchanged.
- **P2:** the neutral log, the resolver, and the Canada federal, Ontario, BC, Alberta, Australia and
  New Zealand policies. If the PR is too large, Australia and New Zealand go first (each is one
  table), then Canada.
- **P2-US (deferred):** the existing `EPA608Policy` text, unchanged, behind the same log, scheduled
  when the owner asks for the US.
- **P3, P6:** unchanged.

### Sources (official; read 2026-10-19 unless marked)

- *Federal Halocarbon Regulations, 2022*, SOR/2022-110. Justice Laws, current to 2026-09-30.
  <https://laws-lois.justice.gc.ca/eng/regulations/SOR-2022-110/FullText.html>
- *Federal Halocarbon Regulations, 2003*, SOR/2003-289. Shown as repealed by SOR/2022-110 s. 29.
  <https://laws-lois.justice.gc.ca/eng/regulations/SOR-2003-289/FullText.html>
- ECCC, *Federal Halocarbon Regulations information* (scope, and "provinces and territories regulate
  in their jurisdictions"). Seen as a search summary only.
  <https://www.canada.ca/en/environment-climate-change/services/air-pollution/issues/ozone-layer/measures-protect/federal-halocarbon-regulations-information.html>
- Ontario, *O. Reg. 463/10: Ozone Depleting Substances and Other Halocarbons*. e-Laws, consolidation
  from 2024-08-30, currency 2026-10-14, last amendment O. Reg. 336/24.
  <https://www.ontario.ca/laws/regulation/100463>
- British Columbia, *Ozone Depleting Substances and Other Halocarbons Regulation*, B.C. Reg. 387/99.
  BC Laws, current to 2026-10-13, last amended by B.C. Reg. 171/2025.
  <https://www.bclaws.gov.bc.ca/civix/document/id/complete/statreg/387_99>
- Alberta, *Ozone-depleting Substances and Halocarbons Regulation*, Alta Reg 181/2000. King's
  Printer office consolidation, current as of 2022-07-20 (to AR 157/2022).
  <https://kings-printer.alberta.ca/documents/Regs/2000_181.pdf>
- Quebec, *Regulation respecting halocarbons*, CQLR c. Q-2, r. 29. **Not read** (LegisQuébec
  returned 403). <https://www.legisquebec.gouv.qc.ca/en/document/cr/Q-2,%20r.%2029>
- Australia, *Ozone Protection and Synthetic Greenhouse Gas Management Act 1989*. Compilation C36
  (C2026C00241), 2026-07-01. <https://www.legislation.gov.au/C2004A03755/latest/text>
- Australia, *Ozone Protection and Synthetic Greenhouse Gas Management Regulations 1995*.
  Compilation No. 48 (F2026C00546), 2026-07-01.
  <https://www.legislation.gov.au/F1996B02085/latest/text>
- DCCEEW, *Rules on charging refrigeration and air conditioning equipment*, last updated
  2024-05-29.
  <https://www.dcceew.gov.au/environment/protection/ozone/rac/rules-charging-rac-equipment>
- DCCEEW, *Refrigeration and air conditioning*, last updated 2026-04-30 (ARC as the Industry Board;
  notes that a National Environmental Protection Agency was established on 2026-07-01).
  <https://www.dcceew.gov.au/environment/protection/ozone/rac>
- New Zealand, *Ozone Layer Protection Act 1996*, version as at 2021-10-28.
  <https://www.legislation.govt.nz/act/public/1996/40/en/latest/>
- New Zealand, *Ozone Layer Protection Regulations 1996* (SR 1996/222), version as at 2025-04-05.
  <https://www.legislation.govt.nz/secondary-legislation/pco-drafted/1996/222/en/latest/>
- New Zealand, *Health and Safety at Work (Hazardous Substances) Regulations 2017* (LI 2017/131),
  version as at 2026-09-23.
  <https://www.legislation.govt.nz/secondary-legislation/pco-drafted/2017/131/en/latest/>
- WorkSafe NZ, *Technical bulletin: Hydrocarbon refrigerants*, October 2022.
  <https://www.worksafe.govt.nz/dmsdocument/55344-technical-bulletin-hydrocarbon-refrigerants/latest/>

Standards and codes named above (AS/NZS 5149, AS/NZS ISO 817, AS/NZS 60335, CSA B52, and the
industry codes that the Australian CEO's standards draw on) are cited by number and title only.

### Unconfirmed

- Whether pure HFOs (R-1234yf, R-1234ze(E)) are "Hydrofluorocarbons (HFC)" under the Canadian
  federal Schedule 1, which names the class without a list. Ontario's "any hydrofluorocarbon"
  wording raises the same question. Until it is settled, the Canadian policies treat a pure HFO as
  out of scope and say so.
- Quebec's regulation, in full: leak detection, logs, any thresholds.
- BC Schedule B Table 1 vacuum values (regulation text, not yet read).
- What units Canadian technicians use day to day (open question 7).
- How Ontario wants a blend named in records (s. 23(2) points at single-substance terms; R-410A is a
  mixture of HFC-32 and HFC-125).
- Australia: the title and contents of the CEO's standards determination under reg 135(5); the
  method for a blend's GWP under reg 2AAA(5) (the department publishes a GWP list, not read); the
  effect, if any, of the new National Environmental Protection Agency on who administers the scheme;
  and state and territory rules for hydrocarbon refrigerant work (not modelled).
- New Zealand: WorkSafe's position that recovery into a cylinder needs an approved filler (seen in
  a summary of a 2017 submissions report, not read in full); the Electricity (Safety) Regulations
  2010 provision behind the retrofit statement; whether A2L refrigerants are treated like
  hydrocarbons under the Hazardous Substances Regulations; the status at October 2026 of the
  refrigerant product stewardship regulations; and whether s. 13(f)'s "controlled substance"
  reaches a blend inside equipment (assumed yes: blends of listed HFCs).
