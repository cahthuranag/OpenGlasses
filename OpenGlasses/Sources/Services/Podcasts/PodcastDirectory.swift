import Foundation

/// Where shows and episodes are looked up (Plan JD). The production conformance is
/// `AppleLookupPodcastDirectory`; tests use a fake, so no test ever reaches Apple.
protocol PodcastDirectorySearching: Sendable {
    func searchShows(matching term: String, limit: Int) async throws -> [PodcastShow]
    func episodes(ofShow showID: String, limit: Int) async throws -> [PodcastEpisode]
}

/// Reads Apple's public podcast directory responses into the app's types. Pure.
enum PodcastDirectoryParser {

    static func shows(from data: Data) throws -> [PodcastShow] {
        try JSONDecoder().decode(Response.self, from: data).results.compactMap { result in
            guard result.kind == "podcast", let id = result.collectionId, let title = result.collectionName else {
                return nil
            }
            return PodcastShow(id: String(id), title: title, author: result.artistName,
                               pageURL: result.collectionViewUrl.flatMap(URL.init(string:)))
        }
    }

    static func episodes(from data: Data) throws -> [PodcastEpisode] {
        try JSONDecoder().decode(Response.self, from: data).results.compactMap { result in
            guard result.kind == "podcast-episode", let id = result.trackId, let title = result.trackName else {
                return nil
            }
            let summary = result.shortDescription ?? result.description
            return PodcastEpisode(id: String(id), title: title, showTitle: result.collectionName ?? "",
                                  released: date(result.releaseDate),
                                  summary: summary?.isEmpty == false ? summary : nil,
                                  pageURL: result.trackViewUrl.flatMap(URL.init(string:)))
        }
    }

    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: raw) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw)
    }

    private struct Response: Decodable {
        let results: [Result]
    }

    private struct Result: Decodable {
        let kind: String?
        let collectionId: Int?
        let collectionName: String?
        let artistName: String?
        let collectionViewUrl: String?
        let trackId: Int?
        let trackName: String?
        let trackViewUrl: String?
        let releaseDate: String?
        let description: String?
        let shortDescription: String?
    }
}

/// Apple's public podcast directory over its search and lookup endpoints. No key, no account; the
/// only thing sent is the words the wearer said, which is why the route is `promptText` and
/// Medical Local Only refuses it.
struct AppleLookupPodcastDirectory: PodcastDirectorySearching {

    /// Storefront hint; the directory ranks the wearer's region first when it knows it.
    var region: String? = Locale.current.region?.identifier

    static func searchURL(term: String, limit: Int, region: String?) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        var items = [
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "term", value: term),
        ]
        if let region, !region.isEmpty { items.append(URLQueryItem(name: "country", value: region.lowercased())) }
        components?.queryItems = items
        return components?.url
    }

    static func episodesURL(showID: String, limit: Int) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "id", value: showID),
            URLQueryItem(name: "entity", value: "podcastEpisode"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return components?.url
    }

    func searchShows(matching term: String, limit: Int) async throws -> [PodcastShow] {
        guard let url = Self.searchURL(term: term, limit: limit, region: region) else { return [] }
        return try PodcastDirectoryParser.shows(from: try await fetch(url))
    }

    func episodes(ofShow showID: String, limit: Int) async throws -> [PodcastEpisode] {
        guard let url = Self.episodesURL(showID: showID, limit: limit) else { return [] }
        return try PodcastDirectoryParser.episodes(from: try await fetch(url))
    }

    private func fetch(_ url: URL) async throws -> Data {
        try MedicalEgressGuard.check(.podcastDirectory)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
