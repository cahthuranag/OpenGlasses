# Plan JY — Manuals in Every Interface Language (search keyed on the document's script)

**Status:** 🚧 P0 merged 2026-10-29 (PR 877): `DocumentLanguageProfile` (script by a weighted
letter count, then language by a constrained recogniser) is recorded per document in a nullable
`documents.language_profile` column and backfilled from stored text on first use, and `TermRule`
(`.english` unchanged, `.prefixStem` with per-language stopwords, `.arabicStem`, `.bigram`) now
cuts both the question and each passage under that document's rule in the term search, BM25F
statistics, the evidence gate, the back-of-book index and the table directory; `CodeTokenizer`
splits codes off Han, kana, Hangul, Cyrillic and Arabic letters. The gate's fractions for the
non-English rules are the English ones, provisional until P3. **P1 merged 2026-10-29 (PR
878):** each document is embedded with its own script's model (`EmbeddingScript`: Latin
unchanged, Cyrillic, Arabic, CJK, and Urdu on the model Apple maps `ur` to — measured below) or
with none, never another script's; a document whose model is missing is stored without vectors
and healed when it lands (`VaultEmbeddingUpgrade` per vault and script, lazily for the Documents
library); a vault keeps one index per (namespace, script); a passage awaiting its model is judged by
its words at the backend's shared fraction + 0.15 (provisional); My Manuals and Field Assist fetch
the phone's languages' script models ahead (`ScriptModelAssets`), and indexing waits at most 20 s
for a download under way. Each manual's language and "searching by words" state show in My Manuals
and Custom Vaults; every document's profile and model in the Developer panel and support report.
Semantic memory and voice skills stay on today's model (P1 item 5 deferred: one ranked list can't
mix two models' cosine scales, and a memory is too short to settle a script). **P2 merged 2026-10-29
(PR 879):** `manual_lookup` takes optional `queries` (the question rewritten per manual language)
and the searched manuals are searched once per language group, each with its own question, merged
by reciprocal rank with each group's gate verdict kept; the vault prompt, My Manuals and lookup
results name each manual's language, and a manual in another script that missed without a rewrite
gets a hint to retry in its language (`ManualLanguageSearch`). Deferred: `equipment_lookup`'s manual
fall-through and the nearest-headings search stay ungrouped, and whether each provider's model
fills `queries` is a device check. **P3 merged 2026-10-29 (PR 880):** calibrated on a parallel
baseline in 17 languages and technical documents in every language but Arabic and Urdu, English identical to `origin/main`: CJK drops
Japanese hiragana pairs and Korean particles from its bigrams (bigrams kept over `NLTokenizer` words);
Cyrillic, Latin and Arabic-script words lose one ending before their prefix (7 for Cyrillic and light
Latin, 6 heavy Latin, 4 Arabic script); heavy Latin's gate asks 0.75 of the question's terms, Arabic's
0.5; question words added for eight languages. hit@4 holds for CJK (230 of 322, out-of-scope refusals
52 → 64 of 135) and rises in every other group (Arabic 7 → 21 of 38, Cyrillic 79 → 92 of 163), with
out-of-scope refusals held or raised except Arabic and Urdu (−2, −1 of 15). Arabic and Urdu stay "less tested". The pending-vector increase stays 0.15 by decision 6, though
measured it only costs (decision owed). **P4 merged 2026-10-29 (PR 881):** a folio printed alone
on a line no longer renumbers an extracted page (the transport regulation's ru and zh-Hans answer
keys are back on the PDF's own pages); fake-bold doubled CJK characters are collapsed at extraction
and the line read as bold; caption and carrying-on words for every interface language; a heading
in a script without case may open with a caseless letter or be set larger than body, and a clause
number followed by a caseless letter is a clause heading; CJK chunks are 0.6 of the targets (420
characters) except in a clause-numbered document; an oversized CJK sentence breaks at its own
punctuation; a CJK or Arabic-script manual takes the six-passage budget. CJK S 333 → 376
(transport regulation zh-Hans hit@4 8 → 27 of 34 on true pages, en 24), Cyrillic 145 → 168, every
other group and all four English sets identical. Stored documents heal at location version 8.
**P5a merged 2026-10-29 (PR 883):** every remaining defect fixed or measured (results below):
a page whose text layer is only its furniture while its body is drawn goes to recognition (the
Arabic transport edition's 223 such pages; no page of any other set); a profile counts a
navigation-like line's letters at a quarter; `equipment_lookup`'s fall-through and the nearest
headings search by language group; a merge across languages keeps a six-passage best; dotted
caption labels are whole; full-width forms and Arabic-Indic digits fold to ASCII on both sides; a
two-pair fake bold is read off the glyphs; a recognised manual is re-read from the pages its import
kept and the Documents library gets the re-read from its own chunks; a chunk cites the page holding
most of it in every group but Cyrillic and heavy Latin; a bold/regular tie no longer makes extraction
differ from run to run. CJK S 376 → 386, light Latin 472 → 479, English 155 → 157, Cyrillic and heavy
Latin identical; Urdu clears "less tested" on a government technical document, Arabic stays marked.
Stored documents heal at location version 9. P5b (device and tester pass) owed.
**Drafted:** 2026-10-28. A tester in China asked about using My Manuals
with research papers. A check of build 581 found that a Chinese PDF indexes but can't be searched,
and a check of the other interface languages found the same problem in different strengths. The
plan was widened the same day, before merging, from Chinese, Japanese and Korean to all 19
interface languages.
**Track:** App-wide underneath. The first users are My Manuals and vault manuals. Documents (Plan
O) and semantic memory share `LexicalSupport` and `Embedder`, so they get the fix too.
**Related:** Plan [O](O-document-rag.md) (`DocumentStore`, `DocumentChunker`), Plan
[AM](embedding-quality-upgrade.md) (`EmbeddingBackend`, `EmbeddingVersion` self-heal), Plan
[EJ](EJ-manual-retrieval-fidelity.md) (the evidence gate and its calibration), Plan
[IV](IV-manual-retrieval-rounds.md) (contextual model P4, BM25F term statistics P7,
`Scripts/retrieval-eval`), Plan [JK](JK-my-manuals.md) (My Manuals), Plan
[IF](IF-photographed-manuals.md) (photographed manuals, whose OCR already follows the phone's
languages), Plan [EC](EC-ui-localization.md) (the interface's own translation; this plan is about
the documents).

---

## Why

The interface is translated into 19 languages: ar, de, en, es, es-MX, fr, fr-CA, hu, it, ja, ko,
nl, pl, pt-BR, ru, uk, ur, zh-Hans and zh-Hant. Manual search, though, was built and measured on
English. A manual in another language uploads, indexes and gets citations. Then it answers well,
badly or not at all, depending on the language, and the wearer has no way to tell why. For
Chinese, Japanese and Korean every question comes back as "the manuals don't cover this". For
Ukrainian, a question about a value printed in the manual was refused in the measurement below.

## Owner decisions (2026-10-28)

1. **Search follows the document's language, not the phone's.** A student in China may run their
   phone in English and read Chinese papers. A technician in Canada with an English phone may get
   a Japanese manual for imported equipment. Each document's script and language are detected
   when it's added. The phone's language is used for three things only:
   - which language models to download ahead of time,
   - the language the answer is spoken in,
   - the direction a question is rewritten in (P2).
2. **Manuals are never translated.** Translating a whole manual isn't accurate enough to answer
   from. When the question and the manual are in different languages, only the question is
   rewritten, which is a few words. The assistant reads the original page and answers in the
   wearer's language, citing that page, so a figure can be checked against it or with "show me".

## What happens today (checked 2026-10-28, build 581)

Each finding below was checked against the code and run on the Mac with Apple's own frameworks
(`NaturalLanguage`, the same models the phone uses). Every example is an invented sentence.

### 1. Extraction and splitting work for every language

`VaultDocumentExtractor` reads the PDF text layer page by page through PDFKit, so text and page
labels come through in any script. `DocumentChunker` splits sentences with
`NLTokenizer(unit: .sentence)`. Photographed manuals (Plan IF) already OCR in the phone's
preferred languages (`CapturedManualMedia.languages(preferred:)`).

### 2. The keyword rules are English rules applied to every language

`LexicalSupport.termSequence` makes a term from each run of letters of four or more characters,
removes an English stopword list and trims one English suffix (-ing, -ed, -es). It is applied
whatever language the text is in. The evidence gate (`RetrievalEvidencePolicy`) then requires
shared content terms for every shipped backend: `minSharedTerms: 3`, scaled by `sharedFraction`
(0.6 for the contextual model Field Assist uses, 0.75 for the others), and never fewer than 1. So
each language fails in its own way:

- **Ukrainian and Russian (the endings change).** "What is the maximum supply-air temperature?"
  against the passage that answers it: the question has four terms, and only повітря and подачі
  match exactly. максимальна vs максимальне and температура vs температуру don't. The gate needs
  three of the four, so the question is **refused**. Comparing the first 5 or 6 letters of each
  word instead matches all four. Apple has no Ukrainian lemmatizer: the tagger offers no lemma
  scheme for `uk`.
- **Polish and Hungarian** inflect the same way and fail the same way.
- **German** inflects less, but forms compounds. Comparing the first six letters still matches
  Temperaturfühler to Temperatur, but not Vorlauftemperatur.
- **Arabic** attaches the article and some prepositions to the front of a word (ال, و, ب), so the
  first letters are the clitic and not the word.
- **French, Spanish, Italian, Portuguese and Dutch** mostly work. Their endings vary less, but
  English stopwords and suffix rules do nothing for them, so a few matches are lost.
- **Chinese and Japanese (no spaces).** Only punctuation separates terms. A Chinese question
  (这篇论文用了什么方法来测量温度？) became one term, and its answer became one term per clause. They
  shared **0** terms. Even split into proper words with `NLTokenizer(unit: .word)`, the
  four-character minimum drops every Chinese word measured (0 of 18) and nearly every Japanese
  one (1 of 18).
- **Korean** separates words with spaces, but the grammar ending stays attached, so 온도를 and
  온도는 (both "temperature") don't match.

### 3. Every embedder is the Latin-script model, and Apple's other script models are never loaded

Every `Embedder` defaults to `language: .english`. That covers `Embedder.fieldAssist()`, the
store's `standardEmbedder`, `SemanticMemoryStore` and `VoiceSkillsTool`.
`prepareFieldAssistAssets` downloads only the English asset. Apple's contextual models are one per
script, measured on the Mac:

| Apple model (`NLContextualEmbedding`) | Interface languages it serves | Loaded by the app |
|---|---|---|
| Latin (`Latn`, 20 languages) | en, de, es, fr, hu, it, nl, pl, pt | Yes. Field Assist search uses it by default (`fieldAssistContextualSearchEnabled`) |
| Cyrillic (`Cyrl`) | uk, ru | No, and its asset wasn't on the Mac |
| Arabic (`Arab`: ar, ars) | ar | No |
| Indic (Deva, Beng and others). Apple maps `ur` to this model, though its scripts don't include Arabic | ur | No. Whether it reads Arabic-script Urdu is unmeasured |
| CJK (Hans, Hant, Jpan, Kore) | zh-Hans, zh-Hant, ja, ko | No (its asset was on the Mac) |

The older `NLEmbedding` sentence models, which the Documents library and a phone without the
contextual asset fall back to, exist for en, fr, es and pt only. de, it, nl, hu, pl, uk, ru, ar,
ur and zh return nil.

The English sentence model still returns a vector for Chinese text, but it's noise. The question
scored 0.968 against its answer and 0.965 against an unrelated sentence about the weather. Text
must never be embedded with a model for another script.

### 4. Code tokens stick to text in other scripts

`CodeTokenizer.wordPattern` is `[\p{L}\p{N}]+`. In 型号ABC123的 the whole string is one code-like
token, not `ABC123`, and the same happens in Cyrillic and Arabic text that has no space before a
model number. Today an exact model or fault code is the one route past the gate. It fails exactly
where a non-English manual needs it.

### 5. Detecting the language

`NLLanguageRecognizer` identified invented German, French and Polish sentences correctly. It
labelled a Chinese sentence containing "ResNet-50" and "ImageNet" as Catalan. Technical and
academic text mixes Latin terms into every script, so the script comes first, from a count of
characters. The recogniser is then asked to choose only among that script's languages.

### 6. Smaller mismatches (measured in P4)

- The chunker's heading heuristic counts uppercase letters. CJK, Arabic and Urdu have no case.
- `hardSplit` breaks an oversized sentence on spaces. CJK falls through to slicing by raw
  character count.
- The 700/900-character chunk targets hold about two to three times as much content in CJK as in
  English.
- Table captions match only `^TABLE` (`TableExtractor.captionPattern`, `ManualStructure.caption`).
  Other books print Tabelle, Tableau, Tabla, Tabela, Táblázat, Таблиця, Таблица, جدول, 表, 図 or 표.
- Traditional and Simplified Chinese don't match each other (溫度 vs 温度).
- CJK text may use full-width letters and digits (ＡＢＣ１２３).

## The design

### A profile for each document

When a document is added, `DocumentLanguageProfile` (pure) records three things:

1. **Its main script**, counted over the extracted letters: Latin, Cyrillic, Arabic, Han/kana,
   Hangul or other.
2. **Its language within that script.** `NLLanguageRecognizer` reads the whole text with
   `languageConstraints` limited to that script's languages. For Han text, kana means Japanese.
3. **A confidence.** When it's low, or no single language dominates, the document gets its
   script's default rule.
   **Latin needs more (P2, 2026-10-29):** a Latin document is named a language other than
   English only with at least 400 Latin letters and a recogniser confidence of at least 0.9;
   otherwise it keeps the English rule and searches with the English group, so an English vault
   stays byte-identical (a short crew note can read as Dutch or Italian). The accepted cost: a
   short German or French document is read as English. Other scripts keep 20 letters and 0.8.
   Stored profiles are recomputed (`currentVersion` 2).

The profile is stored with the document and shown nowhere except the support report and Developer
panel. It is recomputed when the document is re-indexed.

### Term rules by kind of language

`TermRule` has one rule per kind of language. Each document's passages use their document's rule,
and inside a passage each run of text uses the rule for its own script. So a Latin model number in
a Chinese passage is still read as Latin.

| Rule | Used for | What it does |
|---|---|---|
| `.english` | English documents, and Latin documents whose language is uncertain | Today's rule, **unchanged byte for byte**. Pinned by the existing calibration tests |
| `.prefixStem` | de, es, fr, hu, it, nl, pl, pt, uk, ru, ur | Lowercase, remove that language's stopwords, keep the first *n* letters (6 to start; P3 measures 5–7 per group). Words shorter than *n* are kept whole, with a per-language minimum length |
| `.arabicStem` | ar | Strip a fixed list of attached clitics (ال، وال، بال، كال، فال، لل), then `.prefixStem` |
| `.bigram` | zh-Hans, zh-Hant, ja, ko | NFKC, fold Traditional into Simplified, then overlapping two-character pieces. A single character stays whole. A short stop list removes question-word pieces (什么, 这篇, 어떤, です) |

- **Stopword lists:** short function-word lists written for this plan, one per language.
- **Questions:** a question is turned into terms once for each rule present among the candidate
  passages. Each passage is compared with the question's terms under its own rule, so the match
  is symmetric.
- **Gate:** `requiredSharedTerms` gets a fraction for each rule family. The English rule keeps its
  measured values, and the others are provisional until P3.

### Embedding by script

| Document script | Embedding model | When the model isn't on the phone |
|---|---|---|
| Latin | Latin contextual (today's) | Today's `NLEmbedding` fallback (en, fr, es, pt), else lexical only |
| Cyrillic | Cyrillic contextual | Lexical only |
| Arabic | Arabic contextual | Lexical only |
| Urdu | Whatever Apple maps `ur` to, once P1 measures that it reads Arabic-script Urdu. Lexical only until then | Lexical only |
| CJK | CJK contextual | Lexical only |

- **Never another script's model.** "Lexical only" means the passages are stored without a vector
  and tagged so the existing `EmbeddingVersion` self-heal embeds them once the asset lands. Until
  then the gate judges them under the stricter lexical rule (decision 6).
- **Mixed libraries already work.** `DocumentStore.QueryVectors` already embeds the question once
  per stored version tag, so each passage is compared with a question vector from its own model.

## Phases

### P0 — Profiles and term rules (deterministic core, headless)

1. `DocumentLanguageProfile`, with tests over invented text in every interface language and the
   mixed cases (Latin terms inside CJK, Cyrillic and Arabic).
2. `TermRule` with the four rules, per-language stopword lists, Arabic clitics, CJK normalisation
   and stop-bigrams. Questions are turned into terms per rule, and the gate gets a fraction per
   rule family (provisional).
3. `CodeTokenizer`: a letter from a non-Latin script separates code tokens, so 型号ABC123的 and
   модельABC123 yield `ABC123`. Latin text is unaffected.
4. Each document's profile is stored at ingest and backfilled for existing documents by reading
   their stored text. Term statistics are an in-memory cache rebuilt from chunk text
   (`DocumentStore.termStatisticsCache`), so no stored data needs migrating.
5. Tests:
   - English regression: every existing calibration and retrieval test passes unchanged.
   - One invented question/answer pair per language passes the gate, and the same question fails
     against an unrelated passage.
   - The Ukrainian case above, and the Chinese case from finding 2.

P0 is shippable on its own. Every language gets keyword answers before any embedding work.

### P1 — Embedding by script

1. At ingest, the profile chooses the model (the table above), and other-script models are never
   used. Passages are stored lexical-only and healed once the asset lands.
2. **Assets (decision 6): download the model so it's there when it's needed.**
   - When My Manuals or Field Assist is in use, the models for the phone's preferred languages'
     scripts are fetched ahead of time: when the feature is turned on or its plan starts, and
     again at launch if one is missing.
   - Adding a manual requests its own script's model too, if that one isn't already on the phone.
   - Indexing waits briefly for a download already under way, then finishes, and the self-heal
     adds the vectors when the model lands.
   - The download needs a network connection and is never a prerequisite for adding a manual.
     While a model is missing, the upload screen's indexing note says search will improve once
     the language model has downloaded.
   - Other surfaces (Documents, memory) use a model if it's already on the phone. They don't
     trigger downloads by themselves.
3. **Urdu:** measure whether the model Apple maps `ur` to reads Arabic-script Urdu. If it doesn't,
   Urdu stays lexical only. **Measured (2026-10-29): it does**, so Urdu uses it (`EmbeddingScript.urdu`).

   Measured on the Mac (2026-10-29), Apple's framework models with every asset requested, each
   question compared with an invented answer and an invented unrelated sentence, token vectors
   mean-pooled as `NLContextualBackend.embed` does. All models are 512-dimensional.

   | Model | Text | cos(q, answer) | cos(q, unrelated) | Margin |
   |---|---|---|---|---|
   | Cyrillic | Ukrainian, two pairs | 0.982, 0.893 | 0.911, 0.901 | +0.071, −0.008 |
   | Cyrillic | Russian, two pairs | 0.976, 0.937 | 0.953, 0.951 | +0.023, −0.014 |
   | Arabic | Arabic, two pairs | 0.871, 0.840 | 0.598, 0.689 | +0.273, +0.151 |
   | `ur` (Indic) | Urdu in Arabic script, three pairs | 0.895, 0.879, 0.875 | 0.709, 0.681, 0.688 | +0.186, +0.198, +0.187 |
   | Arabic | the same Urdu, two pairs | 0.959, 0.968 | 0.945, 0.939 | +0.014, +0.030 |
   | `ur` (Indic) | Hindi in Devanagari (control) | 0.884 | 0.671 | +0.212 |
   | CJK | Chinese, two pairs | 0.692, 0.862 | 0.583, 0.484 | +0.110, +0.378 |
   | CJK | Japanese / Korean | 0.765 / 0.777 | 0.588 / 0.607 | +0.178 / +0.170 |
   | Latin | English (control) | 0.926 | 0.808 | +0.118 |
   | Latin | Chinese (control) | 0.984 | 1.000 | −0.016 |

   The `ur` model reads Arabic-script Urdu as well as it reads Hindi, and the Arabic model reads
   the same Urdu as noise. **The Cyrillic model separates poorly**: its cosines sit between 0.89
   and 0.98 and two of four pairs score the unrelated sentence higher. It is still the only model
   that reads Cyrillic, so P1 uses it, but Cyrillic ranking leans on the term route and P3 should
   measure whether its vectors earn their place.
4. **Mixed-library test:** a test pins per-tag query vectors with Latin, Cyrillic and CJK
   documents in one store.
5. Documents, semantic memory and voice skills choose their model the same way, so a note or
   memory in Ukrainian isn't embedded as English.

### P2 — Questions in another language

Two languages' vectors can't be compared, and their terms don't match. `manual_lookup`'s result and
the vault prompt list each manual's language, and the tool description tells the model to phrase
`query` in the manual's language. When a lookup spans manuals in more than one language, it
searches once per language and merges the results. The answer is spoken in the wearer's language
and cites the original page (owner decision 2). No translation service is added.

**Built (2026-10-29).** `ManualLanguageSearch` (pure) and its callers:

- **Groups.** Each searched document's group is its profile's language (`en`, `de` … `zh-Hans`,
  `ja`, `ko`). An unsure Latin document and one in no interface script search with English, so a
  library of English manuals stays one group; an unsure Cyrillic document is its own group. A team
  learning never forms a group: it joins the reference group of its own language, else the
  largest (learnings alone are one group).
- **`queries`.** A list of `{language, query}` items beside `query` (a list, not a free-keyed
  object: every provider's schema form and the on-device bridge take a list of fixed-key objects).
  Read defensively: a `{code: query}` object is accepted too, a code in any case or with a region
  (`pt-BR`, `zh_TW`) or an English name is canonicalised, anything else is ignored, one rewrite per
  language, each cut to 400 characters. Simplified and Traditional stand in for each other.
- **Search.** One group: today's single retrieval, with that language's rewrite if one was passed.
  Several: a retriever scoped to each group's documents (`makeRetriever(scope:)`) searches with its
  rewrite or `query`, and the outcomes merge by reciprocal rank (k = 60), never by score, so a
  Latin passage at 0.95 doesn't bury a CJK group's best at 0.55. Only passages that cleared their
  group's gate merge; the lookup is insufficient only when every group is, and a sufficient merge
  keeps a manual passage. The per-turn prompt searches the same way, so a mixed vault no longer
  ranks two script models' cosines in one list. My Manuals already searched each selected manual on
  its own and interleaved them; each now gets its language's rewrite.
- **What the model reads.** The vault prompt (`MANUAL LANGUAGES`) and My Manuals' selection line
  list each manual's title (JSON, untrusted) with its language, and a lookup's result opens with
  the languages searched and their counts, all only when a manual isn't English. A group in
  another script than the question that found nothing without a rewrite gets one hint to retry in
  its language (it replaces the first miss's "don't rephrase" line; the second miss still says stop).
  The tool description asks for `query` in the manual's language and for `queries` when the manuals
  span languages, and to answer in the wearer's language citing the original page.

### P3 — Calibration by language group

Run `Scripts/retrieval-eval` for each group, in the order of decision 5: CJK, Cyrillic, the Latin
groups, then Arabic script. Use in-scope and out-of-scope questions and measure recall@4, hit@1 and
refusals, as EJ and IV did. Each run sets that group's prefix length, stopwords and shared
fraction, and its table is recorded in this plan.

**The sets (decision 7).**
- **Baseline: parallel texts.** The baseline is widely available literature published in many
  languages: openly licensed or public-domain texts in as many of the 19 interface languages as
  can be found. One question set with one answer key (the passage that answers each question) is
  written once and carried into each language, with a native-speaker check for the priority
  groups. Because the documents say the same thing in every language, one group can be compared
  with another directly.
- **What the baseline can't show.** Literature isn't laid out like a manual: it has no tables,
  model numbers or numbered sections. Each group's baseline is therefore followed by at least one
  real technical document in that language, held off-repo like the partner books, before the
  group drops its "less tested" mark.
- **Gaps.** Where no parallel text exists for a language, that group's measurement uses its own
  documents, and the table says so.

| Group | Languages | Rule |
|---|---|---|
| Latin, light endings | es, fr, it, nl, pt | `.prefixStem` |
| Latin, heavy endings or compounds | de, hu, pl | `.prefixStem` |
| Cyrillic | ru, uk | `.prefixStem` |
| Arabic script | ar, ur | `.arabicStem` (ar), `.prefixStem` (ur) |
| CJK | ja, ko, zh-Hans, zh-Hant | `.bigram` |

A group ships marked "less tested" (Developer panel and support report) until its set has been run.

**Built (2026-10-29).** Measured on the Mac runner (`Scripts/retrieval-eval`, now compiling the P0–P2
sources and each document's own script model) with every interface language's contextual model. Sets,
off-repo: a parallel baseline of five books of widely published literature in 17 languages (one chapter
a page; hu and pl have two books), and technical documents — a machinery regulation in nine Latin
languages (page-aligned), a transport-of-dangerous-goods regulation in en, ru and zh-Hans, a programming
tutorial in seven languages, and a national machinery regulation in uk. One English question set per
source (30–38 in scope, 15 out of scope, near misses among them), carried into each language with the
same pages; the translations are machine-written and owe a native-speaker check. Counts only below.

- **Rule for choosing.** A change is kept when S = hit@4 + 2 × out-of-scope refused − in-scope refused
  rises over the group's sets: the EJ/IV rule, a confident answer from the wrong manual weighing twice a
  missed one. One change at a time; a group stops after two changes in a row gain nothing.
- **English control.** Every English set gives identical numbers on `origin/main`'s code and on P3's
  (four sets, 139 in-scope and 60 out-of-scope questions): the English rule did not move.
- **Runner.** `RETRIEVAL_EVAL_PREFIX`, `_MINLEN`, `_ENDINGS`, `_FOLD`, `_CJK`, `_GATE_GROUP` and
  `_PENDING` set a group's candidate values (`Tuning.swift`, read only under `-D RETRIEVAL_EVAL`, which
  the app never defines); `RETRIEVAL_EVAL_VECTORS=pending` measures documents as searched while their
  script model is missing; `RETRIEVAL_EVAL_DETAIL=1` lists each question's expected and returned page
  numbers; the summary names each document's detected script, language and rule.

**Before → after, per group** (shipped values before P3 → after; English is the control):

#### CJK

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | zh-Hans | 38 | 24 → 24 | 29 → 29 | 29 → 29 | 3 → 3 | 10 → 10 of 15 |
| transport reg. | zh-Hans | 34 | 12 → 12 | 18 → 18 | 18 → 18 | 1 → 1 | 4 → 4 of 15 |
| tutorial | zh-Hans | 34 | 11 → 11 | 23 → 23 | 23 → 23 | 3 → 3 | 9 → 9 of 15 |
| baseline | zh-Hant | 38 | 24 → 24 | 29 → 29 | 29 → 29 | 2 → 2 | 10 → 10 of 15 |
| tutorial | zh-Hant | 34 | 12 → 12 | 24 → 24 | 24 → 24 | 2 → 2 | 10 → 10 of 15 |
| baseline | ja | 38 | 20 → 22 | 26 → 28 | 26 → 28 | 0 → 0 | 2 → 7 of 15 |
| tutorial | ja | 34 | 12 → 13 | 26 → 24 | 26 → 24 | 0 → 0 | 0 → 2 of 15 |
| baseline | ko | 38 | 22 → 23 | 30 → 31 | 30 → 31 | 1 → 3 | 5 → 8 of 15 |
| tutorial | ko | 34 | 16 → 15 | 25 → 24 | 25 → 24 | 1 → 1 | 2 → 4 of 15 |

#### Cyrillic

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | ru | 38 | 21 → 23 | 23 → 27 | 23 → 27 | 13 → 8 | 14 → 13 of 15 |
| transport reg. | ru | 34 | 18 → 17 | 25 → 26 | 27 → 29 | 1 → 1 | 7 → 6 of 15 |
| baseline | uk | 38 | 5 → 9 | 7 → 11 | 7 → 11 | 28 → 24 | 13 → 13 of 15 |
| tutorial | uk | 34 | 10 → 14 | 14 → 17 | 14 → 17 | 11 → 7 | 15 → 15 of 15 |
| national reg. | uk | 19 | 9 → 8 | 10 → 11 | 10 → 11 | 4 → 3 | 10 → 12 of 15 |

#### Latin light

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | es | 38 | 16 → 17 | 21 → 22 | 21 → 22 | 15 → 14 | 13 → 13 of 15 |
| machinery reg. | es | 33 | 16 → 16 | 25 → 23 | 25 → 23 | 3 → 2 | 10 → 12 of 15 |
| baseline | fr | 38 | 22 → 23 | 27 → 28 | 27 → 28 | 6 → 6 | 11 → 11 of 15 |
| machinery reg. | fr | 33 | 19 → 17 | 24 → 24 | 24 → 24 | 3 → 2 | 9 → 8 of 15 |
| baseline | it | 38 | 23 → 22 | 25 → 25 | 25 → 25 | 11 → 10 | 11 → 11 of 15 |
| machinery reg. | it | 33 | 19 → 20 | 25 → 25 | 25 → 25 | 0 → 0 | 11 → 12 of 15 |
| baseline | nl | 38 | 21 → 22 | 24 → 25 | 24 → 25 | 11 → 10 | 10 → 11 of 15 |
| machinery reg. | nl | 33 | 13 → 12 | 15 → 16 | 15 → 16 | 7 → 7 | 10 → 12 of 15 |
| baseline | pt-BR | 38 | 27 → 26 | 31 → 33 | 31 → 33 | 3 → 2 | 13 → 13 of 15 |
| tutorial | pt-BR | 34 | 18 → 17 | 25 → 24 | 25 → 24 | 0 → 0 | 15 → 15 of 15 |
| machinery reg. | pt | 33 | 19 → 17 | 25 → 23 | 25 → 23 | 1 → 1 | 10 → 11 of 15 |

#### Latin heavy

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | de | 38 | 16 → 17 | 22 → 25 | 22 → 25 | 14 → 12 | 12 → 14 of 15 |
| machinery reg. | de | 33 | 15 → 15 | 19 → 18 | 19 → 18 | 6 → 7 | 13 → 13 of 15 |
| baseline | hu | 18 | 6 → 7 | 8 → 8 | 8 → 8 | 9 → 8 | 12 → 15 of 15 |
| machinery reg. | hu | 33 | 12 → 15 | 14 → 16 | 14 → 16 | 5 → 4 | 10 → 11 of 15 |
| baseline | pl | 18 | 7 → 10 | 7 → 11 | 7 → 11 | 9 → 4 | 14 → 13 of 15 |
| machinery reg. | pl | 33 | 18 → 20 | 25 → 26 | 25 → 26 | 4 → 4 | 11 → 11 of 15 |

#### Arabic

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | ar | 38 | 7 → 17 | 7 → 21 | 7 → 21 | 27 → 12 | 13 → 11 of 15 |

#### Urdu

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | ur | 38 | 14 → 18 | 15 → 20 | 15 → 20 | 14 → 9 | 14 → 13 of 15 |

#### English

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | en | 38 | 20 → 20 | 25 → 25 | 25 → 25 | 9 → 9 | 11 → 11 of 15 |
| machinery reg. | en | 33 | 12 → 12 | 18 → 18 | 18 → 18 | 7 → 7 | 12 → 12 of 15 |
| transport reg. | en | 34 | 20 → 20 | 24 → 24 | 25 → 25 | 1 → 1 | 7 → 7 of 15 |
| tutorial | en | 34 | 15 → 15 | 24 → 24 | 24 → 24 | 3 → 3 | 12 → 12 of 15 |

**Chosen values** (each in code with its measured basis):

| Group | Prefix | Ending stripped | Gate (min, fraction) | Other |
|---|---|---|---|---|
| CJK | — | — | 3, 0.6 (backend's) | Japanese hiragana pairs and a Korean word's trailing particle leave the bigrams |
| Cyrillic | 7 | yes | 3, 0.6 | "when"/"what happened" question words added to the ru and uk stopwords |
| Latin light (es fr it nl pt) | 7 | yes | 3, 0.6 | question words added |
| Latin heavy (de hu pl) | 6 | yes | 3, 0.75 | — |
| Arabic | 4 | yes (one-letter proclitic and pronoun or plural ending) | 3, 0.5 | question words added |
| Urdu | 4 | yes (plural and oblique endings) | 3, 0.6 | — |

A Korean particle is stripped only while two syllables are left ("온도" keeps its 도; the first cut
stripped it, measured slightly higher, and was a defect). One ending (the longest of the group's list)
is stripped only while three letters are left (four for an
Arabic proclitic), so a word shorter than the prefix meets its other forms ("жінка" and "жінкою").

**What didn't help.** CJK: `NLTokenizer` words instead of bigrams (decision 2's alternative: Chinese
hit@4 within ±4 a set but out-of-scope refusals 39 → 23 of 60; Korean collapsed, words keep their
particles), minimum shared terms 2 (+16 hit@4, out-of-scope refusals 64 → 30 of 135) or 4, fraction 0.4,
dropping kanji–hiragana pairs too. Cyrillic: prefix 5, fraction 0.5 or 0.75, folding ё/ї/ґ (no change).
Latin light: prefix 5, fraction 0.5 or 0.75. Latin heavy: prefix 5 or 7, the question words (S −3).
Arabic script: prefix 5 or 6, dropping the one-letter pronoun endings; for Urdu, fraction 0.5 (tie) and
its question words (in-scope refusals 9 → 14). **Pending vectors** (`RETRIEVAL_EVAL_VECTORS=pending`):
for every group the words alone at increase 0 score the same as with the script model's vectors (CJK
and Cyrillic exactly), and the stricter rule only costs: 0.15 takes Cyrillic hit@4 90 → 82 for three more
out-of-scope refusals of 75, Arabic 4 hit@4 for one more out-of-scope refusal of 15, Urdu 1 for none; 0.3 is no better. CJK's
bigram questions are held by the minimum of 3, so the increase changes nothing there.
`pendingVectorFractionIncrease` stays 0.15 under owner decision 6; **the measurement argues for
revisiting it** (decision owed). The same runs say the non-Latin script models add almost nothing to
hit@4 on these sets beyond the words, which P1 suspected of the Cyrillic model.

**Defects found.** Fixed in the eval keys, not the app, and noted for P4:
- A footer folio printed alone on a line ("- 397 -") at the bottom of a page renumbers the next page and
  the extractor's own `Page N` marker after it is swallowed (`DocumentChunker`: a marker on a page
  opened with no content since is read as a running header). In the transport regulation's ru and zh
  editions 33 and 29 of 34 questions' answer pages are cited under other numbers (ru 5–7 pages early); English is unaffected only because its
  folios are not on lines of their own. A chunker fix moves English citations too, so it is P4's (or its
  own) change.
- Fake-bold text doubles every character in some Chinese headings (an invented example: "温温度度" for 温度), which breaks their
  bigrams (extraction; P4).
- The transport regulation's Arabic edition is image pages with only page furniture in its text layer,
  so Arabic has no technical document here (it needs Vision OCR, which supports Arabic).
- An HTML-derived Ukrainian tutorial whose table of contents and navigation outweighed the body was
  first detected as English (the body was then extracted properly); detection itself was right on every
  real document, including mixed Latin-and-CJK technical text.

**Where the numbers stay low.** zh-Hans answers 18 of 34 on the transport regulation against en 24 and
ru 26: its misses are ranking, close to the answer's page, which is P4's ground (headings without case,
chunk size, the doubled characters). Ukrainian's baseline is a 19th-century translation in an older
orthography, the only public-domain one (11 of 38); its technical sets read 17 of 34 and 11 of 19.
Arabic's baseline translation (21 of 38) is likewise old and has no technical set.

**Less tested.** Groups measured on a baseline and a technical document clear the mark: CJK, Cyrillic,
both Latin groups. Arabic (baseline only) and Urdu (no Urdu technical document has a text layer) stay
marked: the Developer panel's and support report's document lines end "· less tested", and a
`Less tested:` line counts them by group. No new interface strings.

### P4 — Structure in other-language books

Measured against the P3 sets before anything changes:

- **Captions.** Caption words for each interface language (the list in finding 6), plus
  continuation markers (Fortsetzung, suite, continuación, ciąg dalszy, продовження, продолжение,
  تابع, 续表, 続き, 계속).
- **Headings.** A heuristic that doesn't depend on uppercase: numbered section lines (第3章, 3.1,
  一、) and font size, where `VaultDocumentExtractor` already has it.
- **Chunk size and splitting.** Character targets per script, and `hardSplit` breaks CJK at
  、，；.
- **Passage budget.** `ManualPassageLimit` measured on CJK and Arabic text.

**Built (2026-10-29).** Measured on the P3 sets with the P3 rule (S = hit@4 + 2 × out-of-scope
refused − in-scope refused, one change at a time) on the Mac runner with every language's
contextual model. Counts only.

- **Footer folios.** In a document an extractor paginated (form feeds, or its own `Page N` lines), a
  folio printed alone on a line ("- 397 -") is furniture and never turns or renumbers a page
  (`DocumentChunker.isPrintedFolio`, `isExtractorPaginated`); a plain text paginated only by folios
  still turns at them. A page or section that opens inside a sentence's leading whitespace (a form
  feed after a line break) is now that sentence's, which the app's own form-feed path needed once
  the folio line went. The transport regulation's ru and zh-Hans keys are back on the PDF's own pages
  (checked against the PDFs: each question's first body page is in its key for 32 and 33 of 34; the
  rest are a section heading laid out differently and a UN number listed twice). On true pages P3's
  code answered ru 4 and zh-Hans 8 of 34; the fix alone gives 26 and 14. No English document in the
  sets prints a folio on a line of its own; every English chunk, page, section and figure is
  byte-identical.
- **Fake bold.** `OverprintedText` collapses a run of doubled pairs whose letters are all CJK, when it
  has at least three pairs over three different characters, or a doubled CJK punctuation mark beside
  a doubled letter; a line mostly set that way is bold. In the zh-Hans regulation 105 runs of three or
  more pairs and 31 of the 49 two-pair runs go; 18 two-pair runs are left as ambiguous. Latin,
  Cyrillic and Arabic text is never touched (every other extraction is byte-identical). zh-Hans
  hit@4 14 → 15.
- **Captions.** `CaptionWords`, read after the unchanged English rule in `TableExtractor.caption`,
  `ManualStructure.caption` and the Mac extractor: the table and figure words of every interface
  language (Hungarian number-first), labelled canonically ("Table 7"), and the carrying-on words,
  bracketed or ending the title, plus the prefix forms (续表, Продолжение таблицы, Fortsetzung
  Tabelle). ru 0 → 18 marked captions (tables and figures), zh-Hans 0 → 2 (most of its captions are
  not bold); ru hit@4 26 → 27, every other set unchanged.
- **Headings without case.** `ManualStructure.isHeading` lets a line whose first letter has no case
  open a heading, and lets it be one by size (1.2 × body) without bold, with CJK punctuation
  screened. Alone it tied (CJK S 340 → 340); with clause chunking it pays (zh-Hans regulation 24 →
  27), so it ships. The lexical patterns tried beside it (第3章, 一、, (一), 제1장, الفصل, a dotted number
  run into CJK) tied too, cost the Korean tutorial a hit@1, and were dropped.
- **Clause numbers without case.** `DocumentChunker.clauseHeadingLines` accepts a clause number
  followed by a caseless letter (`\p{Lo}`), so a CJK or Arabic code book is chunked at its clauses
  and sent six passages like an English one. Of every set only the zh-Hans regulation changes (0 →
  489 clause lines); hit@4 15 → 27, S +12.
- **Chunk size.** A CJK character carries 1.4–3.5 times an English one's content on these sets
  (non-space characters of the same text). CJK targets scaled: 0.4 → S 364, 0.5 → 368, **0.6 → 369**,
  0.75 → 359, per language (Chinese 0.3, Japanese and Korean 0.5) → 369, against 340 at 1; 0.6 ships
  for the group (420 characters a chunk), except in a clause-numbered document, which keeps today's
  targets (scaling it as well took the zh-Hans regulation 27 → 23). Cyrillic at 1.2 lost (168 → 161);
  every other script stays at 1.
- **Splitting.** `hardSplit` breaks an oversized CJK sentence after 。！？； (else ，、) in the second half
  of the window, and slices raw only where a piece has none; a run without CJK punctuation is sliced
  exactly as before. No sentence in any set reaches the limit (every chunk identical), so it is kept
  untested by the sets and covered by unit tests.
- **Passage budget.** With P4's chunking, a CJK manual's best passage taking six passages (the clause
  budget) answered 255 → 260 of the CJK in-scope questions as sent (five: 258) and Arabic script 41 →
  44 (five: 41), at 1,395 → 1,857 and 1,533 → 1,955 characters a question, under English's 2,200 with
  four. `DocumentStore.usesClausePassageBudget` gives a CJK or Arabic-script manual the six; Latin
  and Cyrillic keep four.

**Before → after, per group** (before: P3 as merged, the transport regulation on true pages; after:
P4; "as sent" with P4's budget):

#### CJK

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | zh-Hans | 38 | 24 → 24 | 29 → 31 | 29 → 32 | 3 → 4 | 10 → 12 of 15 |
| transport reg. | zh-Hans | 34 | 6 → 15 | 8 → 27 | 8 → 26 | 1 → 1 | 4 → 4 of 15 |
| tutorial | zh-Hans | 34 | 11 → 14 | 23 → 25 | 23 → 25 | 3 → 3 | 9 → 10 of 15 |
| baseline | zh-Hant | 38 | 24 → 23 | 29 → 30 | 29 → 30 | 2 → 3 | 10 → 12 of 15 |
| tutorial | zh-Hant | 34 | 12 → 14 | 24 → 27 | 24 → 29 | 2 → 3 | 10 → 11 of 15 |
| baseline | ja | 38 | 22 → 21 | 28 → 30 | 28 → 31 | 0 → 1 | 7 → 6 of 15 |
| tutorial | ja | 34 | 13 → 15 | 24 → 28 | 24 → 28 | 0 → 0 | 2 → 2 of 15 |
| baseline | ko | 38 | 23 → 24 | 31 → 32 | 31 → 33 | 3 → 3 | 8 → 8 of 15 |
| tutorial | ko | 34 | 15 → 17 | 24 → 26 | 24 → 26 | 1 → 2 | 4 → 5 of 15 |

**S** 333 → 376

#### Cyrillic

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | ru | 38 | 23 → 23 | 27 → 27 | 27 → 27 | 8 → 8 | 13 → 13 of 15 |
| transport reg. | ru | 34 | 1 → 17 | 4 → 27 | 4 → 29 | 1 → 1 | 6 → 6 of 15 |
| baseline | uk | 38 | 9 → 9 | 11 → 11 | 11 → 11 | 24 → 24 | 13 → 13 of 15 |
| tutorial | uk | 34 | 14 → 14 | 17 → 17 | 17 → 17 | 7 → 7 | 15 → 15 of 15 |
| national reg. | uk | 19 | 8 → 8 | 11 → 11 | 11 → 11 | 3 → 3 | 12 → 12 of 15 |

**S** 145 → 168

#### Latin light

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | es | 38 | 17 → 17 | 22 → 22 | 22 → 22 | 14 → 14 | 13 → 13 of 15 |
| machinery reg. | es | 33 | 16 → 16 | 23 → 23 | 23 → 23 | 2 → 2 | 12 → 12 of 15 |
| baseline | fr | 38 | 23 → 23 | 28 → 28 | 28 → 28 | 6 → 6 | 11 → 11 of 15 |
| machinery reg. | fr | 33 | 17 → 17 | 24 → 24 | 24 → 24 | 2 → 2 | 8 → 8 of 15 |
| baseline | it | 38 | 22 → 22 | 25 → 25 | 25 → 25 | 10 → 10 | 11 → 11 of 15 |
| machinery reg. | it | 33 | 20 → 20 | 25 → 25 | 25 → 25 | 0 → 0 | 12 → 12 of 15 |
| baseline | nl | 38 | 22 → 22 | 25 → 25 | 25 → 25 | 10 → 10 | 11 → 11 of 15 |
| machinery reg. | nl | 33 | 12 → 12 | 16 → 16 | 16 → 16 | 7 → 7 | 12 → 12 of 15 |
| baseline | pt-BR | 38 | 26 → 26 | 33 → 33 | 33 → 33 | 2 → 2 | 13 → 13 of 15 |
| tutorial | pt-BR | 34 | 17 → 17 | 24 → 24 | 24 → 24 | 0 → 0 | 15 → 15 of 15 |
| machinery reg. | pt | 33 | 17 → 17 | 23 → 23 | 23 → 23 | 1 → 1 | 11 → 11 of 15 |

**S** 472 → 472

#### Latin heavy

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | de | 38 | 17 → 17 | 25 → 25 | 25 → 25 | 12 → 12 | 14 → 14 of 15 |
| machinery reg. | de | 33 | 15 → 15 | 18 → 18 | 18 → 18 | 7 → 7 | 13 → 13 of 15 |
| baseline | hu | 18 | 7 → 7 | 8 → 8 | 8 → 8 | 8 → 8 | 15 → 15 of 15 |
| machinery reg. | hu | 33 | 15 → 15 | 16 → 16 | 16 → 16 | 4 → 4 | 11 → 11 of 15 |
| baseline | pl | 18 | 10 → 10 | 11 → 11 | 11 → 11 | 4 → 4 | 13 → 13 of 15 |
| machinery reg. | pl | 33 | 20 → 20 | 26 → 26 | 26 → 26 | 4 → 4 | 11 → 11 of 15 |

**S** 219 → 219

#### Arabic

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | ar | 38 | 17 → 17 | 21 → 21 | 21 → 21 | 12 → 12 | 11 → 11 of 15 |

**S** 31 → 31

#### Urdu

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | ur | 38 | 18 → 18 | 20 → 20 | 20 → 23 | 9 → 9 | 13 → 13 of 15 |

**S** 37 → 37

#### English

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | en | 38 | 20 → 20 | 25 → 25 | 25 → 25 | 9 → 9 | 11 → 11 of 15 |
| machinery reg. | en | 33 | 12 → 12 | 18 → 18 | 18 → 18 | 7 → 7 | 12 → 12 of 15 |
| transport reg. | en | 34 | 20 → 20 | 24 → 24 | 25 → 25 | 1 → 1 | 7 → 7 of 15 |
| tutorial | en | 34 | 15 → 15 | 24 → 24 | 24 → 24 | 3 → 3 | 12 → 12 of 15 |

**S** 155 → 155

**Healing stored indexes.** `DocumentStore.locationVersion` is 8: `PassageLocationMigration` reads
every vault document's text again once (it previously re-read only the tables from version 3 on).
Where the text chunks as stored — every English document, since no English rule changed — the rows
keep their ids, text and vectors, and `writeLocations` now also rewrites page, section and figure,
which is how a folio-moved page comes back without a re-index. A document whose text changed (a CJK
book: collapsed doubling, smaller chunks, clause chunks) is re-chunked under its own id and
re-embedded with its script's model. A document read by recognition is skipped as before; the
Documents library outside vaults is not migrated (both in P5a). No per-language version was needed:
the text comparison is what keeps English rows untouched.

### P5a — Every remaining defect (headless; after P4 merges)

Each item: evidence (counts only), and the test that proves the fix.

1. **An image-only edition is never recognised.** The transport regulation's Arabic edition has 488
   pages, none empty, 251 with under 160 non-space characters (page furniture only); recognition
   runs only on an empty page (`VaultDocumentExtractor.extract(from:reader:)`, and the Mac extractor
   outside the office worker), so its body never reaches the index. Vision reads Arabic; Plan IF's
   photographed-manual reading may live in another session's branch, so check before building.
   Test: a fixture PDF whose page carries only a folio in its text layer is sent to the reader.
2. **Navigation outweighs the body.** An HTML-derived Ukrainian tutorial whose contents and
   navigation outweighed the body was detected as English (P3). Test: a profile of an invented page,
   three quarters Latin navigation and one quarter Cyrillic body, names the body's language or none.
3. **Ungrouped searches.** `equipment_lookup`'s manual fall-through and the nearest-headings search
   are not grouped by language (P2 deferral). Test: a two-language vault answers each through its
   own group's question.
4. **A merged multi-language result is cut to four.** `retrieveByLanguage` merges the groups with
   `limit: passageLimit.prose`, so a group whose best passage takes six (a clause-numbered or, since
   P4, a CJK or Arabic-script manual) is cut to four once a second language is searched. Test: a
   vault with a Chinese and an English manual sends six when the Chinese passage ranks first.
5. **Dotted caption labels are cut.** A caption "Table 2.7.2.2.1" is labelled "Table 2" with the rest
   as its title (`TableExtractor.labelPattern`): 12 of 12 table captions in the English regulation,
   7 of 7 in the Russian; every such table shares one label. Test: two captions differing past the
   first dot keep separate labels, and an English code book's labels do not move.
6. **Full-width letters and digits are not folded** (finding 6: ＡＢＣ１２３). Test: a full-width model
   number in a CJK passage meets the ASCII one in a question.
7. **Two-pair fake bold.** 18 two-pair doubled runs stay in the zh-Hans regulation, where a
   reduplicated word cannot be told from an overprinted one by the text; the type (two glyphs drawn
   a hair apart) could. Test: an overprinted two-character heading collapses, 高高兴兴 does not.
8. **Recognised and library documents keep pre-P4 structure.** The location migration skips a
   document read by recognition and never sees the Documents library outside vaults, so a folio
   there keeps its moved page until re-imported. Test: a recognised fixture with a folio line is
   re-paginated without being recognised again.
9. **A chunk cites its first sentence's page.** Of the zh-Hans regulation's misses before P4's
   clause chunking, 10 of 19 returned a page within three of the answer's, many a chunk that crosses
   into the answer's page; English shares the rule. Test: a chunk crossing a page break is credited
   to (or split at) the page that holds most of it, English measured alongside.
10. **Caseless headings found only from type.** The lexical caseless patterns tied and were dropped,
    so a plain-text or recognised CJK, Arabic or Urdu book still gets no sections. Test: a recognised
    page's 第3章 line sets the section, once a variant measures above a tie.
11. **No Arabic or Urdu technical document with a text layer**, so their clause rule, captions and
    budget are measured on the literary baseline only; both stay "less tested".

**Built (2026-10-29).** Measured on the P3 and P4 sets with the P3 rule (S = hit@4 + 2 ×
out-of-scope refused − in-scope refused, one change at a time) on the Mac runner with every
language's contextual model, plus two new technical sets (below). Before is P4 as merged. Counts
only.

1. **Furniture-only pages go to recognition — fixed.** A page is sent to the reader when its text
   layer is empty, as before, or when it is only its furniture — under 20 non-space characters once
   lines with no letters (a folio) and lines repeated on three or more pages (a running header or
   copyright line) are set aside — **and** its body band is inked: at least 2% of the band between
   the header and footer bands darker than 200 of 255 at 36 dpi
   (`VaultDocumentExtractor.pagesNeedingRecognition`, the Mac extractor alike). The Arabic transport
   edition's 247 furniture-only pages ink 2–16% on 223 (outlined glyphs) and under 0.2% on the rest
   (blank); every furniture-only page of the English, Russian and Chinese editions (18, 21, 26: blank
   pages with the copyright line) inks under 2%, and the machinery and Ukrainian regulations have
   none, so **no page of any other set is recognised** and their extractions are byte-identical.
   The Arabic edition, re-extracted on the Mac with Vision's Arabic recogniser (223 pages, mean
   confidence 0.89 on a checked page), got a machine-written answer key built as P3's were (31 of
   the 34 in-scope items resolved by clause number, 15 out of scope; native check owed): hit@4 7 → 6
   of 31, in-scope refused 9 → 2, out-of-scope refused 14 → 7 of 15 (S 26 → 18). The other 241 pages
   carry a text layer whose letters are mis-mapped (a broken font encoding: the words do not read
   as Arabic), which no page rule can see, so the edition is half readable either way and Arabic
   stays "less tested"; a check of a text layer against recognition is new work for P5b or later.
   The fall in S is fewer refusals of out-of-scope questions once half the book is readable; the
   fix is kept because the pages it reads were missing from the index. On the way, the Mac
   extractor's recognition stopped answering after a few hundred pages (175 of 223 pages empty in
   one run): its renders and Vision requests now drain page by page, and a request that cannot start
   is tried twice more.
2. **Navigation outweighs the body — fixed.** `DocumentLanguageProfile.letterCounts` counts a line
   with under 24 weighted letters (a menu entry, a breadcrumb, a contents line) at a quarter. No
   document in any set changes script or language (every share holds or rises: the HTML-derived
   Ukrainian tutorial 0.52 → 0.55); an invented page of three quarters Latin navigation and a
   quarter Cyrillic body is now Cyrillic. Profiles are recomputed (`currentVersion` 3).
3. **Ungrouped searches — fixed.** `equipment_lookup`'s manual fall-through goes through
   `retrieveByLanguage` with its own three passages (`fixedLimit`), and the nearest-headings search
   takes each group's headings for its own question (its rewrite, else the question), first of each
   before the second of any. One language: as before.
4. **A merged result cut to four — fixed.** The groups merge at the larger budget and the merge is
   shaped by its best passage (`ManualPassageLimit.shaped`), so a Chinese manual's first passage
   keeps six beside an English manual. Every set is one language, so no number moves.
5. **Dotted caption labels — fixed.** `TableExtractor.labelPattern` keeps up to six dotted parts
   ("Table 2.7.2.2.1"); a full stop before a title is not one. Distinct table labels in the transport
   regulation's English edition 2 → 12 of 12 captions, Russian 2 → 7 of 7; figure labels 3 → 13,
   3 → 8, Chinese 2 → 4. `TableReference` reads the dotted number in a question. A code book's
   labels ("Table 2", "Table 4B", "Table 12." before a title) do not move (tested on invented
   captions shaped like them). English results identical: a verified correction (the PDF prints the
   dotted numbers) at no cost.
6. **Full-width forms — fixed.** `CodeTokenizer.foldedForms` reads ＡＢＣ１２３, the ideographic space
   and Arabic-Indic digits as ASCII in code tokens, token containment and the English term rule (the
   other rules fold by NFKC already), on both sides. No set's numbers move.
7. **Two-pair fake bold — fixed, by the glyphs.** PDFKit's selection bounds give each character's
   box: an overprinted pair's copies start 0.4–0.6 em apart, a CJK character's advance to the next
   is 0.9–1.1 em (0.6% outside), so a doubled CJK pair under 0.7 em is one glyph printed twice
   (`OverprintedText.collapsed(_:advance:)`, fed by `ManualStructure.typedPage`). In the zh-Hans
   regulation the two-pair runs left 18 → 1 and lone doubled pairs 190 → 62 (the rest drawn a full
   glyph apart); headings 196 → 203; results identical. **Found on the way:** a line whose bold and
   regular runs tie (a bold clause number beside a title in a substituted regular font) took the
   dictionary's order, which changes per process, so P4's extraction of one PDF differed from run
   to run (three extractions of the zh regulation, three texts; English one line). A tie now reads
   bold every time (bold and regular measured alike: every set identical).
8. **Recognised and library documents — fixed.** The import keeps a recognised manual's pages
   (the OCR record it already wrote, now removed only with the manual), and location version 9
   reads such a manual again from them, never recognising it twice; one imported before they were
   kept is still left as it is, and needs a re-import for P4's pages. The Documents library outside
   vaults is read again from its own chunks (`DocumentStore.reconstructedText`: each chunk's
   recorded sentences, the overlap dropped, a page break where a chunk's page moves on) for CJK and
   Arabic-script documents, whose chunking P4 changed; every other library document is only
   stamped, its rows untouched. Text that chunks as stored keeps its rows and vectors.
9. **Page credit — majority, by group.** Measured on one index, only the pages rewritten
   (`RETRIEVAL_EVAL_RELOCATE`): crediting a chunk to the page holding most of its characters gave
   CJK 376 → 386, light Latin 472 → 479, English 155 → 157, Urdu up, Arabic tied, but Cyrillic
   168 → 167 and heavy Latin 219 → 218. It ships for every group but those two
   (`DocumentChunker.creditsMajorityPage`). English is a verified correction: of 40 re-credited
   chunks of the English transport regulation sampled against the PDF, more of the chunk's text is
   on the new page for 27, on the old for 4, equal for 9; its PDF sets' numbers do not move, and
   the tutorial's rise (24 → 27) outweighs the baseline's 25 → 24. **Lost:** a share threshold
   (two thirds: Cyrillic 166, heavy 217; four fifths: 166, 218) and splitting at every page break
   (re-indexed: Cyrillic 168 → 158, light 472 → 469, heavy 219 → 205, Arabic down; CJK +1, Urdu up).
   **Within one section only** (found by CI, `ShowSourceTests`): a chunk running from one section's
   tail into the next section on the next page was cited at the next page under the first section,
   so "show me clause 3.9.4" opened two pages. The page now moves only when the majority page's
   first sentence is in the chunk's own section; re-measured, every set in every group with the
   credit is identical. Test: `testAChunkRunningIntoTheNextSectionOnTheNextPageKeepsItsFirstPage`.
10. **Caseless headings from their shape — not kept.** Chapter and section words with numbers
    (第3章, 第二节, 제3장, الفصل), counted items (一、, （二）) and a clause number run into a caseless
    letter, as sections in a document without type: every group's S tied (no set moved), so the
    patterns are not in the app.
11. **Less tested — Urdu cleared, Arabic not.** No Urdu law P3 found has a usable text layer; a
    government ministry's published Urdu report does (an environmental and social impact
    assessment for a hospital, 102 pages; a machine translation with some digits mis-encoded;
    source and provenance off-repo). A machine-written key of 29 in-scope and 15 out-of-scope questions
    (native check owed) answers hit@4 24 of 29 (25 with the majority credit), so Urdu has a
    baseline and a technical document and its "less tested" mark goes. Arabic's technical document
    is half readable (item 1), so Arabic keeps it.

**Before → after, per group** (before: P4 as merged; after: P5a as built, every change in; the
Arabic transport regulation's before is the same edition read from its text layer alone; the Urdu
ESIA has no before). Every set but those two is identical with P5a's changes and the P4 page credit
(the extraction, label and fold changes moved no number); the movement is the page credit.

#### CJK

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | zh-Hans | 38 | 24 → 25 | 31 → 33 | 32 → 33 | 4 → 4 | 12 → 12 of 15 |
| transport reg. | zh-Hans | 34 | 15 → 14 | 27 → 26 | 26 → 25 | 1 → 1 | 4 → 4 of 15 |
| tutorial | zh-Hans | 34 | 14 → 20 | 25 → 26 | 25 → 26 | 3 → 3 | 10 → 10 of 15 |
| baseline | zh-Hant | 38 | 23 → 24 | 30 → 32 | 30 → 32 | 3 → 3 | 12 → 12 of 15 |
| tutorial | zh-Hant | 34 | 14 → 18 | 27 → 28 | 29 → 30 | 3 → 3 | 11 → 11 of 15 |
| baseline | ja | 38 | 21 → 21 | 30 → 31 | 31 → 31 | 1 → 1 | 6 → 6 of 15 |
| tutorial | ja | 34 | 15 → 25 | 28 → 32 | 28 → 32 | 0 → 0 | 2 → 2 of 15 |
| baseline | ko | 38 | 24 → 24 | 32 → 31 | 33 → 32 | 3 → 3 | 8 → 8 of 15 |
| tutorial | ko | 34 | 17 → 17 | 26 → 27 | 26 → 28 | 2 → 2 | 5 → 5 of 15 |

**S** 376 → 386

#### Cyrillic

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | ru | 38 | 23 → 23 | 27 → 27 | 27 → 27 | 8 → 8 | 13 → 13 of 15 |
| transport reg. | ru | 34 | 17 → 17 | 27 → 27 | 29 → 29 | 1 → 1 | 6 → 6 of 15 |
| baseline | uk | 38 | 9 → 9 | 11 → 11 | 11 → 11 | 24 → 24 | 13 → 13 of 15 |
| tutorial | uk | 34 | 14 → 14 | 17 → 17 | 17 → 17 | 7 → 7 | 15 → 15 of 15 |
| national reg. | uk | 19 | 8 → 8 | 11 → 11 | 11 → 11 | 3 → 3 | 12 → 12 of 15 |

**S** 168 → 168

#### Latin light

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | es | 38 | 17 → 18 | 22 → 21 | 22 → 21 | 14 → 14 | 13 → 13 of 15 |
| machinery reg. | es | 33 | 16 → 17 | 23 → 24 | 23 → 24 | 2 → 2 | 12 → 12 of 15 |
| baseline | fr | 38 | 23 → 23 | 28 → 29 | 28 → 29 | 6 → 6 | 11 → 11 of 15 |
| machinery reg. | fr | 33 | 17 → 18 | 24 → 23 | 24 → 23 | 2 → 2 | 8 → 8 of 15 |
| baseline | it | 38 | 22 → 21 | 25 → 26 | 25 → 26 | 10 → 10 | 11 → 11 of 15 |
| machinery reg. | it | 33 | 20 → 22 | 25 → 26 | 25 → 26 | 0 → 0 | 12 → 12 of 15 |
| baseline | nl | 38 | 22 → 21 | 25 → 25 | 25 → 25 | 10 → 10 | 11 → 11 of 15 |
| machinery reg. | nl | 33 | 12 → 12 | 16 → 16 | 16 → 16 | 7 → 7 | 12 → 12 of 15 |
| baseline | pt-BR | 38 | 26 → 26 | 33 → 33 | 33 → 33 | 2 → 2 | 13 → 13 of 15 |
| tutorial | pt-BR | 34 | 17 → 26 | 24 → 28 | 24 → 28 | 0 → 0 | 15 → 15 of 15 |
| machinery reg. | pt | 33 | 17 → 18 | 23 → 24 | 23 → 24 | 1 → 1 | 11 → 11 of 15 |

**S** 472 → 479

#### Latin heavy

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | de | 38 | 17 → 17 | 25 → 25 | 25 → 25 | 12 → 12 | 14 → 14 of 15 |
| machinery reg. | de | 33 | 15 → 15 | 18 → 18 | 18 → 18 | 7 → 7 | 13 → 13 of 15 |
| baseline | hu | 18 | 7 → 7 | 8 → 8 | 8 → 8 | 8 → 8 | 15 → 15 of 15 |
| machinery reg. | hu | 33 | 15 → 15 | 16 → 16 | 16 → 16 | 4 → 4 | 11 → 11 of 15 |
| baseline | pl | 18 | 10 → 10 | 11 → 11 | 11 → 11 | 4 → 4 | 13 → 13 of 15 |
| machinery reg. | pl | 33 | 20 → 20 | 26 → 26 | 26 → 26 | 4 → 4 | 11 → 11 of 15 |

**S** 219 → 219

#### Arabic

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | ar | 38 | 17 → 19 | 21 → 21 | 21 → 21 | 12 → 12 | 11 → 11 of 15 |
| transport reg. | ar | 31 | 3 → 4 | 7 → 6 | 7 → 8 | 9 → 2 | 14 → 7 of 15 |

**S** 57 → 49 (baseline 31 → 31; transport regulation, new in P5a, before = its text layer alone: 26 → 18)

#### Urdu

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | ur | 38 | 18 → 19 | 20 → 22 | 23 → 24 | 9 → 9 | 13 → 13 of 15 |
| health ESIA | ur | 29 | 18 | 25 | 26 | 1 | 11 of 15 |

**S** 37 → 39 on the baseline; the ESIA, new in P5a, S 46

#### English

| Set | Lang | Q | hit@1 | hit@4 | as sent | in-scope refused | out-of-scope refused |
|---|---|---|---|---|---|---|---|
| baseline | en | 38 | 20 → 19 | 25 → 24 | 25 → 24 | 9 → 9 | 11 → 11 of 15 |
| machinery reg. | en | 33 | 12 → 12 | 18 → 18 | 18 → 18 | 7 → 7 | 12 → 12 of 15 |
| transport reg. | en | 34 | 20 → 20 | 24 → 24 | 25 → 25 | 1 → 1 | 7 → 7 of 15 |
| tutorial | en | 34 | 15 → 23 | 24 → 27 | 24 → 27 | 3 → 3 | 12 → 12 of 15 |

**S** 155 → 157

### P5b — Device and tester pass

- On a phone set to each group's language: asset download, indexing time, and voice questions in
  the phone's language and in English, against manuals in both.
- The tester who raised this checks with their own papers. Their documents never enter the repo.

## Decisions (5–7 taken 2026-10-28; 1–4 owed, defaults proceed unless revisited)

1. **Prefix length:** 6 to start. Recommended: one length per group, set by P3. **Measured (P3):** 7
   for Cyrillic and light Latin, 6 for heavy Latin, 4 for Arabic script, each with one ending stripped.
2. **Bigrams or `NLTokenizer` words for CJK.** Recommended: bigrams. They need no dictionary, give
   the same result on every OS version, and need no language label. P3 measures words as the
   alternative. **Measured (P3):** words lose; bigrams kept.
3. **Fold Traditional into Simplified** for matching. Recommended: yes. Citations and answers keep
   the book's own characters.
4. **German compounds.** Recommended: accept the loss for now (prefixes catch the first part of a
   compound, and vectors catch some of the rest) and measure in P3 before considering
   decompounding. **Measured (P3):** German hit@4 41 → 43 of 71 with ending stripping and no
   decompounding; decompounding not tried.
5. ✅ **Order of the P3 groups** (decided 2026-10-28): CJK first (a tester is waiting), then
   Cyrillic, then the Latin groups, then Arabic script.
6. ✅ **Documents without vectors** (decided 2026-10-28): download the model rather than live
   without it. My Manuals and Field Assist fetch the script model ahead of time (P1, item 2), so
   a document is rarely without vectors. When it is anyway (no network, or the download failed),
   the gate uses a stricter lexical rule (a higher shared fraction) until the vectors arrive.
7. ✅ **Measurement sets** (decided 2026-10-28): the baseline is widely available literature
   published in many languages (P3). Parallel texts let one question set and one answer key
   serve every language, so differences between groups come from the language, not from the
   documents. Kept off-repo like the partner books. Test fixtures in the repo are invented
   sentences only.

## Out of scope

- Translating manuals (owner decision 2), or answering in a language other than the wearer's.
- Languages outside the interface. Hebrew and Greek have no Apple contextual model. Thai, Turkish
  and Vietnamese would fall under these rules (bigrams, prefix stems), but nothing is measured.
- The interface's own translation (Plan EC).
