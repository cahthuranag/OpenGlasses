# Job file contract — formats 2 and 3, draft (reference implementation, fixtures and the phone's import)

Drafted 2026-10-05 for Plan [HO](../docs/plans/HO-office-delivery-phone-half.md) P0b. This is the
agreement between an office and the phone app about a job sent as a file (`.ogjob`): what format
2 adds to format 1, what its signature covers, and what makes two files the same job. It is
self-contained so it can be carried into the office repository.

**It asserts nothing about the office app's internals.** Statements about the office are
requirements or marked *Assumption*.

**Built so far:** `Transport/mobile-core/jobfile` reads and writes format 2 — the outer file,
the signature, the job's identity and how two identities relate — and makes the golden fixture
in §8. **The phone app reads both formats** (Plan HO P0b, 2026-10-05): `JobFileValidator` opens
a format-2 file under the rules here, `JobFileSignatureCheck` verifies its signature over the
exact bytes, the job ahead and then the visit's record keep `job_id`, `revision` and the digest
of the job's bytes, and `JobFileService` applies §5. That is tested headless against the golden
fixture; no format-2 file has been opened on a physical phone. Two things in §5 the phone does
not do yet are marked there.

**Format 3** (§10, 2026-10-20, Plans [HT](../docs/plans/HT-external-job-references.md) P0 and
[HU](../docs/plans/HU-service-history-and-maintenance-flags.md) P0) adds what an office that
takes its jobs from another system can say about a job: that system's identity for it, the
office's history of each unit, the site's requirements, and a key, make and label per machine.
The Go package reads and writes it and makes its two golden files; the phone validates it, keeps
it on the job ahead and the visit, and echoes the identity in the record. Nothing of it is shown
yet (Plan HT P1, Plan HU P1).

## 1. What a job file is, in either format

A small JSON document that **proposes** a job ahead. It cannot start a job, change equipment,
create a task or send anything, and nothing is saved until the technician reads the review and
taps to add it. That is unchanged: an office's signature, or the file having arrived over the
[managed connection](README.md), never skips the review.

Format 1 is as the app reads it today: one object with `format` (`openglasses.job`),
`format_version` (`1`), the job's fields and an optional `signature`, signed over a canonical
re-encoding of the fields. It has no identifier of its own. Format 1 **stays readable**, and a
format-1 file is never upgraded in place: it is what it was when it arrived.

## 2. Why format 2

Three things format 1 cannot say:

| Gap | What it costs |
|---|---|
| No identifier the office assigned | The phone matches jobs by the job number a person typed, which two jobs can share and one job can change. A report cannot say which of the office's jobs it answers |
| No revision | A corrected job is a second job, or an overwrite the technician is asked about; an old copy arriving late can replace a newer one |
| The signature covers a re-encoding | Each side must reproduce the other's JSON encoder byte for byte, and the signature is not separated from anything else the organisation's key signs |

## 3. The file

One JSON object with these members and no others:

| Member | Meaning |
|---|---|
| `format` | `openglasses.job` — the wire identifier, unchanged |
| `format_version` | `2` |
| `job` | The job's exact bytes (§4), standard-alphabet padded base64 |
| `signature` | Optional. `{"algorithm":"ed25519","value":"<base64>"}` and no other member |

The whole file is at most 65,536 bytes. Unknown members, trailing data and a member named twice
in any object, at any depth, are refused. A format-1 reader sees a job file at a version it does not know and says so; it does
not mistake it for something else.

**The signature** is Ed25519 over the UTF-8 bytes `Avenkin.JobFile.v2`, one zero byte, then the
exact decoded `job` bytes. Nothing is re-encoded at verification: the bytes signed are the bytes
carried. The key is the **organisation's** job-signing key, which the phone has from its signed
organisation profile — the same key, held the same way, as for format 1. The domain means a
format-2 signature is not a format-1 signature, a managed-job signature or anything else that
key or any other has signed.

## 4. The job

The decoded `job` is one JSON object. Two members are new and **required**:

| Member | Meaning |
|---|---|
| `job_id` | The office's identifier for the job, stable for its whole life: 1–80 ASCII letters, digits, dot, underscore or hyphen, excluding `.` and `..`. It names nobody and is not shown as the job number |
| `revision` | A positive integer in plain decimal, at most 2^53 − 1, higher for each later version of the same job |

The rest are format 1's, with format 1's meaning and limits: `job_reference`, `site`
(`customer`, `address`, `contact`), `fault_report`, `equipment` (up to 10 of `model`, `serial`),
`scheduled_for` (ISO 8601), `notes`, `attachments` (up to 10 of `name`, `reference`; named,
never embedded) and `issued_by`. `format`, `format_version` and `signature` are members of the
file, not of the job. A format-2 job may also name what follows it in the `bulk` folder: an
attachment may carry `sha256`, `bytes` and `media_type`, and the job may have a `manuals` member
naming manual sets it needs ([bulk content](office-bulk.md) §5). The phone reads those in
format 2 and refuses them in format 1; what it then fetches is that contract's business. A
member not listed here is refused, as in format 1: a file that carries
something the phone cannot show is a file whose review would not be the whole truth. Text is
plain — no markup, no control characters beyond a line break in `fault_report` and `notes` —
and within format 1's length limits. A job needs a job number, a site or a fault report.

`job_reference` remains the number a person knows the job by. It may change between revisions;
`job_id` may not.

## 5. One job, its revisions, and the same file twice

A job's **identity** is its `job_id`; its **version** is its `revision` and the SHA-256 of its
exact `job` bytes. When a file arrives for a `job_id` the phone already holds:

| Arriving | The phone |
|---|---|
| A higher `revision` | Shows it in the review as a revision of that job, not a second job, and, when the technician accepts it, replaces the job ahead in place. *Not yet:* the review shows the whole of the new revision and says which revision it replaces; it does not pick out what changed |
| The same `revision`, the same bytes | Has this job already. It is one job, however many times and by whatever route it arrives — in particular when an office issues a job again under a new managed message after a binding renewal |
| The same `revision`, other bytes | Refuses it as a conflict. Laying the same words out differently is other bytes |
| A lower `revision` | Refuses it. An older revision never replaces a newer one |

*Requirement on the office:* it never issues two different jobs under one `job_id` and
`revision`, and it changes a job only by issuing a higher revision.

**A job already started.** A revision that arrives after the technician has started the job
does not change the job in progress or its record. It is shown as information on that job. How
an office sends an update or a note to a job in progress is Plan HN's contract, not this one.
*Not yet:* the phone refuses such a file with a sentence saying the job has been started, and
shows nothing on the job. The same revision arriving again for a started job is still one job.

**Signed and unsigned.** Whether an unsigned file may be offered at all is the phone's existing
rule: refused in medical mode and where the organisation's profile requires its signature,
otherwise offered and said to be unsigned. In addition, in format 2: an unsigned file, or one
whose signature this phone cannot check, never revises a job that arrived signed. Its `job_id`
is only a claim.

## 6. What a report says about the job

A record the phone sends back names the job it was written against. The
[report](office-reports.md) carries `jobID` and `jobRevision`: the `job_id` and `revision` of
the file the job was added from, or empty and `0` for a job that began any other way — typed on
the phone, or from a format-1 file. *Requirement on the office:* it matches a report to its job
by `jobID`, and uses `jobRevision` to see when the technician worked from a revision that has
since been replaced. The job number in the record is for people.

## 7. With the managed connection

A [managed job](README.md) names its job file by digest and size, whatever the file's format, so
format 2 travels there unchanged. The two signatures say different things: the office
application key's signature on the managed message says which office sent these bytes to this
phone; the organisation's signature on the job file says the organisation issued this job. The
managed message's own `messageID` and `sequence` order deliveries; `job_id` and `revision` say
which job, and which version of it, a delivery carries. Two managed messages that carry the same
file are one job (§5).

## 8. Fixture

`Contracts/fixtures/job-file-v2.ogjob`, made by `jobfile.Fixtures()` and kept current by that
package's tests: `job-2031` at revision 2, signed with a fictional organisation key whose seed
is the SHA-256 of the public label `Avenkin public fixture organisation job key v1`. It has no
authority.

```
go -C Transport/mobile-core test -tags noassets ./jobfile/
JOBFILE_WRITE_FIXTURES=1 go -C Transport/mobile-core test -tags noassets ./jobfile/   # regenerate
```

Negative cases, covered in the Go tests and in the app's own tests (`JobFileFormat2Tests`): a file at
another format version; an unknown or duplicate member of the file or of the job; trailing
data; a `job` that is not base64 or not an object; a missing, non-identifier or path-like
`job_id`; a missing, zero, fractional or quoted `revision`; a signature by another key, with no
domain, under another message's domain, or over a re-encoding of the same job; and, for a job
held, a lower revision, and other bytes at the same revision.

## 9. Open points

1. **Attachments.** How a job names bytes that follow it in `bulk` is now in the
   [bulk-content contract](office-bulk.md) §5, as additions to format 2's job rather than a
   format 3: no office had written a format-2 file then, and no released phone read one. Once
   either is true, a new member is a new format version. **Format 3 (§10) was made under this
   rule:** the office has written format 2 since 2026-10-05, so `external`, `history` and
   `site_requirements` are a new version rather than an amendment to format 2. The same rule now
   holds for format 3: every member it will have lands before any released phone reads it, or the
   next member is format 4.
2. **A started job.** §5 leaves a revision of a job in progress as information only. Plan HN
   decides what an office can change once work has begun.
3. **Unsigned format 2.** This draft keeps format 1's rule and lets an unsigned format-2 file be
   offered where policy allows. Whether format 2 should always be signed is undecided.
4. **Withdrawing a job.** Nothing here cancels a job ahead. A revision can say so in words; a
   signed cancellation is not designed.

## 10. Format 3: external references, service history and site requirements

### 10.1 The file

Format 3's file is format 2's (§3) with `format_version` `3`. Its signature is Ed25519 over the
UTF-8 bytes `Avenkin.JobFile.v3`, one zero byte, then the exact decoded `job` bytes, under the
same organisation key. The domain is its own so that a format-3 signature never verifies as
format 2's, and the reverse: relabelling a file's version breaks its signature. Identity,
revisions, the same file twice, signed and unsigned (§5), the report (§6) and the managed
connection (§7) are format 2's, unchanged. A format-3 job's identity on the phone is its
`job_id`; nothing in `external` ever decides whether two files are the same job.

The job is format 2's job (§4) with four additions, all optional. A member not listed here — at
the top of the job or inside any of these blocks — is refused, as in every format. Every text
value is plain text under §4's rules (no markup, no control characters, not blank) within the
limit given, in characters; a block's size is the exact bytes of its value in the job. Formats 1
and 2 never carry any of this: a phone refuses `external`, `history`, `site_requirements`,
`unit_key`, `make` or `label` in them as an unknown member.

*Requirement on the office:* it issues format 2 to a phone whose build predates format 3 (it
records the build at commissioning and check-in), and format 3 only where it has something of
§10.2–10.5 to say.

### 10.2 Machines: `unit_key`, `make`, `label`

Each `equipment[]` item may also carry:

| Member | Rule |
|---|---|
| `unit_key` | `[a-z0-9_-]{1,32}`, unique within the job, and never equal to any `serial` in the job (compared without case). The office's own handle for a machine — for one with no serial — never another system's identifier, never shown |
| `make` | ≤ 64 |
| `label` | ≤ 80. Where the machine sits at the site ("Roof, AHU-2"). Not an identifier |

### 10.3 `external`: the job's identity in another system

Opaque identity. The phone never calls it, never opens it as a link, never interprets it, never
looks anything up with it and shows no identifier from it. None of its values may contain `://`.
At most 2 KiB.

| Member | Required | Rule |
|---|---|---|
| `system` | yes | `[a-z0-9_-]{1,32}`: an opaque token naming the system. The phone compares it to nothing |
| `system_name` | no | ≤ 40. How people name the system, for display. The phone holds no table of names |
| `job_id` | yes | The system's identifier for the job: 1–128 printable ASCII characters, no spaces |
| `job_number` | no | ≤ 64. The number people use for the job |
| `appointment_id` | no | The system's identifier for the visit or booking the job file is for. As `job_id` |
| `location_id`, `customer_id`, `technician_id` | no | As `job_id`. Echoed, never shown |
| `equipment_ids` | no | An object, at most 10 entries, from a machine to the system's identifier for it (as `job_id`). Each key is the machine's `unit_key` when it has one, else its `serial`; a machine with neither has no entry |

Identifiers are printable ASCII rather than §4's identifier rule because some systems encode them
with `=`, `/` or `+`. Tenants, hosts, schedule identifiers and links stay with the office: there
is no other member.

**Which number is the job's.** When `external.job_number` is present it is the job's number on
the phone, on every surface. A `job_reference` that differs from it is kept as the office's
reference, shown on the review as such, never as the title. *Requirement on the office:* it sets
`job_reference` to the other system's job number when there is one.

**The echo.** The block travels with the job's provenance into the visit's record
(`work_record.job_file.external`) with the members and values the file had — re-encoded, so
member order and whitespace are not preserved. It is echoed whatever the file's signature, and
`job_file.signature` says which it was. *Requirement on the office:* it routes a report by
`external` only when the record's `job_file` is signed, and otherwise by its own `job_id` match;
an unsigned file's block is only a claim, as its `job_id` is (§5). The office-report envelope
([office reports](office-reports.md)) is unchanged and does not carry the block.

### 10.4 `history`: what the office knows about each unit

Compiled by the office, never created, edited or inferred on the phone. Internal: it never
reaches the work order, the customer's summary, the sign-off or the record, and the phone drops
it from the visit when the job closes. At most 24 KiB.

| Member | Required | Rule |
|---|---|---|
| `as_of` | yes | When the office compiled it: ISO 8601 date and time |
| `units` | no | At most 10 (one a machine) |
| `flags` | no | At most 12 in all |

**A unit** names exactly one machine on the job, once, by exactly one of `serial` (equal to a
machine's `serial`) or `unit_key` (equal to a machine's `unit_key`) — never by model. Its other
members:

| Member | Rule |
|---|---|
| `installed` | ISO 8601 date (`YYYY-MM-DD`), present only when the office's records hold the installation date (not manufacture) |
| `warranty` | `status` (required: `in_warranty`, `expired` or `unknown`), `until` (ISO date), `note` (≤ 160). No member means no status |
| `visits` | At most 10, newest first (a later visit after an earlier one is refused), each at most 2 KiB |

**A visit:** `date` (ISO date, required), `summary` (≤ 600, required), `job_number` (≤ 64),
`findings` (at most 6, each ≤ 200), `parts_replaced` (at most 8, each ≤ 80),
`technician_initials` (1–4 letters), `source` (a token, as `external.system`).

**A flag:**

| Member | Rule |
|---|---|
| `kind` | `recurring_failure`, `replacement_pattern`, `overdue_maintenance`, `maintenance_due` or `recall_or_bulletin`. An unknown kind is refused: the review would not be the whole truth |
| `basis` | `rule` (the default when absent) or `schedule`. Only `overdue_maintenance` and `maintenance_due` may be `schedule` |
| `unit` | The key a `units` entry is named by. Required, except on a `schedule` flag, where its absence means the whole site |
| `text` | ≤ 240, required |
| `evidence` | At most 10 job numbers, each ≤ 64. At least one unless `basis` is `schedule`, whose evidence is the schedule itself |
| `severity` | `info` or `warning`, required. The office decides; the phone never promotes one |
| `due` | ISO date, on `overdue_maintenance` and `maintenance_due` only |
| `schedule` | ≤ 80: the office's short plain-text name for the service ("Annual service"), on a `schedule` flag only |

A unit has at most 3 flags; site-wide flags count in the 12, not in any unit's 3.

### 10.5 `site_requirements`: what the site asks of the person arriving

Office-authored and internal, as `history`; nothing is kept per site between jobs. At most 4 KiB.
`as_of` (required, as `history`'s) and `items` (required, at most 8), each with `kind`
(`access`, `induction`, `ppe`, `hazard`, `contact` or `other`; unknown refused), `text` (≤ 240)
and `severity` (`info` or `warning`), all three required.

### 10.6 Bounds, and the job's size

With `external` at 2 KiB, `history` at 24 KiB, `site_requirements` at 4 KiB and format 1's fields
at their limits (about 9 KiB), a job stays under the 48 KiB that the 65,536-byte file allows in
base64. Over any bound the job is refused with a sentence; the office trims, the phone never
truncates. More history than fits is a [bulk](office-bulk.md) question, not a larger job file.

### 10.7 Fixtures

`Contracts/fixtures/job-file-v3-external.ogjob` (`job-3031`: a full `external` block, a machine
by serial and one by `unit_key`, each with a make and a label, and an office reference that
differs from the other system's number) and `Contracts/fixtures/job-file-v3-history.ogjob`
(`job-3032`: history for both machines with a warranty each, a rule's flag with evidence, a
schedule's site-wide `maintenance_due` flag, and three site requirements). Both are made by
`jobfile.Fixtures()` with §8's fictional key, from invented data, and regenerated as §8 says.
Negative cases are in the Go tests (`format3_test.go`) and the app's (`JobFileFormat3Tests`,
`JobFileExternalReferenceTests`, `OfficeServiceHistoryValidationTests`,
`SiteRequirementsValidationTests`, `JobFileUnitKeyTests`). The Go package checks every rule here
except the plain-text ones (markup, and the characters a text value may hold beyond control
characters), which are the phone's; an office that wants its files accepted keeps to them.
