# Plan IP — Organisation Feature Switches (a feature an organisation hasn't taken isn't there)

**Status:** 📝 Drafted 2026-10-16 — nothing implemented.
**Track:** Field Assist (B2B) platform.
**Related:** Plan [CT](CT-org-configuration-profiles.md) (the signed profile, `SettingKey`, ceilings,
`PolicyEnvelope`, `ManagedLockdown`), Plan [FS](FS-subscriber-vaults-and-vault-links.md)
(`FieldAssistCapability`), Plan [HG](HG-add-on-catalogue-and-premium-gating.md) (add-ons entitled by
pack), Plan [EE](EE-field-assist-commercial-licensing.md) (tiers), Plan [IH](IH-van-stock.md)
(`organizationForbidsVanStock`, the first feature to migrate), and the features this round adds:
Plans [IM](IM-experience-recordings.md), [IN](IN-verifiable-code-lookup.md) and
[IO](IO-sealed-proof-of-work-photos.md).
**Origin:** The owner, 2026-10-16, while adding an electrical regulations feature alongside the HVAC
and appliance work: "individual features per organisation, so where they don't need [it], it's not
available." An HVAC firm should not see code lookup, and an electrical contractor should not be
asked about van stock if they don't run vans that way.

---

## Outcome

An organisation's signed profile lists the Field Assist features it uses. A feature that is not
listed is absent on that organisation's phones: no tool registered, no Job-tab section, no settings
row, no line in the system prompt, and no question at job close. A feature that is listed is
offered, provided the licence entitles it. A phone with no organisation profile (a solo technician)
gets each feature's solo default. Adding a feature to the app means adding one case to one
registry, and a guard test fails if its tools or surfaces escape it.

## Verified starting point (`main` @ `8d0266ae0`, 2026-10-16)

- **Profiles can only subtract, and only one way per key.** `SettingKey` is an explicit allow-list.
  Each case has a kind: `.profileOwned`, `.ceiling(pinnedTo: true)` (tighten only, such as
  `organizationForbidsVanStock`, `organizationRequiresCustomerSignOff` and `privacyFilterEnabled`),
  `.ceiling(pinnedTo: false)` (such as `agentModeEnabled`, `faceRecognitionEnabled` and
  `teamLearningReviewerDevice`) and `.startingValue` (written once, then the person's). A ceiling in
  the wrong direction is a named drop (`.wrongDirection`). `PolicyEnvelope` clamps on read.
- **Every feature switch today is an opt-out.** `organizationForbidsVanStock` defaults to allowed,
  and its consumers (`JobTab`, `VanStockTool`, `VanStockImportService`, `FieldSessionService`) each
  read `Config.organizationForbidsVanStock`. No profile can say "this organisation uses only these
  features".
- **Lockdown can close tools and settings.** `ManagedLockdown`'s `closedTools` clamps
  `Config.disabledTools` through `SettingsLockPolicy.effectiveDisabledTools`, `SettingsCategoryID`
  categories lock or open, and `EditionPresentation` hides tabs. These are the right mechanisms;
  what is missing is a feature-level name that drives them.
- **Entitlement is a separate axis.** `FieldAssistCapability` (`bundledVaults`, `ownVaults`,
  `auditedExport`, `orgConfiguration`, `everyVaultPack`, `teamLearnings`) comes from licence and
  StoreKit evidence. The licence payload's `packs` claim entitles vault packs. HG's add-on catalogue
  (entitlement by pack) is drafted and unbuilt.
- **CT's standing decisions apply.** The vendor's key signs profiles, ceilings subtract, the clamp
  is on the read side, and keys are deny-by-default (the 2026-09-23 decisions).

## The model: may, uses, and the person

Three layers, each answering a different question, combined in one pure function:

1. **May**: the licence or StoreKit entitlement (`FieldAssistCapability`, plus a licence `features`
   claim for anything sold as an add-on). If the organisation hasn't bought it, it isn't there,
   whatever the profile says.
2. **Uses**: the profile's `features` list. If the organisation hasn't chosen it, it isn't there.
   With no profile, the feature's solo default applies.
3. **The person**: where a feature has a personal switch (van stock, team learnings capture), the
   technician can turn it off but never on past layers 1 and 2.

`OrgFeatureAvailability.resolve(feature, entitlement:, profile:, personal:)` returns `available`,
`notInLicence`, `notChosenByOrganisation`, `offByYou` or `unavailableHere` (HIPAA, or excluded from the
technician app). Every surface asks this one function.

## Decisions proposed (owner to confirm)

1. **A profile that lists features is deny-by-default for Field Assist features; a profile that
   doesn't list them changes nothing.** Every profile issued today keeps its behaviour, and a new
   profile that says `features: [jobs, vaults, debrief, codeLookup]` gets exactly those. That is
   CT's deny-by-default rule applied to a new key.
2. **Core features can't be switched off.** Jobs, the vault and manuals, citations and the debrief
   are the product. The registry marks them `core`, and a profile that omits them still gets them.
   Switchable at launch: `vanStock`, `teamLearnings`, `experienceRecordings` (IM),
   `codeLookup` (IN), `proofPhotos` (IO), `jobRecording` (HE), `officeConnection`, `instantReplay`
   ([IJ](IJ-instant-replay.md)).
3. **Some features can be required, not just allowed.** `proofPhotos` may be `required` (every job
   asks for an as-left photo at close), and so may `customerSignOff`, which subsumes today's
   `organizationRequiresCustomerSignOff` key. That makes each switch `off | on | required` where
   the feature defines `required`.
4. **Existing keys migrate and are kept.** `organizationForbidsVanStock: true` reads as
   `vanStock: off`, and the old key stays readable for profiles already issued. A profile carrying
   both, disagreeing, is a named drop in favour of the stricter.
5. **Solo defaults.** No profile: van stock on, team learnings off (they need a reviewer),
   experience recordings off, code lookup on (a solo electrician is exactly the partner's
   electrician), proof photos on (offered, never required).

## Phases (one PR each)

### P0 — The registry and the resolver (pure)

- `OrgFeature` (enum): each case declares `isCore`, `allowsRequired`, `soloDefault`, its
  `entitlement` (a capability or a licence feature name), and its **surfaces**: tool names, Job-tab
  sections, `SettingsCategoryID`s or rows, close-of-job questions and prompt sections.
- `OrgFeatureAvailability.resolve` as above, and `ConfigProfile.features: [String: FeatureSwitch]`,
  decoded deny-by-default, with an unknown feature name recorded as a named drop (an older phone
  reading a newer profile).
- `LicenseService.LicensePayload.features: [String]?` for add-ons sold by licence (code lookup, if
  priced; IN open question 3).
- **Exit tests:** the resolution table (every layer combination); old profiles unchanged; the van
  stock key migration; disagreement drops; and unknown names.

### P1 — Every surface asks it

- Tool registration: `NativeToolRegistry`'s Field Assist block registers a feature's tools only when
  it is available, and `ToolAuthorizationPolicy` refuses a call by name if one arrives anyway. The
  prompt builder includes a feature's section only when available. The Job tab, Settings and the
  close-of-job flow hide what isn't available. The four `organizationForbidsVanStock` readers move
  to the resolver.
- `OrgFeatureSurfaceGuardTests`: every tool registered in the Field Assist block either belongs to a
  core feature or is listed by exactly one `OrgFeature`. A tool name in a surface list that is not
  registered fails, so a feature can't leak out of its switch as it grows.
- Settings › Field Assist shows "Your organisation uses: …" (read-only on a managed phone), and the
  support report lists the resolved features.
- **Exit tests:** for each switchable feature, a profile without it leaves its tools unregistered,
  its prompt section absent and its Job-tab section hidden. The guard test passes and fails on a
  planted stray tool.

### P2 — Required features, and the office's view

- `required` for `proofPhotos` (IO P1's close question) and `customerSignOff` (migrating the
  existing key).
- The profile authoring in Avenkin Office (private) gains the feature checklist. This repo gets the
  contract change in `Contracts/` with fixtures, so the office's encoder and the phone's decoder
  agree.
- **Exit tests:** contract fixtures; a required proof photo blocks the close until taken or
  explicitly declined with a reason that is recorded.

## Acceptance

- An HVAC firm's profile without `codeLookup` gives phones on which no code lookup tool, setting or
  prompt line exists. An electrical contractor's profile with it, on a licence that includes it,
  gives phones on which it works.
- Every profile already issued behaves exactly as before.
- Adding IM, IN or IO to the app adds one `OrgFeature` case each, and the guard test proves nothing
  of theirs is reachable when switched off.

## Open questions for the owner

1. Decision 2: is the core set right? Should the debrief be switchable for firms that don't want
   voice summaries?
2. Is code lookup sold as an add-on (licence `features` claim) or included in a tier? It changes
   only the entitlement column in P0.
3. Should a partner (a reseller issuing codes under Plan EI) be able to set an organisation's
   features, or only the vendor?
