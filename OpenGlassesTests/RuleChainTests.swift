import XCTest
@testable import OpenGlasses

/// Plan JJ P2 — rule chains an organisation writes, run one step at a time. Every table, rule
/// number, designation and value here is invented (`RuleChainFixtures`, `TableFixtureLayouts`);
/// nothing is a fact from any book.
final class RuleChainTests: XCTestCase {

    // MARK: - Fixtures

    private func chains() throws -> [ChainDefinition] {
        let parsed = ChainParser.parse(RuleChainFixtures.chainsMarkdown)
        XCTAssertEqual(parsed.problems, [], "the example has no problem")
        XCTAssertEqual(parsed.chains.count, 3)
        return parsed.chains
    }

    private func chain(_ name: String) throws -> ChainDefinition {
        try XCTUnwrap(try chains().first { $0.name == name }, name)
    }

    /// Runs a chain with the answers in order, returning the last step and the state.
    private func run(_ chain: ChainDefinition, answers: [String],
                     tables: [TableLookup.Source] = RuleChainFixtures.tables()) -> (ChainStep, ChainState) {
        var state = ChainState()
        var step = ChainRunner.advance(chain, state: &state, answer: nil, tables: tables)
        for answer in answers {
            guard case .ask = step else { break }
            step = ChainRunner.advance(chain, state: &state, answer: answer, tables: tables)
        }
        return (step, state)
    }

    // MARK: - The schema

    func testTheFixtureTablesExtract() {
        let labels = RuleChainFixtures.tables().map(\.table.label)
        XCTAssertEqual(labels, ["Table 99", "Table 98", "Table 97", "Table 90", "Table 92"])
        let bands = RuleChainFixtures.tables().first { $0.table.label == "Table 90" }?.table
        XCTAssertEqual(bands?.rows.map { $0.cells.first?.text }, ["Band A", "Band B", "Band C"])
    }

    func testTheSchemaRoundTrips() throws {
        let original = try chains()
        XCTAssertEqual(original.map(\.name), ["Size a conductor for a load", "Check an installed conductor",
                                              "Voltage drop on a run"])
        let forward = original[0]
        XCTAssertEqual(forward.steps.count, 9, "cite lines attach to the step above them")
        XCTAssertEqual(forward.steps[4].citations, ["Rule QR-12"])
        guard case .ask(let load) = forward.steps[0].kind else { return XCTFail("an ask first") }
        XCTAssertEqual(load.unit, "A")
        XCTAssertEqual(load.range, 1...400)
        guard case .lookup(let size) = forward.steps[7].kind else { return XCTFail("a lookup") }
        XCTAssertEqual(size.cell, "{corrected}")
        XCTAssertEqual(size.rule, .atLeast)
        XCTAssertEqual(forward.tableLabels, ["Table 90", "Table 98", "Table 99"])

        let written = ChainParser.render(original)
        let again = ChainParser.parse(written)
        XCTAssertEqual(again.problems, [])
        XCTAssertEqual(again.chains, original, written)
        XCTAssertEqual(ChainParser.render(again.chains), written, "writing is stable")
    }

    func testStepsWrittenAsAListReadTheSameAsAFencedBlock() throws {
        let fenced = try chain("Voltage drop on a run")
        var listed = "## Voltage drop on a run\nAnswers: \(fenced.answers)\n\n"
        for step in fenced.steps {
            listed += "- " + ChainParser.text(of: step.kind) + "\n"
            listed += step.citations.map { "- cite \($0)\n" }.joined()
        }
        let parsed = ChainParser.parse(listed)
        XCTAssertEqual(parsed.problems, [])
        XCTAssertEqual(parsed.chains, [fenced])
    }

    func testABadStepIsReportedWithItsLine() {
        let file = """
        ## Broken chain
        Answers: nothing, it is broken on purpose.

        ```chain
        ask load (A) range 400..1: What load?
        lokup factor = Table 98 row {ambient} column Band A rule at_least
        calc corrected (A) = load / factor
        lookup size = Table 99 row {corrected} column Rating group 1 rule nearest
        say "Use {size.row} at {nothing}."
        ```

        ## Cites first
        - cite Rule QR-1
        - ask load (A): What load?
        """
        let parsed = ChainParser.parse(file)
        XCTAssertEqual(parsed.chains, [], "a chain with a problem is not offered")
        let byLine = Dictionary(grouping: parsed.problems, by: \.line).mapValues { $0.map(\.message) }
        XCTAssertTrue(byLine[5]?.first?.contains("runs backwards") == true, "\(parsed.problems)")
        XCTAssertTrue(byLine[6]?.first?.contains("unknown step 'lokup'") == true, "\(parsed.problems)")
        XCTAssertTrue(byLine[7]?.contains { $0.contains("'factor' is used before any step sets it") } == true, "\(parsed.problems)")
        XCTAssertTrue(byLine[8]?.first?.contains("the rule 'nearest'") == true, "\(parsed.problems)")
        XCTAssertTrue(byLine[13]?.first?.contains("'cite' attaches a rule to the step above it") == true, "\(parsed.problems)")
        XCTAssertTrue(byLine[14]?.contains { $0.contains("says nothing") } == true, "\(parsed.problems)")
        XCTAssertTrue(parsed.problems.allSatisfy { $0.description.hasPrefix("line \($0.line): ") })
        XCTAssertTrue(parsed.problems.first { $0.line == 6 }?.description.contains("Broken chain") == true)
    }

    func testANameSetTwiceAnAttributeOnAnAskAndAnUnclosedBlockAreProblems() {
        let file = """
        ## Twice
        ```chain
        ask load (A): What load?
        ask load (A): What load again?
        say "{load.row}"
        """
        let messages = ChainParser.parse(file).problems.map(\.description)
        XCTAssertTrue(messages.contains { $0.hasPrefix("line 4:") && $0.contains("already set by line 3") }, "\(messages)")
        XCTAssertTrue(messages.contains { $0.hasPrefix("line 5:") && $0.contains("needs a value a lookup set") }, "\(messages)")
        XCTAssertTrue(messages.contains { $0.hasPrefix("line 2:") && $0.contains("not closed") }, "\(messages)")
    }

    // MARK: - Running: cable sizing both ways

    func testTheForwardChainSizesTheConductor() throws {
        let forward = try chain("Size a conductor for a load")
        let (step, state) = run(forward, answers: ["32", "14", "5", "2"])
        guard case .finished(let said) = step else { return XCTFail("\(step)") }
        // 5 conductors is Band B; 14 °C is in 13-15; group 2 Band B there is 0.86; 32 / 0.86 is
        // 37.21; the smallest group 2 rating at least that is 45, QMX90 with two conductors.
        XCTAssertEqual(state.values["band"]?.text, "Band B")
        XCTAssertEqual(state.values["factor"]?.number, 0.86)
        XCTAssertEqual(try XCTUnwrap(state.values["corrected"]?.number), 32 / 0.86, accuracy: 1e-9)
        XCTAssertEqual(state.values["size"]?.text, "45")
        XCTAssertEqual(state.values["size"]?.lookup?.rowName, "QMX90 › two conductors")
        XCTAssertEqual(said, ["Use QMX90 › two conductors: rated 45 A in rating group 2, against 37.21 A once the load "
                              + "is divided by the factor of 0.86 (Table 98 (Correction factors), PDF page 3)."])
    }

    func testTheInverseChainSaysWhetherTheInstalledConductorCarriesIt() throws {
        let inverse = try chain("Check an installed conductor")
        // QXRT with three conductors is 35 in group 2; 35 × 0.86 = 30.1, short of 32.
        let (short, shortState) = run(inverse, answers: ["QXRT three conductors", "32", "14", "5", "2"])
        guard case .finished(let no) = short else { return XCTFail("\(short)") }
        XCTAssertEqual(shortState.verdicts, [false])
        XCTAssertEqual(no, ["QXRT › three conductors does not carry it: 30.1 A once corrected, against a load of 32 A. "
                            + "The next row is QMX90 › two conductors (45)."])

        // QMX90 with two conductors is 45; 45 × 0.86 = 38.7.
        let (enough, enoughState) = run(inverse, answers: ["QMX90 two conductors", "32", "14", "5", "2"])
        guard case .finished(let yes) = enough else { return XCTFail("\(enough)") }
        XCTAssertEqual(enoughState.verdicts, [true])
        XCTAssertEqual(yes, ["QMX90 › two conductors carries it: 38.7 A once corrected, against a load of 32 A."])
    }

    func testTheVoltageDropChainConvertsAndCalculates() throws {
        let drop = try chain("Voltage drop on a run")
        let (step, state) = run(drop, answers: ["QX6", "20", "100", "240"])
        guard case .finished(let said) = step else { return XCTFail("\(step)") }
        XCTAssertEqual(try XCTUnwrap(state.values["metres"]?.number), 30.48, accuracy: 1e-9)
        XCTAssertEqual(state.values["drop"]?.text, "1.1")
        XCTAssertEqual(state.values["drop"]?.unit, "V", "the column's bracketed unit")
        XCTAssertEqual(said, ["The drop is 6.71 V, 2.79 % of 240 V: within the 4.5 % this example allows."])
        let readBack = ChainRunner.readBack(drop, state: state)
        XCTAssertTrue(readBack.contains("metres = 100 ft in m = 30.48 m"), readBack)
        XCTAssertTrue(readBack.contains("volts = drop * current * metres / 100 = 1.1 * 20 * 30.48 / 100 = 6.71 V"), readBack)
    }

    // MARK: - Row rules

    func testAtLeastAndAtMostPickTheRightRowsAndExactStopsBetweenThem() throws {
        let tables = RuleChainFixtures.tables()
        func row(_ value: String, _ rule: TableLookup.RowRule) -> String? {
            guard case .found(let found) = TableLookup.resolve(.init(table: "Table 98", row: value,
                                                                     column: "Rating group 1 › Band A"),
                                                               rule: rule, in: tables) else { return nil }
            return found.rows.count == 1 ? found.rows[0].path.last : nil
        }
        XCTAssertEqual(row("14", .atLeast), "13-15", "a band that holds the number")
        XCTAssertEqual(row("14", .atMost), "13-15")
        XCTAssertEqual(row("14", .exact), "13-15")
        XCTAssertEqual(row("12.5", .atLeast), "13-15", "between two bands: the one above")
        XCTAssertEqual(row("12.5", .atMost), "10-12", "between two bands: the one below")
        XCTAssertNil(row("12.5", .exact), "exact gives both rows back and picks neither")
        XCTAssertEqual(row("5", .atLeast), "7-9", "below every row: the first is at least it")
        XCTAssertNil(row("5", .atMost))
        XCTAssertEqual(row("30", .atMost), "16-18", "above every row: the last is at most it")
        XCTAssertNil(row("30", .atLeast))

        // A cell search: the smallest group 3 rating at least 41 is 50; the largest at most 41 is 40.
        func cell(_ value: Double, _ rule: TableLookup.RowRule) -> String? {
            guard case .found(let found) = TableLookup.search(.init(table: "Table 99", row: "", column: "Rating group 3"),
                                                              value: value, rule: rule, in: tables) else { return nil }
            return TableLookup.rowName(found.rows[0])
        }
        XCTAssertEqual(cell(41, .atLeast), "QMX90 › two conductors")
        XCTAssertEqual(cell(41, .atMost), "QXRT › three conductors")
        XCTAssertEqual(cell(40, .exact), "QXRT › three conductors")
        XCTAssertNil(cell(41, .exact))
        XCTAssertNil(cell(60, .atLeast))

        // In a chain, exact on a number between rows stops and shows the table's page.
        let between = ChainParser.parse("""
        ## Exact band
        ```chain
        ask ambient (°C): What is the ambient?
        lookup factor = Table 98 row {ambient} column Rating group 1 › Band A rule exact
        say "{factor}"
        ```
        """).chains[0]
        let (step, _) = run(between, answers: ["12.5"])
        guard case .stopped(let stop) = step else { return XCTFail("\(step)") }
        XCTAssertTrue(stop.reason.contains("12.5 falls between the rows 10-12 and 13-15"), stop.reason)
        XCTAssertTrue(stop.reason.contains("never goes on from a guessed cell"), stop.reason)
        XCTAssertEqual(stop.sourceLine, "Source: Invented Book A, page 3, Table 98")
    }

    // MARK: - Answers

    func testAnAnswerOutOfRangeOrNotANumberIsAskedAgainAndNeverTaken() throws {
        let forward = try chain("Size a conductor for a load")
        var state = ChainState()
        let tables = RuleChainFixtures.tables()
        _ = ChainRunner.advance(forward, state: &state, answer: nil, tables: tables)
        let tooBig = ChainRunner.advance(forward, state: &state, answer: "4000", tables: tables)
        guard case .ask(let again) = tooBig else { return XCTFail("\(tooBig)") }
        XCTAssertEqual(again.name, "load")
        XCTAssertTrue(again.again?.contains("4000 A is outside what this chain takes for load (1 to 400 A)") == true,
                      again.again ?? "")
        XCTAssertNil(state.values["load"])
        XCTAssertEqual(state.position, 0)

        let words = ChainRunner.advance(forward, state: &state, answer: "about the usual", tables: tables)
        guard case .ask(let notNumber) = words else { return XCTFail("\(words)") }
        XCTAssertTrue(notNumber.again?.contains("is not a number") == true)

        let taken = ChainRunner.advance(forward, state: &state, answer: "32 amps", tables: tables)
        guard case .ask(let next) = taken else { return XCTFail("\(taken)") }
        XCTAssertEqual(next.name, "ambient")
        XCTAssertNil(next.again)
        XCTAssertEqual(state.values["load"]?.number, 32)
    }

    func testATemperatureSaidInAnotherUnitIsConvertedAndSaysSo() throws {
        let forward = try chain("Size a conductor for a load")
        let (_, state) = run(forward, answers: ["32", "57.2 °F"])
        XCTAssertEqual(try XCTUnwrap(state.values["ambient"]?.number), 14, accuracy: 1e-9)
        XCTAssertTrue(state.entries[1].text.contains("ambient: 14 °C (said as 57.2 °F)"), state.entries[1].text)
    }

    // MARK: - A size said with its unit (Plan JW P0)

    /// An invented Table 98A read from a picture, keyed by widget size: "7", "9" and "11" read
    /// clearly, a fourth row's key not — so no row is matched by number, only by its exact name.
    private func widgetSizes(keys: [String] = ["7", "9", "11"]) -> [TableLookup.Source] {
        var rows = zip(keys, [15.0, 20, 25]).map { key, rating in
            ManualTable.Row(path: [key], cells: [.init(text: ChainRunner.display(rating), value: rating)],
                            page: .init(physical: 4))
        }
        rows.append(.init(path: ["1?"], cells: [.init(text: "30", value: 30)], page: .init(physical: 4), keyUncertain: true))
        let table = ManualTable(label: "Table 98A", title: "Invented widget sizes", page: .init(physical: 4),
                                rowHeaders: ["Size"], columns: [.init(path: ["Rating"])], rows: rows,
                                source: .recognised(reader: .documentGrid, meanConfidence: 0.9))
        return [TableLookup.Source(documentId: "w", documentName: "Invented Book W", table: table)]
    }

    private func widgetChain() throws -> ChainDefinition {
        try XCTUnwrap(ChainParser.parse("""
        ## Size widgets for a load
        ```chain
        ask size (text): Which widget size, as the table prints it?
        lookup rating = Table 98A row {size} column Rating rule exact
        say "{rating}"
        ```
        """).chains.first)
    }

    func testASizeSaidWithItsUnitIsTakenWhenTheKeysDoNotPrintTheUnit() throws {
        let chain = try widgetChain()
        for said in ["7 gauge", "No. 7", "#7", "size 7", "7mm²", "number 7", "7"] {
            let (step, state) = run(chain, answers: [said], tables: widgetSizes())
            guard case .finished(let result) = step else { return XCTFail("\(said): \(step)") }
            XCTAssertEqual(result, ["15"], said)
            XCTAssertEqual(state.values["rating"]?.lookup?.rowName, "7", said)
            XCTAssertTrue(state.entries[1].text.contains("(row asked for: \(said); rule exact)"),
                          "the read-back keeps what was said: \(state.entries[1].text)")
        }
        // A size the table does not print still stops, unit or none.
        let (missing, _) = run(chain, answers: ["8 gauge"], tables: widgetSizes())
        guard case .stopped = missing else { return XCTFail("\(missing)") }
    }

    func testAWordTheRowKeysPrintIsNeverDropped() {
        let printed = widgetSizes(keys: ["7 gauge", "9 gauge", "11 gauge"])[0].table
        XCTAssertNil(ChainRunner.withoutSizeWords("7 gauge", keptBy: printed))
        XCTAssertEqual(ChainRunner.withoutSizeWords("No. 7 gauge", keptBy: printed), "7 gauge")
        let plain = widgetSizes()[0].table
        XCTAssertEqual(ChainRunner.withoutSizeWords("7 GAUGE", keptBy: plain), "7")
        XCTAssertEqual(ChainRunner.withoutSizeWords("7 mm²", keptBy: plain), "7")
        XCTAssertNil(ChainRunner.withoutSizeWords("7", keptBy: plain), "nothing to drop")
        XCTAssertNil(ChainRunner.withoutSizeWords("gauge", keptBy: plain), "nothing would be left")
        XCTAssertNil(ChainRunner.withoutSizeWords("7 widgets", keptBy: plain), "only unit and size words go")
    }

    // MARK: - Stops

    func testAMissingTableStopsTheChainAndAnUnreadOneShowsItsPage() {
        let file = """
        ## Unread table
        ```chain
        ask key (text): Which row?
        lookup value = Table 92 row {key} column Value rule exact
        say "{value}"
        ```

        ## Absent table
        ```chain
        ask key (text): Which row?
        lookup value = Table 89 row {key} column Value rule exact
        say "{value}"
        ```
        """
        let chains = ChainParser.parse(file).chains
        XCTAssertEqual(chains.count, 2)

        let (unread, unreadState) = run(chains[0], answers: ["anything"])
        guard case .stopped(let stop) = unread else { return XCTFail("\(unread)") }
        XCTAssertTrue(stop.reason.contains("Table 92 (Wiring notes) is printed on page 44 of Invented Book A, but its grid could not be read"),
                      stop.reason)
        XCTAssertEqual(stop.sourceLine, "Source: Invented Book A, page 6 (printed 44), Table 92")
        XCTAssertEqual(stop.citations, [Citation(kind: .manual, title: "Invented Book A", page: 6, figure: "Table 92")])
        XCTAssertEqual(stop.stepIndex, 1)
        XCTAssertNil(unreadState.values["value"], "nothing is carried past the step")
        XCTAssertTrue(ChainRunner.readBack(chains[0], state: unreadState).contains("Stopped at step 2 of 3"))
        var after = unreadState
        XCTAssertEqual(ChainRunner.advance(chains[0], state: &after, answer: "again", tables: RuleChainFixtures.tables()),
                       unread, "a stopped chain stays stopped")

        let (absent, _) = run(chains[1], answers: ["anything"])
        guard case .stopped(let gone) = absent else { return XCTFail("\(absent)") }
        XCTAssertTrue(gone.reason.contains("Table 89 is not among the tables read from the loaded manuals"), gone.reason)
        XCTAssertNil(gone.sourceLine, "there is no page to show")

        XCTAssertEqual(chains[1].missingTables(available: RuleChainFixtures.tables().map(\.table.label)), ["Table 89"])
        XCTAssertEqual(chains[0].missingTables(available: RuleChainFixtures.tables().map(\.table.label)), [],
                       "a caption whose grid was not read is there")
    }

    func testAColumnTheTableLacksStopsWithThePage() throws {
        let forward = try chain("Size a conductor for a load")
        // Rating group 3 is a column of Table 99 but not of Table 98.
        let (step, state) = run(forward, answers: ["32", "14", "5", "3"])
        guard case .stopped(let stop) = step else { return XCTFail("\(step)") }
        XCTAssertTrue(stop.reason.contains("Table 98 has no column \"Rating group 3 › Band B\""), stop.reason)
        XCTAssertEqual(stop.sourceLine, "Source: Invented Book A, page 3, Table 98")
        XCTAssertEqual(state.entries.count, 5, "four answers and the band, nothing after the stop")
    }

    // MARK: - The read-back

    func testTheReadBackNamesEveryStepWithItsCitation() throws {
        let forward = try chain("Size a conductor for a load")
        let (_, state) = run(forward, answers: ["32", "14", "5", "2"])
        let readBack = ChainRunner.readBack(forward, state: state)
        let lines = readBack.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "Chain: Size a conductor for a load")
        XCTAssertEqual(lines.count, 1 + forward.steps.count + 1, readBack)
        XCTAssertEqual(lines[1], "1. load: 32 A, as the technician said")
        XCTAssertEqual(lines[5], "5. band: Table 90 (Grouping bands), row 4-6, column Band: Band B — PDF page 5 of "
                       + "Invented Book A (row asked for: 5; rule exact) — follows Rule QR-12")
        XCTAssertEqual(lines[6], "6. factor: Table 98 (Correction factors), row 13-15, column Rating group 2 › Band B: "
                       + "0.86 — PDF page 3 of Invented Book A (row asked for: 14; rule at_least) — follows Rule QR-14")
        XCTAssertEqual(lines[7], "7. corrected = load / factor = 32 / 0.86 = 37.21 A")
        XCTAssertEqual(lines[8], "8. size: Table 99 (Conductor ratings), row QMX90 › two conductors, column Rating group 2: "
                       + "45 — page 12 of Invented Book A (the row whose cell is at least 37.209302; rule at_least) "
                       + "— follows Rule QR-17")
        XCTAssertTrue(lines[9].hasPrefix("9. said: Use QMX90"), lines[9])
        XCTAssertTrue(lines[10].hasPrefix("Result: Use QMX90 › two conductors"), lines[10])

        XCTAssertEqual(ChainRunner.sourceLines(state), [
            "Source: Invented Book A, page 5, Table 90",
            "Source: Invented Book A, page 3, Table 98",
            "Source: Invented Book A, page 2 (printed 12), Table 99",
        ])
        for line in ChainRunner.sourceLines(state) {
            XCTAssertEqual(CitationLineParser.citations(inLine: line).count, 1, "each Source line is a chip: \(line)")
        }
    }

    // MARK: - The evaluator

    func testTheArithmeticEvaluatorKeepsPrecedenceAndRefusesWhatDoesNotRead() throws {
        XCTAssertEqual(ArithmeticExpression.evaluate("(45 * 2) + 100 / 4"), 115)
        XCTAssertEqual(ArithmeticExpression.evaluate("7 / 2"), 3.5, "not whole-number division")
        XCTAssertEqual(ArithmeticExpression.evaluate("-3 + 2 * -2"), -7)
        XCTAssertNil(ArithmeticExpression.evaluate("2 +"), "a malformed expression is refused, not raised")
        XCTAssertNil(ArithmeticExpression.evaluate("(1 + 2"))
        XCTAssertNil(ArithmeticExpression.evaluate("1 / 0"))
        XCTAssertNil(ArithmeticExpression.evaluate("load * 2"), "calculate takes numbers only")
        let node = try ArithmeticExpression.parse("load / factor")
        XCTAssertEqual(ArithmeticExpression.names(in: node), ["load", "factor"])
        XCTAssertEqual(try ArithmeticExpression.evaluate(node, value: ["load": 32, "factor": 0.5].get).get(), 64)
    }

    func testTheCalculatorToolAnswersAsBefore() async throws {
        let reply = try await CalculatorTool().execute(args: ["expression": "(45 * 2) + 100 / 4"])
        XCTAssertEqual(reply, "(45 * 2) + 100 / 4 = 115")
        let half = try await CalculatorTool().execute(args: ["expression": "7 / 2"])
        XCTAssertEqual(half, "7 / 2 = 3.5")
        let bad = try await CalculatorTool().execute(args: ["expression": "2 +"])
        XCTAssertEqual(bad, "Couldn't evaluate that expression.")
    }

    // MARK: - Where it is offered

    func testTheOnDeviceSetDoesNotOfferRuleChainAndTheFieldProfileDoes() {
        let registered = ["field_session", "reading", "table_lookup", "rule_chain", "get_datetime"]
        for offline in [false, true] {
            let names = AppleOnDeviceToolSet.priorityNames(registered: registered, fieldAssistActive: true,
                                                           offlineHandoff: offline)
            XCTAssertFalse(names.contains("rule_chain"))
            XCTAssertTrue(names.contains("table_lookup"))
        }
        XCTAssertTrue(FieldToolProfile.names.contains("rule_chain"))
        XCTAssertEqual(OfflineToolPolicy.offlineNames(["rule_chain"]), ["rule_chain"])
    }

    // MARK: - The vault guide's example

    func testTheVaultGuidesExampleIsTheTestVaultsChains() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let guide = try String(contentsOf: root.appendingPathComponent("docs/field-assist-vault-guide.md"), encoding: .utf8)
        let section = try XCTUnwrap(guide.components(separatedBy: "## Tables and chains").dropFirst().first,
                                    "the guide has a Tables and chains section")
        let example = try XCTUnwrap(section.components(separatedBy: "~~~markdown\n").dropFirst().first?
            .components(separatedBy: "\n~~~").first, "the section's example is a ~~~markdown block")
        let parsed = ChainParser.parse(example)
        XCTAssertEqual(parsed.problems, [])
        XCTAssertEqual(parsed.chains, try chains(), "the guide's example is the test vault's chains.md")
    }
}

private extension Dictionary where Key == String, Value == Double {
    func get(_ key: String) -> Double? { self[key] }
}
