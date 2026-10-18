import Foundation

/// Turns "the latest episode of The Daily", "99% Invisible podcast" or "an episode of Serial about
/// the trial" into a show name and an episode hint (Plan JE). Pure.
///
/// The model usually passes the show alone in `query` and the hint in `episode`; the parser also
/// copes with the whole spoken phrase landing in `query`, because that is what happens.
enum PodcastRequestParser {

    /// Longest first, so "the latest episode of …" is not cut at "the latest ".
    private static let latestLeads = [
        "the most recent episode of ", "the latest episode of ", "the newest episode of ",
        "the new episode of ", "most recent episode of ", "latest episode of ", "newest episode of ",
        "the most recent ", "the latest ", "the newest ", "latest ", "newest ",
    ]

    private static let fillerLeads = ["play ", "put on ", "listen to ", "open ", "start "]

    private static let episodeLeads = ["an episode of ", "the episode of ", "episode of ", "episodes of ", "some "]

    private static let fillerTails = [" podcast episode", " podcast episodes", " podcast", " podcasts"]

    static func parse(query: String, episode: String? = nil) -> PodcastRequest? {
        var text = MusicRequestParser.spokenForm(query)
        var episodeHint = PodcastEpisodeHint.unspecified
        if let episode, let fromArgument = hint(fromArgument: episode) { episodeHint = fromArgument }

        text = stripping(fillerLeads, from: text)
        if let rest = dropping(latestLeads, from: text) {
            text = rest
            episodeHint = .latest
        }
        text = stripping(episodeLeads, from: text)

        if case .unspecified = episodeHint, let range = text.range(of: " about ", options: .backwards) {
            let head = text[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let tail = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !head.isEmpty, !tail.isEmpty {
                text = head
                episodeHint = .about(tail)
            }
        }

        for tail in fillerTails where text.hasSuffix(tail) {
            text = String(text.dropLast(tail.count))
            break
        }
        text = stripping(["the podcast "], from: text).trimmingCharacters(in: .whitespaces)

        guard !text.isEmpty, !["a", "the", "some", "any", "podcast", "a podcast", "podcasts", "the podcast"].contains(text) else {
            return nil
        }
        return PodcastRequest(show: text, episode: episodeHint)
    }

    /// The `episode` argument as the model passes it: "latest" or words from the episode.
    static func hint(fromArgument raw: String) -> PodcastEpisodeHint? {
        let value = MusicRequestParser.normalizedWords(raw)
        guard !value.isEmpty else { return nil }
        let latest: Set<String> = [
            "latest", "newest", "new", "recent", "most recent", "the latest", "the newest",
            "latest episode", "newest episode", "the latest episode", "the newest episode", "most recent episode",
        ]
        return latest.contains(value) ? .latest : .about(value)
    }

    private static func stripping(_ leads: [String], from text: String) -> String {
        dropping(leads, from: text) ?? text
    }

    /// Nil when no lead matches; otherwise what follows it, which may be empty ("the latest
    /// episode of" with nothing after it is consumed, not left as a show called "episode of").
    private static func dropping(_ leads: [String], from text: String) -> String? {
        let padded = text + " "
        for lead in leads where padded.hasPrefix(lead) {
            return String(padded.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
