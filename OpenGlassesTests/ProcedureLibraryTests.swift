import XCTest
@testable import OpenGlasses

/// Tests for Procedure JSON decoding and ProcedureLibrary loading from a vault store overlay.
final class ProcedureLibraryTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProcedureLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    private let sampleJSON = """
    {
      "id": "sample_diag",
      "title": "Sample Diagnostic",
      "version": "1.0.0",
      "vault": "refrigeration",
      "safety_notes": ["Wear PPE."],
      "entry_step": "first",
      "steps": [
        {
          "id": "first",
          "title": "First step",
          "instruction": "Do the thing.",
          "expected_input": "a reading",
          "citations": ["pt_charts.md"],
          "branches": [
            { "id": "ok", "condition": "reading is normal", "next": "done" }
          ],
          "default_next": "done"
        },
        {
          "id": "done",
          "title": "Done",
          "instruction": "Finished.",
          "terminal": true,
          "outcome": "resolved"
        }
      ]
    }
    """

    // MARK: - Decoding

    func testDecodesSnakeCaseSchema() throws {
        let procedure = try JSONDecoder().decode(Procedure.self, from: Data(sampleJSON.utf8))
        XCTAssertEqual(procedure.id, "sample_diag")
        XCTAssertEqual(procedure.entryStep, "first")
        XCTAssertEqual(procedure.safetyNotes, ["Wear PPE."])
        XCTAssertEqual(procedure.steps.count, 2)

        let first = try XCTUnwrap(procedure.step(id: "first"))
        XCTAssertEqual(first.expectedInput, "a reading")
        XCTAssertEqual(first.citations, ["pt_charts.md"])
        XCTAssertEqual(first.defaultNext, "done")
        XCTAssertEqual(first.branches.first?.id, "ok")
        XCTAssertEqual(first.branches.first?.next, "done")
        XCTAssertFalse(first.terminal)

        let done = try XCTUnwrap(procedure.step(id: "done"))
        XCTAssertTrue(done.terminal)
        XCTAssertEqual(done.outcome, "resolved")
    }

    func testEntryFallsBackToFirstStepWhenUnset() {
        let procedure = Procedure(
            id: "p", title: "P", version: "1.0.0",
            steps: [.init(id: "only", title: "Only", instruction: "x")]
        )
        XCTAssertEqual(procedure.entry?.id, "only")
    }

    // MARK: - Loading from a vault store

    private func makeStore() -> VaultStore {
        let manifest = VaultManifest(
            id: "refrigeration", name: "Refrigeration Service", version: "1.0.0",
            files: [], proceduresDir: "procedures"
        )
        // bundleRoot nil → overlay-only; matches how user-uploaded procedures would load.
        return VaultStore(manifest: manifest, bundleRoot: nil, overlayRoot: tempRoot)
    }

    func testLoadsProceduresFromOverlayDirectory() throws {
        let proceduresDir = tempRoot.appendingPathComponent("procedures", isDirectory: true)
        try FileManager.default.createDirectory(at: proceduresDir, withIntermediateDirectories: true)
        try Data(sampleJSON.utf8).write(to: proceduresDir.appendingPathComponent("sample.json"))

        let library = ProcedureLibrary(store: makeStore())
        XCTAssertFalse(library.isEmpty)
        XCTAssertNotNil(library.procedure(id: "sample_diag"))
        XCTAssertEqual(library.summaries(), ["sample_diag — Sample Diagnostic"])
    }

    func testEmptyWhenNoProceduresDirectoryExists() {
        let library = ProcedureLibrary(store: makeStore())
        XCTAssertTrue(library.isEmpty)
    }

    func testIgnoresNonJSONFiles() throws {
        let proceduresDir = tempRoot.appendingPathComponent("procedures", isDirectory: true)
        try FileManager.default.createDirectory(at: proceduresDir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: proceduresDir.appendingPathComponent("readme.txt"))
        try Data(sampleJSON.utf8).write(to: proceduresDir.appendingPathComponent("sample.json"))

        let library = ProcedureLibrary(store: makeStore())
        XCTAssertEqual(library.all.count, 1)
    }

    // MARK: - One procedure per id

    /// A minimal valid procedure: one terminal step.
    private func procedureJSON(id: String, title: String) -> Data {
        Data("""
        {"id": "\(id)", "title": "\(title)", "version": "1.0.0", "safety_notes": [], "entry_step": "done",
         "steps": [{"id": "done", "title": "Done", "instruction": "Finished.", "terminal": true}]}
        """.utf8)
    }

    /// Two files declaring one id list it once, the same one every load. Listing both put two rows
    /// with one id in the Field Assist tab's `List`, in an order that changed between redraws — a
    /// `UICollectionView` batch-update assertion (TestFlight crash, build 556).
    func testTwoFilesDeclaringOneIdListItOnceByTheFirstFileName() throws {
        let proceduresDir = tempRoot.appendingPathComponent("procedures", isDirectory: true)
        try FileManager.default.createDirectory(at: proceduresDir, withIntermediateDirectories: true)
        try procedureJSON(id: "leak_check", title: "From b").write(to: proceduresDir.appendingPathComponent("b.json"))
        try procedureJSON(id: "leak_check", title: "From a").write(to: proceduresDir.appendingPathComponent("a.json"))
        try procedureJSON(id: "airflow", title: "Airflow").write(to: proceduresDir.appendingPathComponent("c.json"))

        for _ in 0..<5 {
            let library = ProcedureLibrary(store: makeStore())
            XCTAssertEqual(library.all.map(\.id), ["airflow", "leak_check"])
            XCTAssertEqual(library.procedure(id: "leak_check")?.title, "From a")
        }
    }

    func testTheOverlaysFileWinsOverTheBundlesForOneId() throws {
        let bundleRoot = tempRoot.appendingPathComponent("bundle", isDirectory: true)
        let overlayRoot = tempRoot.appendingPathComponent("overlay", isDirectory: true)
        for root in [bundleRoot, overlayRoot] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("procedures"),
                                                    withIntermediateDirectories: true)
        }
        // The bundle's file name sorts first; the overlay still wins.
        try procedureJSON(id: "leak_check", title: "Bundled")
            .write(to: bundleRoot.appendingPathComponent("procedures/a.json"))
        try procedureJSON(id: "leak_check", title: "Edited")
            .write(to: overlayRoot.appendingPathComponent("procedures/z.json"))
        let manifest = VaultManifest(id: "refrigeration", name: "Refrigeration Service", version: "1.0.0",
                                     files: [], proceduresDir: "procedures")

        let library = ProcedureLibrary(store: VaultStore(manifest: manifest, bundleRoot: bundleRoot,
                                                         overlayRoot: overlayRoot))
        XCTAssertEqual(library.all.map(\.title), ["Edited"])
    }

    func testResolveGivesTheSameListWhateverOrderTheFilesArriveIn() throws {
        func candidate(_ file: String, _ id: String, overlay: Bool = false) throws -> ProcedureLibrary.Candidate {
            let procedure = try JSONDecoder().decode(Procedure.self, from: procedureJSON(id: id, title: file))
            return .init(file: file, fromOverlay: overlay, procedure: procedure)
        }
        let candidates = [try candidate("b.json", "x"), try candidate("a.json", "x"),
                          try candidate("c.json", "w"), try candidate("d.json", "x", overlay: true)]
        let expected = ProcedureLibrary.resolve(candidates).map(\.title)
        XCTAssertEqual(expected, ["c.json", "d.json"])
        XCTAssertEqual(ProcedureLibrary.resolve(candidates.reversed()).map(\.title), expected)
        XCTAssertEqual(ProcedureLibrary.resolve([candidates[2], candidates[0], candidates[3], candidates[1]])
            .map(\.title), expected)
    }
}
