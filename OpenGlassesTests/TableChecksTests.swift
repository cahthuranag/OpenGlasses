import XCTest
@testable import OpenGlasses

/// Plan JN P3 — checking a table read from a picture against its page: how checks merge into a
/// recognised table, how `table-checks.json` reads, and what the check view's model makes. Every
/// table, designation, value and name is invented.
final class TableChecksTests: XCTestCase {

    static let bookHash = String(repeating: "a1", count: 32)
    static let otherHash = String(repeating: "b2", count: 32)
    static let page = ManualTable.Page(physical: 7, printed: "31")
    static let day = Date(timeIntervalSince1970: 1_792_000_000)   // a whole second
    static let later = day.addingTimeInterval(3_600)

    /// Table Q7, read from a picture: three rows under one heading and two columns, one cell
    /// uncertain, one row name uncertain, one heading uncertain.
    static func q7(uncertainCell: Bool = true, uncertainKey: Bool = true, uncertainHeading: Bool = true) -> ManualTable {
        func cell(_ text: String, _ value: Double?, unit: String? = "mm", uncertain: Bool = false) -> ManualTable.Cell {
            .init(text: text, value: value, unit: value == nil ? nil : unit, uncertain: uncertain)
        }
        var table = ManualTable(
            label: "Table Q7", title: "Invented spacings", page: page, rowHeaders: ["Designation"],
            columns: [.init(path: ["Spacing (mm)"], unit: "mm"),
                      .init(path: ["Invented band", "Band B"], uncertain: uncertainHeading)],
            rows: [.init(path: ["QXRT"], cells: [cell("40", 40), cell("61", 61, unit: nil)], page: page),
                   .init(path: ["QMX90"], cells: [cell("3S", nil, uncertain: uncertainCell), cell("72", 72, unit: nil)],
                         page: page, keyUncertain: uncertainKey),
                   .init(path: ["QZ12"], cells: [cell("70", 70), cell("88", 88, unit: nil)], page: page)],
            source: .recognised(reader: .documentGrid, meanConfidence: 0.8))
        table.pictureAreas = [.init(physical: 7, rect: CGRect(x: 40, y: 120, width: 400, height: 200))]
        return table
    }

    static func check(row: [String]? = ["QMX90"], column: [String]? = ["Spacing (mm)"], kind: TableCheck.Kind = .corrected,
                      value: String = "35", by: String = "the vault manager", at: Date = day,
                      origin: TableCheck.Origin = .phone, hash: String = TableChecksTests.bookHash, table: String = "Table Q7") -> TableCheck {
        TableCheck(documentHash: hash, table: table, row: row, column: column, kind: kind, value: value, by: by, at: at,
                   origin: origin)
    }

    private func apply(_ checks: [TableCheck], to table: ManualTable = TableChecksTests.q7(), hash: String? = TableChecksTests.bookHash,
                       require: Bool = false) -> TableChecks.Applied {
        TableChecks.apply(checks, to: table, documentHash: hash, requireChecked: require)
    }

    // MARK: - Applying

    func testACorrectionTakesTheTypedValueParsedAsACellIs() {
        let applied = apply([Self.check(value: "35*")])
        let cell = applied.table.rows[1].cells[0]
        XCTAssertEqual(cell.text, "35*")
        XCTAssertEqual(cell.value, 35)
        XCTAssertEqual(cell.unit, "mm", "the column's unit, as a parsed cell takes it")
        XCTAssertEqual(cell.markers, ["*"])
        XCTAssertFalse(cell.uncertain)
        XCTAssertEqual(cell.check?.agreedMark?.by, "the vault manager")
        XCTAssertEqual(applied.applied.count, 1)
        XCTAssertTrue(applied.unmatched.isEmpty)
    }

    func testAConfirmationClearsUncertaintyAndKeepsTheReadText() {
        let applied = apply([Self.check(row: ["QZ12"], kind: .confirmed, value: "70")])
        let cell = applied.table.rows[2].cells[0]
        XCTAssertEqual(cell.text, "70")
        XCTAssertEqual(cell.value, 70)
        XCTAssertNotNil(cell.check?.agreedMark)

        let uncertain = apply([Self.check(kind: .confirmed, value: "3S")]).table.rows[1].cells[0]
        XCTAssertFalse(uncertain.uncertain, "confirmed as read: what the page prints, so certain")
        XCTAssertEqual(uncertain.text, "3S")
    }

    func testRowNameAndHeadingChecksClearTheirUncertainty() {
        let applied = apply([Self.check(column: nil, kind: .confirmed, value: ""),
                             Self.check(row: nil, column: ["Invented band", "Band B"], kind: .confirmed, value: "")])
        XCTAssertFalse(applied.table.rows[1].keyUncertain)
        XCTAssertFalse(applied.table.columns[1].uncertain)
        XCTAssertEqual(applied.applied.count, 2)
    }

    func testACorrectedRowNameIsNotApplied() {
        let applied = apply([Self.check(column: nil, kind: .corrected, value: "QMX91")])
        XCTAssertTrue(applied.table.rows[1].keyUncertain)
        XCTAssertEqual(applied.unmatched.count, 1)
    }

    func testPathsMatchWithTheirSpacingMadePlainAndNeverByPosition() {
        let spaced = apply([Self.check(row: [" QMX90 "], column: ["Spacing  (mm)"], value: "35")])
        XCTAssertEqual(spaced.table.rows[1].cells[0].text, "35")

        let unknownRow = apply([Self.check(row: ["QZZ"], value: "35")])
        XCTAssertEqual(unknownRow.unmatched.count, 1, "a row the table does not have is reported")
        XCTAssertEqual(unknownRow.table, Self.q7(), "and nothing else is touched")

        let unknownColumn = apply([Self.check(column: ["Band C"], value: "35")])
        XCTAssertEqual(unknownColumn.unmatched.count, 1)
        XCTAssertEqual(unknownColumn.table, Self.q7())
    }

    func testAPathThatMatchesTwoRowsIsNotApplied() {
        var table = Self.q7()
        table.rows[2].path = ["QMX90"]
        let applied = apply([Self.check(value: "35")], to: table)
        XCTAssertEqual(applied.unmatched.count, 1)
        XCTAssertEqual(applied.table, table)
    }

    func testChecksOfAnotherPDFOrTableDoNotApply() {
        let applied = apply([Self.check(hash: Self.otherHash), Self.check(table: "Table 98")])
        XCTAssertEqual(applied.table, Self.q7())
        XCTAssertTrue(applied.unmatched.isEmpty, "not addressed to this table at all")
        let batch = TableChecks.apply([Self.check(hash: Self.otherHash)], to: [(Self.bookHash, Self.q7())])
        XCTAssertEqual(batch.unmatched.count, 1, "across the vault, a check for no table is reported")
    }

    func testChecksNeverApplyToATextLayerTable() {
        var table = Self.q7(uncertainCell: false, uncertainKey: false, uncertainHeading: false)
        table.source = .textLayer
        let applied = apply([Self.check(row: ["QZ12"], value: "99")], to: table)
        XCTAssertEqual(applied.table.rows[2].cells[0].text, "70")
        XCTAssertNil(applied.table.rows[2].cells[0].check)
        XCTAssertEqual(applied.unmatched.count, 1)
        XCTAssertNil(TableChecks.status(of: applied.table))
        XCTAssertFalse(apply([], to: table, require: true).table.uncheckedWithheld,
                       "the requirement is for pictures only")
    }

    // MARK: - Disagreement

    func testThePhoneAndTheVaultFileDisagreeingMakeTheCellUncertainWithBothValues() {
        let applied = apply([Self.check(value: "35", origin: .phone),
                             Self.check(value: "36", by: "the office reviewer", at: Self.later, origin: .vaultFile)])
        let cell = applied.table.rows[1].cells[0]
        XCTAssertTrue(cell.uncertain, "neither wins")
        XCTAssertEqual(cell.text, "3S", "what was read is kept")
        guard case .disagree(let marks)? = cell.check else { return XCTFail("\(String(describing: cell.check))") }
        XCTAssertEqual(marks.map(\.value), ["35", "36"])
        XCTAssertEqual(marks.map(\.by), ["the vault manager", "the office reviewer"])
        XCTAssertEqual(marks.map(\.origin), [.phone, .vaultFile])
        XCTAssertEqual(TableChecks.status(of: applied.table), .disagree(cells: 1))
    }

    func testTwoVaultFileEntriesDisagreeingAlsoDisagree() {
        let applied = apply([Self.check(value: "35", by: "reviewer one", origin: .vaultFile),
                             Self.check(value: "38", by: "reviewer two", origin: .vaultFile)])
        XCTAssertTrue(applied.table.rows[1].cells[0].uncertain)
        XCTAssertEqual(applied.table.rows[1].cells[0].check?.isDisagreement, true)
    }

    func testTheSameValueFromBothPlacesIsChecked() {
        let applied = apply([Self.check(value: "35", origin: .phone),
                             Self.check(value: " 35 ", by: "the office reviewer", at: Self.later, origin: .vaultFile)])
        let cell = applied.table.rows[1].cells[0]
        XCTAssertFalse(cell.uncertain)
        XCTAssertEqual(cell.value, 35)
        XCTAssertEqual(cell.check?.agreedMark?.by, "the office reviewer", "the latest check is the one named")
    }

    func testCheckingAgainOnThePhoneReplacesThePhonesEarlierCheck() {
        var kept = TableChecks.recording(Self.check(value: "35"), into: [])
        kept = TableChecks.recording(Self.check(value: "36", at: Self.later), into: kept)
        XCTAssertEqual(kept.map(\.value), ["36"])
        let applied = apply(kept)
        XCTAssertEqual(applied.table.rows[1].cells[0].text, "36")
        XCTAssertFalse(applied.table.rows[1].cells[0].uncertain)
    }

    // MARK: - Status and the requirement

    func testATableIsCheckedOnlyWhenEveryCellIsAndNoNameOrHeadingIsLeftUnclear() {
        let model = TableCheckModel(table: Self.q7(), documentHash: Self.bookHash, checks: [])
        XCTAssertEqual(model.status, .notChecked(checked: 0, cells: 6))
        let remaining = model.confirmRemaining(by: "the vault manager", at: Self.day)
        XCTAssertEqual(remaining.count, 5, "every cell read clearly, not the uncertain one")
        XCTAssertTrue(remaining.allSatisfy { $0.kind == .confirmed })

        var checks = remaining
        XCTAssertEqual(model.with(checks: checks).status, .notChecked(checked: 5, cells: 6))
        checks.append(Self.check(value: "35"))
        XCTAssertEqual(model.with(checks: checks).status, .notChecked(checked: 6, cells: 6),
                       "a row name and a heading are still unclear")
        checks += [Self.check(column: nil, kind: .confirmed, value: ""),
                   Self.check(row: nil, column: ["Invented band", "Band B"], kind: .confirmed, value: "")]
        XCTAssertEqual(model.with(checks: checks).status, .checked)
        XCTAssertEqual(model.with(checks: checks).needsLooking, 0)
    }

    func testRequiringChecksWithholdsAnUncheckedTableAndNotACheckedOne() {
        XCTAssertTrue(apply([], require: true).table.uncheckedWithheld)
        XCTAssertFalse(apply([]).table.uncheckedWithheld, "checking is optional by default")
        let clear = Self.q7(uncertainCell: false, uncertainKey: false, uncertainHeading: false)
        let all = TableCheckModel(table: clear, documentHash: Self.bookHash, checks: []).confirmRemaining(by: "the vault manager", at: Self.day)
        XCTAssertFalse(apply(all, to: clear, require: true).table.uncheckedWithheld)
        XCTAssertTrue(apply(Array(all.dropLast()), to: clear, require: true).table.uncheckedWithheld)
    }

    // MARK: - The check view's model

    func testTheModelMakesAConfirmationOrACorrectionFromWhatIsTyped() throws {
        let model = TableCheckModel(table: Self.q7(), documentHash: Self.bookHash, checks: [])
        XCTAssertEqual(model.state(row: 1, column: 0), .uncertain)
        XCTAssertEqual(model.state(row: 0, column: 0), .read)
        let same = try XCTUnwrap(model.check(row: 0, column: 0, value: " 40 ", by: "the vault manager", at: Self.day))
        XCTAssertEqual(same.kind, .confirmed)
        XCTAssertEqual(same.row, ["QXRT"])
        XCTAssertEqual(same.column, ["Spacing (mm)"])
        XCTAssertEqual(same.origin, .phone)
        let typed = try XCTUnwrap(model.check(row: 1, column: 0, value: "35", by: "the vault manager", at: Self.day))
        XCTAssertEqual(typed.kind, .corrected)
        let after = model.with(checks: [typed])
        guard case .checked(let mark) = after.state(row: 1, column: 0) else { return XCTFail("\(after.state(row: 1, column: 0))") }
        XCTAssertEqual(mark.value, "35")
        XCTAssertEqual(after.readText(row: 1, column: 0), "3S", "the view still shows what was read")
        XCTAssertNil(model.check(row: 9, column: 0, value: "1", by: "x", at: Self.day))
    }

    func testTheModelShowsADisagreementAndCountsWhatNeedsALook() {
        let model = TableCheckModel(table: Self.q7(), documentHash: Self.bookHash,
                                    checks: [Self.check(value: "35"), Self.check(value: "36", by: "the office reviewer",
                                                                                 origin: .vaultFile)])
        guard case .disagree(let marks) = model.state(row: 1, column: 0) else { return XCTFail() }
        XCTAssertEqual(marks.count, 2)
        XCTAssertEqual(model.needsLooking, 3, "the disagreeing cell, the row name and the heading")
        XCTAssertFalse(model.confirmRemaining(by: "the vault manager", at: Self.day)
            .contains { $0.row == ["QMX90"] && $0.column == ["Spacing (mm)"] }, "a disagreement is never confirmed in bulk")
    }

    // MARK: - The file

    func testTheFileRoundTripsInItsDocumentedShape() throws {
        let checks = [Self.check(value: "35"), Self.check(row: ["QZ12"], kind: .confirmed, value: "70", origin: .vaultFile)]
        let data = try TableChecksFile.encode(checks)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        for key in ["\"version\" : 1", "\"document_sha256\"", "\"checked_by\"", "\"checked_at\"", "\"origin\" : \"phone\""] {
            XCTAssertTrue(text.contains(key), key)
        }
        XCTAssertEqual(text.components(separatedBy: "\"origin\"").count - 1, 1, "origin written for a phone's check only")
        let parsed = TableChecksFile.parse(data)
        XCTAssertTrue(parsed.problems.isEmpty, "\(parsed.problems)")
        XCTAssertEqual(Set(parsed.checks), Set(checks))
    }

    func testAFileWithoutOriginReadsAsTheVaultFiles() {
        let json = """
        {"version": 1, "checks": [{"document_sha256": "\(Self.bookHash)", "table": "Table Q7", "row": ["QMX90"],
         "column": ["Spacing (mm)"], "kind": "corrected", "value": "35", "checked_by": "the office reviewer",
         "checked_at": "2026-10-21T09:30:00Z"}]}
        """
        let parsed = TableChecksFile.parse(Data(json.utf8))
        XCTAssertEqual(parsed.checks.first?.origin, .vaultFile)
        XCTAssertTrue(parsed.problems.isEmpty)
    }

    func testMalformedEntriesAreWarnedOfAndSkippedAndTheRestKept() {
        let json = """
        {"version": 1, "checks": [
          {"document_sha256": "\(Self.bookHash)", "table": "Table Q7", "row": ["QMX90"], "column": ["Spacing (mm)"],
           "kind": "corrected", "value": "35", "checked_by": "the vault manager", "checked_at": "2026-10-21T09:30:00Z"},
          {"document_sha256": "\(Self.bookHash)", "table": "Table Q7", "row": ["QMX90"], "column": ["Spacing (mm)"],
           "kind": "guessed", "value": "35", "checked_by": "the vault manager", "checked_at": "2026-10-21T09:30:00Z"},
          {"document_sha256": "not-a-hash", "table": "Table Q7", "row": ["QMX90"], "column": ["Spacing (mm)"],
           "kind": "confirmed", "value": "35", "checked_by": "the vault manager", "checked_at": "2026-10-21T09:30:00Z"},
          {"document_sha256": "\(Self.bookHash)", "table": "Table Q7", "kind": "confirmed", "value": "1",
           "checked_by": "the vault manager", "checked_at": "2026-10-21T09:30:00Z"},
          {"document_sha256": "\(Self.bookHash)", "table": "Table Q7", "row": ["QMX90"], "column": ["Spacing (mm)"],
           "kind": "confirmed", "value": "35", "checked_at": "2026-10-21T09:30:00Z"},
          {"document_sha256": "\(Self.bookHash)", "table": "Table Q7", "row": ["QMX90"],
           "kind": "corrected", "value": "QMX91", "checked_by": "the vault manager", "checked_at": "2026-10-21T09:30:00Z"},
          "a line of prose"
        ]}
        """
        let parsed = TableChecksFile.parse(Data(json.utf8))
        XCTAssertEqual(parsed.checks.count, 1)
        XCTAssertEqual(parsed.problems.count, 6, "\(parsed.problems)")
        XCTAssertTrue(parsed.problems.allSatisfy { $0.hasPrefix("table-checks.json entry ") && $0.hasSuffix("; skipped") })
        XCTAssertTrue(parsed.problems.contains { $0.contains("entry 6") && $0.contains("confirmed, not corrected") })
        XCTAssertTrue(parsed.problems.contains { $0.contains("\"checked_by\" is missing") })
        XCTAssertFalse(parsed.problems.joined().contains("QMX91"), "a value never reaches a warning")
    }

    func testAnotherVersionOrShapeIsNotRead() {
        XCTAssertEqual(TableChecksFile.parse(Data(#"{"version": 2, "checks": []}"#.utf8)).problems,
                       ["table-checks.json has version 2; this app reads version 1, so it was not read"])
        XCTAssertTrue(TableChecksFile.parse(Data(#"{"checks": []}"#.utf8)).problems[0].contains("version none"))
        XCTAssertTrue(TableChecksFile.parse(Data("[1, 2]".utf8)).problems[0].contains("not a JSON object"))
        XCTAssertTrue(TableChecksFile.parse(Data(#"{"version": 1}"#.utf8)).problems[0].contains("no \"checks\" list"))
        let big = Data(repeating: 0x20, count: TableChecksFile.maximumBytes + 1)
        XCTAssertTrue(TableChecksFile.parse(big).problems[0].contains("larger than"))
    }

    func testChecksForAPDFTheVaultDoesNotHoldAreWarnedOfAndKept() {
        let checks = [Self.check(), Self.check(hash: Self.otherHash), Self.check(row: ["QZ12"], hash: Self.otherHash)]
        let warnings = TableChecksFile.unknownDocumentWarnings(checks, known: [Self.bookHash])
        XCTAssertEqual(warnings, ["table-checks.json: 2 checks are for a PDF this vault does not hold (b2b2b2b2b2b2…); "
                                  + "kept, and applied if that PDF is loaded"])
    }

    // MARK: - Sharing checks (Plan JN P4)

    func testSharingChecksIsOfferedForVaultTablesOnlyNotPhotographedOnes() {
        XCTAssertTrue(TableCheckModel.offersSharing(photographed: false))
        XCTAssertFalse(TableCheckModel.offersSharing(photographed: true))
    }

    // MARK: - The day a check is said on (Plan JN P4)

    func testTheDayIsSaidOnThePhonesClockWhileTheCheckIsStoredInUTC() throws {
        // 11:30 UTC on 20 October is half past midnight on the 21st in New Zealand (NZDT, +13).
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-20T11:30:00Z"))
        let auckland = try XCTUnwrap(TimeZone(identifier: "Pacific/Auckland"))
        XCTAssertEqual(TableChecks.day(instant, timeZone: auckland), "2026-10-21")
        XCTAssertEqual(TableChecks.day(instant, timeZone: try XCTUnwrap(TimeZone(identifier: "UTC"))), "2026-10-20")
        let mark = TableCheckMark(value: "35", by: "the vault manager", at: instant, origin: .phone, kind: .corrected)
        XCTAssertEqual(TableChecks.checkedNote(mark), "checked by the vault manager on " + TableChecks.day(instant, timeZone: .current))
        let stored = String(decoding: try TableChecksFile.encode([Self.check(at: instant)]), as: UTF8.self)
        XCTAssertTrue(stored.contains("2026-10-20T11:30:00Z"), stored)
    }
}
