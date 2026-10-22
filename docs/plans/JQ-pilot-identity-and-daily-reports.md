# Plan JQ — Who Sent It, and Yesterday's Report

**Status:** 📝 Drafted 2026-10-23 — nothing implemented.
**Origin:** the pilot partner, 2026-10-23, before installing the app at several tester companies:
each company should be identifiable from its licence; Settings should hold the technician's full
name, short name and technician ID; the company and the technician should appear on job reports
and on diagnostic reports; a testing switch should send the day's activity report and transcripts
every night at 23:55, retrying when the app is next opened; and earlier days should stay available
to send by hand. Without these, a tester reports a problem the morning after, and *Send Today's
Activity* covers the wrong day.
**Kept from Plan [FV](FV-support-reports.md):** nothing leaves the phone on its own. iOS gives the
app no timed background run, every email goes through the Mail composer (which needs a tap), and an
unattended send would need a server holding customer transcripts. So the nightly send becomes:
**the first time the app is opened after a day with activity, it offers that day's report, ready to
send in one tap to the pilot's addresses.**

## What is there today

- **Licence.** `LicensePayload` (`LicenseService.swift`) carries `licensee`, `issued`, `expires`,
  `tier`, `plan`, `seats` (recorded, not enforced), `reference` and an optional `profile`. A code is
  an offline bearer credential: one code works on any number of phones, and it has **no ID** of its
  own. The licensee is shown only in Settings → Field Assist, onboarding and enrolment.
- **Company.** `Config.organizationDisplayName` (profile-settable), shown on the customer sign-off
  screen only.
- **Technician.** One field, `Config.technicianDisplayName` ("Your name, as your team sees it",
  `SettingKey.technicianDisplayName`, set and locked by a per-person profile), used as the author of
  team learnings and captured manuals. No full name, no technician ID (`JobFileFormat3` echoes an
  office-issued `technician_id` but the phone stores none).
- **Job reports.** The PDF heading is *Field Assist Session Record*, then the vault and an 8-character
  session ID (`SessionExporter.writePDF`). No company, technician or licence anywhere in the PDF,
  the JSON (`SessionExport`) or the email subject.
- **Support reports.** `AppState.supportEnvironment` prints build, channel, iOS, hardware model,
  language, storefront, mode, model, glasses and goal counts. No company, technician or licence.
  The transcript header is *Avenkin — \<title\>*.
- **Earlier days.** Job tab → *Export a day…* offers a transcript or a support report per day, but
  lists only days that had a job (`JobTranscriptExport.days(in:)`), at most 14
  (`JobTabModel.transcriptDayLimit`). A day of conversations with no job cannot be chosen.
- **What a past day's report can hold.** Conversations: kept until deleted. AI turn traces: 14 days.
  Activity trail: 14 days. The app's own events (`DiagnosticRing.defaultMaxAge`): **48 hours**, so a
  report for three days ago says *"None in this period — the app keeps its own events for up to two
  days."*
- **Support recipient.** One address (`Config.supportReportEmail`, `SupportReportRecipient.resolve`).
  An organisation phone never falls back to the developer.

## Licence keys per company (no code)

One key per company is minted today with `Scripts/generate-field-license.swift`: the company as
licensee, `--plan pilot`, a `--reference` naming the pilot, and a short `--days`. The key is still
a bearer credential, so it is not shared across companies. P1 adds what support needs to tell two
installs apart: a **licence fingerprint** (the first 8 hex digits of the SHA-256 of the code). It is
not secret, and it identifies which code a phone runs without printing the code itself.

## P0 — Technician identity (headless core + Settings)

- `TechnicianIdentity` value: `fullName`, `shortName`, `technicianID`. `shortName` **is** today's
  `technicianDisplayName`, with the same key and the same `TechnicianName.clean`, so nothing
  migrates and team learnings keep filing under it.
- Two new settings, both organisation-owned (set and locked by a profile, like
  `technicianDisplayName`): `technicianFullName` (`TechnicianName.clean`) and `technicianID`
  (`TechnicianID.clean`: trimmed, printable, no control characters, at most 40 characters, empty
  means unset).
- Settings → Field Assist → the *job report* section gains *Full name* and *Technician ID* beside
  today's name field (relabelled *Short name*). Locked rows read as locked, as the name does today.
- `ReportIdentity` (pure): built from the company name, the technician identity, the active licence
  (licensee, reference, issued date, fingerprint) and the enrolment ID. It produces the lines P1
  prints. The company comes from `organizationDisplayName`, falling back to the licensee
  (decision 2). A phone with nothing set produces no lines, never placeholders.

## P1 — Stamped on job reports and support reports

- **Job reports.** The identity is **snapshotted onto the `FieldSession` when the job starts**
  (`reportedBy`, optional, decoded with a default). It is not read live, because a PDF a customer
  already holds must re-render byte for byte (`DebriefDocumentPolicy`), and a name changed later
  must not rewrite an old job. The PDF gains one line under its heading: *Company · Technician full
  name*. `SessionExport` gains an optional `reportedBy` with all four fields. The technician ID goes
  to the JSON and the office, and onto the customer PDF only if decision 1 says so.
- **Office-bound records.** The work record sent to the organisation's endpoint and to Avenkin
  Office carries `reportedBy` only after `Contracts/` is amended in the same PR, with golden fixtures,
  as JL P0 did. The office still links each phone to its FSM technician by enrolment (Plan
  [HT](HT-external-job-references.md)). The phone's technician ID is a label the office may show,
  not a join key.
- **Support reports.** The phone section gains `Company:`, `Technician: Full name (short name), ID`,
  `Licence: licensee, plan, reference, issued <date>, fingerprint <8 hex>` and `Enrolment:` lines.
  The transcript header gains a *From* line, so a report forwarded on its own still says whose it
  is. The name is personal data, so the review sheet lists it with the other things the file holds.
  The same reports already go only to the organisation's support address.

## P2 — Any day, and a week of app events

- **Any day with activity.** `JobTranscriptExport.activityDays` (pure) builds the list from jobs,
  conversation lines, turn traces and activity-trail entries, newest first, up to 14 days (the
  trace retention). Each row says what the day has: *3 jobs, 5 conversations*. The Job tab's
  *Export a day…* and a new Settings → Diagnostics & Support → **Send a Day's Activity…** (beside
  *Send Today's Activity*) both open it. A day's scope is already supported, so only the list
  changes.
- **App events for 7 days.** `DiagnosticRing.defaultMaxAge` goes from 48 hours to 7 days. Its
  capacity (2,000 events, which a long day can fill first) goes up with it, **to a size measured on
  a device first**. The ring is loaded at launch, and launch is where iOS's watchdog kills the app,
  so the persisted file's size and load time are measured on the phone, before and after, and the
  numbers are recorded here. Every place that states the period follows from the constant: the
  *"up to two days"* line in `JobTranscriptExport`, the `DataStoreRegistry` retention text, the
  `DiagnosticExportBuilder` notice and the in-app privacy copy, all in the same PR.

## P3 — Yesterday's report, one tap (pilot reports)

- **The switch.** Settings → Diagnostics & Support → **Pilot reports**, off by default. Under it:
  *Send to* (up to three addresses, each checked by `SupportReportRecipient.isPlausible`) and a line
  saying what goes: the day's conversations, jobs, AI turn details and app events, with keys masked.
  A profile may set it on and set the addresses (decision 4). The technician always sees it, and
  can always switch it off.
- **When it asks.** `PilotReportPromptPolicy` (pure) is given now, the days with activity, the days
  already sent and the last prompt. It answers which days to offer:
  - every unsent day before today with activity, up to 7 days back, newest first;
  - at most once per calendar day;
  - never while a job is open, during a live voice session, or on CarPlay;
  - nothing when the switch is off.

  It runs when the app becomes active (`scenePhase == .active`).
- **What it shows.** A card: *Yesterday's report is ready — Send*, plus *Not now*. *Send* opens the
  existing review sheet on that day's scope with *conversations outside jobs* on and the pilot
  addresses in the composer's *To* (the composer takes several). Two or more unsent days are offered
  as a list, one send each, so no single attachment grows past what Mail will take.
- **What counts as sent.** The Mail composer returns `.sent`, or the share sheet completes with an
  activity. A cancelled send stays unsent and is offered again the next day. *Not now* waits for the
  next calendar day. A day older than 7 days drops off the offer and stays under *Send a Day's
  Activity…* until its traces expire.
- **Optional reminder.** A local notification at a set time (`UNCalendarNotificationTrigger`, no
  background run needed) saying *"Today's report is ready to send"*. Tapping it opens the same
  sheet. Off unless decision 3 sets a time.
- Leaving the organisation clears the pilot addresses and the sent-day record with the rest of its
  settings. Neither is a new store of content, only addresses and dates (`DataStoreRegistry` entry).

## Decisions owed

1. **Technician ID on the customer's PDF?** Proposed: no. The name and company go on it, and the ID
   goes to the JSON, the office and support reports.
2. **Company name when the profile and the licence disagree.** Proposed: the profile's
   `organizationDisplayName`, with the licensee on its own `Licence:` line in support reports.
3. **Reminder notification time.** Proposed: none by default. The prompt on first open covers it,
   and a 23:55 notification lands when technicians are off the clock. A morning time if wanted.
4. **May a profile switch pilot reports on?** Proposed: it may set it on and set the addresses, but
   never lock it on. The tester's agreement is the reason it is on, so the tester can switch it off.
5. **Seven days of app events**, with the capacity raise measured on a device. Proposed: yes.

## Not covered

- **Unattended sending.** As Plan FV: no timed background run on iOS and no server. If Avenkin
  Office is in use, a later phase could carry the same file as one more upload kind over the managed
  folders, still opt-in.
- **Enforcing a key per company or per seat.** A code stays an offline bearer credential (Plan
  [EI](EI-licence-issuance-portal.md)). The fingerprint makes a shared code visible in support,
  nothing more.
- **Mapping the technician to a field-service system's technician.** The office does that by
  enrolment (Plan HT).
- **Live voice modes.** Their turns are not traced (Plan FV, *Not covered*), so a pilot report from
  a live-mode day has conversations only where Plan FW keeps them.

## Tests

- `TechnicianIdentityTests`: cleaning rules for each field, the short name being the existing key,
  profile set-and-lock for both new keys.
- `ReportIdentityTests`: company precedence, the fingerprint (stable, 8 hex, never the code), no
  lines when nothing is set.
- `SessionExporterTests`: the PDF's identity line from the snapshot (a name changed after the job
  starts does not reach it), a PDF with no identity unchanged byte for byte, `reportedBy` in the JSON
  and its absence decoded.
- Contract fixtures for the amended work record.
- `JobTranscriptExportTests`: the support report's identity lines and *From* line; `activityDays`
  across jobs, conversation-only days, trace-only days, the 14-day cut.
- `DiagnosticExportTests`: the ring's 7-day age bound and the new capacity.
- `DataStoreRegistryTests`: the retention text follows the constants.
- `PilotReportPromptPolicyTests`: once a day; unsent days only; the 7-day window; never with a job
  open, live or on CarPlay; a cancelled send offered again; *Not now* until tomorrow; switch off
  means nothing.
- `SupportReportRecipientTests`: the pilot address list (up to three, each checked).
