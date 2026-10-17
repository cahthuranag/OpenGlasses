# Plan IV — Manual Retrieval Rounds (every change measured on a field manual pair and a code book)

**Status:** 📝 Drafted 2026-10-17 — nothing implemented.
**Track:** Field Assist (B2B): every vault with manuals, and the regulations vertical in particular.
**Related:** Plans [ED](ED-vault-manual-retrieval.md) / [EJ](EJ-manual-retrieval-fidelity.md)
(manual retrieval and its evidence gate), [EK](EK-manual-structure-and-figures.md) (structure from
type), [P](P-chunk-citations.md) (page and section citations), [AM](embedding-quality-upgrade.md)
(the contextual embedder, default off), [IN](IN-verifiable-code-lookup.md) (P3 standards as a kind
and editions; P4 compare two editions), [HK](HK-controlled-document-revisions.md) (revisions and
`supersedes`), and the retrieval fix merged as
[#763](https://github.com/straff2002/OpenGlasses/pull/763) (page and common numbers aren't codes,
a lexical route, words-first ordering, a lookup miss that stops the search).
**Origin:** 2026-10-17. A tester's job on the Lennox furnace vault (the flame-sensor procedure that
was never retrieved) led to #763. The same day, a partner supplied two editions of an electrical
code book and a set of electrician exam sheets with the rule numbers written as answers, **for
testing only**. They were turned into a local answer key and a failure breakdown, measured against
the shipped retriever. The owner asked for the improvements to be generic, not specific to one code
book, and for every round to be checked against both measurements.

---

## How this plan was measured, and what is never shipped

Two measurements, run on the same retriever code the app ships (`VaultRetriever` over the
`DocumentStore` searches, the session's evidence gate), on both embedders: the device's sentence
model (`nl-sentence`) and the simulator's word-average fallback (`nl-word`).

- **Lennox calibration.** The 18 in-scope and 18 out-of-scope questions of
  `RetrievalGateCalibrationTests`, over the example vault's two manuals (present only on a
  developer's machine, as today). Recall@4 is a passage from an answering page among the four the
  model gets; insufficiency is an out-of-scope question correctly refused. This plan measures the
  production path (`retrieve(limit: 4)` through the shipped gate), which is slightly stricter than
  the calibration test's ranked-prefix method; the test's own numbers after #763 are recall@4
  0.889 and insufficiency 0.778 on `nl-word`.
- **Code-book answer key (local only).** 72 questions transcribed from the partner's exam sheets,
  each with the rule or table number the answer cites, over the code book's text. Hit@k is "a
  passage among the top k prints the expected rule or table". It is a sanity check, not a training
  set: no threshold here was tuned to it.

**Nothing from the code books, the exam sheets or the answer key is in this repository, in this
plan, in a fixture or in a log.** The publishers restrict copying, the copies are licensed to
individual users and were provided for testing only; every derived artefact was deleted when the
measurement was done. Only aggregate counts appear below. P0 describes how a developer rebuilds the
local eval from their own licensed copy.

## What happens today (`main` @ `2f2341756`, after #763)

| | Device (`nl-sentence`) | Simulator (`nl-word`) |
|---|---|---|
| Code book, newest edition only: hit@1 / hit@4 | 0.15 / 0.42 | 0.17 / 0.46 |
| Code book, both editions loaded (as the partner's vault is): hit@1 / hit@4 | 0.17 / 0.36 | 0.17 / 0.40 |
| Lennox: recall@4 / hit@1 | 0.56 / 7 of 18 | 0.89 / 13 of 18 |
| Lennox: out-of-scope refused | **0 of 18** | 14 of 18 |

"Device" is the device's embedding model, NaturalLanguage's English sentence model, run on a Mac
through the same retriever code. A phone run is owed (P0 makes it routine).

Two things stand out before any breakdown. Loading the older edition beside the newer one costs six
points of hit@4 on both embedders. And on the device, the evidence gate refuses nothing: the
sentence model's gate is the bare 0.30 floor, which EJ left "unmeasured, device run pending"
(`RetrievalEvidencePolicy.default(for:)`, `VaultRetriever.swift:639–646`).

### Why the code-book questions miss (newest edition only)

Each miss was put in the first class that fits, in this order: answer key (f), chunk boundary (c),
edition duplicates (d), ranking (b), recall (a). Multi-rule or calculation questions (e) are counted
as an overlay, because the one-rule test is the wrong test for them whatever the mechanism.

| Class | Device: count (% of 42 misses) | Simulator: count (% of 39) |
|---|---|---|
| (a) recall: the rule's own text is not in the top 30 candidates | 14 (33 %) | 13 (33 %) |
| (b) ranking: in the top 30, outranked | 20 (48 %) | 19 (49 %) |
| — own text at ranks 5–8 / 9–15 / 16–30 | 7 / 7 / 6 | 9 / 1 / 9 |
| (c) chunk boundary: the rule's continuation is in the top 4, without its number | 7 (17 %) | 6 (15 %) |
| (d) duplicates across editions crowding the top 4 | 0 (one edition) — 3 (7 %) with both | 0 — 3 (7 %) with both |
| (f) expected rule not printed in this edition | 1 (2 %) | 1 (3 %) |
| Overlay (e): question needs several rules or a calculation | 11 of the misses (17 such questions) | 9 of the misses |
| Overlay (f): answer-key doubt (handwriting, a teacher's correction) | 14 of the misses (27 such questions) | 14 of the misses |

What outranks the rule in the ranking misses is mostly other prose (70 of 80 top-four slots on the
device). Contents and index pages take 7 slots and number-dense tables take 3. With both editions
loaded, the other edition's copies take 24 of the slots (16 on the simulator).

**A mechanism found while classifying:** the code book prints each rule as its own line, the number
and a capitalised title, under a one-word group heading. The chunker joins sentences with a space
(`DocumentChunker.swift:118`), so the line break before the number is gone. `ClauseReference`
grades a clause as *starting* only after a line break or sentence punctuation
(`ClauseReference.swift:201–210`). A line such as "Wiring" followed by "12-345 Example title"
(a synthetic stand-in) reaches it as "Wiring 12-345 Example title" and grades as a citation.
Of the 57 expected rules the book prints as a heading, 16 (28 %) are never graded as starting
anywhere in it. So clause search can't lead with the rule's own text, and the chunk
that carries the rule's body (c) has nothing tying it to the number.

### What each lever does, on both measurements

| Lever | Code book hit@4 (device / sim) | Lennox recall@4 (device / sim), refused | Verdict |
|---|---|---|---|
| Baseline (#763, newest edition only) | 0.42 / 0.46 | 0.56 / 0.89, 0 / 14 of 18 | — |
| Newest edition only, against both loaded | +0.06 / +0.06 (from 0.36 / 0.40) | no effect (two manuals, not two editions) | **Adopt** (P2) |
| Dedupe near-identical passages across documents (both editions loaded) | +0.04 / +0.00 | no change | Subsumed by P2 |
| Clause-boundary chunking, only for clause-numbered documents | +0.04 / +0.04; hit@1 0.15→0.21 / 0.17→0.24 | no effect (not clause-numbered) | **Adopt** (P3) |
| The same split at *every* heading, all documents | — | +0.11 / **−0.06**, refused 14→13 on sim | Rejected: lowers Lennox |
| Lexical criterion in the device gate (the `nl-word` rule) | no change | no recall change; refused **0 → 15 of 18** | **Adopt** (P1) |
| Contextual embedder (`NLContextualEmbedding`, AM), against the sentence model | 0.47 (from 0.42); hit@1 0.24 (from 0.15) | **0.94** (from 0.56); with P1's gate 0.89, refused 14 of 18 | Measure on a phone, then adopt (P4) |
| Back-of-book index: question words → index entries → rules | alone 0.29 / 0.29; with the retriever, no gain | no index in these manuals | Not as a ranking source; as a hint (P5) |
| Model rewrites the question in the book's vocabulary (hand-written estimate) | 2 of 9 / 2 of 8 failed questions recovered | 6 of 8 / 1 of 2 recovered | Estimate only (P5) |
| A perfect reranker over the top 30 (upper bound) | ≤ 0.69 / ≤ 0.72 | — | Ceiling for P5 |

The index finds the rule for 7 (device) and 6 (simulator) questions the retriever missed, but
putting its passages into the four slots costs as many as it gains. The book's own index is better
used as a pointer the model can follow than as a passage.

## Verified starting point (`main` @ `2f2341756`)

- **Retrieval routes.** `VaultRetriever.retrieve` merges the embedding query, the exact-token
  search, the clause search and (since #763) the lexical route; groups are clause match, token hit,
  rest; within a group, shared content words lead and the score breaks ties
  (`VaultRetriever.swift`, `retrieve`). The per-turn block, `manual_lookup` and `equipment_lookup`
  all build it through `FieldSessionService.makeRetriever` (`FieldSessionService.swift:1576`).
- **The gate per backend.** `RetrievalEvidencePolicy.default(for:)` gives `nl-word` the measured
  lexical criterion and everything else the bare 0.30 floor (`VaultRetriever.swift:639–646`).
- **Documents have no edition.** `VaultDocument` has `file`, `title`, `kind` (free text,
  "informational"), `source`, `sourceUrl` (`VaultManifest.swift:150`). Two editions coexist only
  as two files with two titles. A vault's `prompt_rules` can tell the model to prefer one, but
  retrieval searches both, and their copies take slots before the model sees anything.
- **Chunking.** Sentences are packed to about 700 characters with a 100-character overlap and
  joined with a space (`DocumentChunker.swift:118`). A `## ` line sets the section but doesn't start
  a chunk. With no `## ` line at all, `detectHeading` guesses sections from numbered, chapter and
  all-caps shapes; it doesn't recognise `NN-NNN` rule numbers (IN P3a noted this).
- **Clause grading.** `ClauseReference.startsHere` needs a line start or sentence punctuation before
  the number (`ClauseReference.swift:201–210`).
- **The embedder.** `Embedder` prefers `NLContextualEmbedding` when
  `Config.contextualEmbeddingEnabled` is on (default **off**, `Config.swift:3892`) and its asset is
  present. Otherwise it uses the NLEmbedding sentence model, falling back to the word average.
  Stored vectors carry an `EmbeddingVersion`, so a model swap re-embeds lazily (AM).

## Decided

1. **The newest edition is the reference; an older edition answers only when asked.** This comes
   from the partner who supplied the code books and is not up for review here. When a vault holds
   the same document in more than one edition, retrieval searches the newest only. The older
   edition is searched, and labelled as such, only when the turn explicitly asks for it. That means
   it names the older edition's year or label ("the 2021 code"), says "the previous edition" or "the
   old code", or asks what changed or for a comparison ("what changed", "compare", "difference
   between editions"). IN P3 (the `edition` field) and IN P4 (`compare_editions`) are where editions
   become first-class; this plan supplies the default and the recognition, and IN P4 consumes them.

## Decisions proposed (owner to confirm)

2. **Every round is measured on both sets, and a lever that lowers either doesn't ship as stated.**
   Each phase's exit names the Lennox calibration (CI-skippable, as today) and the local code-book
   eval (a process, P0) on both embedders.
3. **Shape-specific levers detect their shape and otherwise do nothing.** Clause-boundary chunking
   needs a clause-numbered document, the edition default needs a document loaded in more than one
   edition, and an index hint needs a back-of-book index. A manual without that shape is untouched,
   so the Lennox numbers can't move for those phases, and the exit tests prove it.
4. **The device gate gets the lexical criterion now; the contextual embedder only after a device
   run.** The first is measured on the device's own model (simulated on a Mac with the same
   NaturalLanguage sentence model). The second changes every vector, so it waits for a run on a
   phone.

## Phases (one PR each), ordered by measured gain per effort

### P0 — The two measurements as a process

- `RetrievalGateCalibrationTests` gains a production-path column (`retrieve(limit: 4)` through the
  session's own retriever and gate) beside its ranked-prefix one, and prints the device-model
  numbers when it runs on a Mac or a phone with the sentence model. It still skips without the
  manuals.
- A local-only eval runner (an XCTest class that skips unless a developer points it at a folder):
  it reads the developer's own answer key (JSON lines: question, expected rule or table numbers,
  optional notes), imports the developer's own licensed copy into a temporary store, and prints
  hit@1, hit@4 and the (a)–(f) breakdown above. Nothing in it is content: the README says how to
  write an answer key from one's own study material, and the folder is gitignored like the
  manuals.
- **Exit:** both runs print on both embedders; with no manuals and no answer key, both skip cleanly
  in CI; the README describes the process without naming or quoting any book.

### P1 — The device's evidence gate (one default, the largest measured change)

- `RetrievalEvidencePolicy.default(for:)` gives `nl-sentence` the lexical criterion `nl-word`
  already has (minimum shared terms 3, scaled by `sharedFraction` 0.75). The comment records the
  measurement in place of "unmeasured". It is first because it is a one-line default with the
  largest measured effect: the device answers out-of-scope questions from whatever it retrieved,
  every time.
- **Exit:** Lennox calibration on the sentence model: out-of-scope refused 0 → 15 of 18, recall@4
  unchanged (measured 0.56 → 0.56). Code-book eval on the device: hit@4 unchanged (measured 0.42 →
  0.42). Both sets on `nl-word` unchanged, since its gate is untouched.
  `RetrievalGateCalibrationTests` asserts the `nl-sentence` default refuses more than the floor
  alone, as it does for `nl-word`.

### P2 — The newest edition by default (decided rule 1)

- An edition is recognised from the manifest (`edition`, or HK's `supersedes`, when present).
  Failing that, two documents of the same `kind` whose titles differ only in a year or an edition
  label are taken as editions of one work. The newest is the default; nothing is recognised as an
  edition when neither applies.
- `makeRetriever` searches the default edition unless the turn asks for an older one (decided rule
  1's phrases, and the older edition's own year or label). Then both are searched, and the older
  edition's passages carry its label in the citation.
- **Exit:** a synthetic two-edition fixture answers from the newest, answers from the older one
  when asked by year, by "previous edition" and by "what changed", and labels it. Code-book eval
  with both editions loaded: hit@4 rises to at least the single-edition number on both embedders
  (measured: 0.36 → 0.42, 0.40 → 0.46). Lennox calibration unchanged (two manuals, not editions).

### P3 — A rule starts where the book starts it (clause-numbered documents)

- The chunker keeps the line break between sentences that a line break separated, instead of a
  space, so `ClauseReference` can see a rule printed at the start of a line. This is generic, and is
  measured on both sets before anything else in this phase.
- **Shape detection:** a document is clause-numbered when enough of its lines are a clause number
  followed by a capitalised title (`NN-NNN`, `3.9.4.2`, `110.26`), using `ClauseReference`'s own
  recognition. Only then does each such line become a section heading that starts a new chunk, with
  no overlap carried across it. The rule is the chunk's section, so a citation names it (IN P3's
  clause-aware chunking, measured here). Re-chunking goes through IN P0's location migration (a
  text change re-chunks under the same document id).
- Splitting at every heading in every manual was measured and rejected: it lifted Lennox on the
  device but lowered it on the simulator (0.89 → 0.83, one fewer refusal).
- **Exit:** synthetic fixtures: a clause-numbered page whose rules start after a one-word group
  heading grades `.starts`, chunks one rule per chunk and cites it; a manual with numbered
  procedure steps ("1. Ignitor") is *not* detected as clause-numbered and chunks exactly as before.
  Code-book eval: hit@4 +0.04 and hit@1 +0.06 or better on both embedders (measured 0.42 → 0.46 and
  0.15 → 0.21 on the device; 0.46 → 0.50 and 0.17 → 0.24 on the simulator). The line-break join on
  its own lowers neither set on either embedder. Lennox calibration unchanged on both embedders.

### P4 — The contextual embedder, measured on a phone

- Run P0's two measurements on a device with `contextualEmbeddingEnabled` on, against the sentence
  model. Measured on a Mac with the same framework: code-book hit@4 0.47 against 0.42 (hit@1 0.24
  against 0.15), Lennox recall@4 0.94 against 0.56, and 0.89 with 14 of 18 refused under P1's
  gate. If the phone agrees on both sets, the default flips to on, the `nl-contextual` gate
  is calibrated the way P1 calibrated the sentence model, and the asset download (AM) is surfaced
  in vault setup.
- **Exit:** device numbers for both sets on both models recorded in this plan; the default flips
  only if neither set drops; the gate for `nl-contextual` refuses at least what P1's does.

### P5 — Helping the model search the book's way (estimates, measured last)

- What is left after P1–P4 is mostly ranking (the rule's text in the top 30, outranked) and
  vocabulary (the question asked in everyday words, the book written in its own). Hand-written
  rewrites into the book's vocabulary recovered 2 of 9 failed code-book questions and 6 of 8 failed
  Lennox questions on the device. A perfect reranker over the top 30 would reach at most 0.69 on
  the code book. These are estimates, so this phase starts by measuring.
- `manual_lookup`'s description asks the model to search in the document's own terms (the name of
  the part, the procedure, the table), and after a miss to try the book's word once, not a
  rephrasing. #763's miss guidance stays.
- **Index hint, for documents that have a back-of-book index** (detected: a trailing section whose
  lines are terms followed by clause or page references). `manual_lookup` appends one line naming
  the index's rules for the question's words. It takes no passage slot, and the model can follow it
  with a clause lookup, which IN P3a already serves. A document without an index gets no line.
- **Exit:** both sets measured with the model in the loop on a device (a scripted run of the
  failed questions through `manual_lookup`), and the phase ships only the parts that moved either
  set without lowering the other.

## Not in this plan

- Multi-rule and calculation questions (17 of 72 in the answer key). Answering them is IN P3's
  answer rules and the calculators it names, not retrieval.
- Answer-key doubt. The local eval prints it as its own class so that it isn't fixed by tuning.
- Shipping any code book, exam material or answer key, in any form (IN decision 6, EG, FS).
- A new embedding model or a dependency. P4 uses the framework model the app already has.

## Open questions for the owner

1. P2's edition recognition: is a title differing only in a year enough, or should a vault author
   always set `edition` (IN P3) before two editions can coexist?
2. P4: which phone, and with which vaults loaded, for the contextual run?
