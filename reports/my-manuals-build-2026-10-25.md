# My Manuals implementation and private manual measurements — 2026-10-25

Implementation is in the working tree, alongside pre-existing unrelated changes. Signed development
build 565 (2026.10) is installed and launched on GiPhone; nothing has been uploaded to TestFlight.
Purchase offers remain disabled while qualification is
unfinished; verified My Manuals receipts are recognised and restore access.

## Implemented

- Personal entitlement grants `ownVaults`; professional work has a separate `fieldWork` capability.
  Limits derive from all live grants. Legacy unlock plus Personal keeps the personal quota.
- Settings → My Manuals: PDF preflight/import, photographed pages using the existing scanner and
  OCR/PDF components, signed publisher sets, source reader, retry, storage/page information,
  removal, subscription/restore/manage links and the answer-use switch. The camera route keeps
  the existing 40-page capture batch limit; longer books can be supplied as PDFs.
- One admission coordinator counts installed and unfinished holdings across import routes. Exact
  original-PDF page counts are checked before durable install, with reservations for capture.
  Corrupt inventory refuses additions. Failed replacement writes restore the previous baseline.
- Session-independent lookup, table, figure and show-source adapters reuse existing document
  storage/retrieval. Duplicate titles require a choice; stable labels preserve document identity.
  Staged images are consumed once and cleared when the conversation/source scope changes.
- Personal reads omit professional core files, procedures, prompt rules and edition behaviour.
  Organisation captures/managed packs stay excluded. Field/restricted/medical contexts cannot
  fall back to a personal library. Access is rechecked for source reopening and image attachment.
- Existing personal job captures count after a downgrade and can be read, reindexed or removed.
  Unfinished captures remain visible and removable. Files survive lapse; new reads require access.
- Monthly/annual StoreKit fixtures share the professional group at the lower level, with family
  sharing off and a one-week eligible trial. Prices appear only in the StoreKit configuration.

## Supplied private fixtures

Only anonymous counts and measurements are recorded here. Original PDFs, text, indexes and
checkpoints stay outside the repository. No document content is treated as implementation
instructions.

| Fixture | Physical pages | Original bytes | Text-layer pages |
|---|---:|---:|---:|
| Wiring | 466 | 5,302,699 | 288 |
| Repair | 7,595 | 230,658,024 | 7,587 |

The pair totals **8,061 pages**. Both original proposals (2,500 per manual / 6,000 total) would
exclude this ordinary workshop set and are rejected.

An isolated Release benchmark app uses the production extractor, OCR, tables, chunker, embedder
and document store on the connected iPhone Air, iOS 27.2. Preferences and telemetry are adapted;
this is a core pipeline measurement, not an end-to-end main-app acceptance test. The benchmark
used a separate app; the owner subsequently requested the main-app build 564 installation.
See [the runner](../Scripts/manual-library-benchmark/README.md).

The initial text-layer-table baseline completed Wiring in 23.3 seconds and Repair in 84.8 seconds,
with 294 and 14,339 chunks respectively. Queries returned four passages in 10–31 ms; this checks
retrieval operation, not answer accuracy. The combined SQLite files measured 43,295,872 bytes.
OCR read 178 Wiring pages and 8 Repair pages. These initial timings exclude pictured-table OCR.

The full pipeline run includes pictured-table recognition. A five-slot stress fixture uses the
Repair PDF once and Wiring four times: **9,459 pages** across five independent document records.
Repeated Wiring copies test capacity and retained-library cost, not document diversity. An
intermediate run stopped while reading fixture 4 because the helper was updated. No matching
benchmark crash or memory-kill report was found. The clean uninterrupted rerun completed all five
fixtures in 162.1 seconds: 45.6 / 96.1 / 10.7 / 5.0 / 4.6 seconds. The final SQLite files measured
45,997,432 bytes. Later repeated-input passes benefit from warm system caches and are not cold
measurements. See [anonymous raw results](my-manuals-benchmark-2026-10-25.json).

Large imports exposed temporary Objective-C/PDFKit/Vision allocations. Per-page autorelease
boundaries were added around PDF text/selection work, rendering and synchronous Vision OCR.
Memory samples are resident bytes at stage boundaries, not peak memory or the OS pressure
footprint. The full-pipeline samples reached approximately 6.8 GB and then plateaued; no reduction
is claimed from the cleanup boundaries. Thermal state rose during the run, and repeated scanned
input produced different OCR/chunk counts. Do not infer older-phone support or OCR equivalence.

**Provisional limits:** five manuals, 8,000 physical pages per manual, 10,000 pages total. This
admits the supplied 8,061-page pair and the measured 9,459-page five-slot stress set. These are
policy ceilings, not memory guarantees. Purchases remain disabled until older-device memory and
scan-quality acceptance; these measurements alone are insufficient to enable sale.

## Qualification remaining

- Qualify or revise the provisional page ceilings on older hardware and diverse scanned material.
- Default whole-module optimized main-app qualification remains separate from the signed Debug
  phone build; the simulator build and 388 distinct focused tests pass.
- Oldest-supported-phone memory/thermal behaviour; fully scanned large book; camera UI and source
  highlighting; kill/relaunch during actual app indexing; offline/local/cloud provider matrix.
- Actual App Store Connect products/group/levels/trial eligibility and sandbox purchase, renewal,
  refund/revocation, crossgrade and restore checks. Enable sale catalogue only after acceptance.

The supplied measurements do not establish OCR/table correctness or broad-device qualification.

## Validation evidence

The final source builds for iOS Simulator. The direct Xcode simulator XCTest agent ran 387
focused tests with zero failures in 55.9 seconds, covering entitlements, quotas, source revision
revocation, signed projections, capture contracts/storage, manual citations, settings/privacy
inventories, extraction/OCR recovery, tables, link lifecycle and removal. The normal Xcode app-host
launcher repeatedly stalled; direct execution uses the same built app module and test bundle,
without modifying production code. The privacy logging gate and whitespace checks pass.

The exact PDF-door integration check also passes: add one PDF through `PersonalManualLibrary.addPDF`,
confirm physical page 1 in the answer, then retry indexing without another quota slot. Its 12-test
library class passes; combined with the full focused run this is 388 distinct passing tests.

The owner requested a build bump and installation on the phone. Authoritative app, extension and
watch target versions were advanced together from 563 to 564 and the project regenerated.
The signed Debug device build succeeded, installation and launch succeeded, and `devicectl`
confirmed Avenkin 2026.10, bundle version 564 on GiPhone.

## Multi-manual chat selection — 2026-10-25

The home grid now has a managed My Manuals quick action. Its picker permits several books,
shows indexing status and offers Read/Manage manuals. A selection strip is available in the chat
and dock conversation page. The selected stable identities are stored on the conversation, so
switching chats restores its own set and new chats start without inheriting another chat's books.

Lookup searches each selected book with the existing evidence gate, interleaves attributed
passages under the existing result budget, and tells the model to cite each book/page and report
conflicts. Explicit document filters only narrow the selected set. Ambiguous page/figure requests
ask for a book; removed/unavailable selections ask for correction. Source memory and staged images
are cleared on selection changes. Named saved groups are deferred.

The product headline now says “Keep your manuals”. Entitlement and StoreKit fixture summaries
also avoid a fixed manual count. Usage details render the current entitlement's manual/page limits;
the shipped Personal quota remains five. This leaves copy ready for future capacity levels without
adding or changing subscription products in this update.

Selection validation: the final simulator test build succeeded. The direct XCTest agent ran 161
focused tests with zero failures, including paired workshop/electrical sources with conflicting
values, excluding an unrelated book, narrowing within the selected set, ambiguous page refusal,
missing-book refusal, chat switching, disk reload, voice idle-gap activity, source memory,
quick-action composition/editing, organisation presentation, and stable prompt prefixes.
The privacy logging gate and whitespace check pass. The subsequent wording change is included
in the signed device build; subscription capacity and purchase availability are unchanged.

At the owner's request, the My Manuals page no longer repeats Privacy and Terms links. Its
subscription status, purchase/restore controls, subscription management and provider disclosure
remain. The app's other legal/privacy surfaces are unchanged.

## Upload and management — owner follow-up

“Your manuals” now contains Upload manual (PDF, DOC, DOCX, MD/Markdown), photograph and signed-set
controls. Every saved manual offers a confirmed Delete action, also available by swipe. Word and
Markdown uploads retain the original bytes and create an on-phone paginated text reading PDF;
page limits apply to that copy, and citations explicitly say “reading copy”. Layout and images
are not preserved in the text copy, which the confirmation screen explains; use PDF for diagrams.
Both Read copy and Read original are available. Original uploads and generated PDFs are protected,
kept together through later additions/reindexing, and removed together with the search index.
Preparation cancels/cleans up when dismissed. No document conversion service receives the file.

DOCX reads the bounded Word document XML without external entities/resources. Legacy DOC uses
bounded MS-CFB stream chains and the MS-DOC text piece table; macros/embedded objects are never
executed. Damaged, unsupported and locked input fails with an actionable PDF/DOCX fallback.
Real, synthetic `textutil` Word exports are bundled as fixtures; no supplied private manuals were
added to the repository. The current simulator upload/source/removal tests pass, including all
three new formats, retained byte equality, independent book citations and freeing the quota slot.

The direct system XCTest agent lacked the built app's bundled procedures, causing one unrelated
procedure regression to fail. An isolated temporary runner with those same built resources fixes
that harness condition; the procedure probe passes without production changes. The combined
regression run uses this resource-aware runner.

Final combined validation: **583 tests passed, zero failures**, in 70.1 seconds using the isolated
resource-aware simulator XCTest runner. This includes the new upload tests and the original
entitlement, quota, signed-set, captured-manual, OCR/table, source/revocation, settings/privacy,
removal, quick-action and conversation suites. Simulator test compilation, privacy logging and
whitespace checks pass. The signed development build is 565; no store upload or sale enablement
is part of this change.

Build 565 device verification: signed Debug build succeeded; `devicectl` installation and launch
succeeded on GiPhone, and installed-app inventory confirms Avenkin 2026.10, bundle version 565.
It contains the multi-manual picker, neutral headline, removal of repeated legal links, upload
formats and Your manuals management controls described above. The initial build 564 was replaced
by this update. Manual UI/camera/provider and older-device qualification listed above remains.


## Build 566 — personal purchase UI and separate services

The owner clarified that My Manuals and Field Assist have separate subscriptions and access.
This supersedes the original shared-group tier ladder and shared `ownVaults` grant above.
My Manuals now grants `personalManuals` only. Professional subscriptions/licences retain
`fieldWork`, `ownVaults` and their existing manuals. Both receipts remain recorded independently;
Personal does not set the Field Assist purchase flag, and either service can expire independently.
The local StoreKit fixture places Personal monthly/annual together in a separate `my_manuals`
group. No App Store Connect changes or external publishing have been performed.

Personal uploads use a separate manifest gate; received sets use a `personal-` identifier and
manual-only projection so receiving the same publisher source in both services cannot overwrite
the other service's copy. Professional manifests and job captures are excluded from the personal
library and quota. Personal documents are excluded from Field Assist's vault manager, selection
and exports. Holding Field Assist does not remove the Personal quota.

Your manuals exposes Upload manual before purchase; a user without Personal sees the real
monthly/annual StoreKit offers, and a verified purchase/restore resumes the requested action.
The external Manage subscription substitute, fixed main-page capacity, Field Assist redirect/
upsell and entire preparation-placeholder section have been removed. Missing store products
show a specific error and retry action. No synthetic products or entitlement bypass were added.
Store offers are enabled in the app at the owner's request; the older-device/page-quality
qualification limitations above remain and are not established by enabling the purchase surface.

Build 566 compiled for phone/simulator, installed and launched on GiPhone, and installed-app
inventory confirmed 2026.10 (566). The broad 589-test run had one invalid invented professional
fixture; its anti-fabrication/citation text was corrected. The following focused run passed all
118 policy/library/recovery/import tests; its additional native StoreKit integration test failed
under the direct runner, which lacks a registered app-host StoreKit identity. The system runner
reported StoreKit configuration-write errors for its `com.apple.dt.xctest.tool` identity. This is
recorded as a harness limitation, not a successful catalogue check.


## Build 567 — upload before purchase and App Store metadata

Upload manual now groups file selection and publisher links/codes. The standalone Receive row is
removed. Choosing a PDF/Word/Markdown file opens the system picker without a subscription redirect;
the protected local preview validates the Personal page ceiling before purchase. The confirmation
shows the Personal offer/restore only when access is missing, and saving/indexing still rechecks
verified Personal access. Monthly is the current sale offer; annual receipts remain recognised.
The local monthly fixture was updated to the owner's requested price; prices remain store data.

Read the owner's App Store Connect page: product ID matches the app, monthly duration is correct,
family sharing is off, and an introductory offer says “Free for the first week” across the selected
173 regions. The subscription and group had no customer-facing localization. Saved English (U.S.)
subscription name “My Manuals”, description “Your manuals, asked by voice with page-cited answers.”,
and group display name “My Manuals” with the Avenkin app name. Verified those saved rows. No price,
financial agreement or review submission was changed. The review screenshot remains unfilled.
Apple notes metadata can take up to one hour to propagate to sandbox; live phone purchase loading
and a verified real/sandbox transaction have not been claimed successful.

A separate temporary, minimal SwiftUI app-host test uses the same local StoreKit configuration.
Xcode's normal test launcher ran its native StoreKit integration test successfully: monthly product
and professional product both load, subscription groups differ, and Personal's offer is free for
one week. xcresult reports one executed/passed test, zero skips/failures. No product was purchased.
The repository integration test explicitly requires the proper Xcode app-host launch and skips in
the direct resource runner; policy and source-isolation tests do not depend on StoreKit services.

Final simulator test compilation and signed Debug phone build pass. The focused resource-aware
runner executed 119 tests: 118 passed, one app-host StoreKit test explicitly skipped, zero failures.
The independent native StoreKit app-host test passed with zero skips. Privacy logging and whitespace
checks pass. GiPhone installation succeeded; installed-app inventory confirms Avenkin
2026.10, build 567. Automatic launch was refused because the phone was locked. The final page-ceiling preflight change is included in the installed build.
Professional capture's unused quota plumbing was removed from the feature diff; its original
independent implementation is retained. Unrelated working-tree changes are excluded from the PR.
