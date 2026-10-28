# Plan JY — Chinese, Japanese and Korean Manuals (search that reads CJK text)

**Status:** 📝 Drafted 2026-10-28. Nothing built. A tester in China asked about using My Manuals
with research papers, and a check of build 581 found that a Chinese PDF indexes but cannot be
searched. Japanese fails the same way. Korean fails partly.
**Track:** App-wide underneath. The first users are My Manuals and vault manuals. Documents (Plan
O) and semantic memory use the same `LexicalSupport` and `Embedder`, so they get the fix too.
**Related:** Plan [O](O-document-rag.md) (`DocumentStore`, `DocumentChunker`), Plan
[AM](embedding-quality-upgrade.md) (`EmbeddingBackend`, `EmbeddingVersion` self-heal), Plan
[EJ](EJ-manual-retrieval-fidelity.md) (the evidence gate and its calibration), Plan
[IV](IV-manual-retrieval-rounds.md) (contextual model P4, BM25F term statistics P7,
`Scripts/retrieval-eval`), Plan [JK](JK-my-manuals.md) (My Manuals), Plan
[IF](IF-photographed-manuals.md) (photographed manuals, whose OCR already follows the phone's
languages), Plan [EC](EC-ui-localization.md) (UI localisation; this plan is about the documents,
not the interface).

---

## Why

The app's interface is translated into Chinese, Japanese and Korean, and the onboarding lists
China-reachable providers first on a mainland phone. But a manual written in one of those
languages can be uploaded, indexed and cited and still never answers a question. Every question
comes back as "the manuals don't cover this". The wearer has no way to tell that the cause is the
language and not the manual.

## What happens today (checked 2026-10-28, build 581)

Each finding below was checked against the code and run on the Mac with Apple's own frameworks
(`NaturalLanguage`, the same models the phone uses).

### 1. Extraction and splitting work

`VaultDocumentExtractor` reads the PDF text layer page by page through PDFKit, so Chinese text and
page labels come through. `DocumentChunker` splits sentences with `NLTokenizer(unit: .sentence)`,
which handles 。！？ correctly. Photographed manuals (Plan IF) already OCR in the phone's preferred
languages (`CapturedManualMedia.languages(preferred:)`).

### 2. Keyword terms treat a whole clause as one word (the blocker)

`LexicalSupport.termSequence` splits on `CharacterSet.letters.inverted`. Han characters, kana and
Hangul are all letters, so only punctuation separates terms. Measured:

| Text | Terms produced |
|---|---|
| 这篇论文用了什么方法来测量温度？ (question) | one: the whole question |
| 本研究采用红外热成像方法测量样品表面温度，并与热电偶读数进行对比。 (the answer) | two: one per clause |
| Shared | **0** |

The evidence gate (`RetrievalEvidencePolicy`) requires at least one shared content term for every
shipped backend: `minSharedTerms: 3`, scaled by `sharedFraction`, and never below 1. So a CJK
question is refused unless the passage contains a code-like token from it verbatim.
`passages(sharingTermsWith:)` and BM25F (`TermStatistics`) read the same terms, so lexical
retrieval finds nothing either.

### 3. Splitting into words alone isn't enough: the four-character minimum drops them

`LexicalSupport.minimumLength` is 4, which was tuned for English. Measured with Apple's word
tokenizer (`NLTokenizer(unit: .word)`):

| Language | Example words | Words of 4+ characters |
|---|---|---|
| Chinese | 研究/采用/红外/方法/测量/温度 | 0 of 18 |
| Japanese | 研究/赤外/サーモグラフィ/試料/温度/測定 | 1 of 18 |
| Korean | 연구에서는/적외선/방법으로/온도를/측정하였다 | 3 of 9 |

Korean has a second problem. It puts spaces between words, but the particle stays attached:
온도를 (temperature, object) and 온도는 (temperature, topic) are different terms, so a question and
its answer share nothing even when both use "temperature".

### 4. The embedder is English-only, and its vectors for CJK text are noise

Every `Embedder` defaults to `language: .english`: `Embedder.fieldAssist()`, the store's
`standardEmbedder`, `SemanticMemoryStore` and `VoiceSkillsTool`. `prepareFieldAssistAssets`
downloads only the English contextual asset. Measured on the Mac:

- `NLContextualEmbedding(language: .english)` covers 20 languages, all Latin script (`Latn`).
  Chinese is not one of them.
- `NLContextualEmbedding(language: .simplifiedChinese)` is a separate model covering Hans, Hant,
  Jpan and Kore. The app never loads it.
- `NLEmbedding.sentenceEmbedding(for: .simplifiedChinese)` and `wordEmbedding` both return nil.
  There is no `NLEmbedding` fallback for CJK.
- The English sentence model does return a vector for Chinese text, but it's meaningless. The
  question scored 0.968 against its answer and 0.965 against an unrelated sentence about the
  weather.

### 5. Code tokens stick to the CJK text around them

`CodeTokenizer.wordPattern` is `[\p{L}\p{N}]+`, so in 型号ABC123的 the code-like token is the
whole string and not `ABC123`. This means the one route that gets past the gate today, an exact
model or fault code, fails whenever CJK text touches the code. That is the usual case in a CJK
manual.

### 6. Language detection can't handle mixed text

`NLLanguageRecognizer` labelled 我们使用ResNet-50模型在ImageNet数据集上训练 as Catalan. Academic
and technical CJK text mixes in Latin terms all the time. So this plan detects scripts by counting
characters (Han, kana, Hangul, Latin) and doesn't use the recogniser's language guess.

### 7. Smaller mismatches, measured in P3

- The chunker's heading heuristic counts uppercase letters, and CJK has none.
- `hardSplit` breaks an oversized sentence on spaces. CJK falls through to slicing by raw
  character count.
- The 700/900-character chunk targets hold about two to three times more content in CJK than in
  English.
- Table captions match only `^TABLE` (`TableExtractor.captionPattern`, `ManualStructure.caption`).
  A CJK book prints 表 3-1, 図 2 or 표 4.
- Traditional and Simplified Chinese don't match each other (溫度 vs 温度).
- Japanese and Chinese text may use full-width Latin letters and digits (ＡＢＣ１２３).

## What changes

### P0 — Script-aware terms (deterministic core, headless)

1. **`ScriptProfile`** (pure): counts the letters in a text by script (Han, Hiragana/Katakana,
   Hangul, Latin, other) and classifies it as `.latin`, `.chinese`, `.japanese` (any kana),
   `.korean` (any Hangul) or `.mixed`. It works on a passage, a page or a whole document. Tests use
   invented sentences, including mixed ones like the Catalan case.
2. **CJK terms in `LexicalSupport`.** Normalise first: NFKC (full-width to half-width) and fold
   Traditional to Simplified Han (the owner's call, decision 3). Then:
   - A Latin run is handled exactly as today: lowercase, ≥ 4 characters, stopwords, suffix trim.
   - A Han/kana run becomes overlapping **character bigrams** (红外热成像 → 红外/外热/热成/成像). A
     single-character run stays as a unigram.
   - A Hangul run becomes bigrams too, so 온도를 and 온도는 both yield 온도.
   - A small, fixed CJK stop-bigram list removes the question-word noise (什么, 这篇, 어떤, です)
     that would otherwise count as shared terms.

   With these rules, the question and answer from finding 2 share 方法, 测量 and 温度. Bigrams were chosen
   over `NLTokenizer` words because they need no dictionary, give the same result on every OS
   version, and need no language label (decision 1).
3. **Gate scaling for CJK queries.** A CJK question yields many more terms than an English one: ten
   characters give up to nine bigrams. `requiredSharedTerms` counts only the CJK terms that survive
   the stop list, with a provisional fraction that P2 replaces with a measured one. English
   questions are unchanged. The existing English calibration tests must pass untouched.
4. **`CodeTokenizer` boundaries.** CJK characters count as separators for code tokens, so
   型号ABC123的 yields `ABC123`. Latin text is unaffected (pinned by the existing tests).
5. Tests: `ScriptProfileTests`, `LexicalSupportCJKTests` (the bigram rules, normalisation,
   stop-bigrams, an English regression set), `CodeTokenizer` boundary cases, and a gate test where
   an invented CJK question passes against its invented answer and fails against an unrelated
   passage.

Term statistics are an in-memory cache rebuilt from stored chunk text
(`DocumentStore.termStatisticsCache`), so P0 needs no stored-data migration. It is shippable on its
own: CJK questions get lexical answers before any embedding work.

### P1 — Embed each document with the model for its script

1. At ingest, `ScriptProfile` over the extracted text picks the embedding language: Latin →
   `.english` (as today), CJK → the CJK contextual model (`NLContextualEmbedding` for
   `.simplifiedChinese`, which covers all four scripts). A mixed document follows its majority
   script, measured per document, not per passage. Splitting a document's passages across two
   vector spaces is left out: it would complicate ranking and needs measuring first.
2. **Never embed CJK text with a Latin-script model.** If the CJK asset isn't on the phone yet, the
   passages are stored without a vector, tagged so the existing `EmbeddingVersion` self-heal embeds
   them once the asset lands. Until then the gate judges them on lexical evidence only, under
   decision 5's rule. The upload screen's indexing note says search will improve once the language
   model has downloaded.
3. Asset preparation: `prepareFieldAssistAssets`, and the My Manuals upload path, also request the
   CJK asset when a CJK document is added, or at launch on a phone whose preferred languages include
   zh, ja or ko. The download needs a network connection. It is never a prerequisite for adding
   a manual.
4. Queries: `DocumentStore.QueryVectors` already embeds the question once per stored version tag,
   so a library mixing English and Chinese manuals compares each passage with a question vector
   from its own model. P1 adds a test that pins this behaviour.
5. Documents, semantic memory and voice skills read the same `ScriptProfile` choice through
   `Embedder`, so a Chinese memory or note isn't embedded as English either.

### P2 — Questions in another language, and gate calibration

1. **Cross-language questions.** A Chinese question about an English paper shares no terms with
   it, and the two models produce vectors in separate spaces. `manual_lookup`'s result and the
   vault prompt list each manual's script, and the tool description tells the model to phrase
   `query` in the manual's language. When a lookup spans manuals in more than one language, it
   searches once per language and merges. The model is already in the loop, so no translation
   service is added (decision 2).
2. **Calibration.** Run `Scripts/retrieval-eval` on CJK sets (decision 6 says where they come from):
   in-scope and out-of-scope questions for each language, measuring recall@4, hit@1 and refusal
   counts the way EJ and IV did. Set the CJK `sharedFraction` and stop-bigram list from those
   numbers. Record the table in this plan, as EJ did.

### P3 — Structure in CJK books

Measured against the P2 sets before anything changes:

- **Captions.** 表/図/표 labels are recognised in `TableExtractor` and `ManualStructure`, and
  continuation markers (续表, 続き, 계속) are handled.
- **Headings.** A heading heuristic that doesn't depend on uppercase: numbered section lines (第3章,
  3.1, 一、) and font size, where `VaultDocumentExtractor` already has it.
- **Chunk size and splitting.** Character targets per script so a CJK passage holds about as much
  content as an English one. `hardSplit` breaks CJK at 、，；.
- **Passage budget.** `ManualPassageLimit` measured on CJK text, since a character costs the model
  more tokens.

### P4 — Device and tester pass

- On a phone set to Chinese: asset download, indexing time for a long paper, and voice questions in
  Chinese and English against Chinese and English papers.
- The same for Japanese and Korean, if a tester is found.
- The tester who raised this checks with their own papers. Their papers never enter the repo.

## Decisions owed

1. **Bigrams or `NLTokenizer` words** for CJK terms. Recommended: bigrams (see P0, item 2). Word
   segmentation is kept as the alternative P2 measures against.
2. **Cross-language questions.** Recommended: the model rewrites the query in the manual's
   language. The alternative is translating passages at index time, which costs a model call per
   passage and sends manual text off the phone.
3. **Fold Traditional into Simplified** for matching. Recommended: yes. Citations and answers
   keep the book's own characters.
4. **Japanese and Korean in the first release, or Chinese first.** Recommended: all three. P0 and
   P1 are script-level and cost the same either way. Only P2's measurement needs a set per
   language, so Japanese and Korean can ship marked "less tested" if their sets come later.
5. **Gate rule while the CJK vectors are missing.** Recommended: a stricter lexical rule, a higher
   shared fraction, until vectors exist. The alternative is waiting for the asset before answering
   at all.
6. **Measurement sets.** CJK documents for P2, kept off-repo like the partner books. Openly
   licensed texts, or the owner's own. Test fixtures in the repo are invented sentences only.

## Out of scope

- Translating manuals, or answering in a language other than the wearer's.
- Right-to-left scripts, and Thai, Lao and Khmer, which also don't put spaces between words. P0's
  `ScriptProfile` leaves room for them, but nothing is measured.
- The interface's own translation (Plan EC).
