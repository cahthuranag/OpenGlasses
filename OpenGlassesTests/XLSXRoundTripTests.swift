import XCTest
@testable import OpenGlasses

/// Plan IH P3 — a workbook this app writes is one it, and a strict ZIP reader, can read back.
final class XLSXRoundTripTests: XCTestCase {

    private let modified = Date(timeIntervalSince1970: 1_790_000_000)

    private func workbook(_ rows: [[XLSX.Cell]], name: String = "Van stock", hidden: Bool = false) -> XLSX.Workbook {
        XLSX.Workbook(sheets: [XLSX.Sheet(name: name, columns: [XLSX.Column(isText: true), XLSX.Column()],
                                          rows: rows, isHidden: hidden)])
    }

    private func read(_ workbook: XLSX.Workbook) throws -> [XLSXReader.Sheet] {
        try XLSXReader.read(XLSXWriter.data(for: workbook, modified: modified)).get()
    }

    func testTextAndNumbersComeBackAsWritten() throws {
        let sheets = try read(workbook([[.text("Part number"), .text("On hand")],
                                        [.text("62-23543-01"), .number(4)],
                                        [.empty, .number(0)],
                                        [.text("Wire nuts"), .empty]]))
        XCTAssertEqual(sheets.count, 1)
        XCTAssertEqual(sheets[0].name, "Van stock")
        XCTAssertFalse(sheets[0].isHidden)
        XCTAssertEqual(sheets[0].rows, [["Part number", "On hand"], ["62-23543-01", "4"], ["", "0"], ["Wire nuts"]])
    }

    func testAPartNumberIsNeverReinterpreted() throws {
        let numbers = ["00123", "14E65", "1E5", "0x1F", "12/5", "=SUM(A1)", " 7 "]
        let sheets = try read(workbook([[.text("Part number")]] + numbers.map { [.text($0)] }))
        XCTAssertEqual(sheets[0].rows.dropFirst().map { $0[0] }, numbers)
    }

    func testMarkupAndUnusualCharactersSurvive() throws {
        let awkward = "Capacitor <45/5> & \"dual\" µF — 440 V\tspare"
        let sheets = try read(workbook([[.text("Description")], [.text(awkward)], [.text("bell\u{07}char")]]))
        XCTAssertEqual(sheets[0].rows[1][0], awkward)
        XCTAssertEqual(sheets[0].rows[2][0], "bellchar", "a character XML cannot carry is dropped, not written")
    }

    func testSeveralSheetsAndAHiddenOne() throws {
        let book = XLSX.Workbook(sheets: [
            XLSX.Sheet(name: "Van stock", columns: [], rows: [[.text("a")]]),
            XLSX.Sheet(name: "History: [old]/*?", columns: [], rows: [[.text("b")]]),
            XLSX.Sheet(name: "Avenkin", columns: [], rows: [[.text("key"), .text("value")]], isHidden: true),
        ])
        let sheets = try read(book)
        XCTAssertEqual(sheets.map(\.name), ["Van stock", "History old", "Avenkin"])
        XCTAssertEqual(sheets.map(\.isHidden), [false, false, true])
        XCTAssertEqual(sheets[2].rows, [["key", "value"]])
    }

    func testTheSameWorkbookAndDateGiveTheSameBytes() {
        let book = workbook([[.text("Part number")], [.text("14T65")]])
        XCTAssertEqual(XLSXWriter.data(for: book, modified: modified), XLSXWriter.data(for: book, modified: modified))
    }

    func testTheArchiveIsOneTheStrictReaderAccepts() throws {
        let data = XLSXWriter.data(for: workbook([[.text("a")]]), modified: modified)
        let archive = try XCTUnwrap(ZipArchiveReader(data: data))
        XCTAssertEqual(Set(archive.entryNames), ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml",
                                                 "xl/_rels/workbook.xml.rels", "xl/styles.xml",
                                                 "xl/worksheets/sheet1.xml"])
        let sheet = try XCTUnwrap(archive.entryData(named: "xl/worksheets/sheet1.xml"))
        XCTAssertTrue(String(decoding: sheet, as: UTF8.self).contains(#"t="inlineStr""#))
    }

    func testColumnLetters() {
        XCTAssertEqual([0, 1, 25, 26, 27, 51, 52, 701, 702].map(XLSXWriter.columnLetters),
                       ["A", "B", "Z", "AA", "AB", "AZ", "BA", "ZZ", "AAA"])
        XCTAssertEqual(XLSXReader.columnIndex("A1"), 0)
        XCTAssertEqual(XLSXReader.columnIndex("AB12"), 27)
        XCTAssertNil(XLSXReader.columnIndex("12"))
    }

    // MARK: What another program writes

    /// A workbook as a spreadsheet program saves it: shared strings, a formula with a cached
    /// value, a rich-text cell, a cell with no reference, and a prefixed relationship id.
    private func foreignWorkbook(extraEntries: [(String, String)] = [], contentTypes: String? = nil) -> Data {
        let main = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        var parts: [(String, String)] = [
            ("[Content_Types].xml", contentTypes ?? "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"/>"),
            ("xl/workbook.xml", "<workbook xmlns=\"\(main)\" xmlns:rr=\"\(rel)\"><sheets><sheet name=\"Stock\" sheetId=\"1\" rr:id=\"rId7\"/></sheets></workbook>"),
            ("xl/_rels/workbook.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId7\" Type=\"\(rel)/worksheet\" Target=\"/xl/worksheets/data.xml\"/></Relationships>"),
            ("xl/sharedStrings.xml", "<sst xmlns=\"\(main)\"><si><t>Part</t></si><si><r><t>Flame </t></r><r><t>sensor</t></r><rPh><t>ignored</t></rPh></si><si><t>Qty</t></si></sst>"),
            ("xl/worksheets/data.xml", """
            <worksheet xmlns="\(main)"><sheetData>
            <row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>2</v></c></row>
            <row r="3"><c r="A3" t="s"><v>1</v></c><c r="C3"><f>1+3</f><v>4</v></c><c t="str"><f>A3</f><v>copy</v></c><c r="E3" t="e"><v>#N/A</v></c></row>
            </sheetData></worksheet>
            """),
        ]
        parts.append(contentsOf: extraEntries)
        return TestZip.stored(parts)
    }

    func testAnotherProgramsWorkbookIsRead() throws {
        let sheets = try XLSXReader.read(foreignWorkbook()).get()
        XCTAssertEqual(sheets.map(\.name), ["Stock"])
        XCTAssertEqual(sheets[0].rows, [["Part", "", "Qty"], [], ["Flame sensor", "", "4", "copy", ""]])
    }

    // MARK: Refusals

    func testSomethingThatIsNotAWorkbookIsRefused() {
        XCTAssertEqual(XLSXReader.read(Data("part,qty\n14T65,2\n".utf8)), .failure(.notAWorkbook))
        XCTAssertEqual(XLSXReader.read(TestZip.stored([("hello.txt", "hi")])), .failure(.notAWorkbook))
        // An encrypted workbook is a compound file, not a ZIP.
        XCTAssertEqual(XLSXReader.read(Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1] + [UInt8](repeating: 0, count: 64))),
                       .failure(.notAWorkbook))
    }

    func testAMacroWorkbookIsRefused() {
        XCTAssertEqual(XLSXReader.read(foreignWorkbook(extraEntries: [("xl/vbaProject.bin", "x")])), .failure(.macros))
        let types = "<Types><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.ms-excel.sheet.macroEnabled.main+xml\"/></Types>"
        XCTAssertEqual(XLSXReader.read(foreignWorkbook(contentTypes: types)), .failure(.macros))
    }

    func testAFileOverTheBoundIsRefused() {
        XCTAssertEqual(XLSXReader.read(Data(count: XLSXReader.maximumFileBytes + 1)), .failure(.tooLarge))
    }

    func testTooManyRowsIsRefused() {
        let rows: [[XLSX.Cell]] = [[.text("Part number")]] + (0...XLSXReader.maximumRows).map { [.text("P\($0)")] }
        XCTAssertEqual(XLSXReader.read(XLSXWriter.data(for: workbook(rows), modified: modified)), .failure(.tooManyRows))
        let allowed: [[XLSX.Cell]] = [[.text("Part number")]] + (0..<XLSXReader.maximumRows).map { [.text("P\($0)")] }
        XCTAssertNoThrow(try read(workbook(allowed)))
    }
}

/// A stored ZIP of text parts, for workbooks shaped the way another program writes them.
enum TestZip {
    static func stored(_ parts: [(String, String)]) -> Data {
        var archive = Data()
        var central = Data()
        func le<Value: FixedWidthInteger>(_ value: Value) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        for (name, text) in parts {
            let nameData = Data(name.utf8)
            let body = Data(text.utf8)
            let crc = XLSXWriter.crc32(body)
            let offset = UInt32(archive.count)
            let fixed = le(UInt16(20)) + le(UInt16(0)) + le(UInt16(0)) + le(UInt16(0)) + le(UInt16(0x21))
                + le(crc) + le(UInt32(body.count)) + le(UInt32(body.count)) + le(UInt16(nameData.count)) + le(UInt16(0))
            archive += le(UInt32(0x0403_4B50)) + fixed + nameData + body
            central += le(UInt32(0x0201_4B50)) + le(UInt16(20)) + fixed + le(UInt16(0)) + le(UInt16(0)) + le(UInt16(0))
                + le(UInt32(0)) + le(offset) + nameData
        }
        let centralOffset = UInt32(archive.count)
        archive += central
        archive += le(UInt32(0x0605_4B50)) + le(UInt16(0)) + le(UInt16(0)) + le(UInt16(parts.count)) + le(UInt16(parts.count))
            + le(UInt32(central.count)) + le(centralOffset) + le(UInt16(0))
        return archive
    }
}
