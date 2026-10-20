import Foundation

/// Reads one cell of a table extracted from the vault's own loaded manuals or code books (Plan JJ
/// P1): by table, row and column, with the cell's headers, units, notes and printed page, and a
/// `Source:` line that opens the table's page. Resolution is [[TableLookup]]'s, which never
/// interpolates, rounds, or picks a neighbouring row, and asks when the words fit more than one.
@MainActor
final class TableLookupTool: NativeTool {
    let name = "table_lookup"
    let description = """
    Read one value from a table printed in the manuals or code books loaded into the active Field \
    Assist vault: the cell at a row and a column, with its row and column headings, units, the \
    notes it refers to, and the page it is printed on. Pass 'table' (its number as printed, e.g. \
    "Table 99", or words of its title), 'row' (the row's heading, e.g. a size, a type or a range, \
    or a number to find), and 'column' (the column's heading, e.g. "Rating group 2" or a path such \
    as "Rating group 2 › Band B"); leave 'column' out to read the whole row. Pass 'document' when \
    the technician names the book. If the number asked for falls between two rows it returns both \
    rows and says so: say both, and never interpolate, round, or pick the next row yourself. If it \
    asks which row, column, table or book, ask the technician. Read the value out as printed with \
    its row, column and page, and repeat the Source line. Requires an active session in a vault \
    that has manuals.
    """
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "table": [
                "type": "string",
                "description": "The table: its number as printed (\"Table 99\") or words of its title."
            ],
            "row": [
                "type": "string",
                "description": "The row: its heading as printed, a number to find, or words of the heading."
            ],
            "column": [
                "type": "string",
                "description": "Optional: the column heading, or a path of headings separated by ›. Leave out to read the whole row."
            ],
            "document": [
                "type": "string",
                "description": "Optional: the manual or code book the technician named, by title or part of it."
            ]
        ],
        "required": ["table", "row"]
    ]

    private let documentStore: DocumentStore?
    private let injectedSession: FieldSessionService?
    /// The technician's words this turn, for the edition a lookup reads (Plan IV P2).
    private let currentUtterance: @MainActor () -> String?

    init(documentStore: DocumentStore?, sessionService: FieldSessionService? = nil,
         currentUtterance: @escaping @MainActor () -> String? = { TechnicianWords.current() }) {
        self.documentStore = documentStore
        self.injectedSession = sessionService
        self.currentUtterance = currentUtterance
    }

    func execute(args: [String: Any]) async throws -> String {
        guard Config.fieldAssistActive else {
            return "Field Assist is disabled. Enable it in Settings → Field Assist."
        }
        let session = injectedSession ?? FieldSessionService.shared
        guard let store = session.activeVault else {
            return "No active Field Assist session. Start a session to look up a table in its manuals."
        }
        guard let documentStore else { return "Table lookup is unavailable in this context." }
        let table = (args["table"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let row = (args["row"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !table.isEmpty, !row.isEmpty else {
            return "Say which table ('table') and which row ('row') to read, and the column when the table has several."
        }
        let column = (args["column"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let document = (args["document"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let sources = Self.sources(store: store, session: session, documentStore: documentStore,
                                   namedDocument: document?.isEmpty == false,
                                   said: [table, row, column, document, currentUtterance()].compactMap { $0 }.joined(separator: " "))
        let outcome = TableLookup.resolve(.init(table: table, row: row, column: column?.isEmpty == true ? nil : column,
                                                document: document), in: sources)
        noteForShowing(outcome, session: session, documentStore: documentStore)
        return TableLookup.render(outcome)
    }

    /// The vault's tables a lookup may read: its manuals' (never a team learning's, which has
    /// none), in documents still in the vault, of the newest edition unless the technician's words
    /// reach past it or a document is named.
    static func sources(store: VaultStore, session: FieldSessionService, documentStore: DocumentStore,
                        namedDocument: Bool, said: String) -> [TableLookup.Source] {
        let vaultId = store.manifest.id
        let available = VaultManualRemoval.availabilityCheck(forVault: vaultId, documentStore: documentStore,
                                                             capturedCatalog: session.capturedManuals)
        var stored = documentStore.storedTables(namespace: DocumentStore.vaultNamespace(vaultId))
            .filter { available($0.documentId) }
        let editions = session.documentEditions(of: store)
        if !namedDocument,
           let titles = editions.searchableTitles(for: EditionRequest.parse(said, editions: editions),
                                                  among: Array(Set(stored.map(\.documentName)))) {
            stored = stored.filter { titles.contains($0.documentName) }
        }
        return stored.map { TableLookup.Source(documentId: $0.documentId, documentName: $0.documentName, table: $0.table) }
    }

    /// The stored row passages of the rows a set of lookups read, for "show me the table" to mark —
    /// a `rule_chain`'s lookups note theirs the same way (Plan JJ P2).
    static func rowPassages(for founds: [TableLookup.Found], documentStore: DocumentStore) -> [AnswerSourceMemory.Retrieved] {
        var out: [AnswerSourceMemory.Retrieved] = []
        for found in founds {
            let table = found.source.table
            let wanted = Set(found.rows.compactMap { TableRowPassage.sentence(for: $0, in: table) })
            out += documentStore.passages(figure: table.label, documentIds: [found.source.documentId], limit: Int.max)
                .filter { $0.kind == .tableRow && wanted.contains($0.text) }
                .map {
                    AnswerSourceMemory.Retrieved(documentId: $0.documentId, documentName: $0.documentName,
                                                 chunkIndex: $0.chunkIndex, page: $0.page, section: $0.section, text: $0.text)
                }
        }
        return out
    }

    /// What "show me the table" opens next: the cited pages, each marking the row it was read from.
    private func noteForShowing(_ outcome: TableLookup.Outcome, session: FieldSessionService,
                                documentStore: DocumentStore) {
        let sessionId = session.activeSession?.id
        switch outcome {
        case .found(let found):
            let table = found.source.table
            session.sourceCenter.noteTableLookup(
                rows: Self.rowPassages(for: [found], documentStore: documentStore),
                citations: TableLookup.citations(documentName: found.source.documentName, label: table.label,
                                                 pages: TableLookup.pages(of: found)),
                sessionId: sessionId)
        case .notExtracted(let source):
            session.sourceCenter.noteTableLookup(
                rows: [],
                citations: TableLookup.citations(documentName: source.documentName, label: source.table.label,
                                                 pages: [source.table.page]),
                sessionId: sessionId)
        case .ambiguous, .notFound, .noTables:
            break
        }
    }
}
