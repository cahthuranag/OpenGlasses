# Plan IX — Scoped Grants and Read-Only Integrations ("for this job", "read my calendar but never write it")

**Status:** 📝 Drafted (not scheduled), 2026-10-18 — nothing built.
**Extends:** `ApprovalGrant` / `ApprovalGrantStore` (`Services/Security/ApprovalGrant.swift`),
`ToolAuthorizationPolicy`, `ToolEffectClass` / `ToolEffectClassifier`, `ToolConfirmationCoordinator`,
`AIFeatureRegistry`, `ToolsSettingsView`.
**Keeps intact:** Plan [BC](BC-unconditional-safety-gate.md) (the actuation floor), Plan
[DJ](DJ-composed-tool-safety-and-execution-outcomes.md) ("every action reaches the authorization
boundary exactly once"), Plan [BN](BN-shared-consent-surface.md) (one consent surface), W04.3/W04.4
of Plan [EU](EU-remediation-roadmap.md) (consent records, bound approvals).
**Related:** Plan [R](R-mcp-egress-and-tool-poisoning-screen.md) (per-server egress policy — the
nearest thing to a per-integration switch today), Plan [GF](GF-recipe-add-ons.md) (per-add-on
permissions), Plan [CT](CT-org-configuration-profiles.md) (an organisation can pin any of this).

---

## Trigger

Two things the approval model cannot say today.

**"Yes, and for the rest of this job."** A bound approval is single-use and bound to the exact
arguments: the fifth `parts_request` on one job asks the fifth time. That is correct for an unlock
and wearisome for a technician dictating a parts list; the wearisome version teaches people to say
yes without listening, which is the failure the gate exists to prevent.

**"Read it, never write it."** A first-party integration is on or off as a whole. Calendar is one
switch, and the switch covers both "what's next" and "create an event". A wearer who wants the
assistant to know their day but never touch it has no setting, and a native write runs without
asking (the effect floor binds only external writes). Mail is the one exception by accident: the app
can only compose, never read.

## Outcome

- At a confirmation for a repeatable, non-actuating action the wearer may answer **"yes, for this
  job"** (Field Assist, bound to the active `FieldSession.id`) or **"yes, for the next hour"**
  (time-bounded); the assistant restates the scope once ("I'll record parts for this job without
  asking again"). Later matching actions proceed silently and are listed in the activity trail
  (Plan [IW](IW-goals-and-activity-trail.md)). "Stop that" or ending the job revokes.
- A **high-impact action never gets a standing grant**: unlock, disarm, open, send a message, make
  a call, export medical data, enrol a face, anything `unknown` — these ask every time, as now.
- Settings › each integration shows **Read only / Read and write / Off**: Calendar, Reminders,
  Notes, Health vault, Home (HomeKit and Home Assistant), Music, Alarms and timers. Read only
  removes the write actions from the tool's description and refuses them at the boundary with one
  sentence ("Calendar is read-only in Settings").
- Native writes to the wearer's own records (calendar, reminders, notes) ask once per session the
  first time a tool writes, then proceed; the wearer may pick "always ask" per integration.
- Grants and read-only choices are organisation-pinnable (CT) and visible in the support report.

## What exists today (verified 2026-10-18)

- `ApprovalBinding { serverIdentity, toolName, definitionDigest, argumentsDigest, sessionID }`;
  `ApprovalGrant { nonce, binding, issuedAt, ttl = 120 s }`, single-use, redeemed in the same
  `NativeToolRouter.execute` call that issued it; `sessionID` is the process lifetime in practice
  (`rotateSession` has no production caller). Refusal reasons: `noGrant, replayed, expired,
  sessionMismatch, serverMismatch, toolMismatch, definitionChanged, argumentsChanged`. Tests:
  `ToolApprovalBindingTests` (18).
- `ToolEffectClass` ordered `readOnly < write < biometricEnrolment < messaging < physicalActuation <
  sensitiveDisclosure < financial < unknown`; `requiresBoundApproval(on:)` is false for `readOnly`,
  true for native `write` **only on an external seam**, true for everything above. Classification is
  **per tool** from its `executionSemantics` row ("the strongest action"), action-aware only for
  `code_agent`, `face_recognition`, `smart_home`, `home_assistant`. External tools can never be
  `readOnly`; nothing matched → `unknown`.
- Ladder in `ToolAuthorizationPolicy.evaluate`: composition floor → BC actuation floor (when Agent
  Mode off) → `SafetySupervisor` (when on) → the post-ladder effect floor that raises `.allow` to
  `.confirm`. The decision has `call, agentModeEnabled, safetyContext, composedTargets, seam,
  effectClass` — **no job, turn or task identity**.
- `ToolConfirmationCoordinator.requestApproval` returns `.approved(nonce) | .denied |
  .consentWithdrawn`; `RemoteActionVoiceConsent.interpret` is yes/no only. `ConsentStore` exists
  (`consent-records.json`, W04.3) but **`consentStore` is never assigned** in the app, so the
  coordinator runs `.noLedger` and nothing is recorded or withdrawable.
- Per-integration surfaces: `Config.disabledTools` (all-or-nothing per tool, `ToolsSettingsView`,
  org-clamped by `SettingsLockPolicy`), `AIFeatureRegistry` switches (`smartHomeControlEnabled`,
  `aiMessagingEnabled`, `healthVaultAIEnabled` **have no Settings UI**), MCP per-server `enabled` +
  `EgressPolicy`, skill-pack enable. No read-only mode anywhere.
- First-party tools and their verbs (all in `description` text, none a schema `enum`): `calendar`
  (today/next/upcoming | create), `reminder` (list | create, complete), `health_vault` (query | log),
  `save_note`/`notes_vault` (write) with `list_notes` (read), `home_assistant` (get_state,
  list_entities | toggle, call_service, run_automation, converse), `smart_home` (list, list_scenes |
  on/off/toggle/set/scene | lock/unlock → actuation), `music_control` (now_playing, search, devices |
  play/pause/next/volume/add_to_library), `set_alarm` (list | set, cancel), `set_timer` (write).
  **No mail-reading tool**; `send_via channel:email` composes only.
- Field Assist: one active job, `FieldSessionService.activeSession?.id` (UUID, ends with the job),
  `jobReference` optional; `LiveJobBridge.generation` per live session.
- Audit: `ToolAuthorizationEventLog` records refusals only (in memory, 50); approvals exist only as
  `PrivacyLog.toolGate` events.

## Design

### Grant scopes (`ApprovalScope`, pure)

```swift
enum ApprovalScope: Codable, Equatable {
    case once                                  // today's grant: exact arguments, 120 s, single use
    case session                               // this process; exact tool, any arguments of the same shape
    case job(fieldSessionID: String)           // until the job ends or is paused
    case timeBounded(until: Date)              // 15 min / 1 h / until I take the glasses off
}
```

A standing grant (`session`, `job`, `timeBounded`) binds `serverIdentity + toolName + definitionDigest
+ scope` and an **argument shape** rather than exact arguments: `ArgumentShape.digest(args, keys:)`
over the action-selecting keys only (`action`, `verb`, `channel`, `service`), so "record parts for
this job" covers any part number but not a different verb. The shape keys per tool live in one table
beside the semantics rows (`ToolActionKeys`), tested to cover every tool with more than one verb.

**Eligibility (`StandingGrantPolicy`, pure):** a standing grant may be *offered* only when all hold:
effect class is `write` or `messaging`-class tools explicitly listed as repeatable (`parts_request`,
`deliver_report` are the two; `send_message`, `phone_call`, `send_via` are not), seam is `.native`
or an MCP server whose policy is not `block`, the action is not `PromptInjectionPolicy.isHighImpact`,
and the tool is not in `HighImpactToolPolicy.mayRequireConfirmation`. `physicalActuation`,
`biometricEnrolment`, `sensitiveDisclosure`, `financial` and `unknown` are **never eligible**, in any
mode, from any origin — the BC floor and the DJ single-boundary rule are untouched because the
standing grant is only ever consulted *after* the ladder has said `.confirm`, in place of asking.

**Revocation:** job end/pause (`FieldSessionService` publishes), the time bound, "stop that" /
"ask me again" (`RemoteActionVoiceConsent` gains `revoke`), glasses doffed for `timeBounded` when
chosen so, a tool definition change (digest mismatch → the grant is dead and the wearer is asked
anew with "What you agreed to has changed"), Agent Mode turning off, an org policy change, and
`ApprovalGrantStore.rotateSession`. Revocation is immediate and logged.

**Store:** `ApprovalGrantStore` gains `standing: [StandingGrant]`, persisted for `job` and
`timeBounded` only (`Application Support/Security/standing-grants.json`, `completeUntilFirstUserAuthentication`,
backup-excluded; `session` grants die with the process), registered in `DataStoreRegistry` with
`deleteAll` and reachable from the Memory screen's "Forget everything" path. Cap 32.

### Asking with a scope (`ToolConfirmationCoordinator`)

`requestApproval` gains `offeredScopes: [ApprovalScope]` from the policy. The spoken prompt stays
one sentence; when scopes are offered it ends "…say yes, or yes for this job." The phone card shows
the scope buttons. `RemoteActionVoiceConsent.interpret` learns "yes for this job / for the rest of
the job / until I'm done", "yes for an hour / fifteen minutes / until I take them off", "always ask",
"stop that". Anything ambiguous is a plain yes (`once`). The assistant **restates the scope** after a
standing yes. **`consentStore` is finally wired** so every approval, with its scope, is a
`ConsentRecord` (purpose `.toolAction`, new), and the Settings screen below can withdraw it.

### Read-only integrations (`IntegrationAccess`, pure)

```swift
enum IntegrationAccess: String, Codable { case off, readOnly, readWrite }
enum Integration: String, CaseIterable { calendar, reminders, notes, healthVault, home, music, alarms }
```

`IntegrationAccessPolicy.verdict(tool:args:) -> .allow | .refuse(message)` using `ToolActionKeys`
and a per-tool `readVerbs` / `writeVerbs` table (**the table is the new source of truth; the
descriptions are generated from it** so the model is told only the verbs it may use). Evaluated in
`NativeToolRouter.execute` right after the feature gate (step 2), before the ladder, as a refusal
with reason `integrationReadOnly`, recorded in the authorization event log. `home_assistant converse`
(free text) counts as a write. `off` keeps today's `disabledTools` behaviour (tool removed).
Stored as `Config.integrationAccess[Integration]` (default `readWrite` for all, so nothing changes
on upgrade), org-pinnable via `ManagedLockdown` (`closedTools` gains `readOnlyIntegrations`).

### Native writes ask once (`NativeWriteConfirmationPolicy`)

Today a native `write` never confirms. New rule, default on: the **first** native write per
integration per session asks ("I'm about to add an event to your calendar, is that okay?"), and the
yes is a `session` grant for that integration's write shape. Per-integration override "Always ask".
This gives native writes the same shape as everything else (a `.confirm` that a standing grant can
answer) without a prompt on every reminder. `set_timer` and `set_alarm` are exempt (they are the
request itself). Tests must show the BC floor still fires for lock/unlock regardless.

### Surfaces

- Settings › **Integrations & Permissions** (new row under Devices & Privacy): one row per
  `Integration` with the three-way picker and the "Always ask" toggle; a **Standing permissions**
  list (scope, tool, when, revoke) backed by the consent records; the three registry switches that
  have no UI today (`smartHomeControlEnabled`, `aiMessagingEnabled`, `healthVaultAIEnabled`) land
  here as well.
- Support report (FV) gains a content-free "standing grants active: N; integrations read-only:
  [calendar]" line. Copy never names a plan letter.

## Phases (one PR each)

**P0 — Pure core.** `ApprovalScope`, `ArgumentShape` + `ToolActionKeys`, `StandingGrantPolicy`
(eligibility), `StandingGrant` + store logic (issue/consult/revoke/expiry, persistence as a pure
codec), `IntegrationAccess` + `IntegrationAccessPolicy` + the read/write verb table,
`NativeWriteConfirmationPolicy`, `RemoteActionVoiceConsent` scope phrases. Tests:
`ApprovalScopeTests` (job grant dies with the job; time bound honoured; doff revokes when chosen),
`ArgumentShapeTests` (same verb different part number → same shape; different verb → different),
`StandingGrantPolicyTests` (**table over every registered tool × effect class: no actuation,
biometric, disclosure, financial or unknown class is ever eligible; `send_message`/`phone_call`/
`send_via` never; unlock never even on `.native`**), `IntegrationAccessPolicyTests` (every tool
with two or more verbs has a complete read/write split; `converse` is a write; read-only refuses
writes and allows reads; description generation lists only permitted verbs), `VoiceConsentScopeTests`
(ambiguous → once). `ToolEffectClassPolicyTests` and `SafetyGateTests` **unchanged and green**.

**P1 — Boundary and coordinator.** `NativeToolRouter.execute` consults the integration policy then,
after a `.confirm`, the standing grants; `requestApproval` with offered scopes; `consentStore` wired;
scope restatement; revocation hooks (`FieldSessionService`, doff via `GlassesConnectionService.isWorn`,
Agent Mode off, org change). Tests: `StandingGrantRouterTests` (a job grant answers the second
`parts_request`; the third after `endSession` asks; a definition change kills the grant; BC floor
still asks for unlock under a live session grant; DJ single-boundary tests unchanged),
`ConsentLedgerWiringTests` (every approval writes a record; withdraw revokes).

**P2 — Settings, report, org.** The Integrations & Permissions screen, the three orphan switches,
`ManagedLockdown` read-only pins, support-report line, `DataStoreRegistry` entry and the ET matrix
regeneration. Tests: `SettingsHubTests` update, `ManagedLockdownTests` (pinned read-only cannot be
widened), `DataStoreRegistryTests` green. Device pass (owed): a technician dictating five parts on
one job hears one question; "stop that" works mid-list; calendar read-only refuses a create in one
sentence and the model does not retry.

## Risks

- **Scope creep in the word "yes".** A standing grant is only ever an answer to a confirmation the
  ladder already demanded; the eligibility table is the whole safety argument and is tested over
  every tool. The one new permissive rule (native writes ask once) is a *tightening* of today.
- **Argument shape too loose.** Shape keys are per tool and reviewed; a tool without a shape entry
  cannot receive a standing grant (fails closed to `once`).
- **Description drift.** Generating verb lists from the table changes every integration tool's
  description text; the prompt-cache and tool-schema tests need the new text, and the model may
  need a sentence telling it read-only refusals are final.
- **Consent ledger size.** 500-record cap exists; standing grants add few.

## Decisions for Greig

1. **Which scopes in v1:** `job` and `timeBounded` (recommended), or `session` too?
2. **Repeatable messaging-class tools:** `parts_request` and `deliver_report` eligible for a job
   grant (recommended: they are the Field Assist pain), or no messaging class at all?
3. **Native writes ask once** on by default (recommended), or opt-in?
4. **Time bounds offered:** 15 min / 1 h / until doffed, or just "until doffed"?
5. **Default access** for Home: `readWrite` on upgrade (recommended, no behaviour change) or
   `readOnly` for new installs?

## Out of scope

A mail-reading integration (there is none to make read-only), per-MCP-tool toggles, grants that
survive a reinstall, remote-origin (gateway, ops peer) standing grants, and any change to the BC
actuation floor, the DJ boundary or the BN consent surface's single-pending rule.
