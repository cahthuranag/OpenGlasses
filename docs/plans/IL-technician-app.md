# Plan IL — The Technician App (a free download, unlocked by the organisation's licence)

**Status:** 📝 Drafted 2026-10-16 — nothing implemented. The product name is not chosen yet (see
"Name").
**Track:** Field Assist (B2B) distribution.
**Depends on:** Plan [IK](IK-store-build-without-glasses-sdk.md) P0–P2 (the build without the
glasses SDK; this app ships that variant until Meta approves the release channel).
**Related:** Plan [CT](CT-org-configuration-profiles.md) (the Field Assist edition inside the main
app, which is the runtime shape this app fixes in place), Plan
[EE](EE-field-assist-commercial-licensing.md) (tiers and Guideline 3.1.3(c)), Plan
[EI](EI-licence-issuance-portal.md) (a partner issues codes), Plan
[FR](FR-fictional-example-vault.md) (the fictional vault a reviewer or a prospect can try), Plan
[FY](FY-rename-to-avenkin.md) (the listing, and why a bundle id is permanent), Plan
[IP](IP-organisation-feature-switches.md) (what an organisation has switched on).
**Origin:** The owner and a partner, 2026-10-16. The paid consumer app on the store is the wrong
front door for a service company: a technician should not pay for an app their employer licenses,
and the consumer features (music, home, health, chat personas) are noise on a work phone. The
owner proposed splitting Field Assist into its own app that is free to download and does nothing
commercial without an organisation's licence code. The partner agreed, and wants a standard App
Store install for the larger customer rollout.

---

## Outcome

A second app on the store, "[Product] by Avenkin":

- **Free to download, no in-app purchase.** A technician installs it, scans the organisation's
  setup QR or enters the licence code, and is working. The organisation is invoiced outside the
  store, which Guideline 3.1.3(c) permits for services sold directly to organisations for their
  people.
- **Field Assist only.** The Job tab, Modes, vaults and manuals, procedures, the debrief, van
  stock, team learnings, the office connection, CarPlay jobs and the watch. No Chat tab, personas,
  music, home, health or fitness, and no Medical Compliance.
- **Something to try before a licence.** With no code it opens the fictional example vault (Plan
  FR) in a demo job. A prospect, or an App Reviewer, can ask it a question about an invented furnace
  with their phone and earbuds, which is what the partner's customers will want to do first.
- **The same engine.** One source tree, the same tests. The technician app is a second target with
  its own `Info.plist`, entitlements, icon and compile condition. It is not a fork.

The main app keeps Field Assist too, including the StoreKit solo tier for an individual technician
who buys for themselves. Nothing is taken out of it.

## Verified starting point (`main` @ `8d0266ae0`, 2026-10-16)

- **The edition already exists at runtime.** CT 3b's `edition: "fieldAssist"`
  (`EditionPresentation`) hides the Chat tab and the model dock tile, and `ManagedLockdown`
  closes settings categories and tools. A CT profile turns it on. This app fixes it on in the binary.
- **Field Assist has two kinds of evidence.** `LicenseService` verifies an Ed25519 code (`tier`
  team or enterprise, `plan`, `seats` (not enforced), `packs`, `profile`, `organizationID`).
  `StoreKitService` grants the solo tier from `field_assist_monthly`/`field_assist_annual` and the
  retired non-consumable. `FieldAssistEntitlementEvaluator` and `FieldAssistCapability` decide from
  both. `Config.fieldAssistUnlocked` reads the result.
- **One target pulls everything.** The app target compiles `OpenGlasses/Sources` wholesale.
  `OpenGlassesApp.swift` is about 8,200 lines and `Config.swift` over 4,400. Excluding features by
  target membership alone is not practical. Exclusion has to be by condition at the registration
  points (tools, tabs, settings categories, services started at launch) plus by path for files
  that reference a framework the app must not link.
- **One plist, on purpose.** There is a single committed `OpenGlasses/Info.plist`. Per-target plist
  overrides were removed after ITMS-90683 (`project.base.yml`, `project.local.yml.example`). A
  second app needs its own committed plist, not an override.
- **Everything shares the app's ids.** The App Group `group.com.openglasses.app`, the watch's
  `WK_COMPANION_APP_BUNDLE_IDENTIFIER`, the widget and share-extension ids, the scheme, the StoreKit
  configuration and the test host all name `OpenGlasses`.
- **No brand constant.** "Avenkin" is in both plists, the specs, about 1,200 catalogue lines,
  `AssistantIdentity.defaultName`, `MainTab`, `LaunchScreen`, `OnboardingView`, the wake phrase, App
  Intent phrases and two HTTP headers. "Field Assist" is in about 390 Swift string lines and 350
  catalogue lines, plus `FieldAssistPaywallCopy.poweredBy`. `RegistrationFlow.appName` is the only
  name read from `CFBundleDisplayName` at runtime.

## Decisions proposed (owner to confirm)

1. **The technician app sells nothing.** It has no StoreKit code in the binary (`#if
   !AVENKIN_TECHNICIAN_APP` around `StoreKitService`, the paywalls, the vault-pack purchase rows and
   the StoreKit configuration). A solo technician who wants to buy for themselves uses the main app.
   Mixing an in-app purchase into a licence-unlocked business app invites the steering question
   Plan EE took care to avoid, and it doubles the review surface.
2. **The bundle id is name-neutral and permanent.** `com.avenkin.field` (a proposal), never the
   product name, because the name is still being chosen and a bundle id can never change (Plan FY).
   The display name, icon and listing carry the product name.
3. **Its own App Group, no shared data with the main app.** `group.com.avenkin.field`. A technician
   who has both apps has two separate sets of jobs. Sharing an App Group across two products would
   tie their release trains together, and an organisation's data should not sit inside a consumer
   app's container.
4. **Demo mode is the fictional vault, read-only.** No licence: one bundled fictional vault, a demo
   job that is never sent anywhere, no office connection, no team learnings, no van stock. The
   reviewer note gives a demo licence code for everything else.
5. **The glasses arrive with Meta's approval, as in the main app.** The technician app ships IK's
   store variant. When the release channel is approved it gets the SDK the same way the main app
   does, and its own Meta app registration.
6. **The watch comes in P3, not at launch.** Its companion id is tied to the host app. The first
   release has no watch app, and a second watch target follows once the first review has passed.

## Name

The partner is checking product names for conflicts in the US and Canada and will send options;
"Field Assist" is already used by another company in the field-service market. Structure: "[Product]
by Avenkin". The product name says what it does for HVAC, electrical and appliance technicians, and
Avenkin stays the parent brand. The store name field allows 30 characters, so "[Product] by Avenkin"
leaves 18 for the product name. **Nothing in P0–P2 needs the name.** The target is called
`AvenkinField` in the specs and `BrandName.product` reads a placeholder until it is chosen. P3 sets
the display name, icon and listing.

Inside both apps the feature keeps the words "Field Assist" until the name is chosen. P1's
`BrandName` makes the later rename a one-constant change for the Swift literals. The catalogue keys
that interpolate it are renamed with it, through the order-preserving catalogue edit (the
xcstrings scripted-edit rules).

## Phases (one PR each)

### P0 — Inventory and the brand constant (no new target yet)

- A checked-in inventory, `docs/plans/IL-exclusion-inventory.md`, lists every file and registration
  point by what the technician app drops: StoreKit; HealthKit, HomeKit, MusicKit and WeatherKit
  users; consumer tools (`NativeToolRegistry` registrations outside the Field Assist block);
  consumer tabs and settings categories; launch-time services that touch a dropped framework.
  For each it gives the mechanism: path exclusion, `#if`, or "kept". A guard test,
  `TechnicianAppExclusionTests`, reads it and fails on a file that imports a dropped framework but
  is not listed.
- `BrandName` (`Utils/BrandName.swift`): `appName`, `productName` and `poweredBy`, read from the
  bundle with the current literals as defaults. Replace the hard-coded "Avenkin" display literals
  (`AssistantIdentity.defaultName`, `MainTab`, `LaunchScreen`, the onboarding headline,
  `LiveActivityManager`) and `FieldAssistPaywallCopy.poweredBy` with it. The wake phrase, App
  Intent phrases and HTTP user agent stay as they are: they are behaviour, not branding.
- **Exit test:** the main app's UI strings are unchanged (the catalogue diff is empty except for any
  interpolation moved to `BrandName`), and the guard test passes.

### P1 — The second target builds

- `project.technician.yml`, composed when `OPENGLASSES_TECHNICIAN_APP=1` (alongside, not instead of,
  the main app). Target `AvenkinField`: the same sources minus the inventory's path exclusions,
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS: AVENKIN_TECHNICIAN_APP`, its own
  `AvenkinField/Info.plist` (committed; only the usage strings a technician app needs: microphone,
  speech, camera, photos, location for job start and end, Bluetooth for headsets and EVEN, local
  network for the office), its own entitlements (App Group, CarPlay voice) and the IK store
  variant (no glasses SDK).
- `#if AVENKIN_TECHNICIAN_APP` at the registration points: the edition is fixed to
  `.fieldAssist`, `Config.fieldAssistEnabled` is forced on and hidden, consumer tools are not
  registered, the Chat tab and personas do not exist, and Settings shows the Field Assist and
  Devices & Privacy categories only.
- **Exit tests:** both targets build. A technician-target test bundle runs the Field Assist,
  vault, job, office and learnings suites. `nm` on the binary finds no `StoreKit`, `HealthKit`,
  `HomeKit` or `MusicKit` symbol and no `MWDAT` symbol. The main app's suite is unchanged.

### P2 — First run without a licence, and with one

- Onboarding for the technician app: "Set up with my company" (scan the setup QR or enter the
  code, through the existing `LicenseService.activate` and CT enrolment) or "Try it" (the
  fictional vault demo of decision 4). No consumer pages.
- Demo mode: a `DemoEntitlement` that grants `bundledVaults` for the fictional vault only, with
  every send route refused by name ("Demo jobs are not sent anywhere"). It is evidence of its own
  kind in `FieldAssistEntitlementEvaluator`, so a demo can never satisfy a capability check meant
  for a licence.
- A licence that expires drops back to demo mode with the technician's jobs intact and readable.
- **Exit test:** a headless test drives both paths. A demo job cannot be delivered, synced or
  exported to the office. An activated licence opens the organisation's vaults and features
  (through Plan IP's switches once that lands).

### P3 — Name, icon, listing, watch, submission

- The chosen name in `CFBundleDisplayName`, `BrandName.productName`, the icon set, the launch
  screen and the catalogue. The App Store listing, the privacy nutrition label (recomputed:
  smaller than the main app's), the support URL, and review notes with a demo code.
- The watch app as a second watch target tied to the technician app (decision 6), if the first
  review has passed.
- `Scripts/release-dossier.sh` learns the second target.
- **Owed by the owner:** the name (with the partner), the App Store Connect record and App ID with
  its capabilities (a new signed target breaks the archive until they are registered), the
  submission.

## Acceptance

- A technician at a partner's customer installs the app from the store, scans the organisation's
  QR, and runs a job by voice with AirPods without seeing a purchase screen or a consumer feature.
- A prospect with no code asks the demo about the fictional furnace and gets a cited answer, and
  nothing they do leaves the phone.
- Every Field Assist test passes in both targets, and the main app is unchanged for its users.

## Open questions for the owner

1. Decision 1: no in-app purchase at all, so a solo technician is pointed at the main app. Or does
   the technician app also sell the solo subscription?
2. Decision 2: the bundle id.
3. Should an organisation's existing main-app installs be able to move their jobs into the
   technician app (an export and import of the job store), or do they start fresh?
4. Timing against Plan IK: submit the technician app first (free, organisation-driven, the
   partner's rollout) or the paid consumer listing first?
