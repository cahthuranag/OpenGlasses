import Foundation

/// Proposes a rule chain for a question no chain the vault offers answers (Plan JJ P3, decision 4).
///
/// The model retrieves the clauses first (`manual_lookup`, its clause and table routes), then
/// writes the steps those passages say in the chain syntax, with a `cite` on every lookup and check
/// and the passage each lookup came from. [[ChainProposal]] checks it against the passages actually
/// retrieved on this job and the vault's tables, and refuses one that cites nothing, names a rule
/// the passages do not contain, or names a passage that was never retrieved. An accepted proposal
/// is read back step by step with every rule and passage, and held for the technician: they say go
/// (`rule_chain start`), change a step (`change`), or stop (`withdraw`). Nothing runs here, and a
/// proposal is never run silently.
///
/// Not offered to Apple's on-device model (decision 7), like `rule_chain`.
@MainActor
final class ProposeChainTool: NativeTool {
    let name = "propose_chain"
    let description = """
    Propose a rule chain in the active Field Assist vault for a question about a table or a rule \
    that no chain the vault offers answers. First retrieve the clauses with manual_lookup (and the \
    cells with table_lookup); then propose the steps those passages say, never a step, rule, table \
    or value from memory of any code. Actions: 'propose' (pass 'chain', the steps in the chain \
    syntax — ask, lookup, calc, convert, check, cite, say, one per line, with a 'cite' line naming \
    the rule as printed under every lookup and check — with 'name', 'answers', and 'sources', the \
    Source line of the retrieved passage each lookup came from, one per lookup in order), 'change' \
    (pass 'step', its number as read back, and 'text', the new step with its cite line, plus \
    'source' for a new lookup), 'show', 'withdraw'. Read the proposal back as returned, every step \
    with its rule and passage, and say it is unreviewed; start it with rule_chain 'start' only when \
    the technician says go. Requires an active session.
    """
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "action": [
                "type": "string",
                "description": "'propose' (the default), 'change', 'show' or 'withdraw'."
            ],
            "chain": [
                "type": "string",
                "description": "On 'propose': the steps, one per line, e.g. \"ask load (A) range 1..400: What load?\", "
                    + "\"lookup factor = Table 98 row {ambient} column Band B rule at_least\", \"cite Rule 4-1\"."
            ],
            "name": [
                "type": "string",
                "description": "On 'propose': what the chain is called."
            ],
            "answers": [
                "type": "string",
                "description": "On 'propose': the question the chain answers, in a sentence."
            ],
            "sources": [
                "type": "array",
                "items": ["type": "string"],
                "description": "On 'propose': for each lookup, in order, the Source line of the retrieved passage "
                    + "it came from, e.g. \"Code Book, page 112, §4-1\"."
            ],
            "step": [
                "type": "integer",
                "description": "On 'change': the step's number as the read-back numbers it."
            ],
            "text": [
                "type": "string",
                "description": "On 'change': the new step as written, with its cite line under it."
            ],
            "source": [
                "type": "string",
                "description": "On 'change': the Source line of the passage a new lookup came from."
            ]
        ],
        "required": [] as [String]
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
        let session = injectedSession ?? FieldSessionService.shared
        guard session.activeSession != nil else {
            return "No active Field Assist session. Start a session before proposing a rule chain."
        }
        let action = (args["action"] as? String)?.lowercased().trimmingCharacters(in: .whitespaces) ?? "propose"
        switch action {
        case "propose", "": return propose(args: args, session: session)
        case "change": return change(args: args, session: session)
        case "show", "status":
            guard let pending = session.pendingProposal else { return "No chain has been proposed on this job." }
            return pending.proposal.readBack
        case "withdraw", "stop", "cancel":
            guard let withdrawn = session.withdrawProposal() else { return "No chain has been proposed on this job." }
            return "Withdrew the proposed chain '\(withdrawn.chain.name)'. Nothing was run or recorded."
        default:
            return "Unknown action '\(action)'. Use 'propose', 'change', 'show' or 'withdraw'."
        }
    }

    private func propose(args: [String: Any], session: FieldSessionService) -> String {
        let text = (args["chain"] as? String) ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Pass 'chain': the steps the retrieved passages say, one per line, in the chain syntax."
        }
        if let running = session.activeChain {
            return "The chain '\(running.chain.name)' is running. Finish or stop it before proposing another."
        }
        let outcome = ChainProposal.make(text: text, name: args["name"] as? String, answers: args["answers"] as? String,
                                         sources: Self.strings(args["sources"]),
                                         context: session.proposalContext(documentStore: documentStore))
        return hold(outcome, session: session)
    }

    private func change(args: [String: Any], session: FieldSessionService) -> String {
        guard let pending = session.pendingProposal else {
            return "No chain has been proposed on this job to change. Propose one first."
        }
        guard let number = PartsRequestTool.integer(args["step"]) else {
            return "Pass 'step': the number of the step to change, as the read-back numbers it."
        }
        let text = (args["text"] as? String) ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Pass 'text': the new step as written, with its cite line under it."
        }
        let outcome = pending.proposal.changing(step: number, to: text, source: args["source"] as? String,
                                                context: session.proposalContext(documentStore: documentStore))
        return hold(outcome, session: session)
    }

    private func hold(_ outcome: Result<ChainProposal, ChainProposal.Refusal>, session: FieldSessionService) -> String {
        switch outcome {
        case .failure(let refusal):
            return "Not proposed: " + refusal.message
        case .success(let proposal):
            do {
                try session.holdProposal(proposal)
            } catch {
                return error.localizedDescription
            }
            return proposal.readBack + "\n"
                + "Read this back to the technician, every step with its rule and passage, and say it is unreviewed. "
                + "Ask whether to run it, change a step, or stop. On go, call rule_chain 'start' with chain "
                + "'\(proposal.chain.name)'. Never run it without their go."
        }
    }

    /// An array of strings, or one string of lines, as models send them.
    static func strings(_ raw: Any?) -> [String] {
        if let array = raw as? [Any] { return array.compactMap { $0 as? String } }
        if let text = raw as? String {
            return text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return []
    }
}
