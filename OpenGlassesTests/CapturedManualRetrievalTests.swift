import Foundation
import XCTest
@testable import OpenGlasses

final class CapturedManualRetrievalTests: XCTestCase {
    func testCaptureOrderWinsOverShortPagesEmptyPagesAndRecognizedFooters() {
        let chunks = DocumentChunker().chunkPages([
            (number:1,text:"First short page about the pressure switch.\nPage 41"),
            (number:2,text:""),
            (number:3,text:"Second short page about the blower.\n— 43 —")])
        XCTAssertEqual(Set(chunks.compactMap(\.page)),Set([1,3]))
        XCTAssertFalse(chunks.contains { $0.text.contains("pressure") && $0.text.contains("blower") })
        XCTAssertEqual(chunks.map(\.index),Array(chunks.indices))
    }
    func testScopeIsExactAndSameModelCanAnswerOnAnotherUnit() throws {
        let m = try CapturedManualContract.read(OfficeCheckInFixtures.data("captured-manual-v1"))
        let sameModel = CapturedManualAccess(scope:m.scope,sessionID:"another-session",unitID:"another-unit",confirmedModelToken:m.confirmedModelToken)
        XCTAssertTrue(sameModel.permits(m))
        let wrongModel = CapturedManualAccess(scope:m.scope,sessionID:m.sessionID,unitID:m.unitID,confirmedModelToken:"hx41")
        XCTAssertFalse(wrongModel.permits(m))
        var alias = wrongModel;alias.confirmedAliases = [m.confirmedModelToken]
        XCTAssertTrue(alias.permits(m),"only explicitly confirmed exact aliases widen spelling")
        var disabled = sameModel;disabled.enabled = false;XCTAssertFalse(disabled.permits(m))
        for scope in [
            CapturedManualContract.Scope(ownershipScope:"organization",organizationID:"other",enrolmentID:m.enrolmentID,vaultID:m.vaultID),
            .init(ownershipScope:"organization",organizationID:m.organizationID,enrolmentID:"later-enrolment",vaultID:m.vaultID),
            .init(ownershipScope:"organization",organizationID:m.organizationID,enrolmentID:m.enrolmentID,vaultID:"other-vault")
        ] {
            XCTAssertFalse(CapturedManualAccess(scope:scope,sessionID:m.sessionID,unitID:m.unitID,confirmedModelToken:m.confirmedModelToken).permits(m))
        }
    }
    func testUnboundCaptureStaysOnOriginalSessionAndUnit() throws {
        var object = try OfficeCheckInFixtures.fields(OfficeCheckInFixtures.data("captured-manual-v1"))
        object["confirmedModelToken"] = "";object["statedModel"] = ""
        let m = try JSONDecoder().decode(CapturedManualContract.Manifest.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertTrue(CapturedManualAccess(scope:m.scope,sessionID:m.sessionID,unitID:m.unitID,confirmedModelToken:"").permits(m))
        XCTAssertFalse(CapturedManualAccess(scope:m.scope,sessionID:"next-session",unitID:m.unitID,confirmedModelToken:"").permits(m))
        XCTAssertFalse(CapturedManualAccess(scope:m.scope,sessionID:m.sessionID,unitID:"next-unit",confirmedModelToken:"").permits(m))
    }
}
