import CoreGraphics
import PDFKit
import SQLite3
import UIKit
import XCTest
@testable import OpenGlasses

/// Plan JN P1 — reading the tables printed as pictures at import: which captions are read from a
/// picture and which never are, a page with no text layer read whole, the text-layer reading left
/// exactly as it was without a reader, the checkpoint that keeps a relaunch from recognising a
/// region twice, the thermal step-down, and the location migration that reads stored manuals'
/// tables again without touching their text. A fake reader stands in for Vision; every table,
/// label and value is invented.
final class PictureTableReadingTests: XCTestCase {

    private typealias F = RecognisedTableFixtures
    private typealias L = TableFixtureLayouts
    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PictureTableReadingTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    // MARK: - A fake recogniser

    /// What the fake was asked, in order.
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var log: [(region: CGRect, scale: Double, reading: ManualTable.Source.Reader)] = []
        func record(_ render: PictureRegion.Render, _ reading: ManualTable.Source.Reader) {
            lock.lock(); defer { lock.unlock() }
            log.append((render.region, render.scale, reading))
        }
        var all: [(region: CGRect, scale: Double, reading: ManualTable.Source.Reader)] {
            lock.lock(); defer { lock.unlock() }
            return log
        }
    }

    struct FakeReader: PictureTableReader {
        let calls = Calls()
        /// What a region read as, by the reading asked for and the region drawn.
        let respond: @Sendable (PictureRegion.Render, ManualTable.Source.Reader) -> RecognisedPage

        func recognise(_ image: CGImage, render: PictureRegion.Render, reading: ManualTable.Source.Reader) async -> RecognisedPage {
            XCTAssertEqual(image.width, render.pixelWidth)
            XCTAssertEqual(image.height, render.pixelHeight)
            calls.record(render, reading)
            return respond(render, reading)
        }
    }

    /// Table Q7's invented grid for any region, its words for the words reading.
    private func gridReader() -> FakeReader {
        FakeReader { _, reading in reading == .documentGrid ? F.q7Grid() : RecognisedPage(words: F.q7Words(shift: 60)) }
    }

    private func document(_ pages: [L.Page]) throws -> PDFDocument {
        let url = try TableFixtures.write(TableFixtures.pdf(pages), named: "\(UUID().uuidString).pdf", in: tempRoot)
        return try XCTUnwrap(PDFDocument(url: url))
    }

    private func read(_ document: PDFDocument, _ reader: PictureTableReader?, reading: ManualTable.Source.Reader = .documentGrid,
                      thermal: ProcessInfo.ThermalState = .nominal,
                      checkpoint: (directory: URL, hash: String)? = nil) async -> PDFTableReader.Result {
        let context = reader.map { reader -> PictureTableReading.Context in
            var context = checkpoint.map { PictureTableReading.context(reader, checkpointIn: $0.directory, contentHash: $0.hash) }
                ?? PictureTableReading.Context(reader: reader)
            context.reading = reading
            context.floor = 0.6
            context.thermal = { thermal }
            return context
        }
        return await PDFTableReader.read(document: document, pictures: context)
    }

    /// A page with no text layer: a drawing only.
    private func scannedPDF() throws -> PDFDocument {
        let data = UIGraphicsPDFRenderer(bounds: TableFixtures.pageSize).pdfData { context in
            context.beginPage()
            UIColor.gray.setFill()
            context.fill(CGRect(x: 60, y: 100, width: 480, height: 300))
        }
        let url = try TableFixtures.write(data, named: "scan-\(UUID().uuidString).pdf", in: tempRoot)
        return try XCTUnwrap(PDFDocument(url: url))
    }

    /// A caption over two short rows, then a stretch of empty page and a paragraph: the text layer
    /// reads too few rows, and a picture sits under the caption.
    private static func pictureUnderShortCaption() -> L.Page {
        var items = [L.Item(text: "Table 96 Invented gaps", x: 50, y: 60),
                     L.Item(text: "QA1", x: 50, y: 76), L.Item(text: "10", x: 200, y: 76)]
        // Prose down to the footer, so no long stretch of the page is empty but the picture's.
        for line in 0..<42 {
            items.append(L.Item(text: "Invented paragraph line \(line + 1) that follows the pictured grid on this page.",
                                x: 50, y: 200 + Double(line) * 12))
        }
        items.append(L.Item(text: "44", x: 300, y: L.pageHeight - 40))
        return items
    }

    // MARK: - Without a reader, nothing changes

    func testWithNoReaderTheReadingIsTheTextLayersByteForByte() async throws {
        let layouts: [[L.Page]] = [[L.simpleGrid()], [L.tableWithoutText()], L.continued(), L.captionAtFoot(),
                                   [Self.pictureUnderShortCaption()], L.listOfTables()]
        for pages in layouts {
            let document = try document(pages)
            let plain = PDFTableReader.read(document: document)
            let none = await read(document, nil)
            XCTAssertEqual(none, plain)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            XCTAssertEqual(try encoder.encode(none.stored), try encoder.encode(plain.stored))
            XCTAssertEqual(none.recognised, 0)
            XCTAssertNil(none.pictureReader)
        }
        let scanned = try scannedPDF()
        let plain = PDFTableReader.read(document: scanned)
        let none = await read(scanned, nil)
        XCTAssertEqual(none, plain)
        XCTAssertEqual(none.pagesWithoutText, 1)
        XCTAssertTrue(none.stored.isEmpty)
    }

    func testATableTheTextLayerGaveIsNeverRecognised() async throws {
        let reader = gridReader()
        let document = try document([L.simpleGrid()])
        let result = await read(document, reader)
        XCTAssertEqual(reader.calls.all.count, 0, "text first: nothing to recognise")
        XCTAssertEqual(result, PDFTableReader.read(document: document))
        let json = String(decoding: try JSONEncoder().encode(result.stored), as: UTF8.self)
        for key in ["uncertain", "keyUncertain", "source", "pictureAreas"] {
            XCTAssertFalse(json.contains("\"\(key)\""), "a text-layer table stores no \(key)")
        }
    }

    // MARK: - The triggers

    func testACaptionWithNoTextInItsTableIsReadFromThePictureUnderIt() async throws {
        let document = try document([L.tableWithoutText()])
        XCTAssertEqual(PDFTableReader.read(document: document).failures, [.noTextInTable: 1])
        let reader = gridReader()
        let result = await read(document, reader)

        XCTAssertEqual(result.recognised, 1)
        XCTAssertEqual(result.pictureReader, .documentGrid)
        XCTAssertEqual(result.failures, [:])
        XCTAssertEqual(result.captioned, 1)
        let table = try XCTUnwrap(result.tables.first)
        XCTAssertEqual(table.label, "Table 97")
        XCTAssertEqual(table.page.printed, nil)
        XCTAssertTrue(table.source.isRecognised)
        XCTAssertEqual(table.rows.map(\.path), [["QXRT"], ["QMX90"], ["QZ12"], ["QA7"]])
        XCTAssertEqual(table.rows[1].cells.map(\.value), [14, 35, 20])

        // Two passes over the region under the caption, at the two scales, by the one reading.
        let calls = reader.calls.all
        XCTAssertEqual(calls.map(\.scale), [3, 2.5])
        XCTAssertEqual(Set(calls.map(\.reading)), [.documentGrid])
        let region = try XCTUnwrap(calls.first?.region)
        XCTAssertGreaterThan(region.minY, 100, "under the caption and the paragraph set close under it")
        XCTAssertLessThanOrEqual(region.maxY, CGFloat(L.pageHeight) * (1 - PictureRegion.footerBand) + 0.01, "above the footer band")
        XCTAssertEqual(calls.map(\.region), [region, region])
        // Where it was read from is kept for "show me the table" to outline (Plan JN P2).
        XCTAssertEqual(table.pictureAreas, [ManualTable.PictureArea(physical: 1, rect: region)])
    }

    func testTheWordsReadingFeedsTheExtractorInstead() async throws {
        let document = try document([L.tableWithoutText()])
        let reader = gridReader()
        let result = await read(document, reader, reading: .words)
        XCTAssertEqual(Set(reader.calls.all.map(\.reading)), [.words])
        let table = try XCTUnwrap(result.tables.first, "\(result.failures)")
        guard case .recognised(let by, let mean) = table.source else { return XCTFail("\(table.source)") }
        XCTAssertEqual(by, .words)
        XCTAssertEqual(mean, 0.97, accuracy: 0.0001)
        XCTAssertEqual(table.rows.map(\.path), [["QXRT"], ["QMX90"], ["QZ12"], ["QA7"]])
        XCTAssertEqual(result.pictureReader, .words)
    }

    func testACaptionWithTooFewRowsAndAPictureUnderItIsTried() async throws {
        let document = try document([Self.pictureUnderShortCaption()])
        XCTAssertEqual(PDFTableReader.read(document: document).failures, [.tooFewRows: 1])
        let reader = gridReader()
        let result = await read(document, reader)
        XCTAssertEqual(reader.calls.all.count, 2)
        let table = try XCTUnwrap(result.tables.first, "\(result.failures)")
        XCTAssertEqual(table.label, "Table 96")
        XCTAssertTrue(table.source.isRecognised)
    }

    func testAPictureThatMakesNoTableLeavesTheCaptionsOwnFailure() async throws {
        let document = try document([L.tableWithoutText(), Self.pictureUnderShortCaption()])
        // Two rows only: the extractor's own row test refuses it, for a picture as for text.
        let reader = FakeReader { _, _ in RecognisedPage(tables: [.init(cells: F.grid([F.q7Header, F.q7Body[0]]))]) }
        let result = await read(document, reader)
        XCTAssertEqual(reader.calls.all.count, 4)
        XCTAssertEqual(result.recognised, 0)
        XCTAssertEqual(result.failures, [.noTextInTable: 1, .tooFewRows: 1])
        XCTAssertEqual(result.unextracted.map(\.label), ["Table 97", "Table 96"])
    }

    func testATooFewRowsCaptionWithNoRoomUnderItIsNotTried() async throws {
        // Table 93's labels are scattered down the page: there is no empty stretch under it.
        let document = try document([L.drawingUnderTableCaption(pitch: 14)])
        let plain = PDFTableReader.read(document: document)
        let reader = gridReader()
        let result = await read(document, reader)
        XCTAssertEqual(reader.calls.all.count, 0, "\(plain.failures)")
        XCTAssertEqual(result, plain)
    }

    func testAListOfTablesIsNeverRecognised() async throws {
        let reader = gridReader()
        let document = try document(L.listOfTables())
        let result = await read(document, reader)
        XCTAssertEqual(result, PDFTableReader.read(document: document))
        XCTAssertEqual(reader.calls.all.count, 0, "no entry of the list is drawn")
    }

    func testAPageWithNoTextLayerIsReadWholeForItsCaptionThenUnderIt() async throws {
        let document = try scannedPDF()
        let caption = F.words("Table 95 Invented spans", x: 50, y: 60, size: 10)
        let footer = F.words("45", x: 300, y: L.pageHeight - 40)
        let reader = FakeReader { render, reading in
            // The whole page, read by words to find its captions; then the region under one.
            if render.region.height > CGFloat(L.pageHeight) - 1 { return RecognisedPage(words: caption + footer) }
            return reading == .documentGrid ? F.q7Grid() : RecognisedPage()
        }
        let result = await read(document, reader)
        let calls = reader.calls.all
        XCTAssertEqual(calls.count, 3, "the page once, then its region twice")
        XCTAssertEqual(calls.first?.reading, .words)
        XCTAssertEqual(calls.dropFirst().map(\.reading), [.documentGrid, .documentGrid])
        let region = try XCTUnwrap(calls.last?.region)
        XCTAssertGreaterThanOrEqual(region.minY, 69, "under the caption")
        XCTAssertLessThan(region.maxY, CGFloat(L.pageHeight) * 0.92, "above the footer band")

        XCTAssertEqual(result.pagesWithoutText, 1)
        XCTAssertEqual(result.recognised, 1)
        let table = try XCTUnwrap(result.tables.first)
        XCTAssertEqual(table.label, "Table 95")
        XCTAssertEqual(table.title, "Invented spans")
        XCTAssertTrue(table.source.isRecognised)
        XCTAssertEqual(table.page.physical, 1)
    }

    func testAScannedPagesCaptionThatReadsNoTableIsKeptAsAPointerToItsPage() async throws {
        let document = try scannedPDF()
        let caption = F.words("Table 95 Invented spans", x: 50, y: 60, size: 10)
        let reader = FakeReader { render, _ in
            render.region.height > CGFloat(L.pageHeight) - 1 ? RecognisedPage(words: caption) : RecognisedPage()
        }
        let result = await read(document, reader)
        XCTAssertEqual(result.tables, [])
        XCTAssertEqual(result.unextracted.map(\.label), ["Table 95"])
        XCTAssertEqual(result.failures, [.noTextLayer: 1])
    }

    func testAMostlyUnclearPictureIsKeptAsAnUnreadTable() async throws {
        let document = try document([L.tableWithoutText()])
        let reader = FakeReader { _, _ in F.q7Grid(confidence: 0.2) }
        let result = await read(document, reader)
        XCTAssertEqual(result.tables, [])
        XCTAssertEqual(result.unclearInPicture, 1)
        XCTAssertEqual(result.failures, [.unclearInPicture: 1])
        XCTAssertEqual(result.unextracted.first?.failure, .unclearInPicture)
        XCTAssertGreaterThan(result.uncertainCells, 0)
    }

    func testTheSecondPassDecidesWhichCellsAreUncertain() async throws {
        let document = try document([L.tableWithoutText()])
        let reader = FakeReader { render, _ in
            render.scale == 3 ? F.q7Grid() : F.replacing(F.q7Grid(), row: 2, column: 2, with: "45")
        }
        let result = await read(document, reader)
        let table = try XCTUnwrap(result.tables.first)
        XCTAssertTrue(table.rows[1].cells[1].uncertain, "35 on one pass, 45 on the other")
        XCTAssertEqual(table.rows.flatMap(\.cells).filter(\.uncertain).count, 1)
        XCTAssertEqual(result.uncertainCells, 1)
    }

    // MARK: - Continuation

    func testAPictureReadTableJoinsItsContinuedCaption() async throws {
        let continued: L.Page = [L.Item(text: "Table 97 (Continued)", x: 50, y: 60),
                                 L.Item(text: "The invented values carry on from the page before in this example only,", x: 50, y: 80),
                                 L.Item(text: "and they describe nothing real at all; the grid is a picture again.", x: 50, y: 92),
                                 L.Item(text: "45", x: 300, y: L.pageHeight - 40)]
        let document = try document([L.tableWithoutText(), continued])
        let more = [["QB1", "26", "50", "36"], ["QB2", "28", "55", "40"], ["QB3", "30", "60", "45"]]
        // Each page's region answers with its own grid: the fake counts the regions it is shown.
        let pageTwo = FakePageReader(pages: [1: F.q7Grid(), 2: RecognisedPage(tables: [.init(cells: F.grid([F.q7Header] + more))])])
        let result = await read(document, pageTwo)
        XCTAssertEqual(result.recognised, 2)
        XCTAssertEqual(result.tables.count, 1, "\(result.tables.map(\.label))")
        let table = try XCTUnwrap(result.tables.first)
        XCTAssertEqual(table.rows.count, 7)
        XCTAssertEqual(table.pages.map(\.physical), [1, 2])
        XCTAssertEqual(result.captioned, 1)
    }

    /// A fake that answers by the page the region was drawn from, regions coming in page order
    /// and each drawn twice.
    final class FakePageReader: PictureTableReader, @unchecked Sendable {
        private let lock = NSLock()
        private var drawn = 0
        let pages: [Int: RecognisedPage]
        init(pages: [Int: RecognisedPage]) { self.pages = pages }

        func recognise(_ image: CGImage, render: PictureRegion.Render, reading: ManualTable.Source.Reader) async -> RecognisedPage {
            next()
        }

        /// Two passes per page, pages in order. Synchronous, so the lock is never held across a
        /// suspension.
        private func next() -> RecognisedPage {
            lock.lock(); defer { lock.unlock() }
            drawn += 1
            return pages[(drawn + 1) / 2] ?? RecognisedPage()
        }
    }

    /// The privacy log's lines, as a tap hands them over.
    final class LogLines: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func append(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return lines }
    }

    // MARK: - Budget: checkpoint and thermal state

    func testARelaunchReusesTheCheckpointAndRecognisesNothingTwice() async throws {
        let document = try document([L.tableWithoutText()])
        let first = gridReader()
        let read1 = await read(document, first, checkpoint: (tempRoot, "hash-a"))
        XCTAssertEqual(first.calls.all.count, 2)
        let file = PictureTableCheckpoint.url(in: tempRoot, contentHash: "hash-a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(file.deletingLastPathComponent().lastPathComponent, OCRCheckpoint.directoryName, "beside EF's")
        XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        let saved = PictureTableCheckpoint.load(from: tempRoot, contentHash: "hash-a")
        XCTAssertEqual(saved.regions.count, 1)
        XCTAssertEqual(saved.regions.keys.first, PictureTableCheckpoint.key(physical: 1, label: "Table 97", reading: .documentGrid, scale: 3))

        let second = gridReader()
        let read2 = await read(document, second, checkpoint: (tempRoot, "hash-a"))
        XCTAssertEqual(second.calls.all.count, 0, "every region came from the checkpoint")
        XCTAssertEqual(read2, read1)

        // Another file's hash never reuses this one's regions.
        let third = gridReader()
        _ = await read(document, third, checkpoint: (tempRoot, "hash-b"))
        XCTAssertEqual(third.calls.all.count, 2)

        PictureTableCheckpoint.remove(from: tempRoot, contentHash: "hash-a")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testACheckpointThatCannotBeSavedIsCountedAndTheRegionStillReads() async throws {
        struct Locked: Error {}
        let document = try document([L.tableWithoutText()])
        var context = PictureTableReading.Context(reader: gridReader())
        context.floor = 0.6
        context.thermal = { .nominal }
        context.checkpoint = (load: { PictureTableCheckpoint(contentHash: "hash-locked") }, save: { _ in throw Locked() })
        let result = await PDFTableReader.read(document: document, pictures: context)
        XCTAssertEqual(result.recognised, 1, "the import carries on")
        XCTAssertEqual(result.checkpointSaveFailures, 1)

        let lines = LogLines()
        let tap = PrivacyLog.addTap { _, line in lines.append(line) }
        defer { PrivacyLog.removeTap(tap) }
        VaultDocumentExtractor.logTables(result, rowsDropped: 0)
        let logged = lines.all
        let line = try XCTUnwrap(logged.first { $0.contains("table_checkpoint") }, "\(logged)")
        XCTAssertTrue(line.contains("saveFailed"), line)
        XCTAssertFalse(line.contains("Table 97"), "counts only: \(line)")

        let quiet = LogLines()
        let tap2 = PrivacyLog.addTap { _, line in quiet.append(line) }
        defer { PrivacyLog.removeTap(tap2) }
        VaultDocumentExtractor.logTables(await read(document, gridReader()), rowsDropped: 0)
        let none = quiet.all
        XCTAssertFalse(none.contains { $0.contains("table_checkpoint") }, "nothing failed, nothing said")
    }

    func testUnderThermalPressureBothPassesStepDownAndTheCheckpointStillCounts() async throws {
        let document = try document([L.tableWithoutText()])
        let hot = gridReader()
        let result = await read(document, hot, thermal: .serious, checkpoint: (tempRoot, "hash-hot"))
        XCTAssertEqual(hot.calls.all.map(\.scale), [2.5, 2])
        XCTAssertEqual(result.recognised, 1)
        XCTAssertNotEqual(PictureTableReading.scales(for: .critical).first, PictureTableReading.scales(for: .critical).second)

        let cool = gridReader()
        _ = await read(document, cool, thermal: .nominal, checkpoint: (tempRoot, "hash-hot"))
        XCTAssertEqual(cool.calls.all.count, 0, "a region recognised hot is not recognised again cool")
    }

    func testARegionTooTallIsDrawnSmallerAtBothScalesAlike() {
        let region = CGRect(x: 0, y: 0, width: 612, height: 1_800)
        let (first, second) = PictureTableReading.renders(of: region, scales: (3, 2.5))
        XCTAssertLessThanOrEqual(Double(max(first.pixelWidth, first.pixelHeight)), PictureTableReading.maximumPixels + 1)
        XCTAssertEqual(first.scale / second.scale, 3 / 2.5, accuracy: 0.0001)
    }

    // MARK: - Stored manuals: location version 6, tables only

    @MainActor
    func testTheMigrationReadsThePicturedTableAndLeavesTheTextAsItWas() async throws {
        let dir = tempRoot.appendingPathComponent("store", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = DocumentStore(directory: dir)
        let url = try TableFixtures.write(TableFixtures.pdf([TableFixtures.prosePage(), L.tableWithoutText()]),
                                          named: "pictured.pdf", in: tempRoot)
        let extracted = try VaultDocumentExtractor.extract(from: url)
        let tables = try XCTUnwrap(VaultDocumentExtractor.tables(from: url)).stored
        XCTAssertEqual(tables.map(\.failure), [.noTextInTable], "stored by version 5: the caption only")
        let maybe = await store.ingest(name: "Invented Manual", text: extracted.text, sourceType: "vault_document",
                                       namespace: "vault:x", pageLabels: extracted.pageLabels, tables: tables)
        let ref = try XCTUnwrap(maybe)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dir.appendingPathComponent("documents.sqlite").path, &db), SQLITE_OK)
        sqlite3_exec(db, "UPDATE doc_chunks SET location_version = 5", nil, nil, nil)
        sqlite3_close(db)
        XCTAssertGreaterThanOrEqual(DocumentStore.locationVersion, 6)
        XCTAssertTrue(store.needsLocation(documentId: ref.id))
        let text = store.fullText(documentId: ref.id)

        let entry = VaultDocumentLedger.Entry(file: "pictured.pdf", title: ref.name, documentId: ref.id,
                                              contentHash: "hash-m", chunkCount: ref.chunkCount)
        let reader = gridReader()
        let checkpoints = tempRoot.appendingPathComponent("overlay", isDirectory: true)
        let outcome = await PassageLocationMigration.migrate(entry: entry, fileURL: url, store: store,
                                                             pictureReader: reader, checkpointDirectory: checkpoints)
        XCTAssertEqual(outcome, .located)
        XCTAssertEqual(store.fullText(documentId: ref.id), text, "the text is as it was")
        let stored = store.tables(documentId: ref.id)
        XCTAssertEqual(stored.map(\.label), ["Table 97"])
        XCTAssertTrue(stored.first?.isExtracted == true)
        XCTAssertTrue(stored.first?.source.isRecognised == true)
        XCTAssertFalse(store.needsLocation(documentId: ref.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: PictureTableCheckpoint.url(in: checkpoints, contentHash: "hash-m").path),
                       "the checkpoint goes once the tables are stored")

        let again = await PassageLocationMigration.migrate(entry: entry, fileURL: url, store: store, pictureReader: reader)
        XCTAssertEqual(again, .current)
        XCTAssertEqual(reader.calls.all.count, 2, "a second launch recognises nothing")
    }

    @MainActor
    func testTheMigrationWithNoReaderReadsTheTextLayerOnly() async throws {
        let dir = tempRoot.appendingPathComponent("store-plain", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = DocumentStore(directory: dir)
        let url = try TableFixtures.write(TableFixtures.pdf([L.tableWithoutText()]), named: "plain.pdf", in: tempRoot)
        let extracted = try VaultDocumentExtractor.extract(from: url)
        let maybe = await store.ingest(name: "Invented Manual", text: extracted.text, sourceType: "vault_document",
                                       namespace: "vault:x", pageLabels: extracted.pageLabels, tables: [])
        let ref = try XCTUnwrap(maybe)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dir.appendingPathComponent("documents.sqlite").path, &db), SQLITE_OK)
        sqlite3_exec(db, "UPDATE doc_chunks SET location_version = 5", nil, nil, nil)
        sqlite3_close(db)
        let entry = VaultDocumentLedger.Entry(file: "plain.pdf", title: ref.name, documentId: ref.id,
                                              contentHash: "hash-p", chunkCount: ref.chunkCount)
        let outcome = await PassageLocationMigration.migrate(entry: entry, fileURL: url, store: store, pictureReader: nil)
        XCTAssertEqual(outcome, .located)
        XCTAssertEqual(store.tables(documentId: ref.id).map(\.failure), [.noTextInTable])
    }

    // MARK: - Counts

    func testTheResultCountsArePlainNumbers() async throws {
        let document = try document([L.tableWithoutText()])
        let result = await read(document, FakeReader { _, _ in F.replacing(F.q7Grid(), row: 3, column: 1, with: "1O") })
        XCTAssertEqual(result.recognised, 1)
        XCTAssertEqual(result.unclearInPicture, 0)
        XCTAssertEqual(result.uncertainCells, 1, "a confusable glyph in a number column")
        XCTAssertEqual(result.pictureReader, .documentGrid)
    }
}
