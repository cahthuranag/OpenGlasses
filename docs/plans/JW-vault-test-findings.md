# Plan JW — Vault Test Findings (revised tables, printed pages, "show me", chains that stop)

**Status:** 🚧 P0 built 2026-10-27 (PR 861) (all seven items, headless); P1 = partner re-run. Drafted 2026-10-27 from the partner's three
structured vault test sessions on build 564 (2026-10-26). No later build changes any of it:
nothing merged between 564 and 570 touches table reading, page labels, `show_source`, the smart
camera or `rule_chain`.
**Track:** Field Assist first (the partner's code-book vault), app-wide underneath: any vault PDF
whose captions carry a margin mark, any book that prints its page number beside other footer
text, any Direct-mode turn that says "show me".
**Related:** Plan [JJ](JJ-table-lookup-and-rule-chains.md) (`TableExtractor`, `PDFTableReader`,
`table_lookup`, `rule_chain`, `ChainRunner`), Plan [JN](JN-pictured-tables.md) (pictured tables;
its P1 finding is revisited below), Plan [IN](IN-verifiable-code-lookup.md) (printed page labels,
`show_source`, `ShowSourceCenter`), Plan [FD](FD-camera-readiness-and-durable-actions.md) (visual evidence freshness), Plan
[DM](DM-privacy-safe-production-logging.md) (counts only in logs).

---

## Why

The partner ran three sessions against the code-book vault: tables asked for by number, the same
questions in plain words, and the rule chains end to end. Correction-factor tables worked, with
and without the table's number, including a missing input, a value between two printed rows and
a cell printed as a dash. The two rating tables never answered, both chains that were tried
stopped, and "show me the table" paid for a camera it did not use.

Everything below was read from the support reports and checked against the code and against the
private copy of the book on the Mac (which never enters the repo).

## Findings and causes

### 1. A revision mark beside a caption hides the table (cause confirmed)

The book marks a revised table with a small triangle in the margin, printed on the caption's own
line. `TableExtractor.caption(of:)` requires the line to begin with `TABLE` (and, on a page that
sets anything in bold, its first word to be bold), so the mark's word comes first and the line is
not a caption. In the newer edition that is most of the revised tables, including both rating
tables and the two the conduit-fill chain names (the import warning "needs tables … which the app
could not find"). The correction-factor tables carry no mark, which is why they work.

`ManualStructure.caption`, which names passages and decides which pages open, applies the same
rule to typed lines, so a passage on the table's grid page is not named for the table either.

**Plan JN revisited.** JN P1 found "nothing printed under the two captions" on the book's two
failing tables and concluded the copy held for measurement lacked the pictures. With the grid
page's caption invisible, the only caption JN's reader saw for each table was the one on the
continuation page, which carries notes and no grid. The grids are text and read once the caption
is found. JN's picture reader is still right for books that do print tables as pictures; its
"owed: a copy that prints the tables" item is closed by this plan, pending the measurement below.

### 2. "(Concluded)" is not read as a continuation (cause confirmed)

A table that runs over two pages is captioned "(Continued)" on the second page in some books and
"(Concluded)" in this one. `continuedPattern` knows only the first. A concluding page is read as
a table of its own with the same label. Today it is the only one found, so `table_lookup` cites
it and `show_source` opens it: the notes page, never the grid. Once finding 1 is fixed the two
would compete for one label.

### 3. Printed page numbers are not read for this book (cause confirmed)

`PrintedPageBand.label(in:)` accepts a header or footer line that is only a number. This book
prints the page number at the end of the footer line, after the date and the copyright notice, so
no page gets a printed label. `manual_figure`'s `page` is a printed page, and with no label it
falls back to the physical page. "Open printed page N" therefore opens PDF page N, which in this
book is the table index, a few pages before the table. That is what the partner saw when asking
for a rating table in plain words.

### 4. "Show me the table" starts the glasses camera (cause confirmed)

`VisionIntentDetector` lists "show me" as a vision phrase. With smart camera on, every "show me
the table" grabs a frame before the model is called. The glasses were added but not connected, so
the grab ran the three-attempt Meta permission check (about 8 seconds) and was then rejected.
That is most of the reported 24-second wait. Inside a Field Assist session whose last answer cited
manual pages, "show me …" means those pages: `show_source`'s job, not the camera's.

Separately, smart camera tries the glasses when the glasses link is down. The connection rule
("connected means `linkState == .connected`") says that capture cannot succeed, so the attempt
should not be made.

The camera that opened on "read the row on this page" was the model choosing `look_closely` for
"this page". The tool descriptions should say that a page shown from a manual is read with
`table_lookup` / `manual_lookup`, never the camera.

### 5. The highlight stays on the previous row (cause found in P0)

After a lookup that cited two rows (a value between two printed rows), `show_source` ran twice and
the page kept the row marked by the answer before. The model said the new rows were marked. P0
finds where the table lookup's rows are noted for "show me" (`ShowSourceCenter.noteTableLookup`)
and why an answer with two cited rows did not replace them. `show_source`'s result must also say
which rows it marked, so the model cannot claim rows it did not mark.

**Cause (P0).** Not the memory: `noteTableLookup` replaced the first answer's row with the two
rows of the between-rows lookup, keyed by the same table citation, and `show_source` staged the
page with both rows. The viewer dropped them. A sheet on screen was identified by its citation
alone (`AppState.ManualFigureRequest.id`), so the same table on the same page with other rows
was taken for the sheet already open: SwiftUI kept it, `ManualFigurePresentation` handed back the
controller cached under that id (whose model carried the first answer's marks), and the PDF
viewer's coordinator marks a page once and skipped the new passages. `show_source` running twice
changed nothing further — the second request was the same again. It only shows while the sheet
from the first "show me" is still up, which is how the partner asked.

### 6. Chains: rejected answers, a stopped chain that keeps asking, and a start that fails

The report's per-call character counts match the tool's fixed messages exactly, so the sequence
can be read:

- **An answer with its unit was refused.** A size said with its unit (e.g. "12 <unit>") was not
  taken where the chain asks for a size "as the table prints it"; the bare "12" was. The size
  matcher should drop a unit or size word the row keys do not carry (a unit name, "mm", "No.",
  "#").
- **The chain stopped at its table step, and the model kept collecting values.** The step's table
  was unreadable (finding 1), so the chain stopped and filed its read-back. The model then asked
  for the next value anyway, and later restarted the chain without saying so. The stop message
  must say plainly that the chain has ended, name the table it could not read, tell the model not
  to ask for further values, and say how to run it again.
- **"Start the chain called X" while another was running.** The tool said the conduit-fill chain was
  still running, the model stopped it, started the second chain, stopped that too, and told the
  technician to try again later. A technician who names a different chain to start means it. So
  `start` stops the running chain (nothing recorded, as `stop` does) and starts the named one,
  saying both.
- **A chain whose tables cannot be read is started anyway.** `list` already marks it ("needs …,
  it will stop at that step"). `start` does not, and the chain asks its questions before stopping.
  `start` refuses such a chain up front, naming the tables and offering to show their pages.
- **"List the chains" was summarised.** `list` returns every chain with its "answers" text, and
  the model summarised it as categories. The result should lead with the names, one per line, and
  tell the model to read the names out, since the technician starts a chain by name.

### 7. Smaller: several rows marked, two passages "couldn't be marked"

In the first session, "show me" on a correction-factor answer marked three ranges and reported that
two passages could not be marked. It did not recur in the second session. P0 checks whether it
is the same mechanism as finding 5. If not, it stays open here for P1.

**P0: a different mechanism, left open for P1.** Five passages on one page, three located, is not
a stale sheet. The likely path: the answer's `Source:` line named the page without the table's
label, so the citation had no `figure` and `AnswerSourceMemory.retrieved(for:)` fell back to every
passage the turn retrieved on that page (row passages and prose), not the rows the lookup read.
Two of those are prose or rows whose printed runs are not unique on the page, so they are not
located. Not reproduced from the report alone; P1 checks the turn's Source line in the partner's
re-run before changing which passages a page-only citation marks. `show_source` now names the
rows it marked and those it could not (item 5), so a repeat is visible in the report.

## Phases

### P0 — Headless fixes (this PR)

Deterministic, unit-tested, with invented fixtures only (a `Table 99` with a margin mark, a
footer line that ends with the folio):

1. **Margin marks before a caption.** `TableExtractor.caption(of:)` and `ManualStructure.caption`
   skip leading marks on the caption's line: a word with no letter or digit (a triangle, a bar, an
   arrow, a bullet) standing apart from the word `TABLE`. The bold rule applies to the first word
   after the marks. A sentence that merely begins with a symbol still has to pass every other
   caption rule.
   **✅ Built.** One rule, `TableExtractor.droppingMarginMarks` / `captionHead(of:)`: leading words
   of no letter or digit (or a lone Greek capital delta, which is how the triangle reaches the
   text layer) are skipped, and a mark glued to the word is cut; a bracket, a quote and a footnote
   marker are never marks. `TableExtractor.caption(of:)` reads the bold rule and the plain-page
   word limit from the first word after the marks; the figure stop in `layout` uses the same head;
   `ManualStructure.caption` (and its copy in `Scripts/extract-manual-text.swift`, self-checked)
   drops the marks before its pattern. Everything downstream reads labels, not line text.
2. **"(Concluded)" continues.** `continuedPattern` reads "concluded" (and "cont'd" / "continued"
   as now). A concluding piece with no grid joins the table it concludes and never stands in for
   it. Its notes join the table's notes where the reader already joins notes.
   **✅ Built.** `continuedPattern` reads "concluded". In `PDFTableReader.scan`, a continuing
   caption with no grid under it (too few rows, or no text) joins the last read table of its
   label — its notes (`TableExtractor.notes(under:words:)`) added when it is within two pages —
   and is otherwise left out when that table's own caption was kept unread; neither is a table or
   a failure (`Result.concludingPieces` counts them). The picture under it is still tried first,
   so a continuation whose rows are printed as a picture reads as before. A continuing caption
   with nothing before it is kept as before, and a continuation with rows merges as before.
3. **A folio that shares its footer line.** `PrintedPageBand` also takes a number at the outer end
   (first or last word) of a header or footer line. It is trusted for a document only when it runs
   in step with the physical page (a constant offset, held over a run of neighbouring pages), so a
   year or an edition number in the same footer is never read as a page. A lone-number line still
   wins as now.
   **✅ Built.** `PrintedPageBand.labels(bands:pdfLabels:)`, pure over each page's band text: the
   publisher's label, else a lone number (unchanged), else a number at a band line's first or last
   word whose offset from the physical page is held by a page within two either side and by at
   least three pages in the document; competing offsets go to the one more pages hold, a tie to
   none. `VaultDocumentExtractor.pageLabels(of:)` and the retrieval runner read through it. Every
   consumer (table pages, `manual_figure`'s printed page, `show_source`, `PageLabelMap`) reads the
   stored labels and is unchanged.
4. **"Show me" in a session with cited pages is not a camera turn.** While a Field Assist session
   is active and the last answer cited manual pages, a "show me / show the / open the" turn about
   a page, table, figure, row, source or passage does not trigger smart camera. Smart camera never
   starts the glasses capture while the glasses link is not connected (no frame, no 8-second
   permission attempts); the phone camera is not taken in its place without the wearer asking.
   The `look_closely` and `vision_assess` descriptions say a page open from a manual is read with
   the manual tools.
   **✅ Built.** `SmartCameraPolicy` (pure): with the last answer's citations in `ShowSourceCenter`
   for the active session (or the personal library's scope), a turn that puts a page, table,
   figure, row, source, passage, clause or diagram on screen ("show", "open", "bring up", "pull
   up", "go to", "highlight"), or a bare "show me (that)", takes no frame of any kind: routing
   (`expectsCameraImage`) and the grab (`smartCameraImageData`, cooldown follow-up included) both
   ask it first. Words naming the camera or the world in front ("in front of me", "look at",
   "what do you see") keep a camera turn. `smartCameraCapture` returns no image at once when
   `CameraService.isGlassesLinkUp()` is false (no phone swap), and its start now runs inside
   `CameraPermissionRequestPolicy.startedByApp`, so an automatic start never leaves for Meta AI.
   "Read the row on this page" is not covered: it names no show verb, and the model chose
   `look_closely` for it; the two descriptions now say a page open on the phone is read with
   `table_lookup` / `manual_lookup`. 4 tests in `SmartCameraPolicyTests`.
5. **Stale highlight.** Fix what finding 5 finds. `show_source` says which rows it marked.
   **✅ Built.** The sheet's identity is its citations plus what each page marks
   (`StagedFigure.marksKey`, `ManualFigureRequest.identity(of:)`), so other marks on the same page
   are a new sheet with a fresh controller; the same marks still do not blink it. The PDF viewer
   also re-marks when the passages it is handed change (`remarkCurrentPage`). `show_source` names
   the rows marked and those that could not be ("Marked on the page: row 7-9; row 10-12. Say only
   that these rows are highlighted.") from `TableRowPassage.rowName(ofSentence:)` and the locator,
   in place of the generic line. Tests: `TableLookupTests` (a between-rows lookup after a one-row
   one on the same page, end to end) and `ManualFigurePresentationTests`.
6. **Chains.** Unit words dropped from a size answer; an explicit stop message; `start` replaces
   a running chain; `start` refuses a chain whose tables cannot be read; `list` leads with names.
   **✅ Built.** `ChainRunner` retries a row lookup that found no row (not found, ambiguous, or a
   key read unclearly) once without the unit or size words no row key prints
   (`withoutSizeWords(_:keptBy:)`), taking the retry only when it finds the row; the read-back
   keeps what was said. A stop says the chain has ended and is not running, names the table of the
   step, and tells the model to ask for no more values and to 'start' it again only when asked.
   `start` with another chain running stops it (nothing recorded) and says both; the same chain
   again carries on and repeats its question; a chain whose tables are absent or unread
   (`RuleChainTool.unreadableTables`) is refused before anything starts, the unread table's page
   noted for `show_source`. `list` is the names, one per line, with short marks and a line to read
   them out (no "answers" text: the prompt carries it). Tests: 2 in `RuleChainTests`, 1 new and 3
   extended in `RuleChainSessionTests`, `ChainProposalSessionTests` updated for the list.
7. **Re-reading tables already imported.** The fix changes what is read from a PDF already in a
   vault, so the partner's vault must re-read its tables. P0 checks whether reindexing a manual
   (or re-importing the pack) re-reads them. If an automatic re-read on a reader change is small,
   it lands here; otherwise the release note tells the tester to reindex the code books, and an
   automatic re-read moves to P1.
   **✅ Built (automatic).** "Re-index manuals" and re-importing the same pack re-read nothing: the
   ledger skips a manual whose file hash is unchanged. The location migration already re-reads a
   stored manual's tables on launch when `DocumentStore.locationVersion` rises (JJ P1/P5, JN P1),
   so it goes to 7, and its tables-only path now also re-reads a PDF manual's printed page labels.
   The partner's vault re-reads both on the first launch of the new build, the text untouched. What
   it does not refresh is the passages' own figure names (the text is not re-chunked); a passage
   on a marked table's grid page is named for it only after the vault is removed and imported
   again. The table's row passages, which carry the label, are rewritten by the migration.

**Measurement (local only, never committed).** The private Mac runner reads the private book
before and after the fix. It reports, in counts only: captions found, tables extracted, pages with
a printed label, and the lookups that resolve on the partner's question set. The plan records the
counts, never a label, a title or a cell.

**What shipped (items 1, 2, 3, 7).** 21 new unit tests with invented fixtures (`Table 99` with a
margin mark on bold and one-weight pages, `Table 98A` concluded by a notes page, footers ending
"Example Standards Body N"): 11 in `TableExtractorTests`, 2 in `ManualStructureTests`, 7 in
`PassageLocationTests`, 1 in `TableStorageTests`. Measured on the private Mac copies, before →
after (counts only):

| Book | Captions found | Tables read | Captions not read | Pages with a printed label |
|---|---|---|---|---|
| Older edition | 161 → 172 | 77 → 88 | 84 → 84 | none → over 99% of pages |
| Newer edition | 139 → 179 | 56 → 87 | 83 → 92 | under 1% → over 99% of pages |

Every label read in both books has one offset from the physical page. The two tables of finding
1 that never answered now read, each cited on its grid page with no second entry under its label,
the concluding page's notes joined. "Captions not read" rises in the newer edition because marked
captions the reader never saw are now counted, some over grids the extractor still refuses
(varying column counts, rows too few); those are P1 material, not regressions. The lookups on the
partner's question set were not re-run in P0.

### P1 — Partner pass and what P0 leaves

A build with P0 goes to the partner with the same three sessions. Then:

- reindex or re-import, then the two rating tables by number and in plain words;
- "open printed page N" and "find the table" land on the grid page;
- "show me the table" carries no camera event in the report;
- both chains that stopped run to a result;
- finding 7, if P0 did not explain it;
- an automatic re-read of a vault's tables on a reader change, if P0 deferred it.

## Owner decisions taken (reversible)

- **`start` replaces a running chain** rather than refusing. The technician named the chain; the
  replaced chain records nothing, exactly like `stop`.
- **A chain whose tables cannot be read does not start.** Asking the technician three questions
  and then stopping is worse than saying up front which table is missing and offering its page.

## Privacy and licensed material

Fixtures use invented labels, values and wording. No table number, value, page number or phrase
from the partner's book appears in code, tests, this plan or the PR. Logs stay counts only.
