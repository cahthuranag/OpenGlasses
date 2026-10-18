# Plan JC — Planning-Sweep Fixes (small defects found while drafting IW–JB)

**Status:** 📝 Drafted (not scheduled), 2026-10-18 — nothing built.
**Shape:** a bundle in the manner of Plan [ID](ID-ecosystem-review-hardening-bundle.md): five
independent items, each a few lines and a test, **one PR for the bundle**. Items 1 and 2 are taken
out of the plans that first claimed them ([IW](IW-goals-and-activity-trail.md) P0 and
[IX](IX-scoped-grants-and-read-only-integrations.md) P2) because wearers are affected today and
neither needs the parent plan's design.
**Not here, on purpose:** wiring the dormant `ConsentStore` (a design change — IX P1), the
`ToolPermissionGate` correction for `fitness_coach` (lands with the tool's rewrite — JA P1), and
the missing navigation tests (IY P0 opens those files anyway).

---

## Items

### 1. Once-daily scheduled tasks never run

**Found (verified 2026-10-18):** `AgentScheduler.checkScheduledTasks` loops
`for task in tasks where task.enabled && task.intervalMinutes > 0`. `AgentScheduleTool` and the
`ScheduledTasksView` footer both call `intervalMinutes == 0` "once daily" / "Runs once when the
agent starts each day". The built-in `capability-review` task (interval 0) has therefore never run
from the scheduler, and any wearer who created a once-daily task got nothing, silently.

**Fix:** a pure `ScheduleDuePolicy.isDue(task, now, calendar)`: interval > 0 → `now - lastRun >=
interval`; interval == 0 → `lastRun` is nil or on an earlier calendar day in the wearer's time zone
(one run per day, at the first eligible cycle after midnight). The loop uses it. The view footer
says what actually happens ("Runs once a day, the first time the assistant checks after midnight").

**Test:** `ScheduleDuePolicyTests` — interval tasks unchanged; a 0-interval task due with nil
`lastRun`, due at 00:05 when last run was 23:55 the day before, not due twice in one day, day
boundary in `Pacific/Auckland` on a DST change.

### 2. Three AI feature switches have no Settings UI

**Found:** `AIFeatureRegistry` records `smartHomeControl` (`smartHomeControlEnabled` →
`smart_home`, `home_assistant`), `messaging` (`aiMessagingEnabled` → `send_message`, `send_via`,
`asian_messaging`) and `healthVault` (`healthVaultAIEnabled` → `health_vault`). The router gates on
them (`AIFeatureGate.disabledFeature(forTool:)` is the first check in `execute`), but the keys exist
only in `Config` and the registry — **no view renders them**. A wearer cannot turn off AI control of
their home or AI-sent messages except by disabling each tool individually in Tools, which does not
read as the same thing. The other switches are surfaced in their own areas (`EnrolledFacesView`,
`HealthSettingsView`, First Aid in `SettingsView`).

**Fix:** one `InfoToggle` each, where the wearer would look: smart-home control beside the
HomeKit / Home Assistant settings, AI messaging beside the messaging settings, health-vault access in
`HealthSettingsView` next to the health-summaries switch. Copy states the effect ("When off, the
assistant can see your home devices listed in Tools but cannot control them"). Org visibility
through `SettingsVisibilityPolicy` as for the existing switches. IX P2's Integrations screen may
later gather them; this item is about existence, not placement.

**Test:** `AIFeatureSwitchSurfaceTests` — scrape `OpenGlasses/Sources/App/Views` for every
`disableSwitch.key` in the registry; each must appear in at least one view file (the pattern of
`OutboundFrameConsumerTests` / `DataStoreRegistryTests`). Pins the three and prevents a fourth
orphan.

### 3. Plan-step constraint re-injection is dead code

**Found:** `PlanExecutor` has `onNarrate`, `onStep` and `onReinject`; `AgentRunner` wires only
`executor.onStep`. `PlanExecutor.constraintReinjection` is therefore never reached in production,
and `LLMService.onAgentNarrate` is fed by the runner, not the executor. Plan S's intent (restate
the plan's constraints to the model between steps) is not what ships, and nothing says so.

**Fix (decision below):** either wire `onReinject` and the executor's `onNarrate` through
`AgentRunner` to `LLMService`'s existing hooks, or delete the hook and the dead path. Whichever is
chosen, Plan S's status line records it.

**Test:** if wired — `AgentRunnerHookTests`: a two-step plan with a constraint re-injects once
between steps and narrates each step; if removed — the existing `AgentSafetyTests` stay green and
`PlanExecutor` has no unused hook (a one-line assertion in `AgentSafetyTests` that the type exposes
only `onStep`).

### 4. Registry and code disagree on the remote-invoke audit cap

**Found:** `DataStoreRegistry` records `.remoteInvokeAudit` with retention `.cap(50)`;
`RemoteInvokeService.auditLimit = 100`. The ET data-lifecycle matrix (generated from the registry)
therefore states a retention the code does not enforce.

**Fix:** one source of truth — `RemoteInvokeService.auditLimit` becomes the registry's declared
value (or the registry is corrected to 100; decision below), and the registry record references
the constant so they cannot drift again. Regenerate the ET matrix (`UPDATE_PLAN_DOCS`).

**Test:** `RemoteInvokeAuditRetentionTests` — append `cap + 5` entries, read back `cap`; and a
registry attribute-truth test asserting the record's `.cap(n)` equals the service constant (the
pattern other stores already use).

### 5. `manage_schedule` drops a decimal interval and overwrites by slug

**Found:** `AgentScheduleTool.create` reads `args["interval_minutes"] as? Int ?? 30`; a model that
sends `15.0` (common from JSON numbers) gets 30 minutes with no notice. The task id is a slug of the
name with no uniqueness check, so "Check prices" created twice silently replaces the first task.

**Fix:** accept `Int`, `Double` (rounded) and numeric `String`; refuse non-numeric with a spoken
reason. On a slug collision, suffix `-2`, `-3` and say which task was created. The tool's reply
names the interval it actually stored.

**Test:** `AgentScheduleToolTests` (new file — the tool has none): `15.0` → 15; `"20"` → 20;
`"soon"` → refused; two creates with the same name → two tasks; the reply states the interval.

## Exit criteria

- One PR; every item above has its named test; the full suite and a Release build green before it
  opens (house rule).
- Plan S's status line updated for item 3; Plan ET's matrix regenerated for item 4; the IW P0 and
  IX P2 lines that claimed items 1 and 2 are amended to point here (done in the drafting PR).
- No behaviour change beyond the five items; no new stores, routes or tools.

## Decisions for Greig

1. **Item 3:** wire the re-injection (recommended — it is what Plan S promised and the hook is
   there) or delete it?
2. **Item 4:** 100 (the code's number, more history for the audit view) or 50 (the registry's)?
   *Recommend 100 and fix the registry.*
3. **Item 2 placement:** beside each feature's own settings (recommended) or one "AI features" list
   under Devices & Privacy now?

## Out of scope

The consent-store wiring, the fitness permission gate, navigation tests, the standing-grant work, the
scheduler's run history (IW) and anything that changes what a scheduled run does.
