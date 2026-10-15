# Photographed manual contract — draft v1 (Plan IF P0)

This defines an immutable source bundle, its standalone signed Office report, and the proposed
reviewed-vault provenance extension. Swift `CapturedManualContract` and Go `capturedmanual`
validate the same fictional golden corpus. The report validators understand the extension;
**there is no capture UI, store, OCR assembler, indexer, queue producer, peer negotiation or
Office intake/review implementation in P0.** Live phone/Office validation is owed.

A technician photographs a paper manual on the phone. It is their statement, recognised on
device, not approved manufacturer text. Recognition neither understands a wiring diagram nor
certifies numbers. Source images are unchanged by text redaction. Only an explicitly authorised
Office reviewer may approve a pool copy. A signed transport receipt does not approve publication.

## 1. Immutable identity and exact bytes

A bundle has exactly `manifest.json`, `text.md` and `pages.pdf`. A local store may retain ordered
normalised images and redacted checkpoints outside the sealed bundle. Its path is
`Documents/CapturedManuals/<captureID>/<captureRevision>/`; manifest values never choose a path
on a receiving system. All identifiers are checked before a local path is constructed.

`captureID` identifies a book photographed on one originating session. `captureRevision` is a
positive source revision. A retake/reorder/re-encoding or metadata correction creates a new
source revision. Published bytes are never changed. A local journal selects the current revision
and retracts earlier revisions from live retrieval while retaining their files for old citations.

The bundle identity is lower-case hexadecimal SHA-256 of **exact canonical manifest bytes**.
There is no bundle digest in the manifest itself. The manifest binds both final file digests,
metadata, recognition configuration and page map. A text digest is only a review similarity
hint: different diagrams with identical recognised text remain distinct bundles.

The manifest has the members below in exactly this order. Every member is required, including
empty strings, `false` and empty arrays. No unknown, duplicate, omitted or null member is valid,
at any depth. No whitespace outside strings or trailing newline. Integers use plain decimal
(no sign on zero, fraction or exponent). Boolean spelling is `true`/`false`.

Strings are valid UTF-8, without Unicode normalisation. Quote and backslash are escaped as
`\"` and `\\`; control scalars U+0000 through U+001F use lower-case `\u00xx` (never short
`\n`/`\t` escapes). All other scalars are literal UTF-8, including slash, `<`, `>`, `&`, U+2028
and U+2029. Display metadata below forbids U+0000–001F and U+007F anyway. Unicode display
strings are distinct byte strings; a verifier does not re-encode before hashing or signing.

## 2. Manifest schema

| Member | Rule |
|---|---|
| `version`, `kind` | `1`, `avenkin.captured-manual` |
| `captureID`, `captureRevision` | Stable capture identifier and positive source revision |
| `sessionID` | Original session identifier, frozen before camera presentation |
| `jobReference` | Original display reference, up to 120 UTF-8 bytes; empty allowed |
| `jobID`, `jobRevision` | Office job identifier/revision, both present or empty string and `0` |
| `vaultID` | Original vault identifier |
| `ownershipScope` | `personal` or `organization` |
| `organizationID`, `enrolmentID` | Identifiers for organization scope; both empty for personal |
| `unitID` | Original active-unit identifier; empty if absent |
| `statedModel` | Safe equipment model as stated, up to 160 UTF-8 bytes; empty allowed |
| `confirmedModelToken` | Normalised exact, confirmed model/alias, up to 160 UTF-8 bytes; empty means unbound. Nonempty requires `statedModel` |
| `serial` | Original VisitedUnit serial, up to 160 UTF-8 bytes; empty allowed, never a retrieval key or prompt field |
| `title` | Redacted display title, 1–240 UTF-8 bytes |
| `author` | Redacted technician display name, up to 160 UTF-8 bytes; empty allowed |
| `capturedAt` | Frozen positive Unix UTC seconds, informational; never regenerated on restart |
| `capturePolicy` | `jobOnly` or `reviewToPool`; `off` cannot create a sealed revision |
| `poolIntent` | `jobOnly` or `reviewToPool`. Pool intent requires organization scope and capturePolicy `reviewToPool`; it does not itself grant the dedicated capability |
| `encoderVersion` | Identifier pinning image/PDF encoding and metadata settings for this revision |
| `pageCount` | 1–256, equals page-map length and parsed physical PDF count |
| `ocrPages`, `failedPages` | Nonnegative, each at most pageCount, summing to pageCount; failed pages stay viewable |
| `lowConfidencePages` | Count of pages whose confidenceMilli is below 500, including failed pages |
| `recognitionLanguages` | Ordered actual supported Vision identifiers, 1–16 distinct identifiers, preference order then English |
| `recognitionFallback` | True when an unsupported preference needed documented automatic-detection fallback; UI discloses it |
| `pages` | Capture-order page map (§3) |
| `redactions` | Pattern names/counts only (§4), at most 64 entries, ascending ASCII pattern name with no duplicates |
| `textSHA256`, `textBytes` | Lower-case SHA-256 of exact redacted text.md; 1–8,388,608 bytes |
| `pdfSHA256`, `pdfBytes` | Lower-case SHA-256 of exact image-only pages.pdf; 1–134,217,728 bytes |

An identifier is 1–80 ASCII letters/digits/dot/underscore/hyphen, excluding `.` and `..`.
Positive revision/time integers are at most 2^53−1. Display fields are not identifiers or paths.
No raw nameplate text is present. The confirmed token is not `EquipmentIdentity.modelToken`
when that points to a near/partial vault match: binding uses the stated `unitKey` or an explicit
exact alias. The application, rather than the manifest, confirms that identity.

These are **wire ceilings, not measured shipping allowances**. P1 injects smaller local page,
pixel, stored-byte and free-space limits. P3 measures limits on the oldest supported phone.
A manifest never raises an independently configured recipient's limits. Parse/count the PDF
under those limits before calling the portable verifier's `pdfPageCount` input; taking that
count from the manifest would defeat its check. A digest alone does not make malformed PDF
bytes safe to display. Per-image bytes/hashes bind staging checkpoints; validators of the
sealed three-file bundle do not claim to open those staging images.

## 3. Authoritative page map

Each page object has these members in order:

| Member | Rule |
|---|---|
| `index` | Exactly 1, 2, …, pageCount in array order |
| `imageSHA256`, `imageBytes` | Exact normalised image's digest and 1–4,194,304 bytes |
| `textOffset`, `textBytes` | Zero-based UTF-8 byte offset/length of this page's redacted body in exact text.md |
| `confidenceMilli` | Mean recognition confidence quantised to integer 0–1000 (floor of clamped mean × 1000) |
| `printedPage` | 0 if unknown; otherwise 1–9999. Supplementary, never the capture/PDF index |
| `ocrStatus` | `recognized` or `failed`. Failed requires empty body, confidence 0 and printedPage 0 |

`text.md` is the concatenation, for every page (including an empty/failed page), of:

```
## Page <capture index>\n\n
<exact redacted body>\n\n
```

Here `\n` denotes a literal LF byte, not two characters. Offsets exclude the generated header
and separator. A body may include an OCR footer such as `Page 41`; it cannot reset capture
numbering. Empty bodies have a zero-length range. Ranges are ordered, nonoverlapping, within
the text bound and on valid UTF-8 boundaries. Validation checks **every header and separator**
and accounts for all bytes. It refuses extra text outside the page bodies even with a correct
file digest. The reader failure on one page does not fabricate body text or discard other pages.

P2 ingests explicit ranges and capture indices into the chunker. Production-default short pages
may not merge, overlap may not cross a page, and empty pages must retain later physical indices.
A generic Markdown parser is not an authoritative parser for this contract.

## 4. Redaction, scope and local lifecycle

Each redaction object has `pattern` (identifier), then `count` (1–1,000,000). Only aggregate
pattern names/counts leave this boundary, never matched values. The P1 assembler redacts
recognised bodies and user metadata **before** any checkpoint, manifest, export or index write.
Image bytes are not redacted. Do not photograph service logs or customer paperwork.

The verifier's `expectedScope` comes from independently established current ownership/vault
context. Matching metadata never authorises cross-organisation or later-enrolment reuse.
Within the same scope a confirmed model token permits reuse on another unit of that exact
model. An unbound capture is restricted to its original session/unit. Serial and nameplate
text never enter retrieval prompts. The application checks ownVaults, HIPAA, current profile
and departure state separately, at presentation/recovery/commit/retrieval/send boundaries.

`off` hides existing namespaces and blocks new capture/recovery/send without silently deleting
saved records. `jobOnly` permits ordinary job evidence but forbids pool review. A policy may only
narrow a queued capture. It suspends/withdraws a published pool operation or produces a new
source manifest and delivery operation with job-only intent; it never rewrites a published digest.

Protect final, staging, journal, checkpoint, index, export and queue copies according to the
store registry and exclude them from backup. Before erasing source files, durably tombstone
capture/revision identity and cancel assembly/indexing/queued producers so a late callback or
restart cannot recreate them. Document erasure resolves capture/document linkage; original-thread
and job erasure resolve session linkage; person erasure searches saved redacted text and metadata,
not merely the opaque queue JSON. Images have no per-person recognition claim. Remote copies
get an honest unsupported/pending receipt, never an assertion of remote deletion.

## 5. Standalone signed report extension

Compatibility name: **`captured-manual-v1`**. P4 must enable it only with an explicitly selected
compatible opt-in peer. No negotiation is implemented by P0; merely recognising the new enum
on this phone is not evidence that an Office can receive it. Old peers refuse unknown kinds.
An unavailable/old peer leaves the operation pending, and capture operations never fall through
to a local sink returning success. Personal captures without an authorised Office stay local.

The [office report](office-reports.md) exact-byte signature/envelope remains version 1 with:

- `recordKind: capturedManual`, `recordID: captureID`;
- record bytes: the canonical capture manifest, recordSHA256 = bundle identity;
- `revision`: positive **delivery revision**, independent of source captureRevision. A new send
  has a new operationID/reportID and higher delivery revision; retries reuse exact signed bytes;
- organization/enrolment and original jobReference/jobID/jobRevision equal the capture's frozen
  metadata. Office/phone transport identities come from the freshly verified binding;
- `transcript: none`;
- exactly two required, Office-only attachments, one role `capturedManualPDF` with mediaType
  `application/pdf`, one role `capturedManualText` with mediaType `text/markdown`. Their sizes
  and hashes equal the capture manifest. Different files, missing/optional evidence or a
  customer audience are refused. Names (`pages.pdf`, `text.md`) are display-only;
- evidence bytes in outbound `records/attachments/<sha256>`, never reverse inbound `bulk`.

Verify the report signature and expected binding, exact record and attachment-manifest bytes,
canonical capture schema and correlation, then **both actual evidence files and page map**
before marking a whole capture committed. `Report.Carries`/`recordAgrees` checks correlation;
`capturedmanual.Validate`/`CapturedManualContract.validate` checks actual files/page map. Neither
alone replaces the other. Human reference Unicode that cannot fit the existing report's
printable ASCII rule must receive an explicit recoverable delivery result; never silently
rewrite a frozen reference or loosen the report contract to make it fit.

Receipts use existing domains and bind exact envelope/record/manifest hashes and recipient.
`evidencePending` means Office has the record but still owes required files. For this two-required
manifest `recordAccepted` with any outstanding attachment is impossible; both files committed
means `fullyAccepted`. Only that matching signed receipt advances standing to Office accepted.
Transport synchronisation or connection success is never delivery. There is no signed refusal
in report v1; malformed/rejected intake produces no acceptance receipt.

Early intake may await its job; this is an **Office requirement**, not built intake. Later job
reports reference captureID, source revision, bundle digest and known standing, independently of
required job-report evidence. Pending large captures must not block ordinary job acceptance.
Intake reconciles repeated references by exact capture/revision/digest; another digest at the
same source revision is a conflict, never an overwrite. The Office retains approved/receipted
bytes independently of mailbox withdrawal. Retakes/merges do not auto-dedupe by OCR text.

## 6. Proposed reviewed-vault provenance (P5 interface, not active)

Inside each signed archive's `VaultDocument` entry, add optional `captured_manual`:

```
{
  "version": 1,
  "origins": [{"captureID": "fixture-capture-1", "captureRevision": 1,
               "bundleSHA256": "<64 lower-case hex>"}],
  "pageCount": 3, "ocrPages": 2, "failedPages": 1, "lowConfidencePages": 2,
  "pages": [{"index": 1, "originIndex": 0, "capturePage": 1, "printedPage": 41}],
  "organizationID": "fixture-organisation",
  "technician": "Fixture technician", "jobReference": "JOB-1042", "capturedAt": 1800000000,
  "reviewerID": "fixture-reviewer", "reviewerName": "Fixture reviewer", "approvedAt": 1800000120
}
```

This illustrative shape is not a valid complete three-page example; `pages` must cover every
physical source PDF page. Origins are unique by captureID/source revision/digest; originIndex
is zero-based into that list; capturePage is positive in that origin's captured page range.
Counts obey §2. An origin's complete source manifest/page count must be authenticated or retained
at intake to validate the map. Merged manuals name every exact originating revision they replace.
The signed archive bytes bind metadata together with extracted text and source PDF; neither a
loose metadata sidecar nor an unauthenticated assignment can introduce an origin or approval.

P5 must validate/retain this extension through archive verification, manifest, ledger, page
mapping, Ready indexing and retriever provenance, on a second phone. It sets source type
`vault_document_ocr`, retains the scan warning and adds the named technician/job/date/approval
attribution. Existing archives without the optional extension remain valid and grant no source
supersession. Malformed present metadata must fail rather than be silently ignored as legacy.

Only a verified, installed, indexed **Ready** document naming the exact captureID, source revision
and bundle digest supersedes that local revision. Persist lineage and retract its live namespace
atomically/idempotently. Retained source files and historical citations remain; an old citation
binds captureID/revision/bundleSHA256 and capture-order page and checks saved PDF hash. It opens
with `Photographed manual · page N of M photographed`, never `Manufacturer's document`.
Title, model, text-digest similarity, assignment receipt and failed indexing supersede nothing.
Tombstoned/forgotten/superseded revisions cannot be reindexed after restart or archive replay.
The private FX23 intake/review/pool remains an external dependency.

## 7. Portable checks and fixtures

All fixtures are fictional, public and unauthorised. The PDF is a deterministic blank three-page
test file, not live camera/recogniser output. Ordered image hashes are fictional staging hints.
The text exercises Unicode, a printed footer, a failed empty middle page and low confidence.

`captured-manual-v1.json`, `…text-v1.md`, `…pages-v1.pdf`, `…digest-v1.txt` and
`…negative-v1.json` are made by `capturedmanual.Fixtures()`. The shared negative corpus includes
closed-schema/canonical failures, paths, ownership, intent, counts, integer overflow, ranges,
confidence, languages, redaction summaries and wire bounds. Both implementations must refuse
all of them. Tests also alter text/PDF bytes, scope, physical PDF count, UTF-8 ranges and headers.

`captured-manual-report-v1.json`, `…evidence-v1.json` and `…receipt-pending-v1.json` /
`…receipt-full-v1.json` are made by `officereport.Fixtures()` using the existing check-in fixture
keys. Source revision 1 and delivery revision 4 are intentionally different. Tests require both
files, original scope/job/capture identity and the exact signed receipt; wrong report receipts
and impossible required-file counts are refused. Legacy report fixtures stay byte-identical.

```
go -C Transport/mobile-core test -tags noassets ./capturedmanual ./officereport
python3 Contracts/tests/test_manual_contracts.py
CAPTURE_WRITE_FIXTURES=1 go -C Transport/mobile-core test -tags noassets ./capturedmanual
REPORT_WRITE_FIXTURES=1 go -C Transport/mobile-core test -tags noassets ./officereport
```

The lifecycle inventory and unbuilt wiring gates are in
[IF lifecycle inventory](../docs/plans/IF-lifecycle-inventory.md).
