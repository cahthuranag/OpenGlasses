import XCTest
@testable import OpenGlasses

/// Plan JD — spoken podcast requests → a show name and an episode hint.
final class PodcastRequestParserTests: XCTestCase {

    func testABareShowNameIsTheShowWithNoHint() {
        XCTAssertEqual(PodcastRequestParser.parse(query: "The Daily"),
                       PodcastRequest(show: "the daily", episode: .unspecified))
    }

    func testLatestEpisodeOfLeadsToTheLatestHint() {
        XCTAssertEqual(PodcastRequestParser.parse(query: "the latest episode of The Daily"),
                       PodcastRequest(show: "the daily", episode: .latest))
        XCTAssertEqual(PodcastRequestParser.parse(query: "play the newest episode of Serial"),
                       PodcastRequest(show: "serial", episode: .latest))
        XCTAssertEqual(PodcastRequestParser.parse(query: "latest Serial"),
                       PodcastRequest(show: "serial", episode: .latest))
    }

    func testATrailingPodcastWordIsFiller() {
        XCTAssertEqual(PodcastRequestParser.parse(query: "put on the 99% Invisible podcast")?.show, "the 99% invisible")
        XCTAssertEqual(PodcastRequestParser.parse(query: "Serial podcast episodes")?.show, "serial")
    }

    func testAnEpisodeAboutSomethingSplitsTheTopicOff() {
        XCTAssertEqual(PodcastRequestParser.parse(query: "an episode of 99% Invisible about elevators"),
                       PodcastRequest(show: "99% invisible", episode: .about("elevators")))
    }

    func testTheEpisodeArgumentWinsOverWordsInTheQuery() {
        XCTAssertEqual(PodcastRequestParser.parse(query: "The Daily", episode: "latest"),
                       PodcastRequest(show: "the daily", episode: .latest))
        XCTAssertEqual(PodcastRequestParser.parse(query: "The Daily", episode: "the one about the election"),
                       PodcastRequest(show: "the daily", episode: .about("the one about the election")))
        // An explicit hint is not second-guessed by an "about" inside the query.
        XCTAssertEqual(PodcastRequestParser.parse(query: "Stuff About Stuff", episode: "latest"),
                       PodcastRequest(show: "stuff about stuff", episode: .latest))
    }

    func testFillerAloneIsNotARequest() {
        XCTAssertNil(PodcastRequestParser.parse(query: "a podcast"))
        XCTAssertNil(PodcastRequestParser.parse(query: "   "))
        XCTAssertNil(PodcastRequestParser.parse(query: "the latest episode of"))
    }

    func testPunctuationIsSpokenAway() {
        XCTAssertEqual(PodcastRequestParser.parse(query: "Play \"Serial\", please.")?.show, "serial please")
    }
}
