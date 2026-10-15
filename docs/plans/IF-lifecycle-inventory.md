# Plan IF P0 — lifecycle and retrieval inventory

Inventoried 2026-10-11 against merged plan commit `36855b6df` (build 494). P0 defines the source
and report contracts and portable verifiers. Everything below identifies a later wiring gate;
**none of these existing paths already manages photographed manuals.**

## Sources, derived copies and erasure order

| Copy/boundary | Existing seam | Required IF wiring / phase |
|---|---|---|
| Protected ordered images, redacted checkpoints, sealed revisions, revision selection, supersession/tombstone journals | New CapturedManualStore; no equivalent current store | P1: register SensitiveStore entries with complete protection, no backup, thirdPartySubject linkage, subject/full deletes; freeze encoder/language/image order before OCR |
| Index and captured/document linkage | DocumentStore.ingest/ingestWhole, forget(documentId:), forget(documentId:inNamespace:), pageTexts | P1 linkage; P2 explicit page ranges, per-revision namespace and retraction; tombstone before forgetting so recovery cannot recreate rows |
| Staged export copies | StagedExportCoordinator; subject walk starts with stagedExports | P1 store ownership; P4 revoke every captured export by source revision and original session before deleting source |
| Immutable queued evidence | OfficeReportEvidenceStore, OfficeReportService ledger/files, OfflineQueue | P4 pin exact source bytes and explicit capture/session/document links, never regenerate published hashes; erase/revoke derivative evidence before source |
| Final and staging text/metadata person matching | SubjectErasureCoordinator.eraseDocuments currently searches passages, capped at 500 | P1 capture-owned exhaustive match over redacted text and metadata, including unindexed/failed pages; queue JSON digest search is insufficient. Images are not claimed to identify people |
| Document subject | SubjectErasureCoordinator.eraseDocuments directly forgets document ID | P1 resolve capture/revision/document map and cancel assembler; P2 retract namespace before source unlink; forget all retained revisions when capture-level forgetting is requested |
| Original thread/session subject | SubjectErasureCoordinator.eraseDocuments does nothing for conversationThread | P1/P2 resolve original session linkage; settle scanner request and cancel assembly/indexing; erase capture images/text/checkpoints/journals, exports and queue entries through links |
| Remote copies | ErasureReceipt.unsupported / queued tombstones; Office report v1 has no delete/refusal message | P4 report honest remote pending/unsupported, never remote completion. Mailbox withdrawal is not deletion from Office's store |
| Restore / late callback | ErasureLedger records replayable logical subject coverage | P1 monotonic tombstones checked before each write/yield/commit/recovery; do not remove erasure state with source bytes. P2/P5 supersession survives restart/reimport |

Relevant owners: `Services/Privacy/DataStoreRegistry.swift` (SensitiveStore and every record),
`SubjectErasureCoordinator.swift` (order, eraseDocuments, eraseConversations, eraseQueue),
`ErasureLedger.swift` (replay), `Services/RAG/DocumentStore.swift`,
`Services/OfficeSync/OfficeReportEvidenceStore.swift`, `OfficeReportService.swift`.

Do not register an invented production store in P0: the registry owner/delete APIs must exist and
be tested in P1. Its registry and subject-erasure tests intentionally require actual owners and
receipt coverage. Index before source, after durably installing cancellation/tombstones.

## Departure and ownership

`OrgDepartureService.Seams` separates immediate `eraseContent` from owed `eraseRecords`, waits
until no active job, and settles on accepted records or eraseBy. AppState wires it in
`OpenGlassesApp.configureOrgDeparture()`.

Current `eraseContent` removes organisation vaults, learning candidates/entries/corpus, upcoming
jobs, job attachments/updates, exports and turn traces. It does not find captured manuals.
Current `eraseRecords` deletes original sessions and queue entries by sessionId, calls
`officeReports.forget(recordIDs: Set(ids))` and clears Office evidence. A capture's recordID is
captureID, **not** sessionID, so that call will miss it without the persisted linkage. Current
outstanding accounting adds `OfficeReportService.outstanding(recordIDs:)` for session IDs; a
book likewise needs mapping to original sessions. Empty queues/local sink completion do not
prove Office acceptance.

P1 keeps ownership immutable and suppresses eligible lookup on departure. P4 counts pending
capture reports through their original session, keeps them locked under settlement policy,
then removes them and all evidence via exact links. Another organisation or new enrolment
cannot inherit them. P5 preserves approved provenance without widening local scope.

## Every retrieval gate (P2 acceptance checklist)

| Route/gate | Current assumption | Required IF change |
|---|---|---|
| FieldSessionService.retrievalNamespaces | Vault manuals plus published learning namespace (HIPAA only suppresses learnings here) | Add only current, policy/ownership/model-eligible, unsuperseded capture revisions; HIPAA/off gates all capture namespaces |
| retrievableCorpus | manuals = manifest.hasDocuments && vault namespace has rows; plus learnings | Count captures separately; captured-only/out-of-vault books are a reference corpus |
| manualPassagesContext / manualRetriever | Uses shared makeRetriever factory and corpus.any | Keep one factory, add scope checks at query/availability boundaries and preserve both notes after prompt bounding |
| makeRetriever(documentIds:) | A title filter restricts to source.manual; learning namespaces bypass IDs | Include matching captured document IDs in reference title search; never silently drop captured books |
| ManualLookupTool.execute | Rejects unless manifest.hasDocuments or corpus.learnings; requires corpus.any | Captured-only availability, title filtering, reference classification |
| EquipmentLookupTool.manualFallback | Uses shared corpus.any/manualRetriever and confirmed equipment context | Include captures while respecting stated exact identity; sibling vault match cannot relabel a book |
| FieldSessionService equipmentScope passage/model support | One closure requires manifest.hasDocuments | Include eligible capture evidence even when vault has no manufacturer manual/model section |
| FieldSessionService model covered / manual availability paths | Additional hasDocuments checks beyond corpus factory | Audit every guard; no capture eligibility from a global ID or a near/partial match |
| VaultRetriever selection / budget retention | Requires source.manual for document evidence, otherwise teamLearningOnly; holds a best manual through prompt bounding | A distinct capture reference source must remain document evidence and retain capture attribution + scan warning; learning-only stays reserved for learnings |
| Source provenance | recognisedFromScan only on source.manual and ledger sourceType vault_document_ocr | Carry exact source identity, original-job/date note, page map and both disclosures independent of vault ledger |
| Namespace availability | Vault removal journal for manual; row existence for learning | Capture journal/current revision/policy/scope plus row existence; retraction during a turn blocks stale evidence |

Owners: `Services/FieldAssist/FieldSessionService.swift` (equipmentScope, manualPassagesContext,
retrievableCorpus, retrievalNamespaces, makeRetriever and all hasDocuments guards),
`Services/NativeTools/ManualLookupTool.swift`, `EquipmentLookupTool.swift`,
`Services/Vault/VaultRetriever.swift` (RetrievalSource, outcomes, prompt bounding).

P2 tests must run those actual three routes at production chunk/prompt defaults, not a second
retriever made for a fixture. Required cases: captured-only with no declared vault manual,
empty/short pages, footer numbering, title filter, exact model on another unit, different
model/org/enrolment/vault, same-session unbound unit, later policy narrowing, capture+learning,
learning-only, retained disclosures when the budget keeps only a capture, and mid-turn retraction.

## Citation/page and approved import boundaries

`FieldSessionService.resolveCitation(_:)` currently requires a manual citation and active vault;
`manufacturerPDFURL`, manifest/ledger resolution and `manualPageSheet(for:)` find baseline or
ledger sources. `ManualPageSheetModel` and `ManualFigureSheet` label the file as manufacturer's
PDF, and fallback text pages come from DocumentStore's parsed/chunked numbering.

P2 adds a source-bound citation/page model and digest-checked resolution by
captureID/source revision/bundle digest/physical page. P3 routes voice and chip taps to the
photographed-page sheet with capture count/printed-number labels. Retakes and supersession
leave old citations bound to the old PDF; forget/erasure returns unavailable, not a replacement.
A failed OCR page remains physically viewable without manufactured text evidence.

`OfficeManualAssignment` names an archive, not capture origins. `VaultDocument` currently has
file/title/kind/source/source_url only. `VaultImporter` marks scanned PDF extraction as OCR, but
plain Markdown loses that warning; ledger OCR counts/source hash do not carry captured origins
or reviewer attribution. `OfficeManualVaultHandoff` connects installation and indexing state.

P5 validates the proposed signed per-document extension from captured-manual contract §6,
retains it in ledger/retrieval/page models and invokes exact-origin supersession **after Ready**.
Assignment receipt, unrelated archive, matching title/model/text digest and failed indexing
must leave captured retrieval alone. Legacy optional-absent metadata remains supported. Signed
archive replay cannot resurrect tombstones. The private FX23 peer is an external release gate.

## Capture and delivery boundaries still unbuilt

P1: store/assembler/checkpoint/limits/languages/redaction, file protection, atomic sealed commit
and failure/cancellation tests. P3: single-flight frozen request, VisionKit adapter, tool and tap,
job switch/end/error/cancel settlement, original-job commit after saved scan, job deletion and
unsupported-camera handling; no reads of whichever job is active at callback time.

P4: extend real DeliveryRequest.Payload, QueuedOp.OpKind, queue dispatch, audit and UI labels,
audience partition and measured attachment budgets. OfficeReportSink currently intercepts only
work records/parts/addenda. Never add an enum and let a capture reach a default `.done` sink.
Extend matching signed receipt/revision handling and departure accounting together; retain both
exact file bytes until fully accepted. A separate early capture must not become required
ordinary-job evidence or block job acceptance. `jobOnly` evidence can travel with a compatible
peer; reviewToPool stays disabled until P5's approved provenance round trip is supported.
