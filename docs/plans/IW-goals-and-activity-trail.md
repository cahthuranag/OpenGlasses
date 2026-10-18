# Plan IW — Goals and the Activity Trail ("what are we working on, what did you do, what's next")

**Status:** ✅ P0–P2 built 2026-10-19; device pass owed (a three-step goal over two days with one check-in heard at the right time; the Activity screen after a morning of normal use reads as a sensible story; a scheduled task's result visible without `speakResult`); Home tile deferred (decision 5); catalog sync owed for the new screens' strings. Drafted 2026-10-18. See [P0 as built](#p0-as-built), [P1 as built](#p1-as-built) and [P2 as built](#p2-as-built).
**Builds on:** Plan [S](S-plan-then-execute-and-safety-supervisor.md) (`AgentPlan`/`AgentPlanner`/
`PlanValidator`/`PlanExecutor`/`AgentRunner`), `AgentScheduler` + `manage_schedule`,
`AgentNotificationQueue`, Plan [BZ](BZ-notification-digest.md) (digest), Plan
[DY](DY-my-day-everyday-briefing.md) (My Day), `OperationJournal`, `TurnTrace` (Plan
[FV](FV-support-reports.md)), `ToolAuthorizationEventLog`, `HeldRecommendationStore` (Plan W).
**Sits beside:** Plan [GN](GN-agent-notebook.md) (the assistant's own notes — what it *noticed*;
this plan is what the wearer *asked for* and what the assistant *did*), Plan
[GG](GG-readable-memory.md) (memory is what it knows), Plan [DZ](DZ-local-gguf-and-durable-agent-runtime.md)
PR6 (durable scheduler — this plan supplies the run history that PR6 says `ScheduledTasksView` owes),
Plan [IX](IX-scoped-grants-and-read-only-integrations.md) (a standing grant's silent actions must
appear in the trail).

---

## Trigger

Two absences.

**Nothing outlives a turn.** "Help me get the garage sorted before the move" produces a good answer
and, in Agent Mode, perhaps an `AgentPlan` with steps — which is executed within the turn, never
persisted (`AgentStep` is not even `Codable`), and gone. The only long-lived objects are reminders,
brain "needs" (always tied to a person, no due date) and scheduled prompts (an interval and a
string). A goal with steps, progress and a next move has no home, so the assistant cannot pick it up
tomorrow, cannot say "two of five done", and cannot schedule the next step itself.

**Nothing says what was done.** The app keeps a hash-chained HIPAA audit, a refusals-only
authorization ring (in memory, 50), an at-most-once operation journal whose own comment says "no UI
presents it yet", content-free turn traces for support, a remote-invoke audit, and a held-actions
store that drains into one sentence. None of them answers the wearer's question "what did you do
today, and what are you going to do?" A scheduled run with `speakResult` off leaves its result in
`lastResponse` and nowhere else. The approval that lets an action run silently later (IX) has no
place to be seen afterwards.

## Outcome

- "Let's make a goal: clear the garage before the twentieth." → "Okay. I'd break that into: book
  the skip, sort the shelves, list the bike for sale, drop the paint at the depot. Want me to keep
  an eye on it?" → "Yes." The goal exists with four steps, a due date, and a check-in cadence.
- "How's the garage going?" → "Two of four done. The skip is booked for Saturday. Next is the
  bike — want me to draft the listing?" The next step is offered, never taken unasked.
- The assistant advances a goal only through things it may already do: a reminder, a calendar hold,
  a draft, a search, a scheduled check — each through the normal tool boundary, each recorded.
- "What have you done today?" → "Three things: I added the dentist to your calendar, I searched for
  skip hire and saved two options, and I recorded four parts on job 1017 under your standing
  permission. Nothing is waiting on you." Also as a screen: a timeline of actions with what, when,
  why (the goal or request it served), and how it was authorised.
- "What's next?" → open steps across goals, soonest first; My Day shows one goal line when a step is
  due; the digest carries a goal's check-in.
- Everything readable, editable, deletable; nothing hidden reasoning. Copy never names a plan letter.

**First customer: Field Assist.** The trail is what a technician's day of actions looks like
when read back: parts recorded under a standing permission, a work record sent to the office, a
van-stock change, each with how it was authorised. A goal sits beside a job and never shadows it —
a job's own task list (Plan [FO](FO-guided-job-flow-and-job-tab.md)) stays the job's list, and the trail links to
the job record rather than copying it.

## What exists today (verified 2026-10-18)

- `Services/Agent/`: `AgentPlan { goal: String, steps: [AgentStep] }`, `AgentStep { tool, args:
  [String: Any], rationale, reversibility, requiresConfirmation }` (**not `Codable`**);
  `AgentPlanner.plan(request:availableTools:)` (one stateless completion, JSON `{goal, steps}`),
  `PlanValidator` (unknown tool, budget `SafetySettings.stepBudget` = 8, marks irreversible steps),
  `PlanExecutor.execute` → `PlanRunResult { completedSteps, aborted, abortReason, transcript }`
  through `ToolExecuting.executeRoot` (`origin .model`, `invocationID "\(runID)#\(index)"`),
  `AgentRunner.run` → `Result { summary, completedSteps, totalSteps, aborted }`. Entered from
  `LLMService` only when `agentModeEnabled` and `classifyMultiStep` (keyword heuristic +
  optional LLM check). **Nothing persisted; `onReinject` never wired** (constraint re-injection is
  dead code). HUD gets "Step i of N".
- `AgentScheduler.ScheduledTask { id, name, prompt, intervalMinutes, enabled, lastRun, speakResult,
  personaId, modelId, createdBy }` in UserDefaults `agentScheduledTasks`; Agent-Mode-gated;
  foreground timer; one due task per 5/30-min cycle; a run is a full `sendMessage` turn under
  `TurnRecorder.offTurn` with the `[NOTHING]` convention; **`intervalMinutes == 0` tasks never run**
  (the loop filters `> 0`) although the tool and view call 0 "once daily"; result reaches the
  wearer only via `agentNotificationQueue.enqueue` when `speakResult`; no run history beyond
  `lastRun`. `ScheduledTasksView` groups Built-in / Shortcut / Custom; "Run now" sends a chat turn.
- `AgentNotificationQueue`: immediate delivery when glasses connected, worn and idle (**then it
  never reaches the digest**); else queued to `agent_notification_queue.json` and `onQueued` →
  `notificationDigest.ingest(source: .agent, …)`. `DigestSource { calendar, geofence, proactive,
  agent, reminder, sync }`, exhaustive switches in `MyDayDigestPolicy`; staleness low 30 min /
  medium 2 h / high never.
- My Day: `MyDaySource { calendar, digest, reminders, travel, weather }`, `MyDayKind { event,
  leaveBy, preparation, reminder, update, weather }`, `MyDayItem { id, kind, title, detail, dueAt,
  urgency, actions }`; a new source touches `MyDaySource`, a protocol, `MyDayInputs`,
  `MyDaySourceSelection`, `MyDayComposer`, `MyDayKind` icons; `daily_briefing` speaks
  `spokenBriefing()`.
- Brain: `Need { id, person, text, createdAt, resolvedAt }` (person required, no due date), surfaced
  in Memory as "Unfinished things" (`MemoryFactGroup.unfinished`, `MemoryFactStore.brainNeed`,
  label "Follow-up"). `agent_diary` is the assistant's private log, shown under Other.
- Records that exist, all content-free or nearly: `OperationRecord { operationID, toolName, effect,
  origin, state, startedAt, … }` (Application Support, 200 cap, "no UI presents it yet");
  `TurnTrace { toolCalls: [ToolNote { name, outcome }], outcome, … }` (14 d / 2000, support
  reports); `ToolAuthorizationEvent` (refusals only, memory); approvals exist only as
  `PrivacyLog.toolGate` events; `HeldRecommendationStore` (memory, 10, one spoken line on
  re-engage); `RemoteInvokeAuditEntry` (UserDefaults, 100 — registry says 50); `AuditEvent`
  (HIPAA mode only). Screens: Memory, Scheduled Tasks, Remote Invoke Audit, HIPAA audit,
  Developer panel — none shows "what the assistant did".
- `DataStoreRegistry` tests scrape for SQLite/container/UserDefaults-JSON writers; every new
  store needs a `SensitiveStore` record, `ownerPaths`, a working `deleteAll`, and the ET matrix
  regenerated; a wearer-linked store joins the Memory screen's erasure walk.

## Design

### Goals

**Model (`Goal`, `GoalStep`, pure, `Codable`).**
```swift
struct Goal { id, title (≤ 80), why? (≤ 140), createdAt, dueAt?, state: .active | .paused | .done |
              .abandoned, checkIn: CheckInCadence (.none | .daily | .weekly | .beforeDue(days)),
              steps: [GoalStep], persona?, source: .wearer | .proposed }
struct GoalStep { id, title (≤ 80), state: .open | .next | .inProgress | .done | .skipped,
                  dueAt?, suggestedAction: StepAction?, doneAt?, evidence: [ActivityRef] }
enum StepAction { case reminder(text, at), calendarHold(title, at, minutes), search(query),
                  draft(kind, prompt), scheduledCheck(prompt, every), ask(question) }
```
`StepAction` is the **closed set** of things the assistant may offer to do for a step; each maps to
an existing tool (`reminder`, `calendar`, `web_search`, a drafting turn, `manage_schedule`) and
therefore to the existing authorization boundary. No `args: [String: Any]`; no arbitrary tool.

**Creating (`GoalDrafter`).** "Make a goal …" → one structured completion with a schema (title,
why, due date if said, 3–7 steps each with an optional `StepAction`), then `GoalProposalParser`
(pure) validates lengths, dates in the future, action kinds in the set, and **drops any action
whose target names a tool the wearer has disabled or an integration that is read-only** (IX). The
wearer hears the steps and says yes, edits ("drop the paint one"), or no. Nothing is stored until
yes. Agent Mode is **not** required to have goals; it is required for the assistant to *propose*
goals on its own (GN territory) and for scheduled checks to run.

**Advancing (`GoalAdvancePolicy`, pure).** The assistant never executes a step unasked. It may:
offer the `next` step's action when the goal is mentioned, at a check-in, or when My Day shows the
step; mark a step done when the wearer says so or when **evidence arrives** (`ActivityRef` to an
activity entry: the reminder completed, the calendar event passed, a draft was sent) — evidence
auto-completion is **suggested** ("Looks like the skip's booked — mark that done?") not applied,
unless the wearer turned on "mark steps done when you see they're done". Check-ins are
`AgentScheduler` tasks of a new kind `.goalCheckIn(goalID)` (typed, not a prompt string) that
produce a `DigestItem` (`DigestSource.goal`, new) and, when due and the wearer is present, one
sentence through the queue. Daily cap: 2 goal sentences; `.beforeDue` only.

**Reading.** Tool `goals`: `list`, `status(goal)`, `next`, `add(title…)`, `step_done`, `skip`,
`pause/resume`, `abandon`, `edit`. Screen Settings › Assistant › **Goals** (and a Home-grid tile,
Plan [GW](GW-home-grid-pages.md)): goals with progress rings, steps with Done / Skip / Do it
(runs the suggested action through the normal confirm), the check-in picker. Memory screen's
"Unfinished things" gains a "Goals" link; goals are **not** memory facts (they are the wearer's
objects, not inferred knowledge) and are not ingested into `BrainStore`. GN notebook entries may
cite a goal (`evidence: goal:<id>`) when GN is built.

**Store.** `GoalStore` (`Application Support/Goals/goals.json`, `completeUntilFirstUserAuthentication`,
backup-excluded, 50 goals cap, done/abandoned retained 90 days), `SensitiveStore.goals` (wearer,
`deleteAll`, erasure walk), `hipaaRetentionDays` honoured.

### The activity trail

**One record kind, many feeders (`ActivityEntry`, pure, `Codable`).**
```swift
struct ActivityEntry { id, at, kind: ActivityKind, title (≤ 100, past tense, second person: "Added
   the dentist to your calendar"), detail? (≤ 200), tool?, goalID?, stepID?, authorisation:
   .asked | .standingGrant(scope) | .readOnly | .heldForYou | .refused(reason) | .scheduled,
   origin: .wearer | .scheduled | .agent | .remote(source), outcome: .done | .failed | .uncertain |
   .waitingOnYou, refs: [ActivityRef] }   // ActivityRef: operation:<id>, trace:<id>, thread:<id>, goal:<id>
```
**Feeders**, each a thin adapter on an existing hook, no new logging in tools:
- `NativeToolRouter.execute` after dispatch: for every **side-effecting** tool call
  (`ToolEffectClass >= .write`) and every `.confirm`/`.refuse`/`.hold` verdict — title from a
  pure `ActivityTitler` (tool + action key + the model's `approvalSummary` when present; a fixed
  template otherwise); reads are **not** recorded (the trail is actions, not a transcript).
- `OperationJournal` state changes (`onOperationStatusChange`) → `outcome` updates on the same
  entry (`uncertain` for `.unknown`, `done` for `.completed`).
- `AgentScheduler` run end → one entry per run (`origin .scheduled`, title from the task name,
  `outcome .done`/`.failed`, `detail` = first 200 chars of a non-`[NOTHING]` result) — **this is the
  run history DZ PR6 owes** and fixes "result only in `lastResponse`".
- `PlanExecutor.onStep` → entries per planned step with the plan's `goal` as `detail`.
- `HeldRecommendationStore` → `.heldForYou` entries (and the store becomes a view over the trail).
- Standing-grant actions (IX) → `.standingGrant(scope)`; read-only refusals → `.readOnly`.
- `AgentNotificationQueue.deliverImmediately` → an entry `kind .toldYou` so an immediately spoken
  result is no longer invisible (closes the "never reaches the digest" gap in the trail, not the
  digest).
Nothing is recorded for conversation content; `detail` holds the tool's own summary or the
scheduled result's lead, never the wearer's words.

**Store.** `ActivityStore` (`Application Support/Activity/activity.json`, protection as above,
backup-excluded, 14 days / 1000 entries — the same horizon as `TurnTrace`), `SensitiveStore.activityTrail`
(wearer, `deleteAll`, erasure walk), Clear button, `hipaaRetentionDays`. Not a replacement for
`OperationJournal` (at-most-once semantics), `TurnTrace` (support), the HIPAA audit (compliance) or
`ToolAuthorizationEventLog` (security ring) — those stay; the trail **links** to them by `refs`.

**Reading (`ActivityPhraser`, pure).** "What have you done today / this morning / since I left?"
→ counts by kind, then the top 3–5 entries in time order, waiting-on-you items last and explicit;
≤ 35 s of speech (DY's cap). "What's next?" merges goal `next` steps, scheduled tasks due within
24 h, and `.waitingOnYou` entries. Screen Settings › Assistant › **Activity**: a day-grouped
timeline, filters (actions / held / scheduled / refused), each row opening the goal, the thread
or the journal record it refers to. The Developer panel's Debug Events stays separate.

**Surfaces.** `DigestSource.goal` with `displayTag` "Goal"; My Day gains a `goals` source
(one item: the soonest due step, kind `.preparation`, actions `[.open, .complete, .dismiss]`,
`MyDaySourceSelection.goalsIncluded` default on when any goal exists); Home-grid tile "Goals";
support report line "goals: N active; activity entries 14 d: N" (counts only).

### Gates and modes

- Goals and the trail work **without Agent Mode**; check-ins and any `scheduledCheck` action need
  it (they are background work). Turning Agent Mode off pauses check-ins; the goals remain.
- HIPAA: `detail` is already content-light; in HIPAA mode entries keep `title` only.
- Organisation profiles may close `goals` (`closedTools`) and may pin the trail on (a managed phone
  keeps its action history). A technician's job actions appear in the trail *and* the job record;
  the trail links to the job, it does not duplicate the work record (Plan EM).
- Cost: goal drafting is one structured call; check-ins reuse the scheduler's budget.

## Phases (one PR each)

**P0 — Pure core.** `Goal`/`GoalStep`/`StepAction` + codec, `GoalProposalParser`,
`GoalAdvancePolicy` (next-step selection: `next` → earliest `dueAt` → first open; evidence
suggestion rules; daily sentence cap), `GoalPhraser` (status, next, proposal read-back),
`ActivityEntry` + codec + `ActivityTitler`, `ActivityPhraser` ("today" windows in the wearer's
zone; ≤ 35 s), `ActivityRetention`. Also fixes while the file is open: `AgentStep` gains a
`Codable` projection (`PlannedStepRecord { tool, actionKey, rationale }`) so plan runs can be
recorded. (The once-daily scheduler defect this plan first claimed is Plan [JC](JC-planning-sweep-fixes.md)
item 1; if JC has not landed, IW P0 takes it.) Tests: `GoalProposalParserTests` (lengths, past dates, unknown action kinds,
disabled-tool actions dropped), `GoalAdvancePolicyTests` (table), `GoalPhraserTests` (exact strings),
`ActivityTitlerTests` (every side-effecting registered tool has a title template — a table test
over the registry like `ToolEffectClassPolicyTests`), `ActivityPhraserTests` (windows, cap,
waiting-on-you last), `ActivityRetentionTests`.

**P1 — Stores, feeders, tools.** `GoalStore`, `ActivityStore` (+ `DataStoreRegistry` records,
ET matrix regenerated, erasure walk), the router/journal/scheduler/executor/held/queue feeders,
`goals` tool, "what have you done" and "what's next" handled by a `activity` tool (`today`,
`since`, `next`), `GoalDrafter` with a fake-LLM test, `DigestSource.goal` and its exhaustive-switch
updates. Tests: `ActivityFeederTests` (a confirmed `calendar create` makes one entry with
`.asked`; a read makes none; a journal `.unknown` marks `uncertain`; a scheduled run with
`speakResult` off still records; an immediate delivery records `.toldYou`), `GoalStoreTests`,
`GoalDrafterTests` (proposal → yes stores; edit drops a step; no → nothing stored),
`DataStoreRegistryTests` / `SubjectErasureTests` green.

**P2 — Screens and My Day.** Goals and Activity screens, Home tile, My Day `goals` source,
check-in scheduler kind and its digest item, support-report counts, the Memory screen link.
Tests: `MyDayComposerTests` (goal item ranks under a leave-by, above weather),
`GoalCheckInTests` (cadence; `.beforeDue(3)` fires once; cap 2/day), `SettingsHubTests` update.
Device pass (owed): a three-step goal over two days with one check-in heard at the right time; the
Activity screen after a morning of normal use reads as a sensible story; a scheduled task's result
visible without `speakResult`.

### P0 as built

Built 2026-10-19 as pure value types and policies — no store, no screen, no tool registration, no
model call, no feeder. Everything takes its clock, calendar or time zone and its permission rule as
inputs.

- **Goals** (`Services/Goals/`): `Goal`, `GoalStep`, `GoalState`, `GoalStepState`, `GoalSource`,
  `CheckInCadence` (persisted as `none` / `daily` / `weekly` / `before_due:<days>`; the default
  for "keep an eye on it" is two days before the due date, none without one) and `StepAction`, the
  closed set of six offers (`reminder`, `calendar_hold`, `search`, `draft`, `scheduled_check`,
  `ask`), each mapped to an existing tool or to none. All `Codable` through `RecordJSONCodec`
  (ISO 8601 with fractional seconds, sorted keys); the plan's length limits (`GoalLimits`) are
  enforced when a proposal is parsed and again when a stored goal is decoded, and an action kind a
  newer build wrote loses the offer, not the step.
- `GoalProposalParser`: the model's `{title, why?, dueAt?, steps:[{title, action?}]}` → a typed
  `GoalProposalOutcome`. Goal-level problems (length, a due date not in the future, fewer than 3 or
  more than 7 steps, unreadable input) refuse the proposal, all reported at once; a bad action —
  unknown kind, a field out of bounds, a time already gone, or one the injected
  `(StepAction) -> Bool` turns down — is dropped with its reason and the step kept.
  `StepActionPermission.predicate` is today's rule (tool enabled, integration not read-only,
  Agent Mode for `scheduled_check`); IX replaces the predicate without touching the parser. A bare
  date means the end of that day in the wearer's calendar.
- `GoalAdvancePolicy`: next step (`next` → earliest `dueAt` → first open; none on a paused, done or
  abandoned goal), the offer, evidence (a linked, finished, non-held, non-refused entry from the
  step's own tool yields a `GoalEvidenceSuggestion` — a value; nothing applies it), the daily cap of
  two unprompted goal sentences per calendar day, and check-in cadence (`beforeDue(n)` fires once,
  in the window opening `n` calendar days before the goal's or next step's due date).
- `GoalPhraser`: status ("Two of four done. Next: List the bike for sale, due Saturday. Want me to
  draft the listing?"), next, the proposal read-back ("Okay. I'd break that into: … Want me to keep
  an eye on it?"), the evidence question and every action offer. `SpokenPhrasing` builds days and
  times by hand so strings do not move with the system's formatting data.
- **Trail** (`Services/Activity/`): `ActivityEntry` with `ActivityKind`, `ActivityAuthorisation`,
  `ActivityOrigin`, `ActivityOutcome`, `ActivityRef`, every one persisted as an explicit string
  (`planned_step`, `standing_grant:<scope>`, `refused:<reason>`, `remote:<source>`,
  `operation:<id>` …); over-long text is shortened, not refused, because losing the record would
  hide the action.
- `ActivityTitler`: a fixed past-tense, second-person template for every side-effecting registered
  native tool, sharpened by the action key; read actions of a writing tool and every read return
  nil; the approval line the wearer saw becomes the detail ("You approved: Send a message to Sam"),
  cut before any quoted body. Tools with no template (MCP, user-authored) get "Used the … tool".
- `ActivityPhraser`: today / this morning / since a time, in the wearer's zone; counts by kind,
  then up to five entries in time order (failures first in the pick), then what is waiting on the
  wearer — last and always said; inside `MyDaySpeechPolicy`'s 35 s, dropping entries before the
  waiting line. "What's next" merges goal next steps, scheduled tasks due within 24 h and
  waiting-on-you entries.
- `ActivityRetention`: 14 days / 1000 entries, oldest first out, a shorter HIPAA retention honoured.
- `PlannedStepRecord { tool, actionKey, rationale }` and `AgentStep.record` — a `Codable`
  projection that never carries the step's arguments; `AgentStep` stays non-`Codable`.
- The once-daily scheduler defect was fixed by Plan JC (`ScheduleDuePolicy`, with its tests);
  verified, nothing changed here.
- Tests: `GoalProposalParserTests`, `GoalAdvancePolicyTests` (tables), `GoalPhraserTests` (exact
  strings), `GoalCodecTests` and `ActivityEntryCodecTests` (fixture decoding and round trips),
  `ActivityTitlerTests` (the live registry, as `ToolEffectClassPolicyTests` builds it),
  `ActivityPhraserTests` (time-zone boundary, the ceiling, waiting last), `ActivityRetentionTests`,
  `PlannedStepRecordTests`.

Verified 2026-10-19: the 76 new tests (plus `ScheduleDuePolicyTests`); the full unit suite,
11,296 tests (16 skipped, zero failures); a Release build on the simulator (no phone reachable);
the privacy-logging gate; gitleaks over the branch.

**Decisions taken (2026-10-19):** (1) goals work without Agent Mode — only check-ins and
`scheduled_check` need it; (2) evidence completion is suggest-only; (3) trail horizon 14 days /
1000 entries; (4) reads are not recorded; (5) the Home tile is deferred past P2.

### P1 as built

Built 2026-10-19 on the P0 core, unchanged except where noted. No screen, no My Day source, no
check-in scheduler kind (all P2).

- **Stores.** `GoalStore` (`Services/Goals/`) — `Application Support/Goals/goals.json`, at most 50
  goals; at the cap the goal that finished longest ago makes room, and a 51st open goal is refused
  rather than an open one dropped. A goal marked done or set aside is kept 90 days from its new
  `finishedAt` (the one field added to `Goal`; stamped and cleared by the store), fewer when a
  shorter HIPAA retention is set; open goals never expire. An unreadable file is never overwritten;
  one goal that does not decode costs that goal only. `ActivityStore` (`Services/Activity/`) —
  `Application Support/Activity/activity.json`, pruned through `ActivityRetention` on open and on
  every append; a file locked before first unlock is not written over until it can be read and
  merged. Both first-unlock, backup-excluded, `RecordJSONCodec` on disk. Registered as
  `SensitiveStore.goals` (personalMemory) and `.activityTrail` (operationalAudit), wearer-linked,
  with `deleteAll()` and `forget(matching:)`, and walked by the subject erasure (Memory screen's
  forget and the ledger replay): a goal that names the person goes whole, a trail row that names them
  goes. The ET matrix is regenerated.
- **HIPAA.** With compliance mode on an entry keeps its title only — `ActivityStore.append` drops
  the detail before it is written — and `hipaaRetentionDays` shortens both horizons (never
  lengthens them). Outside compliance mode the HIPAA setting does not apply.
- **One seam.** `ActivityRecording` (`record`, `settle(operationID:outcome:)`); production
  `ActivityRecorder` over `ActivityStore.shared`, wired by AppState into the router, the scheduler
  and the notification queue. Unwired (tests, headless) records nothing. Pure builders in
  `ActivityFeed`.
- **Feeders and hook points.**
  - `NativeToolRouter.execute` wraps the old body (`authorizeAndDispatch`) and records one entry
    after it returns: every dispatched call whose `ActivityTitler` title is non-nil (so every read,
    and a writing tool's read actions, make none), with `.asked` (or `.scheduled` inside a scheduled
    run) and the approval line as detail when the wearer was asked; and one entry for each
    `.refuse` (its `ToolRefusalReason`), `.block` (`blocked_by_safety`), confirm with no
    coordinator (`no_confirmation`), withdrawn consent (`consent_withdrawn`), unbound approval (its
    refusal code), decline (`declined`) and `.hold` (`.heldForYou`, `.waitingOnYou`). Refused and
    held rows have fixed titles naming the tool ("Your OK to use the send message tool") and no
    detail. Every row of a dispatched call carries `operation:<invocationID>`; a redelivered
    operation settles its existing row instead of adding one.
  - `OperationJournal`: the router's journal sink (and reconciliation) passes each settled state
    to `settle` — `.unknown` → `uncertain`, `.completed` → `done`, `.failed` → `failed`. A timed-out
    write is recorded uncertain and flips to done when the late answer lands.
  - `AgentScheduler`: each run of a task records `Ran <task name>` (`.scheduledRun`, `.scheduled`)
    with the first 200 characters of a non-`[NOTHING]` result, independent of `speakResult`; the
    run's own tool calls are tagged scheduled through the `ActivityScope.scheduledTask` task-local.
    A deferred run records nothing.
  - `PlanExecutor`: each step runs inside `ActivityScope.plannedStep` (the plan's goal and the
    step's `PlannedStepRecord`), so the router records it as `.plannedStep`, origin `.agent`, with
    the plan's goal as detail — one entry per side-effecting step, not two.
  - `HeldRecommendationStore`: the held row is written at the router's hold verdict, the same moment
    `onActionHeld` feeds the store, so a held action is one row; the store itself is unchanged.
  - `AgentNotificationQueue.deliverImmediately`: once a message has actually been said (spoken or
    through a live session) it records `Passed on an update` (`.toldYou`) with the message's lead.
  - Field Assist: `activityJobThread` (the active job's thread while it is bound) adds
    `thread:<id>` to every row made during a job, so a part recorded or a record sent links to the
    job instead of copying its work record.
- **What the trail does not record:** reads; the wearer's words (titles are fixed templates; detail
  is the approval line cut before any quoted body, a plan's goal or a result the assistant
  produced); calls stopped by a switched-off AI feature, a withheld egress or an unknown tool;
  goal proposals, revisions and declines (nothing stored). No standing grant or read-only gate
  exists yet, so `.standingGrant` and `.readOnly` are not produced (IX).
- **Tools.** `goals` — `list`, `status`, `next` (one goal, or across goals), `add` (the wearer's
  steps through `GoalProposalParser` with the live disabled-tool predicate; only a title → the
  drafter), `accept` / `revise` / `decline` (the yes, edit and no of a held proposal), `step_done`,
  `skip`, `complete`, `pause`, `resume`, `abandon`, `edit`. Semantics `.local` with a 60 s budget;
  the titler treats list/status/next/add/revise/decline as reads. Works without Agent Mode; a
  `scheduled_check` offer is refused with a spoken sentence when it is off. `activity` — `today`,
  `this_morning`, `since` (ISO 8601 or `HH:mm`), `next` (goal next steps, scheduled tasks due within
  24 h while Agent Mode is on — `ScheduleDuePolicy.nextDue` — and waiting-on-you rows from the last
  day). Read semantics; offline `.local` (`goals` `.degraded`: suggesting steps needs a model);
  `activity` joins `localSafeTools` and the on-device everyday list. An organisation closes either
  through `closedTools` with no code of its own (the disabled set the registry reads).
- **`GoalDrafter`.** One structured completion through `LLMService.completeStructured` behind the
  `GoalDraftModel` protocol, the schema the parser reads, today's date and zone in the prompt, and
  `scheduled_check` offered to the model only with Agent Mode on. The proposal is held (one at a
  time, 15 minutes) and read back through `GoalPhraser`; nothing is stored until `accept`, which
  takes the default cadence (two days before it is due) unless the wearer says otherwise.
- **`DigestSource.goal`** ("Goal"); `MyDayDigestPolicy` keeps it out of My Day's digest rows (P2
  adds a goals source of its own).
- In-PR: `RecordJSONCodec` keeps one pair of formatters instead of one per date (the stores write
  every row on every change), and `AgentSummarizer.joinClauses`' comment now matches its serial
  comma.

**Decisions taken in P1 (2026-10-19):** (1) one entry per held action, written by the router —
the held-recommendation store is not a second writer; (2) side-effecting plan steps only (decision
4 holds for plans); (3) a goal proposal is stored only on an explicit `accept`, wearer-dictated
steps included; (4) HIPAA retention shortens the horizons only in compliance mode, and for goals
only finished ones; (5) a job links by its conversation thread (`thread:<id>`) rather than a new ref
kind; (6) `goals` stays out of the small-model safe set (ten actions); `activity` joins it; neither
is added to the always-declared core set.

### P2 as built

Built 2026-10-19 on the P0 and P1 core. No new store: everything below reads and writes
`GoalStore`, `ActivityStore` and the existing scheduled-task list. The Home-grid tile stays
deferred (decision 5).

- **Goals screen** — Settings › AI & Personality › Goals (`GoalsView`, `GoalDetailView`,
  `AddGoalSheet`, `GoalPage`) over `GoalsScreenModel`. Goals on the go and finished ones (kept 90
  days), each with a progress ring of done steps over the steps not skipped. A goal's page: its
  steps with Done, Skip and Reopen, rename and remove by swipe, add a step; the step's own offer as
  a capsule button ("Search for it", "Set the reminder", "Draft it" …) — or the question, for an
  `ask` — disabled with the reason when the tool is off or a scheduled check needs Agent Mode; the
  check-in picker (off, daily, weekly, 1/2/3/7 days before it's due — before-due only when there
  is a date) with a note while Agent Mode is off or the goal is paused; name, reason and due date;
  pause / pick back up / mark done / set aside; delete (with a confirmation, `GoalStore.remove`).
  The add path (empty-state button, toolbar +, sheet) is shown only while `goals` is enabled —
  `Config.isToolEnabled`, which already folds in an organisation's `closedTools` — and the list
  shows either way. The empty state is one sentence in the assistant's voice and does not mention
  jobs.
- **"Do it"** (`StepActionRun`, pure) maps a step's `StepAction` to the call its tool already
  takes — `reminder` create with an ISO `due_at`, `calendar` create with date/start/duration,
  `web_search`, `manage_schedule` create (0 = once a day, else weekly) — and the screen hands it to
  `NativeToolRouter.execute` with the wearer as the origin, so confirmation, safety rules, the
  presence ceiling and Agent Mode apply as they do to a spoken request; nothing bypasses the
  ladder. A draft goes to the conversation as the wearer's message; a question runs nothing. The
  call runs inside `ActivityScope.goalStep`, so the trail row it writes carries the goal and step
  (`goalID`/`stepID` and a `goal:<id>` ref) — the evidence link P0's `GoalAdvancePolicy` reads.
  Running an offer never marks the step done.
- **Activity screen** — Settings › AI & Personality › Activity (`ActivityView`) over
  `ActivityScreenModel`: the trail a day at a time (Today, Yesterday, then dates), newest first,
  each row's title, time, the goal it served (looked up by id — never stored as text), how it was
  authorised in words ("You approved it", "Held for you", "Scheduled", "Refused: you said no" …)
  and an outcome where it adds something ("May not have gone through", "Didn't finish"). Filters:
  all / actions / held / scheduled / refused. A row opens its goal, or the conversation thread it
  links to (a Field Assist job's thread) when that thread is still on the phone; the journal has no
  screen, so an operation ref is not a destination. Clear asks first and calls `deleteAll`. In
  HIPAA mode rows show titles only. The empty state and the footer say the trail records the
  assistant's actions only, never what the wearer said or looked up. Debug Events stays in the
  Developer panel.
- **Check-ins** — `ScheduledTaskKind.goalCheckIn(goalID)` on `AgentScheduler.ScheduledTask`
  (`kind`, persisted as `goal_check_in:<uuid>`; a kind a newer build writes decodes as
  `unrecognised` and never runs, so the list still loads), plus `lastSpokenAt`.
  `GoalCheckInSchedule.reconciled` keeps exactly one check-in task per goal with a cadence that is
  active (on) or paused (off), removes it when the goal is done, set aside, deleted or its cadence
  turned off, and keeps its run history across a pause; a new daily/weekly check-in counts from
  when it was set. AppState reconciles on every change to `GoalStore.$goals` (skipped while the
  store is unreadable, which would read as no goals), and the scheduler reconciles again before
  each run. `ScheduleDuePolicy` treats only prompt tasks as due, so a check-in never reaches the
  model. `GoalCheckInPolicy.run` (pure): nothing while Agent Mode is off (check-ins pause, goals
  stay); each due check-in (`GoalAdvancePolicy.isCheckInDue` — `beforeDue(n)` once) files a
  `DigestItem` (`DigestSource.goal`, one per goal) and, when the wearer is present
  (`AgentNotificationQueue.canDeliverImmediately`) and fewer than two goal sentences were said
  today (the tasks' `lastSpokenAt` stamps), one sentence from `GoalPhraser.checkIn(for:)` through
  the queue. Each check-in also writes a "Checked in on a goal" trail row linked to the goal.
  Scheduled Tasks lists check-ins under Built-in by the goal's title, not editable or deletable
  there (the row opens the goal); its save merges its edits with the stored check-ins
  (`mergingEdits`).
- **My Day** — `MyDaySource.goals` ("Goals"), `GoalsDaySource` / `GoalStoreDaySource` (each active
  goal's next step with a date, its own or the goal's), `MyDayInputs.goalSteps`,
  `MyDaySourceSelection.goals` (`Config.myDayGoalsIncluded`, default on; nothing shows without
  goals) and its switch in My Day settings. `MyDayComposer` adds one row at most — the soonest of
  those steps that is overdue, due today (rank 2) or due tomorrow (rank 3): under a leave-by,
  above the weather — kind `.preparation`, actions `[.open, .complete, .dismiss]`, detail "Due
  today · <goal>". Complete marks the step done (`MyDayService.complete` routes by source); open
  pushes the goal's page from the full My Day screen; dismiss is the card's ordinary per-day clear.
  The row's glyph is a target. `daily_briefing` speaks it with the rest, and its description says
  so. The digest's own goal items stay out of My Day (P1), so a step is never shown twice.
- **Support report** — `GoalActivityReportLine`: "Goals: N active; activity entries (14 d): N",
  counts only, in the report's phone lines.
- **Memory** — the "Unfinished things" group carries a Goals link (a section of its own when no
  unfinished facts exist); goals are not memory facts and are not ingested into `BrainStore`.
- **UI-test seam** — `-OGUITestSeedGoals` writes one goal two steps in and a morning's trail
  through the shipping stores; every UI-test launch clears both files first, so a launch without
  it shows the empty states.
- Tests: `GoalCheckInTests` (cadence → task, finished/deleted/off → none, run history kept,
  screen-save merge, `beforeDue(3)` once, two sentences a day across goals, absent wearer → digest
  only, Agent Mode off pauses, the scheduler end to end, the prompt path never sees a check-in, the
  kind's codec and forward compatibility, the sentence), `MyDayComposerTests` (+4: under a
  leave-by and above the weather, tomorrow's step, none without goals or with nothing due, one row
  across goals), `MyDayGoalsSourceTests` (the selection switch, Done on a row), `GoalsScreenModelTests`,
  `ActivityScreenModelTests` (with the support line), `SettingsHubTests` (Goals and Activity under
  AI & Personality, Goals from Memory), and `GoalsActivityAccessibilityTests` (UI: both screens
  empty and populated, audited at the default size and AX5, screenshots light and dark).

Verified 2026-10-19 on the simulator (no phone reachable): the focused suites (147 tests — the
new `GoalCheckInTests` 13, `GoalsScreenModelTests` 13, `ActivityScreenModelTests` 8,
`MyDayGoalsSourceTests` 3 and the touched P1, My Day and hub suites); the full unit suite, 11,411
tests (16 skipped, zero failures); `GoalsActivityAccessibilityTests`, six UI cases — both screens
empty and populated, audited at the default size and at AX5 with no new deferrals beyond the
standard form set, and screenshots of each in light and dark; a Release build for the simulator;
the privacy-logging gate; gitleaks over the branch.

**Decisions taken in P2 (2026-10-19):** (1) a check-in's sentence count is read from the check-in
tasks' own `lastSpokenAt` stamps rather than a new store — each cadence fires at most once a day,
so the stamps are the day's count (a goal finished the same day takes its stamp with it); (2) a
check-in task is named "Goal check-in", not after the goal, so the wearer's words are not copied
into `UserDefaults`; (3) a goal typed on the screen needs one step or more (a spoken proposal keeps
3–7) and starts with the default check-in; (4) "Do it" never marks a step done — the wearer does,
as P0's suggest-only evidence rule has it; (5) My Day shows a step only when it is overdue or due
today or tomorrow, as reminders are kept to the day.

## Risks

- **A trail that reads like surveillance of the wearer.** It records the *assistant's* actions
  only: no reads, no transcript, titles in the assistant's voice. The screen copy says exactly
  that.
- **Goal nagging.** Two sentences a day, `.beforeDue` default, nothing executed unasked; the
  wearer sets the cadence.
- **Double records.** Operation journal, turn traces and the trail overlap by design and differ
  in purpose; `refs` link them so a reviewer can walk from a trail row to the journal record. The
  plan does not merge them.
- **Store sprawl.** Two new stores with the registry's full ceremony; both are small and capped.

## Decisions for Greig (all five taken 2026-10-19 — see P0 as built)

1. **Goals without Agent Mode** (recommended: a goal is the wearer's list; only the background
   check-ins are agentic), or gate the whole feature?
2. **Evidence auto-completion**: suggest only (recommended) or an opt-in that marks steps done?
3. **Trail horizon** 14 days / 1000 (recommended, matches traces) or 30 days?
4. **Record reads?** No (recommended) — or record `web_search` and `health_summary` so "what did
   you look up" has an answer?
5. **Home tile** in P2 or later?

## Out of scope

The assistant proposing goals on its own (GN decides), executing steps unasked, goals shared
with another person or the office, a goal that spans devices or the gateway, merging the journal,
traces and audit into one store, and any change to what `TurnTrace` or the HIPAA audit record.
