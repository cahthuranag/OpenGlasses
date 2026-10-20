import Foundation

/// Runs a rule chain the active vault offers (Plan JJ P2): a sequence the organisation wrote in
/// its `chains.md` that asks the technician for values, looks cells up in the tables extracted from
/// the vault's own loaded manuals, does the arithmetic and a check, and reads every step back with
/// its citation. [[ChainRunner]] keeps the state and never goes past a step it could not complete;
/// the current question is in the system prompt (`FieldSessionService.chainPromptContext`), so the
/// model asks in its own words. A finished or stopped chain files its read-back on the job as a
/// reading, and its lookups' pages are what "show me the table" opens.
///
/// Not offered to Apple's on-device model (decision 7): a chain's steps and read-back do not fit
/// that window.
@MainActor
final class RuleChainTool: NativeTool {
    let name = "rule_chain"
    let description = """
    Run a rule chain the active Field Assist vault offers: steps its organisation wrote that ask the \
    technician for values, look cells up in the tables of the loaded code books, do the arithmetic \
    and a check, and read every step back with its table, row, column and page — for example sizing \
    a conductor for a load, or checking whether an installed one carries it. Actions: 'list' (the \
    chains, by what they answer), 'start' (pass 'chain', its name), 'answer' (pass 'value', the \
    technician's reply to the current question, as said), 'status', 'stop'. The current question is \
    in the system prompt: ask it in your own words. Never pass a value the technician did not say, \
    and never work a step yourself. When it finishes, say the result and read back the steps with \
    their pages; when it stops, say why and offer to show the page. Requires an active session.
    """
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "action": [
                "type": "string",
                "description": "'list', 'start', 'answer', 'status' or 'stop'."
            ],
            "chain": [
                "type": "string",
                "description": "On 'start': the chain's name as 'list' gives it."
            ],
            "value": [
                "type": "string",
                "description": "On 'answer': what the technician said, e.g. \"32\", \"14 °C\" or a size as printed."
            ]
        ],
        "required": ["action"]
    ]

    private let documentStore: DocumentStore?
    private let injectedSession: FieldSessionService?

    init(documentStore: DocumentStore?, sessionService: FieldSessionService? = nil) {
        self.documentStore = documentStore
        self.injectedSession = sessionService
    }

    func execute(args: [String: Any]) async throws -> String {
        guard Config.fieldAssistActive else {
            return "Field Assist is disabled. Enable it in Settings → Field Assist."
        }
        let actions = "'list', 'start', 'answer', 'status' or 'stop'"
        guard let action = (args["action"] as? String)?.lowercased().trimmingCharacters(in: .whitespaces) else {
            return "No action given. Use \(actions)."
        }
        let session = injectedSession ?? FieldSessionService.shared
        guard session.activeSession != nil else {
            return FieldSessionService.ChainError.noSession.errorDescription ?? ""
        }
        switch action {
        case "list": return list(session)
        case "start": return start(args: args, session: session)
        case "answer": return answer(args: args, session: session)
        case "status": return status(session)
        case "stop", "cancel":
            guard let run = session.stopChain() else { return "No rule chain is running." }
            return "Stopped the chain '\(run.chain.name)' at step \(run.state.position + 1). Nothing was recorded on the job."
        default:
            return "Unknown action '\(action)'. Use \(actions)."
        }
    }

    // MARK: - Actions

    private func tables(_ session: FieldSessionService) -> [TableLookup.Source] {
        guard let store = session.activeVault, let documentStore else { return [] }
        return TableLookupTool.sources(store: store, session: session, documentStore: documentStore,
                                       namedDocument: false, said: "")
    }

    private func list(_ session: FieldSessionService) -> String {
        let vault = session.vaultChains
        guard !vault.chains.isEmpty else {
            return vault.problems.isEmpty
                ? "This vault offers no rule chains."
                : "This vault's chains.md has \(vault.problems.count) problem(s), so none of its chains is offered: "
                    + vault.problems.prefix(3).map(\.description).joined(separator: "; ")
        }
        let labels = tables(session).map(\.table.label)
        var lines = ["Rule chains in this vault:"]
        for chain in vault.chains {
            var line = "• \(chain.name)" + (chain.answers.isEmpty ? "" : " — answers: \(chain.answers)")
            let missing = chain.missingTables(available: labels)
            if !missing.isEmpty {
                line += " (needs \(missing.joined(separator: ", ")), which no loaded manual's tables include: "
                    + "it will stop at that step)"
            }
            lines.append(line)
        }
        if !vault.problems.isEmpty {
            lines.append("\(vault.problems.count) chain problem(s) in chains.md keep some chains out.")
        }
        return lines.joined(separator: "\n")
    }

    private func start(args: [String: Any], session: FieldSessionService) -> String {
        let asked = (args["chain"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let vault = session.vaultChains
        let names = vault.chains.map(\.name)
        guard !asked.isEmpty else {
            return "Say which chain ('chain'). " + (names.isEmpty ? "This vault offers none." : "Chains: " + names.joined(separator: "; ") + ".")
        }
        let matches = vault.chains(named: asked)
        guard matches.count == 1, let chain = matches.first else {
            if matches.isEmpty {
                return "No chain is named like \"\(asked)\". "
                    + (names.isEmpty ? "This vault offers none." : "Chains: " + names.joined(separator: "; ") + ".")
            }
            return "More than one chain fits \"\(asked)\": " + matches.map(\.name).joined(separator: "; ")
                + ". Ask the technician which."
        }
        do {
            let progress = try session.startChain(chain, tables: tables(session))
            note(progress, session: session)
            return "Started the chain '\(chain.name)'.\n" + present(progress)
        } catch {
            return error.localizedDescription
        }
    }

    private func answer(args: [String: Any], session: FieldSessionService) -> String {
        let value: String
        if let text = args["value"] as? String { value = text } else if let number = args["value"] as? NSNumber {
            value = number.stringValue
        } else { value = "" }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Pass 'value': what the technician said in reply to the chain's question."
        }
        do {
            let progress = try session.answerChain(value, tables: tables(session))
            note(progress, session: session)
            return present(progress)
        } catch {
            return error.localizedDescription
        }
    }

    private func status(_ session: FieldSessionService) -> String {
        guard let run = session.activeChain else { return "No rule chain is running." }
        var lines = ["Running the chain '\(run.chain.name)', step \(run.state.position + 1) of \(run.chain.steps.count)."]
        lines += run.state.entries.map { "- " + Self.entryLine($0) }
        if case .ask(let ask) = run.current { lines.append(Self.askLine(ask)) }
        return lines.joined(separator: "\n")
    }

    // MARK: - Showing

    /// The chain's lookups so far are the answer's citations: "show me the table" opens their
    /// pages with the rows marked, as `table_lookup`'s do.
    private func note(_ progress: ChainProgress, session: FieldSessionService) {
        let citations = ChainRunner.citations(progress.state)
        guard !citations.isEmpty else { return }
        let founds = progress.state.values.values.compactMap(\.lookup).map(\.found)
        let rows = documentStore.map { TableLookupTool.rowPassages(for: founds, documentStore: $0) } ?? []
        session.sourceCenter.noteTableLookup(rows: rows, citations: citations, sessionId: session.activeSession?.id)
    }

    private func present(_ progress: ChainProgress) -> String {
        var lines = progress.newEntries.map { "- " + Self.entryLine($0) }
        switch progress.step {
        case .ask(let ask):
            lines.append(Self.askLine(ask))
        case .finished(let said):
            lines.append("Finished. Say the result: " + said.joined(separator: " "))
            lines.append("Then read the steps back with their pages. Recorded on the job:")
            lines.append(ChainRunner.readBack(progress.chain, state: progress.state))
            lines += ChainRunner.sourceLines(progress.state)
        case .stopped(let stop):
            lines.append("Stopped at step \(stop.stepIndex + 1): \(stop.reason)")
            lines.append("Tell the technician why, and do not answer from memory or guess the value. "
                         + (stop.sourceLine == nil ? "" : "Offer to show the page with show_source. ")
                         + "What was worked so far is recorded on the job.")
            lines += ChainRunner.sourceLines(progress.state)
        }
        return lines.joined(separator: "\n")
    }

    private static func askLine(_ ask: ChainAsk) -> String {
        var line = ""
        if let again = ask.again { line += "That answer was not taken: \(again)\n" }
        line += "Next, ask the technician: \(ask.question) (it needs \(RuleChainWording.needs(ask))). "
            + "Call 'answer' with what they say."
        return line
    }

    private static func entryLine(_ entry: ChainState.Entry) -> String {
        entry.text + (entry.rules.isEmpty ? "" : " — follows \(entry.rules.joined(separator: ", "))")
    }
}
