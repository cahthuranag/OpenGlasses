import Foundation

/// Runs a rule chain the active vault offers (Plan JJ P2): a sequence the organisation wrote in
/// its `chains.md` that asks the technician for values, looks cells up in the tables extracted from
/// the vault's own loaded manuals, does the arithmetic and a check, and reads every step back with
/// its citation. [[ChainRunner]] keeps the state and never goes past a step it could not complete;
/// the current question is in the system prompt (`FieldSessionService.chainPromptContext`), so the
/// model asks in its own words. A finished or stopped chain files its read-back on the job as a
/// reading, and its lookups' pages are what "show me the table" opens.
///
/// Since P3 it also runs the chain the model proposed with `propose_chain` once the technician says
/// go, and chains kept on this phone, each marked unreviewed wherever it is said or filed; `keep`
/// keeps a proposed chain that ran to a result, and `share` hands the kept chains to the share
/// sheet as a `chains.md` fragment, so an organisation with no office can add them by hand.
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
    a conductor for a load, or checking whether an installed one carries it. It also runs a chain \
    proposed with propose_chain once the technician says go, and chains kept on this phone; both are \
    unreviewed, so say so. Actions: 'list' (the chains, by what they answer), 'start' (pass 'chain', \
    its name), 'answer' (pass 'value', the technician's reply to the current question, as said), \
    'status', 'stop', 'keep' (keep the proposed chain that just ran to a result on this phone, when \
    the technician asks), 'share' (the kept chains as a chains.md file, by the share sheet). The \
    current question is in the system prompt: ask it in your own words. Never pass a value the \
    technician did not say, and never work a step yourself. When it finishes, say the result and \
    read back the steps with their pages; when it stops, say why and offer to show the page. \
    Requires an active session.
    """
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "action": [
                "type": "string",
                "description": "'list', 'start', 'answer', 'status', 'stop', 'keep' or 'share'."
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
    /// The delivery rules in force, for whether the share sheet may be used. Injectable so a test
    /// does not depend on this device's settings.
    private let settings: () -> DeliverySettings
    /// Where the shared fragment's file is staged.
    private let injectedExports: StagedExportCoordinator?

    init(documentStore: DocumentStore?, sessionService: FieldSessionService? = nil,
         settings: @escaping () -> DeliverySettings = { DeliverySettings.load() },
         exports: StagedExportCoordinator? = nil) {
        self.documentStore = documentStore
        self.injectedSession = sessionService
        self.settings = settings
        self.injectedExports = exports
    }

    func execute(args: [String: Any]) async throws -> String {
        guard Config.fieldAssistActive else {
            return "Field Assist is disabled. Enable it in Settings → Field Assist."
        }
        let actions = "'list', 'start', 'answer', 'status', 'stop', 'keep' or 'share'"
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
        case "keep", "save": return keep(session)
        case "share": return share(session)
        default:
            return "Unknown action '\(action)'. Use \(actions)."
        }
    }

    // MARK: - Actions

    private func tables(_ session: FieldSessionService) -> [TableLookup.Source] {
        guard documentStore != nil else { return [] }
        return session.chainTables(documentStore: documentStore)
    }

    private func list(_ session: FieldSessionService) -> String {
        let vault = session.vaultChains
        let offered = session.offeredChains
        guard !offered.isEmpty else {
            return vault.problems.isEmpty
                ? "This vault offers no rule chains."
                : "This vault's chains.md has \(vault.problems.count) problem(s), so none of its chains is offered: "
                    + vault.problems.prefix(3).map(\.description).joined(separator: "; ")
        }
        let labels = tables(session).map(\.table.label)
        var lines = ["Rule chains in this vault:"]
        for entry in offered {
            let chain = entry.chain
            var line = "• \(chain.name)" + (chain.answers.isEmpty ? "" : " — answers: \(chain.answers)")
            switch entry.origin {
            case .authored: break
            case .kept: line += " [\(ChainOrigin.kept.marking ?? ""): offered on this phone only]"
            case .proposed: line += " [\(ChainOrigin.proposed.marking ?? ""): waiting for the technician's go]"
            }
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
        let offered = session.offeredChains
        let names = offered.map(\.chain.name)
        guard !asked.isEmpty else {
            return "Say which chain ('chain'). " + (names.isEmpty ? "This vault offers none." : "Chains: " + names.joined(separator: "; ") + ".")
        }
        let matches = VaultChains(chains: offered.map(\.chain)).chains(named: asked)
        guard matches.count == 1, let chain = matches.first,
              let entry = offered.first(where: { $0.chain.name == chain.name }) else {
            if matches.isEmpty {
                return "No chain is named like \"\(asked)\". "
                    + (names.isEmpty ? "This vault offers none." : "Chains: " + names.joined(separator: "; ") + ".")
            }
            return "More than one chain fits \"\(asked)\": " + matches.map(\.name).joined(separator: "; ")
                + ". Ask the technician which."
        }
        do {
            let progress = try session.startChain(chain, tables: tables(session), origin: entry.origin,
                                                  sources: entry.sources)
            note(progress, session: session)
            let marked = entry.origin.marking.map { " (\($0))" } ?? ""
            return "Started the chain '\(chain.name)'\(marked).\n" + present(progress)
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
        let marked = run.origin.marking.map { " (\($0))" } ?? ""
        var lines = ["Running the chain '\(run.chain.name)'\(marked), step \(run.state.position + 1) of \(run.chain.steps.count)."]
        lines += run.state.entries.map { "- " + Self.entryLine($0) }
        if case .ask(let ask) = run.current { lines.append(Self.askLine(ask)) }
        return lines.joined(separator: "\n")
    }

    private func keep(_ session: FieldSessionService) -> String {
        switch session.keepLastProposedChain() {
        case .nothingToKeep:
            return "There is no proposed chain that ran to a result on this job to keep. A chain is kept after it "
                + "has run to its result with the technician, never before."
        case .failed(let reason):
            return reason
        case .kept(let kept, let review):
            var lines = ["Kept '\(kept.name)' on this phone, \(ChainOrigin.kept.marking ?? "unreviewed"). It is offered "
                         + "in the list on this phone only, and runs like any other chain. A chain your organisation "
                         + "adds to the vault's chains.md under the same name replaces it."]
            if let review { lines.append(review) }
            lines.append("To share the kept chains with the organisation, rule_chain 'share' puts them on the share "
                         + "sheet as a chains.md file to add to the vault by hand.")
            return lines.joined(separator: " ")
        }
    }

    /// The vault's kept chains on the share sheet as a `chains.md` fragment. Works with no office
    /// and no endpoint: a person picks where it goes.
    private func share(_ session: FieldSessionService) -> String {
        guard let store = session.activeVault,
              let share = RuleChainShare(vaultId: store.manifest.id, vaultName: store.manifest.name,
                                         kept: session.keptChains) else {
            return "No chain is kept on this phone for this vault, so there is nothing to share."
        }
        if let reason = DeliveryPolicy(settings: settings()).decide(channel: .shareSheet).reason {
            return reason
        }
        guard let lease = try? (injectedExports ?? .fieldSession).makeLease(data: Data(share.fragment.utf8), fileExtension: "md",
                                                 displayName: "chains", fallbackName: "chains") else {
            return "The chains file couldn't be prepared."
        }
        let attachment = DeliveryRequest.Attachment(url: lease.fileURL, kind: .chainsMarkdown,
                                                    filename: RuleChainShare.fileName)
        let request = DeliveryRequest.make(ruleChains: share, channel: .shareSheet, recipients: [],
                                           attachment: attachment)
        session.stageDelivery(request)
        return request.confirmation
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
            if let marking = progress.origin.marking {
                lines.append("Say that this chain is \(marking): nobody has reviewed its steps.")
            }
            lines.append("Then read the steps back with their pages. Recorded on the job:")
            lines.append(progress.reading?.value ?? ChainRunner.readBack(progress.chain, state: progress.state))
            if progress.origin == .proposed {
                lines.append("If the technician wants it again, rule_chain 'keep' keeps it on this phone, unreviewed.")
            }
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
