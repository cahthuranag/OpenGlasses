# Plan JJ — Table Lookup and Rule Chains (a cell from the book, and the rules that use it, chained)

**Status:** 🚧 P0 shipped 2026-10-20: a captioned table in an organisation's own loaded PDF is
extracted at import into rows, header paths, cells (number, unit, footnote markers) and notes,
stored beside the document's passages, and each row is searchable as a passage; stored manuals get
their tables by the location migration. Measured privately on the loaded test book's PDF: 94
captioned tables found, 33 extracted to a grid (0.35), 51 with too few rows, 8 with varying
column counts, 2 with merged cells (see "What shipped in P0"). 🚧 P1 built 2026-10-20 (draft
PR): `table_lookup` returns one cell with its headers, units, notes and printed page, both rows
when a number falls between them, and a question back when the words fit more than one row,
column, table or book; a question naming a table ranks that table first; "show me the table"
opens the cited page with the row marked. Measured privately: row passages cost the code book one
question (hit@1 / hit@4 0.39 / 0.56 → 0.38 / 0.55), all of it through the table route; cell
correctness not yet measured (see "What shipped in P1"). P2–P4 not built.
Decisions confirmed 2026-10-20. Field Assist first; every phase is a headless core with the live
edge last. Written for the partner's electricians, whose stated priority
after the first round of code-book testing is **table lookup**: "those tables contain much of the
information electricians actually need", with cable sizing as the example — select a conductor for a
load and an installation, or check whether an existing cable's size and type are right — which "can
require tables and several rules together". The same partner also said testers cannot be expected to
know which rule applies or how to split a question: finding that is part of the assistant's value.

## Why a separate plan

Plan IN made a code book's **clauses** findable and showable: a clause chunked as one rule, found by
its number, cited, and opened on the page with the passage marked. Plan IV measured and tuned how
clause passages rank. Neither touched **tables**, and the first field reports show why that matters:

- **A table page is a picture to the retriever.** `ManualStructure` tags a page of labels and
  numbers as a drawing (`<!-- page: diagram -->`), and a `TABLE N` caption names it, so the page can
  be *shown* on request and even auto-opened. But the words sent to the model are PDFKit's
  flattened run of cells with no rows and no columns, so "what is the rating of this conductor in
  that column" cannot be answered from it, and what the model does answer is read off a jumble.
- **A cell is not a passage.** The embedder ranks a flattened table low against a question about
  one of its cells; the exact-token route finds a number only when the question says it (and a job
  number once opened a vent-length table because one cell held it — `ManualTurnScope`).
- **Nothing chains.** Cable sizing is a sequence: a load, a correction or two from other tables, a
  rule that says which rating column applies, a lookup, and a check. Today each step is a separate
  question the technician has to know to ask, and the answer to one is never carried into the next.
- **The answer must stay verifiable.** Plan IN's acceptance — the technician hears the answer with its
  source and can open the page — has to hold for a table cell (which table, which row, which column,
  which note) and for every step of a chain.

This plan gives the app tables as data it extracted from the organisation's own loaded copy, a
lookup that returns a cell with its provenance, and chains of lookups and arithmetic that run step by
step, read back, and cite. It ships no table content, no rule content and no code text, for the same
reason Plan IN decision 6 ships no standard: the organisation loads its own licensed copy.

## Verified starting point (`main` @ `79d563bd4`, 2026-10-20)

- **Extraction keeps pages and type, not positions.** `VaultDocumentExtractor` extracts each PDF
  page, joins them with a form feed, and reads printed page labels. `ManualStructure.TypedLine`
  carries `raw`, `text`, `size` and `bold` per line — enough to find headings and captions, not
  enough to know which column a word sits in. `ManualStructure.caption` recognises `FIGURE N` and
  `TABLE N` captions and `render` hoists the page's caption to name a drawing page.
- **Chunks have a kind and a figure, not a shape.** `DocumentChunker.Chunk` is `prose` or `diagram`,
  with `figure` ("Table 16") when a caption names its place. A table's cells are chunk text like any
  other, overlapped and sentence-packed. There is no table row anywhere in `DocumentStore`.
- **Clause-numbered documents are detected and chunked at each clause** (IV P3,
  `DocumentChunker.clauseHeadingLines`), and a clause is found by its printed number ahead of the
  token and semantic routes (IN P3a, `ClauseReference`, `DocumentStore.passages(clause:)`).
  `ManualPassageLimit` hands the model six passages when the best one is a clause.
- **Showing a page.** `show_source` resolves "show me" against the last answer's citations;
  `manual_figure` opens a figure or a page; `FigureAutoOpenPolicy` opens a captioned page when the
  technician asks for a page, figure, diagram or table by word, and only attaches it to the model
  otherwise (`.tableNotAskedFor`). `PassageHighlight` marks a located passage; a drawing page is
  never highlighted.
- **Arithmetic exists, chaining does not.** `calculate` evaluates an expression; `convert_units`
  converts; `domain_calc` reads bundled refrigerant saturation tables generated by a script and
  checked in (Plan IS P0) — the one precedent for a table the app answers from, and the precedent
  that a shipped table must be generated from a source the app may ship. Nothing runs a sequence of
  steps, carries a value from one to the next, or reads a chain back.
- **Electrical vault.** `VaultManifest` knows the trade `electrical`; no electrical vault template,
  calculator or standard-kind handling exists. IN P3 (the `standard` document kind, printed-page
  citations, the answer rules for a standard, the starter electrical vault with a voltage-drop
  calculator) is drafted and unbuilt. JG (regulation practice) and JI (apprentice support) are
  drafted and reuse the vault's own copy of the code the same way this plan does.
- **Licensed material is testing-only.** The partner-supplied code books never enter the repo;
  retrieval was measured against a private answer key on a Mac runner (Plan IV) and reported as
  aggregates. Every fixture in this plan is invented, with invented table numbers, designations and
  values, and nothing in a test, comment or plan is a fact from a book.

## Decisions (confirmed 2026-10-20)

1. **Tables are extracted on the phone from the organisation's own loaded PDF, at import.** The app
   ships a table extractor and no tables. A vault pack, export, bundle or link never carries an
   extracted table of a `standard` or a manual, exactly as it never carries the document
   (IN decision 6, Plan EG).
2. **A lookup returns a cell with its provenance, and never decides a rule.** `table_lookup` gives
   the cell at a row and column with the table's caption and title, the row's and column's full
   header path, the units, and the notes the cell or its column references. When the asked value
   falls between rows it returns both bracketing rows and says so; it never interpolates, never
   rounds, and never picks "the next size up" on its own. Which row a rule wants — at least, at
   most, exact — is a chain step's parameter or the technician's call, said out loud.
3. **Rule chains are authored in the vault, not in the app.** A chain is a short declarative
   sequence in a vault core file (`chains.md`): inputs to ask for, lookups by table and header,
   arithmetic, a comparison, what to say. The organisation writes chains against the table and
   rule numbers of *its* code and edition, so the app stays jurisdiction-neutral and ships no rule.
   The app ships the schema, the runner and an invented example. The partner's chains are written
   for the partner's testing by the owner, outside the repo, like the test books themselves.
4. **The model may propose a chain; only the technician runs one.** For a question with no
   authored chain, the model retrieves the clauses (IN/IV) and proposes the steps it reads there
   — which tables, which corrections, which rule picks the column. The technician hears the
   proposal and says go, changes a step, or stops. A proposed chain runs through the same runner,
   reads back the same way, and can be kept for the organisation through the team-learning path
   (Plan FP) where it is reviewed before anyone else sees it. A chain is never run silently.
5. **Every chain answer is read back step by step with a citation per step.** Inputs as heard,
   each lookup as "Table 99, row QXRT, column for the third rating group: 40 — page 12", each
   arithmetic step with its numbers, the comparison, the result. A step whose table could not be
   extracted stops the chain, says so, and shows the page; it never continues from a guessed cell.
   The read-back goes on the job record like a reading.
6. **Cable sizing is the first chain family, both ways.** Forward: a load and an installation to a
   conductor size and type. Inverse: an existing cable's size and type to whether it carries the
   load. Voltage drop is the arithmetic step (IN P3's calculator line moves here). Nothing about
   which corrections a jurisdiction applies is in the app; the chain says.
7. **Table questions run on a cloud or local model.** Following PR 801, a job turn never runs on
   Apple's on-device model when another configuration exists. `table_lookup` is small enough for
   the on-device set and is offered there; chains are not.

## Phases (one PR each)

### P0 — A table as data (headless core) ✅ (2026-10-20)

- **Positioned text.** `VaultDocumentExtractor` gains, for each page, the words with their
  bounds (`PDFPage.characterBounds(at:)` over the page's attributed string, grouped into words and
  lines), kept only long enough to extract tables; chunk text and stored passages are unchanged.
  A page with no text layer (a scanned book, or Plan IF's photographed pages) yields nothing here
  and is reported as such.
- **`TableExtractor` (pure).** Input: a page's typed lines and positioned words, and the caption
  `ManualStructure` found. Output: a `ManualTable` — `label` ("Table 99"), `title`, `page` (physical
  and printed, IN P0's labels), `columns` as a header tree (a group heading over several columns
  becomes a path, "Rating group 2 › 75"), `rows` as a header path too (a row's first cell, plus a
  group row above it), `cells` as text with a parsed number and unit where one parses, `notes`
  (footnote markers and the note text found under the table), and `continuedFrom` when the caption
  reads "(Continued)". Column boundaries come from clustering word x-origins across the body rows;
  header rows are the lines between the caption and the first body row; a row is the words that
  share a baseline. A page that does not resolve to a consistent grid (fewer than three rows, or
  columns that change count row to row) extracts nothing, so a wiring diagram with numbers on it
  is never a table.
- **Continued tables merge** by label across consecutive pages into one `ManualTable` with the
  first page's headers, each row keeping its own page.
- **Storage.** `DocumentStore` gains a `doc_tables` row per table (document id, label, JSON of the
  table), written at import with the chunks and re-extracted by the location migration
  (`locationVersion` 2 → 3) for stored vault documents, under the same document id. Tables are
  excluded from `VaultExporter` and every pack, bundle and link, alongside the document.
- **Row passages for retrieval.** Each body row is also rendered as one sentence ("Table 99
  (Conductor ratings), row QXRT, three conductors: 30 in rating group 1, 35 in rating group 2, 40
  in rating group 3 — page 12") and stored as a chunk of a new kind `.tableRow` with `figure` set,
  so the embedder and BM25F can find a cell by its row header and the token route by its label.
  Row passages are capped per table and never auto-open a page (they are not drawings).
- **Exit tests (invented fixtures):** a simple grid extracts with the right headers and cells; a
  two-level column header gives the right paths; a table continued over two pages merges with each
  row's page; footnote markers attach to cells and the note text is kept; a table with units in the
  header parses numbers; a drawing page with numbers extracts nothing; a page with a caption but no
  grid extracts nothing and says so; row passages render and chunk as `.tableRow`; export omits
  tables. Measured privately on the loaded test book and reported as aggregates: the share of
  captioned tables that extract to a consistent grid, by table, with the failures classified
  (merged cells, rotated headers, no text layer).

#### What shipped in P0 (2026-10-20)

- **Positioned words, only where a table is.** `PDFTableReader` reads a page's words with their
  boxes from PDFKit (`PDFPage.selection(for:)` over each run of non-space characters in the page's
  string, cut where the type size changes so a raised footnote digit stays apart from its number),
  and only for a page whose text mentions a table. `characterBounds(at:)` was tried first and
  dropped: its index does not count the newlines PDFKit's own string contains, so boxes drift a
  character per line. Positions live only while the page is read. `VaultDocumentExtractor.extract`
  is untouched, so chunk text, page separators and labels are byte-for-byte what they were. The
  reader builds on macOS too, so a measurement reads a PDF exactly as an import does.
- **`TableExtractor` (pure, `Sources/Services/Vault/`).** Positioned words and a page in, one
  outcome per caption out: a `ManualTable` or a `Failure` (`no_text_layer`, `caption_not_found`,
  `too_few_rows`, `varying_column_count`, `merged_cells`, `rotated_headers`). The caption is read
  off the positioned lines, which replaces the typed-lines input the bullet above names. On a
  page that sets anything in bold it is the rule `ManualStructure.caption` applies to typed lines
  (bold, `TABLE N`), so every caption that names a chunk's `figure` is a caption here with the
  same label (a test holds that one direction). On a page whose text layer carries no bold at all
  — the loaded code book is set in one font, with no weight anywhere in its text layer — the
  caption is a line that begins `Table N` in any case and stands on its own: at most twelve
  words, no sentence ended before the last. The grid that must follow keeps a short prose line
  beginning with a table reference from extracting anything. `ManualStructure.caption` is
  unchanged: it names passages and decides which pages open, as Plan IV measured. The header is
  the leading run of bold lines under the caption and its title. On a plain page it is the lines
  before the first row whose cells after the first are mostly numbers (at most four), after up to
  three single-phrase lines of a long title that wrapped under the caption. The body runs until a
  note, a paragraph or a wide gap. Columns are the union of the body cells' horizontal extents over the rows with the
  modal cell count, and must come out as many as those rows have cells. More than 15 % of rows
  off the grid refuses the page. A header phrase heads the columns whose centres fall in its
  region (its extent widened symmetrically to the midpoint with its neighbours), which makes a
  group heading a path level ("Rating group 2 › Band B"). Leading text-only columns are row headers,
  and a row header printed once is carried down to the rows that leave it blank. A single phrase
  alone at the left heads a row group. Cells keep their printed text and parse a number (decimal
  comma, thousands separator, typeset minus) and a unit, their own or their column's bracketed
  one. Markers (`*`, daggers, raised digits, `(a)`) are kept on the cell, and notes under the
  table are kept with their markers. A "(Continued)" caption merges into the previous page's table
  of the same label when the column count agrees, each row keeping its own page. A continuation
  with nothing before it stays marked `continues`.
- **Storage.** `doc_tables` (document id, index, label, pages, the table as JSON) is written at
  import beside the chunks. `forget`, the checked forget, `clear(namespace:)` and `clearAll` take
  it. The tables come from the document when it is a PDF, else from the original a text import
  was made from when the vault carries it; with neither, the import logs `tables_no_pdf` and goes
  on. `locationVersion` 2 → 3: `PassageLocationMigration` reads the same PDF for stored vault
  documents and adds their tables through `DocumentStore.replaceTables`. Text chunks are compared
  without the row passages and only re-located when unchanged, so their ids, text and embeddings
  stay as they were. A recognised manual is still left alone.
- **Never leaves the phone.** Tables live only in the document store, which no export, pack,
  bundle or link path reads. A test imports a vault with a table, exports it and finds none of its
  values in any exported file, and a source scan holds the exporter and the pack, link, archive
  and publisher files away from the table types.
- **Row passages.** `TableRowPassage` renders each body row as one sentence ("Table 99 (Conductor
  ratings), row QXRT, three conductors: 30 in Rating group 1, 35 in Rating group 2, 40 in Rating
  group 3 — page 12", the printed page when known). Each is stored as a chunk of the new
  `DocumentChunker.Kind.tableRow` (`table_row`) with `figure` set, numbered after the document's
  own text and embedded the normal way, at most 400 per table, with what the cap left out logged
  as a count. The rows are searched by the token route (as before, all kinds), and also by
  `query` and `passages(sharingTermsWith:)`, whose default kinds are now prose and table rows.
  They are left out of the document's own text (`fullText`, `pageTexts`, the stored text the
  clause and back-of-book detectors read). They cite their table ("Manual, page 12, Table 99"),
  and the model is told "(table row, Table 99, page 12)". `FigureAutoOpenPolicy` gains
  `PassageKind.tableRow`: attached to the model on a question, opened only when the technician
  asks for the page, never by a number. `ManualPassageLimit` is unchanged.
- **Tests (37, invented fixtures).** `TableExtractorTests` (26): a simple grid, a two-level
  header, units in the header and in a cell, footnotes and notes, a continued table merged (and a
  lone continuation kept apart), a figure drawing, a drawing under a table caption, a caption over
  prose, an empty page, merged cells refused, every `ManualStructure` table caption being an
  extractor caption, cell parsing, row sentences and the cap, JSON round trip. On a page with no
  bold: a plain caption over a grid extracts, a wrapped title is read as the title, the same
  caption line on a page with bold elsewhere is not a caption, and prose beginning "Table 95
  shows …" extracts nothing. The PDF
  tests draw the same layouts into a real PDF and read them through PDFKit: printed page labels,
  a merge across two PDF pages, raised footnote digits, a scanned page counted as having no
  text layer, and a PDF whose text layer has no bold. `TableStorageTests` (11): stored at ingest after the text, found by token, figure,
  terms and query, capped with the table kept whole, forgotten and cleared, migrated without
  touching the text chunks (and a second launch idle), read from a text import's original, a
  text-only import skipped, imported then exported with no value in the export, the source scan,
  the auto-open policy, and the citation.
- **Measured privately** with `Scripts/table-extract-eval/` on the loaded test book's PDF
  (aggregates only; the runner compiles `PDFTableReader` and `TableExtractor` unchanged and prints
  nothing from inside a table):

  | | bold caption rule only | plain captions | plain captions + wrapped titles (shipped) |
  |---|---|---|---|
  | Captioned tables found | 0 | 94 | 94 |
  | Extracted to a consistent grid | 0 | 7 (0.07) | **33 (0.35)** |
  | Too few rows | — | 79 | 51 |
  | Varying column count | — | 7 | 8 |
  | Merged cells | — | 1 | 2 |
  | Rotated headers / no text layer | — | 0 / 0 | 0 / 0 |
  | Pages without a text layer | 0 | 0 | 0 |

  Of the 33: median 7 rows (max 23), median 2 value columns (max 9), 15 with notes, none
  continued over pages, 0.83 of filled cells numeric, about 14 s for the whole book on a Mac.
  The book's text layer is set in one font and carries no bold, so the bold rule alone found
  nothing. The remaining failures are mostly "too few rows". The runner does not say why a body
  ended early, so the next lever is a counts-only breakdown of where each body stopped. A vault
  that carries the code book only as extracted text (the test copy first measured was one) gets
  no tables until its original PDF is beside it.
- **Not known yet.** Whether the 33 grids are right. A consistent grid is not a correct one, and
  checking that needs an answer key of cells, which P1's measurement adds. The row passages add
  candidates to every manual search in a vault with tables; their effect on IV's code-book
  numbers is not yet measured.
  "Show me" on a row passage opens its page unmarked ("The passage couldn't be marked on this
  page."), because the row sentence is the app's text, not the page's. Marking the row is P1.

### P1 — `table_lookup`, and "show me the table" 🚧 (built 2026-10-20, draft PR)

- **`table_lookup` tool.** Arguments: `table` (label or title words), `row` (a header value or
  the words of one), `column` (a header path or words of one), and optionally `document`. It
  resolves the table by label first and title words second, the row by exact header then number
  then nearest words, the column by path; it returns the cell with its row and column paths, units,
  the notes it references, and the citation (document, table, printed page). With a numeric row
  key between two rows it returns both and says "between"; with an ambiguous row or column it lists
  the candidates and asks, never guessing. A result is a `Citation` the chips can open.
- **Retrieval.** A question that names a table ("table 99", "the ratings table") takes the lookup
  route ahead of the clause route, the way a clause number does; a question that names a row header
  value reaches the row passage. `ManualPassageLimit` treats a table row as a clause for the limit.
- **Showing it.** `show_source` resolves "show me the table" against the last answer's table
  citation; the page opens and `PassageHighlight` marks the row's text when it is located on the
  page (IN decision 3: found, never guessed; a rotated or image table opens unmarked with the plain
  line). `FigureAutoOpenPolicy` is unchanged.
- **Exit tests:** lookup by label, by title words, by row number, by row words; between-rows
  returns both; ambiguity asks; the citation opens the right table in the right document when two
  books are loaded; a question naming a table ranks the lookup first; an on-device profile offers
  `table_lookup` and not `rule_chain`. Measured privately: a set of single-cell questions on the
  loaded book, answered from the cell with the right citation, as a rate.

#### What shipped in P1 (2026-10-20)

- **`TableLookup` (pure, `Sources/Services/Vault/`).** The stored tables in, one outcome out:
  `found` (the rows and columns read, with `between` set when an asked number fell between two
  rows), `ambiguous` (document, table, row or column, with the candidates to say), `notFound` (with
  what does exist), `notExtracted` (a caption whose grid could not be read, with its page) or
  `noTables`. The table resolves by label ("Table 99", "tbl 99", "table ninety-nine", "No. 99"),
  then by title words; the same label in two books asks which book. The column resolves by its
  path or the end of it ("Band B" under one group), then by words, every number in the words
  having to be in the heading. The row resolves by its header or a run of its headers ("QXRT three
  conductors"), then by number (a numeric key equal to it, or a printed range holding it, "8" in
  "7-9"; else the two rows either side, said as "between"; outside the rows, the range they run
  over), then by its nearest words. Without a column the whole row is read, unless the table has
  one value column. The notes are those a marker on the cell, its row's headers or its column's
  headings keys, and the table's unmarked notes. Nothing is interpolated, rounded or moved to a
  neighbouring row; the rendered text says so, and ends with a `Source:` line in the form
  `VaultRetriever` writes ("Book, page 12 (printed 10), Table 99"), which `CitationLineParser`
  reads into a chip for that table's page in that book. Pages are said by their printed number, else
  as "PDF page N".
- **Unreadable captions are kept.** `ManualTable.failure`: a caption whose page did not resolve
  to a grid is stored by its label, title and page (`PDFTableReader.Result.unextracted`), so a
  lookup says the table is there and could not be read, and names the page to show. Location
  version 3 → 4: a document version 3 already located only has its tables read again; its text,
  ids and embeddings are untouched.
- **`table_lookup` tool** (`NativeTools/TableLookupTool.swift`): registered, in
  `FieldToolProfile.names` and `AppleOnDeviceToolSet.fieldAssistPriority` (decision 7), a read in
  `ToolEffectClassification`, local in `OfflineToolPolicy`, titled in `ActivityTitler`. It reads
  the vault's manuals still in the vault, newest edition unless the words reach past it or a book is
  named, and notes what it cited for "show me the table".
- **Retrieval.** `TableReference` (pure) recognises a table a question names by number, printed,
  abbreviated or spoken, or by its title words when the question says "table" and one title fits
  best; "table saw", "timetable 9", "TBL99X" and "table 99X" are not references. `VaultRetriever`
  has a table route (`DocumentStore.passages(table:)`: the table's row passages, else the page of a
  caption that could not be read) and ranks a named table's passages above the clause groups, its
  rows before its page. A row key printed as a range ("7-9") was split at the dash by the tokenizer
  and never searched; `CodeTokenizer.rangeKeys` keeps it whole and it counts, like a designation,
  only when the manuals print it. A designation ("QXRT") already reached its row. `ManualPassageLimit`
  asks for six when a searched manual has table rows and keeps six when the best passage is a row.
- **Showing it.** `show_source` takes "table", "the tables" and a table label against the last
  answer's citations. A table row's anchor carries the row as printed (`TableRowPassage.printedRuns`),
  and `PassageLocator` marks the first run found exactly once on the page, as the same words; a row
  printed twice, or not found, opens its page unmarked with the existing plain line.
  `FigureAutoOpenPolicy` is as P0 left it.
- **Tests (invented fixtures; the exit tests committed before any run on licensed material, the table of words added after the counts-only breakdown below).** `TableLookupTests`
  (21) and `TableLookupSessionTests` (5): lookup by label, spoken and abbreviated label, title words,
  row number, a range holding the number, row words; between rows returns both and prints no other
  value; ambiguity asks for the row, the column and the book; an unread table names its page;
  `TableReference` recognition and non-matches; range keys; row marking (once, never twice, same
  words); the passage limit; the on-device set offers `table_lookup` and not `rule_chain`, and its
  definition fits beside `field_session`; and, over two invented books both printing a Table 99,
  the citation opens the right table in the right book, "show me the table" marks that row and
  not the one above, a question naming a table ranks it first (by number, by title words, spoken),
  a row header reaches its row, and the migration keeps the unread caption without touching the
  text.
- **Measured privately** (aggregates only), the code book's newest-edition answer key (66 scorable
  questions) on the contextual model, the PDF-backed vault indexed by the Mac runner, which now
  reads a PDF's text and tables as an import does (`RETRIEVAL_EVAL_TABLE_ROWS` = `0`, `1`, `token`,
  `table`):

  | Row passages | hit@1 | hit@4 | as sent | in-scope refused |
  |---|---|---|---|---|
  | Excluded (as before P0) | 0.39 | 0.56 | 0.61 | 0 |
  | Included, every route (shipped) | 0.38 | 0.55 | 0.59 | 0 |
  | Token and table routes only | 0.38 | 0.55 | 0.59 | 0 |
  | Table route only | 0.38 | 0.55 | 0.59 | 0 |
  | Plan IV P7, for reference | 0.39 | 0.56 | 0.61 | 0 |

  One question is lost, and it is the table route's: one question in the key names a table, by its
  title words; it hits with the route off and misses with it on. Keeping the rows out of the
  semantic default changes nothing, so they are not gated there. Ranking a title-word table with
  the token hits rather than above them was tried and did not bring the question back, so it was
  not kept. The cost is one question of 66 against a tool and a route a technician can now use by
  table number.
- **Too few rows, broken down** (`Scripts/table-extract-eval/`, counts only, on the 2024 PDF): of
  51 captions with too few rows, 35 read no body row of two or more cells, 13 one and 3 two; 30
  have no run of three such lines anywhere under the caption, 16 have one within seven lines and 5
  further down; of the 21 runs, 18 are text in the first cell of every row and 13 text in every
  cell. The general shape that was being refused, a table of words on a page set in one weight
  (no row of numbers to find its body by), is now read: the first run of rows heads the grid with
  its first line, and in a table of words only the first column heads the rows. Before → after:
  extracted 33 → 35, too few rows 51 → 45, varying column count 8 → 12, merged cells 2 → 2. The 30
  with no run of rows at all (cells that set close enough to read as one phrase, or rows that wrap)
  are the next lever and are not addressed.
- **Not known yet.** Whether the cells are right. A starter answer key of cells was written beside
  the book for the partner's electrician to check, and is unchecked; P1 does not score against it,
  and the rate of single-cell questions answered from the right cell is owed once it is checked.

### P2 — Rule chains, authored

- **`chains.md` in the vault.** Each chain is a heading with a short declarative body: `ask` steps
  (what to ask the technician, with units and plausible range), `lookup` steps (table by label,
  row and column from earlier values, and the row rule: `exact`, `at_least`, `at_most`), `calc`
  steps (an expression over named values, with units), `convert` steps, `check` steps (a
  comparison with what to say either way), `cite` lines naming the rule each step follows, and
  `say` for the result. The vault validator checks the schema and that every table a chain names
  exists in the vault's extracted tables, and reports the ones that don't at import.
- **`ChainRunner` (pure).** Runs one step at a time over a `ChainState` (values with units and
  provenance), returning what to ask or say next; a lookup step calls the P1 resolver with the row
  rule applied; a `calc` step uses `calculate`'s evaluator; a `check` step records the verdict. It
  never continues past a step it could not complete, and every value it holds knows which step
  made it and from which cell.
- **`rule_chain` tool.** `list` (chains the vault offers, by what they answer), `start`, `answer`
  (the technician's reply to an `ask`), `status`, `stop`. The current step and what it needs are in
  the system prompt the way the active procedure is (`procedure_runner`), so the model asks in its
  own words and the runner keeps the state. A chain started on a job records its read-back on the
  job as a reading with every citation.
- **Cable sizing, both ways, as the shipped example** over invented tables (Table 99 conductor
  ratings with rating groups, Table 98 correction factors) in the test vault: the forward chain
  and the inverse check, the voltage-drop `calc` step, and a `check` that says "carries it" or
  "does not carry it, the next row is …".
- **Exit tests:** the schema round-trips; a chain over the fixture tables runs forward to the
  expected size and inverse to the expected verdict; `at_least` and `at_most` pick the right rows;
  a missing table stops the chain with the page shown; the read-back names every step with its
  citation; a chain that names a table the vault lacks is reported at import.

### P3 — Chains the model proposes, the technician runs, the organisation keeps

- **`propose_chain`.** For a question no authored chain answers, the model is told (in the
  Field Assist prompt, standards section) to retrieve the clauses first and then propose a chain
  in the P2 schema from what they say — never from memory of a code. The proposal is read back as
  steps with each clause cited, and the technician says go, changes a step, or stops. Running it
  goes through `ChainRunner` unchanged.
- **Keeping one.** A proposed chain that ran to a result can be saved as a draft chain through the
  team-learning path (Plan FP): it goes to the organisation's review, not into the vault, and
  until reviewed it is offered only on the phone that made it, marked "unreviewed". A reviewed
  chain lands in `chains.md` on the office side and reaches phones with the next vault update.
- **Exit tests:** a proposal must cite a clause per lookup step or it is refused; a proposed chain
  runs through the same runner and reads back the same; an unreviewed chain is offered only on its
  origin phone; the review hand-off carries the proposal and its citations and nothing else from
  the job.

### P4 — The electrical starter vault

- A vault template for the trade `electrical` with no standard's text: a slot for the
  organisation's code PDFs (`standard` kind when IN P3 lands; a manual otherwise), an empty
  `chains.md` with the schema and the invented example commented, the voltage-drop calculator as
  a `calc` step and as `domain_calc`'s electrical domain, and the vault guide's new step, "Tables
  and chains". The partner's chains are not in it.
- **Exit tests:** the template validates; the guide's example chain validates against the
  template's fixture tables.

## Acceptance

- The partner's electrician asks for a conductor for a stated load and installation and hears
  the answer read back as steps: what was assumed, each table and cell used with its page, the
  arithmetic, the result — and can open any step's page. Asked whether an existing cable is right,
  he hears the same chain the other way round.
- Asked for one cell, he hears the cell, its headers, its units, its notes and its page, or that it
  sits between two rows, or a question back. He never hears an interpolated or guessed value.
- A chain never continues past a step it could not complete.
- No table, chain or clause text from a loaded book leaves the phone in any export, pack, bundle
  or link.
- The tester need not know which rules apply: for a question with no authored chain, the assistant
  proposes the steps from the clauses it found, with each clause cited, and asks before running.

## Open questions for the owner

1. Which chains first, beyond cable sizing both ways: breaker or overcurrent-device sizing, conduit
   fill, grounding-conductor sizing, voltage drop on its own? The partner should name three.
2. Who authors the partner's `chains.md` for testing — the owner, from the partner's own code copy
   and outside the repo, or the partner's lead electrician with the guide? The schema is designed so
   an electrician can write one.
3. Tables with no text layer (image-only pages in an otherwise text PDF) — extract through Plan
   IF's recognition path in P0, or report them and leave them for IF?
4. Does P3's "keep a chain" need the office review surface (Plan FP P4, blocked on q7 there) before
   it is useful, or is "unreviewed, this phone only" enough for the partner's test?
5. Measurement: the private table-question set has to be written against the loaded test book,
   like Plan IV's answer key, and stays off-repo. Who writes it, and how many questions?
