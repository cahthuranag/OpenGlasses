import XCTest
@testable import OpenGlasses

/// "Play X on Spotify" opens Spotify's own search for X — a link, never an API call.
final class SpotifySearchLinkTests: XCTestCase {

    func testTheLinkIsSpotifysSearchPageWithTheWordsEncoded() throws {
        let url = try XCTUnwrap(SpotifySearchLink.url(for: "Discover Weekly"))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "open.spotify.com")
        XCTAssertEqual(url.path, "/search/discover weekly")
        XCTAssertEqual(url.absoluteString, "https://open.spotify.com/search/discover%20weekly")
    }

    func testPunctuationIsSpokenAwayAndSlashesNeverSplitThePath() throws {
        let url = try XCTUnwrap(SpotifySearchLink.url(for: "AC/DC: Back in Black?"))
        XCTAssertEqual(url.pathComponents.count, 3, "one search segment")
        XCTAssertFalse(url.absoluteString.contains("?"))
        XCTAssertFalse(url.absoluteString.contains("#"))
    }

    func testNothingToSearchIsNoLink() {
        XCTAssertNil(SpotifySearchLink.url(for: "   "))
        XCTAssertNil(SpotifySearchLink.url(for: "..."))
    }
}
