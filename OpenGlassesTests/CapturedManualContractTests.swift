import CryptoKit
import Foundation
import PDFKit
import XCTest
@testable import OpenGlasses

/// Shared Go/Swift golden corpus. No camera, OCR, account, office or hardware is substituted.
final class CapturedManualContractTests: XCTestCase {
    private typealias C = CapturedManualContract
    private typealias F = OfficeCheckInFixtures

    private func bundle() throws -> (Data, Data, Data, C.Manifest) {
        let raw = try F.data("captured-manual-v1")
        return (raw, try F.file("captured-manual-text-v1", extension: "md"),
                try F.file("captured-manual-pages-v1", extension: "pdf"), try C.read(raw))
    }

    func testGoldenCanonicalManifestAndPhysicalPages() throws {
        let (raw, text, pdf, m) = try bundle()
        let count = try XCTUnwrap(PDFDocument(data: pdf)).pageCount
        XCTAssertEqual(count, 3)
        XCTAssertEqual(try C.canonicalBytes(m), raw)
        XCTAssertEqual(C.digest(raw) + "\n", String(decoding: try F.file("captured-manual-digest-v1", extension: "txt"), as: UTF8.self))
        XCTAssertEqual(try C.validate(raw, text: text, pdf: pdf, pdfPageCount: count, expectedScope: m.scope), m)
        XCTAssertEqual(m.pages.map(\.index), [1, 2, 3])
        XCTAssertEqual(m.pages.map(\.printedPage), [41, 0, 43])
        XCTAssertEqual(m.pages[1].textBytes, 0, "failed/empty pages remain addressable")
        XCTAssertEqual(m.lowConfidencePages, 2)
        XCTAssertEqual(m.documentID, "captured:fixture-capture-1:1")
        for p in m.pages {
            XCTAssertNotNil(String(data: text.subdata(in: p.textOffset..<(p.textOffset + p.textBytes)), encoding: .utf8))
        }
    }

    func testSharedMalformedAndInvalidManifestCorpus() throws {
        struct Case: Decodable { let name: String; let manifest: String }
        let cases = try JSONDecoder().decode([Case].self, from: F.data("captured-manual-negative-v1"))
        XCTAssertGreaterThan(cases.count, 35)
        for c in cases {
            let raw = try XCTUnwrap(Data(base64Encoded: c.manifest))
            XCTAssertThrowsError(try C.read(raw), c.name)
        }
    }

    func testExactFilesAndIndependentScopeAreRequired() throws {
        let (raw, text, pdf, m) = try bundle()
        XCTAssertThrowsError(try C.validate(raw, text: text + Data([10]), pdf: pdf, pdfPageCount: 3, expectedScope: m.scope))
        XCTAssertThrowsError(try C.validate(raw, text: text, pdf: pdf + Data([10]), pdfPageCount: 3, expectedScope: m.scope))
        XCTAssertThrowsError(try C.validate(raw, text: text, pdf: pdf, pdfPageCount: 2, expectedScope: m.scope))
        for other in [
            C.Scope(ownershipScope: "organization", organizationID: "other-org", enrolmentID: m.enrolmentID, vaultID: m.vaultID),
            C.Scope(ownershipScope: "organization", organizationID: m.organizationID, enrolmentID: "other-enrolment", vaultID: m.vaultID),
            C.Scope(ownershipScope: "organization", organizationID: m.organizationID, enrolmentID: m.enrolmentID, vaultID: "other-vault"),
        ] {
            XCTAssertThrowsError(try C.validate(raw, text: text, pdf: pdf, pdfPageCount: 3, expectedScope: other)) {
                XCTAssertEqual($0 as? C.Refusal, .wrongScope)
            }
        }
    }

    /// Mutate through Codable, then run the real canonical writer: valid hashes do not grant
    /// authority to a fabricated page map. Every invalid case must pass field validation first.
    func testUTF8AndExactPageFurnitureAreValidatedBeyondFileHashes() throws {
        let (raw, text, pdf, m) = try bundle()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        var pages = try XCTUnwrap(object["pages"] as? [[String: Any]])
        pages[2]["textOffset"] = m.pages[2].textOffset + 1 // splits the first Chinese character
        pages[2]["textBytes"] = m.pages[2].textBytes - 1
        object["pages"] = pages
        let changed = try JSONDecoder().decode(C.Manifest.self, from: JSONSerialization.data(withJSONObject: object))
        let canonical = try C.canonicalBytes(changed)
        XCTAssertThrowsError(try C.validate(canonical, text: text, pdf: pdf, pdfPageCount: 3, expectedScope: m.scope)) {
            XCTAssertEqual($0 as? C.Refusal, .invalidPages)
        }
        let altered = Data(String(decoding: text, as: UTF8.self).replacingOccurrences(of: "## Page 3", with: "## Page 9").utf8)
        object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        object["textSHA256"] = C.digest(altered)
        let remapped = try JSONDecoder().decode(C.Manifest.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try C.validate(C.canonicalBytes(remapped), text: altered, pdf: pdf, pdfPageCount: 3, expectedScope: m.scope))
    }

    func testBundleIdentityBindsPicturesMetadataAndSourceRevision() throws {
        let (raw, _, _, _) = try bundle()
        for (key, value) in [("pdfSHA256", C.digest(Data("another diagram".utf8)) as Any),
                             ("title", "Another edition" as Any), ("captureRevision", 2 as Any)] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
            object[key] = value
            let changed = try JSONDecoder().decode(C.Manifest.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertNotEqual(C.digest(try C.canonicalBytes(changed)), C.digest(raw), key)
        }
    }

    func testStandaloneReportAndMatchingSignedReceipts() throws {
        let (record, _, _, capture) = try bundle()
        let held = try F.held()
        let identity = OfficeReport.Identity(organizationID: held.organizationID, enrolmentID: held.enrolmentID,
                                            officeID: held.officeID, phoneTransportID: held.phoneTransportID)
        let envelope = try F.data("captured-manual-report-v1")
        let report = try OfficeReport.report(envelope, phoneApplicationKey: F.phone().publicKey.rawRepresentation, identity: identity)
        let evidence = try XCTUnwrap(OfficeReport.manifest(F.data("captured-manual-evidence-v1")))
        XCTAssertEqual(report.recordKind, "capturedManual")
        XCTAssertEqual(report.revision, 4)
        XCTAssertEqual(capture.captureRevision, 1)
        XCTAssertEqual(OfficeReport.payloadBytes(report), try F.payload("captured-manual-report-v1"))
        XCTAssertTrue(OfficeReport.recordAgrees(report, record: record, attachments: evidence))
        for (stage, expected) in [("pending", OfficeReport.Outcome.evidencePending), ("full", .fullyAccepted)] {
            let (_, outcome) = try OfficeReport.receipt(
                F.data("captured-manual-receipt-\(stage)-v1"), officeApplicationKey: F.office().publicKey.rawRepresentation,
                reportEnvelope: envelope, report: report, attachments: evidence)
            XCTAssertEqual(outcome, expected)
        }
        // A receipt for a different report is never evidence this book was delivered.
        XCTAssertThrowsError(try OfficeReport.receipt(F.data("office-report-receipt-full-v1"),
            officeApplicationKey: F.office().publicKey.rawRepresentation, reportEnvelope: envelope,
            report: report, attachments: evidence))
        XCTAssertFalse(OfficeReport.recordAgrees(report, record: record, attachments: Array(evidence.prefix(1))))
        let optional = evidence.map { OfficeReport.Attachment(sha256: $0.sha256, bytes: $0.bytes, role: $0.role,
            mediaType: $0.mediaType, name: $0.name, requirement: "optional", audience: $0.audience) }
        XCTAssertFalse(OfficeReport.recordAgrees(report, record: record, attachments: optional))
        let wrongPDF = evidence.map { OfficeReport.Attachment(sha256: $0.sha256, bytes: $0.bytes + 1, role: $0.role,
            mediaType: $0.mediaType, name: $0.name, requirement: $0.requirement, audience: $0.audience) }
        XCTAssertFalse(OfficeReport.recordAgrees(report, record: record, attachments: wrongPDF))
        for role in [OfficeReport.Role.capturedManualPDF, .capturedManualText] {
            XCTAssertNil(OfficeReport.manifestBytes([.init(sha256: capture.pdfSHA256, bytes: 100, role: role.rawValue,
                mediaType: "application/pdf", name: "page.pdf", requirement: "required", audience: "customer")]))
            XCTAssertNil(OfficeReport.manifestBytes([.init(sha256: capture.pdfSHA256, bytes: 100, role: role.rawValue,
                mediaType: "image/jpeg", name: "page.jpg", requirement: "required", audience: "office")]))
        }
        // Every required file must be committed: recordAccepted with one outstanding is impossible.
        let impossible = try F.changed("captured-manual-receipt-pending-v1", domain: OfficeReport.receiptDomain, by: F.office()) {
            $0["outcome"] = "recordAccepted"; $0["attachmentsCommitted"] = 1; $0["attachmentsOutstanding"] = 1
        }
        XCTAssertThrowsError(try OfficeReport.receipt(impossible, officeApplicationKey: F.office().publicKey.rawRepresentation,
            reportEnvelope: envelope, report: report, attachments: evidence))
    }
}
