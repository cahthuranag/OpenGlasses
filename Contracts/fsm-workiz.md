# Direct Workiz reports, draft v1

The phone speaks the [official Workiz v2 API](https://developer.workiz.com/v2/), at
`https://api.workiz.com/crm/api/v2/`, using a company-wide Bearer key kept only on that phone.
This contract is public so Avenkin Office can consume the same synthetic fixtures and report blocks.

The job report field defaults to **Field Assist report**, a **Large Text** custom field on **JOB**.
Discover its `CF-` ID by exact name, type and entity. Duplicate matching names require attention.
`external.job_id` is the v2 `JOB-…` ID, never the legacy `uuid`; `external.technician_id` is `USR-…`.
The report's `reported_by` identity retains that Workiz technician ID.

Each report block begins on its own line with `Avenkin ref <8 lowercase hex>`. The eight digits
are the first eight SHA-256 digits of the exact exported work-record JSON bytes used for this send.
A writer replaces only the block with that exact marker, appends a new report below previous blocks,
and preserves all other blocks and any unmarked preamble. Duplicate matching markers require review.
A revisit has a new work record and therefore its own marker. Treat markers as deduplication hints,
not authorization or cryptographic proof (a 32-bit digest can collide).

The only permitted writes are `PUT /jobs/{JOB-id}` with a body containing **only `customFields`**,
whose array contains **only the report field** (`id`, `value`), and optional
`POST /clients/{CL-id}/notes` with **only `note`**. No job status, description, schedule, tags,
contact, money, transcript, photos or attachments are changed or uploaded. Fetch the latest job
before merging. Refuse malformed, truncated or duplicate-ID custom-field snapshots and oversize
text rather than treating an incomplete snapshot as an empty report. Workiz exposes no compare-and-swap: coordinated phone/Office routing is required.

Client notes carry the same marker. Persist the returned `CLN-` ID. Persist that POST is about to
be attempted before sending it; after an uncertain result, scan bounded note pages for the marker.
If absent after an ambiguous attempt, require attention; never blindly POST again.
Explicit 401/403/429 responses can be retried after credentials/backoff permit them.

A verified `organizationFieldServiceRoute=office` ceiling stops the direct connector, erases its
key and selected technician, removes unstarted direct jobs and terminates queued direct writes.
The signed office check-in's optional `fsmDirect` member reports `{system:"workiz",state:"on"}`
or `off`; omission means unknown. The office holds dispatch until `off` under its new profile.
A new challenge is needed after a route change; a previously answered challenge keeps its exact bytes.

## Qualification still owed

Fixture validation does not prove that Workiz's custom-fields-only PUT preserves every other job
field, or that its created-date scan includes every unscheduled job. Live trial validation was
explicitly deferred by the owner on 23 Oct 2026. Verify these, rate limits, field visibility and
permission/rotation behaviour before production rollout. See Plan JR's live walkthrough.
