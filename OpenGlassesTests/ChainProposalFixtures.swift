import Foundation
@testable import OpenGlasses

/// Plan JJ P3's invented proposal: a conductor sized for a load, over the invented tables of P2's
/// test vault (Tables 90, 98 and 99), with an ambient the model assumed rather than asked for, so
/// "ask me the ambient instead" has a step to change. The passages it cites are invented too —
/// invented rule numbers ("Rule QR-12") over invented sentences in an invented book. Nothing here
/// is a fact from any book.
enum ChainProposalFixtures {

    static let book = "Invented Book A"
    static let name = "Size a conductor, ambient assumed"
    static let answers = "which conductor carries a load at an assumed ambient, once corrected for grouping."

    /// The steps as the model would send them, one per line.
    static let steps = """
    ask load (A) range 1..400: What load will the circuit carry, in amps?
    calc ambient (°C) = 17
    ask conductors (conductors) range 1..9: How many current-carrying conductors share the run?
    ask group range 1..3: Which rating group is the installation method in?
    lookup band = Table 90 row {conductors} column Band rule exact
    cite Rule QR-12
    lookup factor = Table 98 row {ambient} column Rating group {group} › {band} rule at_least
    cite Rule QR-14
    calc corrected (A) = load / factor
    lookup size = Table 99 column Rating group {group} cell {corrected} rule at_least
    cite Rule QR-17
    say "Use {size.row}: rated {size} A in rating group {group}, against {corrected} A."
    """

    /// The Source line of the passage each lookup came from, in order.
    static let sources = [
        "\(book), page 6, §QR-12",
        "Source: \(book), page 7, §QR-14",
        "\(book), page 8, §QR-17",
    ]

    /// The step "ask me the ambient instead" puts in place of the assumed one (step 2).
    static let askAmbient = "ask ambient (°C) range 0..40: What is the ambient temperature along the run?"

    /// Three invented passages, as `manual_lookup` would have retrieved them on the job.
    static let passages: [ChainProposal.Passage] = [
        .init(documentName: book, page: 6, section: "QR-12",
              text: "Rule QR-12 Invented example: the band for a number of grouped conductors is read from Table 90."),
        .init(documentName: book, page: 7, section: "QR-14",
              text: "Rule QR-14 Invented example: the factor for the ambient is read from Table 98, by rating group and band."),
        .init(documentName: book, page: 8, section: "QR-17",
              text: "Rule QR-17 Invented example: the conductor is the first in Table 99 rated at least the corrected load."),
    ]

    /// The same passages as `VaultRetriever` returns them, for a session's source memory.
    static func retrieved(documentId: String) -> [VaultRetriever.Passage] {
        passages.enumerated().map { index, passage in
            VaultRetriever.Passage(documentId: documentId, documentName: passage.documentName, chunkIndex: 900 + index,
                                   text: passage.text, page: passage.page, section: passage.section,
                                   similarity: 0.8, score: 0.8, matchedTokens: [])
        }
    }

    static let tableLabels = ["Table 99", "Table 98", "Table 97", "Table 90", "Table 92"]

    static var context: ChainProposal.Context {
        .init(passages: passages, tableLabels: tableLabels, takenNames: ["Size a conductor for a load"])
    }
}
