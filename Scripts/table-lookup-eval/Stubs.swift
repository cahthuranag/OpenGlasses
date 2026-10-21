import Foundation

// The app types the table lookup reaches that a command-line score does not need: the citation a
// lookup hands to the chips, and the document-name matcher a lookup by book uses.

struct Citation: Equatable {
    enum Kind { case manual }
    let kind: Kind
    let title: String
    let page: Int?
    let figure: String?

    init(kind: Kind, title: String, page: Int? = nil, figure: String? = nil) {
        self.kind = kind
        self.title = title
        self.page = page
        self.figure = figure
    }
}

enum ManualDocumentChoice {
    static func matches(_ name: String, requested: String) -> Bool {
        name.localizedCaseInsensitiveContains(requested)
    }
}
