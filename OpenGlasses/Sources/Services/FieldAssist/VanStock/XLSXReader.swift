import Foundation

/// Reads the cells of a spreadsheet workbook somebody edited (Plan IH §6).
///
/// Over the same strict ZIP reader the book importer uses, and `XMLParser`. It reads what a cell
/// shows — shared, inline and formula-string text, and the cached value of a number — and nothing
/// else: no formulas are evaluated, no styles are read, and nothing in the file is executed.
///
/// Refused outright: a file that is not a workbook (which is also what an encrypted one looks
/// like), a macro workbook, and anything past the size bounds below.
enum XLSXReader {

    struct Sheet: Equatable {
        let name: String
        let isHidden: Bool
        /// Every row as far as its last cell; an empty cell is an empty string.
        let rows: [[String]]
    }

    enum Failure: Error, Equatable {
        case notAWorkbook
        case tooLarge
        case macros
        case tooManyRows
    }

    static let maximumFileBytes = 2 * 1_024 * 1_024
    static let maximumInflatedBytes = 16 * 1_024 * 1_024
    static let maximumEntries = 200
    /// Data rows, not counting the header.
    static let maximumRows = 5_000
    static let maximumColumns = 64

    static func read(_ data: Data) -> Result<[Sheet], Failure> {
        guard data.count <= maximumFileBytes else { return .failure(.tooLarge) }
        guard let archive = ZipArchiveReader(data: data) else { return .failure(.notAWorkbook) }
        let entries = archive.entryMetadata
        guard entries.count <= maximumEntries else { return .failure(.tooLarge) }
        var inflated = 0
        for entry in entries {
            let (next, overflow) = inflated.addingReportingOverflow(entry.uncompressedSize)
            guard !overflow, next <= maximumInflatedBytes else { return .failure(.tooLarge) }
            inflated = next
        }
        guard !entries.contains(where: { $0.name.lowercased().hasSuffix("vbaproject.bin") }) else {
            return .failure(.macros)
        }
        func part(_ name: String) -> Data? {
            archive.entryData(named: name, maximumUncompressedSize: maximumInflatedBytes)
        }
        if let types = part("[Content_Types].xml"), let text = String(data: types, encoding: .utf8),
           text.lowercased().contains("macroenabled") {
            return .failure(.macros)
        }

        guard let workbookData = part("xl/workbook.xml"),
              let relationshipData = part("xl/_rels/workbook.xml.rels") else { return .failure(.notAWorkbook) }
        let listed = WorkbookParser.sheets(in: workbookData)
        let targets = RelationshipParser.targets(in: relationshipData)
        guard !listed.isEmpty else { return .failure(.notAWorkbook) }
        let shared = part("xl/sharedStrings.xml").map(SharedStringsParser.strings(in:)) ?? []

        var sheets: [Sheet] = []
        for entry in listed {
            guard let target = targets[entry.relationshipID],
                  let sheetData = part(path(for: target)) else { return .failure(.notAWorkbook) }
            let parser = SheetParser(shared: shared)
            guard let rows = parser.rows(in: sheetData) else { return .failure(.tooManyRows) }
            sheets.append(Sheet(name: entry.name, isHidden: entry.isHidden, rows: rows))
        }
        return .success(sheets)
    }

    /// A relationship target, as a path inside the archive.
    private static func path(for target: String) -> String {
        target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
    }

    /// The zero-based column of a cell reference: "A1" is 0, "AB12" is 27. Nil when there is none.
    static func columnIndex(_ reference: String) -> Int? {
        var index = 0
        var seen = false
        for scalar in reference.unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90 else { break }
            index = index * 26 + Int(scalar.value - 64)
            seen = true
            guard index <= 20_000 else { return nil }
        }
        return seen ? index - 1 : nil
    }
}

// MARK: - Parsers

/// `xl/workbook.xml`: the sheets, in the order the workbook shows them.
private final class WorkbookParser: NSObject, XMLParserDelegate {
    struct Entry {
        let name: String
        let relationshipID: String
        let isHidden: Bool
    }

    private var entries: [Entry] = []

    static func sheets(in data: Data) -> [Entry] {
        let delegate = WorkbookParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        return parser.parse() ? delegate.entries : []
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == "sheet", let name = attributeDict["name"] else { return }
        // The relationship id is `r:id` under whatever prefix the writer chose.
        let relationship = attributeDict.first { $0.key == "id" || $0.key.hasSuffix(":id") }?.value
        guard let relationship else { return }
        let state = attributeDict["state"] ?? "visible"
        entries.append(Entry(name: name, relationshipID: relationship, isHidden: state != "visible"))
    }
}

/// `xl/_rels/workbook.xml.rels`: relationship id to target.
private final class RelationshipParser: NSObject, XMLParserDelegate {
    private var found: [String: String] = [:]

    static func targets(in data: Data) -> [String: String] {
        let delegate = RelationshipParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        return parser.parse() ? delegate.found : [:]
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == "Relationship", let id = attributeDict["Id"],
              let target = attributeDict["Target"], attributeDict["TargetMode"] != "External" else { return }
        found[id] = target
    }
}

/// `xl/sharedStrings.xml`: each `si`, its text runs joined. Phonetic runs are not text.
private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var inText = false
    private var phoneticDepth = 0

    static func strings(in data: Data) -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        return parser.parse() ? delegate.strings : []
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "si": current = ""
        case "rPh": phoneticDepth += 1
        case "t": inText = phoneticDepth == 0
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "si": strings.append(current)
        case "rPh": phoneticDepth = max(phoneticDepth - 1, 0)
        case "t": inText = false
        default: break
        }
    }
}

/// One worksheet: its rows, each as far as its last cell.
private final class SheetParser: NSObject, XMLParserDelegate {
    private let shared: [String]
    private var rows: [[String]] = []
    private var row: [String] = []
    private var column = 0
    private var type = ""
    private var value = ""
    private var inValue = false
    private var inInlineText = false
    private var tooMany = false

    init(shared: [String]) {
        self.shared = shared
    }

    /// Nil when the sheet has more rows than the bound.
    func rows(in data: Data) -> [[String]]? {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = self
        let parsed = parser.parse()
        if tooMany { return nil }
        return parsed ? rows : []
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "row":
            row = []
            // A row that names itself may skip the empty ones before it.
            if let number = attributeDict["r"].flatMap(Int.init), number - 1 > rows.count {
                guard number - 1 <= XLSXReader.maximumRows + 1 else {
                    tooMany = true
                    parser.abortParsing()
                    return
                }
                rows.append(contentsOf: Array(repeating: [], count: number - 1 - rows.count))
            }
        case "c":
            column = attributeDict["r"].flatMap(XLSXReader.columnIndex) ?? row.count
            type = attributeDict["t"] ?? "n"
            value = ""
        case "v":
            inValue = true
        case "t":
            inInlineText = type == "inlineStr"
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inValue || inInlineText { value += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "v":
            inValue = false
        case "t":
            inInlineText = false
        case "c":
            guard column < XLSXReader.maximumColumns else { return }
            let text: String
            switch type {
            case "s": text = Int(value).flatMap { $0 >= 0 && $0 < shared.count ? shared[$0] : nil } ?? ""
            case "e": text = ""
            default: text = value
            }
            if row.count <= column { row.append(contentsOf: Array(repeating: "", count: column - row.count + 1)) }
            row[column] = text
        case "row":
            rows.append(row)
            if rows.count > XLSXReader.maximumRows + 1 {
                tooMany = true
                parser.abortParsing()
            }
        default:
            break
        }
    }
}
