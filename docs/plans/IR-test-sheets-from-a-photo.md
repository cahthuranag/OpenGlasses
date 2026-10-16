# Plan IR — Test Sheets From a Photo (an electrician's handwritten results become checked, structured readings)

**Status:** 📝 Drafted 2026-10-17 — nothing implemented.
**Track:** Field Assist (B2B), the electrical vertical beside Plan IN.
**Related:** Plan [IN](IN-verifiable-code-lookup.md) (codes and standards with clause citations,
where limits come from), Plan [IO](IO-sealed-proof-of-work-photos.md) (sealed photos, so the sheet
photo is proof as well), Plan [structured vision](structured-vision-assessment.md) (AD:
`instrument_reading`, `UnitNormalizer`), Plan [U](U-structured-capture-flows.md) (capture flows and
their bindings), Plan [GB](GB-field-test-round-3.md) P3 (`SpokenReading` and its corrections),
Plan [EF](EF-scanned-manual-import.md) (on-device page recognition), Plan
[IP](IP-organisation-feature-switches.md) (the organisation switches it on).
**Origin:** The October 2026 competitor review. A New Zealand electrical-certification app turns a
photo of handwritten test results into its test sheet, takes the job description by voice, and
points to the relevant clause of the wiring rules. Electricians write test results on paper because
meters and gloves don't mix with phones. Typing them up afterwards is the chore. The results also
feed the job record, the certificate, and the proof that the work was tested.

---

## Outcome

The electrician photographs the page of results they wrote at the board, or a meter's display.
The phone reads it on the device and builds one row per circuit and test: circuit, test,
value, unit, and the test voltage or current. The electrician hears each row read back and
confirms or corrects it. Each value is checked against the limits the organisation's own vault
states, with the clause cited. The results go into the job record, the work-order PDF and a
spreadsheet export for certificate software. Nothing is called compliant unless it was checked
against a limit someone loaded.

## Verified starting point (`main` @ `0606aeabb`, 2026-10-17)

- **No electrical test types exist.** A repo-wide search for insulation resistance, earth loop,
  Zs, RCD, polarity, megger and continuity finds only the spoken expansion of "MΩ"
  (`SpokenSymbolExpander`). There is no Ω, MΩ, ms, mA or kA normalisation, no loop-impedance or
  trip-time schema, and no electrical vault or capture flow.
- **Readings exist in two forms.** `instrument_reading` (`vision_assess`, Plan AD) returns
  quantity, instrument, value, unit as displayed, confidence and a region, normalised by
  `UnitNormalizer` (temperature, pressure, mass, Brix, volts). Low confidence asks for a
  re-capture, and a reading can fill the current capture-flow step. `SpokenReading` (`reading`
  tool) stores free-text quantity, value and unit, normalising only °F and °C. Corrections
  supersede the original, and readings are tagged to unit and task.
- **Capture flows have the right bindings but no table.** Bindings are `voice`, `voice_number`
  (with unit and range), `enum`, `barcode_or_voice`, `photo` and `ocr_text`. The PDF prints
  "Captured Records" with each field's method.
- **On-device text recognition, not tables.** `OCRService`, `DocumentScanTool` and `BadgeScanTool`
  use `VNRecognizeTextRequest` at `.accurate`. Nothing sets a handwriting option, and
  `DocumentScanTool` returns reading-order text sorted by bounding box. Nothing turns a page into
  rows and columns.
- **Photos are filtered and kept** (`JobPhotoEvidenceService`, `filteredStill`). A sheet photo
  joins the job like any other.

## Decisions proposed (owner to confirm)

1. **Every value traces to the page.** A row's value, unit and circuit each carry the bounding box
   of the text they came from, and the review shows that crop beside the row. A value the
   recogniser did not read is empty, never inferred, and is asked for by voice.
2. **The electrician confirms every row, by voice or on screen.** Read back in groups: "Circuit 3,
   insulation 200 megohms at 500 volts, continuity 0.4 ohms. Right?" Corrections supersede, as
   `SpokenReading` does, and the original stays in the record.
3. **Limits come from the vault, never from the model.** An electrical vault may carry a limits
   table (`limits/*.json`: test, conditions such as circuit type, protective device and test
   voltage, the threshold, and the clause it comes from). A row is marked within or outside the
   limit only against that table, with the clause cited. With no table, results are recorded and
   no judgement is shown. The table is the organisation's own, written from the standard it holds
   (Plan IN decision 6). We ship a template with no thresholds filled in.
4. **On-device recognition first, the model only for structure.** Vision reads the page on the
   phone. The model, given the recognised words and their positions (never the photo, when the
   organisation sets the privacy filter to block it), proposes the row structure through a forced
   schema. Validation drops anything that doesn't map back to a recognised word. Offline, the pure
   grid parser alone is used and the electrician confirms more.
5. **A test sheet is a capture-flow binding, not a new subsystem.** A `test_sheet` binding fills a
   repeating group of rows, so an organisation's own test flow (per circuit, per board) is
   authored like any other flow (Plan U's author view).

## Phases (one PR each)

### P0 — Electrical test types and units (pure)

- `ElectricalTest` (`insulationResistance`, `continuity`, `earthLoopImpedance`,
  `prospectiveFaultCurrent`, `rcdTripTime`, `polarity`, `earthElectrodeResistance`, plus `custom`
  with a unit) and the conditions each carries: test voltage for insulation resistance, the test
  current multiple for an RCD, and the circuit and protective device.
- `UnitNormalizer` learns Ω, kΩ, MΩ, GΩ (and "meg", "megs", "M" in context), ms, mA, A, kA and V,
  and the conventions technicians write: ">200", "∞" or "OL" (over range), "<0.01", and "pass" or
  "✓" for polarity.
- `TestLimitTable` (the vault's `limits/*.json`) and `TestLimitCheck` (pure: row plus table gives
  `within(clause)`, `outside(clause, by)` or `noLimitLoaded`).
- **Exit tests:** the normaliser on a corpus of written forms (">999MΩ", "OL", "0.36Ω", "28ms",
  "pass"); the limit check across conditions; a table missing its clause is rejected at import.

### P1 — Rows from a photo (headless, with fixtures)

- `TestSheetGridParser` (pure): from Vision's text observations with their boxes, it clusters
  lines into rows and columns, finds header cells (circuit, R1+R2, IR, Zs, RCD, and the
  organisation's own column names from the flow), and emits candidate rows with the source box for
  every cell.
- `TestSheetStructurer`: the forced-schema model pass over the recognised words and positions
  (decision 4), validated against the grid parser's cells. Unmapped values are dropped.
- Recognition setting: `.accurate` with language correction off for numeric columns, and automatic
  language detection off. The handwriting rate on real sheets is P1's owed device measurement.
- **Exit tests:** fixture images of printed and handwritten sheets and a meter display, with known
  rows. The parser alone is checked to an exact cell match on the printed fixture. Structurer
  output never contains a value without a source box. A page that isn't a test sheet yields "not a
  test sheet", not empty rows.

### P2 — Review and correction, by voice and on screen

- The review screen: each row with its crop, its limit result and clause, and an edit field. Voice
  read-back groups rows by circuit (decision 2). "Circuit 4 should be 1.2 ohms" supersedes. "Skip
  circuit 6, not tested" records it as not tested.
- `test_sheet` capture-flow binding (decision 5) and a starter flow, "Board test", in the electrical
  vault template.
- Glasses: when the glasses' camera is connected, the same capture works from the glasses' still
  (filtered), and the read-back is spoken.
- **Exit tests:** the review state machine; supersession history; the flow binding fills a
  repeating group; the IP switch hides the binding, the review and the tool when off.

### P3 — The record, the report, and the export

- Test results in `WorkRecord` (rows, limit results with clauses, corrections, the sheet photo's id
  and, under IO, its seal). A "Test results" table in the work-order PDF, with a limit column only
  where a table was loaded. A `.xlsx` export with one row per circuit and test (the van stock
  plan's writer, text-typed cells), for certificate software to import.
- The customer summary (Plan IQ) gains one line, "Electrical tests recorded: n circuits", never the
  values or judgements, unless the organisation turns that on.
- **Exit tests:** PDF snapshot, export round trip, no limit column without a table.

### P4 — Certificate fields (owner decides which)

- Map the recorded results onto one certificate's fields: the New Zealand certificate of compliance
  and electrical safety certificate, an Australian state certificate, or a Canadian or US
  inspection form. This is either an export the certificate software imports, or a partnership with
  a certification app (decision owed). No certificate is issued by this app. The electrician
  issues it in whatever their regulator accepts.

## Acceptance

- An electrician photographs a handwritten sheet of eight circuits. Every value is either read
  correctly, or empty and asked for. Nothing appears that isn't on the page.
- With the organisation's limits table loaded, a 0.8 MΩ insulation result is shown outside the
  limit with its clause. Without the table, the same result is recorded with no judgement.
- The work-order PDF shows the results, and the spreadsheet opens in a certificate tool with
  circuit numbers intact.

## Open questions for the owner

1. Which market's sheet layout first? New Zealand and Australia (AS/NZS 3000 and 3017, where the
   Auckland interest is) or the partner's North American electrician? It decides the P1 fixtures and
   the P4 certificate.
2. Decision 4: should the model ever see the sheet photo itself (better on messy handwriting), or
   only the recognised words?
3. P4: export only, or approach a certification app about an integration?
