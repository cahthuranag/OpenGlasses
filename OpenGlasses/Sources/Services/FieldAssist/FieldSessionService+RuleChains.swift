import Foundation

/// A rule chain running on the open job (Plan JJ P2): the chain, where it is, and what it last
/// asked or said. Held in memory for the job it was started on; a chain that finishes or stops
/// writes its read-back on the job as a reading and ends.
struct ActiveChainRun: Equatable {
    let sessionId: String
    let chain: ChainDefinition
    var state: ChainState
    var current: ChainStep
}

/// What one start or answer came to, for the tool to say.
struct ChainProgress: Equatable {
    let chain: ChainDefinition
    let state: ChainState
    let step: ChainStep
    /// The read-back entries this call added (the steps it ran).
    let newEntries: [ChainState.Entry]
    /// The reading the read-back was filed as, when the chain finished or stopped.
    let reading: SpokenReading?
}

extension FieldSessionService {

    enum ChainError: LocalizedError, Equatable {
        case noSession
        case alreadyRunning(String)
        case notRunning

        var errorDescription: String? {
            switch self {
            case .noSession: return "No active Field Assist session. Start a session before running a rule chain."
            case .alreadyRunning(let name):
                return "The chain '\(name)' is running. Answer its question, or stop it before starting another."
            case .notRunning: return "No rule chain is running. Use 'list' to see the chains, and 'start' to begin one."
            }
        }
    }

    /// The chain running on this job, if any. A chain started on an earlier job is not this job's.
    var activeChain: ActiveChainRun? {
        guard let run = chainRun, run.sessionId == activeSession?.id else { return nil }
        return run
    }

    /// The chains the session's vault offers, read from its `chains.md`.
    var vaultChains: VaultChains {
        activeVault.map(VaultChains.init(store:)) ?? VaultChains()
    }

    /// Start a chain and run it to its first question (or its end).
    func startChain(_ chain: ChainDefinition, tables: [TableLookup.Source]) throws -> ChainProgress {
        guard let session = activeSession else { throw ChainError.noSession }
        if let running = activeChain { throw ChainError.alreadyRunning(running.chain.name) }
        var state = ChainState()
        let step = ChainRunner.advance(chain, state: &state, answer: nil, tables: tables)
        let run = ActiveChainRun(sessionId: session.id, chain: chain, state: state, current: step)
        chainRun = run
        return settle(run, newEntries: state.entries)
    }

    /// The technician's answer to the chain's current question.
    func answerChain(_ answer: String, tables: [TableLookup.Source]) throws -> ChainProgress {
        guard var run = activeChain else { throw ChainError.notRunning }
        let before = run.state.entries.count
        run.current = ChainRunner.advance(run.chain, state: &run.state, answer: answer, tables: tables)
        chainRun = run
        return settle(run, newEntries: Array(run.state.entries.dropFirst(before)))
    }

    /// Stop the running chain without a result. Nothing is recorded: the technician stopped it.
    @discardableResult
    func stopChain() -> ActiveChainRun? {
        let run = activeChain
        chainRun = nil
        return run
    }

    /// A chain that finished or stopped files its read-back on the job and ends; one still asking
    /// carries on.
    private func settle(_ run: ActiveChainRun, newEntries: [ChainState.Entry]) -> ChainProgress {
        var reading: SpokenReading?
        switch run.current {
        case .ask:
            break
        case .finished, .stopped:
            reading = recordChainReading(chain: run.chain.name, readBack: ChainRunner.readBack(run.chain, state: run.state))
            chainRun = nil
        }
        return ChainProgress(chain: run.chain, state: run.state, step: run.current, newEntries: newEntries,
                             reading: reading)
    }

    // MARK: - Prompt

    /// The running chain's current question — the model asks it in its own words and the runner
    /// keeps the values — or, with none running, the chains the vault offers by what they answer.
    func chainPromptContext() -> String? {
        if let run = activeChain, case .ask(let ask) = run.current {
            return Self.chainPromptBlock(chain: run.chain, state: run.state, ask: ask)
        }
        let chains = vaultChains.chains
        guard !chains.isEmpty else { return nil }
        var lines = ["RULE CHAINS this vault offers. When the technician's question is one a chain answers, offer it "
                     + "and start it with rule_chain 'start' (pass its name); never work its steps yourself:"]
        lines += chains.prefix(8).map { "- \($0.name)" + ($0.answers.isEmpty ? "" : ": \($0.answers)") }
        if chains.count > 8 { lines.append("- and \(chains.count - 8) more (rule_chain 'list')") }
        return lines.joined(separator: "\n")
    }

    static func chainPromptBlock(chain: ChainDefinition, state: ChainState, ask: ChainAsk) -> String {
        var lines = ["ACTIVE RULE CHAIN — \(chain.name) (step \(ask.stepIndex + 1) of \(chain.steps.count)):"]
        lines.append("Ask the technician, in your own words: \(ask.question)")
        lines.append("It needs " + RuleChainWording.needs(ask) + ".")
        if let again = ask.again {
            lines.append("Their last answer was not taken: \(again)")
        }
        lines.append("When they answer, call rule_chain action 'answer' with what they said. Never answer for them, "
                     + "assume a value, or work a step yourself: the chain does the lookups and the arithmetic, and "
                     + "reads every step back with its page.")
        let done = state.entries.map(\.text)
        if !done.isEmpty {
            lines.append("So far: " + done.joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }
}

/// How a chain's question and progress are said, shared by the prompt block and the tool.
enum RuleChainWording {

    /// "a number in A, from 1 to 400", "a number", "the technician's words".
    static func needs(_ ask: ChainAsk) -> String {
        if ask.isText { return "the technician's words, as they say them" }
        var text = "a number" + (ask.unit.map { " in \($0)" } ?? "")
        if let range = ask.range {
            text += ", from \(ChainRunner.display(range.lowerBound)) to \(ChainRunner.display(range.upperBound))"
        }
        return text
    }
}
