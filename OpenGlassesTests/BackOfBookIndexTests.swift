import XCTest
@testable import OpenGlasses

/// A document's own back-of-book index, detected and read from its text (Plan IV P5). Every word,
/// number and entry here is invented; no real index is parsed by a test.
final class BackOfBookIndexTests: XCTestCase {

    /// Invented one-word subjects for index entries, each paired with a rule number below.
    static let subjects = [
        "Lantern", "Copper", "Harbour", "Pebble", "Saddle", "Thimble", "Ribbon", "Marble",
        "Beacon", "Ferry", "Quill", "Orchard", "Tumbler", "Canopy", "Gravel", "Satchel",
        "Bramble", "Cobble", "Ladle", "Mitten", "Nutmeg", "Parcel", "Quarry", "Rafter",
        "Spindle", "Trellis", "Velvet", "Wicker", "Yarrow", "Zither", "Anchor", "Bellows",
    ]

    /// A clause-numbered body of `rules` invented rules, then (when `indexEntries` > 0) an "Index"
    /// heading and that many entries, plus a heading with two sub-entries and a carried-over line.
    static func inventedBook(rules: Int = 40, indexEntries: Int = 32, contentsMentionsIndex: Bool = true) -> String {
        var lines: [String] = []
        if contentsMentionsIndex { lines += ["Contents", "Rules .... 1", "Index .... 9", ""] }
        for i in 0..<rules {
            lines += [
                "Page \(i / 4 + 1)",
                "",
                "41-\(300 + i * 2) Example rule number \(i)",
                "Keep item \(i) on the \(i % 2 == 0 ? "left" : "right") shelf. Label it before the van leaves.",
                "",
            ]
        }
        guard indexEntries > 0 else { return lines.joined(separator: "\n") }
        lines += ["Index", ""]
        for (n, subject) in subjects.prefix(indexEntries).enumerated() {
            lines.append("\(subject) hooks, 41-\(300 + n * 2)")
        }
        lines += [
            "Willow baskets",
            "  lining, 41-390",
            "  handles, 41-392; Table Q7",
            "Kettle spouts, 41-394",
            "41-396, Table Q8",
        ]
        return lines.joined(separator: "\n")
    }

    func testAnInventedIndexIsFoundAndItsEntriesRead() throws {
        let index = try XCTUnwrap(BackOfBookIndex.parse(Self.inventedBook()))
        XCTAssertEqual(index.entries.count, 32 + 4, "32 entries, two sub-entries, one entry and its carried line")
        XCTAssertEqual(index.references(for: "where do the lantern hooks go", limit: 1), ["41-300"])
        XCTAssertEqual(index.references(for: "the zither hooks", limit: 1), ["41-358"])
    }

    func testASubEntryCarriesItsHeadingsWords() throws {
        let index = try XCTUnwrap(BackOfBookIndex.parse(Self.inventedBook()))
        XCTAssertEqual(index.references(for: "what goes in the lining of a willow basket", limit: 1), ["41-390"])
        XCTAssertEqual(index.references(for: "willow basket handles", limit: 2), ["41-392", "Table Q7"])
        XCTAssertTrue(index.entries.contains { $0.terms.isSuperset(of: ["willow", "basket"]) && $0.references == ["41-390"] },
                      "the heading's words ride on the sub-entry")
    }

    func testReferencesCarriedOntoTheNextLineBelongToTheEntryAbove() throws {
        let index = try XCTUnwrap(BackOfBookIndex.parse(Self.inventedBook()))
        XCTAssertEqual(index.references(for: "kettle spouts", limit: 4), ["41-394", "41-396", "Table Q8"])
    }

    func testWordsTheIndexDoesNotHoldGetNothing() throws {
        let index = try XCTUnwrap(BackOfBookIndex.parse(Self.inventedBook()))
        XCTAssertEqual(index.references(for: "violet umbrella"), [])
        XCTAssertEqual(index.references(for: ""), [])
    }

    func testABookWithoutAnIndexHasNone() {
        // The contents page names an index the text never prints: the front "Index" line is not one.
        XCTAssertNil(BackOfBookIndex.parse(Self.inventedBook(indexEntries: 0)))
    }

    func testAShortListUnderAnIndexHeadingIsNotAnIndex() {
        XCTAssertNil(BackOfBookIndex.parse(Self.inventedBook(indexEntries: BackOfBookIndex.minimumEntries - 6)))
        XCTAssertNotNil(BackOfBookIndex.parse(Self.inventedBook(indexEntries: BackOfBookIndex.minimumEntries)))
    }

    func testAProseManualWithReadingsAndStepsHasNone() {
        // A service manual's shape: numbered steps, decimal readings, a parts list — and no index.
        let steps = (1...60).map { "Step \($0 / 10).\($0 % 10): turn the dial to \($0).5 and wait 2.25 minutes for the lamp." }
        let parts = (1...30).map { "Part 7-\($0) small grey bracket" }
        let manual = (["Service guide", "Contents", "Index .... 40", ""] + steps + ["Parts list"] + parts)
            .joined(separator: "\n")
        XCTAssertNil(BackOfBookIndex.parse(manual))
    }
}
