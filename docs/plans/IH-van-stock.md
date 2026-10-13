# Plan IH — Van Stock (what is on the technician's own truck, kept by voice)

**Status:** 📝 Drafted 2026-10-13 — nothing implemented. A technician tells the assistant what
they loaded at the shop and what they used on a job; the phone keeps the count, answers "have I
got one?" with no signal, says when the last one has gone, and offers to ask the office for a
replacement. The count lives on the phone and nowhere else. A spreadsheet goes out and comes back
in for bulk loading and hand corrections. Company-wide stock is not in this plan.
**Track:** Field Assist (B2B).
**Depends on:** Plan [EM](EM-work-record-and-parts.md) P1 (shipped: `PartsVerifier`,
`VaultPartsIndex`, `parts_request`, the work record). Nothing here waits on the office connection.
**Related:** Plan [HF](HF-office-stock-and-capture-contracts.md) (the firm's stock in Avenkin
Office; this plan is the van end of it, built so HF can take it over), Plan
[FO](FO-guided-job-flow-and-job-tab.md) (the Job tab and its to-dos), Plan
[GE](GE-automatic-offline-handoff.md) (offline tool classification), Plan
[CT](CT-org-configuration-profiles.md) (an organisation can pin the feature off), Plan
[IA](IA-agent-choice-questions.md) (answering "which one?" from the glasses), Plan
[BT](BT-reading-companion.md) (the read-only ZIP reader this plan reuses).
**Origin:** A partner's field experience, 2026-10-13: a technician uses a part, forgets to record
it, and arrives at the next job without one. The ask was the smallest thing that fixes that — the
technician's own truck, by voice, in a file they can open and correct — tested alone before
anything company-wide.

---

## Decisions proposed (owner to confirm)

1. **The store is a movement log; the spreadsheet is a view of it.** The phone keeps an
   append-only list of movements and derives every level from it. The spreadsheet is exported
   from the log and an edited one comes back as corrections. A file that is the store cannot be
   undone, cannot say when a figure was last true, and is corrupted by being open in another app
   while the phone writes it.
2. **A real `.xlsx`, never CSV.** A spreadsheet program opening a CSV drops leading zeros and
   turns a number such as `14E65` into scientific notation. Part numbers are written as text
   cells in a text-formatted column.
3. **Stock is not tied to a job.** Loading happens at the shop with no job open. The tool needs
   Field Assist switched on and nothing else; a use is tagged to the open job when there is one.
4. **Most van stock is in no manual.** Capacitors, contactors, fuses and fittings are universal.
   The vault check (`PartsVerifier`) still runs and its result is recorded, but an unverified
   number is never refused, and an item may have a description and no number at all.
5. **Write, read back, and let the technician undo.** A load or a use is recorded at once and
   read back in the same breath. "Undo that" reverses the whole spoken batch. A confirm-before-
   write step would double every turn while somebody's hands are full of boxes.
6. **Ordered and on the van are different facts.** Asking the office for a replacement opens an
   order; only the technician saying they loaded it adds stock. Until then the answer is "none on
   the van, one asked for on Tuesday".
7. **Nothing is ordered unattended.** A low count is spoken and a request is offered. The
   technician says yes. Anything that would act without them is gated behind `agentModeEnabled`
   and is out of this plan.
8. **One phone, one van.** A shared truck, a second technician's phone and stock moving between
   vans belong to HF.

## Product promise

- *"Check my truck for a 45/5 capacitor."* — *"Two on the van, counted on Monday."*
- *"Record that I used one, and ask the office for a replacement."* — *"One left. I've asked the
  office for one; it goes with the job report."*
- At the shop: *"I've loaded four flame sensors, part 62-23543-01, and six 45/5 capacitors."* —
  the assistant reads both lines back, and spells out any number it has not met before.
- At the end of a job: *"The igniter on this job has no stock entry. Did it come off the van?"*
- An unknown is spoken as unknown. A count the log cannot stand behind is said to be unreliable
  until somebody counts; an invented figure is never spoken.
- It all works in a basement. Nothing in this plan touches the network.

## Verified starting point (`9a613d51`, 2026-10-13)

- **Part numbers are already checked.** `Services/FieldAssist/PartsVerifier.swift` turns a spoken
  number into a `TaskPart` (`number`, `partDescription`, `verified`, `page`): the vault's parts
  table first (`VaultPartsIndex.part(number:)`, which also resolves a superseded number to its
  replacement), then the manuals as an exact token. `VaultPartsIndex.normalise` strips the
  punctuation a transcribed number picks up.
- **Requests to base exist.** `NativeTools/PartsRequestTool.swift` (`parts_request`) records a
  `PartsRequest` (`quantity`, `urgency`, `onVan`, `status` `requested`/`sent`/`answered`,
  `baseAnswer`) on the active session. It refuses without one. `on_van` already means "the
  technician has one and this is a replacement for stock". The request leaves with the job report
  by the organisation's channel (`DeliverySettings`: email, messages, WhatsApp, Telegram or an
  endpoint) or through the office connection.
- **"Used" has no quantity.** `WorkRecord.partsUsed` is the parts on tasks that ended `done`,
  de-duplicated by number. `TaskPart` carries no quantity, and a part on a task did not
  necessarily come off the van. `propose_task` is what attaches parts to a task.
- **Codes can be scanned.** `BarcodeScannerTool` (`scan_code`) decodes QR and the common retail
  and industrial symbologies on device from a filtered still, and returns the text.
- **Archives can be read, not written.** `ZipArchiveReader` (`Services/Reading/
  BookFileExtractor.swift`) is a strict read-only ZIP parser with stored and deflate decoding,
  already reused by `OfficeManualImport`. There is no ZIP writer and no spreadsheet code. No
  package would need adding: `XMLParser` and the system zlib cover the rest.
- **The app's files are not in Files.** `Info.plist` declares three document types the app
  receives as a copy (`LSSupportsOpeningDocumentsInPlace` is `NO`); `UIFileSharingEnabled` is
  not set. `ShareSheet` and file importers are used across the app.
- **Enforced registers a new tool and a new store must join.** `OfflineToolPolicy` (every tool
  is `local`, `degraded` or `needsNetwork`), `ToolEffectClassification` (checked against the live
  registry by `ToolEffectClassificationTests`), and `SensitiveStore` in `DataStoreRegistry`
  (checked by a source scrape in `DataStoreRegistryTests`).
- **The Job tab has to-dos.** `JobDay.Todo.Kind` lists `debrief`, the report states, `signOff`,
  `parts`, and the recording kinds; `JobNeedsSection` shows them.
- **HF is drafted and unbuilt.** Its stock snapshot already has a location class `van` and a flag
  for the phone's own van, movement kinds as a closed list, and provenance on every figure.

## Design

### 1 · Items and movements

An **item** is one line of stock: a stable `itemID`, an optional part `number` (normalised with
`VaultPartsIndex.normalise`), a `description`, a `unit`, an optional `minimum`, an optional `bin`
(a short label such as "left shelf 2"), zero or more scanned `codes`, and whether the number was
`verified` against the vault when it was last checked. The identifier is separate from the part
number, as HF requires, because a number can be corrected and an item can have none.

A **movement** is one dated fact about one item. The kinds are a closed list:

| Kind | Effect on the level | Carries |
|---|---|---|
| `loaded` | + quantity | — |
| `used` | − quantity | the job session and job reference, when a job is open |
| `removed` | − quantity | a reason from a closed list: `returned`, `damaged`, `lent`, `other` |
| `counted` | sets the level | — |
| `ordered` | none | the `PartsRequest` id; closed by later loads, oldest first |
| `edited` | none | which attribute changed (number, description, unit, minimum, bin) |
| `reversed` | undoes one earlier movement | that movement's id |

Every movement has an id, a time, a `batch` id (one spoken sentence or one imported sheet is one
batch), and a `source`: `spoken`, `typed`, `scanned` or `sheet`. Movements carry no free text, so
the log holds part data and job references and nothing about a person.

**Levels are a fold.** `VanStockLedger` (pure) reduces the movements to, per item: `onHand`,
`onOrder`, `provenance` — `counted` when nothing has moved since the last count, `inferred`
otherwise — and `asOf`, the time of the last movement that changed the level. These are HF's
words for the same things.

**A use the log cannot cover.** The technician is holding the part, so the use is always
recorded. If the log said none, the level stays at zero, the item is marked **unreliable**, and
every answer about it says so until a count clears it: *"I've recorded it. The log said you had
none, so I can't tell you how many are left — count them when you can."*

**Units.** A closed list, whole quantities only: `each`, `m`, `ft`, `kg`, `lb`, `l`, `pack`.
Refrigerant weighed to a fraction is out of scope (Open question 1).

### 2 · Finding the item somebody means

`VanStockMatcher` (pure) takes what was said and the current items and returns one item, several
candidates, or none. In order:

1. a scanned code already attached to an item;
2. the normalised part number, exactly;
3. the vault's supersession, both ways, so the number printed on the old component finds the
   stock of its replacement;
4. description tokens — "45/5 capacitor" against "Capacitor, dual run, 45/5 µF 440 V".

Several candidates go back to the model as a short list to ask about; it never picks one. **Only
a load or a count may create an item.** A use, a removal or a check that matches nothing says so
and changes nothing, which is what stops a misheard number quietly becoming a new line with
minus one in it.

Deducting is the easy direction: the reference only has to match one of the lines on this van.
Loading is the hard one, because any number can be said. So a number that is neither verified
against the vault nor already on the van is read back character by character
(`SpokenPartNumber`: "six two, dash, two three five four three, dash, zero one") with the
invitation to undo.

**Scanning.** The model may call `scan_code` and pass the result as the reference with source
`scanned`. A printed barcode is usually a retail code, not the part number, so the first time a
code matches nothing the technician is asked what it is, and the code is remembered against that
item. The second box scans straight in.

### 3 · The `van_stock` tool

One native tool, registered with the other Field Assist tools when `Config.fieldAssistActive`.
It does not require an active session. Its description names both "van" and "truck".

| `action` | What it does |
|---|---|
| `check` | One item's level, on-order figure, provenance and age; or candidates; or "not on the van" |
| `low` | Items at or below their minimum, and items at zero with no minimum set |
| `load` | One or more lines of `part`/`description`, `quantity`, `unit` |
| `use` | The same shape; tagged to the active job when there is one |
| `remove` | The same shape, with a reason |
| `count` | Sets one or more levels: a stocktake |
| `undo` | Reverses the most recent batch, once |

Rules, each a test:

- **Every answer about a level states how it is known**: counted or worked out, and as of when.
  An unreliable item is said to be unreliable before any figure.
- **A write returns the read-back the model must speak**: what was recorded, the level now, and
  for a use whether the item has reached its minimum or zero.
- **At zero or at minimum the result offers a request and stops.** It does not call
  `parts_request`; the model asks the technician.
- **No store, no guess.** With nothing ever loaded the tool says the van list is empty and how to
  start one. It gives the model no route to answer from memory.
- **A repeated identical write inside a few seconds is one write.** Models retry; a retry must
  not load four sensors twice.

Classification: `OfflineToolPolicy` `local`; `ToolEffectClassification` `.local()`, since the
strongest action writes on-device state. The existing `parts_request` gains one seam: a request
made with `on_van` set, or made on the back of a `van_stock` offer, writes an `ordered` movement
so the van knows something is coming. A request for a part that will be fitted rather than
stocked does not.

### 4 · The store

`VanStockStore` keeps the movements and the items in the app's Application Support directory,
written atomically, with complete file protection. It joins `SensitiveStore` as `vanStock`:
business data, the technician's own working record, **left in the device backup** so a new phone
still knows what is on the truck, and outside the subject-erasure walk because it holds no
personal data — which the no-free-text rule in §1 is there to keep true.

Movements older than a retention window (proposed 400 days; Open question 5) are folded into
one opening balance per item, so levels stay exact while the history stays short.

### 5 · The Van Stock screen

Reached from the Job tab. A searchable list — description, number, on hand, on order, a mark for
low, unreliable and unverified — with a detail view per item: a number field and stepper to set
the count (a `counted` movement), the editable attributes, and the item's history. A toolbar
carries Export, Import and Undo.

This screen, not the spreadsheet, is the ordinary way to fix one wrong figure on the phone.
Every state it shows is also spoken by the tool; it passes the accessibility audit at the largest
text size, and none of it is a paid extra beyond the organisation's Field Assist licence.

An organisation may pin the feature off with one CT ceiling key. Like every ceiling it only
subtracts.

### 6 · The spreadsheet, out and back

**Why it earns its place.** A working truck already holds a couple of hundred lines. Nobody will
dictate them. The first thing a pilot needs is to load the list the shop already has, and the
second is a way to fix twenty figures at a desk.

**Out.** `VanStockSheetExport` builds a workbook with two sheets through `XLSXWriter` (pure; a
stored, uncompressed ZIP with CRC-32 from the system zlib, and the handful of XML parts a
workbook needs):

- **Van stock** — Part number, Description, Unit, On hand, Minimum, Bin, Last changed, and a
  hidden Item ID column. Part number and Bin are text-formatted columns, so a number typed into
  a new row stays as typed.
- **History** — the movements, newest first. Read-only in spirit: import ignores it.

The workbook records when it was exported and the last movement it includes. It leaves through
the share sheet, to wherever the technician sends it.

**Back.** The app registers as a viewer for `.xlsx` and takes the file as a copy, exactly as it
takes a job file, or through a file importer on the screen. `XLSXReader` (pure, over
`ZipArchiveReader` and `XMLParser`) reads shared, inline and formula-string cells and cached
numeric values. `VanStockSheetImport` (pure) turns the sheet into a **proposal**:

- a changed On hand becomes a `counted` movement;
- a new row becomes a new item and a `counted` movement;
- changed attributes become `edited` movements;
- **a missing row changes nothing** and is listed as missing — sorting, filtering and an
  accidental delete must not zero the van; zero is typed as zero;
- a line that also moved on the phone after the export is shown with both figures, and the
  technician chooses; the sheet's figure is the default.

Nothing is applied until the technician has seen the summary ("7 counts changed, 2 new items,
1 needs a choice") and tapped once. The whole import is one batch, so one undo takes it back.

**A sheet we did not write.** A first import has no Item ID column. Columns are found by header,
from a short list of synonyms (part / part number / item; description; qty / quantity / on
hand; unit; min / minimum; bin / location). A sheet with no recognisable header is refused with a
sentence naming the headers it needs.

**Refused outright:** a macro workbook, an encrypted workbook, more than 5,000 rows, a file over
2 MiB or one that inflates past 16 MiB, and — per line, with the reason — a quantity that is
negative, fractional or not a number.

### 7 · The end of the job, and the record

This is the part that fixes the complaint the plan started from.

`VanStockReconciler` (pure) compares the parts on the job's finished tasks (`partsUsed`) with the
`used` movements tagged to that job, and returns the parts that have no stock entry. They become
one Job-tab to-do, and one question when the job is being closed: *"Two parts on this job have no
stock entry: the igniter and the pressure switch. Did they come off the van?"* Yes records the
use, asking the quantity; "no, it was ordered in" or "the customer's" dismisses that part for
this job. It never deducts by itself, because a part on a task is not proof of where it came
from.

The work record gains an optional `van_stock` block: what came off the van on this job, with
quantities, units and whether each number was verified. Nil, and absent from the JSON, on a job
that used nothing — the pattern `usage` and `teamLearnings` already follow. This is the quantity
HF's mapping from the record to "issued to job" is missing today.

### 8 · When the office keeps stock too

When HF is built, the office's snapshot may also carry a figure for this phone's own van. The
phone's ledger is the fresher of the two for its own van and answers for it; the snapshot answers
for base and for everybody else. The ledger's movements are already in HF's vocabulary, so a
van's history can go to the office as capture proposals without being reshaped. Neither is built
here.

### 9 · Honest limits

- The count is only as good as what the technician says. The plan makes saying it cheap, makes a
  mistake cheap to undo, and asks at the end of the job; it cannot see the shelf.
- A spoken part number in a noisy shop is the weakest link. Read-back, the van's own list as the
  vocabulary, and the barcode are the three mitigations; how well they hold is a device check.
- The spreadsheet round trip depends on the technician's spreadsheet app saving a workbook the
  reader accepts. Which apps do, on which devices, is a check owed before the pilot.
- The spoken number reaches whichever model the conversation uses. Under the medical local-only
  mode that model is on device; nothing in this plan adds an egress of its own.
- One phone knows one van. A technician who changes phones without a backup re-imports the last
  export.

## Build order (one PR each)

**P0 — Ledger, matcher and sentences (pure).** `VanStockItem`, `VanStockMovement`,
`VanStockLedger`, `VanStockMatcher`, `VanStockAnswerComposer` (injected clock, localised strings),
`SpokenPartNumber`. No store, no tool, no UI.
*Owed:* nothing.

**P1 — Store and `van_stock`.** `VanStockStore`, the `SensitiveStore` case, `VanStockService`,
`VanStockTool`, its `OfflineToolPolicy` and `ToolEffectClassification` rows, registration, the
`parts_request` seam, scanned-code aliases.
*Owed (device):* ten parts loaded by voice in a noisy room, through the glasses and through the
phone; a check and a use in aeroplane mode; the same in a live session.
**The three-line voice workflow is testable with a partner after this phase**, on an empty van.

**P2 — The Van Stock screen.** List, detail, correction, history, undo, the CT ceiling key, the
accessibility audit entry.
*Owed (device):* VoiceOver and largest text size on the list and the detail.

**P3 — Spreadsheet out and back.** `XLSXWriter`, `XLSXReader`, `VanStockSheetExport`,
`VanStockSheetImport`, the review sheet, the document type.
*Owed (hand):* a file saved by each spreadsheet app a pilot technician actually uses, on the
phone and on a desktop, added to the fixtures. **A real truck can be loaded after this phase.**

**P4 — Job close and the record.** `VanStockReconciler`, the to-do kind, the close-out question,
the `van_stock` block on the work record, the low-stock line in the day view.
*Owed:* the office accepting a report whose record carries the new block; one uncoached job.

## Tests

- `VanStockLedgerTests` — every kind's effect; a reversal undoes exactly one movement and cannot
  be reversed twice; provenance flips to inferred on the first movement after a count; a use past
  zero marks the item unreliable and a count clears it; orders close oldest first; folding old
  movements leaves every level unchanged.
- `VanStockMatcherTests` — exact number; supersession both ways; code alias; description tokens;
  several candidates are returned, never chosen; only load and count create.
- `VanStockAnswerComposerTests` — the age is always present; unreliable is said before a figure;
  an unknown is never a number; on-order wording; minimum and zero wording.
- `SpokenPartNumberTests` — digits, letters, dashes and slashes.
- `VanStockStoreTests` — atomic write, protection class, survival of a relaunch, a torn file
  refused rather than half-read.
- `VanStockToolTests` — no active session is fine; Field Assist off is refused; empty van; the
  read-back; the duplicate-write guard; undo; an offer at zero that orders nothing.
- `PartsRequestToolTests` update — the `ordered` movement is written for a stock replacement and
  not for a part to be fitted.
- `OfflineToolPolicyTests`, `ToolEffectClassificationTests`, `DataStoreRegistryTests` updates.
- `XLSXWriterTests` and `XLSXReaderTests` — round trip; a part number with leading zeros and one
  shaped like an exponent survive; shared, inline and formula-string cells; each refusal.
- `VanStockSheetImportTests` — each proposal kind; a missing row changes nothing; the conflict
  case; a foreign sheet matched by header; an unrecognised header refused.
- `VanStockReconcilerTests` — a part on a finished task with no movement is listed; one with a
  movement is not; a dismissed part stays dismissed for that job only.
- `WorkRecordTests` update — the block is absent when empty, so an older record encodes as it did.

## Non-goals

- The firm's stock, base stock, stock on other vans, and transfers between them (HF).
- Ordering from a supplier, prices, and anything that spends money.
- Requests sent without the technician saying so.
- Fractional quantities and unit conversion.
- Exposing the app's documents folder in Files, or editing a workbook in place.
- A column-mapping screen for arbitrary spreadsheets.
- Counting stock from a photo of a shelf.

## Open questions

1. **Units.** Is whole-number `each`/length/weight enough for the pilot, or is refrigerant by
   weight needed from the first day? Fractions change the quantity type everywhere, HF included.
2. **The word.** "Truck" in North America, "van" here. Proposed: the tool understands both and
   the screen title follows the region's English.
3. **Where corrections happen.** If pilot technicians correct on the phone, P2 is enough for them
   and P3 is only for the first load. If they correct at a desk, P3 moves ahead of P2.
4. **Barcodes.** Do the shop's parts carry them? If not, the alias work in P1 can wait.
5. **How long the history is kept** before it is folded into an opening balance.
6. **When to ask about an unrecorded part:** only when the job is closed (proposed), or as soon
   as its task is finished.
7. **Minimums.** Wanted from the first day, or is "that was your last one" enough?
8. **The office.** Whether its report intake already tolerates an unknown block on the work
   record, or needs a change before P4 ships.
