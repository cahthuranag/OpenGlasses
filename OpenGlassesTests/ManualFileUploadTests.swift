import PDFKit
import XCTest
@testable import OpenGlasses

final class ManualFileUploadTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("manual-upload-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    static func fixture(_ ext: String) throws -> URL {
        try XCTUnwrap(Bundle(for: ManualFileUploadTests.self).url(forResource: "manual-upload", withExtension: ext))
    }

    func testRealWordExportsProduceReadablePaginatedCopiesAndKeepOriginalBytes() throws {
        for ext in ["doc", "docx"] {
            let original = try Self.fixture(ext)
            let prepared = try ManualFileUpload.prepare(original)
            defer { prepared.discard() }
            XCTAssertTrue(prepared.converted)
            XCTAssertEqual(try Data(contentsOf: prepared.original), try Data(contentsOf: original))
            let pdf = try XCTUnwrap(PDFDocument(url: prepared.readingPDF))
            XCTAssertEqual(prepared.pages, pdf.pageCount)
            XCTAssertGreaterThan(pdf.pageCount, 0)
            XCTAssertTrue(pdf.string?.contains("37 Nm") == true, pdf.string ?? "no text")
            XCTAssertTrue(pdf.string?.contains("terminal A1") == true, pdf.string ?? "no text")
        }
    }

    func testMarkdownPreservesUnicodeAndPaginatesWithoutTruncatingTheLastParagraph() throws {
        let input = root.appendingPathComponent("garage.md")
        let text = "# Garage\n\n" + String(repeating: "The sump plug torque is 37 Nm.\n", count: 400) + "\nFinal paragraph: café Ω 42."
        try Data(text.utf8).write(to: input)
        let prepared = try ManualFileUpload.prepare(input)
        defer { prepared.discard() }
        let pdf = try XCTUnwrap(PDFDocument(url: prepared.readingPDF))
        XCTAssertGreaterThan(prepared.pages, 1)
        XCTAssertTrue(pdf.string?.contains("Final paragraph") == true)
        XCTAssertTrue(pdf.string?.contains("café") == true)
        XCTAssertEqual(try String(contentsOf: prepared.original, encoding: .utf8), text)
        XCTAssertThrowsError(try ManualFileUpload.prepare(input, maximumPages: 1))
    }

    func testDocxRowsAndVisibleTextAreKeptAndDeletedTextIsExcluded() throws {
        let xml = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
        <w:p><w:r><w:t>Workshop</w:t></w:r><w:del><w:r><w:delText>obsolete 99 Nm</w:delText></w:r></w:del></w:p>
        <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Sump plug</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>37 Nm</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
        </w:body></w:document>
        """
        let input = root.appendingPathComponent("table.docx")
        try VaultArchiveFixture.zip([("word/document.xml", Data(xml.utf8))]).write(to: input)
        let text = try ManualFileUpload.text(from: input)
        XCTAssertTrue(text.contains("Sump plug"))
        XCTAssertTrue(text.contains("37 Nm"))
        XCTAssertFalse(text.contains("obsolete"))
    }

    func testMalformedProtectedAndEntityBasedWordDocumentsAreRefused() throws {
        let input = root.appendingPathComponent("bad.docx")
        let xml = "<!DOCTYPE document [<!ENTITY x SYSTEM 'file:///private/test'>]><document><t>&x;</t></document>"
        try VaultArchiveFixture.zip([("word/document.xml", Data(xml.utf8))]).write(to: input)
        XCTAssertThrowsError(try ManualFileUpload.prepare(input))
        try Data("not a Word document".utf8).write(to: input)
        XCTAssertThrowsError(try ManualFileUpload.prepare(input))
        let doc = root.appendingPathComponent("truncated.doc")
        try Data(contentsOf: Self.fixture("doc")).prefix(1024).write(to: doc)
        XCTAssertThrowsError(try ManualFileUpload.prepare(doc))
        let empty = root.appendingPathComponent("empty.md")
        try Data("  \n".utf8).write(to: empty)
        XCTAssertThrowsError(try ManualFileUpload.prepare(empty))
    }

    func testCyclicLegacyWordSectorChainIsRefused() throws {
        var data = try Data(contentsOf: Self.fixture("doc"))
        func u32(_ offset: Int) -> Int { (0..<4).reduce(0) { $0 | Int(data[offset + $1]) << ($1 * 8) } }
        let size = 1 << (Int(data[30]) | Int(data[31]) << 8)
        let directory = u32(48)
        let fat = u32(76)
        let location = (fat + 1) * size + directory * 4
        for byte in 0..<4 { data[location + byte] = UInt8((directory >> (byte * 8)) & 255) }
        let input = root.appendingPathComponent("cycle.doc")
        try data.write(to: input)
        XCTAssertThrowsError(try ManualFileUpload.prepare(input))
    }

    func testPreparedFilesAreDiscardedOnCancellation() throws {
        let prepared = try ManualFileUpload.prepare(Self.fixture("docx"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.original.path))
        prepared.discard()
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.directory.path))
    }
}
