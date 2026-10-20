import Foundation

/// A chain the model proposed on a job, that ran to a result and that the technician kept on this
/// phone (Plan JJ P3). Unreviewed: nobody but the technician who ran it has seen it. It is offered
/// in `rule_chain list` on this phone only, marked so, and runs like any other chain.
struct KeptChain: Codable, Equatable {
    /// The chain's name, as its heading writes it.
    let name: String
    /// The chain as `chains.md` writes it: its heading, `Answers:` line and fenced steps. Read
    /// back through `ChainParser`, the same parser an authored chain goes through.
    let markdown: String
    /// The passage each lookup came from, by the lookup's value name, as the proposal gave it.
    let sources: [String: String]
    let keptAt: Date
    /// The job it was worked out on, when it had a number.
    let jobReference: String?

    init(chain: ChainDefinition, sources: [String: String], keptAt: Date, jobReference: String?) {
        self.name = chain.name
        self.markdown = KeptChains.markdown(chain)
        self.sources = sources
        self.keptAt = keptAt
        self.jobReference = jobReference
    }

    /// The chain, read back. Nil only when the stored text no longer reads, which a phone that
    /// wrote it itself never produces.
    var chain: ChainDefinition? {
        let parsed = ChainParser.parse(markdown)
        return parsed.problems.isEmpty ? parsed.chains.first : nil
    }
}

/// The kept chains of one vault, in the vault's own folder on this phone beside the authored
/// `chains.md` (Plan JJ P3).
///
/// The file is `_kept_chains.json` in the vault's overlay, the folder a vault update leaves alone,
/// so a kept chain survives the organisation pushing a new version of the vault. It is not a
/// manifest file: it is never read into the prompt, never part of an export, pack or link, and goes
/// with the vault when the vault is removed. A chain the organisation adds to `chains.md` under the
/// same name supersedes the kept one, which is then no longer offered.
enum KeptChains {

    static let fileName = "_kept_chains.json"

    private struct File: Codable {
        var version = 1
        var chains: [KeptChain]
    }

    /// The vault's kept chains, oldest first. Empty when there are none or the file does not read.
    static func read(store: VaultStore) -> [KeptChain] {
        guard let text = store.read(fileName), let data = text.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(File.self, from: data))?.chains ?? []
    }

    static func write(_ chains: [KeptChain], store: VaultStore) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(File(chains: chains))
        try store.write(fileName, contents: String(decoding: data, as: UTF8.self))
    }

    /// `chain` kept beside `existing`: a kept chain of the same name is replaced, so keeping a
    /// chain again after changing it keeps the new one.
    static func keeping(_ chain: KeptChain, in existing: [KeptChain]) -> [KeptChain] {
        existing.filter { $0.name.caseInsensitiveCompare(chain.name) != .orderedSame } + [chain]
    }

    /// The kept chains still offered: those that read, and that no authored chain of the same
    /// name has superseded.
    static func offered(_ kept: [KeptChain], authored: [ChainDefinition]) -> [KeptChain] {
        kept.filter { chain in
            chain.chain != nil
                && !authored.contains { $0.name.caseInsensitiveCompare(chain.name) == .orderedSame }
        }
    }

    /// One chain as `chains.md` writes it, with an `Answers:` line always, so a line of prose added
    /// under the heading is never read as what it answers.
    static func markdown(_ chain: ChainDefinition, notes: [String] = []) -> String {
        var lines = ["## \(chain.name)", "Answers: \(chain.answers.isEmpty ? chain.name : chain.answers)"]
        lines += notes
        lines.append("")
        lines.append("```chain")
        for step in chain.steps {
            lines.append(ChainParser.text(of: step.kind))
            lines += step.citations.map { "cite \($0)" }
        }
        lines.append("```")
        return lines.joined(separator: "\n")
    }

    /// The kept chains as a `chains.md` fragment an organisation can review and paste into its
    /// vault's `chains.md` by hand: a title, a paragraph saying what they are, and each chain with
    /// a line saying where it came from and the passages its lookups were read from. The parser
    /// reads the paragraph and those lines as prose, so the fragment is a valid `chains.md`.
    static func fragment(_ kept: [KeptChain]) -> String {
        var blocks = ["# Rule chains kept on a phone (unreviewed)",
                      "Each chain below was proposed by the assistant on a job, built from the passages it retrieved "
                        + "from your loaded books, run to a result and kept on one phone. Nobody has reviewed them. "
                        + "Check every step, table and rule against your own book before adding one to your vault's "
                        + "chains.md. A chain in chains.md with the same name replaces the kept one on the phone."]
        for chain in kept {
            guard let definition = chain.chain else { continue }
            var notes = ["Unreviewed — kept on a phone on \(day(chain.keptAt))"
                         + (chain.jobReference.map { ", worked out on job \($0)" } ?? "") + "."]
            let lookups = ChainProposal.lookupNames(definition).compactMap { name in
                chain.sources[name].map { "\(name) from \($0)" }
            }
            if !lookups.isEmpty { notes.append("Read from: " + lookups.joined(separator: "; ") + ".") }
            blocks.append(markdown(definition, notes: notes))
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    private static func day(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}

/// The kept chains of one vault on their way off the phone as a `chains.md` fragment (Plan JJ P3):
/// by the share sheet, so an organisation with no office can paste it into its vault by hand. It
/// belongs to no job.
struct RuleChainShare: Equatable {
    /// What a delivery of kept chains is filed under: no job's.
    static let queueSessionID = "rule-chains"
    static let fileName = "chains.md"

    let vaultId: String
    let vaultName: String
    let names: [String]
    let fragment: String

    init?(vaultId: String, vaultName: String, kept: [KeptChain]) {
        let readable = kept.filter { $0.chain != nil }
        guard !readable.isEmpty else { return nil }
        self.vaultId = vaultId
        self.vaultName = vaultName
        self.names = readable.map(\.name)
        self.fragment = KeptChains.fragment(readable)
    }

    private var count: String { names.count == 1 ? "1 rule chain" : "\(names.count) rule chains" }

    var subject: String { "Rule chains kept on a phone, unreviewed — \(vaultName)" }

    var body: String {
        "\(count) kept on a phone for \(vaultName), unreviewed: \(names.joined(separator: "; ")).\n\n"
            + "Review each against your own book, then paste it into the vault's chains.md. "
            + "The attached chains.md holds them as written:\n\n" + fragment
    }

    var shortBody: String {
        "\(count) kept on a phone for \(vaultName), unreviewed: \(names.joined(separator: "; ")). Review before adding to chains.md."
    }
}
