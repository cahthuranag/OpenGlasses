# Plan JG — Regulation Practice (questions from a reviewed bank that ships inside a vault, checked against the organisation's own copy of the code, and an apprentice's questions on the way to the job)

**Status:** 📝 Drafted 2026-10-19 — nothing implemented. Revised the same day: a reviewed question
bank. Generation is not trusted as an answer key, so the phone never asks a question a person has
not approved. There is **one bank format**, shipped only inside a vault: the vault author builds
banks into the vaults they sell, and an organisation can build its own in Avenkin Office, inside
its own organisation vault. A bank never carries the book's text, and its items stay dormant until
the matching edition of the standard is loaded. The phone loads, validates, checks the signature
and asks. For an organisation it also proposes new questions back to the office, anonymously,
with FP's candidate pattern, and — only when the organisation turns it on, disclosed to the
technician — sends the technician's rule-graded right / wrong / unsure results to the office.
**Owner answers, 2026-10-19:** all twelve open questions answered and folded in as decisions — a
solo technician may write or draft and self-review their own questions (phone-only, labelled);
"quiz me on the <year> edition"; an optional syllabus in the bank; passenger mode in the car;
suggested employee-notice wording shown with the profile; transcription plus validation against a
human-approved key is not an AI system (decided; P1 records it in the AI Act review); refrigerant
texts are `standard` documents; a proposed tier split.
**Track:** Field Assist (B2B): the regulations vertical (electrical first, refrigerant next), for
apprentices and qualified technicians.
**Related:** Plan [IW](IW-goals-and-activity-trail.md) (goals, steps, `StepAction`, `GoalStore`,
`GoalAdvancePolicy`, check-ins, the activity trail: this plan's learning goals *are* IW goals),
Plan [IN](IN-verifiable-code-lookup.md) (clause references, citations, `show_source`, the passage
highlight, the `standard` document kind, editions), Plan [IV](IV-manual-retrieval-rounds.md) (what
retrieval on a code book actually achieves), Plan [EG](EG-vault-packs.md) (signed, sellable vault
packs), Plan [FS](FS-subscriber-vaults-and-vault-links.md) (vault links, publisher signatures,
`VaultReceipt`), Plan [HO](HO-office-delivery-phone-half.md) and the
[bulk content contract](../../Contracts/office-bulk.md) (an organisation's own publisher, office
manual delivery), Plan [FX](FX-desktop-office-and-device-sync.md) (the phone's connection to
Avenkin Office), Plan [FP](FP-team-learnings.md) (team learnings: the candidate → office review →
approved set pattern reused in §8), Plan [IF](IF-photographed-manuals.md) (copyright is the
organisation's decision), Plans [ED](ED-vault-manual-retrieval.md) /
[EJ](EJ-manual-retrieval-fidelity.md) (the retrieved manual tier), Plan
[FO](FO-guided-job-flow-and-job-tab.md) (jobs ahead, the brief, the CarPlay Jobs list), Plan
[EL](EL-equipment-identity.md) (equipment identity, `VaultModelIndex`), Plan
[HV](HV-site-system-vaults.md) (site and system vaults), Plan
[HU](HU-service-history-and-maintenance-flags.md) (the office's service history and flags), Plan
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
only; the second family is refrigerant regulations (IS). **Revised 2026-10-19** on the owner's
question "is generation 100% accurate?": no. A question is asked only once a senior technician or
the vault author has approved it, and the bank travels inside a vault like the rest of the
vault author's work.

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
not a retrieval problem at all. Number-dense tables are where passages are weakest. A model that
drafts a question from one of those passages can be wrong in the question, the answer or the
clause, and no check on the phone can prove it right. A person qualified in that code can. So the
answer key is a **reviewed bank**: drafted by whoever likes, approved by someone who knows the
code, and asked only after that.

## Outcome

- "Quiz me on the code." → "Okay, five questions from the wiring rules you've loaded. First: what is
  the least height above a finished floor for a widget, in millimetres?" → "Six hundred." → "That's
  right. Clause 9.4.7: not less than 600 mm above a finished floor." (Invented clause and wording,
  as in every example here.)
- A miss: → "Four hundred." → "Not quite. Clause 9.4.7 says not less than 600 mm. I've put it on
  your list." The clause joins a learning goal and comes back on a spacing schedule until it is
  answered right on two separate days.
- When the app cannot be sure — a free-form answer it cannot match, a word it did not catch — it
  says so and does not mark it wrong: "I can't be sure that matches. Check clause 9.4.7 yourself;
  it's on your list to look at."
- A solo technician who has bought a vault with a question bank, and loaded the edition of the
  standard it was written for, practises from it. Without such a vault: "Practice questions come
  with a vault that includes a question bank. None of your vaults has one yet. You can also write your own."
- A technician can also write their own questions, or ask the phone to draft some from their own
  copy and confirm each one: "Draft questions on clause 4.3." They are labelled "your own
  questions", graded "against your own answer", and never leave the phone.
- In the van as a passenger: "Are you driving, or a passenger?" → "Passenger." The session can run
  longer and the phone's screen shows each question and answer; the car screen still shows nothing.
- A technician whose organisation runs an office practises from the vault author's bank and the
  organisation's own bank side by side; each question says where it came from on the phone's
  screen ("From the wiring rules vault" / "From your organisation").
- When a newer edition of the standard is loaded and becomes the default, the old edition's
  questions stop being asked: "These questions were written for the 2018 edition (invented). They
  come back once the vault is updated for the edition you use now."
- "Make a learning goal: the earthing part of the code before my exam on the first of March." →
  the goal's steps are the clause groups that the bank has questions for; IW's screens, check-ins,
  My Day row and trail carry it unchanged.
- An apprentice gets into the van with Job 1007 ahead, a heat pump with a three-phase supply. When
  CarPlay connects (after the brief, if the brief is on): "Want three questions on the way? Two are
  about the heat pump at 1007." → "Go on." Questions come one at a time, between navigation prompts,
  and stop the moment the apprentice says anything else.
- After the drive, the phone shows what was missed, each row opening the clause's page with the
  passage highlighted (IN's viewer), from the organisation's own copy.
- In an organisation, a missed clause, or a clause a code-lookup answer cited that the bank has no
  question for, may become a **proposed** question sent to the office for its senior technician to
  approve. The proposal never says who missed it or when.
- Results are the technician's own **unless the organisation turns on "Share practice results with
  the office"** (off by default). Then the phone sends, per question, the clause, edition, item,
  right / wrong / unsure and the date under the technician's name, and the Practice screen shows
  exactly that before the first send and ever after. Only answers matched by fixed rules are
  shared; anything a model judged stays on the phone.

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
  `clauseMatch`, `editionLabel`, `recognisedFromScan`, `printedPage`. `PassageLocator`
  (`Services/RAG/PassageLocation.swift`) finds a passage's sentences on its PDF page after folding;
  `show_source` opens what an answer cited, highlighted. `StandardDocumentOpenPolicy.isStandard`
  reads a manifest document's `kind == "standard"`; `VaultDocument` carries `edition`;
  `DocumentEditions` picks the newest edition (IV P2). The `standard` kind's import step and IN P3's
  answer rules are unbuilt.
- **Vault format and how vaults arrive.** `VaultManifest` (`Services/Vault/VaultManifest.swift`)
  holds `files`, `documents_dir`, `documents: [VaultDocument]`, `documents_included`,
  `procedures_dir`; `VaultValidator.validate(directory:)` checks a folder before import, including
  `procedures/*.json` through `validateProcedureGraph`. Three signed routes exist:
  **EG packs** (`VaultPackManifest`, `VaultPackCatalogService.installPack(zipData:signatureBase64:expectedId:)`,
  vendor-signed with `SkillPackSignature`, entitlement through `VaultRegistry.isUnlocked`);
  **FS vault links** (`VaultLinkPolicy`, `VaultLinkService`, `VaultLinkInstaller`, the review
  sheet in `VaultLinkReview`; `VaultArchiveVerification` is `.signed(publisherId:publisherName:)`
  for a catalogue-listed publisher, `.unverified(.notSigned | .unknownPublisher)` installable at
  the reader's own risk, or `.refused(.signatureInvalid | .contentsAltered | .revokedPublisher |
  .headerDoesNotMatchVault)` with no override; the result is kept in `VaultReceipt.verification`);
  and **office delivery** (HO P4, opt-in office transport build: `OfficeManualService` and
  `OfficeManualImport` verify an archive with the organisation's own publisher, granted by the
  administrator key under the vendor-signed profile — bulk contract §3 — and hand it to the existing
  installer). `Scripts/make-vault-archive.swift` builds and signs an archive. A folder import is
  never signed.
- **Vault-author docs.** `docs/field-assist-vault-guide.md` (Steps 1–7, receiving and publishing a
  vault, three sharing situations), rendered to the site and PDF by
  `Scripts/build-vault-guide-page.py`.
- **Cross-repo contracts.** `Contracts/` holds the phone ↔ office agreements (manual assignment,
  bulk content, team learning, captured manual, …) with golden fixtures in `Contracts/fixtures/` and
  portable checks in `Contracts/tests/` (`test_manual_contracts.py` copies the app's Swift sources
  unchanged into a temporary package and runs them against the fixtures).
- **Team learnings (FP P0–P3).** `LearningCandidate` / `LearningCandidateStore` (filed on the phone),
  `LearningReview` (a pure state machine; `Approver { name, role }`), `LearningSafetyCheck`,
  `LearningBundle` (unsigned, strict decoder `LearningBundleJSON`), `LearningBundleOutbox`
  (`composeCandidates`, `deliveryRequest(for:channel:)`, `queuedOp(for:)`, `delivered`),
  `DeliveryRequest.Payload` (`workRecord`, `learningBundle`, `capturedManual`), `OpKind` in
  `Services/Offline/QueuedOp.swift`, `OfficeReportSink.handledKinds` (`workRecord`, `partsRequest`,
  `capturedManual`), and the office-side contract `Contracts/team-learning.md` (design only).
  `Config.teamLearningReviewerDevice` marks a reviewer device; `FieldAssistCapability.teamLearnings`
  is granted to team and enterprise licences only.
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

- **The app ships no question bank.** No question from any book is in the app, a bundled vault, a
  fixture, a log, a support report or an export. A bank arrives only inside a vault (§2), from the
  vault author or from the organisation's own office.
- **A bank never carries the book's text.** The format (§2) is a closed schema with no field a
  passage could ride in: a clause number, a short question, a short expected answer, and — at most —
  an *anchor*, the word count and SHA-256 of the quote's folded words, which the phone uses to find
  the quote in **the organisation's own loaded copy**. What is spoken or shown as the book's words
  is always read from that copy at the moment it is needed, and only when the copy is there.
- **Who answers for the publisher's terms.** A stored question and answer are derived from the
  licensed text. For a bank the vault author sells, the vault author is responsible for their
  publisher's terms, exactly as the vault guide already makes them responsible for the manuals they
  supply. For a bank an organisation builds itself, the organisation decides, as IF decided for
  photographed manuals. **Decided 2026-10-19:** the app builds the capability and enforces that the
  organisation's own copy is loaded before anything is asked; whether a derived bank is permitted is
  the publisher's agreement with the vault author or the organisation, and rules differ by country.
  It is not the app's to settle and does not block this plan.
- **The only model egress is the call the organisation already permits for manual answers**, and
  only in three places: drafting a proposal for the office (§8), drafting a technician's own
  questions (§3a) and the free-form judge (§4, P6).
  Asking and grading numbers and yes/no answers make no model call at all. Under Medical Local Only,
  or with cloud models off, drafting uses the on-device model or does not happen, and term answers
  are skipped.
- **Logs and the trail carry counts and clause numbers only.** `PrivacyLog` events, the activity
  trail and the support report never carry a question, an answer, a quote or a section heading.
- **Fixtures are invented.** Tests, `Contracts/fixtures/question-bank-*` and the author guide's
  worked example use clause numbers and wording made up for the purpose ("Clause 9.4.7 (invented):
  A widget shall be mounted not less than 600 mm above a finished floor"), and a guard test fails on
  any practice fixture without the "(invented)" marker.
- **Only documents the vault marks as regulations are sources.** A bank file names a manifest
  document of kind `standard` (IN). A manual, a team learning (FP) and an app-authored reference
  such as the bundled `epa_608.md` cannot carry a bank. A summary is not the regulation, and an
  answer key built from one inherits its mistakes.

### 2 · One bank format, inside a vault

There is one format, used by the vault author's vaults, an organisation's own vaults and Avenkin
Office alike. Its contract is **`Contracts/question-bank.md`** (draft v1, written in P0), with
golden fixtures and portable checks beside the other cross-repo contracts.

**Where it lives.** `VaultManifest` gains `practice_dir` (like `procedures_dir`); each file in it,
`practice/<name>.json`, is the bank for **one standard document at one edition**:

```json
{
  "schemaVersion": 1,
  "kind": "avenkin.question-bank",
  "bankId": "wiring-rules-questions",
  "revision": 3,
  "document": {
    "file": "wiring-rules-2026.md",
    "edition": "2026 (invented)",
    "fingerprint": [ { "words": 12, "sha256": "…" }, { "words": 9, "sha256": "…" } ]
  },
  "items": [ {
    "id": "0f6c…", "revision": 1,
    "clause": "9.4.7",
    "question": "What is the least height above a finished floor for a widget, in millimetres? (invented)",
    "answerKind": "number",
    "expected": { "value": "600", "unit": "mm" },
    "variants": [], "tolerance": null,
    "anchor": { "words": 14, "sha256": "…" },
    "car": true,
    "equipment": ["widget"],
    "approval": { "role": "Senior technician", "approvedOn": "2026-10-19", "drafted": "authored" }
  } ],
  "retired": [ { "id": "7a21…", "reason": "withdrawn" } ],
  "syllabus": [
    { "id": "earthing", "title": "Earthing and bonding (invented)", "clauses": ["4.1–4.3", "4.5"] }
  ]
}
```

- **Items.** `id` (32 lowercase hex) and `revision`; `clause` in `ClauseReference`'s syntax;
  optional `figure` ("Table 4 (invented)") for an item about a table or figure; `question` (at most
  160 characters); `answerKind` `number` | `yesNo` | `term`; `expected` — `{ value, unit }` with the
  value as a **decimal string** (so every reader parses the same value; the strict reader refuses
  JSON fractions and exponents), `{ yes: true|false }`, or `{ term }` (at most 60 characters);
  `variants` (up to eight more accepted answers of the same shape); `tolerance` (a decimal string in
  the expected unit, numbers only, absent means exact); optional `anchor`; `car` (whether it may be
  asked by voice in the car: at most 25 spoken words in the question); optional `equipment` (up to
  eight lowercase words, for choosing questions for a job, §5); and `approval`.
- **The approval record is mandatory.** `role` (who approved, as the organisation names the role),
  optional `name`, `approvedOn` (a date, no time), and `drafted`: `authored` (a person wrote it),
  `modelDrafted` (a person approved a model's draft) or `proposed` (it began as a phone's proposal,
  §8). **A file holds approved items only**: there is no unreviewed, pending or rejected state in the
  format, because the format is what is published. Drafts and rejections live wherever the review
  happens — the vault author's own tools or Avenkin Office — never on a phone.
- **Edition keying.** `document.file` names a `standard` document in the same manifest;
  `document.edition` must equal that document's `edition`; `document.fingerprint` (one to five
  anchors, chosen by the author from that edition's text) is how a phone tells that the copy it has
  loaded really is that edition, whatever its file name or its purchaser's watermark. An item is
  keyed by document + edition + clause.
- **Retirement.** `retired` lists item ids withdrawn since an earlier revision, with a reason
  (`withdrawn`, `superseded`, `editionChanged`). An id absent from a later revision without a
  retirement is also gone: a bank file is a whole set, replaced on each vault update.
- **Syllabus (optional, decided 2026-10-19).** An ordered list of topics, each an `id`, a `title`
  (at most 80 characters, the author's own words, no book text) and clause ranges in
  `ClauseReference`'s syntax. It lets a vault author or an organisation lay out a course — say, an
  apprentice year — that learning goals can follow (§7). It carries no questions of its own; a topic
  with no live items is skipped.
- **Folding.** Anchors are SHA-256 over the quote's words after one folding both sides compute the
  same way — the contract spells it out (Unicode NFKC, case folded, whitespace collapsed, line-end
  hyphens joined, quotes and dashes normalised) and pins it with fixtures; `PassageLocator`'s fold
  is the reference.
- **Limits.** 2 MiB a file, 2,000 items a file, every string capped, no control or bidirectional
  override characters, unknown keys refused by path, duplicate ids refused. The strict reader is
  FP's `LearningBundleJSON`, reused.

**Why tables, exceptions and ranges are allowed here.** A person has checked the item against the
book, so the bank may ask what the narrow pre-filter (§8) would never let a model draft: a table
cell ("From Table 4 (invented), the least conductor size for a 32 A circuit?"), an exception ("Is a
widget in a dry store exempt from clause 9.4.7 (invented)? Yes or no.") or a bound of a range. Such
an item still uses one of the three answer kinds and still cites its clause; it may have no anchor,
and then the confirmation speaks the approved answer and the clause instead of a quote (§4).

**Validation, two places, one code.** `PracticeBankValidator` (pure over bytes) is the app's
check, run by `VaultValidator` on `practice_dir`, so a vault with a bad bank is refused at import
exactly like a bad procedure. The same source file is what the vault author runs: a new
`Scripts/check-question-bank.swift <vaultDir>` builds it unchanged into a temporary package, as
`Contracts/tests` already do, and `Scripts/make-vault-archive.swift` refuses to build an archive
whose bank fails. The author's check and the phone's cannot disagree.

**The vault-author guide.** `docs/field-assist-question-bank-guide.md` (new in P0), linked from a
new optional step in `docs/field-assist-vault-guide.md` and rendered by the same
`Scripts/build-vault-guide-page.py`: what a bank is and is not (no book text), every field, the
approval record and what it promises, edition keying and how to choose fingerprint anchors, how
retirement and new editions work, the optional syllabus, a worked example with invented clauses that the contract test
validates, how to run the checker, and the rights paragraph — the author must hold the right to
publish questions derived from the standard.

### 3 · Who may publish a bank, and when an item is asked

**Approved by publication.** The phone does no review. An item counts as approved because its
vault came from a signed source, and only then. `PracticeBankTrust.verdict(for:)` (pure) reads how
the vault was installed:

| How the vault arrived | Verdict | Items |
|---|---|---|
| EG pack, vendor-signed, installed by `installPack` | `.pack(id)` | asked |
| FS archive, `VaultReceipt.verification == .signed` by a catalogue-listed publisher (the vault author's own site) | `.publisher(id, name)` | asked |
| Office assignment, verified with the organisation's granted publisher (bulk §3, `OfficeManualService`) | `.organisation(publisherID)` | asked, shown as the organisation's |
| FS archive unsigned or from an unknown publisher; folder import; the bundled vaults | `.none` | **dormant**: "This vault isn't signed, so its questions aren't used." |
| Bad signature, altered contents, revoked publisher | (refused at install, no override) | none: the vault never installs |

A revoked publisher's vault that is already installed is kept, as FS keeps it; its bank goes
dormant. The organisation's publisher is honoured only through an office assignment (bulk §3), so
an organisation-signed archive arriving by link is an unknown publisher's and its bank is dormant.

**Who builds banks, by customer.**

- **A solo technician** buys the vault author's vaults — an EG pack, or a signed archive from the
  vault author's own site through FS's link and QR route — and practises from the banks inside them.
  They may also keep **their own questions** (§3a), self-reviewed and on that phone only.
- **An organisation** may buy the same vaults, and may also build its own bank in the same format
  inside its own organisation vault. Authoring, model-drafted candidates, the senior technician's
  approve / edit / reject, retirement and re-review happen in **Avenkin Office** — the office half,
  to be drafted as an FX-series plan in the private office repository and not designed here. The
  organisation's vault reaches phones the way organisation vaults already do: an office assignment
  over HO's transport, verified with the organisation's publisher. Building a bank is a team and
  enterprise capability; on the phone it needs nothing new, because the organisation's publisher
  exists only under a vendor-signed organisation profile, which a solo licence cannot hold. The
  Office enforces it at authoring.
- **Side by side.** Items from a bought vault and from the organisation's vault are one pool to the
  selector, each carrying its origin (`PracticeItemOrigin.vault(vaultId, publisherName)` /
  `.organisation`), shown on the phone's screens. When two items cite the same clause, a session asks
  at most one of them.

**`PracticeBankIndex`** (rebuilt on every vault install, update and removal) reads every installed
vault's banks and gives each item a status, computed by the pure `PracticeItemStatus.of(item,
bank, vault, loadedDocuments)`:

- **`live`** — the vault is unlocked (`VaultRegistry.isUnlocked`) and its trust verdict is not
  `.none`; the bank's document is loaded with text; every fingerprint anchor is found in it; the
  document is the default edition of its work (`DocumentEditions`); and, when the item has an
  anchor, the anchor is found among the clause's own passages (`DocumentStore.passages(clause:)`).
  Only live items are ever asked.
- **`dormant(reason)`** — `.unverifiedVault`, `.vaultLocked`, `.documentNotLoaded`,
  `.editionNotLoaded` (the loaded copy fails the fingerprint), `.anchorNotFound`. Not asked; the
  Practice screen says why in one line. Dormant items wake on their own when the reason goes.
- **`needsReReview(.newerEditionDefault)`** — a newer edition of the same work is loaded and has
  become the default. Not asked by default, and not silently kept: the screen says the questions are
  for the older edition and wait for the vault's update. **Named edition (decided 2026-10-19):** when
  the technician asks for that edition by name ("quiz me on the 2018 edition"), its items — needs
  re-review ones included, provided the older copy is still loaded and passes its fingerprint — are
  asked for that session, each session opening "These are from the 2018 edition, not the one you
  use now." and every confirmation naming the edition. The vault author (or the organisation's office)
  ships a new bank file keyed to the new edition, re-approved; nothing on the phone re-approves.
- **`retired(reason)`** — listed in `retired`, absent from a later revision, or its vault removed.
  Its progress is dropped with it; trail entries already written (counts only) stay.

An item whose `revision` rises with a changed expected answer starts again in box 1 with no miss
recorded, because the key it was learned against changed; a revision with the same answer keeps its
place.

**Refrigerant regulations (decided 2026-10-19).** The refrigerant regulation texts an organisation
loads — including the Canadian, Australian and New Zealand texts IS's amendment settles — are
`standard` documents and may carry banks, exactly like the electrical code.

### 3a · Your own questions (self-reviewed, on this phone only)

**Decided 2026-10-19 (reversing the earlier recommendation):** a solo technician may write, or have
the phone draft, questions for their own learning and approve them themselves. This is the **one
narrow exception** to "the phone never generates an askable question", and it is fenced:

- **Where they come from.** Written by hand on the Practice screen (clause, question, answer kind,
  expected answer, variants, tolerance; the clause must be in a loaded `standard`), or drafted by
  `PracticeQuestionModel` from **the technician's own loaded copy** of a `standard`, through
  `QuestionAnswerabilityGate` (§8) as the pre-filter. A draft is never live: the technician sees it
  beside its clause's passage and confirms, edits or discards each one. Drafting asks for a clause
  or clause group ("draft questions on clause 4.3"), at most ten drafts a day.
- **What they are.** `PracticeItemOrigin.own`, approval `selfReviewed(on:)`, kept in
  `OwnPracticeStore` (`SensitiveStore.ownPracticeItems`: wearer-linked, first-unlock protected,
  backup-excluded, the erasure walk). Bound to the document and edition like a bank item (an anchor
  located on the phone, the fingerprint of the copy they were written against), so they go dormant
  and to needs re-review by the same rules.
- **Labelled everywhere.** Listed as "Your own questions" on the Practice screen and in the missed
  list; a session that uses one says "One of your own:"; grading says "That matches your own
  answer." / "That doesn't match your own answer of 600 mm. Clause 9.4.7." — never "That's right",
  because no one else checked the key.
- **Never leaves the phone.** Never in a vault, a bank file, `VaultExporter`'s output, a team
  learning bundle, a proposal (§8), the results feed (§10), a support report or any
  `DeliveryRequest` or `QueuedOp`. Never merged into `PracticeBankIndex`'s bank items: the selector
  takes them from their own store, and a clause that has a bank item asks the bank item first.
- **In the car and in goals.** Own questions marked for the car may be asked on a drive, with the
  same lead-in; they may feed the technician's own learning goals, whose done suggestion then says
  "on your own questions".
- **Organisation technicians (proposed, owner to confirm):** yes, private only — the same route on
  an organisation's phone, never shared and never counted in anything the organisation sees. An
  organisation profile may switch the route off and lock it (`SettingKey.ownPracticeQuestions`, a
  ceiling), but never reads it. The rule "the phone never generates an askable question" holds for
  everything the organisation's bank, results or proposals touch.

### 4 · Asking, grading and the spacing schedule (pure)

```swift
struct PracticeItem { bankId, id, revision, origin: PracticeItemOrigin, documentFile, edition,
                      clause, figure?, question, answerKind, expected: ExpectedAnswer,
                      variants: [ExpectedAnswer], tolerance: Decimal?, anchor: QuoteAnchor?,
                      car: Bool, equipment: [String], approval: PracticeApproval }
enum ExpectedAnswer { case number(value: Decimal, unit: String) case yesNo(Bool) case term(String) }
struct PracticeAttempt { itemKey, at, outcome: PracticeOutcome }
enum PracticeOutcome { case correct, incorrect, unsure, notHeard, skipped }
```

- **`SpokenAnswerParser` + `AnswerGrader` (pure, `number` and `yesNo`).** A spoken value ("six
  hundred", "six hundred mil", "point six of a metre", "sixty amps") is parsed and normalised
  through `UnitNormalizer`, which gains length, current and time. It is graded against the
  **approved** expected answer and its variants: equal after normalisation, or within the
  reviewer's tolerance → `correct`; a different value of the same dimension → `incorrect`; no value
  found, or a value in another dimension → `notHeard` ("I didn't catch a number"). No tolerance
  unless the bank gives one. A bare number with no unit is graded in the unit the question named.
  Yes/no reads "yes", "no", "it shall", "it can't" and refuses to guess on anything else
  (`notHeard`).
- **`term` answers (P6)** go through `PracticeGrading`, a protocol whose model-backed judge sees
  only the question, the approved answer and its variants, and the technician's answer — **never
  the passage** — and returns `correct`, `incorrect` or `unsure`. Deterministic guards sit on both
  sides: the approved term or a variant found in the answer is `correct` without a model call; a
  judge's `incorrect` on an answer that shares most of the approved answer's content words becomes
  `unsure`. **`unsure` and `notHeard` never count as a miss.**
- **`PracticeSchedule` (Leitner, pure).** Five boxes, re-asked after 0 (later in the same session),
  1, 3, 7 and 21 days. `correct` moves an item up a box; `incorrect` sends it to box 1 and onto the
  technician's "to go over" list; `unsure`, `notHeard` and `skipped` leave it where it is. An item is
  **learned** in box 3 or above: answered right on at least two separate days.
- **`PracticeSelector` (pure).** Picks a session's items from **live items only**: due review items
  first, then items for today's jobs (§5), then new items for the next open step of an active
  learning goal — capped per session, never the same clause twice in one session (whatever bank it
  came from), a miss re-asked at most once later in the same session.
- **`PracticePhraser` (pure, exact strings).** The question; "That's right. Clause 9.4.7: …" with the
  anchored words read from the loaded copy (IN P3's rule: never paraphrase a requirement without its
  clause); for an item without an anchor, "That's right: 600 mm. Clause 9.4.7." (with the figure
  when there is one); "Not quite. Clause 9.4.7 says … I've put it on your list."; the unsure and
  not-heard lines; the session's close ("Two of three. Clause 9.4.7 is on your list."). A quote is
  cut to at most 25 words when spoken in the car, with "the rest is on your phone".

### 5 · Questions from the day's jobs

`JobPracticeContext` (pure) turns a job ahead into a choice among **live items**, from **equipment
words only**:

- `UpcomingJob.equipment` resolved through `VaultModelIndex` to the model's vault section: its
  category words ("heat pump", "outdoor unit", "three-phase", "gas-fired"), never a serial;
- this phone's `JobHistoryIndex` visits on the same serial or site: parts replaced and work done
  ("replaced the contactor") — equipment words, not the debrief's free text;
- **when built:** HV's site document (connection kinds and media: `power`, `fluid`/refrigerant), HU's
  flag kinds (`recurring_failure`, `overdue_maintenance`) and parts, HU's `site_requirements` kinds,
  and IS's refrigerant and charge for the unit. Each enters through a `PracticeContextSource`
  protocol that is empty until its plan lands.

Items whose `equipment` words match come first; then the words are run as at most three retrieval
queries over the organisation's loaded `standard` documents and the live items on the clauses that
come back are taken. No model is involved. Never the customer, address, contact, fault report text
or office notes: those are the organisation's data about a person, and choosing a question does
not need them.

**Chosen before the drive.** `PracticeSetPicker` picks a job's set (at most five, `car == true`
only) when the job arrives or changes, and on demand, so the car never waits on retrieval. A job
with no matching live item gets no set, and the car offers nothing for it.

### 6 · In the car: voice only, short, and second to the road

`DrivePracticePolicy.next(inputs) -> DriveStep` (pure) decides `.offer`, `.ask(item)`, `.wait(reason)`
or `.stop(reason)` from:

- CarPlay connected, Field Assist active, practice on, the role's default (§9), a picked set of live
  `car` items for a job ahead today;
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
  measures on a real car what that is. **Decided 2026-10-19:** routes handed to the maps app are the
  normal case, and drive questions stay on them under this abandon-on-interruption rule;
- **listening.** One answer window of eight seconds; silence is `skipped`, not wrong;
- **stopping.** "Stop", "not now", "enough", "later", the wake word followed by any other request,
  a call, or CarPlay disconnecting ends the session at once. Nothing more is said in that drive
  unless asked; the close line is skipped when the stop was the technician's.

Nothing is shown on the car screen beyond the voice states the app already uses: no question text,
no list of misses. The CarPlay Jobs list's upcoming-job page may gain one row, "Questions on the
way", which starts the same session (`CarPlayJobsList.UpcomingAction.practice`). "Quiz me on the way
to 1007" works by voice at any point in the drive, within the same per-drive caps. Only live items
(and the technician's own, §3a) are ever asked in the car, as everywhere else.

**Passenger mode (decided 2026-10-19).** Once per drive, when a session starts, the phone asks
"Are you driving, or a passenger?" `DriveRole { driver, passenger, unknown }`: only the word
"passenger" (or "I'm a passenger") sets `passenger`; anything else, silence or no answer is
`unknown`, which gets the driver rules. The phone **never infers** passenger by itself — not from
motion, not from CarPlay, not from a previous drive — and the answer lasts until CarPlay
disconnects. As a passenger:

- the caps relax: up to fifteen questions in the drive, and the day's cap rises from fifteen to
  thirty; the offer itself still counts under IW's two-a-day cap, and the quiet rule (no starting
  over other audio, abandoning on a prompt) stays, because the driver still needs to hear
  directions;
- **the phone's screen** may show the question, the answer and the clause's passage as they are
  spoken; the **car screen still shows nothing** beyond the voice states;
- the technician can say "I'm driving" at any time, which returns to driver rules for the rest of
  the drive.

Driver rules — voice only, nothing on any screen, the five-a-drive cap — apply whenever the role is
`driver` or `unknown`.

### 7 · Learning goals are IW goals

No second goal model. A **learning goal** is an IW `Goal` whose steps carry a practice offer:

- **`StepAction.practise(topic: PracticeTopic)`** — a seventh case in IW's closed set, persisted as
  kind `practise`, mapped to the `regulation_practice` tool. `PracticeTopic { documentFile, edition,
  clausePrefix ("4.3"), label }`. Older builds decode it as an unknown kind and keep the step, as IW
  designed. `StepActionPermission` offers it only when the tool is enabled (an organisation's
  `closedTools` and IP switch included), Field Assist is active and the topic still has live items.
  `StepActionRun` maps "Do it" to a practice session on the phone for that topic.
- **Steps come from the bank and the document, not the model.** "Make a learning goal: the earthing
  part of the code" finds the section in the loaded standard; `TopicPartitioner` (pure) groups the
  **live items' clauses** in that section by number prefix into 3–7 steps ("Clauses 4.1–4.2",
  "Clauses 4.3", …, with the heading as the citation already shows it); a clause group with no live
  item is not a step, because there would be nothing to practise. **Following a course (decided
  2026-10-19):** when the bank carries a `syllabus` (§2), "make a learning goal from the course" (or
  "the earthing topic of the course") takes the steps from its topics in order instead, each step a
  topic's clause ranges, still keeping only steps with live items. The proposal goes through
  `GoalProposalParser` and is held and read back exactly as `GoalDrafter`'s are; nothing is stored
  until `accept`. A due date ("before my exam on the first of March") is the goal's `dueAt`, and
  IW's default cadence applies.
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
- **Editions.** When a newer edition becomes the default, the older edition's items go to
  `needsReReview` (§3), and a learning goal on the older edition gets one sentence on the Goals
  screen: "These questions were for an older edition. They come back when the vault is updated, or
  ask for the 2018 edition by name."
  When a bank for the new edition arrives, "Practise from the new edition instead?" (a new goal, on
  yes). Comparing what changed is IN P4's.

### 8 · Proposing questions to the office (organisations only, anonymous)

A bank grows best from what technicians actually stumble on. In an organisation, the phone may
**draft** a candidate question and send it to the office for the senior technician to approve, on
FP's pattern — candidate on the phone, review in the office, the approved set delivered back — with
one difference that matters: **a proposal carries nobody's identity**.

**Triggers.**

- **(a) A miss or an "unsure".** The technician misses, or answers unsure to, a bank question → the
  phone drafts one or two candidates on the same clause or a sibling clause in its group (a second
  angle on what was hard).
- **(b) A gap.** During a job, a code-lookup answer cites a clause the installed banks have no item
  for → a gap candidate for that clause.

**Drafting.** `PracticeQuestionModel` (a protocol, one structured completion per passage, like
`GoalDraftModel`) is given one passage from the organisation's loaded copy, its clause and the
answer kinds allowed, and returns up to two drafts `{ question, answerKind, expected, quote,
clause }`. `QuestionAnswerabilityGate.check(draft, passage, document) -> GateVerdict` (pure) is the
pre-filter, so the office's reviewer does not spend time on drafts no passage can settle. It accepts
only when every rule holds, and otherwise names the first failing reason:

1. **Source.** A `standard`, the default edition, not read by recognition (`recognisedFromScan`). →
   `.notARegulation`, `.olderEdition`, `.scannedSource`.
2. **Prose, not a table.** `kind == .prose`, no table `figure`, not a contents page
   (`ClauseReference.looksLikeContents`), numeric-token share under a table threshold. →
   `.tableOrFigure`.
3. **The clause is the passage's own.** `ClauseReference.match` is `starts` or `startsSubclause`
   (IV class (c)). → `.clauseNotOwned`.
4. **The quote is the book's words.** Found verbatim after `PassageLocator`'s folding, 6–40 words. →
   `.quoteNotFound`, `.quoteLength`.
5. **One rule.** One requirement word, no cross-reference, no exception. → `.multiRule`,
   `.crossReference`, `.exception`.
6. **The answer is in the quote**, with no second value of the same dimension, polarity agreeing. →
   `.answerNotInQuote`, `.ambiguousValue`, `.polarityMismatch`.
7. **A fair question.** Does not contain the answer, at most 160 characters and 25 spoken words,
   names the unit. → `.answerGiven`, `.tooLong`, `.noUnit`.

A draft that fails is dropped, never repaired; a gap whose drafts all fail is still sent as a
**bare gap** (the clause, no draft) — "questions wanted here" is useful to the reviewer on its own.
**Passing the gate makes nothing askable.** A candidate is never asked on any phone, the one that
drafted it included; it becomes a question only when the office approves it and it comes back in
the organisation's bank with `drafted: "proposed"`, approved by the office's reviewer.

**The payload is anonymous by design** (EU AI Act Annex III 4: monitoring or evaluating workers).
`PracticeCandidate` carries exactly: the document file and edition, the edition's fingerprint, the
clause, the drafted question and expected answer (or none, for a bare gap), the quote as an anchor
(word count and digest, never the words: the office shows the passage from its own copy), the
trigger kind (`miss` | `gap`) and the **day** it was drafted. It carries **no** technician name or
id, device name, enrolment id, job reference, site, score, attempt history, answer the technician
gave, or time finer than a day. The trigger `miss` folds "missed" and "unsure" together, so the
payload does not even say how the person answered. Candidates leave in one daily batch in shuffled
order, so arrival time does not tie one to a job.

**Seams, reused from FP.** `PracticeCandidate` / `PracticeCandidateStore` follow `LearningCandidate`
/ `LearningCandidateStore`; `PracticeCandidateOutbox` follows `LearningBundleOutbox`
(`composeCandidates`, `queuedOp(for:)`, `delivered`); `DeliveryRequest.Payload` gains
`.practiceCandidates(_:)`; `OpKind` gains `practiceCandidates`, added to
`OfficeReportSink.handledKinds` so it rides HO's office transport. The office intake — verifying,
storing, aggregating, review — is the office half's, and the message is specified in
`Contracts/question-bank.md` §"Candidates (phone → office)". There is no email or share-sheet route
for proposals: they exist only where an office reviewer does.

**Requirements on the office intake** (stated in the contract, built in the office): the transport
knows which phone a batch came from, so the intake must not keep or show that against a candidate.
Identical candidates (same document, edition, clause and folded draft) aggregate into one with a
count — "proposed from 4 phones" — without saying which; counts below three are shown as "proposed
more than once" or not at all, so a crew of two cannot read off who missed what.

**Kept apart from the results feed (§10).** When an organisation also shares results, a
miss-triggered proposal dated to the day could be joined to a named "wrong on 9.4.7 that day".
So while results sharing is on, a miss-triggered proposal is dated to its ISO week, not its day,
and leaves in a weekly batch; the office half must not join the two feeds. Gap proposals keep the
day.

**Limits on the phone.** At most five candidates a day per phone (`PracticeCandidatePolicy`, pure);
one per clause while it is pending; never one for a clause that already has a live item from the
organisation's bank, or a pending candidate from this phone; a pending candidate clears when the
organisation's bank gains an item on its clause, or after 60 days. The store keeps pending
candidates only, first-unlock protected, backup-excluded, registered in `DataStoreRegistry` and
walked by the subject erasure.

**The technician decides.** The Practice screen says plainly: "Questions you miss may suggest new
questions to your office. They never say who suggested them." A switch, **Suggest questions to my
office**, on by default in an organisation, turns it off; an organisation profile may switch it off
for everyone and lock it, but cannot force it on. A solo technician has no office: misses feed only
their own schedule, and no proposal is drafted. **Decided 2026-10-19:** a solo technician's gaps may
later go back to the vault author as anonymous, opt-in feedback (the same payload shape, a route the
vault author runs); not in this plan's phases. Beyond proposals and §3a, the phone drafts nothing.

### 9 · Roles and results

- **`PracticeRole { apprentice, qualified }`**, set by the technician in Settings › Field Assist ›
  Practice questions. An organisation profile may set the default but not hide the setting. For an
  apprentice the drive offer is on when practice is on; for a qualified technician it is off and
  practice is by request ("quiz me"), with edition refreshers later.
- **Results are kept on the phone as the technician's data.** `PracticeProgressStore` is
  `SensitiveStore.practice` (wearer-linked, `deleteAll`, the erasure walk, the HIPAA retention
  honoured), keyed by bank, item and revision, and kept apart from the banks, which live in their
  vaults and are the same on every phone. The Practice screen shows each bank with its origin and
  how many items are live, dormant (and why) or waiting for an update; boxes, learned clauses and
  the "to go over" list, each opening the clause's page through IN's viewer.
- **It is practice, not an assessment, on the phone.** Copy says so; the phone computes no score,
  pass, rank or competence rating, and keeps no record that could stand for a sign-off. What an
  office does with shared results (§10) is the office half's, under the rules there.

### 10 · Sharing results with the office (an organisation setting, off by default)

An organisation may want an apprentice's practice record — which clauses were asked, which were
right — as part of its training. That is a **named results feed**, separate from §8's anonymous
proposals, and it is the organisation's choice, made in the open.

- **The setting.** "Share practice results with the office", `Config.practiceResultsSharing`,
  declared as `SettingKey.practiceResultsSharing` — **organisation-owned**: off by default, turned
  on only by a Plan CT profile key (set and locked) or, once the office half exists, by the Office
  through the same signed route. The technician cannot turn it on, and sees it, with their role,
  in Settings › Field Assist › Practice questions. It needs an office to send to; without one it
  does nothing.
- **Disclosure before the first send.** At the first practice session after the setting turns on,
  before any result leaves, the phone says and shows, in plain words: "Your organisation has asked
  for your practice results. For each question: the clause, whether you got it right, and the date,
  under your name and your role (apprentice). Answers a model had to judge, and anything I didn't
  hear, are not sent." The Practice screen keeps a **What's sent** row that lists exactly the
  fields and the last batch's count. Nothing is sent until that disclosure has been shown
  (`PracticeResultsDisclosure`, recorded with its date).
- **What is sent, per result.** The bank id, item id and revision, the clause, the document and
  edition, the outcome (`right` | `wrong` | `unsure`), the date (a day), and the technician's
  identity as the organisation already knows it: `Config.technicianDisplayName` and the role, under
  the phone's existing organisation enrolment. Never the question text, the answer the technician
  said, a quote, a transcript, a job, a site or a time finer than a day.
- **Only rule-graded results.** A result is shared only when `AnswerGrader` settled it by fixed
  rules — a spoken number and unit, or a yes / no, matched against the human-approved answer, its
  variants and tolerance. **No `term` item's result is ever shared**, the model judge's (P6) and its
  deterministic short-circuit alike, so no shared result rests on a model's judgement. A
  technician's own questions (§3a) are never shared. `notHeard`
  and `skipped` are never sent; `unsure` is sent as `unsure`, never as `wrong`; an abandoned car
  question is nothing.
- **Seams.** `PracticeResultsBatch` (pure: picks shareable attempts, builds the payload) and
  `PracticeResultsOutbox`, on FP's outbox pattern; `DeliveryRequest.Payload.practiceResults(_:)`;
  `OpKind.practiceResults`, added to `OfficeReportSink.handledKinds`, so it rides HO's office
  transport with the queue's retries and idempotency. One batch a day. The message is specified in
  `Contracts/question-bank.md` §"Results (phone → office)"; viewing an apprentice's record is the
  office half's.
- **EU AI Act position (owner decision, 2026-10-19).** Transcription plus validation against a
  human-approved key is not an AI system. The answer key is human-authored — by the vault author,
  or the organisation's senior technician in the Office — and shared results are graded by a
  rule-based match against it, which the Commission's guidelines on the definition of an AI system
  treat as outside "AI system". Speech recognition is AI, but it only transcribes, and a mishearing
  is `notHeard`, never a miss, and never sent. Sharing model-judged results, or any model-derived
  score, ranking or competence rating, would move the feature into Annex III 3(b) (evaluating
  learning outcomes) or 4(b) (evaluating workers) and stays **excluded**; the contract states the
  same as a requirement on the office half. **P1 adds the section on this feed to
  `docs/eu-ai-act-review-2026-10.md` in the same PR**, recording the decision, the exclusion and
  that §8's aggregate counts evaluate no one. With that section in place the setting is offered on
  every storefront, the EEA included: `MarketAvailabilityPolicy.Capability` gains
  `practiceResultsSharing` with a nil row, as `emotionInference` has, so a later change of position
  is one table entry rather than new code.
- **Suggested employee-notice wording (a P1 deliverable).** The employer gives the notice; the app
  helps it do so. When an organisation profile that turns results sharing on is applied (Plan CT's
  review sheet on the phone; the Office's switch, office half), the operator is shown suggested
  common wording, plain and jurisdiction-neutral, to adapt and give to employees. It ships as
  `PracticeResultsNotice.suggestedWording`, and the same text goes into `Contracts/question-bank.md`
  so the Office shows it identically. Draft:

  > **Practice results from Field Assist**
  >
  > **Why.** We use Field Assist's practice questions to support your training on the codes and
  > regulations you work under. With this setting on, your practice results come to us so that we
  > can see which topics to cover with you and plan training.
  >
  > **What is collected.** For each practice question you answer: the clause of the code it was
  > about, the edition, whether your spoken answer matched the approved answer (right, wrong or
  > unsure), the date, your name as we know it, and your role (apprentice or qualified). Not
  > collected: what you actually said, recordings or transcripts, where you were, which job you
  > were on, or the time of day. Answers the app could not hear, or could only judge with a model,
  > are not sent.
  >
  > **Who sees it.** <Named roles, for example your supervisor and the training lead.> It is not used
  > to rank or score you automatically.
  >
  > **How long we keep it.** <A period, for example the length of your apprenticeship plus
  > <n> months>, after which it is deleted.
  >
  > **Your questions.** Ask <contact> to see the results we hold about you or to raise a concern.

  A note beside it, not part of the text (our understanding, to be confirmed by the owner's
  adviser): in Canada, the federal PIPEDA covers employees' personal information only for
  federally regulated employers, and Manitoba has no private-sector privacy statute in force that
  covers employees, so a provincially regulated Manitoba employer may have no statutory notice duty
  for this. A clear notice is still the right thing to give, and collective agreements or workplace
  policies may require one. The wording is a starting point, not legal advice, and every bracketed
  field is the employer's to fill in.

### 11 · Gates and modes

Field Assist only, inside its tool block and `FieldToolProfile`; an IP feature switch
`regulation_practice`; `closedTools` closes it with no code of its own. Practising from a bank asks
only that its vault is installed and unlocked; there is no new capability on the phone. Not in
HIPAA-only or Medical setups (no `standard` documents there); HIPAA mode sends no results and no
proposals. Agent Mode is not required: practice is the technician's own request, and the drive
offer is a goal sentence under IW's cap. The tool's description stands alone (`SystemPromptBuilder`
lists it). Spoken copy names no plan letter.

## Phases (one PR each)

### P0 — The bank: contract, validator, author guide, and asking from it

- `Contracts/question-bank.md` (draft v1): the bank file (§2), the folding rule, the approval
  record, edition keying and the fingerprint, retirement, the optional syllabus, the candidates
  message (§8) and the office intake's requirements; fixtures `Contracts/fixtures/question-bank-v1.json` (valid, invented
  clauses, a table item with no anchor), `question-bank-negative-v1.json` (one case per refusal),
  `question-bank-fold-v1.json` (fold inputs and digests) and `question-bank-vault-v1.zip` (a signed,
  fictional test vault with a bank and an invented standard); `Contracts/tests/test_question_bank_contract.py`
  running the app's Swift sources unchanged against them.
- `PracticeBankFile` + `PracticeBankValidator` (pure, over bytes, on `LearningBundleJSON`),
  `VaultManifest.practiceDir`, the `VaultValidator` hook; `Scripts/check-question-bank.swift` and
  the refusal in `Scripts/make-vault-archive.swift`.
- `docs/field-assist-question-bank-guide.md` and its step in `docs/field-assist-vault-guide.md`;
  the site page and PDF regenerated.
- `PracticeBankTrust`, `PracticeItemStatus`, `PracticeBankIndex`; `PracticeItem` / `ExpectedAnswer`
  / `PracticeAttempt` / `PracticeOutcome` + codec (explicit strings); `SpokenAnswerParser`,
  `AnswerGrader` (`number`, `yesNo`, variants, tolerance), `UnitNormalizer` length, current and
  time; `PracticeSchedule`, `PracticeSelector`, `PracticePhraser`; `PracticeProgressStore` (+
  `DataStoreRegistry` record, ET matrix, erasure walk); the `regulation_practice` tool (`quiz` with
  an optional topic, clause or named edition, `answer`, `skip`, `stop`, `missed`); the Practice screen (Settings ›
  Field Assist › Practice questions) with role, banks and their status, and the missed list opening
  `show_source`.

**Exit tests (invented fixtures only):** the contract test green on every fixture;
`PracticeBankValidatorTests` — the valid bank passes; one refusal per rule (a `passage` key — an
unknown key — refused by path, an item with no approval, a question over 160 characters, a clause
outside `ClauseReference`'s syntax, an unknown unit, `car: true` over 25 spoken words, a duplicate
id, a document not of kind `standard` or not in the manifest, an edition that differs from the
manifest's, a value spelled as a JSON fraction, a bidirectional override, a syllabus title over 80
characters or a clause range outside the syntax); an **authored table item** (figure, no anchor)
valid; a syllabus valid and carrying no questions. `PracticeBankIndexTests` — an **author-approved item from a signed pack
is live and asked with no review on the phone**; **dormant when the standard is not loaded**, and
when the loaded copy fails the fingerprint (`editionNotLoaded`); **a newer default edition → needs
re-review, not asked** by default, and **asked when the technician names that edition**, every line
saying it is the older edition (and not when the older copy is gone); anchor not found → dormant; an unsigned or unknown-publisher archive and a
folder import → dormant `unverifiedVault`; **an archive with a bad signature installs nothing and
contributes no items** (through the existing installer's refusal); a retired id → retired, progress
dropped; a revised item with a changed answer → box 1, no miss; **a vault item and an
organisation item on the same clause both live, each with its origin, one asked per session**.
`RegulationPracticeToolTests` — **a solo technician with no bank installed (and, from P5, no own
questions) gets no practice and the one sentence saying why**; a refrigerant regulation loaded as a
`standard` carries a bank like any other; a session over the fixture vault; unsure counted as nothing; the
anchored quote read from the loaded copy, the table item confirmed with answer, figure and clause.
`AnswerGraderTests` (spoken numbers and units, variants, tolerance, wrong dimension → not heard,
yes/no wording); `PracticeScheduleTests`; `PracticeSelectorTests` (live items only); `PracticePhraserTests`
(exact strings, the 25-word car cut); `PrivacyLog` and trail tests that no question, answer or
quote text is written; a guard test that every practice fixture carries the "(invented)" marker;
`DataStoreRegistryTests` / `SubjectErasureTests` green.

### P1 — Sharing results with the office

`Config.practiceResultsSharing` / `SettingKey.practiceResultsSharing` (organisation-owned),
`PracticeResultsDisclosure`, `PracticeResultsBatch`, `PracticeResultsOutbox`,
`DeliveryRequest.Payload.practiceResults`, `OpKind.practiceResults` in
`OfficeReportSink.handledKinds`, the contract's results message and fixture
(`Contracts/fixtures/question-bank-results-v1.json`), the `MarketAvailabilityPolicy` row (nil),
`PracticeResultsNotice.suggestedWording` shown in CT's profile review when a profile turns sharing
on (and in the contract, for the Office), the Practice screen's setting and **What's sent** rows,
and — **in the same PR** — the new section of `docs/eu-ai-act-review-2026-10.md` recording the
owner's decision (§10). Depends on P0; the office's view is the office half.

**Exit tests:** `PracticeResultsBatchTests` — **setting off → nothing composed or queued**; **a
`term` item's result (model-judged or short-circuited) is never in the payload**; **`unsure` is
sent as `unsure` and `notHeard` / `skipped` are not sent — neither ever as `wrong`**; the payload's
keys are exactly the allowed set (no question text, spoken answer, quote, job, site or time finer
than a day), asserted on the wire form; `PracticeResultsDisclosureTests` — **nothing is sent before
the disclosure has been shown**, and the disclosure names the fields and the role;
`MarketAvailabilityPolicyTests` — the `practiceResultsSharing` row is nil, so the setting is
available on an EEA storefront and a Canadian one alike, and injecting a date makes it unavailable
in the EEA (the switch is one table entry); a doc guard that the AI Act review names the feed;
`PracticeResultsNoticeTests` — the suggested wording is shown in the profile review exactly when
the profile turns sharing on, names purpose, what is collected, who sees it and retention, and
matches the contract's text byte for byte;
`PracticeResultsRouteTests` (the op rides the office sink only; a batch a day; retries are the
queue's; HIPAA mode sends nothing); `PracticeCandidate` dating coarsened to the week while
sharing is on (with P4).

### P2 — Questions from the day's jobs, and the drive

`JobPracticeContext` over `UpcomingJob`, `VaultModelIndex` and `JobHistoryIndex`, with empty
`PracticeContextSource`s for HV, HU and IS; `PracticeSetPicker`; `DrivePracticePolicy` and its
wiring in `CarPlaySceneDelegate` (offer after connect and after the brief when that is on; the Jobs
list row; the stop words routed before the model); the IW budget stamp; passenger mode
(`DriveRole`, the once-per-drive question, the relaxed caps, the phone-screen view). Depends only on
P0's live items; independent of P1.

**Exit tests:** `JobPracticeContextTests` (the queries carry no customer, address, contact or fault
text; equipment words match before retrieval; a job with no indexed model yields nothing);
`PracticeSetPickerTests` (five at most, `car` items only, dormant and needs-re-review items never
picked); `DrivePracticePolicyTests` — a table: no offer past IW's cap; an interruption mid-question
abandons it uncounted; walking guidance running → wait; a stop word → stop with nothing further
said; five questions then stop; disconnect → stop; `DrivePassengerTests` — the role is asked once a
drive and only "passenger" sets it; silence or anything else → driver rules; **nothing infers
passenger** (motion, CarPlay, a previous drive); passenger → up to fifteen a drive and thirty a
day, the phone screen shows the question and answer, the car screen still shows nothing; "I'm
driving" mid-drive → driver rules for the rest of it; a new drive asks again.
**Device pass (owed):** a real drive with directions handed to the maps app: what the audio session
reports when the maps app speaks, whether a question is ever cut by a prompt, and whether an
apprentice finds the pace right.

### P3 — Learning goals

`StepAction.practise` with its codec, permission and `StepActionRun` mapping; `TopicPartitioner`
over live items; the `learning_goal` action on the tool (held proposal through IW's
`accept`/`revise`/`decline`); the standing "Go over what I've missed" goal; `ActivityKind.practiceSession`,
its place in `evidenceSuggestion`, and the done suggestion; the edition sentences on the Goals
screen; a learning goal that follows a bank's syllabus.

**Exit tests:** `TopicPartitionerTests` (3–7 steps, prefixes, a clause group with no live item is
no step); `GoalCodecTests` + `GoalAdvancePolicyTests` extended for `practise`; `LearningGoalTests`
(a proposal from the fixture bank, stored only on accept; a miss joins the right step and a second
miss in the same group joins the same step; IW's evidence suggestion after two separate correct
days; the older-edition sentence when the bank goes to needs re-review; **a goal from a syllabus**
takes its topics in order as steps, skipping a topic with no live items).

### P4 — Proposing questions to the office (the phone half)

`PracticeQuestionModel` over `LLMService.completeStructured`, `QuestionAnswerabilityGate` (§8, every
refusal named), the two triggers (a miss or unsure in `regulation_practice`; a cited clause with no
item in the code-lookup answer path), `PracticeCandidate`, `PracticeCandidateStore`,
`PracticeCandidatePolicy` (daily cap, dedupe, pending, week dating while results sharing is on),
`PracticeCandidateOutbox`,
`DeliveryRequest.Payload.practiceCandidates`, `OpKind.practiceCandidates` in
`OfficeReportSink.handledKinds`, the daily shuffled batch, the switch and its profile ceiling.
Organisations with an office only; the office's intake and review are the office half.

**Exit tests:** `QuestionAnswerabilityGateTests` — one passing draft and one failing case per
reason (a table passage, a passage that cites the clause, a quote not in the passage, "except", a
cross-reference, a range, a polarity mismatch, the answer in the question, a scanned source, an
older edition); `PracticeCandidateTests` — **the encoded payload's keys are exactly the allowed
set: no name, id, device, enrolment, job, site, score, answer or time finer than a day** (asserted
on the wire form, so a field added later fails the test), and a miss and an unsure encode the same;
`PracticeCandidatePolicyTests` (five a day, one per clause while pending, none for a clause with a
live organisation item, pending cleared by the bank or after 60 days); `PracticeCandidateDraftTests`
with a fake model (a hallucinated quote dropped; a table passage never sent to the model; all
drafts failing → a bare gap; **a candidate is never asked**, the drafting phone included);
`PracticeCandidateRouteTests` (the op rides the office sink only; no candidate on a solo phone or
with the switch off; the batch order shuffled; while results sharing is on, a miss-triggered
candidate carries a week, not a day, and leaves in the weekly batch); `DataStoreRegistryTests` /
`SubjectErasureTests` green.

### P5 — Your own questions (self-review, on this phone only)

`OwnPracticeStore` (+ `DataStoreRegistry` record, erasure walk), `PracticeItemOrigin.own` and the
`selfReviewed` approval, the hand-written form and the drafted route (`PracticeQuestionModel` and
`QuestionAnswerabilityGate` from P4, over the technician's own loaded `standard`), the confirm /
edit / discard list, the labels, `SettingKey.ownPracticeQuestions` (a ceiling an organisation
profile may lock off), and the exclusions from every outbound path. Depends on P0 and on P4's model
and gate.

**Exit tests:** `OwnPracticeQuestionTests` — **a draft is not live until the technician confirms
it**; a draft that fails the gate is dropped; an edited draft keeps the edit; **labelled** on every
surface ("Your own questions", "One of your own:", "That matches your own answer"); dormant and
needs-re-review by the same edition rules; `OwnPracticeIsolationTests` — **never in any outbound
payload**: `VaultExporter`'s output, a `LearningBundle`, a practice candidate, a results batch, a
support report, any `DeliveryRequest` or `QueuedOp` built while own items exist (each asserted on
the encoded bytes); **never merged into `PracticeBankIndex`**'s bank items; a bank item on the same
clause asked first; the profile ceiling hides the route and leaves existing items untouched but
unasked; `DataStoreRegistryTests` / `SubjectErasureTests` green.

### P6 — Term answers

`AnswerKind.term` in the grader and the model-backed `PracticeGrading` judge with the deterministic
guards (§4); skipped under Medical Local Only or with cloud models off unless the on-device model is
enabled for it.

**Exit tests:** `PracticeGradingTests` with a fake judge (the approved term or a variant
short-circuits; a judge's incorrect over a near-match becomes unsure; a judge's unsure is never a
miss; the judge's input holds no passage text).

### The office half (not a phone phase)

Authoring an organisation's bank, model-drafted candidates for it, the senior technician's review
(approve, edit question / expected answer / variants / tolerance, reject with a reason), re-review
when a new edition arrives, intake and aggregation of §8's proposals, the switch for §10's
results feed and the view of an apprentice's record (no model-derived score, ranking or rating),
and publishing the organisation vault with its bank: an FX-series plan to be drafted in the
private office repository, against `Contracts/question-bank.md`. Nothing on the phone waits for it
except P1's and P4's routes having a reader.

## Decisions

### Decided by the owner (2026-10-19, answers to the open questions)

1. **Licence terms are not the app's to settle.** The app enforces that the organisation's own copy
   of the standard is loaded before anything is asked; whether a derived bank is permitted is the
   publisher's agreement with the vault author (for a bank they sell) or with the organisation (for
   its own). Rules differ by country, and it does not block this plan.
2. **A solo technician may write or draft and self-review their own questions** (§3a): marked
   `selfReviewed`, on that phone only, never exported into a vault, bank, bundle, proposal or
   results feed, labelled "your own questions" and graded "against your own answer"; drafts come
   from the technician's own loaded `standard` through the gate and are live only once confirmed.
   This is the one exception to "the phone never generates an askable question".
3. **No other phone drafting**: beyond §8's proposals and §3a, drafting a bank happens in the
   Office, where the reviewer is.
4. **A solo technician's gaps may go back to the vault author later**, opt-in and anonymous; not in
   this plan's phases.
5. **No unsigned organisation bank is honoured**: an organisation's own bank needs the Office and its
   organisation publisher; without them it buys the vault author's.
6. **A named older edition is asked on request**: "quiz me on the 2018 edition" asks that
   edition's items, needs-re-review ones included, labelled as the older edition, while its copy is
   loaded.
7. **An optional syllabus in the bank file** (topic names and clause ranges, no text) that learning
   goals can follow; in the contract, the guide, P0 and P3.
8. **Drive questions stay on routes handed to the maps app**, under the abandon-on-interruption
   rule. **Passenger mode**: on the technician's word only, asked once a drive, relaxed caps and the
   phone screen may show questions and answers; driver rules whenever driving or unknown; the car
   screen never shows them.
9. **Suggested employee-notice wording** (purpose, what is collected, who sees it, retention;
   plain, jurisdiction-neutral, with a Canadian / Manitoba note) is shown to the operator when a
   profile turning results sharing on is applied; the employer gives the notice.
10. **Transcription plus validation against a human-approved key is not an AI system.** P1 records
    it in `docs/eu-ai-act-review-2026-10.md` in the same PR; with that section in place results
    sharing is offered on EEA storefronts too. Model-judged results stay excluded from sharing.
11. **Refrigerant regulation texts an organisation loads are `standard` documents** and may carry
    banks.

### Design decisions (proposed, owner to confirm)

12. **One bank format, shipped only inside a vault** (`practice_dir`, one file per standard and
    edition), shared by the vault author, organisation vaults and Avenkin Office, specified in
    `Contracts/question-bank.md`. The app itself ships no bank.
13. **Approved by publication, trusted only from a signed source.** A bank item is asked only when
    its vault arrived as a vendor-signed EG pack, a signed archive from a catalogue-listed
    publisher, or an office assignment verified with the organisation's publisher. Unsigned or
    unknown-publisher → dormant; a bad signature installs nothing.
14. **The phone never reviews a bank item**, and generates an askable question only on the §3a
    route; review happens where the bank is made.
15. **A bank never carries the book's text**: clause, short question, short answer and an anchor
    digest; quotes are read from the organisation's own loaded copy, and only when it is there.
16. **Edition-bound, never silently kept or dropped**: dormant until the matching edition is loaded
    (by fingerprint), needs re-review when a newer edition becomes the default (the bank's publisher
    ships an update), retired when withdrawn or the vault is removed.
17. **Only `standard` documents carry a bank.**
18. **Grading is against the approved answer**, its variants and tolerance; **`unsure` and
    `notHeard` never count as a miss**; the free-form judge sees the approved answer, never the
    passage.
19. **Tables, exceptions and ranges are allowed in a bank** (a person checked them); the narrow
    answerability gate applies only to drafts.
20. **A vault author's items and an organisation's sit side by side**, each showing its origin; one
    per clause per session; a bank item before a technician's own on the same clause.
21. **Proposals to the office are anonymous by design**: clause, edition, draft and trigger kind, a
    date to the day, nothing about the person; a payload-shape test pins it; the office shows
    aggregate counts only, none below three. Organisations only; the technician may turn it off and
    an organisation can switch it off but not force it on; at most five a day per phone; dated to
    the week while results sharing is on, so the two feeds cannot be joined.
22. **Learning goals are IW goals**: a seventh `StepAction`, `practise`; steps from the live items'
    clause groups or the bank's syllabus; done suggested, never applied; one standing "Go over what
    I've missed" goal per document.
23. **The drive offer counts against IW's two unprompted goal sentences a day**; an accepted
    session has its own budget: one offer per drive; as a driver at most five questions per drive
    and fifteen a day, as a passenger fifteen and thirty.
24. **Job context is equipment words only**: never the customer, address, contact or fault report
    text.
25. **Results may be shared with the office, by the organisation's choice, in the open**: "Share
    practice results with the office" is organisation-owned and off by default (a CT profile key,
    later the Office); disclosed in plain words before the first send and in the Practice screen,
    with the technician's role; per result the clause, edition, item, right / wrong / unsure and the
    day, under the name the organisation already knows; through the office transport
    (`DeliveryRequest.Payload.practiceResults`, `OpKind.practiceResults`). The phone itself computes
    no score, pass, rank or rating.
26. **Only rule-graded bank results are shared**: a spoken number and unit or a yes / no matched by
    fixed rules against the human-approved answer and tolerance. No `term` item's result and no own
    question's result ever leaves; `unsure` is never sent as `wrong`, and `notHeard` / `skipped` are
    not sent.
27. **Organisation technicians may keep private own questions** (§3a): never shared, never counted
    in anything the organisation sees; an organisation profile may switch the route off but never
    read it.
28. **Apprentice role**: the drive offer is on by default; **qualified role**: off by default.
29. **Pricing (no prices here):** practice from banks, drive time, learning goals and own questions
    are in every Field Assist tier; building an organisation's bank in the Office, results to the
    office and anonymous proposals come with team and enterprise, because they need the Office and
    an organisation; a bank is part of the vault author's product and priced by them — the app does
    not treat a vault with a bank as a separate product; no separate regulations add-on now, revisited
    with IN's open question 3.

## Open questions for the owner

1. **Private own questions on an organisation's phones** (decision 27): agree that they are allowed,
   private and never shared, with the organisation able to switch the route off but not to read it?
2. **Passenger caps** (decision 23): are fifteen a drive and thirty a day right for a passenger, or
   should a passenger session be limited only by the drive?
3. **The Manitoba note** beside the notice wording (§10) is our reading of PIPEDA's employee scope
   and Manitoba's private-sector position; it wants the owner's adviser to confirm it before the
   first organisation sees it.

## Risks

- **A wrong answer key taught as right.** The defence is a person: every item is approved by the
  vault author or the organisation's reviewer before any phone asks it, the phone asks nothing else,
  and anything the grader cannot settle is "unsure". A bank's approval record says who stands
  behind it.
- **Licensed text leaking.** A bank has no field for text; anchors are digests; quotes come from
  the organisation's own copy; no log, trail, report or export carries text; fixtures are invented
  and guarded by a test.
- **A stale bank.** A new edition puts its items in needs re-review rather than asking yesterday's
  answer; the screen says so. Honest limit: a phone that never receives the vault update keeps the
  old edition's items waiting, not asking.
- **Re-identification from proposals.** The payload carries no person, but in a very small crew
  "someone missed 4.3" can still be guessed; the office's threshold of three and the technician's
  switch are the mitigation, and the transport's own sender knowledge is a requirement on the
  office, not something the phone can enforce.
- **Distraction.** Voice only, quiet-window starts, abandon on any prompt, stop on any request,
  per-drive caps, and nothing on the car screen. Passenger mode relaxes only the caps and the
  phone's screen, and only on the technician's word; a driver who says "passenger" is outside what
  the phone can check, which is why it is asked plainly and never inferred.
- **A wrong own answer key.** A technician's own question is only as right as they made it; it is
  labelled as theirs everywhere, graded "against your own answer", and never leaves the phone.
- **Nagging.** The offer sits under IW's two-a-day cap; a qualified technician is never offered
  unprompted.
- **Becoming an employer's assessment tool.** Results are shared only by the organisation's
  choice, disclosed first, rule-graded only, with no model-derived score, rank or rating on either
  side, and the AI Act position written into the review in the same PR that builds the feed.
- **Joining the two feeds.** A named result and an anonymous proposal on the same clause and day
  would undo the proposal's anonymity; while sharing is on, miss-triggered proposals are dated to
  the week and sent weekly, and the office half must not join them. Honest limit: in a crew of one
  apprentice, a week's proposals on a clause that apprentice got wrong still point at them.

## Out of scope

A bank bundled with the app, exam material of any kind (exam preparation from original questions is
Plan [JI](JI-apprentice-support.md)'s deliberate exception), or any question asked that no person
approved; calculation questions (IN P3's calculators answer those); comparing editions (IN P4); the
office half (authoring, review, intake, aggregation, publishing, the results switch and any office
view of an apprentice's record);
apprentice logbooks (Plan [JI](JI-apprentice-support.md), which takes the item over from IQ); practice from manuals or team learnings;
any language but English for spoken answers in P0–P5 (IN's amendment covers the answer language;
spoken-number parsing in other languages follows EC).
