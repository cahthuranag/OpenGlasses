# Plan JY — Manuals in Every Interface Language (search keyed on the document's script)

**Status:** 📝 Drafted 2026-10-28. Nothing built. A tester in China asked about using My Manuals
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
  then the gate judges them under the stricter lexical rule (decision 5).
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
2. **Assets:** a document's script asset is requested when the document is added, and the phone's
   preferred languages' assets at launch. The download needs a network connection and is never a
   prerequisite for adding a manual. Until it lands, the upload screen's indexing note says search
   will improve once the language model has downloaded.
3. **Urdu:** measure whether the model Apple maps `ur` to reads Arabic-script Urdu. If it doesn't,
   Urdu stays lexical only.
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

### P3 — Calibration by language group

Run `Scripts/retrieval-eval` for each group, in the order of decision 5. Use in-scope and
out-of-scope questions and measure recall@4, hit@1 and refusals, as EJ and IV did. Each run sets
that group's prefix length, stopwords and shared fraction, and its table is recorded in this plan.

| Group | Languages | Rule |
|---|---|---|
| Latin, light endings | es, fr, it, nl, pt | `.prefixStem` |
| Latin, heavy endings or compounds | de, hu, pl | `.prefixStem` |
| Cyrillic | ru, uk | `.prefixStem` |
| Arabic script | ar, ur | `.arabicStem` (ar), `.prefixStem` (ur) |
| CJK | ja, ko, zh-Hans, zh-Hant | `.bigram` |

A group ships marked "less tested" (Developer panel and support report) until its set has been
run.

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

### P5 — Device and tester pass

- On a phone set to each group's language: asset download, indexing time, and voice questions in
  the phone's language and in English, against manuals in both.
- The tester who raised this checks with their own papers. Their documents never enter the repo.

## Decisions owed

1. **Prefix length:** 6 to start. Recommended: one length per group, set by P3.
2. **Bigrams or `NLTokenizer` words for CJK.** Recommended: bigrams. They need no dictionary, give
   the same result on every OS version, and need no language label. P3 measures words as the
   alternative.
3. **Fold Traditional into Simplified** for matching. Recommended: yes. Citations and answers keep
   the book's own characters.
4. **German compounds.** Recommended: accept the loss for now (prefixes catch the first part of a
   compound, and vectors catch some of the rest) and measure in P3 before considering
   decompounding.
5. **Order of the P3 groups.** This is a market call. Suggested: CJK first (a tester is waiting),
   then Cyrillic, then the other Latin groups, then Arabic script.
6. **Gate rule while a document has no vectors.** Recommended: a stricter lexical rule, a higher
   shared fraction, until the vectors exist. The alternative is not answering at all until the
   asset arrives.
7. **Measurement sets.** Documents for each group in P3, kept off-repo like the partner books:
   openly licensed texts, or the owner's own. Test fixtures in the repo are invented sentences
   only.

## Out of scope

- Translating manuals (owner decision 2), or answering in a language other than the wearer's.
- Languages outside the interface. Hebrew and Greek have no Apple contextual model. Thai, Turkish
  and Vietnamese would fall under these rules (bigrams, prefix stems), but nothing is measured.
- The interface's own translation (Plan EC).
