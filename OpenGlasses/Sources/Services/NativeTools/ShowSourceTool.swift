import Foundation
import PDFKit

/// Opens the page an answer cited, with the cited passage highlighted (Plan IN P2).
///
/// Resolves against the citations of the most recent answer, by document and page — never by
/// searching every manual for a page number, which is how "show me the page" used to open page 34
/// of the wrong book with two loaded (decision 2). A tool rather than turn classification, so it
/// works the same in Direct, Gemini Live and OpenAI Realtime.
@MainActor
final class ShowSourceTool: NativeTool {
    let name = "show_source"
    let description = """
    Open the manual or code-book page your last answer cited, on the technician's phone, with the \
    cited passage highlighted. Call it when the technician says "show me the page", "show me the \
    relevant pages", "show me clause 3.9.4", "show me the table", "show me the second one" or \
    "where does it say that". Pass 'which': "first" (the default), "second", "last", "all" for \
    every cited page as one paged sheet, a clause number as printed, "table" for the table the \
    answer cited (its row highlighted), or a table number such as "Table 99". Pass 'document' \
    when the technician names the book. It opens only what the last answer cited, so search with \
    manual_lookup or table_lookup and answer first. If it reports that the phone is locked, tell the technician "It's on your phone." and \
    do not say the page is showing. Uses your loaded manuals, or the active Field Assist session. In a personal library, name the manual when several are loaded; camera lookup requires Field Assist.
    """
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "which": [
                "type": "string",
                "description": "Which cited source: \"first\", \"second\", \"third\", \"last\", \"all\", a clause number such as \"3.9.4\", \"table\", or a table number such as \"Table 99\"."
            ],
            "document": [
                "type": "string",
                "description": "Optional: the manual or code book the technician named, by title or part of it."
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
        if !Config.fieldAssistActive {
            return PersonalManualLibrary.shared.show(args, documentStore: documentStore)
        }
        guard Config.fieldAssistActive else {
            return "Field Assist is disabled. Enable it in Settings → Field Assist."
        }
        let session = injectedSession ?? FieldSessionService.shared
        guard let store = session.activeVault else {
            return "No active Field Assist session. Start a session to show a page from its manuals."
        }
        guard VaultRegistry.shared.isUnlocked(store.manifest) else { return MyManualsPaywallCopy.locked }
        let center = session.sourceCenter
        let which = args["which"] as? String
        let document = args["document"] as? String
        let sources: [ShowSourceResolver.Source]
        switch ShowSourceResolver.resolve(which: which, document: document, memory: center.memory) {
        case .problem(let sentence): return sentence
        case .sources(let found): sources = found
        }

        var pages: [FieldSessionService.StagedFigure] = []
        var unavailable: [String] = []
        for source in sources {
            guard case .figure(var staged) = session.resolveCitation(source.citation) else {
                unavailable.append(source.citation.label)
                continue
            }
            // Asked for by the technician: that is the only reason this tool runs.
            staged.origin = .requested
            staged.presentOnPhone = true
            staged.citedPassages = center.citedPassages(for: source.citation, documentId: staged.documentId,
                                                        store: documentStore, number: source.number)
            staged.pictureAreas = center.pictureAreas(for: source.citation)
            session.logCitationOpened(source.citation, origin: .voice)
            pages.append(staged)
        }
        guard let first = pages.first else {
            return "The cited manual is no longer in this vault (" + unavailable.joined(separator: "; ")
                + "), so there is no page to show. Nothing was opened."
        }

        let checked = pages.map { markState(of: $0, session: session) }
        let rows = checked.reduce(into: RowMarks()) { $0.marked += $1.rows.marked; $0.unmarked += $1.rows.unmarked }
        let onScreen = center.present(pages, notice: ShowSourceCenter.noticeText(for: first.asCitation))
        return Self.reply(pages: pages, marks: checked.map(\.state), rows: rows, onScreen: onScreen,
                          unavailable: unavailable)
    }

    /// The table rows the marks came to, by row heading (Plan JW P0), so the reply names exactly
    /// the rows on the page — the partner heard "both rows are highlighted" over a page that showed
    /// neither.
    struct RowMarks: Equatable {
        var marked: [String] = []
        var unmarked: [String] = []
        var isEmpty: Bool { marked.isEmpty && unmarked.isEmpty }
    }

    /// Whether the cited passages could be marked on a staged page, so the reply never claims a
    /// highlight the sheet will not draw.
    enum MarkState: Equatable {
        case marked
        case unmarked
        /// No passage to mark — the page opens plain, and the reply says nothing about marking.
        case noPassage
        /// A table read from a picture: the region it was read from is outlined (Plan JN P2).
        case outlined
    }

    private func markState(of staged: FieldSessionService.StagedFigure,
                           session: FieldSessionService) -> (state: MarkState, rows: RowMarks) {
        guard !staged.citedPassages.isEmpty else {
            return (staged.pictureAreas.contains { $0.physical == staged.page } ? .outlined : .noPassage, RowMarks())
        }
        var pageText: String?
        if let url = session.sourcePDFURL(for: staged), let document = PDFDocument(url: url),
           staged.page >= 1, staged.page <= document.pageCount {
            pageText = document.page(at: staged.page - 1)?.string
        } else {
            pageText = documentStore?.pageTexts(documentId: staged.documentId)
                .first { $0.page == staged.page }?.text
        }
        let marks = PassageMarks(passages: staged.citedPassages, page: staged.page, pageText: pageText)
        return (marks.located.isEmpty ? .unmarked : .marked,
                Self.rowMarks(staged.citedPassages, page: staged.page, pageText: pageText))
    }

    /// Which of the cited table rows on `page` are found on its text, by heading; passages that are
    /// not a table's rows are left to the generic line. Pure.
    static func rowMarks(_ passages: [CitedPassage], page: Int, pageText: String?) -> RowMarks {
        var rows = RowMarks()
        for passage in passages where passage.anchor.page == page {
            guard let name = TableRowPassage.rowName(ofSentence: passage.anchor.text) else { continue }
            if PassageLocator.locate(passage.anchor, onPageText: pageText).ranges.isEmpty {
                if !rows.unmarked.contains(name) { rows.unmarked.append(name) }
            } else if !rows.marked.contains(name) {
                rows.marked.append(name)
            }
        }
        return rows
    }

    /// What the model is told. Pure.
    static func reply(pages: [FieldSessionService.StagedFigure], marks: [MarkState], rows: RowMarks = RowMarks(),
                      onScreen: Bool, unavailable: [String]) -> String {
        var lines: [String] = []
        let labels = pages.map(\.citation)
        if onScreen {
            lines.append(pages.count == 1
                ? "Showing \(labels[0]) on the technician's phone."
                : "Showing \(pages.count) pages on the technician's phone, in the order you cited them: "
                    + labels.joined(separator: "; ") + ".")
        } else {
            lines.append("The phone is locked or the app is in the background, so the page is not on screen yet. "
                + "A notification says where it is, and it opens when the technician unlocks the phone. "
                + "Tell the technician \"It's on your phone.\" Do not say the page is showing.")
        }
        if !rows.isEmpty {
            // Table rows are named, so nothing is claimed beyond what the page shows.
            if !rows.marked.isEmpty {
                lines.append("Marked on the page: " + rows.marked.map { "row \($0)" }.joined(separator: "; ") + ".")
            }
            if !rows.unmarked.isEmpty {
                lines.append("Could not be marked: " + rows.unmarked.map { "row \($0)" }.joined(separator: "; ")
                    + ". Do not say \(rows.unmarked.count == 1 ? "it is" : "they are") highlighted; read the value aloud if asked.")
            }
            if rows.marked.isEmpty {
                lines.append("No row is highlighted on the page.")
            } else {
                lines.append("Say only that \(rows.marked.count == 1 ? "this row is" : "these rows are") highlighted.")
            }
        } else if marks.contains(.marked) {
            lines.append(marks.contains(.unmarked)
                ? "The cited passage is highlighted where it was found; on the other pages it couldn't be marked, so read the clause aloud if asked."
                : "The cited passage is highlighted on the page.")
        } else if marks.contains(.unmarked) {
            lines.append("The passage couldn't be marked on the page, so the page opens without a highlight.")
        }
        if marks.contains(.outlined) {
            lines.append("The table on that page was read from a picture, so the region it was read from is outlined "
                + "instead of a highlighted row: ask the technician to check the value against the page.")
        }
        if !unavailable.isEmpty {
            lines.append("Not opened, because the manual is no longer in this vault: " + unavailable.joined(separator: "; ") + ".")
        }
        return lines.joined(separator: " ")
    }
}
