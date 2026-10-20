import XCTest
@testable import OpenGlasses

/// Plan JJ P3 — a chain the model proposes from passages it retrieved, checked before the
/// technician hears it, and kept on the phone. Every table, rule, passage and value is invented
/// (`ChainProposalFixtures`, `RuleChainFixtures`); nothing is a fact from any book.
final class ChainProposalTests: XCTestCase {

    private typealias F = ChainProposalFixtures

    private func propose(_ steps: String = F.steps, sources: [String] = F.sources,
                         context: ChainProposal.Context = F.context) -> Result<ChainProposal, ChainProposal.Refusal> {
        ChainProposal.make(text: steps, name: F.name, answers: F.answers, sources: sources, context: context)
    }

    private func accepted(_ steps: String = F.steps, sources: [String] = F.sources,
                          context: ChainProposal.Context = F.context) throws -> ChainProposal {
        switch propose(steps, sources: sources, context: context) {
        case .success(let proposal): return proposal
        case .failure(let refusal):
            XCTFail("refused: \(refusal.message)")
            throw refusal
        }
    }

    private func refusal(_ steps: String = F.steps, sources: [String] = F.sources,
                         context: ChainProposal.Context = F.context) -> ChainProposal.Refusal? {
        if case .failure(let refusal) = propose(steps, sources: sources, context: context) { return refusal }
        return nil
    }

    private func removing(_ line: String, from steps: String = F.steps) -> String {
        steps.split(separator: "\n").filter { $0.trimmingCharacters(in: .whitespaces) != line }.joined(separator: "\n")
    }

    // MARK: - Accepted

    func testAProposalWithACitationPerLookupIsAcceptedAndReadBackWithItsCitations() throws {
        let proposal = try accepted()
        XCTAssertEqual(proposal.chain.name, F.name)
        XCTAssertEqual(proposal.chain.steps.count, 9)
        XCTAssertEqual(proposal.missingTables, [])
        XCTAssertEqual(proposal.sources["factor"], "\(F.book), page 7, §QR-14", "kept without its Source: marker")
        XCTAssertEqual(proposal.passageCitations.count, 3)

        let lines = proposal.readBack.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "Proposed chain: \(F.name) (proposed, unreviewed)")
        XCTAssertEqual(lines[1], "Answers: \(F.answers)")
        XCTAssertEqual(lines[2], "1. Ask for load: What load will the circuit carry, in amps? (a number in A, from 1 to 400)")
        XCTAssertEqual(lines[3], "2. Work out ambient (°C) = 17")
        XCTAssertEqual(lines[6], "5. Look up band in Table 90: row {conductors}, column Band, rule exact — follows Rule QR-12 "
                       + "— from \(F.book), page 6, §QR-12")
        XCTAssertEqual(lines[9], "8. Look up size in Table 99: the row whose cell in column Rating group {group} is at least "
                       + "{corrected} — follows Rule QR-17 — from \(F.book), page 8, §QR-17")
        XCTAssertEqual(lines.count, 11)
    }

    func testAProposalAlreadyUnderAHeadingReadsTheSame() throws {
        let headed = "## \(F.name)\nAnswers: \(F.answers)\n\n```chain\n\(F.steps)\n```"
        let proposal = try XCTUnwrap(try? ChainProposal.make(text: headed, sources: F.sources, context: F.context).get())
        XCTAssertEqual(proposal.chain, try accepted().chain)
    }

    func testAProposalNamingATableTheVaultLacksIsAcceptedAndMarked() throws {
        let steps = F.steps.replacingOccurrences(of: "lookup band = Table 90", with: "lookup band = Table 89")
        let proposal = try accepted(steps)
        XCTAssertEqual(proposal.missingTables, ["Table 89"])
        XCTAssertTrue(proposal.readBack.contains("5. Look up band in Table 89: row {conductors}, column Band, rule exact "
                                                 + "— follows Rule QR-12 — from \(F.book), page 6, §QR-12 (needs Table 89, "
                                                 + "which no loaded manual's tables include: the chain will stop here)"),
                      proposal.readBack)
        XCTAssertEqual(proposal.readBack.components(separatedBy: "(needs").count, 2, "only that step is marked")
    }

    // MARK: - Refused

    func testALookupWithNoCiteIsRefused() {
        let steps = removing("cite Rule QR-14")
        XCTAssertEqual(refusal(steps), .uncited(["step 6 (lookup factor = Table 98 row {ambient} column Rating group "
                                                 + "{group} › {band} rule at_least)"]))
        XCTAssertTrue(refusal(steps)?.message.hasPrefix("These steps cite no rule: step 6") == true)
    }

    func testACheckWithNoCiteIsRefused() {
        let steps = F.steps.replacingOccurrences(
            of: "say \"Use {size.row}: rated {size} A in rating group {group}, against {corrected} A.\"",
            with: "check size >= corrected ? \"{size.row} carries it\" : \"it does not\"")
        XCTAssertEqual(refusal(steps), .uncited(["step 9 (check size >= corrected ? \"{size.row} carries it\" : \"it does not\")"]))
    }

    func testAProposalThatCitesNothingIsRefused() {
        let steps = ["cite Rule QR-12", "cite Rule QR-14", "cite Rule QR-17"].reduce(F.steps) { removing($1, from: $0) }
        XCTAssertEqual(refusal(steps), .citesNothing)
    }

    func testAProposalCitingARuleNotInTheSuppliedPassagesIsRefused() {
        let steps = F.steps.replacingOccurrences(of: "cite Rule QR-17", with: "cite Rule QR-71")
        XCTAssertEqual(refusal(steps), .ruleNotInPassages(["Rule QR-71"]))
        XCTAssertTrue(refusal(steps)?.message.contains("never a rule from memory") == true)
        // A number that is only the start of one the passages print is not that rule.
        let shorter = F.steps.replacingOccurrences(of: "cite Rule QR-17", with: "cite Rule QR-1")
        XCTAssertEqual(refusal(shorter), .ruleNotInPassages(["Rule QR-1"]))
        // A subrule of a printed rule is that rule's number.
        XCTAssertNotNil(try? propose(F.steps.replacingOccurrences(of: "cite Rule QR-17", with: "cite Rule QR-17(2)")).get())
    }

    func testEveryLookupNamesARetrievedPassage() {
        XCTAssertEqual(refusal(sources: Array(F.sources.prefix(2))), .missingSource(["size"]))
        var wrong = F.sources
        wrong[1] = "\(F.book), page 70, §QR-14"
        XCTAssertEqual(refusal(sources: wrong), .sourceNotRetrieved(lookup: "factor", source: wrong[1]))
        wrong[1] = "Invented Book B, page 7"
        XCTAssertEqual(refusal(sources: wrong), .sourceNotRetrieved(lookup: "factor", source: wrong[1]))
    }

    func testNothingRetrievedMeansNothingCanBeProposed() {
        let empty = ChainProposal.Context(passages: [], tableLabels: F.tableLabels)
        XCTAssertEqual(refusal(context: empty), .noPassages)
        XCTAssertTrue(ChainProposal.Refusal.noPassages.message.contains("manual_lookup"))
    }

    func testAProposalThatDoesNotReadOrTakesANameIsRefused() {
        guard case .doesNotRead(let problems)? = refusal(F.steps + "\nlokup x = Table 99 row QXRT rule exact") else {
            return XCTFail("a bad step is refused")
        }
        XCTAssertTrue(problems.first?.contains("unknown step 'lokup'") == true, "\(problems)")
        XCTAssertEqual(ChainProposal.make(text: F.steps, sources: F.sources, context: F.context).failureValue, .noName)
        XCTAssertEqual(ChainProposal.make(text: F.steps, name: "Size a conductor for a load", sources: F.sources,
                                          context: F.context).failureValue,
                       .nameTaken("Size a conductor for a load"))
    }

    // MARK: - Changing a step

    func testAChangedStepReparsesAndRunsThroughTheRunner() throws {
        let proposal = try accepted()
        let changed = try XCTUnwrap(try? proposal.changing(step: 2, to: F.askAmbient, context: F.context).get())
        guard case .ask(let ask) = changed.chain.steps[1].kind else { return XCTFail("step 2 asks now") }
        XCTAssertEqual(ask.name, "ambient")
        XCTAssertEqual(ask.range, 0...40)
        XCTAssertEqual(changed.chain.name, F.name, "a change keeps the chain's name")
        XCTAssertEqual(changed.sources, proposal.sources, "the lookups keep their passages")
        XCTAssertTrue(changed.readBack.contains("2. Ask for ambient: What is the ambient temperature along the run? "
                                                + "(a number in °C, from 0 to 40)"), changed.readBack)

        var state = ChainState()
        var step = ChainRunner.advance(changed.chain, state: &state, answer: nil, tables: RuleChainFixtures.tables())
        for answer in ["32", "14", "5", "2"] {
            step = ChainRunner.advance(changed.chain, state: &state, answer: answer, tables: RuleChainFixtures.tables())
        }
        guard case .finished(let said) = step else { return XCTFail("\(step)") }
        XCTAssertEqual(said.first?.hasPrefix("Use QMX90 › two conductors: rated 45 A in rating group 2"), true, "\(said)")
    }

    func testAChangeThatAddsALookupNeedsItsPassageAndOneThatBreaksIsRefused() throws {
        let proposal = try accepted()
        let lookup = "lookup ambient = Table 98 row 13 column Ambient (°C) rule exact\ncite Rule QR-14"
        XCTAssertEqual(proposal.changing(step: 2, to: lookup, context: F.context).failureValue, .missingSource(["ambient"]))
        XCTAssertNotNil(try? proposal.changing(step: 2, to: lookup, source: F.sources[1], context: F.context).get())
        XCTAssertEqual(proposal.changing(step: 12, to: F.askAmbient, context: F.context).failureValue,
                       .noSuchStep(12, count: 9))
        guard case .doesNotRead? = proposal.changing(step: 2, to: "ask ambient", context: F.context).failureValue else {
            return XCTFail("a step that does not read is refused")
        }
    }

    // MARK: - Kept chains and the fragment

    func testTheSharedFragmentIsAChainsFileTheP2ParserAccepts() throws {
        let proposal = try accepted()
        let other = try accepted(F.steps, sources: F.sources).chain
        var renamed = other
        renamed.name = "Size a conductor, second"
        let kept = [KeptChain(chain: proposal.chain, sources: proposal.sources,
                              keptAt: Date(timeIntervalSince1970: 1_800_000_000), jobReference: "1042"),
                    KeptChain(chain: renamed, sources: proposal.sources, keptAt: Date(timeIntervalSince1970: 1_800_000_000),
                              jobReference: nil)]
        let fragment = KeptChains.fragment(kept)
        let parsed = ChainParser.parse(fragment)
        XCTAssertEqual(parsed.problems, [], fragment)
        XCTAssertEqual(parsed.chains, [proposal.chain, renamed])
        XCTAssertTrue(fragment.hasPrefix("# Rule chains kept on a phone (unreviewed)\n"), fragment)
        XCTAssertTrue(fragment.contains("Unreviewed — kept on a phone on 2027-01-15, worked out on job 1042."), fragment)
        XCTAssertTrue(fragment.contains("Read from: band from \(F.book), page 6, §QR-12; factor from \(F.book), "
                                        + "page 7, §QR-14; size from \(F.book), page 8, §QR-17."), fragment)
        XCTAssertEqual(ChainParser.parse(kept[0].markdown).chains, [proposal.chain], "each kept chain reads on its own")

        let share = try XCTUnwrap(RuleChainShare(vaultId: "v", vaultName: "Rule Chain Test", kept: kept))
        let attachment = DeliveryRequest.Attachment(url: URL(fileURLWithPath: "/tmp/chains.md"), kind: .chainsMarkdown,
                                                    filename: RuleChainShare.fileName)
        let request = DeliveryRequest.make(ruleChains: share, channel: .shareSheet, recipients: [], attachment: attachment)
        XCTAssertEqual(request.attachments.map(\.kind), [.chainsMarkdown])
        XCTAssertEqual(request.attachments.first?.filename, "chains.md")
        XCTAssertEqual(DeliveryRequest.Attachment.Kind.chainsMarkdown.mimeType, "text/markdown")
        XCTAssertEqual(request.sessionId, RuleChainShare.queueSessionID, "kept chains belong to no job")
        XCTAssertNil(request.payload.queuedOp(), "never queued for an endpoint")
        XCTAssertTrue(request.body.hasSuffix(fragment), "the text to paste rides in the body too")
        XCTAssertTrue(request.confirmation.contains("Nobody has reviewed them"), request.confirmation)
        XCTAssertNil(RuleChainShare(vaultId: "v", vaultName: "x", kept: []))
    }

    func testAReviewedChainOfTheSameNameSupersedesTheKeptOne() throws {
        let proposal = try accepted()
        let kept = KeptChain(chain: proposal.chain, sources: proposal.sources, keptAt: Date(), jobReference: nil)
        XCTAssertEqual(KeptChains.offered([kept], authored: ChainParser.parse(RuleChainFixtures.chainsMarkdown).chains), [kept])
        var reviewed = proposal.chain
        reviewed.name = F.name.uppercased()
        XCTAssertEqual(KeptChains.offered([kept], authored: [reviewed]), [], "the organisation's chain of the same name wins")
        // Keeping a chain again under its name replaces it.
        let again = KeptChain(chain: proposal.chain, sources: [:], keptAt: Date(), jobReference: "7")
        XCTAssertEqual(KeptChains.keeping(again, in: [kept]), [again])
    }

    func testTheOnDeviceSetOffersNeitherProposingNorRunningAChain() {
        let registered = ["field_session", "reading", "table_lookup", "rule_chain", "propose_chain", "get_datetime"]
        for offline in [false, true] {
            let names = AppleOnDeviceToolSet.priorityNames(registered: registered, fieldAssistActive: true,
                                                           offlineHandoff: offline)
            XCTAssertFalse(names.contains("propose_chain"))
            XCTAssertFalse(names.contains("rule_chain"))
            XCTAssertTrue(names.contains("table_lookup"))
        }
        XCTAssertTrue(FieldToolProfile.names.contains("propose_chain"))
        XCTAssertEqual(OfflineToolPolicy.offlineNames(["propose_chain"]), ["propose_chain"])
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}
