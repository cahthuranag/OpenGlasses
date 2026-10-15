import Foundation
import PDFKit
import XCTest
@testable import OpenGlasses

final class CapturedManualStoreTests: XCTestCase {
    private typealias S = CapturedManualStore
    private typealias A = CapturedManualAssembler
    private typealias F = OfficeCheckInFixtures
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        func set(_ value: Bool) { lock.lock(); defer { lock.unlock() }; flag = value }
        var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    }
    private actor Calls {
        var pages: [String] = []
        func add(_ page: String) { pages.append(page) }
        func all() -> [String] { pages }
    }
    private func metadata(revision: Int64 = 1, title: String = "Test manual") -> S.Metadata {
        .init(captureID:"test-capture",revision:revision,sessionID:"test-session",jobReference:"JOB-1",
            jobID:"",jobRevision:0,scope:.init(ownershipScope:"personal",organizationID:"",enrolmentID:"",vaultID:"test-vault"),
            unitID:"unit-1",statedModel:"HX-40",confirmedModelToken:"hx40",serial:"serial",title:title,author:"Tester",
            capturedAt:1_800_000_000,policy:"jobOnly",poolIntent:"jobOnly")
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at:url) }
        return url
    }
    private func staged(_ store: S, metadata: S.Metadata? = nil) throws -> String {
        let m = metadata ?? self.metadata()
        _ = try store.begin(m,languages:["en-US"],fallback:false)
        for i in 1...3 { try store.appendImage(Data(String(i).utf8),to:m.key) }
        try store.finishStaging(m.key)
        return m.key
    }
    private func assembler(_ store: S, read: @escaping @Sendable (Data,[String],Bool) async throws -> A.Reading = { bytes,_,_ in
        let p = String(decoding:bytes,as:UTF8.self)
        if p == "2" { throw S.Failure.missingPage }
        return .init(text:"Pressure page \(p)\n— 41 —",confidence:0.9)
    }) throws -> A {
        let pdf = try F.file("captured-manual-pages-v1",extension:"pdf")
        return A(store:store,read:read,makePDF:{ _, image in
            for i in 1...3 { _ = try image(i) }
            return pdf
        },pageCount:{ data in try XCTUnwrap(PDFDocument(data:data)).pageCount })
    }
    func testCompleteBundleKeepsFailedPageAndRetainsImmutableRetakeCitations() async throws {
        let root = try directory(); let store = try S(root:root,availableBytes:{Int.max})
        let key = try staged(store)
        let m = try await assembler(store).assemble(key)
        XCTAssertEqual(m.ocrPages,2);XCTAssertEqual(m.failedPages,1)
        XCTAssertEqual(m.pages.map(\.index),[1,2,3]);XCTAssertEqual(m.pages[1].textBytes,0)
        let oldPDF = try store.file(m,name:"pages.pdf")
        let original = try Data(contentsOf:oldPDF)
        let second = metadata(revision:2,title:"Retake")
        let next = try await assembler(store).assemble(staged(store,metadata:second))
        XCTAssertEqual(try store.manifests().map(\.captureRevision),[2])
        XCTAssertNotEqual(m.documentID,next.documentID)
        XCTAssertEqual(try Data(contentsOf:store.file(m,name:"pages.pdf")),original)
        let restored = try S(root:root,availableBytes:{Int.max})
        XCTAssertEqual(try restored.manifests().first?.captureRevision,2)
        XCTAssertEqual(try Data(contentsOf:restored.file(m,name:"pages.pdf")),original)
    }
    func testInterruptedRecognitionResumesWithSamePDFAndRedactedCheckpoints() async throws {
        let root = try directory(); let store = try S(root:root,availableBytes:{Int.max})
        let key = try staged(store,metadata:metadata(title:"Manual test@example.invalid"))
        let calls = Calls()
        let interrupted = try assembler(store) { data,languages,fallback in
            let p = String(decoding:data,as:UTF8.self);await calls.add(p)
            XCTAssertEqual(languages,["en-US"]);XCTAssertFalse(fallback)
            if p == "3" { throw CancellationError() }
            return .init(text:"Page \(p)\nContact test@example.invalid",confidence:0.4)
        }
        do { _ = try await interrupted.assemble(key);XCTFail("should cancel") } catch is CancellationError {} 
        XCTAssertTrue(try store.manifests().isEmpty)
        let pdf = try XCTUnwrap(store.pdf(key))
        let draft = try store.load(key)
        XCTAssertEqual(draft.recognized.count,2)
        XCTAssertFalse(draft.metadata.title.contains("@"))
        let files = FileManager.default.enumerator(at:root,includingPropertiesForKeys:nil)!.allObjects.compactMap { $0 as? URL }
        for url in files where url.pathExtension == "json" {
            XCTAssertFalse(try String(contentsOf:url,encoding:.utf8).contains("test@example.invalid"))
        }
        let restored = try S(root:root,availableBytes:{Int.max})
        var resumed = try assembler(restored) { data,_,_ in
            let p = String(decoding:data,as:UTF8.self);await calls.add(p)
            return .init(text:"第三页\n— 43 —",confidence:0.9)
        }
        resumed = A(store:restored,read:resumed.read,makePDF:{ _,_ in XCTFail("must reuse PDF");return Data() },pageCount:resumed.pageCount)
        let m = try await resumed.assemble(key)
        XCTAssertEqual(try Data(contentsOf:restored.file(m,name:"pages.pdf")),pdf)
        XCTAssertEqual(m.lowConfidencePages,2)
        let pages = await calls.all();XCTAssertEqual(pages,["1","2","3","3"])
        XCTAssertEqual(m.redactions.first(where:{$0.pattern == "email"})?.count,3)
    }
    func testErasureDuringRecognitionCannotRecreateCapture() async throws {
        let root = try directory();let store = try S(root:root,availableBytes:{Int.max});let key = try staged(store)
        let worker = try assembler(store) { _,_,_ in
            try store.forget("test-capture")
            return .init(text:"late result",confidence:1)
        }
        do { _ = try await worker.assemble(key);XCTFail("erased work returned") } catch {}
        let restored = try S(root:root,availableBytes:{Int.max})
        XCTAssertTrue(try restored.pending().isEmpty);XCTAssertTrue(try restored.manifests().isEmpty)
        XCTAssertThrowsError(try restored.begin(metadata(),languages:["en-US"],fallback:false))
    }
    func testLimitsMissingImagesAndFilesystemFailureNeverSelectHalfBundle() async throws {
        let root = try directory();var limits = S.Limits();limits.pages = 1
        let store = try S(root:root,limits:limits,availableBytes:{Int.max})
        let m = metadata();_ = try store.begin(m,languages:["en-US"],fallback:false)
        try store.appendImage(Data([1]),to:m.key)
        XCTAssertThrowsError(try store.appendImage(Data([2]),to:m.key));XCTAssertTrue(try store.manifests().isEmpty)
        let spaceFlag = Flag()
        let lowSpace = try S(root:directory(),availableBytes:{ spaceFlag.value ? 0 : Int.max })
        _ = try lowSpace.begin(m,languages:["en-US"],fallback:false); spaceFlag.set(true)
        XCTAssertThrowsError(try lowSpace.appendImage(Data([1]),to:m.key))
        let flag = Flag(); let failingRoot = try directory()
        let failing = try S(root:failingRoot,availableBytes:{Int.max},writeBytes:{ data,url in
            if flag.value && url.lastPathComponent == "journal.json" { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to:url,options:.atomic)
        })
        let key = try staged(failing);flag.set(true)
        do { _ = try await assembler(failing).assemble(key);XCTFail("journal write should fail") } catch {}
        XCTAssertTrue(try failing.manifests().isEmpty)
        flag.set(false)
        let recovered = try await assembler(failing).assemble(key)
        XCTAssertEqual(try failing.manifests().first,recovered)
        let broken = try S(root:directory(),availableBytes:{Int.max});let brokenKey = try staged(broken)
        try FileManager.default.removeItem(at:broken.root.appendingPathComponent("staging/\(brokenKey)/page-2.jpg"))
        do { _ = try await assembler(broken).assemble(brokenKey);XCTFail("missing source must fail") } catch {}
        XCTAssertTrue(try broken.manifests().isEmpty)
    }
    func testHistoricalMetadataAndOriginalSessionErasureCoverEveryRevision() async throws {
        let store = try S(root:directory(),availableBytes:{Int.max})
        let old = try await assembler(store).assemble(staged(store,metadata:metadata(title:"Old canary manual")))
        _ = try await assembler(store).assemble(staged(store,metadata:metadata(revision:2,title:"Replacement")))
        XCTAssertEqual(try store.manifests(currentOnly:false).count,2)
        XCTAssertEqual(try store.deleteMatching { m,_ in m.title.contains("canary") },1)
        XCTAssertTrue(try store.manifests(currentOnly:false).isEmpty)
        XCTAssertThrowsError(try store.file(old,name:"pages.pdf"))
        XCTAssertThrowsError(try store.begin(metadata(revision:3),languages:["en-US"],fallback:false))
    }

    func testPrintedNumbersAndRecognitionLanguages() {
        for text in ["Body\n— 41 —","Page 41\nBody","Body\n41"] {XCTAssertEqual(PrintedPageNumberFinder.find(in:text),41)}
        for text in ["Body\n2026","Body\nP/N 41","Page 40\nBody\n41"] {XCTAssertNil(PrintedPageNumberFinder.find(in:text))}
        XCTAssertEqual(CapturedManualLanguages.resolve(preferred:["fr-CA"],supported:["fr-FR","en-US"]).identifiers,["fr-FR","en-US"])
        XCTAssertEqual(CapturedManualLanguages.resolve(preferred:["en-NZ","en-US"],supported:["en-US"]).identifiers,["en-US"])
        XCTAssertTrue(CapturedManualLanguages.resolve(preferred:["xx-YY"],supported:["en-US"]).fallback)
    }
}
