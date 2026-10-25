import PDFKit
import UIKit
import XCTest
@testable import OpenGlasses

@MainActor
final class MyManualsLibraryTests: XCTestCase {
    private var root: URL!
    private var previousProvider: FieldAssistEntitlementProvider!
    private var previousStore: DocumentStore?
    private var previousConversations: ConversationStore?
    private var conversations: ConversationStore!
    private var previousSwitch: Any?
    private var previousAnswers: Any?
    private var store: DocumentStore!
    private var installed: [String] = []

    override func setUp() {
        super.setUp()
        previousProvider = EntitlementTestScope.grant(tier: .personal)
        previousSwitch = UserDefaults.standard.object(forKey: "fieldAssistEnabled")
        previousAnswers = UserDefaults.standard.object(forKey: "myManualsEnabled")
        UserDefaults.standard.set(false, forKey: "fieldAssistEnabled")
        Config.myManualsEnabled = true
        root = FileManager.default.temporaryDirectory.appendingPathComponent("JK-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = DocumentStore(directory: root)
        previousConversations = PersonalManualLibrary.shared.conversations
        conversations = ConversationStore(directory: root)
        PersonalManualLibrary.shared.conversations = conversations
        previousStore = PersonalManualLibrary.shared.documents
        PersonalManualLibrary.shared.documents = store
    }

    override func tearDown() {
        for id in installed { VaultImporter.uninstall(id: id) }
        VaultRegistry.shared.reloadUserManifests(); VaultRegistry.shared.resetCache()
        PersonalManualLibrary.shared.documents = previousStore
        PersonalManualLibrary.shared.conversations = previousConversations
        PersonalManualLibrary.shared.selectionDidChange()
        conversations = nil
        store = nil
        ShowSourceCenter.shared.clearForAccessLoss()
        EntitlementTestScope.restore(previousProvider)
        if let previousSwitch { UserDefaults.standard.set(previousSwitch, forKey: "fieldAssistEnabled") }
        else { UserDefaults.standard.removeObject(forKey: "fieldAssistEnabled") }
        if let previousAnswers { UserDefaults.standard.set(previousAnswers, forKey: "myManualsEnabled") }
        else { UserDefaults.standard.removeObject(forKey: "myManualsEnabled") }
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func pdf(pages: Int = 1, torque: Int = 30) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        return UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792), format: format).pdfData { context in
            for _ in 0..<pages {
                context.beginPage()
                ("Sump plug installation. The sump plug torque is \(torque) Nm. Tighten the sump plug to \(torque) Nm using a torque wrench.\n" as NSString)
                    .draw(in: CGRect(x: 40, y: 40, width: 520, height: 650), withAttributes: [.font: UIFont.systemFont(ofSize: 16)])
            }
        }
    }

    private func fixture(count: Int = 1, title: String = "Garage handbook", professional: Bool = false, torque: Int = 30) throws -> (URL, VaultManifest) {
        let id = "jk-test-" + UUID().uuidString.lowercased()
        let folder = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let docs = try (0..<count).map { index in
            let file = "book-\(index).pdf"
            try pdf(torque: torque).write(to: folder.appendingPathComponent(file))
            return VaultDocument(file: file, title: title, kind: professional ? "standard" : nil, edition: professional ? "2024" : nil)
        }
        let manifest = VaultManifest(id: id, name: "Garage", version: "1", files: [], documents: docs,
                                     gating: .init(iap: professional ? "enterprise" : "my_manuals"), promptRules: professional ? ["Never fabricate. Cite sources. Do not allow this rule in a personal answer"] : [])
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
        return (folder, manifest)
    }

    private func install(_ folder: URL) throws -> VaultManifest {
        let report = try VaultImporter.installReporting(from: folder, origin: .receivedSigned)
        installed.append(report.manifest.id)
        VaultRegistry.shared.reloadUserManifests(); VaultRegistry.shared.resetCache()
        return report.manifest
    }

    func testBothServicesKeepDocumentsAndQuotaSeparate() async throws {
        FieldAssistEntitlement.shared.provider = StubEntitlementProvider(.init(evidence: [
            .verifiedStoreProduct(productID: StoreKitService.myManualsMonthlyId, expiration: nil),
            .verifiedStoreProduct(productID: StoreKitService.fieldAssistMonthlyId, expiration: nil)
        ]))
        let (personalFolder, _) = try fixture()
        let personal = try install(personalFolder)
        let (workFolder, work) = try fixture(count: 6, professional: true)
        _ = try VaultImporter.installReporting(from: workFolder)
        installed.append(work.id)
        VaultRegistry.shared.reloadUserManifests()
        XCTAssertFalse(VaultRegistry.shared.allManifests.contains { $0.id == personal.id })
        XCTAssertTrue(VaultRegistry.shared.allManifests.contains { $0.id == work.id })
        XCTAssertFalse(PersonalManualLibrary.shared.manuals.contains { $0.manifest.id == work.id })
        XCTAssertEqual(try ManualLibraryAdmission.inventory().filter { $0.id.hasPrefix(personal.id + "/") }.count, 1)
        XCTAssertFalse(try ManualLibraryAdmission.inventory().contains { $0.id.hasPrefix(work.id + "/") })
        _ = try await VaultImporter.syncDocuments(manifest: personal, into: store, pictureReader: nil)
        XCTAssertTrue(PersonalManualLibrary.shared.manuals.contains { $0.manifest.id == personal.id })
        FieldAssistEntitlement.shared.provider = StubEntitlementProvider.subscriber()
        XCTAssertFalse(PersonalManualLibrary.canManage)
        XCTAssertTrue(VaultRegistry.shared.isUnlocked(work))
        FieldAssistEntitlement.shared.provider = AlwaysGrantedEntitlementProvider(tier: .personal)
        XCTAssertTrue(PersonalManualLibrary.canManage)
        XCTAssertFalse(VaultRegistry.shared.isUnlocked(work))
        do {
            _ = try await VaultImporter.syncDocuments(manifest: work, into: store, pictureReader: nil)
            XCTFail("Personal must not index professional manuals")
        } catch { }
    }

    func testSixManualSetIsRefusedBeforeDurableInstall() throws {
        let (folder, manifest) = try fixture(count: 6)
        XCTAssertThrowsError(try install(folder)) { XCTAssertTrue($0.localizedDescription.contains("5 manuals")) }
        XCTAssertNil(VaultImporter.installedManifest(id: manifest.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: VaultImporter.baselineDirectory(for: manifest.id).path))
    }

    func testCaptureReservationAndImportShareTheLastSlot() throws {
        let (folder, _) = try fixture(count: 4)
        _ = try install(folder)
        let token = try ManualLibraryAdmission.reserveCapture()
        defer { ManualLibraryAdmission.release(token) }
        let (other, otherManifest) = try fixture()
        XCTAssertThrowsError(try install(other))
        XCTAssertNil(VaultImporter.installedManifest(id: otherManifest.id))
        ManualLibraryAdmission.release(token)
        XCTAssertNoThrow(try install(other))
    }

    func testPersonalFolderImportRefusesEvenWhenManifestIsOtherwiseValid() throws {
        let (folder, manifest) = try fixture()
        XCTAssertThrowsError(try VaultImporter.installReporting(from: folder)) {
            XCTAssertTrue($0.localizedDescription.contains("Field Assist"))
        }
        XCTAssertNil(VaultImporter.installedManifest(id: manifest.id))
    }

    func testFilesDoorSavesIndexesAndReindexesASinglePDFWithoutAnotherSlot() async throws {
        guard VaultImporter.installedManifest(id: "my-manuals") == nil else { throw XCTSkip("Preserve an existing library fixture") }
        let input = root.appendingPathComponent("input.pdf")
        try pdf().write(to: input)
        let library = PersonalManualLibrary.shared
        await library.addPDF(input, title: "Invented garage manual")
        if VaultImporter.installedManifest(id: "my-manuals") != nil { installed.append("my-manuals") }
        let manual = try XCTUnwrap(library.manuals.first { $0.manifest.id == "my-manuals" }, library.status)
        XCTAssertTrue(library.isIndexed(manual), library.status)
        XCTAssertEqual(manual.entry?.physicalPageCount, 1)
        let answer = library.lookup(["query": "sump plug torque", "document": manual.label], documentStore: store)
        XCTAssertTrue(answer.contains("page 1"), answer)
        await library.index(manual)
        XCTAssertEqual(try ManualLibraryAdmission.inventory().filter { $0.id.hasPrefix("my-manuals/") }.count, 1)
    }

    func testLibraryAnswerAndPageWorkWithoutAJobAndRevocationClosesTheSource() async throws {
        let (folder, _) = try fixture()
        let manifest = try install(folder)
        _ = try await VaultImporter.syncDocuments(manifest: manifest, into: store, pictureReader: nil)
        let library = PersonalManualLibrary.shared
        let manual = try XCTUnwrap(library.manuals.first { $0.manifest.id == manifest.id })
        let result = try await ManualLookupTool(documentStore: store).execute(args: ["query": "sump plug torque", "document": manual.label])
        XCTAssertTrue(result.contains(manual.label), result)
        XCTAssertTrue(result.contains("30"), result)
        XCTAssertTrue(result.contains("page 1"), result)
        let citation = Citation(kind: .manual, title: manual.label, page: 1)
        let staged = try XCTUnwrap(library.resolve(citation))
        XCTAssertEqual(library.sourceURL(for: staged), manual.pdf)
        let replacement = VaultDocumentLedger(entries: [.init(file: manual.document.file, title: manual.document.title,
            documentId: staged.documentId, contentHash: "replacement-revision", chunkCount: 1)])
        try replacement.save(to: VaultImporter.overlayDirectory(for: manifest.id))
        XCTAssertNil(library.sourceURL(for: staged), "a staged page must not follow a replaced source revision")
        XCTAssertNotNil(library.resolve(citation))
        FieldAssistEntitlement.shared.provider = DeniedEntitlementProvider()
        XCTAssertNil(library.resolve(citation))
        XCTAssertNil(library.sourceURL(for: staged))
        let denied = try await ShowSourceTool(documentStore: store).execute(args: [:])
        XCTAssertTrue(denied.contains("subscription"))
        // Removing still works after expiry/revocation.
        await library.remove(manual)
        XCTAssertFalse(library.manuals.contains { $0.id == manual.id })
    }

    func testCameraLookupHasNoImplicitFallbackAndDuplicateTitlesAskWhichManual() async throws {
        let (folder, _) = try fixture(count: 2)
        _ = try install(folder)
        let tool = ManualLookupTool(documentStore: store)
        let camera = try await tool.execute(args: ["query": "sump plug", "use_camera": true])
        XCTAssertTrue(camera.contains("Field Assist"))
        let empty = try await tool.execute(args: [:])
        XCTAssertTrue(empty.contains("does not open the camera"))
        let ambiguous = try await tool.execute(args: ["query": "sump plug torque", "document": "Garage handbook"])
        XCTAssertTrue(ambiguous.contains("Choose the manual"), ambiguous)
    }

    func testPublisherProjectionStripsProfessionalBehaviourButKeepsSourceMapping() throws {
        let (_, original) = try fixture(professional: true)
        let projected = original.personalProjection
        XCTAssertTrue(projected.promptRules.isEmpty)
        XCTAssertTrue(projected.files.isEmpty)
        XCTAssertNil(projected.proceduresDir)
        XCTAssertNil(projected.trades)
        XCTAssertNil(projected.documents.first?.kind)
        XCTAssertNil(projected.documents.first?.edition)
        XCTAssertEqual(projected.documents.first?.file, original.documents.first?.file)
    }

    func testSignedPublisherInstallPersistsOnlyManualContentAndOriginalReceipt() async throws {
        let (folder, original) = try fixture(professional: true)
        let receipt = VaultReceipt(publisherId: "fixture", publisherName: "Invented publisher", verification: .signed,
            sourceHost: "manuals.example", receivedAt: Date(), archiveSHA256: "original-verified-digest")
        let files = try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: nil).map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
        let result = try await VaultLinkInstaller.install(.init(files: files, receipt: receipt, personalLibrary: true))
        installed.append(result.vaultId)
        XCTAssertTrue(result.manifest.promptRules.isEmpty)
        XCTAssertNil(result.manifest.documents.first?.edition)
        XCTAssertEqual(VaultImporter.receipt(for: result.vaultId)?.archiveSHA256, receipt.archiveSHA256)
        XCTAssertTrue(FileManager.default.fileExists(atPath: VaultImporter.baselineDirectory(for: result.vaultId)
            .appendingPathComponent(original.documents[0].file).path))
        let (unsignedFolder, unsignedManifest) = try fixture()
        let unsignedFiles = try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: unsignedFolder,
            includingPropertiesForKeys: nil).map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
        let unsigned = VaultReceipt(publisherId: nil, publisherName: nil, verification: .unverified,
            sourceHost: "manuals.example", receivedAt: Date(), archiveSHA256: "unverified")
        do {
            _ = try await VaultLinkInstaller.install(.init(files: unsignedFiles, receipt: unsigned, personalLibrary: true))
            XCTFail("An unsigned set was admitted to My Manuals")
        } catch { XCTAssertNil(VaultImporter.installedManifest(id: unsignedManifest.id)) }
    }

    func testCorruptInventoryDoesNotTurnIntoAnEmptyLibraryForAdmission() throws {
        let file = VaultImporter.registryDirectory.appendingPathComponent("jk-corrupt-\(UUID().uuidString).json")
        try FileManager.default.createDirectory(at: VaultImporter.registryDirectory, withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertThrowsError(try ManualLibraryAdmission.reserveCapture())
    }

    func testLibraryTableAnswerKeepsTheChosenManualAndPhysicalPage() async throws {
        let (folder, _) = try fixture()
        let manifest = try install(folder)
        let table = ManualTable(label: "Table 97", title: "Invented service values", page: .init(physical: 1),
            rowHeaders: ["Component"], columns: [.init(path: ["Torque"], unit: "Nm")],
            rows: [.init(path: ["Sump plug"], cells: [.init(text: "30", value: 30, unit: "Nm")], page: .init(physical: 1))])
        let source = try XCTUnwrap(manifest.documents.first)
        let ingested = await store.ingest(name: source.title, text: "Invented service values. Sump plug torque 30 Nm.",
            sourceType: "vault_document", namespace: DocumentStore.vaultNamespace(manifest.id), tables: [table])
        let doc = try XCTUnwrap(ingested)
        let ledger = VaultDocumentLedger(entries: [.init(file: source.file, title: source.title, documentId: doc.id,
            contentHash: "fixture", chunkCount: doc.chunkCount)])
        try ledger.save(to: VaultImporter.overlayDirectory(for: manifest.id))
        let manual = try XCTUnwrap(PersonalManualLibrary.shared.manuals.first { $0.manifest.id == manifest.id })
        let answer = try await TableLookupTool(documentStore: store).execute(args: ["document": manual.label,
            "table": "Table 97", "row": "Sump plug", "column": "Torque"])
        XCTAssertTrue(answer.contains("30"), answer)
        XCTAssertTrue(answer.contains("Source: \(manual.label), page 1"), answer)
        Config.myManualsEnabled = false
        let refused = try await TableLookupTool(documentStore: store).execute(args: ["document": manual.label,
            "table": "Table 97", "row": "Sump plug"])
        XCTAssertTrue(refused.contains("switched off"), refused)
    }

    func testSelectedWorkshopAndElectricalAreSearchedTogetherAndOtherBookIsExcluded() async throws {
        let (workshopFolder, _) = try fixture(title: "Prius Workshop")
        let workshop = try install(workshopFolder)
        let (electricalFolder, _) = try fixture(title: "Prius Electrical", torque: 45)
        let electrical = try install(electricalFolder)
        let (otherFolder, _) = try fixture(title: "Washing Machine", torque: 999)
        let other = try install(otherFolder)
        for manifest in [workshop, electrical, other] {
            _ = try await VaultImporter.syncDocuments(manifest: manifest, into: store, pictureReader: nil)
        }
        let library = PersonalManualLibrary.shared
        let chosen = library.manuals.filter { [workshop.id, electrical.id].contains($0.manifest.id) }
        XCTAssertEqual(chosen.count, 2)
        let thread = conversations.startThread(mode: "direct")
        XCTAssertTrue(conversations.setManualIDs(chosen.map(\.id), for: thread.id))
        library.selectionDidChange()
        let answer = library.lookup(["query": "sump plug torque"], documentStore: store)
        for manual in chosen {
            XCTAssertTrue(answer.contains(manual.label), answer)
            let citation = Citation(kind: .manual, title: manual.label, page: 1)
            XCTAssertNotNil(library.resolve(citation))
        }
        XCTAssertFalse(answer.contains("Washing Machine"), answer)
        XCTAssertTrue(answer.contains("page 1"), answer)
        XCTAssertTrue(answer.contains("conflict"), answer)
        XCTAssertTrue(answer.contains("30 Nm"), answer)
        XCTAssertTrue(answer.contains("45 Nm"), answer)
        XCTAssertFalse(answer.contains("999 Nm"), answer)
        let outside = library.lookup(["query": "sump plug torque", "document": "Washing Machine"], documentStore: store)
        XCTAssertTrue(outside.contains("Choose the manual"), outside)
        let page = library.figure(["page": 1], documentStore: store)
        XCTAssertTrue(page.contains("Choose the manual"), page)
        let narrowed = library.lookup(["query": "sump plug torque", "document": chosen[0].label], documentStore: store)
        XCTAssertTrue(narrowed.contains(chosen[0].label), narrowed)
        XCTAssertFalse(narrowed.contains(chosen[1].label), narrowed)
        await library.remove(chosen[0])
        let missing = library.lookup(["query": "sump plug torque"], documentStore: store)
        XCTAssertTrue(missing.contains("no longer available"), missing)
        XCTAssertTrue(missing.contains("No other books were searched"), missing)
    }

    func testSelectionsFollowThreadsAndRoundTripWithoutChangingLegacyThreads() throws {
        let first = conversations.startThread(mode: "direct")
        conversations.noteActiveThreadActivity(at: Date().addingTimeInterval(-3_600))
        XCTAssertTrue(conversations.setManualIDs(["workshop", "electrical", "workshop"], for: first.id))
        XCTAssertLessThan(Date().timeIntervalSince(try XCTUnwrap(conversations.activeThreadLastActivityAt)), 2,
                          "Choosing manuals is activity, so the next voice turn must retain this chat's selection")
        let encoded = try JSONEncoder().encode(conversations.threads[0])
        let decoded = try JSONDecoder().decode(ConversationThread.self, from: encoded)
        XCTAssertEqual(decoded.manualIDs, ["electrical", "workshop"])
        let second = conversations.startThread(mode: "direct")
        XCTAssertTrue(PersonalManualLibrary.shared.selectedManualIDs.isEmpty)
        XCTAssertTrue(conversations.setManualIDs(["washer"], for: second.id))
        _ = conversations.resumeThread(first.id)
        XCTAssertEqual(PersonalManualLibrary.shared.selectedManualIDs, ["electrical", "workshop"])
        _ = conversations.resumeThread(second.id)
        XCTAssertEqual(PersonalManualLibrary.shared.selectedManualIDs, ["washer"])
        XCTAssertTrue(conversations.setManualIDs([], for: second.id))
        XCTAssertNil(conversations.threads.first { $0.id == second.id }?.manualIDs)
        conversations.isLocked = true
        XCTAssertFalse(conversations.setManualIDs(["wrong"], for: first.id))
        conversations.isLocked = false
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "manualIDs")
        XCTAssertNil(try JSONDecoder().decode(ConversationThread.self, from: JSONSerialization.data(withJSONObject: legacy)).manualIDs)
    }

    func testSelectionSurvivesDiskReloadWithConversationPersistence() throws {
        let savedPersistence = UserDefaults.standard.object(forKey: "conversationPersistenceEnabled")
        let savedEncryption = UserDefaults.standard.object(forKey: "conversationEncryptionEnabled")
        defer {
            UserDefaults.standard.set(savedPersistence, forKey: "conversationPersistenceEnabled")
            UserDefaults.standard.set(savedEncryption, forKey: "conversationEncryptionEnabled")
        }
        Config.setConversationPersistenceEnabled(true)
        Config.setConversationEncryptionEnabled(false)
        let thread = conversations.startThread(mode: "direct")
        XCTAssertTrue(conversations.setManualIDs(["workshop", "electrical"], for: thread.id))
        let reloaded = ConversationStore(directory: root)
        XCTAssertEqual(reloaded.threads.first { $0.id == thread.id }?.manualIDs, ["electrical", "workshop"])
    }

    func testSelectionChangeClearsSourceMemoryAndStaleSelectionDoesNotSearchOtherBooks() async throws {
        let (folder, _) = try fixture()
        let manifest = try install(folder)
        _ = try await VaultImporter.syncDocuments(manifest: manifest, into: store, pictureReader: nil)
        let library = PersonalManualLibrary.shared
        let manual = try XCTUnwrap(library.manuals.first { $0.manifest.id == manifest.id })
        let thread = conversations.startThread(mode: "direct")
        XCTAssertTrue(conversations.setManualIDs([manual.id], for: thread.id))
        let oldScope = library.sourceScope
        _ = library.lookup(["query": "sump plug torque"], documentStore: store)
        XCTAssertNotNil(library.promptContext)
        XCTAssertTrue(conversations.setManualIDs(["missing-book"], for: thread.id))
        library.selectionDidChange()
        XCTAssertNotEqual(oldScope, library.sourceScope)
        XCTAssertNil(library.takeStagedFigure())
        XCTAssertTrue(library.promptContext?.contains("unavailable") == true)
        XCTAssertTrue(library.lookup(["query": "sump plug torque"], documentStore: store).contains("No other books were searched"))
    }

    func testManualQuickActionIsUniqueManagedAndFollowsAvailability() {
        let actions = Config.withMyManualsAction([QuickAction.myManuals, QuickAction.recordMeeting, QuickAction.myManuals], available: true)
        XCTAssertEqual(actions.map(\.id), [QuickAction.myManuals.id, QuickAction.recordMeeting.id])
        XCTAssertEqual(Config.withMyManualsAction(actions, available: false).map(\.id), [QuickAction.recordMeeting.id])
        XCTAssertFalse(SpeedDialEditor.isEditable(QuickAction.myManuals))
        XCTAssertFalse(SpeedDialEditor.isDeletable(QuickAction.myManuals))
        XCTAssertTrue(DockSlot.action(.quickAction(.myManuals)).leadsWhenUnplaced)
        XCTAssertTrue(EditionPresentation.hidesDockSlot(.action(.quickAction(.myManuals)), restricted: true))
        XCTAssertFalse(EditionPresentation.hidesDockSlot(.action(.quickAction(.myManuals)), restricted: false))
    }

    func testWordAndMarkdownUploadsKeepOriginalsCiteReadingCopiesAndDeleteBothFiles() async throws {
        guard VaultImporter.installedManifest(id: "my-manuals") == nil else { throw XCTSkip("Preserve an existing library fixture") }
        let library = PersonalManualLibrary.shared
        var loaded: [PersonalManualLibrary.Manual] = []
        for ext in ["doc", "docx", "md"] {
            let input: URL
            if ext == "md" {
                input = root.appendingPathComponent("Invented manual.md")
                try Data("# Sump plug\nThe sump plug torque is 37 Nm. Tighten the sump plug to 37 Nm using a torque wrench.".utf8).write(to: input)
            } else { input = try ManualFileUploadTests.fixture(ext) }
            await library.addFile(input, title: "Invented \(ext) manual")
            if !installed.contains("my-manuals"), VaultImporter.installedManifest(id: "my-manuals") != nil { installed.append("my-manuals") }
            let manual = try XCTUnwrap(library.manuals.first { $0.document.title == "Invented \(ext) manual" }, library.status)
            XCTAssertTrue(library.isIndexed(manual), library.status)
            XCTAssertEqual(manual.document.personalReadingCopy, true)
            XCTAssertEqual(try Data(contentsOf: manual.original), try Data(contentsOf: input))
            let answer = library.lookup(["query": "sump plug torque", "document": manual.label], documentStore: store)
            XCTAssertTrue(answer.contains("37"), answer)
            XCTAssertTrue(answer.contains("reading copy"), answer)
            XCTAssertTrue(answer.contains("page 1"), answer)
            let staged = try XCTUnwrap(library.resolve(.init(kind: .manual, title: manual.label, page: 1)))
            XCTAssertEqual(library.sourceURL(for: staged), manual.pdf)
            XCTAssertEqual(manual.entry?.physicalPageCount, try ManualLibraryAdmission.pageCount(manual.pdf))
            loaded.append(manual)
            for old in loaded { XCTAssertTrue(FileManager.default.fileExists(atPath: old.original.path)) }
        }
        XCTAssertEqual(try ManualLibraryAdmission.inventory().filter { $0.id.hasPrefix("my-manuals/") }.count, 3)
        let deleting = try XCTUnwrap(loaded.first)
        let documentID = deleting.entry?.documentId
        await library.remove(deleting)
        XCTAssertFalse(FileManager.default.fileExists(atPath: deleting.original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: deleting.pdf.path))
        XCTAssertFalse(store.documents.contains { $0.id == documentID })
        XCTAssertEqual(try ManualLibraryAdmission.inventory().filter { $0.id.hasPrefix("my-manuals/") }.count, 2)
    }

    func testPersonalClaimOnALicenceStillHasTheOrganisationFloor() {
        let payload = LicenseService.LicensePayload(feature: "field_assist", licensee: "Fictional test", issued: Date(), expires: nil, tier: "personal")
        XCTAssertEqual(payload.resolvedTier, .team)
    }

    func testRegistryUpgradeAndDowngradeTakeEffectWithoutRecreatingTheRegistry() {
        UserDefaults.standard.set(true, forKey: "fieldAssistEnabled")
        let registry = NativeToolRegistry(locationService: LocationService(), documentStore: store)
        XCTAssertNotNil(registry.tool(named: "manual_lookup"))
        XCTAssertNil(registry.tool(named: "field_session"))
        FieldAssistEntitlement.shared.provider = StubEntitlementProvider.subscriber()
        XCTAssertNotNil(registry.tool(named: "field_session"))
        XCTAssertTrue(registry.toolNames.contains("procedure_runner"))
        FieldAssistEntitlement.shared.provider = AlwaysGrantedEntitlementProvider(tier: .personal)
        XCTAssertNil(registry.tool(named: "field_session"))
        XCTAssertFalse(registry.toolNames.contains("procedure_runner"))
        XCTAssertNotNil(registry.tool(named: "manual_lookup"))
    }
}
