import XCTest
@testable import OpenGlasses

/// Plan JE — the directory's JSON becomes shows and episodes, and only podcasts.apple.com pages
/// are ever openable. Every id, title and name in the fixtures is invented.
final class PodcastDirectoryParserTests: XCTestCase {

    private let searchFixture = """
    {"resultCount": 2, "results": [
      {"wrapperType": "track", "kind": "podcast", "collectionId": 100200300,
       "collectionName": "The Morning Ledger", "artistName": "Harbourline Audio",
       "collectionViewUrl": "https://podcasts.apple.com/nz/podcast/the-morning-ledger/id100200300?uo=4",
       "feedUrl": "https://example.invalid/feed.xml"},
      {"wrapperType": "track", "kind": "podcast", "collectionId": 100200301,
       "collectionName": "Ledger Lines", "collectionViewUrl": "https://podcasts.apple.com/nz/podcast/ledger-lines/id100200301"},
      {"wrapperType": "track", "kind": "song", "collectionId": 5, "collectionName": "Not a podcast"}
    ]}
    """

    private let lookupFixture = """
    {"resultCount": 3, "results": [
      {"wrapperType": "track", "kind": "podcast", "collectionId": 100200300, "collectionName": "The Morning Ledger"},
      {"wrapperType": "podcastEpisode", "kind": "podcast-episode", "trackId": 900100, "trackName": "Harbour dredging",
       "collectionName": "The Morning Ledger", "releaseDate": "2026-10-17T05:00:00Z",
       "shortDescription": "Part one.", "description": "Part one, the long version.",
       "trackViewUrl": "https://podcasts.apple.com/nz/podcast/harbour-dredging/id100200300?i=900100&uo=4"},
      {"wrapperType": "podcastEpisode", "kind": "podcast-episode", "trackId": 900099, "trackName": "The bridge toll",
       "collectionName": "The Morning Ledger", "releaseDate": "2026-10-10T05:00:00.000Z",
       "shortDescription": "", "trackViewUrl": "https://podcasts.apple.com/nz/podcast/the-bridge-toll/id100200300?i=900099"}
    ]}
    """

    func testShowsKeepOnlyPodcastResults() throws {
        let shows = try PodcastDirectoryParser.shows(from: Data(searchFixture.utf8))
        XCTAssertEqual(shows.map(\.id), ["100200300", "100200301"])
        XCTAssertEqual(shows[0].title, "The Morning Ledger")
        XCTAssertEqual(shows[0].author, "Harbourline Audio")
        XCTAssertEqual(shows[0].pageURL?.host, "podcasts.apple.com")
        XCTAssertNil(shows[1].author)
    }

    func testEpisodesSkipTheShowRowAndReadDatesAndNotes() throws {
        let episodes = try PodcastDirectoryParser.episodes(from: Data(lookupFixture.utf8))
        XCTAssertEqual(episodes.map(\.id), ["900100", "900099"])
        XCTAssertEqual(episodes[0].title, "Harbour dredging")
        XCTAssertEqual(episodes[0].showTitle, "The Morning Ledger")
        XCTAssertEqual(episodes[0].summary, "Part one.")
        XCTAssertNotNil(episodes[0].released)
        XCTAssertNotNil(episodes[1].released, "fractional-second dates are read too")
        XCTAssertNil(episodes[1].summary, "an empty note is no note")
        XCTAssertEqual(episodes[0].pageURL?.query, "i=900100&uo=4")
    }

    func testMalformedJSONThrowsRatherThanReturningNothing() {
        XCTAssertThrowsError(try PodcastDirectoryParser.shows(from: Data("not json".utf8)))
    }

    func testOnlyAnApplePodcastsPageIsOpenable() {
        XCTAssertNotNil(PodcastDeepLink.openable(URL(string: "https://podcasts.apple.com/nz/podcast/x/id1?i=2")))
        XCTAssertNil(PodcastDeepLink.openable(URL(string: "http://podcasts.apple.com/nz/podcast/x/id1")), "cleartext never")
        XCTAssertNil(PodcastDeepLink.openable(URL(string: "https://example.invalid/podcast")), "another host never")
        XCTAssertNil(PodcastDeepLink.openable(URL(string: "podcasts://podcasts.apple.com/x")), "no custom scheme")
        XCTAssertNil(PodcastDeepLink.openable(nil))
    }

    func testTheDirectoryURLsCarryOnlyTheWordsAndTheRegion() throws {
        let search = try XCTUnwrap(AppleLookupPodcastDirectory.searchURL(term: "the morning ledger", limit: 5, region: "NZ"))
        XCTAssertEqual(search.host, "itunes.apple.com")
        let items = try XCTUnwrap(URLComponents(url: search, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.map(\.name).sorted(), ["country", "entity", "limit", "media", "term"])
        XCTAssertEqual(items.first { $0.name == "country" }?.value, "nz")
        XCTAssertEqual(items.first { $0.name == "term" }?.value, "the morning ledger")

        let episodes = try XCTUnwrap(AppleLookupPodcastDirectory.episodesURL(showID: "100200300", limit: 25))
        XCTAssertEqual(episodes.query, "id=100200300&entity=podcastEpisode&limit=25")
    }
}
