# JK — My Manuals: review and build preparation

> **Owner revision — 2026-10-25:** My Manuals and Field Assist are separate services, with
> separate subscriptions and access. My Manuals grants `personalManuals`; Field Assist grants
> `fieldWork`/`ownVaults` and retains its own manual management. A Field Assist subscriber normally
> uses that service's manuals and does not need Personal. Holding both is supported; neither
> unlocks the other, and their expiry and quotas are independent. The local StoreKit fixture now
> uses a separate `my_manuals` group, with monthly/annual at the same level. Personal library
> documents and publisher projections are excluded from professional vault selection and quota.
> This supersedes the original shared-group upgrade/downgrade ladder described below.
> The My Manuals page exposes Upload before purchase and opens native in-app plans; the
> preparation placeholder, external subscription-management button, fixed headline capacity and
> Field Assist redirect/upsell have been removed. Current capacity is in the purchase sheet's
> Plan limits disclosure. Live App Store Connect setup and sandbox qualification remain open.


**Reviewed:** 2026-10-25 against checkout `04f95ff15` and the working tree.
**Readiness:** P0 and P1 phone code is implemented in the working tree. Validation and device/store
qualification are in progress. Purchase offers remain disabled. The supplied workshop pair has
7,595 and 466 pages. A five-slot 9,459-page phone run completed; provisional ceilings are
8,000 per manual / 10,000 total, pending older-device qualification. See the [implementation and measurement
report](../../reports/my-manuals-build-2026-10-25.md) for current evidence and remaining acceptance.
**Product plan:** [JK — My Manuals](JK-my-manuals.md). This document supplies the implementation
contracts and smaller build steps for that plan.

**Existing photographed-manual implementation:** [Plan IF](IF-photographed-manuals.md) P0–P5
phone code is already implemented, including scanning, durable redacted OCR, recovery, retrieval
and page viewing. Physical-device and live Office/pilot qualification remain outstanding. JK
extends that implementation to a personal library without a field job and adds quota admission;
it does not rebuild photographed manuals.

## Decisions recorded

The owner confirmed on 2026-10-25:

- Family sharing stays off.
- Offer a one-week introductory trial to eligible subscribers.
- Every document in a publisher set counts toward the five-manual allowance.
- Each paywall names the other tier.
- The entitlement label is **Personal**; the product is **My Manuals**.
- Choose page limits **after measuring representative large manuals**. The previous 2,500 / 6,000
  figures are benchmark candidates, not agreed limits or values to put in production code.

Previously settled: five manuals, monthly and annual subscriptions, `personal` below `solo`,
same subscription group as Field Assist, prices only in store configuration and off-repo.

## Review findings and required changes

| Priority | Finding in the current code | Build requirement |
|---|---|---|
| P1 | [NativeToolRegistry](../../OpenGlasses/Sources/Services/NativeTools/NativeToolRegistry.swift) registers all four manual tools inside `if Config.fieldAssistActive`. Changing their execute guards alone leaves them unreachable. | Register the library tools separately; refresh registration and provider exposure when entitlement, library contents or mode changes. Retain execution-time checks. |
| P1 | [CapturedManualCatalog.mayUse / eligible](../../OpenGlasses/Sources/Services/FieldAssist/CapturedManual/CapturedManualCatalog.swift) require Field Assist and a session. [ManualCaptureService.start](../../OpenGlasses/Sources/Services/FieldAssist/CapturedManual/ManualCaptureService.swift) refuses without a job. [The v1 contract](../../OpenGlasses/Sources/Services/FieldAssist/CapturedManual/CapturedManualContract.swift) requires a session ID. | Add an explicit personal capture context. Reuse the scanner, redaction and extraction work; do not create a hidden field job or relax the organisation capture contract. |
| P1 | The draft resolver falls through to a personal library when Field Assist is active but its vault is unavailable. Hiding Settings under an edition does not protect tool execution. | Field mode and restricted editions resolve exclusively to their authorised session, or a refusal. Medical restrictions run before library selection. Never fall back to personal content in those contexts. |
| P1 | [VaultDocumentLedger](../../OpenGlasses/Sources/Services/Vault/VaultDocumentLedger.swift) has no total physical page count. Its convenience load treats an unreadable ledger as empty; photographed captures also live outside that ledger. | Inventory admitted manuals and pending additions, including captures. Persist measured page metadata, derive totals, and treat unknown/corrupt inventory as unavailable for admission rather than zero. |
| P1 | [VaultImporter.installReporting](../../OpenGlasses/Sources/Services/Vault/VaultImporter.swift) copies files before async `syncDocuments` applies its entitlement guard. A quota checked only at `toIngest` can leave installed files behind. [VaultLinkInstaller](../../OpenGlasses/Sources/Services/Vault/VaultLinkInstaller.swift) serialises one vault at a time. | Authorise and reserve capacity before durable installation; one library-wide coordinator covers every admission route and concurrent additions to different vaults. Recheck at commit. |
| P1 | [VaultLinkService.FetchOffer](../../OpenGlasses/Sources/Services/Vault/VaultLinkService.swift) knows a host and byte ceiling; it has no manifest or page counts before download. | Apply exact quota and publisher eligibility at downloaded review and again at commit. The initial network consent screen can describe the allowance but cannot promise counts it has not measured. |
| P1 | [ManualLookupTool](../../OpenGlasses/Sources/Services/NativeTools/ManualLookupTool.swift), [ManualFigureTool](../../OpenGlasses/Sources/Services/NativeTools/ManualFigureTool.swift), [TableLookupTool](../../OpenGlasses/Sources/Services/NativeTools/TableLookupTool.swift) and [ShowSourceTool](../../OpenGlasses/Sources/Services/NativeTools/ShowSourceTool.swift) call session-owned retrieval, scope, citation, table and presentation functions throughout. | Extract a shared manual context and page-resolution adapter, rather than replacing two guards and keeping the session as hidden authority. Keep the session adapter for existing Field Assist behaviour. |
| P1 | [AnswerSourceMemory](../../OpenGlasses/Sources/Services/FieldAssist/ShowSource.swift) scopes memory by optional session ID and resolves table citations using title/page. A library has no job and may contain duplicate titles or unrelated machines. | Give library citations a conversation/source scope and stable vault/document/revision identity. Resolve ambiguity explicitly; never choose a book by title or page alone. Revalidate access when reopening a source. |
| P2 | [StoreKitService](../../OpenGlasses/Sources/Services/StoreKitService.swift) separately filters recognised entitlement IDs, sale catalogue IDs, subscription IDs and renewal state. [Entitlement status](../../OpenGlasses/Sources/Services/Entitlement/FieldAssistEntitlementStatus.swift) labels only the existing Field Assist subscriptions as subscriptions. | Add personal products to every relevant recognition and status path. Register evidence in P0 but expose purchases only once personal workflows work. Distinguish renewal dates from expected loss of access. |
| P2 | The local [StoreKit configuration](../../OpenGlasses/MedicalCompliance.storekit) has Field Assist monthly only, although code recognises annual. | Reconcile the professional pair as well as adding the personal pair. Exercise all four products and their levels locally, then check the actual App Store Connect group. |
| P2 | [ManualFigureAttachment](../../OpenGlasses/Sources/Services/FieldAssist/ManualFigure.swift) can attach a rendered manual page to a cloud-model turn through [LLMService](../../OpenGlasses/Sources/Services/LLMService.swift). | Privacy copy must cover selected passages **and page images** sent to the chosen model. “Never leaves the phone” cannot describe every answering path. Retain the no-sharing/no-full-manual-export rules. |

P1 denotes a correctness issue to resolve before making the feature usable; P2 denotes integration
and release work. These are review findings about the proposed build, not claims of new live bugs.

## Implementation contracts

### Entitlement and access

- Add personal product IDs to the verified purchase recorder's recognised family, without putting
  them in the professional subscription set. Maintain separate offer sets and renewal state.
- Personal products grant exactly `ownVaults`. Professional subscriptions grant `fieldWork`,
  `bundledVaults`, `ownVaults`; the retired unlock grants `fieldWork`, `bundledVaults`. Existing
  licence grants gain `fieldWork`; keep the licence service's team floor, including a code that
  claims `personal`. Do not grant `fieldWork` to an unknown product by default.
- Derive `ManualLimits` from **all live evidence**, not the winning tier alone: personal-only has
  five slots and measured page limits; any live unlimited `ownVaults` grant lifts those limits.
  A legacy unlock beside personal enables field work but does not lift the personal manual quota.
- Update `Config.fieldAssistUnlocked`, mode inputs, bundled vaults, pack access, catalogue rows,
  settings and job/tool gates consistently. Search production uses of `isGranted` and tier switches;
  each use must mean either any entitlement, or the specific capability it actually needs.
- A vanished grant denies the next read and invalidates staged pages/source references. Remove
  remains available. Keep files through lapse, downgrade and revocation; existing erasure still works.
- Reconcile the existing `ownVaultsLapsed` copy (“stay readable”) with the registry's access gate and
  JK's intended lapse behaviour before reusing that copy for My Manuals.

### Library inventory and admission

Use stable `(vaultID, document identity)` records for installed manuals and a request identity for
staged additions. Content hash identifies a revision, not a new slot. An explicitly confirmed
replacement of a manual replaces that identity; a new manual with the same title does not.

Count documents held, not indexed chunks: an admitted manual still counts while indexing, after
indexing fails, or when every page is a drawing. Count local photographed manuals as well. A
reviewed/replaced copy of the same capture must not consume two slots. Persist per-document page
metadata in the existing inventory/ledger or capture records; do not persist an entitlement or
an independently mutable total count.

The pure quota consumes a proposed **transition** (held, replaced/removed, additions), not merely
`toIngest.count`. No-op reindexing and same-content retry consume no new capacity. A downgrade may
leave the library over a limit: retain reading while `ownVaults` is live, allow removal and
non-growing retries, and reject additions or growth that violates the current limits. Refuse a
publisher set as a whole; quota refusal must leave the current library intact.

One coordinator makes admission serial across Files, links and capture. Reserve a slot before
opening a new capture; check measured pages when the scan returns and before commit. Reserve
downloaded/selected additions before indexing yields, so simultaneous imports cannot both claim
the last slot. Represent pending admission in protected staging/inventory metadata, recover or
release it after cancellation/failure/relaunch, and retain no reservation for abandoned camera UI.
Set one lock order (library admission before per-vault mutation); never hold a lock throughout OCR.

Preflight each personal PDF off the main actor: physical page count, readability/encryption, file
size and available space. Do not derive page counts from text chunks or the highest indexed page.
Measure original/source PDFs when the searchable representation is extracted text. If a received
document has no independently measurable page representation, do not treat its page count as zero:
refuse personal admission with an explanation until support is defined. Existing legacy manuals
remain readable while metadata is repaired; unknown totals block additions, not removal.

### Publisher sets and downgraded vaults

Verify the unmodified archive, publisher status and reviewed digest first. Then derive a
manual-only installation/read projection for a personal user. Keep trust provenance tied to the
verified original; do not label rewritten bytes as the publisher's signed archive. The projection
contains document content and source-page mapping, without core prompt files, scenarios,
procedures, site data, edition/rule-chain behaviour or prompt rules. Any schema metadata retained
solely for mapping a source page must not activate a professional feature.

Apply the same read projection to professional imports already held after a downgrade. Admission
restrictions alone do not stop an old manifest's prompt rules or procedures reaching the assistant.
Use actual registry access and organisation ownership/lease/departure checks to choose personal
sources; `ownVaults` must never reopen an organisation's withdrawn manuals. Installation may use
an internal app-generated manifest; user-supplied manifest import remains a professional door.

### Source selection, answering and “show me”

Resolve descriptors in a pure policy, then load authorised stores in the adapter:

1. Apply the existing medical/privacy restrictions. A personal manual library does not add a
   source to a medical context.
2. If a restricted organisation edition is in force, or Field Assist mode is active, use only the
   authorised active session vault. Without one, return a session-specific refusal.
3. Otherwise require live `ownVaults`, select eligible personal manuals, and use their manual-only
   projection. Return a precise empty/indexing/lapsed/storage-unavailable reason as appropriate.

Carry the resolved context through the whole lookup, table, figure and page-opening path. Preserve
namespaces and vault/document/revision identities in merged retrieval and citation resolution.
When multiple manuals concern different machines, ask which one if the question or a title filter
does not establish the source. Duplicate titles require disambiguation; equal page numbers do not
resolve it. Never blend conflicting service values into one answer. Preserve existing evidence
thresholds, insufficient-information replies and pictured-table uncertainty rules.

Library `use_camera` is rejected before acquiring a frame. A missing or empty query asks what to
look up; it must not trigger ManualLookupTool's implicit camera fallback. Ordinary camera features
elsewhere in the app keep their existing policies; this is a restriction on the manual lookup.

Provide a library source-memory scope based on the active conversation and source revision set;
reset it on conversation reset/source switch and invalidate affected entries on replacement,
removal, lapse or policy changes. Retain document identity through the model's citation text.
Revalidate scope when opening a page and when attaching its image to another turn. Preserve
locked-phone, CarPlay and actual-on-screen reporting behaviour. Exercise Direct, Gemini Live,
OpenAI Realtime and supported local-model tool routes.

### Personal photographed manuals

Recommended boundary: a library capture request holds a personal-library destination and an
admission token, independent of `FieldSession`. Reuse the phone scanner and local redaction/OCR
components and commit a generated PDF plus its extraction/page metadata as one managed personal
manual. Preserve local capture provenance and deletion linkage. The existing v1 IF job/Office
contract and organisation outbox remain job-scoped; no fabricated session ID and no Office upload
for a library capture. Any additional durable capture metadata joins `DataStoreRegistry` and
subject erasure. Test switching jobs while a personal scan is open and switching modes before
its OCR completes.

## Build sequence and exit checks

### P0 — Evidence and capability boundary

Change entitlement types/evaluator inputs, product recognition, capability gates, pack gates,
mode presentation and pure source/quota policies. Extend `FieldAssistCapabilityTests`,
`FieldAssistTierTests`, `FieldAssistEntitlementTests`, `FieldAssistModeTests`, `VaultPackTests`
and `StoreKitRecoveryTests`; add pure quota/source tests. Cover lapsed and mixed evidence,
personal + legacy, personal + team, restore, revocation and unknown product IDs. Preserve existing
solo/team/enterprise access. Keep personal offers unavailable until P1 is complete.

**Exit:** evidence grants the right capabilities; personal never enables Field Assist mode;
recognised personal transactions survive refresh/restore; page limits are injectable in tests.

### P1a — Inventory, measurement and Files admission

Add inventory page metadata/migration, staging reservations and the library admission coordinator.
Implement single-PDF admission with editable title, background extraction and honest progress.
Gate folder import at its service entry point as well as the picker. Extend removal/retry/relaunch
coverage; test two concurrent additions with one free slot, replacements at five slots, over-limit
downgrades, protected-storage failure and an interrupted import.

Run the measurement protocol below and select the page limits before accepting P1a.

**Exit:** a personal customer can add/remove/retry a PDF without a job; the sixth manual is refused
before durable install; no corrupt or pending inventory permits an extra slot.

### P1b — Retrieval, tool exposure and citations

Extract the manual context/adapters; register and expose the four library tools; update Apple
on-device priority input and tool descriptions. Preserve JD's exclusion of `manual_lookup` from
Apple's small on-device tool set and explain that route's limitation in product copy. Do not
promise that every selected model can answer the full manual workflow.

**Exit:** library lookup/table/figure/show-source work with Field Assist off; manual identity
survives multiple vaults and duplicate titles; policy changes deny stale references; an active or
restricted field context never falls through to personal sources. Existing field retrieval,
equipment/edition handling and uncertainty tests remain green.

### P1c — Links and camera admission

Integrate verified review/commit quotas and the manual-only projection, including downgrade reads.
Add personal capture without changing the job contract. Extend `VaultLinkServiceTests`,
`VaultLinkNoShareTests`, captured-manual access/recovery/removal tests and new admission tests.

**Exit:** unverified personal archives are refused; a signed set is admitted whole or rejected;
professional metadata never affects personal answers; capture counts/reservations recover;
personal captures never enter an organisation outbox.

### P1d — Settings, paywalls and lifecycle

Add Settings › My Manuals, usage/source/indexing state, Files/camera/QR actions, deletion, first-run
hint and product/status copy. Use catalogue presence rules for editions. Localise and test
VoiceOver/Dynamic Type. Include the selected-model disclosure for text and page images in
`AIFeatureRegistry` and the library. Show renewal and trial status from StoreKit; a renewing
monthly subscription should not always look as though it is about to be lost.

**Exit:** complete phone-only journey, no personal-facing “vault” or job language, editions hide
the personal entry, restoration updates surfaces and tools, and all copy guards pass.

### P2 — Store fixtures, sandbox, device and release

Configure both personal products and the professional monthly/annual pair in the local StoreKit
file. Personal monthly/annual share one level below the professional pair. Apple ranks the highest
service level as 1; the two durations of each tier have equal content and belong at the same level.
The one-week trial is conditional on eligibility across the entire subscription group; using a
My Manuals trial does not create another introductory-trial entitlement on upgrade. See
[Apple subscription levels](https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/)
and [introductory offers](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/)
(checked 2026-10-25).

Owner sets the actual products, levels, introductory offers, availability and figures in App
Store Connect. Use StoreKit's verified effective entitlement at upgrade/downgrade, not the user's
requested next product. Test pending/cancelled purchases, restore on a fresh install, both
durations, trial eligibility, renewals, revocation, lapse and resubscription. Keep EE's unresolved
billing-grace decision visible; do not imply JK implemented grace by comparing an expiry date.

Run buy → five imports → sixth refused → upgrade → sixth admitted → downgrade takes effect → all
six readable/seventh refused → lapse → reads denied/files retained → resubscribe → reading
resumes. Device acceptance includes Files, a scan, a signed set, AirPods pocket use, supported
glasses, CarPlay's page restrictions, “show me” on the bench and a table value with units.

**Exit:** selected regressions and required CI pass, Release builds with the repo's XcodeGen
configuration, and sandbox/device evidence is recorded. Do not label fixture success as device
acceptance or store availability.

## Large-manual measurement protocol

The tracked PDFs found during this review are guides and a capture fixture; they are not a
representative collection of large factory/workshop manuals. No page limit or indexing-time
estimate was established by this review.

Use privately held representative originals: a large text-layer factory service manual, a large
scanned workshop manual, a diagram/table-heavy manual, and a five-manual mixed library. Keep
copyrighted source PDFs out of commits. Record anonymous fixture IDs, page/file sizes and device
specifications alongside the results.

On the oldest supported target phone and a current phone, record cold import wall time, OCR and
embedding time separately, peak memory, thermal state, baseline/index storage, free-space needed,
cancel/resume time, app restart recovery and lookup latency/accuracy after import. Exercise blank
and drawing-only pages. Use synthetic boundary PDFs only to verify exact quota thresholds;
they cannot establish real OCR or retrieval performance. Show actual bytes/pages and indexing
state before import; display a time estimate only after measurements justify one.

Choose the per-manual and total page limits from the largest intended consumer books and the
measured device envelope, then record the chosen values and rationale in JK. Five slots remains
fixed. Measurements and the final page-cap choice gate P1a, not starting P0.

## Validation and handoff state

This preparation changes documentation only. Source findings were checked against the files
linked above; Xcode 27.2 and XcodeGen are installed. The root `Package.swift` is not the app's
authoritative build graph: use [BUILDING](../BUILDING.md), `project.base.yml`, the project
generation script and `ci_scripts/Package.resolved`. Run app tests through the generated Xcode
project as [.github/workflows/tests.yml](../../.github/workflows/tests.yml) does.

The working tree already contains unrelated app changes, including tool registration/exposure,
Apple on-device tools, LLMService and localisation, which P1 will touch. Integrate against their
current contents; do not reset them or copy an older version over them. No branch, commit, app
build, app test run or App Store Connect change is claimed by this preparation.


Owner follow-up (build 567): Upload manual groups file selection and publisher links/codes.
Files can be selected and previewed before subscribing; save/index remains behind Personal access.
The standalone Receive row is removed. Only monthly is currently offered; annual restore remains.
The local native StoreKit app-host probe confirms the product, separate group and one-week offer.
Live App Store Connect metadata and review acceptance remain separate from that fixture check.
