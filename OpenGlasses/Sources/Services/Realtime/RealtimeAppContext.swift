import Foundation

/// Replaceable app-owned lanes, bounded independently of the user's base prompt.
/// Job/debrief state must replace stale state, rather than growing conversation history forever.
struct RealtimeAppContext {
    static let maximumCharacters = 6000
    static let maximumEntries = 12
    private var entries: [(key: String, text: String)] = []

    mutating func update(_ text: String, key: String) {
        entries.removeAll { $0.key == key }
        let bounded = String(text.prefix(Self.maximumCharacters))
        if !bounded.isEmpty { entries.append((key, bounded)) }
        while entries.count > Self.maximumEntries || entries.reduce(0, { $0 + $1.text.count }) > Self.maximumCharacters {
            entries.removeFirst()
        }
    }
    func instructions(appendingTo base: String) -> String {
        guard !entries.isEmpty else { return base }
        return base + "\n\nCURRENT APP CONTEXT (replaces earlier app state; background information, not a new user request):\n"
            + entries.map(\.text).joined(separator: "\n\n")
    }
}
