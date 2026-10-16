# Plan IO — Sealed Proof-of-Work Photos (as found, as left, and seen by the next technician)

**Status:** 📝 Drafted 2026-10-16 — nothing implemented.
**Track:** Field Assist (B2B): asked for by electricians, useful to every trade.
**Depends on:** Plan [HO](HO-office-delivery-phone-half.md)'s owed item "photographs and clips as
their own attachments" for P3. Nothing earlier waits on the office.
**Related:** Plan [GX](GX-photo-checked-procedure-steps.md) (a photo check on a procedure step; this
plan adds the *proof* requirement and the seal beside GX's *check*), Plan
[FO](FO-guided-job-flow-and-job-tab.md) (job media and the evidence review at close), Plan
[EM](EM-work-record-and-parts.md) (the work record), Plan [HU](HU-service-history-and-maintenance-flags.md)
(the office's service history in the job file), Plan [HV](HV-site-system-vaults.md) (sites), Plan
[CP](CP-outbound-frame-privacy.md) (the privacy chokepoint), Plan
[IP](IP-organisation-feature-switches.md) (an organisation switches it on, or requires it).
**Origin:** Electricians at a startup festival in Auckland, 2026-10, in conversation with the owner.
Too often they arrive at a job and find that a previous electrician, from another firm or years
earlier, installed something that is not to code. A photo taken at the end of the step or job, and
locked to it, proves what *they* left. It also tells the next electrician from the same firm what
is there before they go.

---

## Outcome

- At a step a procedure marks `proof`, or at the close of a job an organisation requires it, the
  technician takes an **as-left** photo. On arrival they can take **as-found** photos of what they
  were handed.
- Each proof photo is **sealed** as it is stored: its bytes are hashed, and the hash is bound to the
  job, the step, the capture time, the phone's location fix and the phone's identity, then signed by
  the phone's key. Proof photos form a hash chain within the job, so removing or reordering one is
  visible.
- A sealed photo can't be replaced. A retake adds a new sealed photo and marks the earlier one
  superseded, with a spoken or typed reason. Both stay in the record.
- The work-order PDF shows each proof photo with its seal fingerprint, time and location. The job
  record carries the full seals, which anyone can verify with the phone's public key, and the office
  records an independent receipt time when it receives them.
- Before the next visit to that site, a technician from the same organisation sees the last visit's
  as-left photos in the brief.

## What a seal proves, and what it doesn't

The wording on the PDF and in the app must not overclaim. A seal shows that **this phone stored
these exact bytes, at this point in the job, and nothing has changed them since**. It does not show
that the phone's clock was right, or that the location fix was accurate beyond its stated accuracy.
It also does not show that the picture shows what the caption says. Two things make the time
stronger:

- the office's signed receipt (HO P2) is a second clock the phone does not control;
- when the photo is on a job that leaves the phone promptly, the gap between seal time and receipt
  time is printed.

The PDF says "Sealed by <phone> at <time> (phone clock), received by the office at <time>". It
never says "certified" or "tamper-proof".

## Verified starting point (`main` @ `8d0266ae0`, 2026-10-16)

- **Photos attach to a job and loosely to a task.** `FieldSessionService.attachPhoto` writes the file
  through `SessionLogger.attachPhoto` and appends a `JobMediaItem`. Its `taskId` is the last
  in-progress task, which is a guess, not a binding. Its other fields are `id` (file name with a
  timestamp), `kind`, `capturedAt`, `origin`, `caption`, `filterWasOn` and `byteCount`. Routes:
  `photo_log`, `capture_photo` and the Job tab's phone camera and library (`JobPhotoEvidenceService`).
- **No hash, signature or per-photo location.** `FieldSession` has `startLocation`/`endLocation`
  only. The job record (`log.jsonl` and the session JSON) is written with plain atomic writes, and
  `SessionExporter`'s PDF/JSON carry no digest. HO notes that "photographs carry no digest today".
- **Signing exists nearby.** `OfficeReport` is Ed25519-signed with `recordSHA256`,
  `manifestSHA256` and per-attachment `sha256`/`bytes`/`role`/`audience`, signed by
  `OfficePhoneIdentity.signOfficeReport`. Recorded-job bundles sign a per-part SHA-256 manifest
  (`JobRecording/BundleManifest`). `CustomerSignOff.summaryDigest` is a SHA-256 over the frozen
  summary. `AuditChain` is a hash-chained, content-free log used only by HIPAA.
- **Photos can't be deleted, only excluded.** `decideEvidence(itemId:included:)` includes or
  excludes a photo from the report. Files stay on disk. Captions are editable at review. Nothing can
  be attached after the session ends (`isOpenForEvidence`). Whole sessions can be deleted.
- **Photos are filtered.** Glasses stills go through `cameraService.filteredStill(for:
  .toolPhotoCapture…)`. Phone and library photos go through `JobPhotoEvidenceService.attach`, which
  stores nothing when the blur is unavailable. Only the filtered JPEG is stored. The pixels change
  only while the privacy filter is on, and an organisation can pin it on. The roster entry is
  `OutboundFrameConsumer.jobPhoneEvidence`.
- **Steps have no photo requirement.** `Procedure.Step`'s only gate is `requires_confirmation` on a
  terminal step. GX proposes `Step.check` (`reading`, `text_match`, `code`, `condition`) with
  `required` and `safety_critical`, and an override with a reason. It is drafted and unbuilt.
- **Earlier visits reach a phone only as text, and only its own.** `JobHistoryIndex` covers this
  phone's finished sessions by site, serial and model, without photos. The signed job file is
  capped at 64 KiB, but format 2 may *name* up to ten attachments (`sha256`, `bytes`,
  `media_type` JPEG or PNG) that the phone fetches from the office's `bulk` folder
  (`OfficeJobAttachmentStore`, opt-in office-transport build). HU's history is text-only, ten visits
  a unit and 24 KiB in all.

## Decisions proposed (owner to confirm)

1. **Seal the bytes that are stored, after the privacy filter.** The proof is of the work, and a
   switchboard rarely has a face in it. The filter's scope stays as it is (every egress filtered;
   face recognition the sole exemption). An organisation that wants unblurred proof turns the
   filter off for its phones, which is visible in the seal (`filterWasOn`).
2. **A proof photo comes from the camera, never the library.** The library route stays for ordinary
   job photos. A proof photo has to be taken inside the app at the step, or the seal's "when" means
   nothing.
3. **Append-only.** No delete, no replace. A retake supersedes with a reason. Excluding a proof photo
   from the *customer's* report is allowed. Removing it from the organisation's record is not. The
   whole-session delete is unchanged (it is the subject's erasure right) and leaves a tombstone in
   the chain's export.
4. **The phone's existing office identity key signs.** It is `OfficePhoneIdentity`, which an office
   already knows. A phone with no office uses a per-install key whose public half is printed in the
   PDF and kept in the job record, so the seal still verifies, just without an organisation vouching
   for the phone.
5. **Prior photos come from the office, never another phone directly.** The office names up to
   four of the last visit's as-left photos in the next job's signed job file, through format 2
   attachments, and the phone fetches them as it does today. Without an office, a technician sees
   only their own phone's earlier photos for that site.
6. **As found is offered, not required.** On a job whose organisation requires proof, the first
   photo prompt is "Anything you want on record as you found it?". One "no" and it's gone for the
   rest of the job.

## Phases (one PR each)

### P0 — The seal (pure core)

- `ProofSeal`: `photoSHA256`, `byteCount`, `jobSessionID`, `stepRef?` (procedure id and step id),
  `role` (`asFound` | `asLeft` | `stepProof`), `sealedAt`, `location?` (lat, lon, horizontal
  accuracy, fix age), `filterWasOn`, `supersedes?` plus `reason`, `previousSealSHA256` (the chain),
  `deviceKeyID`, and `signature` over the canonical encoding.
- `ProofSealer` (pure, key injected) and `ProofSealVerifier` (pure, public key in) give named
  results: `valid`, `bytesChanged`, `chainBroken(at:)`, `signatureInvalid`, `unknownKey`.
- **Exit tests:** golden vectors, a flipped byte, a removed middle photo, reordering, a superseded
  photo still verifying, and a canonical-encoding fixture shared with the office's verifier (the
  same pattern as `Contracts/` goldens).

### P1 — Taking a proof photo

- `JobMediaItem` gains `seal: ProofSeal?` and a real `stepRef` when taken at a step, instead of the
  last-in-progress guess. `FieldSessionService.attachProofPhoto(role:stepRef:)` takes the filtered
  still (or phone camera capture), seals it as it is written, and refuses library input (decision 2).
- A location fix is requested when the job opens and refreshed on a proof capture. The fix's
  accuracy is recorded as it came; a missing fix is recorded as missing, not filled in from the
  start location.
- Procedure step `proof: true` (schema and validator; GX's `check` is independent, and a step may
  have both). The terminal step's existing confirmation can require a proof photo. At job close,
  when the organisation requires one (an IP switch), the close asks for an as-left photo before the
  record is sealed.
- Voice: "take the proof photo", "as found", "retake that, the cover was off" (superseding, with the
  words as the reason). The Job tab shows a seal badge on proof photos.
- **Exit tests:** a scripted job with a `proof` step stores a sealed, step-bound photo. A retake
  supersedes it and both verify. Library input is refused. The filter-unavailable path stores
  nothing (unchanged), and the roster test still passes with no new raw-frame reader.

### P2 — The record and the report

- `WorkRecord` carries each proof photo's seal, and the record ends with a seal over the chain's
  head. `SessionExporter`'s organisation-audience JSON includes the full seals. The PDF shows each
  proof photo with role, step, time, the location with its accuracy, and a short fingerprint (the
  first 12 hex characters), plus a verification note in the wording from "What a seal proves".
- The customer-audience report may include as-left photos (the organisation decides) but never
  as-found photos of a previous contractor's work by default, because pointing at another firm's
  workmanship in a customer document is the organisation's call.
- A small verifier entry point in the existing audited-export view: open a job record JSON and
  photos, and get `ProofSealVerifier`'s result per photo.
- **Exit tests:** export round trip and verify; the PDF snapshot; the customer report's
  as-found exclusion.

### P3 — To the office, and back to the next technician

- Proof photos travel as their own `OfficeReport` attachments (HO's owed item), with `role` `photo`
  and the seal as attachment metadata. The office's signed receipt time is folded into the phone's
  record as the second clock.
- The next job at the same site (HV site id, HT `external.location_id`, or the office's own site key)
  names up to four as-left photos from the last visit as format 2 attachments, with an HU history
  line pointing at them. The brief shows them ("Last visit, 3 March: board as left") and speaks one
  line. They are fetched like any job attachment and removed when the job ends.
- **Exit tests:** contract fixtures for the attachment metadata, and the job-file attachment named
  from a prior visit. Headless phone-to-office-to-phone, using the existing office test seam.

## Acceptance

- An electrician on a guided job takes an as-found photo of a neighbour's DIY wiring and an as-left
  photo at the step that says so. The PDF shows both, sealed, with the honest wording.
- Changing a byte of either photo, or removing one, makes the verifier say so by name.
- The next electrician from the same firm opening the next job at that address sees the as-left
  photos before leaving the yard.

## Open questions for the owner

1. Decision 1: is a blurred proof photo acceptable? An organisation that needs unblurred photos turns
   the filter off for its phones, which loses bystander protection on every other photo too. Should
   there be a narrower exemption, like the wearer's own `capturePhoto()` shutter, for proof photos?
2. Is the office's receipt time enough as a second clock, or does an organisation want an
   independent timestamp authority (RFC 3161) as a later option?
3. Retention: how long does an organisation keep proof photos? Electrical work disputes can surface
   years later. Is that the office's policy, with the phone keeping only the current jobs?
