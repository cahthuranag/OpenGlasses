# Plan JL — Procedure Deviations and the Learning Round Trip (what a technician did differently, bound to the step; the learning it becomes; the set that comes back)

**Status:** 📝 Drafted 2026-10-20 — nothing implemented. Owner decisions in §8.
**Track:** Field Assist (B2B), phone half. The office half is the office repository's Plan FX28
(procedure runs against the approved graph, deviations, and drafting a scenario from a manual).
**Related:** [F](F-field-assist.md) (the procedure runner), [FP](FP-team-learnings.md) (capture,
review, bundles — P0–P3 shipped; this plan binds a candidate to a step and builds the office
exchange FP left to "the signed route"), [EM](EM-work-record-and-parts.md) (the task a procedure
runs under and the work record it lands in), [GY](GY-procedure-from-narrated-recording.md) (P1b's
document route; the office drafts from a manual with the same step-splitting rules),
[GX](GX-photo-checked-procedure-steps.md) (a failed photo check is one kind of deviation once it
exists), [HK](HK-controlled-document-revisions.md) (whether a revised procedure needs an
acknowledgement), `Contracts/team-learning.md` (the office contract this plan amends and
fixtures), `Contracts/office-folders.md` (the `learning/` paths both halves already name).

---

## 1. The problem

The office can now write, check, approve and release a guided procedure, and a release reaches a
paired phone through the signed assignment path. What comes back is thin. A report's
`procedures_run` says which procedure ran, how many different steps were reached and how it
ended. It does not say which step the technician skipped, where they did something the procedure
does not say, or where they found the procedure wrong. The runner only knows *next*, *back*,
*repeat* and *complete*; a technician who departs from the procedure has nowhere to say so except
a free-text learning, which is bound to the job, the machine and the task — not to the step.

So the organisation cannot see where its procedures and its crews disagree, and a learning that
should become a revision of step 4 arrives as a sentence with no step on it.

The other direction is also open. A learning that changes a procedure already has a route home:
revise it at the office, approve, release, send. A learning that does **not** change a procedure
("on this model the sight glass bubbles for a minute after start; wait before judging it") has no
route to the phones at all. The office has the published learning set and the phone has the
capture, review and bundle code, but nothing carries a set over the managed folders, because the
contract's fixtures were never written and the phone half was never built.

## 2. What exists (verified 2026-10-20 against `main`)

- **Runner.** `ProcedureRunner` logs a `procedure_step` event per step with `procedure_id`,
  `step_id`, `branch_taken` (including `back`) and the visited `stack`; `procedure_started` and
  `procedure_completed` (with `outcome`) bracket a run. `ProcedureRunnerTool` accepts `list`,
  `start`, `next`, `previous`, `repeat`, `status`, `complete`.
- **Export.** `SessionExport.ProcedureRun` is `procedureId`, `stepsCompleted`, `outcome?`, written
  as `procedures_run` in the audit JSON. The office reads exactly those three fields
  (`scenario_usage`), joins them to its scenario library by procedure id, and shows per scenario
  how many runs finished and where unfinished runs most often stopped. It parses the audit JSON
  leniently — an added field is ignored by an older office, not refused.
- **Learnings on the phone (FP P1–P3).** `team_learning` files a `LearningCandidate` in the
  contract's §3 shape, bound to `jobSessionID`, `jobNumber?`, `taskID?`, `vaultID`,
  `modelToken?`; `LearningReview` and `LearningEntryStore` hold review and publication;
  `LearningBundle` (`schemaVersion: 1`, unsigned, closed schema — an unknown key is refused by
  path) carries candidates in and decisions out by email, share sheet or the organisation
  endpoint. FP's own words: the signed route is the office contract, whose envelopes wrap these
  payloads.
- **Office contract.** `Contracts/team-learning.md` (draft v1) names the candidate, the status,
  the learning set and the `learning/` paths under `control` and `records`; §9 lists the fixtures
  to add and none exist. The office's set builder and verifier are built against the text and
  marked provisional for that reason.
- **Managed folders.** `OfficeManualService` already runs a pass over `control` and `bulk` and
  writes receipts into `records`; its shape (verify under the binding, commit, receipt, bounded
  reason on refusal, waiting is not failure) is the pattern for anything else the office sends.

## 3. Product promise

- A technician can say, in one phrase, that they skipped a step, did it another way, or that the
  step is wrong — and the procedure carries on. The assistant reads back what was recorded and
  asks nothing twice.
- A step with a safety note cannot be skipped silently: the note is read back and the reason is
  required. A safety-critical step is never marked done by the assistant on the technician's
  behalf (GX's rule, applied here).
- A deviation is a fact about the run, not a judgement about the technician. It is written into
  the audit record and the internal work record; it never reaches the customer's copy.
- Filing a learning while a procedure runs binds it to that procedure, its version and the step,
  without the technician saying any of that.
- What the office approves comes back as one set, verified before a word of it is used, and the
  assistant cites a learning as *your organisation's learning*, never as a manual.

## 4. The deviation

A new session event, `procedure_deviation`, and a new `deviate` action on `procedure_runner`.

| Field | Meaning |
|---|---|
| `procedure_id`, `procedure_version` | The procedure as the phone holds it; `version` is the JSON's own `version` string, so the office can tell a run of 1.0.0 from a run of 1.1.0 |
| `step_id` | The step the technician was on |
| `kind` | `skipped` — went past the step without doing it; `done_differently` — did the step another way; `step_wrong` — the step's instruction or value is wrong for this unit |
| `reason` | The technician's words, 1–500 characters, redacted by `SecretPatterns` at capture, a line feed refused |
| `safety_note_read_back` | `true` when the step carried a safety note and the assistant read it back before recording the deviation |
| `next_step_id?` | For `skipped`: the step the runner moved to (the step's `default_next`, else the first branch target) |
| `learning_candidate_id?` | Set when the technician filed the deviation as a learning in the same breath (§5) |

Rules:

- `skipped` advances; `done_differently` and `step_wrong` record and stay on the step, so the
  technician still says *next*. A terminal step cannot be skipped — the runner says why.
- A step with a `safety_note`, or one that `GX` later marks safety-critical, requires the note
  to be read back and a reason given before `skipped` is recorded. The reason is not judged; the
  requirement is that it exists.
- `step_wrong` with no reason is refused with the prompt "what did you find instead?" — the
  office cannot act on a bare flag.
- A deviation on a step the procedure does not have, or outside a running procedure, is refused
  by name (`FieldSessionError.noProcedureRunning` / `.unknownStep`).
- The runner's `status` and the ACTIVE PROCEDURE prompt section list the run's deviations so far
  in one line each, so a later turn does not re-record one.

### What the export carries

`SessionExport.ProcedureRun` gains three optional fields, absent on a phone that recorded none:

```
procedures_run[]: { procedure_id, steps_completed, outcome?,
                    version?, steps_visited?: [step_id], deviations?: [ { step_id, kind, reason, at, next_step_id? } ] }
```

`steps_visited` is the ordered list of distinct steps reached (from the `procedure_step` events),
so the office can draw the path taken over the approved graph without parsing the transcript.
`steps_completed` keeps its meaning and value. The work record's internal section gains one line
per deviation under the task the procedure ran for; the customer view's allow-list is unchanged,
and the canary test is extended so a deviation reason can never appear there.

## 5. The learning, bound to the step

- `LearningCandidate` gains `procedure?: { procedureID, version, stepID }`. `team_learning note`
  during a running procedure fills it from the runner; the technician says nothing extra.
- `deviate` accepts `as_learning: true`: the deviation's reason becomes the candidate's `finding`,
  the step's instruction its `symptom`, and the candidate's `procedure` is the step. The
  candidate's id is written on the deviation so the office can join the two.
- **Contract amendment (v1, additive):** `Contracts/team-learning.md` §3 gains the optional
  `procedure` object with the three fields above; §5's entry gains the same optional object so
  an approved learning can say which step it is about, and §7 gains a rule: a set entry naming a
  procedure the phone does not hold is kept and cited without the step line.
- **Bundle:** `LearningBundle.schemaVersion` becomes 2 when any item carries `procedure`; a
  version-1 bundle is still read, and a phone composing a bundle with no bound item still writes
  version 1, so a reviewer on an older build keeps reading what it can. The closed-schema walk
  learns the new key under version 2 only.

## 6. The set that comes back (the phone half of the office exchange)

`OfficeLearningService`, beside `OfficeManualService`, over the same managed folders and the same
seams:

- **Out:** a candidate (and a withdrawal) is written to
  `records/learning/candidates/<candidateID>-<revision>.envelope.json` under the phone's binding,
  by the same queue that sends reports; the phone keeps it until the office's `received` status
  arrives (contract §3), and an absent office is not a failed send.
- **In:** `control/learning/status/<candidateID>-<revision>.envelope.json` moves the candidate's
  status on the author's session (filed → sent → approved / not taken up, with the reason);
  `control/learning/set.envelope.json` is the whole current set. A set is verified in the
  contract's order — size cap, closed envelope, signature under the office application key
  carried by the binding, version, closed payload, binding, field and text rules, newer than the
  set held — and then **replaces the organisation's namespace whole** (FP §4's rule for a signed,
  sequenced set from one office, as opposed to an unsigned bundle, which is a delta). A set that
  fails any check is refused whole with a bounded reason and the held set stays.
- A learning cited at answer time is named as the contract's §7.1 citation name; the trust rules
  are FP §5's, unchanged.
- Nothing here is reachable without an office binding; a crew without an office keeps FP P3's
  unsigned bundles exactly as shipped.

## 7. Phases (one PR each)

| Phase | Deliverable | Headless | Stop when |
|---|---|---|---|
| **P0 — contract and fixtures** | `Contracts/team-learning.md` v1 amended as §5 says; the §9 fixtures written at last (`learning-candidate-v1.json`, `learning-candidate-status-v1.json`, `learning-set-v1.json`, `learning-fixture-keys.json` with fictional keys, `learning-rules-v1.json` with the §7 cases) plus `procedures-run-v1.json`, an audit excerpt with `version`, `steps_visited` and two deviations; `generate-fixture.go` extended; a portable test under `Contracts/tests` that the phone's codecs round-trip every fixture | yes | The office's provisional code can be checked against the fixtures; the `procedure` object is optional everywhere |
| **P1 — the deviation** | `procedure_deviation` event, `deviate` action with the §4 rules, `ProcedureRunner.deviate(kind:reason:)`, the prompt-section line, `SessionExport.ProcedureRun` fields, the work-record line, the canary extension. Tests: `ProcedureRunnerDeviationTests` (skip advances by default then first branch; terminal refused; safety note gates; stays on step for the other kinds; stack unchanged by a non-advancing kind), `ProcedureRunnerToolTests` (bare `step_wrong` refused; outside a run refused), `SessionExportTests` (absent fields on a clean run; `steps_visited` order; customer view never carries a reason) | yes | A deviation is never recorded twice for one utterance; the audit JSON of a run with no deviation is byte-identical to today's |
| **P2 — the bound learning** | `LearningCandidate.procedure`, auto-binding from the runner, `deviate as_learning`, bundle schema version 2 with version 1 still read and still written when unbound. Tests: `LearningCandidateTests` (bound from a running step; unbound outside one), `LearningBundleTests` (v1 read; v2 written only when needed; a v2 key under v1 refused by path as today), fixture round-trip from P0 | yes | A reviewer on the previous build still reads a bundle from a phone that filed nothing bound |
| **P3 — the set over the managed folders** | `OfficeLearningService` as §6; `QueuedOp.teamLearning` routed to `records/learning/candidates/` under a binding; status and set intake; whole-set replacement; receipts. Tests against the P0 fixtures: set accepted and namespace replaced; older sequence refused; wrong key refused; tampered payload refused; status moves the author's session; a candidate retried until `received` | yes (engine seams as `OfficeManualService`) | A set is never partially applied; a phone with no binding writes nothing to `records/learning/` |
| **P4 — device pass** | One paired phone: run a procedure, skip a safety step with a reason, file one bound learning, receive the office's set and hear it cited | no | — |

## 8. Owner decisions

1. **Can a safety-note step be skipped at all?** Drafted: yes, with the note read back and a
   reason, because a technician who has already decided to skip will do so either way and the
   record is worth more than the refusal. The alternative is to refuse `skipped` on any step with
   a safety note and allow only `done_differently`.
2. **Should a deviation be spoken to the office in the work record the customer sees?** Drafted:
   never. The internal section and the audit JSON carry it; the customer copy is unchanged.
3. **Does `step_wrong` need a second confirmation**, the way a safety learning does at approval?
   Drafted: no on the phone (the office reviews it), but the office may require it on its side.
4. **Whole-set replacement scoped per vault or per organisation** is contract open point 1;
   this plan follows whatever is decided there and reads `vaultIDs`.

## 9. Privacy and policy

- A reason is the technician's own words and is redacted by `SecretPatterns` at capture, like a
  learning; it carries no customer name, address or transcript by rule, and review is where a
  slip is caught (contract §8).
- HIPAA withholding applies as to learnings: no candidate, no set, and the deviation reason is
  kept out of every prompt.
- A deviation is never used to score a technician on the phone; the plan adds no count, badge or
  comparison on any phone surface. What the office does with the counts is the office's plan.
- The EU AI Act review's rule stands: nothing here infers anything about a person; it records
  what they said about a step.
