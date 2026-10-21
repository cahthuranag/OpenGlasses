# Photographed manuals

On an open Field Assist job, choose **Photographed manuals → Photograph a manual** on
the Job screen or in Custom Vaults. The phone's document camera saves pages in capture order.
Photograph the reference book; customer paperwork and service logs belong outside this flow.
Saving starts on-device text recognition. The completion message says **saved locally**.

The request belongs to the job, unit and organisation selected before the camera opened.
Changing that context cancels an unsaved request. Once pages have been saved, recognition
continues against that original job. It never attaches a book to whichever job happens to be
open when recognition finishes.

A photographed manual is an unreviewed reference. Answers retain the original job/date and
the warning to check recognised text against the page. Page 1 means the first photographed
page; a detected printed number is an extra label. A captured book without a confirmed model
answers only on its original job/unit. A confirmed model permits reuse on the same exact model
within the same organisation, enrolment and vault.

Use **Resume recognition** after unlocking or reopening the app. A fully staged capture resumes
from its saved PDF and redacted text checkpoints. A scan interrupted before all images were saved
is labelled incomplete and must be discarded and photographed again. No incomplete book is
published into search. **Forget** removes every revision and suppresses late recognition results.
The forget action remains available when policy disables capture or lookup.

Recognition redacts detected secrets in text and human metadata before saving them. The page
images themselves retain the photographed contents. These are local protected files, excluded
from device backup. Pool approval is unavailable until a compatible Office review round trip is
supported; capturing a book does not approve it for the organisation's pool.

## Delivery

Organisation-owned books retain their original job when queued. A queued book is not an Office acceptance: the signed receipt must acknowledge both the saved PDF and recognised text. The production sender currently waits for compatible Office support; the signed in-memory peer is test coverage. Personal captures remain local.

Ordinary reports to the Office may include saved manual files within the channel’s measured attachment budget. Messages carries recognised text only; customer reports carry neither manual file. The report says which files stayed on the phone. Saved manuals also offers explicit page/text sharing. A later policy change is checked again before a composer opens.

## Reviewed copies

An Office-approved copy carries the named technician, original job/date and named reviewer/date, together with the scan warning. It replaces local search evidence only after its authenticated signed archive is installed and indexed Ready, and only for the exact originating capture revision and bundle digest. Existing citations still open the saved original PDF. Matching titles or text, assignment receipt alone and failed indexing replace nothing. The private Office review/pool service and live crew round trip still require qualification.

## Qualification record

The current limits are provisional engineering defaults: 40 pages, 4 MiB per encoded image,
512 MiB local source storage, and 32 MiB reserved free space. Images use a maximum edge of
2200 pixels, reduced to 1650 at serious/critical thermal state. Limits are checked before
publication; a disk or protected-data failure leaves resumable work or an explicit incomplete
capture, rather than a searchable partial book.

Headless checks cover ordered physical pages, an empty failed page, language fallback,
redaction, interruption/restart, immutable retakes, quota/free-space failures, journal-write
failure, erasure during recognition, real JPEG/PDF encoding, and retained citation files.
On main build 502, 190 focused simulator tests pass (one skipped, zero failures), covering the production store/catalog/factory/tool routes, request lifecycle, signed in-memory delivery receipts, composer policy changes, erasure, and a reviewed signed-archive round trip onto a second simulated phone.

The following physical qualifications have **not been run**. These defaults are not measured
shipping limits until the results are recorded here:

| Pass | Record before release |
| --- | --- |
| Oldest supported phone, real forty-page binder | Device/OS, elapsed capture/OCR/index time, peak memory, thermal states |
| Glare, small print, diagrams, mixed page orientation | Wrong/missing text, confidence counts, page and figure verification |
| Cancel, lock/unlock, background, process termination and relaunch | No wrong-job publication; complete staging resumes; incomplete staging is labelled |
| Low disk and protected-data failures | No half bundle or index; retry/discard remains possible |
| Signed Office test peer | Early capture plus later job report, exact retries and required-file receipts |
| Office review and second phone (private FX23 dependency) | Named approval, scan warning, exact Ready supersession and retained old citations |
| A ruled table on a binder page, under shop lighting | Look up a cell by voice: the "read from a picture" read-back names the photographed page, uncertain cells are refused, "show me the table" outlines it; record clear cells' least word confidence to set the photographed-table floor (provisionally the PDF's 0.5) |
