# Plan IN — Code Lookup You Can Verify (open the cited page on request, the passage highlighted, editions compared)

**Status:** 🚧 P3a shipped 2026-10-17 (clause numbers found by number, the clause's own text
first); P0–P2, the rest of P3, and P4 unbuilt.
**Track:** Field Assist (B2B): a regulations vertical for electricians, and every manual user gets
the highlight.
**Related:** Plans [ED](ED-vault-manual-retrieval.md) / [EJ](EJ-manual-retrieval-fidelity.md)
(manual retrieval and its fidelity), [EF](EF-scanned-manual-import.md) (scanned pages),
[P](P-chunk-citations.md) (page and section citations), [GB](GB-field-test-round-3.md) (page
evidence: shown, opened, verified), [HK](HK-controlled-document-revisions.md) (document revisions:
`revision`, `effective_from`, `supersedes`), [HL](HL-revision-impact.md) (revision impact),
[IF](IF-photographed-manuals.md) (P2 in flight: physical-page evidence for photographed pages,
which shares the page-index question in §1), [FS](FS-subscriber-vaults-and-vault-links.md) (own
vaults, no redistribution), [IP](IP-organisation-feature-switches.md) (an organisation switches it
on).
**Origin:** Two conversations, 2026-10-16. At a startup festival in Auckland, electricians showed
the owner strong interest in checking work against the relevant regulations. Separately, a
partner's own electrician wants to load his region's electrical codes and ask questions instead of
searching the documents, and said he would pay for it. His priorities, in order:
1. a source reference with every answer (already done);
2. open the relevant PDF page **on request**, so he can verify without scrolling;
3. **highlight the exact supporting passage**, so he reads the requirement instead of the whole
   page;
4. optionally, compare two editions for a situation ("for this underground cable installation at a
   commercial site, what changed between these editions?"). It should cite both, or say it could
   not establish whether anything changed.

The partner added that this has to work on request: the phone may be in a pocket and the spoken
answer may be enough. When he wants to check, he says "show me the page" or "show me the relevant
pages".

---

## What happens today, for the partner's test

The partner is about to test whether "show me the page" works. Verified against `main` @
`8d0266ae0`, here is what he will find:

- **Auto-open fires only for diagrams.** In a Field Assist job, Direct mode, each turn's retrieval
  stages a figure only if a passage is a diagram or has a figure caption
  (`FieldSessionService.bestFigure`). `FigureAutoOpenPolicy` then opens it for "show me…"
  phrasing, or for a question that a diagram answers. **A prose passage, which is what a code
  clause is, is never staged**, so asking a code question does not open its page.
- **In Gemini Live and OpenAI Realtime there is no per-turn retrieval** (`promptContext()` has no
  turn there). A page opens only if the model calls `manual_lookup` and then `manual_figure`.
- **"Show me the page" works through `manual_figure`, with limits.** The model can call it with
  `page:` (or `figure:`, or `again: true` for the last one shown). It shows one page per call. A
  bare page number is looked up across every manual in the vault and takes the first hit, so with
  two code books loaded it can open the right page number in the wrong book. Tapping a citation chip
  opens the right page in the right document.
- **No passage is highlighted.** Nothing in the app uses `PDFSelection`, `PDFAnnotation` or
  `findString`.
- **Chat with your files (Document RAG, outside Field Assist) has no page viewer at all.** Its
  import takes plain text, so a PDF loaded there keeps neither its pages nor the file. Codes must be
  loaded as documents in a custom vault (Plan H) to get pages at all.

So the reply to the partner: the page shows when he taps the citation, or asks for a figure or
diagram. A spoken "show me the page" after a code answer may open the wrong book when two are
loaded. Nothing is highlighted yet. P0–P2 fix all three.

## Verified starting point (`main` @ `8d0266ae0`, 2026-10-16)

- **Chunks know their page, not their place on it.** `DocumentChunker.Chunk` holds `index`, `text`,
  `page`, `section`, `kind` and `figure`. The chunker computes offset-keyed breakpoints internally
  (`DocumentChunker.swift` around line 164) and discards them. `DocumentStore`'s `doc_chunks` rows
  have no character range. Chunk text is sentence-packed and overlapped, and
  `ManualStructure.render` adds or strips heading markers, so the chunk text is not a literal
  substring of the page.
- **Page numbers are physical.** `VaultDocumentExtractor` extracts each PDF page and joins them
  with a form feed, so `page` is the PDF index plus one. Comments say "printed page", but
  `ManualFigureAttachment.render` and `ManualPDFPageView` both use `page - 1` as the index. A code
  book whose printed page 112 is PDF page 130 is cited as "page 130".
- **The viewer.** `ManualFigureSheet` hosts `ManualPDFPageView` (a `PDFView`, `go(to:)`), with
  paging, a return-to-cited-page control and the audit log (`ManualPageSheetModel`,
  `ManualPageController`). When no PDF is bundled it falls back to extracted text pages. Evidence is
  recorded as `shown` for an app-opened page, `opened` for a requested one, and `verified` only on
  "Checked against manual" or a spoken confirmation (`PageEvidencePolicy`).
- **Citations are made in code.** `VaultRetriever.Passage.citation` gives "Title, page N, §Section".
  `CitationLineParser` reads "Source:" lines back into tappable `Citation`s (`CitationChips`).
  `openCitation` opens the page.
- **Documents have no edition.** `VaultDocument` has `file`, `title`, `kind` (free text, described
  as informational), `source` and `sourceUrl`. The ledger is keyed by file name plus content hash. A
  changed hash replaces the old chunks without saying so. Two editions can coexist only as two files
  with two titles. HK (revisions) and HL (impact, with section compare deferred) are drafted and
  unbuilt.
- **No electrical vault or standards handling.** Bundled vaults are health, IT network, notes and
  refrigeration. Plan F's "Electrical pack (v2)" is one roadmap line. Nothing in the code or plans
  mentions wiring rules, AS/NZS 3000, BS 7671, the NEC or the CEC.
- **Standards are licensed, and the app already behaves accordingly.** Vault packs never contain
  OEM manuals (Plan EG), `VaultExporter` omits documents, and FS decision 2 forbids in-app sharing.
  An electrician's purchased code is in the same position as an OEM manual: they load their own
  copy.

## Decisions proposed (owner to confirm)

1. **On request, not automatic, for standards.** A document of kind `standard` is never auto-opened
   by turn classification, whatever its passage kind. The partner's electrician wants the spoken
   answer to suffice and the page when he asks. Manuals keep today's diagram auto-open.
2. **"Show me" resolves against the last answer's citations, not a bare page number.**
   `show_source` takes `which` ("first", "second", "all", or a clause number such as "3.9.4") and
   resolves it against the citations of the most recent answer, by document id and page. It never
   searches every manual for a page number. `manual_figure` keeps its figure and `again` paths, and
   its `page` path gains a `document` argument.
3. **A highlight is only shown when it was found, never guessed.** The highlight comes from locating
   the passage's own text on the page. If it cannot be located (an OCR page whose PDF has no text
   layer, heavy reflow), the page opens with a plain line, "The passage couldn't be marked on this
   page", and no highlight. A wrong highlight is worse than none, because it would be read as the
   requirement.
4. **Cite the printed page and the clause; open the physical page.** Where a page label exists
   (`PDFPage.label`, or a printed number found in the header or footer during extraction), the
   citation says "AS/NZS 3000:2018, clause 3.9.4.2, page 112". The viewer opens the PDF index it
   maps to. Where there is no label it says "PDF page 130", not "page 130". This also settles the
   comment-versus-code disagreement above. IF P2 is touching physical-page evidence now, so the
   change is coordinated with that branch, not raced.
5. **Edition compare answers only from the two retrieved texts.** It never answers from what the
   model remembers about a code's history. Each side is cited by edition and clause. "I couldn't
   find this situation in the 2007 edition" is an answer, and so is "these clauses read the same".
6. **The organisation loads its own licensed copies.** No standard is ever in a pack, a bundle, a
   shared link or an office distribution beyond seats the organisation says it holds. A `standard`
   document is excluded from every export, like a manual.

## Phases (one PR each)

### P0 — Where the passage is on the page (headless core)

- The chunker keeps each chunk's character range within its page's extracted text, plus the
  sentence boundaries inside it. Both are stored in `doc_chunks` (`page_start`, `page_end`,
  `sentences` as a compact offset list). An `EmbeddingVersion`-style ingest version bump re-chunks
  existing vault documents on next launch through the ledger, so nobody re-imports anything.
- `PassageLocator` (pure): given a `PDFPage`'s `string`, the stored page text and a chunk's range,
  it returns the `NSRange`s on the PDF page by normalised matching. Whitespace, hyphenation at line
  ends, ligatures and quotes are folded, anchored on the first and last six words of each sentence,
  with a whole-sentence match required. A sentence it cannot anchor is dropped from the highlight,
  not stretched to fit.
- Page labels: `VaultDocumentExtractor` records `PDFPage.label` and a printed page number found in
  the top or bottom band when the label is absent (decision 4).
- **Exit tests:** fixture PDFs (a two-column standard-like layout with clause numbering, a
  hyphenated page, and an OCR'd page with no text layer) give exact ranges for the first two and a
  named `.notLocatable` for the third. Re-ingest migrates an existing store without losing evidence
  rows. Printed and physical page mapping is tested on a PDF with roman-numeral front matter.

### P1 — The highlight in the viewer

- `ManualPDFPageView` takes the located ranges and adds `PDFAnnotation` highlights per line
  (`PDFSelection.selectionsByLine()`) in the design kit's highlight colour, readable in light and
  dark. It scrolls the first one into view and zooms to page width. Highlights are view-only and
  never written into the PDF file.
- With several cited passages on one page, each is highlighted and numbered as it is in the spoken
  answer.
- The text-page fallback (no bundled PDF) highlights the same ranges in the extracted text.
- VoiceOver reads the highlighted passage first, then the page.
- **Exit tests:** snapshot tests of the annotated page in both appearances; the unlocated case
  shows its line and no annotation; evidence still records `opened` and `verified` as before.

### P2 — "Show me the page", "show me the relevant pages"

- `show_source` (`which`, optional `document`), registered in the Field Assist block and
  `FieldToolProfile`. It resolves against the last answer's citations (decision 2) and presents one
  page, or with `all` several pages, as a paged sheet. Each page carries its highlight and its
  clause. The tool description names the phrases "show me the page", "show me the relevant pages"
  and "show me clause …". It works in Direct, Gemini Live and OpenAI Realtime alike, because it is
  a tool, not turn classification.
- The answer's citations are kept per turn on the session (`lastAnswerCitations`), so "show me the
  second one" still works after a follow-up question that cited nothing.
- If the phone is locked or the app is in the background, the request is kept and a notification
  ("AS/NZS 3000, clause 3.9.4.2 — tap to open") opens the sheet. Nothing claims the page is showing
  when it is not, and the spoken reply says "It's on your phone."
- Decision 1's `standard` kind is respected by `FigureAutoOpenPolicy`.
- **Exit tests:** a scripted session with two code books loaded. A question cites book B, clause
  3.9.4; "show me the page" opens book B at the right page with the passage highlighted. "Show me
  the relevant pages" opens all three cited pages in order. A bare `manual_figure(page:)` without a
  document refuses by name when two documents have that page.

### P3a — Find a clause by its number ✅ (2026-10-17)

Pulled forward for the partner's electrician's test, because it fails on the first question he is
likely to ask. Before it, "what does clause 3.9.4.2 say" had no exact match at all:
`CodeTokenizer` keeps a decimal whole and never boosts on one (a reading, GB P1), and it split
"26-700" at the hyphen, so a rule number boosted every passage that printed a 26 or a 700. The
answer came from the embedder alone, which ranks a clause and its cross-references alike.

- `ClauseReference` (pure) recognises a clause in the question: two or more dots ("3.9.4.2"), any
  dotted or hyphenated number after a clause word ("clause 3.9", "rule 26-700", "section 110.26",
  "§ 210.8"), a dotted number with a subdivision ("210.8(A)"), and a bare `NN-NNN` rule. A spoken
  "3 point 9 point 4" or "26 dash 700" reads the same. A one-dot number alone, a voltage range
  ("208-230"), a model ("30RB-060") and a date are not clauses. Its pieces stay out of the token
  boost.
- Matching is the whole printed number with number-aware edges ("3.9.4" is not in "13.9.4",
  "2.3.9.4" or "3.9.40"), and grades how the passage holds it: **starts** it (number then a
  capitalised title, at a line or sentence start), starts a **subclause**, **continues** it (the
  chunk after the heading, or a later chunk of its section), or **cites** it. A contents page
  (entries run together with their page numbers, or dot leaders) only cites.
- `DocumentStore.passages(clause:)` returns that order, and `VaultRetriever` ranks clause hits ahead
  of code-token hits ahead of semantic ones. A book cross-references its busiest clauses dozens of
  times, so the token search's document order filled the limit before reaching the clause. Without
  a clause in the question the ranking is unchanged.
- `manual_lookup`'s description names clause numbers, so the model passes them as printed.
- **Tests:** `ClauseReferenceTests`. They cover recognition, readings that are not clauses, edges,
  starts against cites, contents pages, a 30-citation fixture where the old token search misses the
  clause and the new one leads with it and its continuation, and the ranking without a clause
  unchanged.
- **Not in P3a:** the citation still names the PDF page and the detected section heading. Clause
  headings in the `NN-NNN` form are not detected as sections, so a CEC rule cites its page only.
  Printed-page citations, the `standard` kind and the answer rules stay in P3.

### P3 — Standards as a document kind

- `VaultDocument.kind = "standard"`, with `edition` (a label such as "2018", "Amdt 2"),
  `jurisdiction` (free text shown to the user, never parsed) and HK's `revision`/`supersedes` when
  HK P0 lands. The custom-vault importer and the vault guide gain a "codes and standards" step.
- Clause-aware chunking: a heading that reads as a clause number (`3.9.4.2`) becomes the
  `section`, so citations name the clause. Clause numbers are indexed so "show me clause 3.9.4"
  and P4 can find them by number.
- Answer rules for `standard` passages, enforced in the prompt builder and checked in the citation
  parser: quote the requirement's operative words with the clause, never paraphrase a "shall"
  without it, and say "the code I have doesn't cover this" when nothing clears the floor. A
  standard is never outranked by a team learning; FP's safety rules apply at least as strictly.
- A starter "electrical" vault template with no standards text (decision 6) and a slot for the
  electrician's own code PDFs. Its first domain tool is a voltage-drop calculator, from Plan F's
  unbuilt "Electrical pack (v2)" line; the rest of that line stays out of this plan.
- **Exit tests:** clause-section extraction on the fixture; the "doesn't cover this" path; an
  answer missing its clause fails the citation check; the export omits `standard` documents.

### P4 — Compare two editions (optional, the partner's fourth priority)

- `compare_editions(situation, from_edition?, to_edition?)`. It retrieves the situation in each
  edition separately (clause numbers first, then semantic), pairs clauses by number and by
  similarity, and runs a pure text diff of each pair. The model then explains the differences using
  only the two retrieved texts (decision 5). A pair with no counterpart is reported as added or not
  found, never as unchanged.
- The answer cites both sides ("2007 clause 3.11.5.3 → 2018 clause 3.11.5.4"), and "show me" opens
  them side by side with each highlighted.
- **Exit tests:** two fixture editions with a known change, a renumbered-but-unchanged clause, a
  removed clause and a situation in neither. Each must give the expected verdict and citations.

## Acceptance

- The partner's electrician asks a code question with the phone in his pocket and hears the answer
  with its clause. He takes the phone out and says "show me the page". The right book opens at the
  right page with the requirement highlighted.
- With two code books loaded, no page ever opens in the wrong one.
- Asking what changed between two editions for a stated situation gives the clauses from both, or
  says it couldn't establish a change.
- No standard's text leaves the phone in any export, pack or bundle.

## Open questions for the owner

1. Which codes first? AS/NZS 3000 for the New Zealand and Australian interest, and the CEC or NEC
   for the partner's region. That decides the fixture layouts P0 is tested against.
2. Decision 6: do the standards publishers' licence terms for a purchased PDF allow loading it into
   an app on the licensee's own phone? Typically yes, for a single user, but this needs checking per
   publisher before the vertical is marketed.
3. Should regulation lookup be its own priced add-on for electrical organisations (the partner's
   electrician "would be willing to pay"), or part of the Field Assist tiers? Plan IP decides how it
   is switched, not what it costs.
