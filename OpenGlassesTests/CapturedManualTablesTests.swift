import CoreGraphics
import Foundation
import PDFKit
import UIKit
import XCTest
@testable import OpenGlasses

/// Plan JN P4 — the tables printed on a photographed manual's pages: read by the scanned-page path
/// from the captured revision's own pages, only where IF's recognised text names a table; stored
/// with the captured document by IF's page map; redacted before anything keeps them and never
/// checkpointed; given by `table_lookup` from a picture with the captured page; checked on the
/// phone by the revision's identity; and gone with the capture. A fake reader stands in for Vision
/// (one test runs the real one on a drawn page). Every table, label, value and name is invented.
@MainActor
final class CapturedManualTablesTests: XCTestCase {
    private typealias F = RecognisedTableFixtures
    private typealias L = TableFixtureLayouts
    private var root: URL!
    private var source: CapturedManualStore!
    private var documents: DocumentStore!
    private var sessions: FieldSessionService!
    private var catalog: CapturedManualCatalog!
    private var checks: TableCheckStore!
    private var previousEntitlement: FieldAssistEntitlementProvider!
    private var previousEnabled: Any?
    private var previousHipaa = false
    private let vaultID = "jn_p4_capture_tables"

    /// A secret-shaped token, built at run time so no scanner reads it as a credential. It matches
    /// `SecretPatterns`' `openai_key` shape and is nobody's key.
    private static let secretToken = "sk-" + "proj-" + String(repeating: "Q", count: 24)

    override func setUp() async throws {
        try await super.setUp()
        root = TeamLearningFixtures.tempDirectory("CapturedManualTables")
        previousEnabled = UserDefaults.standard.object(forKey: "fieldAssistEnabled")
        UserDefaults.standard.set(true, forKey: "fieldAssistEnabled")
        previousHipaa = Config.hipaaMode; Config.hipaaMode = false
        previousEntitlement = EntitlementTestScope.grant(tier: .team)
        let folder = TeamLearningFixtures.writeVault(in: root, id: vaultID)
        let manifest = VaultManifest(id: vaultID, name: "Capture tables", version: "1.0.0",
                                     files: ["safety.md", "models.md"], proceduresDir: nil, documentsDir: nil, documents: [],
                                     gating: .init(iap: "enterprise"), promptRules: ["Never fabricate.", "Cite the source."])
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"))
        _ = try VaultImporter.install(from: folder)
        VaultRegistry.shared.reloadUserManifests(); VaultRegistry.shared.resetCache()
        source = try CapturedManualStore(root: root.appendingPathComponent("captures"), availableBytes: { Int.max })
        documents = TeamLearningFixtures.documentStore(in: root)
        checks = TableCheckStore(directory: root.appendingPathComponent("table-checks", isDirectory: true))
        catalog = CapturedManualCatalog(); catalog.injectedSource = source
        catalog.accessAllowed = { true }
        catalog.scopeForVault = { .init(ownershipScope: "personal", organizationID: "", enrolmentID: "", vaultID: $0) }
        catalog.documents = documents
        catalog.tableChecks = checks
        sessions = FieldSessionService(sessionsRoot: root.appendingPathComponent("sessions"))
        sessions.capturedManuals = catalog; sessions.documentStore = documents
        sessions.retrievalPolicy = .init(similarityFloor: 1.01)
        _ = try sessions.startSession(vaultId: vaultID, assetId: nil)
        TableCheckStore().removeAll(vaultId: vaultID)
    }

    override func tearDown() async throws {
        TableCheckStore().removeAll(vaultId: vaultID)
        sessions = nil; catalog = nil; documents = nil; source = nil; checks = nil
        VaultImporter.uninstall(id: vaultID)
        VaultRegistry.shared.reloadUserManifests(); VaultRegistry.shared.resetCache()
        try? FileManager.default.removeItem(at: root)
        if let previousEnabled { UserDefaults.standard.set(previousEnabled, forKey: "fieldAssistEnabled") }
        else { UserDefaults.standard.removeObject(forKey: "fieldAssistEnabled") }
        Config.hipaaMode = previousHipaa; EntitlementTestScope.restore(previousEntitlement)
        try await super.tearDown()
    }

    // MARK: - A fake recogniser over photographed pages

    /// Answers a whole-page reading with the next page's words, and the regions under its captions
    /// with that page's grid. Records how often it was asked.
    final class FakeCaptureReader: PictureTableReader, @unchecked Sendable {
        private let lock = NSLock()
        private var pagesRead = 0
        private var asked = 0
        let pageWords: [[RecognisedWord]]
        let grids: [RecognisedPage]
        init(pageWords: [[RecognisedWord]], grids: [RecognisedPage]) {
            self.pageWords = pageWords
            self.grids = grids
        }
        var wholePages: Int { lock.lock(); defer { lock.unlock() }; return pagesRead }
        var calls: Int { lock.lock(); defer { lock.unlock() }; return asked }

        func recognise(_ image: CGImage, render: PictureRegion.Render, reading: ManualTable.Source.Reader) async -> RecognisedPage {
            respond(render, reading)
        }
        private func respond(_ render: PictureRegion.Render, _ reading: ManualTable.Source.Reader) -> RecognisedPage {
            lock.lock(); defer { lock.unlock() }
            asked += 1
            if render.region.height > CGFloat(L.pageHeight) - 1 {
                pagesRead += 1
                return RecognisedPage(words: pagesRead <= pageWords.count ? pageWords[pagesRead - 1] : [])
            }
            guard reading == .documentGrid, pagesRead >= 1, pagesRead <= grids.count else { return RecognisedPage() }
            return grids[pagesRead - 1]
        }
    }

    /// Page one prints Table Q7 under its caption; page two captions Table 98 with nothing under it.
    private func reader(grid: RecognisedPage = F.q7Grid()) -> FakeCaptureReader {
        FakeCaptureReader(pageWords: [F.words("Table Q7 Invented clearances", x: 50, y: 60, size: 10),
                                      F.words("Table 98 Invented gaps", x: 50, y: 60, size: 10)],
                          grids: [grid, RecognisedPage()])
    }

    /// What IF recognised on each photographed page (already redacted by IF).
    private static let pageTexts = [
        "Table Q7 Invented clearances\nDesignation Clearance Spacing Limit\nPage 41",
        "Table 98 Invented gaps\nPage 42",
        "Other page about the invented blower\nPage 43",
    ]

    /// Three photographed pages as an image-only PDF, as `CapturedManualMedia.pdf` makes one.
    private func pagesPDF() -> Data {
        UIGraphicsPDFRenderer(bounds: TableFixtures.pageSize).pdfData { context in
            for _ in 0..<3 {
                context.beginPage()
                UIColor.lightGray.setFill()
                context.fill(CGRect(x: 60, y: 120, width: 480, height: 300))
            }
        }
    }

    private func capture(revision: Int64 = 1, reader: PictureTableReader?) async throws -> CapturedManualContract.Manifest {
        catalog.pictureReader = reader
        let session = try XCTUnwrap(sessions.activeSession)
        let m = CapturedManualStore.Metadata(captureID: "tables-book", revision: revision, sessionID: session.id,
            jobReference: "JOB-INVENTED", jobID: "", jobRevision: 0, scope: catalog.scopeForVault(vaultID),
            unitID: session.continuityScope, statedModel: "", confirmedModelToken: "", serial: "",
            title: "Invented clearance book", author: "Technician", capturedAt: 1_800_000_000, policy: "jobOnly", poolIntent: "jobOnly")
        _ = try source.begin(m, languages: ["en-US"], fallback: false)
        for page in 1...3 { try source.appendImage(Data("\(page)".utf8), to: m.key) }
        try source.finishStaging(m.key)
        let pdf = pagesPDF()
        let assembler = CapturedManualAssembler(store: source, read: { bytes, _, _ in
            let page = Int(String(decoding: bytes, as: UTF8.self)) ?? 0
            return .init(text: Self.pageTexts[page - 1], confidence: 0.95)
        }, makePDF: { _, _ in pdf }, pageCount: { try XCTUnwrap(PDFDocument(data: $0)).pageCount })
        let result = try await assembler.assemble(m.key)
        try await catalog.index(result)
        return result
    }

    private func lookup(row: String, column: String = "Spacing") async throws -> String {
        try await TableLookupTool(documentStore: documents, sessionService: sessions, currentUtterance: { nil })
            .execute(args: ["table": "Table Q7", "row": row, "column": column])
    }

    // MARK: - Which pages, and where the tables go

    func testOnlyPagesWhoseRecognisedTextNamesATableAreRead() {
        let pages = Self.pageTexts.enumerated().map { (number: $0.offset + 1, text: $0.element) }
        XCTAssertEqual(CapturedManualTables.pagesNamingTables(pages), [1, 2])
        XCTAssertEqual(CapturedManualTables.pagesNamingTables([(number: 1, text: "Figure Q7 Invented drawing\nsee Table")]), [])
    }

    func testACaptionedTableIsStoredWithTheCapturedDocumentByIFsPageMap() async throws {
        let fake = reader()
        let m = try await capture(reader: fake)
        XCTAssertEqual(fake.wholePages, 2, "the page naming no table is never recognised")
        XCTAssertEqual(fake.calls, 6, "each named page once, then each caption's region twice")

        let stored = documents.tables(documentId: m.documentID)
        let q7 = try XCTUnwrap(stored.first { $0.label == "Table Q7" })
        XCTAssertTrue(q7.source.isRecognised)
        XCTAssertEqual(q7.page.physical, 1, "the photograph's capture index")
        XCTAssertEqual(q7.page.printed, "41", "the number IF detected on the page")
        XCTAssertEqual(q7.pictureAreas.map(\.physical), [1])
        XCTAssertEqual(q7.rows.map { $0.path.first }, ["QXRT", "QMX90", "QZ12", "QA7"])
        XCTAssertEqual(documents.storedTables(namespace: m.documentID).count, 2)
        XCTAssertTrue(documents.storedTables(namespace: DocumentStore.vaultNamespace(vaultID)).isEmpty)

        // The pointer: a caption with no table under it names its page and gives nothing.
        let pointer = try XCTUnwrap(stored.first { $0.label == "Table 98" })
        XCTAssertFalse(pointer.isExtracted)
        XCTAssertEqual(pointer.page.physical, 2)
        XCTAssertEqual(pointer.failure, .noTextLayer)

        // The captured bundle is what IF made: the tables add nothing to it.
        XCTAssertFalse(String(decoding: try Data(contentsOf: source.file(m, name: "manifest.json")), as: UTF8.self).contains("Table Q7 "))
        XCTAssertEqual(m.pages.count, 3)

        // "Show me the table" opens the photographed page the table was read from.
        let citation = try XCTUnwrap(CitationLineParser.parse("Source: \(CapturedManualCatalog.citationName(m)), page 1").first)
        let staged = try XCTUnwrap(sessions.stagedFigure(for: citation))
        XCTAssertEqual(staged.page, 1)
        XCTAssertTrue(sessions.manualPageSheet(for: staged).photographed)
    }

    func testWithNoReaderNoTablesAreReadAndTheTextIsStillIndexed() async throws {
        let m = try await capture(reader: nil)
        XCTAssertTrue(documents.tables(documentId: m.documentID).isEmpty)
        XCTAssertEqual(documents.pageTexts(documentId: m.documentID).map(\.page), [1, 2, 3])
    }

    func testThePhotographedFloorIsItsOwnConstant() {
        let context = CapturedManualTables.context(reader())
        XCTAssertEqual(context.floor, PictureTableReading.capturedFloor)
        XCTAssertEqual(context.reading, PictureTableReading.preferred)
        XCTAssertNil(context.checkpoint, "a photographed page's recognition is never checkpointed")
    }

    // MARK: - Redaction before persistence

    func testASecretShapedCellIsRedactedUnclearAndNeverPersisted() async throws {
        XCTAssertTrue(SecretPatterns.containsSensitive(Self.secretToken), "the fixture must be one the patterns catch")
        let grid = F.replacing(F.q7Grid(), row: 2, column: 2, with: Self.secretToken)
        let m = try await capture(reader: reader(grid: grid))

        let q7 = try XCTUnwrap(documents.tables(documentId: m.documentID).first { $0.label == "Table Q7" })
        let cell = q7.rows[1].cells[1]
        XCTAssertEqual(cell.text, SecretPatterns.redactionPlaceholder)
        XCTAssertTrue(cell.uncertain)
        XCTAssertNil(cell.value)

        // Nothing under the test's root — the index, its row passages, IF's files — holds the token,
        // and no table recognition was checkpointed anywhere.
        let needle = Data(Self.secretToken.utf8)
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])?
            .compactMap { $0 as? URL } ?? []
        for url in files where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            let data = try Data(contentsOf: url)
            XCTAssertNil(data.range(of: needle), "unredacted text in \(url.lastPathComponent)")
            XCTAssertFalse(url.lastPathComponent.hasSuffix("-tables.json"), "a recognition checkpoint was written")
        }

        // Never given: the lookup refuses it as unclear, and gives its clear neighbour.
        let refused = try await lookup(row: "QMX90")
        XCTAssertTrue(refused.contains("this cell could not be read clearly from the picture"), refused)
        XCTAssertFalse(refused.contains(Self.secretToken), refused)
    }

    func testRedactionMarksAChangedRowNameAndHeadingUnclear() throws {
        let table = ManualTable(label: "Table Q7", title: "Invented clearances", page: .init(physical: 1),
                                columns: [.init(path: [Self.secretToken]), .init(path: ["Spacing (mm)"])],
                                rows: [.init(path: ["QX " + Self.secretToken], cells: [.init(text: "12", value: 12), .init(text: "30", value: 30)],
                                             page: .init(physical: 1)),
                                       .init(path: ["QMX90"], cells: [.init(text: "14", value: 14), .init(text: "35", value: 35)],
                                             page: .init(physical: 1))],
                                source: .recognised(reader: .documentGrid, meanConfidence: 0.9))
        let safe = CapturedManualTables.redacted(table)
        let out = try XCTUnwrap(safe.table)
        XCTAssertEqual(safe.redacted, 2)
        XCTAssertTrue(out.columns[0].uncertain)
        XCTAssertFalse(out.columns[1].uncertain)
        XCTAssertTrue(out.rows[0].keyUncertain)
        XCTAssertFalse(out.rows[1].keyUncertain)
        XCTAssertEqual(out.rows[1], table.rows[1], "an untouched row is kept as read")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(out), as: UTF8.self).contains(Self.secretToken))
    }

    // MARK: - Lookup, checks

    func testALookupOnACapturedTableSaysItWasReadFromAPictureOnTheCapturedPage() async throws {
        let m = try await capture(reader: reader())
        let text = try await lookup(row: "QXRT")
        XCTAssertTrue(text.contains("\"30\""), text)
        XCTAssertTrue(text.contains(TableLookup.pictureNote(documentName: CapturedManualCatalog.citationName(m),
                                                            page: .init(physical: 1, printed: "41"))), text)
        XCTAssertTrue(text.contains("read the value back to the technician to check against the page"), text)
        // "Show me the table" outlines where it was read, on the photographed page.
        let cited = try XCTUnwrap(TableLookup.citations(documentName: CapturedManualCatalog.citationName(m), label: "Table Q7",
                                                        pages: [.init(physical: 1, printed: "41")]).first)
        XCTAssertEqual(sessions.sourceCenter.pictureAreas(for: cited).map(\.physical), [1])
        let staged = try XCTUnwrap(sessions.stagedFigure(for: cited))
        var shown = staged
        shown.pictureAreas = sessions.sourceCenter.pictureAreas(for: cited)
        XCTAssertNotNil(sessions.manualPageSheet(for: shown).pictureLine)

        let pointer = try await TableLookupTool(documentStore: documents, sessionService: sessions, currentUtterance: { nil })
            .execute(args: ["table": "Table 98", "row": "QA1"])
        XCTAssertTrue(pointer.contains("Do not answer from memory") || pointer.contains("could not be read"), pointer)
    }

    func testAPhoneCheckKeyedByTheRevisionIdentityApplies() async throws {
        let m = try await capture(reader: reader())
        let hash = try XCTUnwrap(CapturedManualTables.checkHash(m))
        XCTAssertEqual(hash, CapturedManualContract.digest(try CapturedManualContract.canonicalBytes(m)))
        XCTAssertEqual(hash.count, 64)
        let check = TableCheck(documentHash: hash, table: "Table Q7", row: ["QXRT"], column: ["Spacing (mm)"], kind: .corrected,
                               value: "31", by: "the vault manager", at: Date(timeIntervalSince1970: 1_800_000_000), origin: .phone)
        try VaultTableChecks.record([check], vaultId: vaultID, photographed: true)
        XCTAssertEqual(TableCheckStore().checks(vaultId: vaultID).map(\.value), ["31"], "the phone's own store")
        XCTAssertNil(try? Data(contentsOf: VaultImporter.overlayDirectory(for: vaultID).appendingPathComponent(TableChecksFile.fileName)),
                     "never written into the vault's own file")

        let text = try await lookup(row: "QXRT")
        XCTAssertTrue(text.contains("\"31\""), text)
        XCTAssertTrue(text.contains("checked by the vault manager on " + TableChecks.day(check.at)), text)
        XCTAssertFalse(text.contains("read the value back to the technician to check against the page"), text)

        // A share file carries it under the same identity.
        let shared = try XCTUnwrap(try VaultTableChecks.shareFile(VaultTableChecks.checks(vaultId: vaultID, photographed: true),
                                                                   documentHash: hash))
        XCTAssertEqual(TableChecksFile.parse(try Data(contentsOf: shared)).checks.map(\.documentHash), [hash])
    }

    // MARK: - Gone with the capture

    func testANewRevisionReReadsItsOwnPagesAndTheOldTablesGo() async throws {
        let first = try await capture(reader: reader())
        XCTAssertFalse(documents.tables(documentId: first.documentID).isEmpty)
        let fake = reader()
        let second = try await capture(revision: 2, reader: fake)
        XCTAssertEqual(fake.wholePages, 2, "the new revision's own pages are read")
        XCTAssertTrue(documents.tables(documentId: first.documentID).isEmpty)
        XCTAssertEqual(documents.tables(documentId: second.documentID).map(\.label).sorted(), ["Table 98", "Table Q7"])
        XCTAssertNotEqual(CapturedManualTables.checkHash(first), CapturedManualTables.checkHash(second))
    }

    func testForgettingTheCaptureRemovesItsTablesAndChecks() async throws {
        let m = try await capture(reader: reader())
        let hash = try XCTUnwrap(CapturedManualTables.checkHash(m))
        try checks.save([TableCheck(documentHash: hash, table: "Table Q7", row: ["QXRT"], column: ["Spacing (mm)"], kind: .confirmed,
                                    value: "30", by: "the vault manager", at: Date(), origin: .phone)], vaultId: vaultID)
        try catalog.forget(m.captureID)
        XCTAssertTrue(documents.tables(documentId: m.documentID).isEmpty)
        XCTAssertTrue(documents.storedTables(namespace: nil, documentIds: [m.documentID]).isEmpty)
        XCTAssertTrue(checks.checks(vaultId: vaultID).isEmpty)
        let text = try await lookup(row: "QXRT")
        XCTAssertFalse(text.contains("\"30\""), text)
    }

    func testTheSubjectDeleteOfTheCaptureRemovesItsTablesAndChecks() async throws {
        let m = try await capture(reader: reader())
        let hash = try XCTUnwrap(CapturedManualTables.checkHash(m))
        try checks.save([TableCheck(documentHash: hash, table: "Table Q7", row: ["QXRT"], column: ["Spacing (mm)"], kind: .confirmed,
                                    value: "30", by: "the vault manager", at: Date(), origin: .phone)], vaultId: vaultID)
        var stores = SubjectErasureCoordinator.Stores()
        stores.capturedManuals = source
        stores.documents = documents
        stores.tableChecks = checks
        let receipts = await SubjectErasureCoordinator(stores: stores).erase(.document(id: m.documentID), recordInLedger: false)
        let tableReceipt = try XCTUnwrap(receipts.first { $0.store == .tableChecks })
        XCTAssertEqual(tableReceipt, ErasureReceipt.complete(.tableChecks, removed: 1))
        XCTAssertTrue(documents.tables(documentId: m.documentID).isEmpty)
        XCTAssertTrue(checks.checks(vaultId: vaultID).isEmpty)
        XCTAssertTrue(try source.manifests().isEmpty)
    }

    // MARK: - The real recogniser on a drawn photograph

    /// A ruled table with its caption drawn onto a page image, turned a degree as a hand-held
    /// photograph is, then through IF's real encoder, PDF and recognition and the real
    /// `VisionTableReader`.
    func testAPhotographedRuledTableReadsWithVision() async throws {
        let image = try XCTUnwrap(Self.photographedPage())
        let jpeg = try CapturedManualMedia.jpeg(image)
        let session = try XCTUnwrap(sessions.activeSession)
        let metadata = CapturedManualStore.Metadata(captureID: "vision-book", revision: 1, sessionID: session.id,
            jobReference: "JOB-INVENTED", jobID: "", jobRevision: 0, scope: catalog.scopeForVault(vaultID),
            unitID: session.continuityScope, statedModel: "", confirmedModelToken: "", serial: "",
            title: "Invented gap book", author: "Technician", capturedAt: 1_800_000_000, policy: "jobOnly", poolIntent: "jobOnly")
        _ = try source.begin(metadata, languages: ["en-US"], fallback: false)
        try source.appendImage(jpeg, to: metadata.key)
        try source.finishStaging(metadata.key)
        let assembler = CapturedManualAssembler(store: source,
            read: { try await CapturedManualMedia.recognize($0, languages: $1, fallback: $2) },
            makePDF: { try CapturedManualMedia.pdf($0, imageAt: $1) }, pageCount: { try CapturedManualMedia.pageCount($0) })
        let m = try await assembler.assemble(metadata.key)
        let text = String(decoding: try Data(contentsOf: source.file(m, name: "text.md")), as: UTF8.self)
        guard text.localizedCaseInsensitiveContains("table") else {
            throw XCTSkip("Vision recognised no caption on the drawn page in this simulator; the device pass covers it")
        }
        catalog.pictureReader = VisionTableReader()
        try await catalog.index(m)
        let stored = documents.tables(documentId: m.documentID)
        let table = try XCTUnwrap(stored.first { $0.label == "Table 98" }, "\(stored.map(\.label))")
        guard table.isExtracted else {
            throw XCTSkip("Vision found the caption but no grid under it on this simulator (\(table.failure?.rawValue ?? "none")); the device pass covers it")
        }
        XCTAssertTrue(table.source.isRecognised)
        XCTAssertEqual(table.page.physical, 1)
        XCTAssertEqual(table.pictureAreas.map(\.physical), [1])
        let keys = table.rows.compactMap(\.path.last)
        XCTAssertTrue(keys.contains("QMX90") || keys.contains("QXRT"), "\(keys)")
        let row = try XCTUnwrap(table.rows.first { $0.path.last == "QMX90" })
        let given = row.cells.filter { !$0.uncertain }.map(\.text)
        XCTAssertTrue(Set(given).isSubset(of: ["14", "20"]), "a clear cell reads as drawn: \(given)")
    }

    /// An invented ruled table on a white page, 1700 × 2200 pixels, turned one degree.
    private static func photographedPage() -> CGImage? {
        let size = CGSize(width: 1700, height: 2200)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let rows = [["Designation", "Gap (mm)", "Limit (A)"], ["QXRT", "12", "16"], ["QMX90", "14", "20"],
                    ["QZ12", "18", "25"], ["QA7", "22", "32"], ["QB4", "26", "40"]]
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            let cg = context.cgContext
            cg.translateBy(x: size.width / 2, y: size.height / 2)
            cg.rotate(by: .pi / 180)
            cg.translateBy(x: -size.width / 2, y: -size.height / 2)
            let caption: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 44), .foregroundColor: UIColor.black]
            NSString(string: "Table 98 Invented gaps").draw(at: CGPoint(x: 160, y: 200), withAttributes: caption)
            let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 40), .foregroundColor: UIColor.black]
            let left = 160.0, top = 320.0, widths = [520.0, 420.0, 420.0], height = 110.0
            UIColor.black.setStroke()
            let total = widths.reduce(0, +)
            for line in 0...rows.count {
                let path = UIBezierPath(); path.lineWidth = 3
                path.move(to: CGPoint(x: left, y: top + Double(line) * height))
                path.addLine(to: CGPoint(x: left + total, y: top + Double(line) * height)); path.stroke()
            }
            var x = left
            for column in 0...widths.count {
                let path = UIBezierPath(); path.lineWidth = 3
                path.move(to: CGPoint(x: x, y: top))
                path.addLine(to: CGPoint(x: x, y: top + Double(rows.count) * height)); path.stroke()
                if column < widths.count { x += widths[column] }
            }
            for (r, row) in rows.enumerated() {
                var cellX = left
                for (c, text) in row.enumerated() {
                    NSString(string: text).draw(at: CGPoint(x: cellX + 30, y: top + Double(r) * height + 30), withAttributes: body)
                    cellX += widths[c]
                }
            }
            NSString(string: "7").draw(at: CGPoint(x: 840, y: 2050), withAttributes: body)
        }
        return image.cgImage
    }
}
