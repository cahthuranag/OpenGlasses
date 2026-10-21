# Plan JN — Pictured Tables (a table printed as a picture, read on the phone, and said to be)

**Status:** 🚧 All phases P0–P4 built 2026-10-21 — the headless core (see "What shipped in P0"),
the import path with its measurement (see "What shipped in P1"), the wording that says where a
value came from (see "What shipped in P2"), checking a pictured table on the phone (see "What
shipped in P3") and the tables on photographed manual pages (see "What shipped in P4"); device
passes owed (see "Device pass owed"). P1's acceptance on
the private book is **not met**: the copy of the book held for measurement prints nothing at all
under the two captions (no picture, no drawing), so neither reader has anything to read there; a
copy that prints the tables is owed (see "What shipped in P1"). Drafted 2026-10-21; four owner decisions confirmed the same day (see "Owner
decisions"). Takes up Plan JJ's open question 3 (tables
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
  `useLanguageCorrection` and `customWords` (the latter used by Vision only with language
  correction on, so this plan does not pass it; see "What shipped in P2"). Nothing in the app uses
  it yet.

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

### What shipped in P0 (2026-10-21)

- `RecognisedTable.swift`: `RecognisedWord` / `RecognisedPage` (words with top-down page boxes,
  confidence and candidates; tables as cells with row and column ranges); reader A
  `RecognisedWords.table` (the caption's text-layer words, weight dropped, plus the recognised
  words, through `TableExtractor.extractGrids` unchanged); reader B `RecognisedGrid.table`; and
  `RecognisedReading`, which keeps each value cell's words and place for the certainty pass.
  Foundation and CoreGraphics only.
- `TableExtractor`: the one-weight header rule is now `plainHeader(rows:wrapTitle:isHeaderLine:)`
  over `HeaderRuleRow`s, and the row-header rule (`stubCount`) and the numbered-heading rule are
  callable on any grid; the text-layer path calls the same functions, and JJ's tests are
  unchanged. `Grid.cellBoxes` records where each value cell was printed (never stored), so reader
  A ties a cell back to its words.
- Reader B leaves a blank row-header cell blank rather than carrying the key above into it (a
  blank in a picture may be a missed cell); a header printed once over several rows comes from the
  recogniser as a cell spanning them. Notes under a pictured table are not read yet.
- `CellCertainty.assess`: uncertain on a word under the floor (a parameter), a confusable glyph in
  a number column, a second pass that reads the cell differently or not at all, a cell whose text
  cannot be tied to its words, or a blank cell (a blank and a missed cell look alike; it is not
  counted against the share). Under `minimumCertainShare` (0.5) clear cells among cells that read
  anything, the table is `unclear_in_picture`.
- `ManualTable.source` and `Cell.uncertain` are written only when not the default, so a text-layer
  table stores byte-for-byte the JSON it stored before; JSON from before JN decodes with defaults.
- `PictureRegion.below` takes the first stretch at least three caption lines tall that the text
  layer leaves empty under the caption's block (a lead paragraph set close under it is passed
  over), ending at the next text line or the footer band; `PictureRegion.pageRect` is the one
  mapping from a normalised bottom-left box in the rendered region to top-down page points, the
  image's rounded-up pixel size included.

## P1 — Read the pictured tables at import

- **The adapters.** `VisionTableReader` (behind a `PictureTableReader` protocol so tests inject a
  fake) renders the region at a fixed scale with `PDFPage.thumbnail(of:for:)` or a
  CoreGraphics draw. It runs `RecognizeDocumentsRequest` with language correction off, and runs
  `RecognizeTextRequest`, same settings, for reader A. No custom words: Vision reads them only with
  language correction on, which a cell cannot have (P1 passed the book's vocabulary anyway; P2
  removed it). It renders
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

### What shipped in P1 (2026-10-21)

- **The adapters.** `PictureTableReader` (protocol, `Sendable`) and `VisionTableReader` (Vision,
  builds on iOS and macOS): `documentGrid` runs `RecognizeDocumentsRequest` (each table's cells by
  row and column range, a spanned cell once, with its own words and candidates); `words` runs
  `RecognizeTextRequest` and splits each line into words by the recogniser's own character boxes.
  Both with language correction off and a text-height floor low enough for small table type. (P1
  also passed the book's own text-layer vocabulary as custom words; P2 removed it, see below.) `PictureTableReading.image` draws only the region, white under it, from
  the page's own content with CoreGraphics; `PictureRegion.pageRect` brings every box back.
  Nothing is logged and the images are dropped after each pass.
- **Where it runs.** `PDFTableReader.read(document:printedLabels:pictures:)` reads the text layer
  first (`scan`, the old loop, which also returns the regions a recogniser could read), recognises
  those regions, then reads the document again with them. Without a reader, or with nothing to
  recognise, the result is the text-layer reading itself, byte for byte (JJ's tests unchanged). A
  region is read for a caption that failed `no_text_in_table`; for one that failed `too_few_rows`
  only when `PictureRegion.below` finds an empty stretch at least five caption lines tall right
  under it (the P0 snag); never for an entry in a list of tables; and for a page with no text
  layer, whose own recognition (by words) is searched for table captions, each read from the
  region under it to the next caption or the footer band. A picture's table must pass the
  extractor's structural tests; one that does not leaves the caption's own failure (on a page with
  no text layer, `no_text_layer`, now kept as a pointer to the page). A table read from a picture
  joins continuation handling like any other ("(Continued)" captions merge; the words reading's
  grid carries on to a text page).
- **Two passes, one reader.** Each region is drawn at 3 and 2.5 pixels per point (2.5 and 2
  under serious or critical thermal state, as EF steps its resolution down) and read twice by
  `PictureTableReading.preferred`; the other reading is not run. `CellCertainty` with the second
  pass decides `uncertain`; under `minimumCertainShare` the caption is kept as
  `unclear_in_picture`.
- **Heading certainty.** P0 judged value cells only; a misread row key or column heading points a
  lookup at another row's or column's values. Row keys (the row-header cells and a heading printed
  over the rows) and column headings are now judged by the same evidence: a word under the floor,
  a second pass that reads them differently, words the reader cannot tie to them (reader A) or a
  confusable glyph where the other keys (the other headings) are numbers. `ManualTable.Row.keyUncertain`
  and `ManualTable.Column.uncertain` are decoded with defaults and written only when set.
  `TableLookup` gives no value (`unclear`, a minimal refusal naming the page, wording for P2) for a
  row whose key is uncertain, a column that is, a cell that is, a number placed between rows (or
  picked by a row rule outside them) when any key of the table is uncertain, and a column search
  over a column holding an uncertain cell. `rule_chain` stops on it, and its "the next row is"
  leaves out a row with an uncertain key and an uncertain cell. Nothing uncertain is written into
  a row passage (a row with an uncertain key has none; an uncertain cell, or one under an
  uncertain heading, is left out of its row's), so a search cannot hand the model what the lookup
  refuses. The confusable set gains D and Q (0), G and b (6), T (7), g and q (9).
- **Budget.** Only those regions are recognised (15 and 16 in the two editions of the private
  book). Each region is checkpointed as it is recognised
  (`PictureTableCheckpoint`, keyed by the PDF's content hash, then page, caption, reading and
  scale; in the vault's `_ocr` folder beside EF's, excluded from backup — complete file protection
  in P1, aligned with EF's class in P2;
  removed once the document is stored, and with the manual on removal), so a relaunch recognises no
  region twice, at either thermal step. `VaultImporter.defaultPictureReader` (Vision; tests inject a
  fake or nil) feeds the import, off the main actor.
- **Stored manuals.** Location version 5 → 6: the migration reads each stored document's tables
  again, the text untouched, with the same reader and checkpoint. A manual any page of which was
  read by recognition is still left as it is (as since IN P0).
- **Counts.** `PDFTableReader.Result` gains `recognised`, `unclearInPicture`, uncertain cells, keys
  and headings, and `pictureReader`; `logTables` logs them through `PrivacyLog` as counts.
- **Measurement.** `Scripts/table-lookup-eval/` gains `TABLE_LOOKUP_EVAL_RECOGNISE=off|grid|words`,
  `TABLE_LOOKUP_EVAL_FLOOR`, `TABLE_LOOKUP_EVAL_DIAGNOSE=1` (per region, counts only), the wrong
  certain cells and the stored tables that differ from the text layer alone;
  `Scripts/retrieval-eval/` gains `RETRIEVAL_EVAL_RECOGNISE`. The Mac runners compile the new files.

**The measurement (2026-10-21, a Mac, the PDF-backed vault of both editions, the cell key
unchecked: 30 questions, 3 more lines naming no row and not scored).** Counts only.

| Run | Tables read / unread / missing | Cells expected / matched | Read from a picture | Pictured-table lookups resolving | Uncertain cells | Wrong certain cells (pictured / any table) | Stored tables changed |
|---|---|---|---|---|---|---|---|
| off (text layer) | 12 / 13 / 5 | 29 / 9 | – | – | – | 0 / 0 | – |
| grid, floor 0.3 | 12 / 13 / 5 | 29 / 9 | 0 | 0 | 0 | 0 / 0 | 0 |
| grid, floor 0.5 | 12 / 13 / 5 | 29 / 9 | 0 | 0 | 0 | 0 / 0 | 0 |
| grid, floor 0.7 | 12 / 13 / 5 | 29 / 9 | 0 | 0 | 0 | 0 / 0 | 0 |
| words, floor 0.3 | 12 / 13 / 5 | 29 / 9 | 0 | 0 | 0 | 0 / 0 | 0 |
| words, floor 0.5 | 12 / 13 / 5 | 29 / 9 | 0 | 0 | 0 | 0 / 0 | 0 |
| words, floor 0.7 | 12 / 13 / 5 | 29 / 9 | 0 | 0 | 0 | 0 / 0 | 0 |

Why nothing reads: the diagnosis (per region, counts only) found no word in 29 of the 31 regions
and one or two in the other two. Measured in ink, 28 of the 31 regions are blank, the other three
holding a stray mark. The caption pages of the two tables carry text and an empty placeholder
drawing where the table would be, no image and no rule, and images appear on only 9 and 11 pages
of the two editions at all. The two tables are not pictures in this file; they are absent from it. JJ P5's
reading ("most likely a picture") was a guess from the text layer alone, and P1 shows it wrong for
this copy. No recogniser can read them from it.

**The choice.** The two readers tie (nothing to read, no wrong certain cell at any floor), so the
document grid ships (decision 3: on a tie the document request, whose spanned cells come from the
SDK). The floor is 0.5: the private book cannot set it, and on the invented test tables the
document reading's least word confidence on a clean, ruled grid ran from 0.66 to 0.80 across the
three scales, so 0.7 would mark clean cells uncertain; the agreement pass and the confusable rule
carry the rest. No rule had to be tightened: there was no wrong certain cell to remove. Both are
**provisional** until the tables can be measured on a copy that prints them.

- **Retrieval** (`Scripts/retrieval-eval/`, the code book's answer key, 66 scorable questions, the
  PDF-backed vault, contextual model, `RETRIEVAL_EVAL_RECOGNISE=grid`): hit@1 0.39, hit@4 0.58, as
  sent 0.61, in-scope refused 0, 28 misses — JJ P5 as shipped, unmoved.
- **The 15 resolving lookups** still resolve: with a reader the stored tables are the text layer's
  byte for byte wherever no picture reads (0 changed above), and the chains read those tables.
- **Not known yet / owed.** P1's acceptance (one of the two tables read with no wrong certain cell)
  needs a copy of the book that prints them: the partner's own PDF if it differs, or the pages
  photographed (P4). The device pass (recognition time and thermal behaviour on the phone, and
  Vision on the phone against the Mac) is owed. Until P2, a certain recognised cell was given like a
  text-layer one, without "read from a picture"; P2 (below) closes that.

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

### What shipped in P2 (2026-10-21)

- **`table_lookup`.** A cell of a recognised table is given as before (row, column, headings,
  notes, `Source:` line) and every row line it gives ends "— read from a picture of the table on
  page N of <manual>" (N the spoken page, as for a text table; both rows of a between-rows answer
  carry it). The answer adds that the value was read from a picture on the phone, not from the PDF's
  text, to say so, read it back for the technician to check against the page, and offer the page
  with `show_source`; with no notes it says notes printed with a pictured table are not read. A
  text-layer table's answer is byte for byte what it was (asserted). `Outcome.unclear` now carries
  which part was unclear (`UnclearPart`: cell, row key, column heading) and says "this cell could
  not be read clearly from the picture" (or "a row's name …" / "a column's heading this lookup
  depends on …"), the pages, and the not-extracted outcome's "Do not answer from memory. Tell the
  technician, and offer to show the page with show_source."
- **A loose match over an uncertain name (P1 doubt).** On a table with any uncertain row key, a row
  found other than by an exact name (by number, a printed range, or words) gives `unclear` (row
  key); with any uncertain heading, a column found by words gives `unclear` (column heading), in a
  lookup and in a chain's column search. Refusing was chosen over asking: the ambiguity path would
  read the misread names out as choices. An exact name on a clear row or heading is unaffected; a
  text-layer table matches loosely as before.
- **`rule_chain`.** A step whose lookup read a recognised table is read back with "— from a picture
  of <table>, page N: check it against the page", the tool adds a line telling the model to say so
  and offer the page, and the reading filed on the job keeps the marks in `pictureMarks`
  (`picture_marks`, written only when there are any, also in the session log payload). A recognised
  cell never stops a chain; an unclear one stops it naming the page and its `Source:` line. A
  proposed or kept chain runs through the same runner and is marked the same way.
- **"Show me the table."** A recognised table stores the region it was read from
  (`ManualTable.pictureAreas`: PDF page and top-down page rect, written only when present, older JSON
  decodes empty). A lookup on it notes no row passage (a picture has no text to mark) and the
  region instead; the cited-page viewer outlines it (a square annotation tagged like the
  highlights, `PictureRegion.pdfRect` mapping back to PDF space), the sheet's header says the table
  is printed as a picture and the outline marks where its values were read, and `show_source` says
  the region is outlined. A table whose start is text and whose continuation was read from a
  picture is merged as one read from a picture (never presented as text).
- **Description.** `table_lookup`'s description gains one sentence on recognised cells, carried
  into the Direct and Live prompts by `SystemPromptBuilder`.
- **Checkpoint (P1 doubt).** `PictureTableCheckpoint` is written with
  `completeUntilFirstUserAuthentication`, the class EF's `OCRCheckpoint` inherits as the app's
  default, so an import running on with the phone locked can save; still excluded from backup. A
  save that fails no longer vanishes: the import carries on, and the count is logged through
  `PrivacyLog` (`saveFailed`, `table_checkpoint`, counts only).
- **Custom words (P1 doubt).** Removed from `VisionTableReader` and the `PictureTableReader` seam,
  with the vocabulary pass that fed them: Vision uses custom words only with language correction on,
  and correction stays off, so passing them claimed a steer that never happened.
- **Owed.** The device pass (a recognised cell by voice, then "show me the table" with its outline;
  a chain through one and its filed reading). P1's acceptance is still not met (no copy that prints
  the tables).

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

### What shipped in P3 (2026-10-21)

- **The model (`TableChecks.swift`, pure).** `TableCheck`: the PDF's SHA-256 (the PDF the tables
  were read from: the manual, or the original a text import was made from), the table label, the
  row path and the column path as read (a cell's check has both, a row name's `row` only, a
  heading's `column` only; never a position), `confirmed` or `corrected`, the value as printed, who
  and when, and where it was made (`phone`, or a vault file). `TableChecks.apply` merges checks into
  a recognised table: an agreed cell takes the value through `TableExtractor.parseCell` (number,
  unit, markers) and is no longer uncertain; a confirmed row name or heading clears
  `keyUncertain`/`uncertain`; a cell checked to two values (phone against file, or two file
  entries) goes back to uncertain carrying every value with who and when, and is never given; a
  check matching no row or column, or more than one, is reported and applied nowhere; a text-layer
  table is never touched. The marks ride on `Cell.check` and the requirement on
  `ManualTable.uncheckedWithheld`, both transient (never stored: the stored table stays what was
  read). `TableChecks.status`: checked only when every cell is checked and no row name or heading
  is left unclear. A row name or heading can be confirmed, not corrected (a correction is refused
  with a warning): a misread one keeps its values refused and the page shown.
- **`table-checks.json`** (`TableChecksFile`), version 1, schema in the code and in the vault guide:
  read leniently (an entry that does not read, breaks a bound, names neither row nor column, or
  corrects a name is warned of and skipped), a file over 1 MB or of another version not read, a
  check for a PDF the vault does not hold warned of and kept. Imported like `chains.md`: the
  validator warns, the installer copies the file from the folder's root (listed in `files` or
  not), and the prompt builder never loads it.
- **Where checks live (`TableCheckStore.swift`).** A vault the phone authored (imported from a
  folder, or bundled): checks made on the phone are written into the vault's own
  `table-checks.json` through its overlay, atomically, starting from the file it was imported with;
  a later import of the folder with a file merges into it, so a check from elsewhere shows beside
  the phone's (and a disagreement with it). A vault the phone did not author (office-assigned,
  received from a link, or a signed pack): the phone never writes into it; its checks go to
  `TableCheckStore` (Application Support/FieldAssist/table-checks/{vault}.json, first-unlock
  protection, out of backup, registered as `tableChecks` in `DataStoreRegistry`) and are merged
  with the vault's file at apply time. Checking a cell again on the phone replaces the phone's
  earlier check of it.
- **Lookup and chains.** `TableLookupTool.sources` applies the vault's checks (with the document
  hash from the ledger) before `table_lookup` and `rule_chain` read. A checked cell is still "read
  from a picture of the table on page N of <manual>", with ", checked by <who> on <date>", and the
  answer's line drops "read the value back … to check against the page"; a chain step on a checked
  cell reads "from a picture of <table>, page N, checked by <who> on <date>". A disagreeing cell
  keeps P2's unclear wording. Row passages of a pictured table whose checks changed a value,
  disagree, or withhold it are not searched (`FieldSessionService.withheldRowPassages`): they
  still say what was read, so its values come from `table_lookup` only.
- **Requiring checks.** `organizationRequiresTableChecks`, a profile ceiling pinned on (a profile
  can only switch it on; off by default): a recognised table that is not checked gives no value at
  all — `unclear` with "this table was read from a picture and has not been checked against the
  page yet", in a lookup and a chain's column search, so the chain stops on it. In the deployer
  sheet's table.
- **The check view (phone).** Settings › Custom Vaults lists each manual's tables read from a
  picture with "Read from a picture: not checked / checked / checks disagree". The check view
  draws the stored regions from the PDF page (the P1 renderer, cropped to `pictureAreas`) above the
  grid, marks unclear and disagreeing cells, and takes a tap on a cell (confirm or type what the
  page prints), an unclear row name or heading (confirm), "Mark table checked" (confirms every
  cell read clearly and unchecked; never an unclear or disagreeing one) and "Share checks" (that
  manual's checks as `table-checks.json` on the share sheet). Checking is gated like importing a
  vault (`CustomVaultGateState.allowsImport`). Who a check names: the technician name set in
  Settings, else the phone's name. `TableCheckModel` holds the view's rules.
- **Reset and erase.** A different PDF (a new hash) starts unchecked; the old checks stay in the
  file, are reported unmatched and never apply. Removing a manual forgets its checks (the phone's
  store, and for a phone-authored vault its file, under the shared-reference rule); uninstalling a
  vault removes the phone's store for it. The subject erasure walks `tableChecks` before the vault
  ledger: a document's checks by the PDF hash its ledger entry names, a person's by the name a
  check gives.
- **Tests.** `TableChecksTests` (apply, disagreement, status, requirement, the file, the model) and
  `TableCheckStoreTests` (where checks live, import and merge, share round trip, reset, removal,
  uninstall, erasure, lookup and chain wording, row passages withheld, the profile key), invented
  tables, values and names only.
- **Owed.** The device pass (a correction, the read-back again, a share to a second phone). The
  office's check screen is a private office plan; any file in the schema is honoured. New UI
  strings need a catalogue sync. Correcting a misread row name or heading is not offered.

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

### What shipped in P4 (2026-10-21)

- **Where captured tables are read (`CapturedManualTables`, `CapturedManualCatalog.index`).** When a
  sealed capture revision is indexed, the pages whose recognised text (IF's, already redacted)
  carries a table caption line by `ManualStructure.caption` are read from the revision's own
  `pages.pdf` (an image-only PDF, one page per photograph) by the P1 scanned-page path, unchanged:
  `PDFTableReader.scan` finds the pages with no text layer, only the named ones are recognised
  (each page's words once, then the region under each caption twice by the document grid), and
  the second scan reads them, with `CellCertainty` judging cells, row keys and headings and the
  extractor's structural tests unrelaxed. A caption with no table under it is kept as a pointer
  to its page (`no_text_layer`). Pages naming no table are never recognised. The reader is
  `VaultImporter.defaultPictureReader` (Vision), injectable on the catalog; nil reads none.
- **Page mapping.** IF's: the physical page is the photograph's capture index (the page a
  photographed-manual citation opens) and the printed page is the number IF detected on it, when it
  detected one; picture areas are in that PDF page's own top-down points. "Show me the table"
  outlines the region on the photographed page (the captured branch of `manualPageSheet` now
  carries the picture areas).
- **Redaction, no checkpoint.** Every string a captured table keeps (label, title, row headers,
  column paths and units, row paths, cell text, markers and units, notes, printed pages) passes
  `SecretPatterns.redact`; a cell the redaction changed keeps the redacted text only, loses its
  value and unit and is uncertain (never given); a changed row name makes its key uncertain, a
  changed heading its column; a table with anything sensitive left after redaction is not kept.
  Redactions are counted through `PrivacyLog`. Captured pages are **not checkpointed**:
  `PictureTableCheckpoint` is not used for them, so no recognition of a photographed page is
  written anywhere.
- **Stored with the captured document.** `DocumentStore.ingestPages` gains `tables`: the tables
  and their row passages are published in the same transaction as the captured text, in the
  captured revision's own namespace, where `forget(documentId:)` already removes them. So a
  subject delete, a retake (the new revision is read from its own pages; the old revision's rows
  and tables go when the new one is indexed), a supersession by a reviewed copy and a capture
  forget take the tables with the document through IF's existing linkage. The captured bundle
  (images, PDF, text, manifest), its contract and its delivery are unchanged.
- **Relaunch: redo.** The text and the tables are published together, so an interrupted reading
  leaves the revision unindexed and IF's index recovery (`recoverIndex`, on launch and foreground)
  indexes it again from the start, tables included. The reading runs on a detached utility task,
  never on the main actor; the camera, page saving and sealing never wait for it; the scales step
  down under thermal pressure as P1's do. One indexing per revision runs at a time
  (`CapturedManualCatalog`), so recovery and the capture's own job never read the pages twice.
- **Lookup, chains, checks.** `TableLookupTool.sources` adds the tables of the photographed
  manuals the catalog makes eligible for the job (its scope, policy and supersession rules), never
  filtered by a vault manual's editions; `rule_chain` reads the same sources. Their values carry
  P2's "read from a picture of the table on page N of <the photographed manual's citation>". Table
  passages of a captured document are reachable by a question naming the table (`tableSearch`,
  `tableCatalogue`), and its row passages are withheld after checks exactly as a vault manual's.
  A check of a captured table keys `document_sha256` by the revision's bundle digest (the SHA-256
  of its canonical manifest, the identity IF's citations and reviewed copies bind to) and lives in
  the phone's `TableCheckStore` under the vault it was photographed against, never in a vault's
  file (`VaultTableChecks.capturedChecks`, `record(_:vaultId:photographed:)`). The saved
  photographed manuals list shows each manual's pictured tables with the P3 check view and Share
  checks. Forgetting the capture, and the subject delete of the captured document or its
  capture, forget its checks.
- **Floor.** `PictureTableReading.capturedFloor`, provisionally the PDF floor (0.5) and not
  measured: the IF device guide's binder pages set it (device pass owed; one row added there).
- **P3 date.** "checked by <who> on <date>" says the day on the phone's own clock
  (`TableChecks.day(_:timeZone:)`, `.current` by default); checks are still stored as ISO-8601
  instants in UTC.
- **Tests.** `CapturedManualTablesTests` (a fake page reader: only named pages read, the table
  stored by IF's page map, the pointer, redaction with no unredacted text in any file and no
  checkpoint, lookup wording on the captured page, a check by the revision identity, a new
  revision re-read, forget and subject delete, the floor; and one simulator test drawing a ruled,
  slightly turned table onto a page image through IF's real encoder, PDF and recognition and the
  real `VisionTableReader`, skipped with a reason if Vision reads nothing there) and a time-zone
  test in `TableChecksTests`. Invented tables, values and names only.
- **Owed.** The device pass (a photographed binder table under shop lighting; the photographed
  floor measured there). No new UI strings (the saved photographed manuals list reuses P3's check
  rows and view). P1's acceptance on the private
  book is still not met; photographing the two tables' pages from the paper book is now the route
  to reading them.

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
