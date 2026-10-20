import Foundation

// The app types the chain and table sources reach that a command-line check does not need: the
// tool protocol `UnitConversionTool` conforms to, the vault store `VaultChains` can read from, the
// citation a lookup hands to the chips, and the document-name matcher a lookup by book uses.

protocol NativeTool {
    var name: String { get }
    var description: String { get }
    var parametersSchema: [String: Any] { get }
    func execute(args: [String: Any]) async throws -> String
}

final class VaultStore {
    struct Manifest { let files: [String] }
    let manifest = Manifest(files: [])
    func read(_ name: String) -> String? { nil }
}

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
