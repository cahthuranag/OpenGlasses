# Plan IW — Goals and the Activity Trail ("what are we working on, what did you do, what's next")

**Status:** 📝 Drafted (not scheduled), 2026-10-18 — nothing built.
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

## Decisions for Greig

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
