import Foundation
import XCTest
@testable import OpenGlasses

@MainActor
final class CapturedManualDeliveryTests: XCTestCase {
    private typealias F = OfficeCheckInFixtures
    func testMeasuredManualPartitionReservesOtherEvidenceAndDeniesCustomerCopies() {
        let email = AttachmentBudget(channel:.email,perFileBytes:100,totalBytes:140,carriesFiles:true)
        XCTAssertEqual(email.partitionManual(pdfBytes:80,textBytes:10,reservedBytes:40,officeAudience:true).attached,[.pdf,.text])
        let text = email.partitionManual(pdfBytes:80,textBytes:10,reservedBytes:60,officeAudience:true)
        XCTAssertEqual(text.attached,[.text]);XCTAssertEqual(text.omitted,[.pdf])
        XCTAssertTrue(text.note?.contains("stayed on this phone") == true)
        XCTAssertTrue(email.partitionManual(pdfBytes:1,textBytes:1,officeAudience:false).attached.isEmpty)
        XCTAssertTrue(email.partitionManual(pdfBytes:80,textBytes:nil,officeAudience:true).attached.isEmpty)
        XCTAssertTrue(email.partitionManual(pdfBytes:80,textBytes:10,reservedBytes:Int.max,officeAudience:true).attached.isEmpty)
        let messages = AttachmentBudget(channel:.messages,perFileBytes:100,totalBytes:140,carriesFiles:true)
        XCTAssertEqual(messages.partitionManual(pdfBytes:1,textBytes:10,officeAudience:true).attached,[.text])
        for channel in [DeliveryChannel.endpoint,.whatsapp,.telegram] {
            XCTAssertTrue(AttachmentBudget.standard(for:channel).partitionManual(pdfBytes:1,textBytes:1,officeAudience:true).attached.isEmpty)
        }
        XCTAssertTrue(AttachmentBudget.standard(for:.messages,canSendAttachments:false)
            .partitionManual(pdfBytes:1,textBytes:1,officeAudience:true).attached.isEmpty)
    }
    func testStandaloneBookWaitsForExactSignedRequiredFileReceiptAndNeverFallsThrough() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let sourceBytes = try F.data("captured-manual-v1")
        var fields = try F.fields(sourceBytes);fields["captureRevision"] = 7
        let m = try JSONDecoder().decode(CapturedManualContract.Manifest.self,from:JSONSerialization.data(withJSONObject:fields))
        let held = try F.held()
        let transport = OfficeManagedFolderMemoryTransport()
        let binding = try F.fields(F.payload("office-check-in-binding-v1"))
        let identity:[String:Any] = ["organizationID":held.organizationID,"enrolmentID":held.enrolmentID,
            "officeID":held.officeID,"generation":1,"officeTransportID":try XCTUnwrap(binding["officeTransportID"]),
            "officeApplicationKey":held.officeApplicationKey.base64EncodedString(),"phoneApplicationKey":held.phoneApplicationKey.base64EncodedString()]
        try await transport.startFolders(bindingJSON:String(decoding:JSONSerialization.data(withJSONObject:identity),as:UTF8.self),policy:"automatic",lanHint:"")
        let evidenceBytes = [try F.file("captured-manual-pages-v1",extension:"pdf"),try F.file("captured-manual-text-v1",extension:"md")]
        let attachments = try XCTUnwrap(OfficeReport.manifest(F.data("captured-manual-evidence-v1")))
        let evidence = try zip(attachments,evidenceBytes).map { attachment,bytes -> OfficeReportService.Evidence in
            // Match by digest because the canonical manifest sorts its attachments.
            let data = try XCTUnwrap(evidenceBytes.first {OfficeReport.digest($0) == attachment.sha256})
            let file = root.appendingPathComponent(attachment.sha256);try data.write(to:file)
            return .init(attachment:attachment,file:file)
        }
        var saved = OfficeReportService.Ledger()
        var allowed = true
        var seams = OfficeReportService.Seams(transport:transport,held:{held})
        seams.sign = {try F.phone().signature(for:OfficeReport.reportDomain + $0)}
        seams.load = {saved};seams.save = {saved = $0};seams.recordAllowed = {_ in allowed}
        let service = OfficeReportService(seams:seams)
        let fallback = LocalSyncSink()
        var compatible = false
        let sink = OfficeReportSink(seams:.init(fallback:fallback,officeIsDestination:{true},reports:service,
            evidence:{_ in (evidence,.none)},capturedManualAllowed:{_ in compatible && allowed}))
        let op = QueuedOp.make(capturedManual:m)
        XCTAssertEqual(op.sessionId,m.sessionID)
        if case .waiting = await sink.deliver(op) {} else {XCTFail("an unqualified peer must wait")}
        XCTAssertTrue(fallback.delivered.isEmpty)
        if case .waiting = await fallback.deliver(op) {} else {XCTFail("local storage is not Office delivery")}
        compatible = true
        if case .waiting = await sink.deliver(op) {} else {XCTFail("transfer is not acceptance")}
        let entry = try XCTUnwrap(service.ledger.entries.first)
        XCTAssertEqual(entry.revision,1);XCTAssertEqual(entry.recordID,m.captureID)
        XCTAssertEqual(m.captureRevision,7,"source revision and signed delivery revision are independent")
        let restarted = OfficeReportService(seams:seams)
        _ = try await restarted.submit(XCTUnwrap(OfficeReportSink.submission(for:op,evidence:evidence,transcript:.none)))
        XCTAssertEqual(restarted.ledger.entries.first?.payload,entry.payload)
        let publishes = await transport.reportPublishes
        XCTAssertEqual(publishes,1,"retry/restart preserves the exact signed report and files")
        let published = try XCTUnwrap(entry.published)
        let report = try OfficeReport.report(published,phoneApplicationKey:held.phoneApplicationKey,identity:.init(held))
        XCTAssertEqual(report.jobReference,m.jobReference);XCTAssertEqual(report.jobID,m.jobID)
        func receipt(outcome:String,wrongDigest:Bool = false) throws -> Data {
            let payload = OfficeReport.Receipt(version:1,kind:OfficeReport.receiptKind,reportID:entry.reportID,
                reportSHA256:wrongDigest ? String(repeating:"0",count:64) : OfficeReport.digest(published),
                recordSHA256:entry.recordSHA256,manifestSHA256:OfficeReport.digest(entry.manifest),
                organizationID:held.organizationID,enrolmentID:held.enrolmentID,officeID:held.officeID,
                phoneTransportID:held.phoneTransportID,outcome:outcome,attachmentsCommitted:outcome == "evidencePending" ? 1 : 2,
                attachmentsOutstanding:outcome == "evidencePending" ? 1 : 0,receivedAt:F.now)
            return try F.signed(JSONEncoder().encode(payload),domain:OfficeReport.receiptDomain,by:F.office())
        }
        await transport.put(receipt:try receipt(outcome:"fullyAccepted",wrongDigest:true),reportID:entry.reportID,stage:"full")
        do {_ = try await service.sweep()} catch {}
        XCTAssertEqual(service.status(operationID:op.id),.waiting)
        await transport.put(receipt:try receipt(outcome:"evidencePending"),reportID:entry.reportID,stage:"pending")
        do {_ = try await service.sweep()} catch {}
        XCTAssertEqual(service.status(operationID:op.id),.evidencePending)
        await transport.put(receipt:try receipt(outcome:"fullyAccepted"),reportID:entry.reportID,stage:"full")
        _ = try await service.sweep()
        let delivered = await sink.deliver(op)
        XCTAssertEqual(delivered,.done)
        XCTAssertEqual(service.status(operationID:op.id),.fullyAccepted)
        XCTAssertEqual(QueuedRecordRows.outstandingCount(in:[op],sessionId:m.sessionID),1)
        let resend = QueuedOp.make(capturedManual:m)
        _ = await sink.deliver(resend)
        XCTAssertEqual(service.ledger.entries.last?.revision,2)
        allowed = false
        _ = try await service.sweep()
        let publishedAfterPolicyChange = await transport.reports
        XCTAssertTrue(publishedAfterPolicyChange.isEmpty,"policy narrowing withdraws a published capture instead of continuing its attachments")
        if case .waiting = await sink.deliver(resend) {} else {XCTFail("a queued book cannot override current policy")}
    }
}
