# Plan JR — Workiz From the Phone

**Status:** Implemented against synthetic fixtures on 2026-10-23, based on merged Plan JQ (#835). Live Workiz
qualification is deferred by the owner: **“Build and test with fixtures; validate live later.”**
The company-wide-key risk and proposed defaults below govern this implementation: local key paste
behind the administrator gate when managed, report-only writes, customer primary phone, Office-only
routing under its profile, and the newest five read-only notes. No live account or credential was used.

**Origin:** an appliance-repair tester that runs its business on Workiz asked, through the pilot
partner, whether the app could connect to it. Its owner wants to start with refrigerators, and the
firm has no office computer running Avenkin Office.
**Decided (owner, 2026-10-23):** the phone may talk to Workiz directly. This **amends Plan
[HT](HT-external-job-references.md)**, whose rule was that the phone never talks to a field-service
system and the office does. That rule stays for every firm that runs Avenkin Office. A firm without
the office may connect **one** field-service system on the phone, and Workiz is the first.

Why: the field work must work from the phone alone, with the office as an addition and never a
prerequisite. A small firm on Workiz has no other route.

## What Workiz offers (v2 API, read 2026-10-23)

- **Access.** `https://api.workiz.com/crm/api/v2/…`, with `Authorization: Bearer <key>`. The
  account owner turns on the *Developer API* add-on (the pricing page lists the API on the top plan
  only), then creates **named keys**. Each key gets per-resource *Read* or *Read & Write* access, an
  optional expiry, rotation and its own logs. There is **no sandbox**. The free trial lasts 7 days.
- **Errors.** `401` missing or invalid key; `403` *"This API key does not have permission to access
  this resource"*; `429` rate limited (no published limit).
- **Jobs.** `GET /jobs` is paginated, with a date filter (`dateProperty`/`dateOperator`/`date`,
  defaulting to the last 30 days by scheduled date) and `isOpen`. **There is no filter by
  technician.** `GET /jobs/{id}` returns `id` (`JOB-…`), `serialId` (the number people use),
  `name`, `status`, `subStatus`, `date`/`endDate`, `jobType`, `description`, `clientInfo` (client ID,
  names, company, phones, email, address, service area), `team` (`USR-…` and name), `lineItems`,
  `tags`, `customFields`, `notes` (read only) and `attachments` (name and URL, read only).
- **Writing.** `PUT /jobs/{id}` takes `status`, `subStatusId`, `date`/`endDate`, `name`,
  `description`, `jobTypeId`, `clientInfo`, `tags` and `customFields`. **No call adds a job note,
  uploads a file or adds a line item.** `POST /clients/{clientId}/notes` adds a note to the client.
  `GET /customfields` lists custom fields, including *Large Text*.
- **Users.** `GET /users` gives `id`, `name`, `emailAddress`, `role`, `fieldTech` and `active`.
- **Webhooks** post to a server when an automation rule fires. A phone cannot receive them, so this
  plan polls.

## The risk, said once

A Workiz key is **company-wide**. Its scopes narrow it by resource, not by technician, so a key
that reads jobs reads every job and every client's contact details, and the same key sits on every
technician's phone. A phone that leaves the firm, or a key copied off a phone, keeps that access
until the owner rotates the key. The plan reduces this but cannot remove it:

- **The smallest key that works.** The app lists the scopes it needs and nothing more: Jobs
  *Read & Write*, Users *Read*, Custom fields *Read*, and Clients *Read & Write* only when client
  notes are on. It recommends an expiry.
- **Stored only on this phone.** The key goes in the Keychain (`…ThisDeviceOnly`), is never in a
  backup, a log, a support report or a profile, and is erased when the phone leaves its organisation
  and by *Remove Workiz key*.
- **The phone shows only the technician's own jobs**, even though the key could read more.
- **Rotation is one paste.** A `401` after a rotation says *"Workiz didn't accept the key — it may
  have been replaced. Paste the new key in Settings."*

The owner accepts this risk for a firm without the office (decision 1).

## P0 — Headless core

All pure, over values and fixtures, with no network:

- **`WorkizAPI`.** Builds requests (base URL, path, query, Bearer header, JSON body) and decodes
  responses into closed, bounded types: `WorkizJob`, `WorkizClient`, `WorkizUser`,
  `WorkizCustomField`, `WorkizPage`. Workiz is untrusted input: unknown members are ignored, strings
  are capped, and a malformed job is dropped from a list with a count, never a crash. Errors map to a
  sentence each: bad key, missing permission (naming the resource from the path), rate limited,
  Workiz unavailable, no connection. The key is never in an error, description or log line
  (`DiagnosticsRedactor` gets it as a known secret).
- **`WorkizMyJobs`.** Decides which jobs the phone shows: open jobs whose `team` contains the
  technician's `USR-` ID, scheduled from yesterday to 7 days ahead, plus unscheduled ones assigned to
  them. Sorted by time and capped at `UpcomingJobStore.entryCap`. Pages are fetched until the date
  window is covered, with a page budget.
- **`WorkizJobMapper`.** Maps a Workiz job to an `UpcomingJob`. Origin is a new `.connector`; the
  job number is `serialId`; the site comes from `clientInfo`'s address and name; the fault report
  from `jobType` and `description`; `scheduledFor` from `date`; notes from the newest five Workiz
  notes, each with its author and time. Attachments are listed by name and **never fetched**, the
  rule job files already follow. It also builds an `ExternalJobReference`: `system: "workiz"`,
  `systemName: "Workiz"`, `jobID` (`JOB-…`), `jobNumber`, `customerID` (`CL-…`) and `technicianID`
  (`USR-…`). A re-pull updates a job not yet started; a started job keeps the snapshot it started
  with.
- **`WorkizWriteBack`.** Composes what goes back from the closed job's work record and customer
  summary: the work done, findings, parts used, recommendations, the key readings, and who did it
  (Plan [JQ](JQ-pilot-identity-and-daily-reports.md)'s identity). **Never the transcript, never
  photos.** It produces a write plan:
  1. the job's report custom field (a *Large Text* field the owner creates, found by name through
     `GET /customfields`), set with `PUT /jobs/{id}` carrying **only** `customFields`;
  2. optionally a client note (`POST /clients/{clientId}/notes`) headed *Job 1234 — 23 Oct 2026*;
  3. optionally a sub-status (decision 3).

  The plan never writes the description, schedule, status, client details, tags or money. The
  field's value is made of **report blocks**, each beginning with its marker line (`Contracts/fsm-workiz.md`).
  A writer replaces only the block carrying its own marker, appends a block for a new report, and
  never removes or edits another block, whether the phone or an office wrote it. So a resend is
  idempotent, and a revisit's report sits below the first. A client note is posted once, with its ID
  remembered, and carries the same marker line.
- **Shared fixtures and a contract, in `Contracts/`.** The office's Workiz connector decodes the
  same responses and must recognise what the phone wrote, so P0 publishes both where the office pins
  public contracts:
  - `Contracts/fixtures/workiz-v2/` with a `README.md` (synthetic, built from the v2 document's
    example shapes, invented IDs, names and addresses): a jobs page with `hasMore` and a last page;
    jobs scheduled, unscheduled, cancelled, done, with two technicians, and with notes and
    attachments; the users list; the custom-field list with and without the report field; a job
    whose report field holds two blocks; a client-notes list holding a marker; and the error bodies
    for `400`, `401`, `403` and `429`.
  - `Contracts/fsm-workiz.md`, short:
    - the report field's default name, **Field Assist report** (*Large Text*, on jobs);
    - the marker line, `Avenkin ref <8 lowercase hex>`, where the hex is the first eight digits of
      the SHA-256 of the report's work record as sent;
    - the block rules above;
    - the job identity (`external.job_id` is the `JOB-…` ID, never v1's `uuid`;
      `external.technician_id` is the `USR-…` ID);
    - the only writes allowed: the report field through a `customFields`-only `PUT`, and
      `POST /clients/{id}/notes`.

  The phone's tests run over these fixtures, as the office's will.

## P1 — The connection, in Settings

**Settings → Field Assist → Field service software → Workiz.** The section is shown only when Field
Assist is licensed and the profile does not route the firm's field-service system through its
office (`organizationFieldServiceRoute`, see *When the firm gets Avenkin Office*).

1. **Key.** A paste field with a short *How to make a key* list: Feature center → Developer API;
   Settings → Developer → v2 → Create New API Key; the scopes above; an expiry.
2. **Test connection.** It calls `GET /users?pageSize=1`, `GET /jobs?pageSize=1` and `GET
   /customfields`, then says in one line what works: *"Connected to Workiz. Jobs ✓ Users ✓ Report
   field ✓ — client notes off."* A missing scope names the scope to add. Write access cannot be
   tested without writing, so it is confirmed on the first send, and a `403` then says which
   permission to add.
3. **Who are you in Workiz?** A list of active field technicians from `GET /users`, with the one
   whose full name uniquely matches Plan JQ's technician details preselected. The choice stores the
   `USR-` ID and display name in the device-only Keychain, shown as *"You're Jamie Lee in Workiz."*
   It persists across app launches and key rotation. Normal job refreshes do not fetch the users
   list or ask again; Test connection fetches it again and clears an inactive or missing choice.
   Plan JQ's names and company still supply the human report identity; Workiz supplies its external
   technician ID.
4. **What goes back.** Report field name (default *Field Assist report*), client notes on or off,
   and a sub-status if decision 3 allows one.
5. **Remove Workiz key.**

**On a company's phones:** a profile cannot carry the key, because a secret must never be printable
in a QR code (`SettingKey`'s rule). The profile may turn the connector on, set the report field
name and write-back choices, and lock them. The key is pasted on each phone, behind the admin
passcode when the phone is managed (decision 2). A route `NetworkRoute.workizAPI` is registered with
the same data classes as the offline endpoint sync plus `credential`, is blocked under Medical Local
Only, and gets its own `URLSession` transport behind a seam so tests never reach the network.

## P2 — Workiz jobs in the Job tab

- **When it pulls.** When the app comes to the foreground, when the Job tab opens (at most every 10
  minutes) and on pull-to-refresh. There is no background fetch. The last pull is kept in
  `UpcomingJobStore` and labelled *"From Workiz at 8:12"*, so a phone with no signal still shows the
  morning's jobs.
- **What the technician sees.** The job-day card and the Job tab list Workiz jobs with the time,
  number, type and client: *"10:00 · #1234 · Fridge not cooling · M. Smith, 12 Elm St"*, with a small
  *Workiz* label. Tapping one opens the brief, and *Start job* starts it with the number, site, fault
  and notes filled in. The technician then identifies the fridge by voice or photo, as today.
- **By voice.** *"What's my next job?"*, *"brief me on the next job"* and *"directions to the next
  job"* already read `UpcomingJobStore` (`brief_next_job`, `DirectionsTool.next_job`), so Workiz jobs
  answer them with no new tool.
- **Changes in Workiz.** A job rescheduled or reassigned to someone else moves or leaves on the next
  pull. A job cancelled before it started leaves with one line in the list: *"Job 1234 was cancelled
  in Workiz."* A job already started is never removed by a pull.
- **Calling the customer.** The client's primary phone is shown with a call button (decision 4).

## P3 — The report goes back to Workiz

- When a Workiz job closes and its report is sent through the usual flow (`JobSendService`), a
  Workiz delivery joins the offline queue as a new `SyncSink`, `WorkizSyncSink`. It is retried with
  the queue's back-off and survives a relaunch.
- The job's row shows how it went: *Sent to Workiz*, *Waiting for a connection*, or *Needs
  attention — the Workiz key can't write jobs. Ask the owner to give it Jobs: Read & Write.* A
  `401`/`403` stops retrying until the key changes; a `429` or `5xx` backs off.
- The customer PDF and photos still go by email as today, because Workiz's API cannot take files.
- The visit's record keeps the `ExternalJobReference` (Plan HT's echo), so the job file, report and
  Workiz job stay tied together.

## When the firm gets Avenkin Office

A firm may start on the phone and add the office later. The office then connects Workiz itself
(office plan FX24), and the two routes must never run together, or the same job is issued twice
and the same report written twice (office plan FX29). Three things on the phone make the
hand-over safe:

1. **A route key.** `SettingKey.organizationFieldServiceRoute`, tighten-only, whose one value is
   `office`. The office adds it to its profile request when it first connects a field-service
   system. On a phone that verifies a profile carrying it:
   - the direct connector stops, for every system;
   - the Settings section is replaced by one line, *"Your office connects to Workiz for you."*;
   - the Workiz key and the stored `USR-` ID are erased;
   - Workiz jobs not yet started leave the list on the next refresh; jobs already started keep
     their snapshot and their `ExternalJobReference`;
   - a Workiz delivery still waiting in the queue ends as *"Not sent to Workiz — your office posts
     reports now"*. The report goes to the office by the usual route, and the office posts it,
     recognising any block the phone already wrote by its marker.

   The key never re-enables anything when it is absent: a later profile without it leaves the
   section available again, and the technician has to paste a key again.
2. **A check-in member.** The office check-in (`Contracts/office-check-in.md` §4.2, draft v1)
   gains an optional member `fsmDirect: {system, state}`, with `state` either `on` (a key is stored
   and the connector is running) or `off`. Absent means an app that predates it, which the office
   reads as *unknown*. It is covered by the check-in's signature like every member. The contract's
   §11 fixtures are regenerated with one `on` and one `off` check-in. The office holds a
   technician's jobs until that phone's check-in reports `off` under the new profile.
3. **The shared fixtures and contract** (P0), so the office's connector reads the phone's job
   identity and report blocks exactly as the phone wrote them.

This replaces decision 5's *"hidden while an office connection is set"*: the profile, not a local
guess about a connection, decides.

## How we check the experience

**1. In the simulator, with a stub (built with P2).** A UI-test launch argument
(`-UITestWorkizFixture`, beside the existing `UITestSupport` switches) swaps in a stub transport
serving fixture jobs. Screenshots, in light and dark mode, at default and the largest Dynamic Type,
of:
- Settings: empty, testing, connected, wrong key, missing permission, and the *Who are you* list;
- the Job tab with three Workiz jobs (one now, one later, one unscheduled), *"From Workiz at …"*,
  offline;
- the brief, the started job, and the closed job in each delivery state;
- a cancelled job's line.

The accessibility audit runs over each screen. The screenshots go in the PR for review. Device
captures only for anything public, per the screenshot rule.

**2. Against a real Workiz account (the owner, on the 7-day trial).** Invented customers and three
jobs assigned to one invented technician. One sitting on the phone, every step timed and marked
pass or fail:
1. Paste the key and run Test connection.
2. Pick yourself.
3. See today's jobs (target: under 5 s on 4G).
4. Start the next job by voice.
5. Close it.
6. Find the report in the Workiz job's report field and the client note.
7. Reschedule a job in Workiz and refresh.
8. Cancel one.
9. Remove the key's Jobs-write permission and close a job: the sentence names the permission.
10. Rotate the key: the *paste the new key* sentence appears.
11. Go offline and open the Job tab.

The results are recorded in this plan.

**3. With the tester (after 2 passes).** The owner makes the key on their own account; one
technician uses it for a week. We watch: jobs started from Workiz against jobs typed in, write-back
success, time from opening the app to the first job started, and every *needs attention*. Their
feedback comes through the partner. Plan JQ's daily report carries the evidence.

## Decisions owed

1. **The risk.** A company-wide key on each technician's phone (above), accepted for firms without
   Avenkin Office. *Proposed: yes, with the mitigations listed.*
2. **How the key reaches each phone.** *Proposed: pasted on each phone* (behind the admin passcode
   when managed). Later, a sealed key file like the licence activation file, if pasting proves error
   prone.
3. **Changing the job's status from the phone.** Workiz statuses and sub-statuses are each
   company's own. *Proposed: none in P3*, and later an optional sub-status the owner names (e.g.
   *Report sent*), never *Done*.
4. **The customer's contact details on the phone.** *Proposed: name, address and primary phone
   (to call ahead); not email.*
5. **A firm with Avenkin Office and Workiz.** *Proposed: the office's connector only.* The
   mechanism is the route key and check-in member in *When the firm gets Avenkin Office*.
6. **Workiz job notes on the phone.** *Proposed: the newest five, read only*, since they are often
   the office's instructions for the visit.

## Open questions to settle on the trial account

- Whether `PUT /jobs/{id}` with only `customFields` leaves every other field alone (the spec implies
  a partial update; to be confirmed before P3 ships).
- The rate limit in practice, and whether the date filter can select by scheduled start.
- Whether a *Large Text* custom field shows on the job in Workiz's own mobile app for the office.
- Whether a technician-role user can be given an API key, which would narrow the risk.

## Not covered

- **Creating jobs, estimates, invoices, payments or line items** from the phone.
- **Any other field-service system.** Each one gets its own plan. The parts here that are not
  Workiz's (the connector origin, the sink, the Settings shape) are written so a second system does
  not reshape them.
- **Webhooks and background refresh.** There is no server to receive a webhook, and there is no
  background run.
- **The office's own Workiz connector.** It is office plan FX24 (private). This plan owns only the
  phone's half of the hand-over and the shared contract.

## Tests

- `WorkizAPITests`: request shapes (path, query, header), decoding of each fixture, unknown members
  ignored, oversize strings capped, a malformed job dropped and counted, each status code's
  sentence, the key absent from every description.
- `WorkizMyJobsTests`: team filtering, the date window, unscheduled jobs, paging to the window, the
  cap.
- `WorkizJobMapperTests`: every mapped field, the external reference, attachments never fetched,
  re-pull versus started snapshot, cancellation.
- `WorkizWriteBackTests`: the composed text (no transcript; JQ identity), a body with only
  `customFields`, field lookup by name, the marker line's digest, block rules (replace own, append
  new, never touch another's, over the two-block fixture), the client note once, idempotent resend.
- `WorkizRouteTests`: `organizationFieldServiceRoute` is tighten-only; on it, the connector stops,
  the key and user ID are erased, unstarted jobs leave, started jobs keep their reference, and a
  queued delivery ends with its sentence.
- Check-in: `fsmDirect` encoded `on`, `off` and absent, signed over, against the regenerated
  fixtures.
- `WorkizSyncSinkTests`: retry and back-off, `401`/`403` stopping, persistence over relaunch.
- `NetworkRouteRegistry`, `DataStoreRegistry` and telemetry guards updated for the new route, the
  key and the stored user ID.
- A UI test over the stub that walks P1–P3 and takes the screenshots above.

## Implementation and validation — 2026-10-23

P0–P3 are wired into the phone. `Services/FieldAssist/Workiz/` contains the bounded v2 API,
closed values, assignment/window filter, mapper, report-block writer, protected connection,
transport seam, refresh controller and durable sink. Workiz jobs use the existing ahead store,
brief/start/next-job/directions paths. Started visits keep their external identity and note snapshot.
The cached pull stamp is protected and excluded from backup beside the ahead store.

The dedicated ephemeral transport rejects redirects and arbitrary hosts, caps response bytes and
checks Medical Local Only and the live Field Assist licence before every request, including retries.
A licence lapse stops requests while preserving local records and the saved key for renewal. The request builder permits only reads, the
report-field-only PUT and optional note-only POST. Attachment URLs and customer email are discarded.
Malformed, duplicate-ID or over-budget custom-field snapshots are refused before any PUT so an
existing report is never treated as an empty field after truncation. The queue persists field progress, the client-note write-ahead flag/receipt, authentication generation,
backoff date and terminal Office handover. Foreground timers re-arm persisted retries; no background
job polling was added. The usual PDF/email route stays in place. A report marker hashes the exact
confirmed work-record bytes, including Plan JQ's identity.

The profile's `organizationFieldServiceRoute` is a string ceiling accepting only `office`.
Workiz options can be profile-owned and locked; the key cannot be carried by a profile.
Handover clears the device-only key and selected technician, removes unstarted Workiz jobs and
terminates direct deliveries. A durable revocation flag prevents a failed Keychain erase from
re-enabling the connector on relaunch. The optional signed check-in state is implemented in Swift
and the public Go transport, with new on/off golden fixtures and strict nested-field validation.

Validation:

- Final selected iOS run: 260 tests, zero failures, one existing optional-manual test skipped
  because its local manuals are absent. Includes all 33 Workiz tests, job briefs/lists/external
  references/work records, store and route inventories, manifest reconciliation, profile policy,
  offline queue, JQ identity and signed check-in/service tests.
- Full `go test -tags noassets ./...` passed, including signed direct-state rejection cases.
  The changed check-in package also passed `go test -race -tags noassets ./checkin`.
- Public portable suites: 72 manual-contract, 16 entitlement/pairing and 221 recording-contract
  tests passed. The Swift call to the new optional bridge method type-checks against freshly
  generated Objective-C bindings.
- Privacy logging gate passed. The privacy inventory's generated table includes Workiz.
- All 12 fixture UI walks passed, with zero failures, in light/dark mode at default and largest
  Dynamic Type. The accessibility audit ran on all 60 captured viewports. The
  [screenshot matrix and exact audit exceptions](evidence/JR/README.md) are committed for review.
  The Workiz status scrolls with the Jobs list, and status/action labels wrap at accessibility sizes.

Live qualification remains **unrun**. In particular, do not infer from fixtures that a
`customFields`-only PUT preserves every other field in a real account, that created-date scanning
covers every unscheduled job, or that the report field is visible in Workiz mobile. The timed
11-step walkthrough and subsequent tester week above are still owed before production rollout.
