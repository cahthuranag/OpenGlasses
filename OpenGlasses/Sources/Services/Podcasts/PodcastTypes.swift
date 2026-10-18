import Foundation

// Plan JE — value types for playing a podcast by name. Pure: nothing here touches the network or
// the Podcasts app.

/// A show as Apple's public podcast directory lists it.
struct PodcastShow: Equatable, Sendable {
    let id: String
    let title: String
    let author: String?
    /// The show's page on podcasts.apple.com — the Podcasts app claims it as a universal link.
    let pageURL: URL?
}

/// One episode of a show.
struct PodcastEpisode: Equatable, Sendable {
    let id: String
    let title: String
    let showTitle: String
    let released: Date?
    let summary: String?
    /// The episode's page on podcasts.apple.com.
    let pageURL: URL?
}

/// Which episode the wearer meant.
enum PodcastEpisodeHint: Equatable, Sendable {
    /// Nothing said: the newest episode.
    case unspecified
    /// "the latest episode of …"
    case latest
    /// "an episode of … about …"
    case about(String)
}

/// What the wearer asked for, once the filler words are gone.
struct PodcastRequest: Equatable, Sendable {
    var show: String
    var episode: PodcastEpisodeHint = .unspecified
}

/// Keeps the app from opening anything but a podcasts.apple.com page: the directory's JSON is
/// data from the web, and a URL in it is only handed to the system when it is the one kind of
/// link the Podcasts app claims.
enum PodcastDeepLink {
    static let host = "podcasts.apple.com"

    static func openable(_ url: URL?) -> URL? {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == host else { return nil }
        return url
    }
}
