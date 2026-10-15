import Foundation
import XCTest
@testable import OpenGlasses

final class CapturedManualReviewTests: XCTestCase {
    static func review(_ m:CapturedManualContract.Manifest,digest:String? = nil) throws -> CapturedManualReview {
        .init(version:1,origins:[.init(captureID:m.captureID,captureRevision:m.captureRevision,
            bundleSHA256:try digest ?? CapturedManualContract.digest(CapturedManualContract.canonicalBytes(m)),pageCount:m.pageCount)],
            pageCount:m.pageCount,ocrPages:m.ocrPages,failedPages:m.failedPages,lowConfidencePages:m.lowConfidencePages,
            pages:m.pages.map {.init(index:$0.index,originIndex:0,capturePage:$0.index,printedPage:$0.printedPage,textOffset:$0.textOffset,textBytes:$0.textBytes)},
            organizationID:m.organizationID,technician:m.author,jobReference:m.jobReference,capturedAt:m.capturedAt,
            reviewerID:"fixture-reviewer",reviewerName:"Fixture reviewer",approvedAt:m.capturedAt + 60)
    }
    func testReviewedMetadataKeepsPhysicalPageMapAndBindsExactSourceFiles() throws {
        let m = try CapturedManualContract.read(OfficeCheckInFixtures.data("captured-manual-v1"))
        let review = try Self.review(m)
        XCTAssertTrue(review.valid)
        let text = try OfficeCheckInFixtures.file("captured-manual-text-v1",extension:"md")
        let pdf = try OfficeCheckInFixtures.file("captured-manual-pages-v1",extension:"pdf")
        let pages = try review.pageTexts(text)
        XCTAssertEqual(pages.map(\.number),[1,2,3]);XCTAssertEqual(pages[1].text,"")
        let document = VaultDocument(file:"text.md",title:"Fictional book",source:"pages.pdf",capturedManual:review)
        let first = try document.capturedBinding(text:text,pdf:pdf)
        XCTAssertNotEqual(first,try document.capturedBinding(text:text,pdf:pdf + Data([0])))
        XCTAssertTrue(review.citationName(title:"Fictional book").contains("approved by Fixture reviewer"))
        XCTAssertEqual(try JSONDecoder().decode(VaultDocument.self,from:JSONEncoder().encode(document)),document)
    }
    func testMalformedPresentReviewIsNeverTreatedAsLegacyAndBadOffsetsCannotRenumberPages() throws {
        let m = try CapturedManualContract.read(OfficeCheckInFixtures.data("captured-manual-v1"))
        let review = try Self.review(m)
        let encoded = try JSONEncoder().encode(VaultDocument(file:"text.md",title:"Book",source:"pages.pdf",capturedManual:review))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:encoded) as? [String:Any])
        object["captured_manual"] = NSNull()
        XCTAssertThrowsError(try JSONDecoder().decode(VaultDocument.self,from:JSONSerialization.data(withJSONObject:object)))
        object.removeValue(forKey:"captured_manual")
        XCTAssertNil(try JSONDecoder().decode(VaultDocument.self,from:JSONSerialization.data(withJSONObject:object)).capturedManual)
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(review)) as? [String:Any])
        var pages = try XCTUnwrap(fields["pages"] as? [[String:Any]])
        pages[0]["capturePage"] = 3;fields["pages"] = pages
        XCTAssertFalse(try JSONDecoder().decode(CapturedManualReview.self,from:JSONSerialization.data(withJSONObject:fields)).valid)
        pages = review.pages.map {try! JSONSerialization.jsonObject(with:JSONEncoder().encode($0)) as! [String:Any]}
        pages[0]["textOffset"] = Int.max;fields["pages"] = pages
        let bad = try JSONDecoder().decode(CapturedManualReview.self,from:JSONSerialization.data(withJSONObject:fields))
        XCTAssertThrowsError(try bad.pageTexts(OfficeCheckInFixtures.file("captured-manual-text-v1",extension:"md")))
    }
}
