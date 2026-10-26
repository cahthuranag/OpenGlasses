import PDFKit
import UIKit
import XCTest
@testable import OpenGlasses

/// Plan JK P1e exit: the allowance at every door, through the real admission lock, on an
/// in-memory history (never the live keychain or iCloud store). Manual content is invented.
@MainActor
final class ManualAdditionAdmissionTests: XCTestCase {
    private var root: URL!
    private var previousProvider: FieldAssistEntitlementProvider!
    private var previousAdditions: ManualAdditionHistoryStore!
    private var previousStore: DocumentStore?
    private var previousConversations: ConversationStore?
    private var conversations: ConversationStore!
    private var previousSwitch: Any?
    private var previousAnswers: Any?
    private var backend: InMemoryManualAdditionBackend!
    private var store: DocumentStore!
    private var installed: [String] = []
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        previousProvider = EntitlementTestScope.grant(tier: .personal)
        FieldAssistEntitlement.shared.clock = { [start] in start }
        previousAdditions = ManualLibraryAdmission.additions
        backend = InMemoryManualAdditionBackend()
        ManualLibraryAdmission.additions = ManualAdditionHistoryStore(backend: backend, subscriptionKey: { "store-test" })
        previousSwitch = UserDefaults.standard.object(forKey: "fieldAssistEnabled")
        previousAnswers = UserDefaults.standard.object(forKey: "myManualsEnabled")
        UserDefaults.standard.set(false, forKey: "fieldAssistEnabled")
        Config.myManualsEnabled = true
        root = FileManager.default.temporaryDirectory.appendingPathComponent("JK-allowance-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = DocumentStore(directory: root)
        previousStore = PersonalManualLibrary.shared.documents
        PersonalManualLibrary.shared.documents = store
        previousConversations = PersonalManualLibrary.shared.conversations
        conversations = ConversationStore(directory: root)
        PersonalManualLibrary.shared.conversations = conversations
    }

    override func tearDown() {
        for id in installed { VaultImporter.uninstall(id: id) }
        VaultRegistry.shared.reloadUserManifests(); VaultRegistry.shared.resetCache()
        PersonalManualLibrary.shared.documents = previousStore
        PersonalManualLibrary.shared.conversations = previousConversations
        conversations = nil
        PersonalManualLibrary.shared.selectionDidChange()
        ShowSourceCenter.shared.clearForAccessLoss()
        ManualLibraryAdmission.additions = previousAdditions
        EntitlementTestScope.restore(previousProvider)
        if let previousSwitch { UserDefaults.standard.set(previousSwitch, forKey: "fieldAssistEnabled") }
        else { UserDefaults.standard.removeObject(forKey: "fieldAssistEnabled") }
        if let previousAnswers { UserDefaults.standard.set(previousAnswers, forKey: "myManualsEnabled") }
        else { UserDefaults.standard.removeObject(forKey: "myManualsEnabled") }
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func advance(days: Double) {
        let moved = FieldAssistEntitlement.shared.clock().addingTimeInterval(days * 86_400)
        FieldAssistEntitlement.shared.clock = { moved }
    }

    /// One distinct invented manual: the label is drawn into the page, so the bytes differ.
    private func pdf(_ label: String) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage()
            ("\(label). Sump plug installation. The sump plug torque is 30 Nm. Tighten the sump plug to 30 Nm.\n" as NSString)
                .draw(in: CGRect(x: 40, y: 40, width: 520, height: 650), withAttributes: [.font: UIFont.systemFont(ofSize: 16)])
        }
    }

    /// A one-manual signed set laid out as a folder.
    private func set(_ documents: [Data]) throws -> (URL, VaultManifest) {
        let id = "jk-allowance-" + UUID().uuidString.lowercased()
        let folder = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let docs = try documents.enumerated().map { index, data in
            try data.write(to: folder.appendingPathComponent("book-\(index).pdf"))
            return VaultDocument(file: "book-\(index).pdf", title: "Invented book \(index)")
        }
        let manifest = VaultManifest(id: id, name: "Invented", version: "1", files: [], documents: docs, gating: .init(iap: "my_manuals"))
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
        return (folder, manifest)
    }

    @discardableResult
    private func install(_ data: Data...) throws -> VaultManifest {
        let (folder, manifest) = try set(data)
        do {
            let report = try VaultImporter.installReporting(from: folder, origin: .receivedSigned)
            installed.append(report.manifest.id)
            VaultRegistry.shared.reloadUserManifests(); VaultRegistry.shared.resetCache()
            return report.manifest
        } catch {
            XCTAssertNil(VaultImporter.installedManifest(id: manifest.id), "a refused set leaves nothing behind")
            throw error
        }
    }

    private func remove(_ manifest: VaultManifest) {
        VaultImporter.uninstall(id: manifest.id)
        installed.removeAll { $0 == manifest.id }
        VaultRegistry.shared.reloadUserManifests(); VaultRegistry.shared.resetCache()
    }

    private func preflight(_ data: Data...) throws {
        let (folder, _) = try set(data)
        let files = try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
        try VaultLinkInstaller.personalPreflight(files: files)
    }

    private var remaining: Int? { ManualLibraryAdmission.allowanceStatus()?.remaining }

    /// Five free fills, then three new manuals, each swapped in by removing one: the allowance is spent.
    private func spendTheWindow() throws -> (shelf: [VaultManifest], firstBytes: Data) {
        let first = pdf("Invented manual 1")
        var shelf = [try install(first)]
        for index in 2...5 { shelf.append(try install(pdf("Invented manual \(index)"))) }
        XCTAssertEqual(ManualLibraryAdmission.allowanceStatus()?.freeRemaining, 0)
        XCTAssertEqual(remaining, 3, "filling the shelf never touches the allowance")
        for index in 6...8 {
            remove(shelf.removeLast())
            shelf.append(try install(pdf("Invented manual \(index)")))
        }
        XCTAssertEqual(remaining, 0)
        remove(shelf.removeLast())
        return (shelf, first)
    }

    func testTheNewManualAfterTheAllowanceIsRefusedAtEveryDoorWithTheDate() async throws {
        _ = try spendTheWindow()
        let nextDate = ManualAdditionAllowance.dayMonth(start.addingTimeInterval(30 * 86_400))

        XCTAssertThrowsError(try install(pdf("Invented manual 9"))) {
            XCTAssertTrue($0.localizedDescription.contains("You've added 3 new manuals in the last 30 days"), $0.localizedDescription)
            XCTAssertTrue($0.localizedDescription.contains(nextDate), $0.localizedDescription)
        }
        XCTAssertThrowsError(try preflight(pdf("Invented manual 9"))) {
            XCTAssertTrue($0.localizedDescription.contains(nextDate), $0.localizedDescription)
        }
        XCTAssertThrowsError(try ManualLibraryAdmission.reserveCapture()) {
            XCTAssertTrue($0.localizedDescription.contains(nextDate), $0.localizedDescription)
        }

        if VaultImporter.installedManifest(id: "my-manuals") == nil {
            let input = root.appendingPathComponent("files-door.pdf")
            try pdf("Invented manual from Files").write(to: input)
            await PersonalManualLibrary.shared.addPDF(input, title: "Invented manual from Files")
            if VaultImporter.installedManifest(id: "my-manuals") != nil { installed.append("my-manuals"); XCTFail("the Files door admitted a new manual") }
            XCTAssertTrue(PersonalManualLibrary.shared.status.contains(nextDate), PersonalManualLibrary.shared.status)
        }

        // A day after the oldest spend comes back, there is room again.
        advance(days: 30)
        XCTAssertNoThrow(try install(pdf("Invented manual 9")))
    }

    func testAReturningManualInstallsWhenTheAllowanceIsSpent() throws {
        let (shelf, firstBytes) = try spendTheWindow()
        remove(shelf[0])
        XCTAssertNoThrow(try install(firstBytes), "a manual you've had before can come back any time")
        XCTAssertEqual(remaining, 0)
    }

    func testRemovingAndReAddingAManualCostsNothing() throws {
        let bytes = pdf("Invented swap manual")
        let manifest = try install(bytes)
        for index in 2...5 { try install(pdf("Invented fill \(index)")) }
        remove(manifest)
        XCTAssertNoThrow(try install(bytes))
        XCTAssertEqual(remaining, 3)
        // A reindex of what is held is not a new addition either.
        XCTAssertEqual(ManualLibraryAdmission.allowanceStatus()?.freeRemaining, 0)
    }

    func testAPreflightSpendsNothing() throws {
        var shelf: [VaultManifest] = []
        for index in 1...5 { shelf.append(try install(pdf("Invented fill \(index)"))) }
        remove(shelf.removeLast())
        let before = ManualLibraryAdmission.additions.history()
        XCTAssertNoThrow(try preflight(pdf("Invented reviewed set")))
        XCTAssertEqual(ManualLibraryAdmission.additions.history(), before)
    }

    func testASetThatDoesNotFitIsRefusedWhole() throws {
        var shelf: [VaultManifest] = []
        for index in 1...5 { shelf.append(try install(pdf("Invented fill \(index)"))) }
        remove(shelf.removeLast())
        shelf.append(try install(pdf("Invented new 1")))  // two left
        remove(shelf.removeLast()); remove(shelf.removeLast()); remove(shelf.removeLast())
        XCTAssertThrowsError(try install(pdf("Set A"), pdf("Set B"), pdf("Set C"))) {
            XCTAssertTrue($0.localizedDescription.contains("nothing was added"), $0.localizedDescription)
        }
        XCTAssertEqual(remaining, 2)
        XCTAssertNoThrow(try install(pdf("Set A"), pdf("Set B")))
        XCTAssertEqual(remaining, 0)
    }

    func testAnUndoAfterACitedAnswerRefundsNothingAndAnUnreadUndoDoes() async throws {
        var shelf: [VaultManifest] = []
        for index in 1...5 { shelf.append(try install(pdf("Invented fill \(index)"))) }
        remove(shelf.removeLast())

        // The wrong file, removed unread within the day: given back.
        let wrong = try install(pdf("Invented wrong file"))
        XCTAssertEqual(remaining, 2)
        let wrongManual = try XCTUnwrap(PersonalManualLibrary.shared.manuals.first { $0.manifest.id == wrong.id })
        advance(days: 0.25)
        await PersonalManualLibrary.shared.remove(wrongManual)
        XCTAssertEqual(remaining, 3, PersonalManualLibrary.shared.status)

        // The job's manual, used for an answer, removed the same day: spent.
        let used = try install(pdf("Invented job manual"))
        _ = try await VaultImporter.syncDocuments(manifest: used, into: store, pictureReader: nil)
        let manual = try XCTUnwrap(PersonalManualLibrary.shared.manuals.first { $0.manifest.id == used.id })
        let answer = PersonalManualLibrary.shared.lookup(["query": "sump plug torque", "document": manual.label], documentStore: store)
        XCTAssertTrue(answer.contains("30"), answer)
        advance(days: 0.25)
        await PersonalManualLibrary.shared.remove(manual)
        XCTAssertEqual(remaining, 2, "a manual an answer cited is not a wrong-file undo")
        XCTAssertEqual(PersonalManualLibrary.shared.status, "Manual removed.")
    }
}
