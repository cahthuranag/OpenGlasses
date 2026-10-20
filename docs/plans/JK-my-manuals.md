# Plan JK — My Manuals (a personal tier: your own manuals, asked by voice, without Field Assist)

**Status:** 📝 Drafted 2026-10-20 — nothing implemented. Owner decisions the same day: the product
is called **My Manuals**; it holds **five manuals**; it is sold as a **monthly and an annual**
subscription; it is a new **`personal` tier** below `solo`; and its figures are set in the store
configuration and off-repo, never in this plan, a PR or a commit (the rule
[Plan EE](EE-field-assist-commercial-licensing.md) set for every price).
**Track:** consumer. Phone first; the glasses, AirPods and CarPlay are surfaces, not requirements.
**Related:** [EE](EE-field-assist-commercial-licensing.md) (tiers, the paywall, the store products),
[FS](FS-subscriber-vaults-and-vault-links.md) (a subscriber's own vaults, receiving a vault by link
or QR, the never-share rule), [H](H-custom-vault-import.md) (the importer),
[EF](EF-scanned-manual-import.md) and [IF](IF-photographed-manuals.md) (a paper manual, by camera),
[EK](EK-manual-structure-and-figures.md) (figures), [JJ](JJ-table-lookup-and-rule-chains.md)
(tables), [FN](FN-vault-manual-removal.md) (removal), [DP](DP-release-entitlement-boundary.md)
(entitlement is verified evidence, never a preference), [HB](HB-field-assist-mode-and-job-day.md)
(Field Assist as a mode of the phone), [JD](JD-apple-intelligence-tools.md) (the on-device tool
set), [DH](DH-local-gemma-keyless-tier.md) (a local model, no key).

---

## Why

The owner's question: *could Field Assist be made for a private user — the person with a car in the
garage who wants a few manuals at hand — without giving them the solo technician's Field Assist?*

Yes, and cheaply, because the part that person wants already ships and already sits behind one
capability. Since Plan FS a gate never asks *which tier* but *which capability*
(`FieldAssistCapability`), and a store product resolves to a capability set in one pure function.
Import a PDF, photograph the pages of the manual in the glovebox, ask a question hands-free and hear
the answer with its page, say "show me" and see the page with the passage marked, read one cell of
a torque table with its headings and units, receive a manual set a publisher sells by scanning a
code: every one of those is behind `ownVaults`, and none of it was built for teams.

The hard part is the other half of the question. "Ask my manual" is also the heart of what the solo
technician buys, so a cheaper tier has to be defined by what it **lacks**, and the lack has to be
structural — a capability the code asks for — rather than a hidden switch or a word on a paywall.
Three things do that, and together they are the whole plan:

1. **No Field Assist mode.** The phone never becomes a technician's phone: no Field Assist tab, no
   Jobs tab, no job-day card, no sessions, work records, procedures, escalation, van stock, parts
   orders, apprentice logbook, refrigerant toolkit, site systems, field-service connectors or team
   learnings. All of those hang off the mode today, so one new capability removes the lot.
2. **No bundled trade vaults and no packs.** The customer brings their own manuals.
3. **A quota.** Five manuals. There is no vault or document limit anywhere in the code today; this
   is the one genuinely new concept.

The competitor review of 2026-10-17 recommended exactly this shape: a low-priced individual tier as
the funnel, leading with what no rival has (a wake word on AirPods, CarPlay and the glasses), with
the working technician's tier and then the team seat as the upgrades. The ladder holds only if the
middle rung is priced for what it adds — the whole job layer — not for the manuals.

## The customer, in one paragraph

Someone owns a car, a motorbike, a boat, a tractor, a sewing machine or a 1990s hi-fi, and owns the
manual for it: a factory service manual bought as a PDF, a workshop manual on paper, the owner's
handbook in the glovebox. Their hands are dirty or full. They want to ask "what's the torque on the
sump plug" or "which fuse is the rear wiper" and hear the answer with the page, then glance at the
page on the phone on the bench. They do not have a job, a customer, a crew or a van. They will not
tolerate the word *vault*, a "session", or a screen that asks which trade they are in.

## Verified starting point (main, 2026-10-20, build 541)

- **Capabilities, not tiers, are the gates.** `FieldAssistCapability` (`Sources/Services/Entitlement/`)
  resolves one piece of evidence to a set: a Field Assist subscription grants `bundledVaults` and
  `ownVaults`; the retired one-time unlock, and *any store product the build does not recognise*,
  grant `bundledVaults` only; a licence code grants by its signed tier. `capabilities(for set:)`
  unions live evidence; lapsed evidence contributes nothing. `FieldAssistCapabilityCheck.resolve`
  gives a gate `granted` / `notIncluded(held:)` / `denied(reason)`, so a screen can say *your
  purchase covers X; Y comes with Z* instead of a generic lock.
- **A tier is what a licence is.** `FieldAssistTier` is `solo` / `team` / `enterprise`, `Comparable`
  by rank; `FieldAssistEntitlementEvaluator.decide` picks the highest live tier, then perpetual, then
  the later expiry, and reports the granted tier and when it lapses. Licence codes carry a signed
  `tier`; `LicenseService` reads a code's claim and never resolves it below `team`
  (`testSoloCodeClaimIsNeverBelowTeam`).
- **Field Assist is a mode.** `FieldAssistMode.isOn` (Plan HB) is `(switchOn || restricted) &&
  entitled`, where `entitled` is `Config.fieldAssistUnlocked`, which is
  `FieldAssistEntitlement.shared.isGranted` — *any* live evidence. `Config.fieldAssistActive` is the
  switch and the grant together; the field tools and vaults gate on it.
- **Every manual tool needs a field session today.** `manual_lookup`, `manual_figure`, `table_lookup`
  and `show_source` all begin `guard Config.fieldAssistActive` and then `guard let store =
  session.activeVault`, the vault `FieldSessionService` loaded for the job. There is no way to ask a
  manual a question without Field Assist switched on and a vault chosen as the session's.
  `equipment_lookup` does the same and reads an organisation's site systems.
- **Own vaults are one gate.** `VaultRegistry.isUnlocked` returns `has(.ownVaults)` for a vault of
  the reader's own, `isGranted` for the two bundled trade vaults, and the pack rules (store product,
  licence `packs` claim, or `everyVaultPack`) for a pack. `VaultImporter` refuses to ingest without
  `ownVaults` but lets a lapsed licence still shed manuals. `CapturedManualCatalog` (photographed
  pages) asks `ownVaults` alone for local use; only submitting pages for an organisation reviewer asks
  `capturedManualReview`. `VaultLinkService` asks `ownVaults` before installing a received vault.
- **No quota exists.** The only limits are the receive path's byte, entry-count and zip-slip caps.
- **The store.** `StoreKitService` knows three Field Assist products: the retired non-consumable and
  the monthly and annual subscriptions, in one subscription group, `field_assist`. The paywall
  offers `fieldAssistCatalogProductIds` (monthly only today). `FieldAssistPaywallCopy`
  (`FieldAssistEntitlementStatus.swift`) is guarded by `testPaywallCopyNeverSteersOutsideTheStore`.
  `FieldAssistEntitlementStatus` gives the 30-day and 7-day lapse warnings.
- **Manuals never leave the phone** (FS): every export and every vault archive excludes documents
  (`documents_included` marker); the app never offers to share a vault; received manuals are
  excluded from export. These rules carry over unchanged and are the reason a personal customer can
  index a copyrighted manual they own: it is their copy, read on their phone, redistributed by nothing.

## Product shape

| Capability | My Manuals (`personal`) | Field Assist (`solo`) | Team / Enterprise |
|---|---|---|---|
| Your own manuals, indexed on the phone (`ownVaults`) | ✅ **five manuals** | ✅ no limit | ✅ |
| Ask by voice, page cited, "show me" opens the page with the passage marked | ✅ | ✅ | ✅ |
| Figures and table cells from your manuals | ✅ | ✅ | ✅ |
| A paper manual by camera (local pages) | ✅ counts as a manual | ✅ | ✅ (+ reviewer route) |
| Receive a manual set by link or QR (FS) | ✅ counts its manuals | ✅ | ✅ |
| Wake word on AirPods, CarPlay, the glasses | ✅ | ✅ | ✅ |
| Field Assist mode: tabs, jobs, sessions, work records, procedures (`fieldWork`, new) | — | ✅ | ✅ |
| Bundled trade vaults, domain calculators (`bundledVaults`) | — | ✅ | ✅ |
| Vault packs | — | by purchase | by licence / all |
| Expert escalation, van stock, parts, site systems, refrigerant toolkit, apprentice, FSM | — | ✅ (as each plan says) | ✅ |
| Audited export, org configuration, team learnings, reviewer route | — | — | ✅ |

| Who | Vehicle | Where |
|---|---|---|
| Private owner | two new auto-renewing products, monthly and annual, in the **same** subscription group as Field Assist, one level **below** solo | In-app, StoreKit |
| Solo technician | the existing Field Assist monthly / annual | In-app, StoreKit |
| Team / enterprise | signed licence code (never `personal`) | Vendor |

Same group, lower level: upgrading from My Manuals to Field Assist is an in-group upgrade with
Apple's proration and one subscription, and the customer's manuals are already own vaults, so
nothing is re-imported — the limit lifts. The downgrade is the same path in reverse, and the quota
then applies to what they hold (see §2).

## Design

### 1. Entitlement: a tier that *is* something and a capability that gates the mode

- **`FieldAssistTier.personal`**, rank below `solo`, label "Personal", summary: *Up to five manuals of
  your own, asked by voice with the page cited.* Raw value `personal`. The evaluator needs no change:
  a personal subscription beside a live Field Assist subscription grants solo and reports solo's
  lapse; beside a lapsed one it grants personal. `LicenseService` keeps its clamp: a code claiming
  `personal` still resolves to `team`, because a vendor never issues the personal tier and a
  code's floor is the organisation's.
- **Two product ids** — `com.openglasses.my_manuals_monthly`, `com.openglasses.my_manuals_annual` —
  in `StoreKitService`, recorded as evidence by the existing `VerifiedStorePurchaseRecorder`, with
  `FieldAssistEntitlementEvidence.tier` reading `personal` for them (today every store product reads
  `solo`; `testStoreProductsAreAlwaysSolo` becomes *store products are solo unless personal*).
- **`FieldAssistCapability.fieldWork`** (new): *the phone as a technician's: Field Assist mode, a
  field session, the job tools.* Granted by both Field Assist subscriptions, the retired unlock, and
  every licence tier. **Not** granted by the personal products, which grant exactly `[.ownVaults]`.
- **The mode asks for it.** `FieldAssistMode.Inputs.entitled` and `Config.fieldAssistUnlocked` read
  `has(.fieldWork)` instead of `isGranted`. `Config.fieldAssistActive` follows. A personal subscriber
  with the Field Assist switch somehow on sees nothing change: the Modes tab stays the persona picker,
  the Jobs tab is absent, the Settings › Field Assist screen shows the Field Assist paywall with its
  `notIncluded(held: [.ownVaults])` explanation ("your My Manuals subscription covers your own
  manuals; Field Assist adds jobs, the trade vaults and the job tools").
- **The bundled vaults ask for theirs.** `VaultRegistry.isUnlocked`'s two bundled branches read
  `has(.bundledVaults)`; the pack branch requires `has(.fieldWork)` before the pack rules (a pack is
  a trade's; a publisher's manual set for a private owner is a received vault, not a pack). The
  Packs list is hidden without `fieldWork`.
- **`FieldAssistCapability.manualLimit(for set:)`** (new, pure): the number of manuals the live
  evidence allows across every own vault, or nil for no limit. Personal → 5; anything else granting
  `ownVaults` → nil; the most generous live piece wins. Only `ownVaults` holders ever reach it.
- Everything above is pure and lands with a truth table in `FieldAssistCapabilityTests` /
  `FieldAssistTierTests`: every evidence combination × every capability × the limit, and
  `FieldAssistMode` with a personal grant in every switch/edition state.

### 2. The library: five manuals, counted at the only two doors

A *manual* is one document in an own vault: a PDF, a text import's original, a photographed manual,
or one document of a received vault. The count is over every own vault on the phone. Nothing is
counted by size or pages.

- **`ManualQuota`** (new, pure): `decide(limit: Int?, held: Int, adding: Int) -> Verdict` with
  `.allowed`, `.wouldExceed(held:, adding:, limit:)`. Called at the two doors a manual can enter:
  `VaultImporter` (the plan's `toIngest`, before the entitlement gate's existing position) and
  `VaultLinkService` (the offer, so the refusal is on the confirmation sheet with the counts, not
  after a download). A refusal names the counts: *"This set has 8 manuals. My Manuals holds 5, and
  you have 2. Remove some, or Field Assist has no limit."* A received set is refused whole, never
  installed partially — a partial manual set would answer wrong by omission.
- **The photographed route counts.** `ManualCaptureTool` / `CapturedManualCatalog` ask the quota
  before a new capture begins, not when its pages are bound.
- **Removal frees a slot** through Plan FN's removal, unchanged. Forgetting never needs the
  entitlement (the importer's rule today) and never needs the quota.
- **Over the limit without adding** — a downgrade from Field Assist, or a lapse — deletes nothing.
  Every manual stays readable while an `ownVaults` grant is live; the quota only refuses the next
  addition. On lapse, reading stops exactly as an own vault's does today (`isUnlocked` false), the
  files stay until the person removes them, and the paywall says so. No grace period beyond Apple's
  own billing grace (Plan EE's open question stands; the decision here is *no*).
- **One place to live.** On first addition without any own vault, the app creates the personal vault
  (`my-manuals`, an own vault like any Plan H import, with no trades, procedures or scenarios) and
  adds to it. A received set keeps its own vault id, as FS requires, and counts into the same five.
  The word *vault* appears nowhere the personal customer reads; the library screen lists manuals.

### 3. Answering without a field session

The four manual tools stop asking for a session and ask **which manuals answer right now**:

- **`ManualSource`** (new, pure): given `fieldAssistActive`, the session's active vault (if any),
  whether `ownVaults` is held, and the own vaults with documents, return `.session(store)` when Field
  Assist is active and a session vault is loaded; else `.library(stores)` when `ownVaults` is held
  and a store has documents; else `.none(reason)` with a reason the tool can say ("you have no
  manuals yet — add one in Settings › My Manuals" / "your My Manuals subscription has ended").
- `manual_lookup`, `manual_figure`, `table_lookup` and `show_source` replace `guard
  Config.fieldAssistActive` + `session.activeVault` with the resolver. Retrieval, figures, tables,
  the page sheet (`ManualPageSheet`) and the passage highlight are unchanged behind it; a library of
  several vaults is searched as one corpus (`DocumentStore` namespaces per vault, as today), and an
  answer names the manual when more than one is loaded (`manual_lookup`'s `manual` filter already
  exists). `equipment_lookup` keeps its field-session guard: site systems are an organisation's.
- **Tool descriptions** say "the manuals you have loaded" rather than "the vault"; the system-prompt
  list is generated from them (`SystemPromptBuilder`), so no other list changes. The Field Assist
  wording stays for a field session, chosen by the resolver's case.
- **The on-device set** (JD): `AppleOnDeviceToolSet.priorityNames` gets a `libraryHasManuals` input
  beside `fieldAssistActive`, so `manual_figure`, `table_lookup` and `show_source` rank early for a
  personal customer too. `manual_lookup` stays off that set for the reason JD recorded (a lookup's
  size), and a cloud or local model answers it as now. `FieldToolProfile` applies only in a field
  job and is untouched.
- **Where the answer is heard and seen.** The ordinary assistant, in any persona, by wake word on
  AirPods, the glasses or in CarPlay; the page opens on the phone, never in the car (the existing
  car rules), and the HUD is unchanged. Nothing here is a mode.

### 4. Surfaces

- **Settings › My Manuals** (`SettingsCatalog` entry, a sibling of Field Assist, shown to everyone
  without `fieldWork`; a Field Assist holder manages the same vaults under Custom Vaults and sees
  My Manuals as a row that says so): the subscription row with the status and warnings
  (`FieldAssistEntitlementStatus` reused), the manuals held of five, each with title, pages and
  source (file, camera, received), *Add a manual* (Files picker; the camera route; *scan a code*
  for a received set), remove, storage used, and *What the assistant can read*: your manuals are
  indexed on this phone and never leave it through the app; when you ask, the passages that answer
  are sent to the model you have chosen, or stay on the phone with a local model.
- **The paywall.** `MyManualsPaywallCopy` beside `FieldAssistPaywallCopy`, both under the
  never-steer-outside-the-store guard: what you get, five manuals, monthly and annual, the terms and
  privacy links, *Restore purchases*, and the Field Assist upgrade as the one line Apple's rules
  allow for an in-group upgrade. The Field Assist paywall gains a line naming the smaller option.
  `fieldAssistCatalogProductIds` splits into the two offer sets.
- **The Modes tab** (HB) for a personal subscriber: the persona picker with no Field Assist row;
  `ModesTabPresentation` gets a case for *entitled to manuals, not to Field Assist*, which is the
  persona picker, nothing added.
- **First run after purchase**: one hint on the home screen, *Add your first manual*, until one is.
- **An organisation's edition in force** (`AdminGate.isRestricted`): My Manuals is not offered and a
  personal library never answers in a field session — the resolver's `.session` case wins whenever
  Field Assist is active, and the Settings entry is hidden under the edition. A technician's own
  manuals do not leak into an audited job.

### 5. What stays out, by construction

Because `fieldWork` is missing: Field Assist mode and both its tabs; `field_session` and every job
tool in `FieldToolProfile.names` that is not a manual tool; work records and the session log;
procedures and `procedure_runner`; `domain_calc` and `refrigerant_gauges`; escalation and the
expert transports; van stock, parts, deliveries; site systems; the apprentice logbook; team
learnings; the office route and every connector. Because `bundledVaults` is missing: the two trade
vaults. Because `auditedExport` is missing: every export of a session (there is none). Because
`capturedManualReview` is missing: pages never go to a reviewer. Each is a test, not a promise.

### 6. Store

Two products in the `field_assist` group at a level below the Field Assist pair; family sharing off
(as every product today; open question 1); the local `.storekit` file gains both with placeholder
figures that are the only place a figure shows in the repo; App Store Connect is the owner's by hand.
Sandbox checks: buy personal → import 5 → sixth refused → upgrade in-group → sixth imports → downgrade
→ all 6 still readable, seventh refused → let lapse → reading stops, files stay, re-subscribe → reading
resumes with nothing re-imported.

### 7. Privacy, copyright, data

- **Copyright.** The person indexes a manual they own, on their phone, for their own use. The app
  never redistributes it: FS's rules (no sharing, documents out of every export and archive) are
  the enforcement and stay guarded by their tests. The in-app copy says *your own copy*.
- **The model sees passages.** As with every vault today, the passages that answer go to the model
  the person has chosen; a local model (DH) keeps them on the phone. `AIFeatureRegistry` gets a
  `myManuals` record (or the Field Assist record's title and copy widen to "Field Assist and My
  Manuals") so the privacy copy names it; the `PrivacyInfo.xcprivacy` claims do not change (no new
  egress, no new SDK).
- **Stores.** The library is own vaults in `DocumentStore` namespaces and the vault ledger, both
  already registered in `DataStoreRegistry` and covered by subject erasure; the quota keeps no
  store of its own (it counts the ledger). The capture catalogue is as IF left it.
- **Medical mode** keeps its existing vault rules; nothing new is read or sent.
- **EU AI Act**: retrieval over the person's own documents; nothing in Annex III; no change to the
  review document.
- **Nothing is a preference.** The grant is the verified transaction; the quota is derived from it
  on every read; no stored "manual count" or "tier" boolean exists (Plan DP's rule).

## Phases

### P0 — Entitlement core (headless, one PR)

`FieldAssistTier.personal`; the two product ids and their evidence; `fieldWork` and
`manualLimit`; `FieldAssistMode`, `Config.fieldAssistUnlocked` / `fieldAssistActive`,
`VaultRegistry.isUnlocked` and `VaultPackAccess` moved onto capabilities; `ManualQuota` and
`ManualSource` as pure types with their tests; `MyManualsPaywallCopy` under the guard; the
`ModesTabPresentation` case. Tests: the capability truth table with personal evidence in every
combination; mode never on for a personal grant; bundled vaults locked, own vaults open, packs
hidden; licence codes never personal; quota verdicts; resolver cases; paywall copy guard; every
existing Field Assist gate test still green (nothing a solo or team holder has changes).

### P1 — The library and the answer (one PR)

The quota at both doors and before a capture; the personal vault created on first addition; the
four manual tools on the resolver; tool-description wording; the on-device set input; Settings ›
My Manuals; the paywall; the first-run hint; the edition rule; the `AIFeatureRegistry` record and
privacy copy. Tests: importer and link-offer refusals with the counts in the message; capture
refused at the limit; forget and remove need neither grant nor quota; a lookup from the library with
Field Assist off, and from the session with it on, with the same vaults loaded; a two-manual answer
names the manual; the on-device set ranks the manual tools with a library and no job; the settings
entry present without `fieldWork`, hidden under an edition; the catalogue guard (strings, no plan
letters in copy).

### P2 — Store and device (owner + one PR)

The `.storekit` products; App Store Connect setup and the listing copy (owner); the sandbox sequence
in §6 on a phone; a device pass: add a PDF from Files, photograph three pages, ask by wake word on
AirPods with the phone in a pocket, ask in CarPlay, "show me" on the bench, a table cell with units;
the upgrade path end to end. Release build before the PR, as always.

## Non-goals

- No AI-generated summaries of a manual, no "chat with your car": the answer is a passage with its
  page, as for a technician.
- No sharing, no sync between phones, no cloud copy of a manual. FS's rule is the product.
- No fetching a manual from a manufacturer's site (Plan IT is organisation-side; a later plan could
  offer the public-copy route to personal customers under IT's rules).
- No mode, no tabs, no jobs, no "my garage" record keeping. A later consumer plan may want a vehicle
  record (Plan AZ exists); it is not this one.
- No pack purchases for personal customers; publishers reach them by link or QR.
- No free tier: the app is paid and the subscription is on top, as for every paid capability.

## Open questions (owner)

1. Family sharing on the personal products? Every product today has it off. Proposal: off, revisit
   if asked.
2. A free trial, as Medical Compliance has? Proposal: yes, one week, since the first manual takes a
   few minutes to index and the value shows only after it.
3. A page cap per manual? A 1,200-page factory service manual indexes slowly on an older phone.
   Proposal: no cap; P1 measures indexing time and storage for a large PDF and the screen says both
   before the import starts.
4. Does a received publisher set count its manuals toward the five? Proposal: yes (this plan assumes
   it); a publisher selling to private owners sizes sets accordingly.
5. Should the Field Assist paywall name the smaller option? Proposal: one line, since Apple shows
   the group anyway in Manage Subscriptions.
6. The entitlement screen's label: "Personal". Confirm.

## Tests (headless)

`FieldAssistCapabilityTests`, `FieldAssistTierTests` (extended), `FieldAssistModeTests` (personal
rows), `ManualQuotaTests`, `ManualSourceTests`, `VaultImporterQuotaTests`,
`VaultLinkOfferQuotaTests`, `ManualCaptureQuotaTests`, `ManualToolsLibraryTests` (lookup, figure,
table, show-source from a library with Field Assist off), `AppleOnDeviceToolSetTests` (library
input), `MyManualsSettingsPresenceTests`, `PaywallCopyGuardTests` (both copies), the existing
`BrandNameGuardTests`, `OutboundFrameConsumerTests` and `TelemetryOptOutGuardTests` unchanged.
