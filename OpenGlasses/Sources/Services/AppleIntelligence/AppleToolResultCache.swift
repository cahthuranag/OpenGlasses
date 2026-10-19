import Foundation

/// The tool results of one on-device turn, replayed rather than re-run when the turn's session is
/// rebuilt.
///
/// A window the model reports as full is recovered by building a fresh session with less of the
/// conversation carried (`AppleSessionPolicy`), and the fresh session asks for the same tools
/// again. Without this, every rebuild re-executed them: a field report showed "open a new job"
/// run three times in one turn, the first opening the job and the next two reporting it already
/// open. The first result for a call is the result for that call for the rest of the turn, the
/// way a cloud tool loop never runs the same call twice.
///
/// Keyed by tool name and the arguments' canonical JSON (keys sorted), so a retry that writes the
/// same arguments in another order is the same call. Errors are replayed too: a refused approval
/// stays refused rather than asking the wearer again. `clear()` ends the turn.
///
/// Pure apart from the closure it is handed; no Foundation Models import, so the replay is
/// asserted headlessly.
@MainActor
final class AppleToolResultCache {

    private var results: [String: String] = [:]
    /// Calls answered from the cache this turn, for the privacy log.
    private(set) var replays = 0

    /// The cached result for this call, or the result of running `execute` once and remembering it.
    func resolve(name: String, argumentsJSON: String,
                 execute: () async -> String) async -> String {
        let key = Self.key(name: name, argumentsJSON: argumentsJSON)
        if let cached = results[key] {
            replays += 1
            return cached
        }
        let result = await execute()
        results[key] = result
        return result
    }

    /// Forget the turn's results.
    func clear() {
        results.removeAll()
        replays = 0
    }

    var isEmpty: Bool { results.isEmpty }

    /// `name` plus the arguments as canonical JSON. Text that does not parse as JSON keys as
    /// itself — still the same call when the model writes it the same way.
    nonisolated static func key(name: String, argumentsJSON: String) -> String {
        name + "\u{1F}" + canonicalJSON(argumentsJSON)
    }

    nonisolated static func canonicalJSON(_ json: String) -> String {
        // Anything the parser produced is something the writer can write back, so the second step
        // cannot raise.
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let canonical = try? JSONSerialization.data(withJSONObject: object,
                                                          options: [.sortedKeys, .fragmentsAllowed]),
              let text = String(data: canonical, encoding: .utf8) else {
            return json.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
