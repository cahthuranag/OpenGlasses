import Foundation
import PDFKit
import XCTest
@testable import OpenGlasses

/// Real source/store/factory/tool routes, with an empty custom vault and no camera or model.
@MainActor
final class CapturedManualIntegrationTests: XCTestCase {
    private typealias F = TeamLearningFixtures
    private var root: URL!
    var source: CapturedManualStore!
    private var documents: DocumentStore!
    var sessions: FieldSessionService!
    var catalog: CapturedManualCatalog!
    private var previousEntitlement: FieldAssistEntitlementProvider!
    private var previousEnabled: Any?
    private var previousHipaa = false
    var access = true
    private let vaultID = "if_capture_integration"

    override func setUp() async throws {
        try await super.setUp()
        root = F.tempDirectory("CapturedManualIntegration")
        previousEnabled = UserDefaults.standard.object(forKey:"fieldAssistEnabled")
        UserDefaults.standard.set(true,forKey:"fieldAssistEnabled")
        previousHipaa = Config.hipaaMode; Config.hipaaMode = false
        previousEntitlement = EntitlementTestScope.grant(tier:.team)
        let folder = F.writeVault(in:root,id:vaultID)
        let manifest = VaultManifest(id:vaultID,name:"Capture test",version:"1.0.0",
            files:["safety.md","models.md"],proceduresDir:nil,documentsDir:nil,documents:[],
            gating:.init(iap:"enterprise"),promptRules:["Never fabricate.","Cite the source."])
        try JSONEncoder().encode(manifest).write(to:folder.appendingPathComponent("manifest.json"))
        _ = try VaultImporter.install(from:folder)
        VaultRegistry.shared.reloadUserManifests(); VaultRegistry.shared.resetCache()
        source = try CapturedManualStore(root:root.appendingPathComponent("captures"),availableBytes:{Int.max})
        documents = F.documentStore(in:root)
        catalog = CapturedManualCatalog();catalog.injectedSource = source
        catalog.accessAllowed = { [weak self] in self?.access == true }
        catalog.scopeForVault = { .init(ownershipScope:"personal",organizationID:"",enrolmentID:"",vaultID:$0) }
        sessions = FieldSessionService(sessionsRoot:root.appendingPathComponent("sessions"))
        sessions.capturedManuals = catalog;sessions.documentStore = documents
        sessions.retrievalPolicy = .init(similarityFloor:1.01)
        _ = try sessions.startSession(vaultId:vaultID,assetId:nil)
    }
    override func tearDown() async throws {
        sessions = nil;catalog = nil;documents = nil;source = nil
        VaultImporter.uninstall(id:vaultID)
        VaultRegistry.shared.reloadUserManifests();VaultRegistry.shared.resetCache()
        try? FileManager.default.removeItem(at:root)
        if let previousEnabled { UserDefaults.standard.set(previousEnabled,forKey:"fieldAssistEnabled") }
        else { UserDefaults.standard.removeObject(forKey:"fieldAssistEnabled") }
        Config.hipaaMode = previousHipaa;EntitlementTestScope.restore(previousEntitlement)
        try await super.tearDown()
    }
    private func capture(revision: Int64 = 1) async throws -> CapturedManualContract.Manifest {
        let session = try XCTUnwrap(sessions.activeSession)
        let m = CapturedManualStore.Metadata(captureID:"integration-book",revision:revision,sessionID:session.id,
            jobReference:"JOB-ORIGINAL",jobID:"",jobRevision:0,scope:catalog.scopeForVault(vaultID),
            unitID:session.continuityScope,statedModel:"",confirmedModelToken:"",serial:"SERIAL-DO-NOT-QUOTE",
            title:"Pressure service book",author:"Technician",capturedAt:1_800_000_000,policy:"jobOnly",poolIntent:"jobOnly")
        _ = try source.begin(m,languages:["en-US"],fallback:false)
        for page in 1...3 {try source.appendImage(Data("\(page)".utf8),to:m.key)}
        try source.finishStaging(m.key)
        let pdf = try OfficeCheckInFixtures.file("captured-manual-pages-v1",extension:"pdf")
        let assembler = CapturedManualAssembler(store:source,read:{ bytes,_,_ in
            let page = String(decoding:bytes,as:UTF8.self)
            return .init(text:page == "1" ? "Fault ZX7 means wet pressure switch tubing. Replacement part AB1234.\nPage 41" : "Other page \(page)",confidence:0.95)
        },makePDF:{ _,_ in pdf },pageCount:{try XCTUnwrap(PDFDocument(data:$0)).pageCount})
        let result = try await assembler.assemble(m.key)
        try await catalog.index(result);return result
    }
    func testCapturedOnlyAnswersEveryFactoryRouteWithPhysicalPagesAndWarnings() async throws {
        let m = try await capture()
        XCTAssertFalse(try XCTUnwrap(sessions.activeVault).manifest.hasDocuments)
        let expected = CapturedManualCatalog.citationName(m)
        let replies = [
            try XCTUnwrap(sessions.promptContext(turn:"what does ZX7 mean")),
            try await ManualLookupTool(documentStore:documents,sessionService:sessions).execute(args:["query":"ZX7"]),
            try await EquipmentLookupTool(documentStore:documents,sessionService:sessions).execute(args:["query":"ZX7"])
        ]
        for reply in replies {
            XCTAssertTrue(reply.contains(expected),reply)
            XCTAssertTrue(reply.contains("page 1"),reply)
            XCTAssertTrue(reply.contains("text recognised from a scan"),reply)
            XCTAssertFalse(reply.contains("SERIAL-DO-NOT-QUOTE"),reply)
        }
        XCTAssertTrue(sessions.verifyPart("AB1234").verified)
        XCTAssertEqual(documents.pageTexts(documentId:m.documentID).map(\.page),[1,2,3])
        XCTAssertTrue(documents.personalDocuments().isEmpty)
        XCTAssertTrue(documents.query("ZX7",limit:10).isEmpty,"unscoped searches cannot read capture text")
        let narrowed = try await ManualLookupTool(documentStore:documents,sessionService:sessions)
            .execute(args:["query":"ZX7","document":"Pressure service book"])
        XCTAssertTrue(narrowed.contains(expected),narrowed)
        let citation = try XCTUnwrap(CitationLineParser.parse("Source: \(expected), page 1").first)
        XCTAssertEqual(citation.title,expected);XCTAssertEqual(citation.page,1)
        let staged = try XCTUnwrap(sessions.stagedFigure(for:citation))
        XCTAssertNotNil(sessions.sourcePDFURL(for:staged))
        XCTAssertTrue(sessions.manualPageSheet(for:staged).photographed)
    }
    func testPolicyChangeRetakeAndForgetRetractLiveSearchButPreserveHistoricalCitation() async throws {
        let first = try await capture()
        let citation = CapturedManualCatalog.citationName(first)
        access = false
        XCTAssertTrue(sessions.retrievalNamespaces(vaultId:vaultID).allSatisfy {$0.source != .capturedManual})
        XCTAssertTrue(documents.pageTexts(documentId:first.documentID).isEmpty)
        XCTAssertNil(catalog.historical(citation:citation))
        access = true
        let second = try await capture(revision:2)
        XCTAssertEqual(sessions.retrievalNamespaces(vaultId:vaultID).filter {$0.source == .capturedManual}.map(\.namespace),[second.documentID])
        XCTAssertEqual(catalog.historical(citation:citation),first)
        XCTAssertNoThrow(try source.file(first,name:"pages.pdf"))
        try catalog.forget(first.captureID)
        XCTAssertTrue(documents.documents.isEmpty)
        XCTAssertNil(catalog.historical(citation:citation))
        XCTAssertThrowsError(try source.file(first,name:"pages.pdf"))
    }
}
