import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import XCTest
@testable import OpenGlasses

final class CapturedManualMediaTests:XCTestCase {
    private func page() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data:nil,width:300,height:2400,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray:1,alpha:1));context.fill(CGRect(x:0,y:0,width:300,height:2400))
        return try XCTUnwrap(context.makeImage())
    }
    func testImageBoundsAndRealPDFPageCountAndFrozenDates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store = try CapturedManualStore(root:root,availableBytes:{Int.max})
        let m = CapturedManualStore.Metadata(captureID:"media-test",revision:1,sessionID:"job",jobReference:"JOB-1",
            jobID:"",jobRevision:0,scope:.init(ownershipScope:"personal",organizationID:"",enrolmentID:"",vaultID:"vault"),
            unitID:"unit",statedModel:"",confirmedModelToken:"",serial:"",title:"Test pages",author:"",capturedAt:1_800_000_000,
            policy:"jobOnly",poolIntent:"jobOnly")
        _ = try store.begin(m,languages:["en-US"],fallback:false)
        let jpeg = try CapturedManualMedia.jpeg(page(),longEdge:1000)
        let image = try CapturedManualMedia.image(jpeg)
        XCTAssertEqual(image.height,1000);XCTAssertLessThanOrEqual(image.width,1000)
        XCTAssertThrowsError(try CapturedManualMedia.image(Data("invalid".utf8)))
        for _ in 0..<3 {try store.appendImage(jpeg,to:m.key)}
        try store.finishStaging(m.key)
        let assembler = CapturedManualAssembler(store:store,read:{_,_,_ in .init(text:"Pressure switch instructions",confidence:0.9)},
            makePDF:CapturedManualMedia.pdf,pageCount:CapturedManualMedia.pageCount)
        let manifest = try await assembler.assemble(m.key)
        let data = try Data(contentsOf:store.file(manifest,name:"pages.pdf"))
        XCTAssertEqual(try CapturedManualMedia.pageCount(data),3)
        let pdf = try XCTUnwrap(PDFDocument(data:data))
        XCTAssertEqual(pdf.pageCount,3)
        let date = try XCTUnwrap(pdf.documentAttributes?[PDFDocumentAttribute.creationDateAttribute] as? Date)
        XCTAssertEqual(date.timeIntervalSince1970,Double(m.capturedAt),accuracy:1)
        let modified = try XCTUnwrap(pdf.documentAttributes?[PDFDocumentAttribute.modificationDateAttribute] as? Date)
        XCTAssertEqual(modified.timeIntervalSince1970,Double(m.capturedAt),accuracy:1)
        // Exercise the post-serialization repair even on PDFKit releases that honor attributes.
        pdf.documentAttributes = [PDFDocumentAttribute.creationDateAttribute:Date(timeIntervalSince1970:1),
                                  PDFDocumentAttribute.modificationDateAttribute:Date(timeIntervalSince1970:2)]
        let rewritten = try XCTUnwrap(pdf.dataRepresentation())
        let pinned = try CapturedManualMedia.pinDates(rewritten,to:Date(timeIntervalSince1970:Double(m.capturedAt)))
        XCTAssertEqual(pinned.count,rewritten.count,"cross-reference byte offsets must not move")
        XCTAssertEqual(try CapturedManualMedia.pageCount(pinned),3)
        let repaired = try XCTUnwrap(PDFDocument(data:pinned))
        for key in [PDFDocumentAttribute.creationDateAttribute,.modificationDateAttribute] {
            let saved = try XCTUnwrap(repaired.documentAttributes?[key] as? Date)
            XCTAssertEqual(saved.timeIntervalSince1970,Double(m.capturedAt),accuracy:1)
        }
        XCTAssertThrowsError(try CapturedManualMedia.pinDates(rewritten + Data("/CreationDate".utf8),to:date))
        XCTAssertNil(jpeg.range(of:Data("GPSLatitude".utf8)))
        #if os(iOS)
        XCTAssertEqual(try root.resourceValues(forKeys:[.isExcludedFromBackupKey]).isExcludedFromBackup,true)
        #endif
    }
}
