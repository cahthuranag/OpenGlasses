# Plan JG — Regulation Practice (questions from the organisation's own code, checked against the clause, and an apprentice's questions on the way to the job)

**Status:** 📝 Drafted 2026-10-19 — nothing implemented.
**Track:** Field Assist (B2B): the regulations vertical (electrical first, refrigerant next), for
apprentices and qualified technicians.
**Related:** Plan [IW](IW-goals-and-activity-trail.md) (goals, steps, `StepAction`, `GoalStore`,
`GoalAdvancePolicy`, check-ins, the activity trail: this plan's learning goals *are* IW goals),
Plan [IN](IN-verifiable-code-lookup.md) (clause references, citations, `show_source`, the passage
highlight, the `standard` document kind, editions), Plan [IV](IV-manual-retrieval-rounds.md) (what
retrieval on a code book actually achieves), Plans [ED](ED-vault-manual-retrieval.md) /
[EJ](EJ-manual-retrieval-fidelity.md) (the retrieved manual tier and its evidence gate), Plan
[FO](FO-guided-job-flow-and-job-tab.md) (jobs ahead, the brief, the CarPlay Jobs list), Plan
[EL](EL-equipment-identity.md) (equipment identity, `VaultModelIndex`), Plan
[HV](HV-site-system-vaults.md) (site and system vaults), Plan
[HU](HU-service-history-and-maintenance-flags.md) (the office's service history and flags), Plan
[FP](FP-team-learnings.md) (team learnings, deliberately separate), Plan
[IS](IS-refrigerant-toolkit.md) (refrigerant toolkit, being amended for Canada, Australia and New
Zealand), Plan [IP](IP-organisation-feature-switches.md) (an organisation switches it on), Plan
[IR](IR-test-sheets-from-a-photo.md) (the electrical sibling), Plan [JD](JD-apple-intelligence-tools.md)
(the on-device model), [EU AI Act review](../eu-ai-act-review-2026-10.md).
**Origin:** The owner, 2026-10-18/19. A regulations "learning / question tester" for Field Assist:
the technician is asked what a regulation requires, answers by voice, and is told whether they got
it right, with the source clause; what they get wrong becomes something to learn. It must also feed
apprentice training on the way to a job, with questions that reflect the equipment at the site and
the site's history, asked during the drive by voice only. It is built on IW's goal model, not beside
it. It was first tried in private testing on an electrical code book a partner loaded for testing
only; the second family is refrigerant regulations (IS).

---

## Trigger

IN made the code answerable: a question gets the clause, and "show me the page" opens it
highlighted. That serves a technician who already knows what to ask. An apprentice studying for a
licence, and a qualified technician keeping up with a new edition, need the opposite direction: the
app asks, and they answer. The drive between jobs is the obvious time — twenty minutes with nothing
to read — and the day's jobs say which parts of the code matter today.

The hard part is not asking. It is that **a wrong answer key is worse than no question**: a
technician who is "corrected" into a wrong clearance carries it onto a job. IV measured how far
retrieval on a code book can be trusted: on the default path a clause-numbered document's answer
carries six passages, the answering passage is somewhere in them for 0.57 of questions (0.68 for
single-rule questions), and multi-rule and calculation questions (17 of 72 in the answer key) are
not a retrieval problem at all. Number-dense tables are where passages are weakest. So the design
starts from what can be checked, and asks only that.

## Outcome

- "Quiz me on the code." → "Okay, five questions from the code you've loaded. First: what is the
  least height above a finished floor for a widget, in millimetres?" → "Six hundred." → "That's
  right. Clause 9.4.7: not less than 600 mm above a finished floor." (Invented clause and wording,
  as in every example here.)
- A miss: → "Four hundred." → "Not quite. Clause 9.4.7 says not less than 600 mm. I've put it on
  your list." The clause joins a learning goal and comes back on a spacing schedule until it is
  answered right on two separate days.
- When the app cannot be sure — a free-form answer it cannot match, a word it did not catch — it
  says so and does not mark it wrong: "I can't be sure that matches the book's wording. Check
  clause 9.4.7 yourself; it's on your list to look at."
- "Make a learning goal: the earthing part of the code before my exam on the first of March." →
  the goal's steps are the section's clause groups, read from the loaded document itself, each with
  a practice offer; IW's screens, check-ins, My Day row and trail carry it unchanged.
- An apprentice gets into the van with Job 1007 ahead, a heat pump with a three-phase supply. When
  CarPlay connects (after the brief, if the brief is on): "Want three questions on the way? Two are
  about the heat pump at 1007." → "Go on." Questions come one at a time, between navigation prompts,
  and stop the moment the apprentice says anything else.
- After the drive, the phone shows what was missed, each row opening the clause's page with the
  passage highlighted (IN's viewer).
- Results are the technician's own. Nothing is shared with a supervisor or the office unless the
  technician sends it, and this plan does not build the sending.

## What exists today (verified against `main` @ `e364e24bd`, 2026-10-19)

- **Goals (IW, built P0–P2).** `Goal { id, title, why?, createdAt, dueAt?, state, checkIn:
  CheckInCadence, steps, persona?, source: GoalSource, finishedAt? }`, `GoalStep { id, title,
  state, dueAt?, suggestedAction: StepAction?, doneAt?, evidence: [ActivityRef] }`
  (`Services/Goals/Goal.swift`). `StepAction` is a closed set of six (`reminder`, `calendar_hold`,
  `search`, `draft`, `scheduled_check`, `ask`), each mapped to a tool through `Kind.toolName`; a
  stored action of an unknown kind "loses the offer, not the step". `StepActionPermission.predicate`
  decides whether an action may be offered; `StepActionRun` maps an offer to the call its tool takes
  for the Goals screen's "Do it". `GoalProposalParser` validates 3–7 steps for a spoken proposal;
  `GoalDrafter` (behind `GoalDraftModel`) holds one proposal for 15 minutes until `accept`.
  `GoalAdvancePolicy`: next step, `evidenceSuggestion(for:in:)` (suggest-only; the entry must come
  from the step's own tool, be done, and be `.action`/`.plannedStep`/`.scheduledRun`/`.toldYou`),
  `dailySentenceCap = 2` unprompted goal sentences a day, `isCheckInDue` (`beforeDue(n)` once).
  Check-ins are `ScheduledTaskKind.goalCheckIn(goalID:)` tasks that make no model call; the day's
  count is read from those tasks' `lastSpokenAt` stamps (IW P2 decision 1). `GoalStore` is
  `SensitiveStore.goals`; the trail is `ActivityStore` (`SensitiveStore.activityTrail`) behind the
  `ActivityRecording` seam, with `ActivityKind { action, plannedStep, scheduledRun, toldYou, held,
  refused }`. Settings › AI & Personality › Goals and › Activity; My Day's `goals` source.
- **Code lookup (IN P0–P3a).** `ClauseReference` recognises clause numbers and grades a passage as
  `starts`, `startsSubclause`, `continues` or `cites` its clause; `DocumentStore.passages(clause:)`;
  `VaultRetriever.Passage` carries `kind` (`prose`/`diagram`), `figure` ("Table 16"), `section`,
  `clauseMatch`, `editionLabel`, `recognisedFromScan`, `printedPage`. `PassageLocator` finds a
  passage's sentences on its PDF page; `show_source` opens what an answer cited, highlighted.
  `StandardDocumentOpenPolicy.isStandard` reads a manifest document's `kind == "standard"`;
  `VaultManifest` documents carry `edition`; `DocumentEditions` picks the newest edition (IV P2).
  The `standard` kind's import step and IN P3's answer rules are unbuilt.
- **Jobs (FO, HB).** `UpcomingJob { jobReference, site: JobSite, faultReport, equipment:
  [KnownEquipment { model, serial }], scheduledFor, brief, … }` in `UpcomingJobStore` (`next` is the
  first); `JobHistoryIndex` (this phone's finished visits by site, serial and model);
  `GuidedJobFlow.briefAloud(jobId:)`; `JobDayFeed`. `VaultModelIndex` resolves a model to its vault
  section (EL).
- **Not built:** HV's site document, HU's `OfficeServiceHistory` and flags (and its 2026-10-18
  `site_requirements` amendment), IS. JG reads them through a seam that is empty until they land.
- **CarPlay.** `CarPlaySceneDelegate` (tab bar: Voice, Modes, Conversations, Playbooks, Jobs; depth
  three), `CarPlayJobsList` (pure rows and selections), `AppState.carPlayConnected`, the brief on
  connect (`Config.briefOnCarPlayConnect`, off by default), directions handed to the technician's
  maps app (`MapsHandoff`). The app does **not** own driving guidance; it cannot read the maps
  app's prompt schedule. `WakeListenPolicy` has a `.carPlay` listen mode.
- **Spoken numbers and units.** `SpokenReading` keeps a spoken value as text;
  `DebriefJobResolver.spokenNumber(in:)` reads a spoken job number; `UnitNormalizer` converts
  temperature, pressure, mass, brix and voltage (no length, current or time yet).
- **The bundled refrigeration vault's `epa_608.md`** is the app's own summary of a regulation, not
  the regulation; #753 found it wrong once.

## Design

### 1 · Licensed content: the rules this plan never bends

Codes and standards are licensed to the organisation (IN decision 6, EG, FS). For practice:

- **Questions are generated at run time from the organisation's own loaded vault passages, and
  always cite them** (document, edition, clause, page). There is no question bank, no exam material,
  no answer key and no book text in the app, a vault pack, a bundle, a fixture, a log, a support
  report, an export or the office transport.
- **The only egress is the model call the organisation already permits for manual answers** — the
  same route `manual_lookup` uses to send passages to the model. Under Medical Local Only, or with
  cloud models off, generation uses the on-device model or practice is unavailable and says so.
- **What is stored, and where.** A practice item (§3) keeps the document id, edition label, clause
  number, page, a digest of the source chunk, the generated question, the expected answer and the
  quote's *character range in the chunk* — not a copy of the quote, which is re-read from the vault
  store when it is spoken or shown. The store is on the phone only, first-unlock protected,
  backup-excluded, and **bound to its document**: removing the document, a changed chunk digest, or
  a newer edition becoming the default retires its items (§4).
- **Logs and the trail carry counts and clause numbers only.** `PrivacyLog` events, the activity
  trail and the support report never carry a question, an answer, a quote or a section heading.
- **Fixtures are invented.** Tests use clause numbers and wording made up for the test ("Clause
  9.4.7 (invented): A widget shall be mounted not less than 600 mm above a finished floor"). A
  developer may measure the gate on their own licensed copy locally, as IV's local eval does; only
  aggregate counts go into this plan, and every derived artefact is deleted afterwards.
- **Only documents the vault marks as regulations are sources.** A document of manifest kind
  `standard` (IN) is eligible; a manual, a team learning (FP) and an app-authored reference such as
  the bundled `epa_608.md` are not. A summary is not the regulation, and an answer key built from
  one inherits its mistakes.

### 2 · The answerability gate: a question is asked only if the passage settles it

The model proposes; a pure gate decides. `PracticeQuestionModel` (a protocol, one structured
completion per passage, like `GoalDraftModel`) is given one retrieved passage, its clause number and
the answer kinds allowed, and returns up to two candidates:

```swift
struct QuestionCandidate { question: String, answerKind: AnswerKind, expected: String,
                           quote: String, clause: String }
enum AnswerKind { case number          // a single value with its unit
                  case yesNo           // a "shall" / "shall not"
                  case term }          // a short named thing (P3)
```

`QuestionAnswerabilityGate.check(candidate, passage, document) -> GateVerdict` (pure) accepts only
when **every** rule holds, and otherwise returns the first failing reason by name:

1. **Source.** The document is a `standard`, is the newest edition loaded (`DocumentEditions`) unless
   the technician asked for an older one, and the passage was not read by recognition
   (`recognisedFromScan`: numbers are where recognition fails quietly). → `.notARegulation`,
   `.olderEdition`, `.scannedSource`.
2. **Prose, not a table.** `kind == .prose`, `figure` does not name a table, the passage is not a
   contents page (`ClauseReference.looksLikeContents`), and its share of numeric tokens is under a
   table threshold. → `.tableOrFigure`.
3. **The clause is the passage's own.** `ClauseReference.match(candidate.clause, in:)` is `starts`
   or `startsSubclause` — the passage *is* the clause, not one that cites it or continues it without
   its number (IV class (c)). → `.clauseNotOwned`.
4. **The quote is the book's words.** The quote is found verbatim in the passage after the same
   folding `PassageLocator` uses, and is 6–40 words. → `.quoteNotFound`, `.quoteLength`.
5. **One rule.** The quote holds exactly one requirement word ("shall", "shall not", "must", "is
   required"), no reference to another clause, table or figure ("in accordance with", "as specified
   in", a clause number), and — at first — no exception ("except", "unless", "other than", "where
   permitted"). → `.multiRule`, `.crossReference`, `.exception`.
6. **The answer is in the quote.** A `number` answer's value and unit appear in the quote, and the
   quote holds no second value of the same dimension (a range "between 300 and 600 mm" is refused
   at first). A `yesNo` answer agrees with the requirement word's polarity. A `term` answer appears
   verbatim. → `.answerNotInQuote`, `.ambiguousValue`, `.polarityMismatch`.
7. **A fair question.** The question does not contain the answer, is at most 160 characters and 25
   spoken words, and names the unit a number is wanted in. → `.answerGiven`, `.tooLong`, `.noUnit`.

Rule 5's exceptions and rule 6's ranges are where the gate is deliberately narrow: they cut the
question types IV found weakest. They loosen only after a measurement shows they can (open question
2). A candidate that fails is dropped, never repaired; a passage none of whose candidates passes asks
nothing.

### 3 · Items, grading and the spacing schedule (pure)

```swift
struct PracticeItem { id, documentId, editionLabel?, clause, page?, chunkDigest, question,
                      answerKind, expected: ExpectedAnswer, quoteRange, createdAt, origin:
                      .onRequest | .learningGoal(goalID, stepID) | .job(jobReference) }
enum ExpectedAnswer { case number(value: Double, unit: String) case yesNo(Bool) case term(String) }
struct PracticeAttempt { itemID, at, outcome: PracticeOutcome }
enum PracticeOutcome { case correct, incorrect, unsure, notHeard, skipped }
```

- **`SpokenAnswerParser` + `AnswerGrader` (pure, for `number` and `yesNo`).** A spoken value ("six
  hundred", "six hundred mil", "point six of a metre", "sixty amps") is parsed and normalised
  through `UnitNormalizer`, which gains length, current and time. Equal after normalisation →
  `correct`; a different value of the same dimension → `incorrect`; no value found, or a value in
  another dimension → `notHeard` ("I didn't catch a number"). No tolerance unless the quote states
  one. A bare number with no unit is graded in the unit the question named. Yes/no reads "yes",
  "no", "it shall", "it can't" and refuses to guess on anything else (`notHeard`).
- **`term` answers (P3)** go through `PracticeGrading`, a protocol whose model-backed judge sees
  only the quote and the technician's answer and returns `correct`, `incorrect` or `unsure`.
  Deterministic guards sit on both sides: the key term found in the answer is `correct` without a
  model call; a judge's `incorrect` on an answer that shares most of the quote's content words
  becomes `unsure`. **`unsure` and `notHeard` never count as a miss.**
- **`PracticeSchedule` (Leitner, pure).** Five boxes, re-asked after 0 (later in the same session),
  1, 3, 7 and 21 days. `correct` moves an item up a box; `incorrect` sends it to box 1 and onto the
  technician's "to go over" list; `unsure`, `notHeard` and `skipped` leave it where it is. An item is
  **learned** in box 3 or above: answered right on at least two separate days.
- **`PracticeSelector` (pure).** Picks a session's items from: due review items first, then items
  for today's jobs (§5), then new items for the next open step of an active learning goal — capped
  per session, never the same clause twice in one session, a miss re-asked at most once later in
  the same session.
- **`PracticePhraser` (pure, exact strings).** The question; "That's right. Clause 9.4.7: …" with
  the quote's operative words (IN P3's rule: never paraphrase a requirement without its clause);
  "Not quite. Clause 9.4.7 says … I've put it on your list."; the unsure and not-heard lines; the
  session's close ("Two of three. Clause 9.4.7 is on your list."). The quote is cut to at most 25
  words when spoken in the car, with "the rest is on your phone".

### 4 · Learning goals are IW goals

No second goal model. A **learning goal** is an IW `Goal` whose steps carry a practice offer:

- **`StepAction.practise(topic: PracticeTopic)`** — a seventh case in IW's closed set, persisted as
  kind `practise`, mapped to the `regulation_practice` tool. `PracticeTopic { documentId, clausePrefix
  ("4.3"), label }`. Older builds decode it as an unknown kind and keep the step, as IW designed.
  `StepActionPermission` offers it only when the tool is enabled (an organisation's `closedTools` and
  IP switch included), Field Assist is active and the document is still loaded. `StepActionRun`
  maps "Do it" to a practice session on the phone for that topic.
- **Steps come from the document, not the model.** "Make a learning goal: the earthing part of the
  code" retrieves the section in the loaded standard; `TopicPartitioner` (pure) groups its clause
  headings by number prefix into 3–7 steps ("Clauses 4.1–4.2", "Clauses 4.3", …, with the section
  heading as the citation already shows it). The proposal goes through `GoalProposalParser` and is
  held and read back exactly as `GoalDrafter`'s are; nothing is stored until `accept`. A due date
  ("before my exam on the first of March") is the goal's `dueAt`, and IW's default cadence applies.
- **Misses become steps.** A missed item whose clause falls inside an active learning goal's step
  stays with that step. One that falls outside every goal (a job-led question) goes to one standing
  learning goal per document, "Go over what I've missed in <document title>", created the first
  time with the technician's yes. Its steps are clause groups, so a second miss in 4.3 joins the
  "Clauses 4.3" step rather than adding one; at seven open steps, the oldest learned step is closed.
- **Done is suggested, never applied.** When every item under a step is learned, the
  `regulation_practice` tool records a trail entry for that step, and IW's
  `evidenceSuggestion(for:in:)` turns it into "Looks like you've got clauses 4.3 — mark that step
  done?" (IW decision 2). `ActivityKind` gains `practiceSession` ("practice_session"), one entry per
  session, title fixed ("Went over four regulation questions with you; three right"), no detail,
  refs `goal:<id>`; `GoalAdvancePolicy`'s switch accepts it as evidence.
- **Editions.** When a newer edition becomes the default, items from the older one retire, and a
  learning goal on the older edition gets one sentence on the Goals screen: "A newer edition is
  loaded. Practise from it instead?" (a new goal, on yes). Comparing what changed is IN P4's.

### 5 · Questions from the day's jobs

`JobPracticeContext` (pure) turns a job ahead into at most three retrieval queries over the
organisation's `standard` documents, from **equipment words only**:

- `UpcomingJob.equipment` resolved through `VaultModelIndex` to the model's vault section: its
  category words ("heat pump", "outdoor unit", "three-phase", "gas-fired"), never a serial;
- this phone's `JobHistoryIndex` visits on the same serial or site: parts replaced and work done
  ("replaced the contactor") — equipment words, not the debrief's free text;
- **when built:** HV's site document (connection kinds and media: `power`, `fluid`/refrigerant), HU's
  flag kinds (`recurring_failure`, `overdue_maintenance`) and parts, HU's `site_requirements` kinds,
  and IS's refrigerant and charge for the unit. Each enters through a `PracticeContextSource`
  protocol that is empty until its plan lands.

Never the customer, address, contact, fault report text or office notes: those are the
organisation's data about a person, and the generation call does not need them. The model is told
only the passage and "the technician is seeing a <category> today".

**Prepared before the drive.** `PracticeSetPreparer` builds a job's set when the job arrives or
changes, and on demand, so the car never waits on a model: at most eight passages tried per job and
twenty a day, at most five gated items kept per job. It runs in the foreground, or in the background
only on a cloud model (on-device MLX cannot run backgrounded). A job none of whose candidates passes
gets no set, and the car offers nothing for it.

### 6 · In the car: voice only, short, and second to the road

`DrivePracticePolicy.next(inputs) -> DriveStep` (pure) decides `.offer`, `.ask(item)`, `.wait(reason)`
or `.stop(reason)` from:

- CarPlay connected, Field Assist active, practice on, the role's default (§7), a prepared set for a
  job ahead today;
- **the IW budget.** The offer is an unprompted goal sentence: it is spoken only when
  `GoalAdvancePolicy.maySpeakGoalSentence` allows, and it stamps the standing learning goal's
  check-in task's `lastSpokenAt`, so IW's two-a-day count stays the one count. Once the technician
  says yes, the session has its own explicit budget: **one offer per drive, at most five questions
  per drive and fifteen a day**, each question at most two sentences;
- **quiet.** A question starts only after 20 seconds with no other audio — no audio interruption,
  no other app's spoken audio, no call, no Siri, no live session — and only when the app's own
  guidance (walking, today) is not running. Another app's spoken prompt arriving mid-question
  abandons that question: it is neither answered nor counted, and may be asked again later. The app
  cannot see the maps app's prompt schedule, so it yields to what the audio session reports; P2
  measures on a real car what that is (open question 4);
- **listening.** One answer window of eight seconds; silence is `skipped`, not wrong;
- **stopping.** "Stop", "not now", "enough", "later", the wake word followed by any other request,
  a call, or CarPlay disconnecting ends the session at once. Nothing more is said in that drive
  unless asked; the close line is skipped when the stop was the technician's.

Nothing is shown on the car screen beyond the voice states the app already uses: no question text,
no list of misses. The CarPlay Jobs list's upcoming-job page may gain one row, "Questions on the
way", which starts the same session (`CarPlayJobsList.UpcomingAction.practice`). "Quiz me on the way
to 1007" works by voice at any point in the drive, within the same per-drive caps.

### 7 · Roles, results and who sees them

- **`PracticeRole { apprentice, qualified }`**, set by the technician in Settings › Field Assist ›
  Practice questions. An organisation profile may set the default but not hide the setting. For an
  apprentice the drive offer is on when practice is on; for a qualified technician it is off and
  practice is by request ("quiz me"), with edition refreshers later.
- **Results are the technician's own data.** `PracticeStore` is `SensitiveStore.practice`
  (wearer-linked, `deleteAll`, the erasure walk, the HIPAA retention honoured), and the Practice
  screen shows boxes, learned clauses and the "to go over" list, each opening the clause's page
  through IN's viewer.
- **Sharing is explicit and not built here.** A supervisor or the office seeing results would go
  through the phone's office transport (FX / HO), as a summary the technician sends: clause numbers,
  counts and dates, never answers or question text. The office half lives in the private office
  repository. This plan builds no sharing; see open questions 6 and 7.
- **It is practice, not an assessment.** Copy says so, nothing is called a score or a pass, and the
  app keeps no record that could stand for a competence sign-off.

### 8 · Gates and modes

Field Assist only, inside its tool block and `FieldToolProfile`; an IP feature switch
`regulation_practice`; `closedTools` closes it with no code of its own. Not in HIPAA-only or Medical
setups (no `standard` documents there). Agent Mode is not required: practice is the technician's own
request, and the drive offer is a goal sentence under IW's cap. The tool's description stands alone
(`SystemPromptBuilder` lists it). Spoken copy names no plan letter.

## Phases (one PR each)

### P0 — Pure core

`QuestionCandidate`, `AnswerKind`, `QuestionAnswerabilityGate` (§2, every refusal named),
`PracticeItem` / `ExpectedAnswer` / `PracticeAttempt` / `PracticeOutcome` + codec (explicit
strings), `SpokenAnswerParser`, `AnswerGrader` (`number`, `yesNo`), `UnitNormalizer` length, current
and time, `PracticeSchedule`, `PracticeSelector`, `PracticePhraser`, `TopicPartitioner`,
`StepAction.practise` with its codec, permission and `StepActionRun` mapping, `ActivityKind.practiceSession`
and its place in `evidenceSuggestion`. No store, no tool, no model.

**Exit tests (invented fixtures only):** `QuestionAnswerabilityGateTests` — a table with one
passing candidate and one failing case per reason (a table passage, a passage that cites the clause,
a quote not in the passage, "except", a cross-reference, a range, a polarity mismatch, the answer in
the question, a scanned source, an older edition); `AnswerGraderTests` (spoken numbers and units,
wrong dimension → not heard, yes/no wording); `PracticeScheduleTests` (box moves, unsure leaves the
box, learned on two separate days); `PracticeSelectorTests`; `PracticePhraserTests` (exact strings,
the 25-word car cut); `TopicPartitionerTests` (3–7 steps, prefixes); `GoalCodecTests` +
`GoalAdvancePolicyTests` extended for `practise`; a guard test that every practice fixture passage
carries the "(invented)" marker, so a real clause pasted in for convenience fails the suite.

### P1 — Generation, the store, the tool, learning goals (on the phone)

`PracticeQuestionModel` over `LLMService.completeStructured` (schema as §2), `PracticeQuestionGenerator`
(retrieval over `standard` documents → candidates → gate), `PracticeStore` (+ `DataStoreRegistry`
record, ET matrix, erasure walk; retirement on document removal, digest change and edition default),
`regulation_practice` tool (`quiz` with an optional topic or clause, `answer`, `skip`, `stop`,
`missed`, `learning_goal` → held proposal through IW's `accept`/`revise`/`decline`), the standing
"Go over what I've missed" goal, trail entries and the done suggestion, the Practice screen
(Settings › Field Assist › Practice questions) with role and the missed list opening `show_source`.

**Exit tests:** `PracticeQuestionGeneratorTests` with a fake model (a good candidate stored; a
hallucinated quote dropped; a table passage never sent to the model); `PracticeStoreTests`
(retirement cases; nothing written that is not in the item's fields); `RegulationPracticeToolTests`
(a session over invented fixtures; a miss joins the right step; a second miss in the same group
joins the same step; unsure counted as nothing); `LearningGoalTests` (a proposal from a fixture
section, stored only on accept; IW's evidence suggestion after two separate correct days);
`PrivacyLog` and trail tests that no question, answer or quote text is written;
`DataStoreRegistryTests` / `SubjectErasureTests` green.

### P2 — Questions from the day's jobs, and the drive

`JobPracticeContext` over `UpcomingJob`, `VaultModelIndex` and `JobHistoryIndex`, with empty
`PracticeContextSource`s for HV, HU and IS; `PracticeSetPreparer` (budgets, foreground or cloud-only
background); `DrivePracticePolicy` and its wiring in `CarPlaySceneDelegate` (offer after connect and
after the brief when that is on; the Jobs list row; the stop words routed before the model);
the IW budget stamp.

**Exit tests:** `JobPracticeContextTests` (the queries carry no customer, address, contact or fault
text; a job with no indexed model yields nothing); `PracticeSetPreparerTests` (caps; no background
run on the on-device model); `DrivePracticePolicyTests` — a table: no offer past IW's cap; an
interruption mid-question abandons it uncounted; walking guidance running → wait; a stop word →
stop with nothing further said; five questions then stop; disconnect → stop.
**Device pass (owed):** a real drive with directions handed to the maps app: what the audio session
reports when the maps app speaks, whether a question is ever cut by a prompt, and whether an
apprentice finds the pace right.

### P3 — Term answers and a measured gate

`AnswerKind.term` and the model-backed `PracticeGrading` judge with the deterministic guards (§3);
a local-only measurement on a developer's own licensed copy: the gate's pass rate per refusal
reason, and a hand check of a sample of accepted items for answer-key correctness by someone
qualified in that code. Only aggregate counts are recorded, in this plan. Loosening rule 5's
exceptions or rule 6's ranges is decided on that evidence, not before.

**Exit tests:** `PracticeGradingTests` with a fake judge (the key term short-circuits; a judge's
incorrect over a near-quote becomes unsure; a judge's unsure is never a miss).

## Decisions proposed (owner to confirm)

1. **Only `standard` documents are question sources**: never a manual, a team learning or an
   app-authored summary such as the bundled `epa_608.md`.
2. **The gate starts narrow**: single-rule prose that starts its own clause, a number with a unit
   or a yes/no, no exceptions, no ranges, no tables. It is widened only on P3's measured evidence.
3. **`unsure` and `notHeard` never count as a miss**, and the app says "check clause X yourself"
   rather than guessing.
4. **Learning goals are IW goals**: a seventh `StepAction` case, `practise`; steps come from the
   document's clause groups, not the model; done is suggested, never applied.
5. **One standing "Go over what I've missed" goal per document**, created on the technician's first
   yes, holding job-led misses by clause group (at most seven open steps).
6. **The drive offer counts against IW's two unprompted goal sentences a day**; an accepted session
   has its own budget: one offer per drive, at most five questions per drive and fifteen a day.
7. **Car questions are prepared before the drive**, never generated in the car; at most five per
   job, eight passages tried per job and twenty a day.
8. **Voice only in the car**: no question text or results on the car screen; one optional Jobs-list
   row to start a session.
9. **Job context is equipment words only**: never the customer, address, contact or fault report
   text.
10. **Results stay on the phone**, are the technician's own data, and are called practice, never an
    assessment; this plan builds no sharing.
11. **Apprentice role**: the drive offer is on by default; **qualified role**: off by default.

## Open questions for the owner

1. **Licence terms.** IN's open question 2, sharpened: does a publisher's single-user licence allow
   generated questions from the licensee's copy, stored on their phone? Per publisher, before this
   is marketed.
2. **When to widen the gate.** What measured accuracy on P3's hand check is enough to admit
   exceptions and ranges, and who is qualified to do that check for each code?
3. **A syllabus.** Should an organisation (or a training provider) be able to supply a topic list
   for apprentices — clause ranges only, no text — so learning goals follow a course rather than the
   technician's choice?
4. **Navigation prompts.** If the car pass shows the app cannot reliably tell when the maps app is
   about to speak, should drive questions be limited to drives without a route handed off, or kept
   with the abandon-on-interruption rule?
5. **Which model generates.** Cloud only, or the on-device model (JD) as well when the gate makes a
   weaker generator safe enough? Preparing in the background needs the cloud.
6. **Supervisor visibility.** Does an organisation want an apprentice's practice summary at all, and
   if so is it always the apprentice's send, never a standing share? The office half (FX / HO) is
   not designed here.
7. **EU AI Act.** Evaluating learning outcomes in vocational training (Annex III 3) and monitoring
   or evaluating workers' performance (Annex III 4) are high-risk uses from 2 Dec 2027. Personal
   practice that never leaves the phone is the design's position; any sharing with an employer
   needs a review in `docs/eu-ai-act-review-2026-10.md` first. Agree?
8. **Refrigerant regulations.** Once IS's amendment settles which Canadian, Australian and New
   Zealand texts an organisation loads, are they loaded as `standard` documents (and so practice
   sources), or are some public regulation texts the organisation may not have loaded at all?
9. **Pricing.** Part of the regulations add-on IN's open question 3 asks about, or of every Field
   Assist tier?

## Risks

- **A wrong answer key taught as right.** The gate is the whole defence: the quote must be the
  book's words, the answer must be inside it, and anything the app cannot settle is "unsure". P3's
  hand check is the evidence; until then the gate stays narrow.
- **Licensed text leaking.** Stored items are bound to their document and retired with it; no
  log, trail, report or export carries text; fixtures are invented and guarded by a test.
- **Distraction.** Voice only, quiet-window starts, abandon on any prompt, stop on any request,
  per-drive caps, and nothing on the car screen.
- **Nagging.** The offer sits under IW's two-a-day cap; a qualified technician is never offered
  unprompted.
- **Becoming an employer's assessment tool.** No sharing in this plan; open question 7 before any.

## Out of scope

Bundled question banks or exam material of any kind; multi-rule, table and calculation questions
(IN P3's calculators answer those); comparing editions (IN P4); the office's view of results and the
transport for it; apprentice logbooks (IQ, waiting on a partner's answers); practice from manuals
or team learnings; any language but English for spoken answers in P0–P2 (IN's amendment covers the
answer language; spoken-number parsing in other languages follows EC).
