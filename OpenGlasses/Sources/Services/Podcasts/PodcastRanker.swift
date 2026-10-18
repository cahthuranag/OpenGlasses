import Foundation

/// Picks the show and the episode the wearer meant from what the directory returned (Plan JD).
/// Pure.
enum PodcastRanker {

    /// An exact title (ignoring case, accents, a leading "the" and a trailing "podcast") beats the
    /// directory's own first result; otherwise the directory's ranking stands.
    static func bestShow(for request: PodcastRequest, in shows: [PodcastShow]) -> PodcastShow? {
        guard !shows.isEmpty else { return nil }
        let want = key(request.show)
        return shows.first { key($0.title) == want } ?? shows.first
    }

    struct EpisodePick: Equatable {
        let episode: PodcastEpisode
        /// False when the wearer named a topic and no episode matched it, so the newest was used.
        let matchedTopic: Bool
    }

    /// Newest first for "latest" and for nothing said; for "about …", the newest episode whose
    /// title or notes carry every word of the topic, then any word, then the newest with a flag.
    static func pickEpisode(_ hint: PodcastEpisodeHint, from episodes: [PodcastEpisode]) -> EpisodePick? {
        let newestFirst = episodes.sorted { ($0.released ?? .distantPast) > ($1.released ?? .distantPast) }
        guard let newest = newestFirst.first else { return nil }
        switch hint {
        case .unspecified, .latest:
            return EpisodePick(episode: newest, matchedTopic: true)
        case .about(let topic):
            let words = MusicRequestParser.normalizedWords(topic)
                .split(separator: " ").map(String.init)
                .filter { $0.count > 2 && !stopWords.contains($0) }
            guard !words.isEmpty else { return EpisodePick(episode: newest, matchedTopic: false) }
            if let every = newestFirst.first(where: { episode in
                let text = searchText(episode)
                return words.allSatisfy { text.contains($0) }
            }) {
                return EpisodePick(episode: every, matchedTopic: true)
            }
            if let any = newestFirst.first(where: { episode in
                let text = searchText(episode)
                return words.contains { text.contains($0) }
            }) {
                return EpisodePick(episode: any, matchedTopic: true)
            }
            return EpisodePick(episode: newest, matchedTopic: false)
        }
    }

    private static let stopWords: Set<String> = ["the", "and", "with", "about", "episode", "one", "that", "this"]

    private static func searchText(_ episode: PodcastEpisode) -> String {
        " " + MusicRequestParser.normalizedWords(episode.title + " " + (episode.summary ?? "")) + " "
    }

    private static func key(_ title: String) -> String {
        var key = MusicRequestParser.normalizedWords(title)
        for lead in ["the ", "a "] where key.hasPrefix(lead) {
            key = String(key.dropFirst(lead.count))
            break
        }
        if key.hasSuffix(" podcast") { key = String(key.dropLast(" podcast".count)) }
        return key
    }
}
