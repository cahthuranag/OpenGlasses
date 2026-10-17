import XCTest
@testable import OpenGlasses

/// The newest edition answers; an older one only when asked for (Plan IV P2).
@MainActor
final class DocumentEditionsTests: XCTestCase {

    private var tempRoot: URL!
    private var previousEntitlement: FieldAssistEntitlementProvider!
    private var installedVaultId: String?

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentEditionsTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        UserDefaults.standard.set(true, forKey: "fieldAssistEnabled")
        previousEntitlement = EntitlementTestScope.grant()
        VaultRegistry.shared.resetCache()
    }

    override func tearDown() {
        if let installedVaultId { VaultImporter.uninstall(id: installedVaultId) }
        VaultRegistry.shared.reloadUserManifests()
        VaultRegistry.shared.resetCache()
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: "fieldAssistEnabled")
        EntitlementTestScope.restore(previousEntitlement)
        super.tearDown()
    }

    // MARK: - Recognising editions

    func testTitlesThatDifferOnlyByAYearAreEditionsNewestFirst() {
        let editions = DocumentEditions(documents: [
            VaultDocument(file: "a.txt", title: "Fixture Code 2021", kind: "standard"),
            VaultDocument(file: "b.txt", title: "Fixture Code 2024", kind: "standard"),
            VaultDocument(file: "c.txt", title: "Fixture Wiring Guide", kind: "standard"),
        ])
        XCTAssertEqual(editions.works.count, 1)
        XCTAssertEqual(editions.works[0].map(\.title), ["Fixture Code 2024", "Fixture Code 2021"])
        XCTAssertEqual(editions.works[0].map(\.label), ["2024", "2021"])
        XCTAssertNil(editions.work(of: "Fixture Wiring Guide"), "a document with no other edition is not one")
    }

    func testTheManifestsEditionFieldNamesEditionsWhoseTitlesDontSayIt() {
        let editions = DocumentEditions(documents: [
            VaultDocument(file: "a.txt", title: "Fixture Code (previous)", kind: "standard", edition: "Rev B"),
            VaultDocument(file: "b.txt", title: "Fixture Code (current)", kind: "standard", edition: "Rev C"),
        ])
        // The titles differ by more than a label, so they are two works, each in one edition.
        XCTAssertTrue(editions.isEmpty)

        let same = DocumentEditions(documents: [
            VaultDocument(file: "a.txt", title: "Fixture Code Rev B", kind: "standard", edition: "Rev B"),
            VaultDocument(file: "b.txt", title: "Fixture Code Rev C", kind: "standard", edition: "Rev C"),
        ])
        XCTAssertEqual(same.works.first?.map(\.label), ["Rev C", "Rev B"])
    }

    func testAVaultWithOneEditionOfEachDocumentHasNoEditions() {
        for documents in [
            [VaultDocument(file: "a.txt", title: "SLP99UHVK Service Manual", kind: "service_manual"),
             VaultDocument(file: "b.txt", title: "SLP99UHVK Installation Instructions", kind: "install_guide")],
            [VaultDocument(file: "a.txt", title: "Fixture Code 2024", kind: "standard")],
            // Same year words but different kinds: a code book and a guide to it.
            [VaultDocument(file: "a.txt", title: "Fixture Code 2024", kind: "standard"),
             VaultDocument(file: "b.txt", title: "Fixture Code 2021", kind: "handbook")],
        ] {
            let editions = DocumentEditions(documents: documents)
            XCTAssertTrue(editions.isEmpty, "\(documents.map(\.title))")
            XCTAssertNil(editions.searchableTitles(for: .newest, among: documents.map(\.title)))
            XCTAssertEqual(EditionRequest.parse("what changed in the 2021 code", editions: editions), .newest)
        }
    }

    // MARK: - What a turn asks for

    private var twoEditions: DocumentEditions {
        DocumentEditions(documents: [
            VaultDocument(file: "a.txt", title: "Fixture Code 2021", kind: "standard"),
            VaultDocument(file: "b.txt", title: "Fixture Code 2024", kind: "standard"),
        ])
    }

    func testTheTurnDecidesTheEdition() {
        let e = twoEditions
        let table: [(String, EditionRequest)] = [
            ("what is the minimum clearance for a receptacle", .newest),
            ("what does the 2024 code say about clearance", .newest),
            ("what did the 2021 code say about clearance", .named(["2021"])),
            ("check the previous edition for that", .previous),
            ("what did the old code say", .previous),
            ("and in the last code?", .previous),
            ("what changed between the 2021 and 2024 code for clearance", .compare),
            ("what's changed for clearance", .compare),
            ("compare that with the previous edition", .compare),
            ("2021 versus 2024 clearance", .compare),
            ("compare the two readings", .newest),
        ]
        for (turn, expected) in table {
            XCTAssertEqual(EditionRequest.parse(turn, editions: e), expected, turn)
        }
    }

    func testEachRequestSearchesItsEditionsAndEverythingElse() {
        let e = twoEditions
        let titles = ["Fixture Code 2021", "Fixture Code 2024", "Fixture Wiring Guide"]
        XCTAssertEqual(e.searchableTitles(for: .newest, among: titles), ["Fixture Code 2024", "Fixture Wiring Guide"])
        XCTAssertEqual(e.searchableTitles(for: .previous, among: titles), ["Fixture Code 2021", "Fixture Wiring Guide"])
        XCTAssertEqual(e.searchableTitles(for: .named(["2021"]), among: titles), ["Fixture Code 2021", "Fixture Wiring Guide"])
        XCTAssertEqual(e.searchableTitles(for: .named(["1999"]), among: titles), ["Fixture Code 2024", "Fixture Wiring Guide"],
                       "a year no edition carries falls back to the newest")
        XCTAssertEqual(e.searchableTitles(for: .compare, among: titles), Set(titles))
    }

    // MARK: - Through the session: per-turn, manual_lookup, manual_figure, citations

    /// Two editions of one code that disagree on a number, and a guide that is no edition of
    /// anything.
    private func writeVault() throws -> URL {
        let dir = tempRoot.appendingPathComponent("vault", isDirectory: true)
        let docs = dir.appendingPathComponent("documents", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        func code(_ clearance: String) -> String {
            """
            Page 1

            Receptacles
            99-200 Receptacles near sinks
            A receptacle shall be at least \(clearance) mm from the edge of a sink basin.
            """
        }
        try code("1000").write(to: docs.appendingPathComponent("code-2021.txt"), atomically: true, encoding: .utf8)
        try code("1500").write(to: docs.appendingPathComponent("code-2024.txt"), atomically: true, encoding: .utf8)
        try "Page 2\n\nGrounding electrodes are driven to a depth of three metres.\n"
            .write(to: docs.appendingPathComponent("guide.txt"), atomically: true, encoding: .utf8)
        let manifest = VaultManifest(
            id: "editions_fixture", name: "Editions Fixture", version: "1.0.0", files: ["safety.md"],
            proceduresDir: nil, documentsDir: "documents",
            documents: [VaultDocument(file: "code-2021.txt", title: "Fixture Code 2021", kind: "standard"),
                        VaultDocument(file: "code-2024.txt", title: "Fixture Code 2024", kind: "standard"),
                        VaultDocument(file: "guide.txt", title: "Fixture Wiring Guide", kind: "handbook")],
            gating: .init(iap: "enterprise"), promptRules: ["Never fabricate.", "Cite the source."])
        try JSONEncoder().encode(manifest).write(to: dir.appendingPathComponent("manifest.json"))
        try "# Safety\n\nIsolate the supply first.".write(to: dir.appendingPathComponent("safety.md"), atomically: true, encoding: .utf8)
        return dir
    }

    private func startSession() async throws -> (FieldSessionService, DocumentStore, VaultStore) {
        let storeDir = tempRoot.appendingPathComponent("store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let store = DocumentStore(directory: storeDir)
        let manifest = try VaultImporter.install(from: try writeVault())
        installedVaultId = manifest.id
        VaultRegistry.shared.reloadUserManifests()
        VaultRegistry.shared.resetCache()
        _ = try await VaultImporter.syncDocuments(manifest: manifest, into: store)
        let service = FieldSessionService(sessionsRoot: tempRoot.appendingPathComponent("sessions", isDirectory: true))
        service.documentStore = store
        service.retrievalPolicy = RetrievalEvidencePolicy(similarityFloor: 0)
        _ = try service.startSession(vaultId: manifest.id, assetId: nil)
        return (service, store, VaultRegistry.shared.store(for: manifest))
    }

    func testThePerTurnPassagesComeFromTheNewestUnlessTheTurnAsksOtherwise() async throws {
        let (service, _, vault) = try await startSession()

        let plain = try XCTUnwrap(service.manualPassagesContext(turn: "rule 99-200 receptacle sink clearance", store: vault))
        XCTAssertTrue(plain.contains("Source: Fixture Code 2024"), plain)
        XCTAssertFalse(plain.contains("Source: Fixture Code 2021"), "the older edition is not searched by default: \(plain)")
        XCTAssertFalse(plain.contains("(edition:"), "nothing to label when only the newest answers")
        XCTAssertTrue(plain.contains("EDITIONS: these passages are from the newest edition"), plain)

        let older = try XCTUnwrap(service.manualPassagesContext(
            turn: "what did the 2021 code say for rule 99-200 receptacle sink clearance", store: vault))
        XCTAssertTrue(older.contains("Source: Fixture Code 2021"), older)
        XCTAssertFalse(older.contains("Source: Fixture Code 2024"), older)
        XCTAssertTrue(older.contains("(edition: 2021)"), older)

        let compare = try XCTUnwrap(service.manualPassagesContext(
            turn: "what changed for rule 99-200 receptacle sink clearance", store: vault))
        XCTAssertTrue(compare.contains("Source: Fixture Code 2021") && compare.contains("Source: Fixture Code 2024"), compare)
        XCTAssertTrue(compare.contains("(edition: 2021)") && compare.contains("(edition: 2024)"), compare)
        XCTAssertTrue(compare.contains("asked to compare editions"), compare)
    }

    func testManualLookupReadsTheTechniciansWordsForTheEdition() async throws {
        let (service, store, _) = try await startSession()
        var said: String? = nil
        let tool = ManualLookupTool(documentStore: store, sessionService: service, currentUtterance: { said })

        let plain = try await tool.execute(args: ["query": "rule 99-200 receptacle sink clearance"])
        XCTAssertTrue(plain.contains("Source: Fixture Code 2024") && !plain.contains("Source: Fixture Code 2021"), plain)

        said = "and what did the previous edition say about that"
        let older = try await tool.execute(args: ["query": "rule 99-200 receptacle sink clearance"])
        XCTAssertTrue(older.contains("Source: Fixture Code 2021") && !older.contains("Source: Fixture Code 2024"), older)

        // A document the model names is searched as named, whatever the default.
        said = nil
        let named = try await tool.execute(args: ["query": "rule 99-200 receptacle sink clearance", "document": "2021"])
        XCTAssertTrue(named.contains("Source: Fixture Code 2021"), named)
    }

    func testAPageInBothEditionsOpensInTheNewestAndAnOlderCitationStillOpens() async throws {
        let (service, store, _) = try await startSession()
        var said: String? = nil
        let tool = ManualFigureTool(documentStore: store, sessionService: service, currentUtterance: { said })

        _ = try await tool.execute(args: ["page": 1])
        XCTAssertEqual(service.stagedFigure?.documentTitle, "Fixture Code 2024",
                       "page 1 is in both editions of the code; the newest opens")

        said = "show me page 1 of the 2021 code"
        _ = try await tool.execute(args: ["page": 1])
        XCTAssertEqual(service.stagedFigure?.documentTitle, "Fixture Code 2021")

        // An answer that cited the older edition opens that edition's page, default or not.
        let cited = try XCTUnwrap(service.stagedFigure(for: Citation(kind: .manual, title: "Fixture Code 2021", page: 1)))
        XCTAssertEqual(cited.documentTitle, "Fixture Code 2021")
    }
}
