# Plan JN — Pictured Tables (a table printed as a picture, read on the phone, and said to be)

**Status:** 📝 Drafted 2026-10-21 — nothing implemented. Four owner decisions confirmed the same
day (see "Owner decisions"). Takes up Plan JJ's open question 3 (tables
with no text layer) and the gap Plan IF leaves: IF recognises a photographed page's text, not its
grid.
**Track:** Field Assist first (the partner's code book), app-wide underneath: any vault PDF, any
photographed manual. **Phone first:** the partner's owner sets all of it up and checks the
tables on the phone, with no office. An organisation with the office can also check tables
there, as an addition and never a prerequisite. Recognition is on device and no page image leaves
the phone.
**Related:** Plan [JJ](JJ-table-lookup-and-rule-chains.md) (`TableExtractor`, `PDFTableReader`,
`ManualTable`, `table_lookup`, `rule_chain`, the cell key and `Scripts/table-lookup-eval/`),
Plan [IF](IF-photographed-manuals.md) (captured pages, their recognition, redaction before
persistence, erasure linkage), Plan [EF](EF-scanned-manual-import.md) (`ScannedPageReader`, the
recognition checkpoint, the confidence floor), Plan [IN](IN-code-lookup.md) (printed page labels),
Plan [IV](IV-retrieval-quality.md) (the retrieval key; nothing here may cost it a question),
Plan [DM](DM-privacy-safe-production-logging.md) (counts only, no cell text in a log).

---

## Why

JJ P5 left the partner's book with 25 table lookups that cannot resolve. 24 of them sit on two
tables printed as pictures, 19 on one of them. The caption is text and the grid under it is not.
`PDFTableReader` reports that honestly as `no_text_in_table`, and `table_lookup` says the table is
on page N and offers to show it. That is correct, and it means the chains built on those tables
(cable sizing among them) stop at the step that needs them on every run.

What the code does today, read on 2026-10-21 against build 554:

- **The table reader works on a text layer only.** `PDFTableReader.positionedWords(on:)` reads
  word boxes from `PDFPage.selection(for:)`. A picture gives none, so the caption reads and the
  grid does not (`TableExtractor.Failure.noTextInTable`). A page with no text layer at all is
  skipped before captions are looked for (`pagesWithoutText`), so a wholly scanned book has no
  tables, not even unread ones.
- **Recognition exists, and it yields lines, not a grid.** EF's `VisionScannedPageReader` and IF's
  `CapturedManualMedia.recognize` both run `VNRecognizeTextRequest` and keep text plus a mean
  confidence. `OCRService` keeps per-line boxes. None keeps per-word boxes, and all three set
  `usesLanguageCorrection = true`, which turns "5O" into "50" or "SO" by a dictionary's rules.
  That is the wrong behaviour for a cell.
- **The SDK now reads tables.** `RecognizeDocumentsRequest` (Vision, iOS 26, the app's floor) returns a `DocumentObservation` whose containers carry `tables`. Each table carries
  `rows` and `columns` of cells, each cell with its `rowRange` and `columnRange` (so a spanned
  heading is a range, not a guess) and its content as text with `lines` and `words`
  (`RecognizedTextObservation`, each with candidates and confidence). Its text options include
  `useLanguageCorrection` and `customWords`. Nothing in the app uses it yet.

So the pieces are there: a page image (PDFKit renders one, IF already holds one), two
recognisers, and a pure extractor that already reads a grid from positioned words "on a page set
in one weight". What is missing is the bridge, and saying to the technician that a value came from
a picture.

## Principles

1. **A value read from a picture says so, every time.** A recognised table carries its source,
   and every cell it gives carries it on. `table_lookup` says "read from a picture of the table on
   page N" and offers the page. A chain whose read-back used one marks that step. Nothing
   recognised is presented as if the PDF had printed it as text.
2. **An uncertain cell is not given.** A cell below the confidence floor, or one that reads
   differently on two passes, or a confusable glyph in a numeric column, comes back as the page to
   show, the same outcome as an unread table. A wrong cable size is worse than a page reference.
3. **The extractor's rules do not relax for pictures.** A recognised grid must pass the same
   structural tests as a text one: three rows, agreeing columns, the merged-cell tolerance. A
   picture that does not make a table stays `no_text_in_table`.
4. **Text first, recognition only where text failed.** Recognition runs for a caption that came
   out `no_text_in_table`, and for a scanned page whose recognised text names a table. It never
   re-reads a table the text layer gave. Chunk text and stored passages do not change.
5. **Phone first, office as well.** Both recognisers are Apple Vision, on the phone, and no page
   image leaves it. Everything (import, recognition, checking, correcting, sharing the checks) can
   be done on the phone by whoever manages the vault, with no office. The office can do the same
   check against its own copy of the PDF, and its result reaches the phone through the vault like
   any other vault file. No phase waits for the office.
6. **Measured, not assumed.** Which recogniser feeds the grid, the floor, and whether the two
   tables read at all are settled on the private book with the cell key, in counts only, before
   anything is switched on by default.

## P0 — A recognised page as words and as a grid (headless core)

- **`RecognisedPage` (pure input).** A page's recognition in page space: words with top-down
  boxes, per-word confidence and the candidate strings Vision offered, plus any tables the
  document request returned as cells with row and column ranges. It is built by two thin adapters
  (P1) and constructed directly in tests, so every rule here runs without Vision or a PDF.
- **Region and coordinates.** `PictureRegion.below(caption:words:pageBounds:)` gives the
  rectangle to recognise: from under the caption and title to the next text line, or the footer
  band (`PrintedPageBand`), whichever comes first. The mapping from Vision's normalised,
  bottom-left boxes in the cropped image to the page's top-down points is one pure function,
  tested at several crops and render scales.
- **Reader A: words into the existing extractor.** `RecognisedWords.positioned(_:)` turns words
  into `[PositionedWord]`. The size comes from box height and `bold` is false, which routes
  `TableExtractor` to its one-weight header rule. The words are fed with the caption's own text
  words to `TableExtractor.extractGrids`, unchanged.
- **Reader B: the SDK's grid into a `ManualTable`.** `RecognisedGrid.table(_:caption:page:)` maps
  cells by row and column range. A cell spanning columns in the leading rows becomes a column-path
  level, as `TableExtractor` makes one from a heading over several columns. A cell spanning rows
  in the first columns becomes a row-path level. Header rows are the leading rows before the first
  row of numbers, the extractor's own one-weight rule, shared rather than copied. Cell text goes
  through the same `Cell` parsing (value, unit, markers), and a grid failing the structural tests
  returns the extractor's `Failure`.
- **Cell certainty (pure).** `CellCertainty.assess` marks a cell `uncertain` when:
  - its lowest word confidence is under the floor (a parameter, settled in P1's measurement);
  - its column's other cells are numbers and it holds a confusable glyph (O/0, l/1/I, S/5, B/8,
    Z/2, a stray "," or "." between digits), in which case the cell is flagged, never "corrected";
  - a second pass at another render scale (P1) read it differently.
  An uncertain cell keeps its text for the check view (P3) and is never given as a value.
- **The model.** `ManualTable` gains `source` (`textLayer`, the default, or
  `recognised(reader:, meanConfidence:)`), and `Cell` gains `uncertain` (default false). Both are
  decoded with defaults, so stored tables read unchanged. `TableExtractor.Failure` gains
  `unclear_in_picture` for a recognised grid whose structure passed and whose cells are mostly
  uncertain. Below a set share of certain cells it is kept as an unread table, not a sparse one.
- **Tests.** Invented tables only (no standard's labels, rows or numbers): fixtures for both
  readers built as `RecognisedPage` values. They cover a spanned group heading, a two-level row
  path, a footnote marker read as a separate word, a confusable glyph in a number column, a
  disagreement between passes, a grid that fails the row test, and coordinate round-trips.

## P1 — Read the pictured tables at import

- **The adapters.** `VisionTableReader` (behind a `PictureTableReader` protocol so tests inject a
  fake) renders the region at a fixed scale with `PDFPage.thumbnail(of:for:)` or a
  CoreGraphics draw. It runs `RecognizeDocumentsRequest` with language correction off and
  `customWords` from the document's own text-layer vocabulary (column headings and units printed
  elsewhere in the book), and runs `RecognizeTextRequest`, same settings, for reader A. It renders
  again at a second scale for the agreement pass. Both are kept to the region, never the page.
- **Where it runs.** `PDFTableReader.read` gains an optional reader. A caption that failed
  `no_text_in_table` is re-read through it. A page with no text layer whose EF recognised text
  carries a caption line (`ManualStructure.caption`) is read whole. A table read this way joins
  continuation handling like any other. Without a reader (the default in unit tests, and on a
  device the policy holds back), behaviour is today's.
- **Budget.** Recognition runs only on those captions, so tens of regions per book, not
  thousands of pages. It runs in the import's background task with EF's checkpointing, so a
  relaunch does not recognise a region twice, and it yields to `PowerPolicyService`'s thermal
  state like EF does. Stored manuals get their tables by the location migration (version 5 → 6),
  tables only, text untouched, as JJ P5 did.
- **Result counts.** `PDFTableReader.Result` gains `recognised` (tables read from a picture),
  `unclearInPicture` and the reader used, logged through `logTables` as counts (DM).
- **Measure, then choose.** `Scripts/table-lookup-eval/` gains `TABLE_LOOKUP_EVAL_RECOGNISE=A|B|both`
  so the developer can measure before anything ships. It compiles the same reader code and is a
  development tool only; no user ever needs a Mac. Recognition on a Mac can differ from the
  phone's, so the numbers that decide are confirmed by importing the book on the phone (device
  pass). On the private book, against the cell key:
  - how many of the 24 lookups on pictured tables resolve, and how many give a cell matching the
    key, per reader;
  - uncertain cells per table, at three floors;
  - the 15 lookups that already resolve stay resolved (nothing regresses);
  - IV's retrieval key unchanged (hit@1 / hit@4 as P5 shipped).
  The reader with more matching cells and no wrong certain cell wins. A wrong certain cell found by
  the key is a blocker until the floor or the confusable rule catches it. The numbers go into this
  plan as counts only. The key stays unchecked until the partner checks it (JJ's rule), and the numbers
  say so.
- **Wholly scanned books.** Measured separately, on an invented scanned fixture and, if the
  partner has one, a scanned book of their own, kept off-repo.

## P2 — Say where the value came from

- **`table_lookup`.** A cell from a recognised table is given with "read from a picture of the
  table on page N of <manual>", its headers and notes as now, and an offer to show the page. An
  uncertain cell returns the not-extracted outcome with its own reason ("this cell could not be
  read clearly from the picture"), the page, and the instruction already given for unread tables:
  do not answer from memory.
- **`rule_chain`.** A step whose lookup used a recognised cell is marked in the read-back ("from a
  picture of Table 99, page N: check it against the page") and in the reading filed on the job.
  A chain never stops because a cell is recognised. It stops, as now, when the cell is uncertain.
- **"Show me the table."** Opens the cited page as today. For a recognised table the region is
  outlined, since there is no text selection to mark.
- **Prompt and description.** The `table_lookup` description gains one sentence on recognised
  cells, so the Direct and Live prompts carry it through `SystemPromptBuilder`. No hand-kept list.

## P3 — Check a pictured table (on the phone, or in the office)

- **Where.** The manual's page in the vault viewer lists its tables. A recognised table shows
  "Read from a picture: not checked" and opens a check view: the picture's region above, the grid
  below, uncertain cells marked.
- **What checking does.** Whoever manages the vault on the phone can mark the table checked, or
  correct a cell by typing what the page prints. A correction is kept with who and when, and a
  corrected or confirmed cell stops being uncertain. A checked table's cells are still said to be
  from a picture (principle 1), and the read-back drops "check it against the page". A new import
  of a different PDF (a new hash) starts unchecked.
- **Checks are a vault file.** The checks are written to `table-checks.json` in the vault, keyed by
  document hash, table label, row path and column path (no cell is keyed by position alone), and
  imported and validated like `chains.md`. A check for a hash the vault does not hold is warned
  of and kept. So:
  - **Phone only:** the file lives in the phone's vault, and the share sheet exports it so a
    second phone can import it (the JJ P3 pattern for chains). No office needed.
  - **With the office:** the office checks the same table against its own copy and writes the same
    file into the managed vault, which reaches the phone the way the approved set does (Plan JL).
    The office side is a private office plan, not drafted.
  - **Both:** a cell checked on the phone and in the office to the same value is checked. One
    checked to two different values goes back to uncertain, with both values and who checked each
    shown in the check view, until someone checks it again. Neither silently wins.
- **Who may.** Whoever may manage the vault on this phone. An organisation profile can require
  checking before recognised cells are given at all (P2's outcome until checked). Optional by
  default (decision 2).

## P4 — Photographed manuals (IF pages)

- A captured manual's page images go through the same reader when their recognised text names a
  table. Its tables are stored with the captured document's passages, derived, so the captured
  bundle contract is not changed. They are forgotten with it through IF's existing erasure
  linkage, and a new revision re-reads them.
- Recognised table words pass `SecretPatterns.redact` before anything is persisted, as IF's
  checkpoints do. A redacted cell is uncertain, never given.
- A photographed table is a picture of a picture: skew, glare and curl. Its floor is measured
  separately (the IF device guide's binder pages), not inherited from the PDF case.
- The captured manual's existing delivery is unchanged. A recognised grid is not added to what
  it sends. Checks of a captured table go in the same `table-checks.json`, keyed by the captured
  revision.

## Not in this plan

- A cloud recogniser or a vision-model read of the table. On device first; a cloud read would be a
  processor to disclose and is a later, separate decision.
- Diagrams, charts and curves read for values. A wiring diagram with numbers on it is still never
  a table.
- Correcting the text layer of a PDF, or the passages' text.
- The office's check surface. It is a private office plan, and nothing here waits for it.

## Owner decisions (confirmed 2026-10-21)

1. **Recognised cells feed a chain's result: yes.** They are marked in the read-back with the page
   offered, and an uncertain cell never feeds one.
2. **Checking is optional.** A recognised table carries "not checked" until someone checks it, on
   the phone or in the office. An organisation profile can make checking required.
3. **The reader is settled by P1's measurement**, document request against words into the
   extractor, on the private book against the cell key. The reader with more matching cells and no
   wrong certain cell ships. On a tie the document request ships, because its spanned cells come
   from the SDK rather than from inference. The counts go here.
4. **P4 comes after the partner's PDF case (P0–P3).** The 24 lookups are in the PDF, and IF's
   device qualification is still owed.

## Acceptance

- P0: both readers' fixtures pass headless, the coordinate round-trips hold, and the stored
  tables of the existing test vault decode unchanged.
- P1: on the private book, at least one of the two pictured tables reads with no wrong certain
  cell against the key. The 15 resolving lookups still resolve. IV's key does not move. The
  location migration re-reads tables only.
- P2: a recognised cell is never given without "from a picture" and the page, and an uncertain
  one never as a value. Both are asserted on the tool's output with a value-only token (the "no
  results" echo lesson).
- P3: a correction survives relaunch, is gone when the document is forgotten, and resets on a new
  hash. An exported `table-checks.json` imports on a second phone. A cell checked to two
  different values is uncertain again.
- P4: a captured page's table is gone with the capture's subject delete.

## Device pass owed

- Import of the partner's book on the phone: recognition time for the pictured regions, and
  thermal behaviour.
- `table_lookup` by voice on a recognised cell, then "show me the table".
- A chain through a recognised cell to a read-back, then the check view, a correction, and the
  read-back again.
- The checks exported from one phone and imported on a second, which then gives the corrected
  cell.
- A photographed binder table (P4) under shop lighting.
