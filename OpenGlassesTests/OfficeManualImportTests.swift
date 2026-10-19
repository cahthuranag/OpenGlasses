import CryptoKit
import Foundation
import XCTest
@testable import OpenGlasses

final class OfficeManualImportTests: XCTestCase {
    private let now: Int64 = 1_800_000_000
    private func fixture(_ name: String, extension ext: String) throws -> Data {
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
        #else
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: ext)
        #endif
        return try Data(contentsOf: XCTUnwrap(url))
    }
    private func publisher(status: VaultPublisher.Status = .active) throws -> VaultPublisher {
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("manual-fixture-keys", extension: "json")) as? [String: Any])
        return .init(id: "fixture-publisher", name: "Fictional Publisher",
                     publicKey: try XCTUnwrap(keys["publisherPublicKey"] as? String), status: status)
    }
    private func assignment(archive: Data? = nil, mutation: ((inout [String: Any]) -> Void)? = nil,
                            highWater: OfficeManualAssignment.HighWater? = nil,enrolmentID:String = "fixture-phone") throws -> OfficeManualAssignment.Verified {
        var envelope = try fixture("manual-assignment-v1", extension: "json")
        let seed = Data(SHA256.hash(data: Data("Avenkin public fixture office key v1".utf8)))
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        if archive != nil || mutation != nil || enrolmentID != "fixture-phone" {
            let e = try JSONDecoder().decode(OfficeManualAssignment.Envelope.self, from: envelope)
            var p = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(Data(base64Encoded: e.payload))) as? [String: Any])
            if let archive { p["archiveBytes"] = archive.count; p["archiveSHA256"] = VaultArchiveReader.sha256Hex(archive) }
            p["enrolmentID"] = enrolmentID
            mutation?(&p)
            let raw = try JSONSerialization.data(withJSONObject: p, options: [.sortedKeys])
            let signature = try key.signature(for: OfficeManualAssignment.domain + raw)
            envelope = try JSONEncoder().encode(OfficeManualAssignment.Envelope(payload: raw.base64EncodedString(), signature: signature.base64EncodedString()))
        }
        let trust = OfficeManualAssignment.Trust(organizationID: "fixture-org", enrolmentID: enrolmentID,
            officeID: "fixture-office", generation: 1, setID: "fixture-set", publicKey: key.publicKey.rawRepresentation,
            maximumArchiveBytes: 1_048_576)
        return try OfficeManualAssignment.verify(envelope, trust: trust, now: now, highWater: highWater)
    }
    private func prepare(_ archive: Data, assignment: OfficeManualAssignment.Verified? = nil,
                         publishers: [VaultPublisher]? = nil, maximum: Int = 1_048_576) throws -> OfficeManualImport.Prepared {
        try OfficeManualImport.prepare(assignment: assignment ?? self.assignment(), archive: archive,
            publishers: publishers ?? [publisher()], maximumInflatedBytes: maximum,
            receivedAt: Date(timeIntervalSince1970: TimeInterval(now)))
    }
    private func signedArchive(files: [String: Data], headerVersion: String = "1.0.0", signed: Bool = true) throws -> Data {
        let header = VaultArchiveFixture.header(for: files, vaultId: "fixture-vault", vaultVersion: headerVersion,
            publisherId: "fixture-publisher", publisherName: "Fictional Publisher")
        let seed = Data(SHA256.hash(data: Data("Avenkin public fixture publisher key v1".utf8)))
        let signature = signed ? try VaultArchiveSignature.sign(header: header, files: files, privateKeyBase64: seed.base64EncodedString()) : nil
        return VaultArchiveFixture.archive(header: header, files: files, signature: signature)
    }
    func testSharedSignedArchivePreparesExistingVaultFiles() throws {
        let archive = try fixture("manual-vault-v1", extension: "zip")
        let prepared = try prepare(archive)
        XCTAssertEqual(prepared.manifest.id, "fixture-vault")
        XCTAssertTrue(prepared.verification.isSigned)
        XCTAssertEqual(prepared.files.count, 3)
        XCTAssertTrue(String(data: try XCTUnwrap(prepared.files["documents/manual.txt"]), encoding: .utf8)?.contains("FICTIONAL TEST ONLY") == true)
    }
    #if !SWIFT_PACKAGE
    @MainActor
    func testAppVaultHandoffRetainsVerifiedPublisherProvenance() throws {
        let prepared = try prepare(fixture("manual-vault-v1", extension: "zip"))
        let request = prepared.vaultImportRequest
        XCTAssertEqual(request.files, prepared.files)
        XCTAssertEqual(request.receipt.verification, .signed)
        XCTAssertEqual(request.receipt.publisherId, "fixture-publisher")
        XCTAssertEqual(request.receipt.archiveSHA256, prepared.archiveSHA256)
        XCTAssertEqual(request.receipt.sourceHost, "Avenkin Office")
        XCTAssertFalse(request.receipt.sourceHost.contains("://"))
    }
    #endif
    #if !SWIFT_PACKAGE
    @MainActor
    func testReviewedCaptureRoundTripRequiresReadyThenWorksOnSecondPhone() async throws {
        let previous = EntitlementTestScope.grant(tier:.team)
        let enabled = UserDefaults.standard.object(forKey:"fieldAssistEnabled")
        UserDefaults.standard.set(true,forKey:"fieldAssistEnabled")
        let root = TeamLearningFixtures.tempDirectory("ReviewedCapture")
        defer {
            VaultImporter.uninstall(id:"fixture-vault");VaultRegistry.shared.reloadUserManifests();VaultRegistry.shared.resetCache()
            try? FileManager.default.removeItem(at:root)
            EntitlementTestScope.restore(previous)
            if let enabled {UserDefaults.standard.set(enabled,forKey:"fieldAssistEnabled")} else {UserDefaults.standard.removeObject(forKey:"fieldAssistEnabled")}
        }
        VaultImporter.uninstall(id:"fixture-vault")
        let source = try CapturedManualStore(root:root.appendingPathComponent("source"),availableBytes:{Int.max})
        let metadata = CapturedManualStore.Metadata(captureID:"round-trip-book",revision:1,sessionID:"original-session",
            jobReference:"JOB-IF",jobID:"",jobRevision:0,
            scope:.init(ownershipScope:"organization",organizationID:"fixture-org",enrolmentID:"fixture-phone",vaultID:"fixture-vault"),
            unitID:"unit",statedModel:"",confirmedModelToken:"",serial:"",title:"Pressure book",author:"Fixture technician",
            capturedAt:now-120,policy:"jobOnly",poolIntent:"jobOnly")
        _ = try source.begin(metadata,languages:["en-US"],fallback:false)
        for page in 1...3 {try source.appendImage(Data("\(page)".utf8),to:metadata.key)}
        try source.finishStaging(metadata.key)
        let pdf = try fixture("captured-manual-pages-v1",extension:"pdf")
        let assembler = CapturedManualAssembler(store:source,read:{data,_,_ in
            if data == Data("2".utf8) {throw CapturedManualStore.Failure.missingPage}
            return .init(text:"Fault RC991: wet pressure switch tubing.\nPage 41",confidence:0.9)
        },makePDF:{_,_ in pdf},pageCount:{try CapturedManualMedia.pageCount($0)})
        let m = try await assembler.assemble(metadata.key)
        let review = try CapturedManualReviewTests.review(m)
        let text = try Data(contentsOf:source.file(m,name:"text.md"))
        var files = VaultArchiveFixture.vaultFiles(vaultId:"fixture-vault")
        let manifest = VaultManifest(id:"fixture-vault",name:"Reviewed book",version:"1.0.0",files:["fault-codes.md"],
            documentsDir:"documents",documents:[.init(file:"manual.md",title:"Pressure book",source:"pages.pdf",capturedManual:review)],
            promptRules:["Never fabricate.","Cite the source."])
        files["manifest.json"] = try JSONEncoder().encode(manifest)
        files["documents/manual.txt"] = nil;files["documents/manual.md"] = text;files["documents/pages.pdf"] = pdf
        let archive = try signedArchive(files:files)
        let prepared = try prepare(archive,assignment:assignment(archive:archive))
        let documents = TeamLearningFixtures.documentStore(in:root)
        let catalog = CapturedManualCatalog();catalog.injectedSource = source;catalog.documents = documents;catalog.accessAllowed = {true}
        catalog.scopeForVault = {_ in metadata.scope}
        try await catalog.index(m)
        let wrong = try CapturedManualReviewTests.review(m,digest:String(repeating:"0",count:64))
        let wrongManifest = VaultManifest(id:"fixture-vault",name:"Reviewed book",version:"1.0.0",files:["fault-codes.md"],
            documentsDir:"documents",documents:[.init(file:"manual.md",title:"Pressure book",source:"pages.pdf",capturedManual:wrong)],
            promptRules:["Never fabricate.","Cite the source."])
        var wrongFiles = files;wrongFiles["manifest.json"] = try JSONEncoder().encode(wrongManifest)
        let wrongArchive = try signedArchive(files:wrongFiles)
        let wrongPrepared = try prepare(wrongArchive,assignment:assignment(archive:wrongArchive))
        let wrongInstalled = try await VaultLinkInstaller.install(wrongPrepared.vaultImportRequest)
        _ = try await VaultImporter.syncDocuments(manifest:wrongInstalled.manifest,into:documents,capturedCatalog:catalog)
        XCTAssertEqual(try source.manifests().count,1,"even Ready and identical titles/text/PDF cannot replace a different bundle digest")
        let installed = try await VaultLinkInstaller.install(prepared.vaultImportRequest)
        try catalog.reconcileReviewedVault("fixture-vault")
        XCTAssertEqual(try source.manifests().count,1,"assignment and installation alone are not Ready")
        catalog.accessAllowed = {false}
        do {_ = try await VaultImporter.syncDocuments(manifest:installed.manifest,into:documents,capturedCatalog:catalog);XCTFail("blocked indexing must fail")} catch {}
        XCTAssertEqual(try source.manifests().count,1,"failed indexing cannot supersede")
        catalog.accessAllowed = {true}
        let ledger = try await VaultImporter.syncDocuments(manifest:installed.manifest,into:documents,capturedCatalog:catalog)
        XCTAssertEqual(ledger.entries.first?.capturedManual,review)
        XCTAssertEqual(ledger.entries.first?.ocrPages,2)
        XCTAssertTrue(try source.manifests().isEmpty)
        XCTAssertFalse(documents.documents.contains {$0.id == m.documentID})
        XCTAssertNoThrow(try source.file(m,name:"pages.pdf"))
        let citation = CapturedManualCatalog.citationName(m)
        XCTAssertEqual(catalog.historical(citation:citation),m,"old citations still resolve to their own immutable source")

        // A second phone receives a fresh assignment for its own enrolment, with the same
        // reviewed signed archive and no source capture. Reset only the simulated phone's index.
        let second = try prepare(archive,assignment:assignment(archive:archive,enrolmentID:"fixture-second"))
        _ = try await VaultLinkInstaller.install(second.vaultImportRequest)
        try VaultDocumentLedger().save(to:VaultImporter.overlayDirectory(for:"fixture-vault"))
        let secondDocuments = TeamLearningFixtures.documentStore(in:root)
        let secondCatalog = CapturedManualCatalog();secondCatalog.accessAllowed = {true}
        secondCatalog.injectedSource = try CapturedManualStore(root:root.appendingPathComponent("second-source"),availableBytes:{Int.max})
        secondCatalog.scopeForVault = {_ in .init(ownershipScope:"organization",organizationID:"fixture-org",enrolmentID:"fixture-second",vaultID:"fixture-vault")}
        _ = try await VaultImporter.syncDocuments(manifest:manifest,into:secondDocuments,capturedCatalog:secondCatalog)
        let sessions = FieldSessionService(sessionsRoot:root.appendingPathComponent("sessions"))
        sessions.capturedManuals = secondCatalog;sessions.documentStore = secondDocuments;sessions.retrievalPolicy = .init(similarityFloor:1.01)
        _ = try sessions.startSession(vaultId:"fixture-vault",assetId:nil)
        let reply = try await ManualLookupTool(documentStore:secondDocuments,sessionService:sessions).execute(args:["query":"RC991"])
        XCTAssertTrue(reply.contains("text recognised from a scan"),reply)
        XCTAssertTrue(reply.contains("photographed by Fixture technician at job JOB-IF"),reply)
        XCTAssertTrue(reply.contains("approved by Fixture reviewer"),reply)
        let ref = try XCTUnwrap(CitationLineParser.parse("Source: \(review.citationName(title:"Pressure book")), page 1").first)
        let figure = try XCTUnwrap(sessions.stagedFigure(for:ref))
        XCTAssertNotNil(sessions.sourcePDFURL(for:figure))
        XCTAssertTrue(sessions.manualPageSheet(for:figure).reviewedPhotograph)
        secondCatalog.accessAllowed = {false}
        XCTAssertNil(sessions.sourcePDFURL(for:figure))
        XCTAssertTrue(try CapturedManualStore(root:source.root,availableBytes:{Int.max}).manifests().isEmpty,"supersession survives process restart")
    }
    #endif
    func testModifiedOrTruncatedArchiveIsRefusedBeforeExtraction() throws {
        var archive = try fixture("manual-vault-v1", extension: "zip")
        archive[archive.count / 2] ^= 1
        XCTAssertThrowsError(try prepare(archive)) { XCTAssertEqual($0 as? OfficeManualImport.Refusal, .archiveDoesNotMatchAssignment) }
        XCTAssertThrowsError(try prepare(archive.dropLast())) { XCTAssertEqual($0 as? OfficeManualImport.Refusal, .archiveDoesNotMatchAssignment) }
    }
    func testUnknownRevokedOrWrongPublisherKeyCannotInstall() throws {
        let archive = try fixture("manual-vault-v1", extension: "zip")
        let wrong = VaultPublisher(id: "fixture-publisher", name: "Fictional Publisher", publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString())
        for publishers in [[], [try publisher(status: .revoked)], [wrong]] {
            XCTAssertThrowsError(try prepare(archive, publishers: publishers)) { XCTAssertEqual($0 as? OfficeManualImport.Refusal, .publisherNotVerified) }
        }
    }
    func testOfficeSignatureDoesNotAuthorizeAnUnsignedPublisherArchive() throws {
        let archive = try signedArchive(files: VaultArchiveFixture.vaultFiles(vaultId: "fixture-vault"), signed: false)
        XCTAssertThrowsError(try prepare(archive, assignment: assignment(archive: archive))) {
            XCTAssertEqual($0 as? OfficeManualImport.Refusal, .publisherNotVerified)
        }
    }
    func testWrongVaultVersionOrPublisherIsRefused() throws {
        let archive = try fixture("manual-vault-v1", extension: "zip")
        for field in ["vaultID", "vaultVersion", "publisherID"] {
            let v = try assignment(mutation: { $0[field] = "different" })
            XCTAssertThrowsError(try prepare(archive, assignment: v)) { XCTAssertEqual($0 as? OfficeManualImport.Refusal, .wrongVaultOrPublisher) }
        }
    }
    func testSignedUnsafeManifestCannotEscapeValidatedFiles() throws {
        var files = VaultArchiveFixture.vaultFiles(vaultId: "fixture-vault")
        let unsafe = VaultManifest(id: "fixture-vault", name: "Fictional", version: "1.0.0", files: ["../outside.md"], promptRules: ["Never fabricate.", "Cite files."])
        files["manifest.json"] = try JSONEncoder().encode(unsafe)
        let archive = try signedArchive(files: files)
        XCTAssertThrowsError(try prepare(archive, assignment: assignment(archive: archive))) { XCTAssertEqual($0 as? OfficeManualImport.Refusal, .unsafeManifest) }
    }
    func testListedSiteDocumentsMustBeSafeAndPresent() throws {
        func archive(sites: [String], extra: [String: Data] = [:]) throws -> Data {
            var files = VaultArchiveFixture.vaultFiles(vaultId: "fixture-vault")
            let base = try JSONDecoder().decode(VaultManifest.self, from: XCTUnwrap(files["manifest.json"]))
            let manifest = VaultManifest(id: base.id, name: base.name, version: base.version, files: base.files,
                                         proceduresDir: base.proceduresDir, documentsDir: base.documentsDir,
                                         documents: base.documents, gating: base.gating, promptRules: base.promptRules,
                                         sourceAttributionFormat: base.sourceAttributionFormat,
                                         sourceAttributionRequired: base.sourceAttributionRequired, sites: sites)
            files["manifest.json"] = try JSONEncoder().encode(manifest)
            for (path, data) in extra { files[path] = data }
            return try signedArchive(files: files)
        }
        for unsafe in [try archive(sites: ["../site.json"]), try archive(sites: ["sites/missing.json"])] {
            XCTAssertThrowsError(try prepare(unsafe, assignment: assignment(archive: unsafe))) {
                XCTAssertEqual($0 as? OfficeManualImport.Refusal, .unsafeManifest)
            }
        }
        let present = try archive(sites: ["sites/one.json"], extra: ["sites/one.json": Data("{}".utf8)])
        XCTAssertNoThrow(try prepare(present, assignment: assignment(archive: present)))
    }
    func testMissingDeclaredManualAndInflationLimitAreRefused() throws {
        var files = VaultArchiveFixture.vaultFiles(vaultId: "fixture-vault")
        files.removeValue(forKey: "documents/manual.txt")
        let archive = try signedArchive(files: files)
        XCTAssertThrowsError(try prepare(archive, assignment: assignment(archive: archive))) { XCTAssertEqual($0 as? OfficeManualImport.Refusal, .unsafeManifest) }
        XCTAssertThrowsError(try prepare(fixture("manual-vault-v1", extension: "zip"), maximum: 1)) { XCTAssertEqual($0 as? OfficeManualImport.Refusal, .invalidArchive) }
    }
    func testAssignmentExpiryIsRecheckedAfterTheDownload() throws {
        let verified = try assignment()
        let archive = try fixture("manual-vault-v1", extension: "zip")
        XCTAssertThrowsError(try OfficeManualImport.prepare(assignment: verified, archive: archive,
            publishers: [publisher()], maximumInflatedBytes: 1_048_576,
            receivedAt: Date(timeIntervalSince1970: TimeInterval(verified.payload.expiresAt)))) {
            XCTAssertEqual($0 as? OfficeManualImport.Refusal, .assignmentNotCurrentlyValid)
        }
    }
    func testInflationBudgetIncludesTheHeaderAndSignature() throws {
        let archive = try fixture("manual-vault-v1", extension: "zip")
        let zip = try XCTUnwrap(ZipArchiveReader(data: archive))
        let payloadOnly = zip.entryMetadata.filter {
            $0.name != VaultArchiveHeader.filename && $0.name != VaultArchiveHeader.signatureFilename
        }.reduce(0) { $0 + $1.uncompressedSize }
        XCTAssertThrowsError(try prepare(archive, maximum: payloadOnly)) {
            XCTAssertEqual($0 as? OfficeManualImport.Refusal, .invalidArchive)
        }
    }
    func testExactReplayRequiresCommitLookupRatherThanReimport() throws {
        let accepted = try assignment()
        let replay = try assignment(highWater: accepted.highWater)
        XCTAssertThrowsError(try prepare(fixture("manual-vault-v1", extension: "zip"), assignment: replay)) { XCTAssertEqual($0 as? OfficeManualImport.Refusal, .replayRequiresCommitLookup) }
    }
}
