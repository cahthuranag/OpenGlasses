import SwiftUI

/// A manual's detected language, and — while its script's search model has not downloaded — that
/// it is searched by its words (Plan JY P1). Shown under a manual wherever its indexing state is:
/// My Manuals and the Custom Vaults list.
struct ManualLanguageLine: View {
    let diagnostic: DocumentStore.LanguageDiagnostic?

    var body: some View {
        if let diagnostic {
            VStack(alignment: .leading, spacing: 2) {
                if let name = Self.languageName(diagnostic.profile.language) {
                    Text("Language: \(name)")
                }
                if diagnostic.searchesByWords {
                    Text("Searching by words until the language model downloads")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    /// The language's name in the interface's own language ("Chinese, Simplified", "Ukrainian"),
    /// from the system, or nil when no language was settled.
    nonisolated static func languageName(_ code: String?, locale: Locale = .current) -> String? {
        guard let code, !code.isEmpty else { return nil }
        return locale.localizedString(forIdentifier: code) ?? locale.localizedString(forLanguageCode: code)
    }
}
