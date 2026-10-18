import XCTest
@testable import OpenGlasses

/// Plan JE — which show and which episode the wearer meant. Every id and title here is invented.
final class PodcastRankerTests: XCTestCase {

    private func show(_ id: String, _ title: String) -> PodcastShow {
        PodcastShow(id: id, title: title, author: "Harbourline Audio",
                    pageURL: URL(string: "https://podcasts.apple.com/nz/podcast/x/id\(id)"))
    }

    private func episode(_ id: String, _ title: String, daysAgo: Int, summary: String? = nil) -> PodcastEpisode {
        PodcastEpisode(id: id, title: title, showTitle: "The Morning Ledger",
                       released: Date(timeIntervalSinceNow: -Double(daysAgo) * 86_400),
                       summary: summary,
                       pageURL: URL(string: "https://podcasts.apple.com/nz/podcast/x/id100200300?i=\(id)"))
    }

    func testAnExactTitleBeatsTheDirectorysFirstResult() {
        let shows = [show("1", "The Morning Ledger Daily Recap"), show("2", "The Morning Ledger")]
        XCTAssertEqual(PodcastRanker.bestShow(for: PodcastRequest(show: "morning ledger"), in: shows)?.id, "2")
        XCTAssertEqual(PodcastRanker.bestShow(for: PodcastRequest(show: "the morning ledger podcast"), in: shows)?.id, "2")
    }

    func testOtherwiseTheDirectorysRankingStands() {
        let shows = [show("1", "Ledger Lines"), show("2", "The Morning Ledger")]
        XCTAssertEqual(PodcastRanker.bestShow(for: PodcastRequest(show: "ledger"), in: shows)?.id, "1")
        XCTAssertNil(PodcastRanker.bestShow(for: PodcastRequest(show: "ledger"), in: []))
    }

    func testLatestIsTheNewestByReleaseDateWhateverTheOrder() {
        let episodes = [episode("a", "Older", daysAgo: 9), episode("b", "Newest", daysAgo: 1), episode("c", "Middle", daysAgo: 4)]
        XCTAssertEqual(PodcastRanker.pickEpisode(.latest, from: episodes)?.episode.id, "b")
        XCTAssertEqual(PodcastRanker.pickEpisode(.unspecified, from: episodes)?.episode.id, "b")
        XCTAssertNil(PodcastRanker.pickEpisode(.latest, from: []))
    }

    func testAnUndatedEpisodeNeverBeatsADatedOne() {
        let undated = PodcastEpisode(id: "u", title: "Undated", showTitle: "x", released: nil, summary: nil, pageURL: nil)
        let episodes = [undated, episode("b", "Dated", daysAgo: 30)]
        XCTAssertEqual(PodcastRanker.pickEpisode(.latest, from: episodes)?.episode.id, "b")
    }

    func testAboutPrefersTheNewestEpisodeCarryingEveryTopicWord() {
        let episodes = [
            episode("a", "Harbour dredging, part two", daysAgo: 2),
            episode("b", "Harbour dredging, part one", daysAgo: 9),
            episode("c", "The bridge toll", daysAgo: 1, summary: "Why the harbour crossing costs what it does"),
        ]
        let pick = PodcastRanker.pickEpisode(.about("harbour dredging"), from: episodes)
        XCTAssertEqual(pick?.episode.id, "a")
        XCTAssertEqual(pick?.matchedTopic, true)
        // Any one word is the fallback; notes count as well as titles.
        XCTAssertEqual(PodcastRanker.pickEpisode(.about("crossing"), from: episodes)?.episode.id, "c")
    }

    func testAnUnmatchedTopicFallsBackToTheNewestAndSaysSo() {
        let episodes = [episode("a", "Harbour dredging", daysAgo: 2), episode("b", "The bridge toll", daysAgo: 1)]
        let pick = PodcastRanker.pickEpisode(.about("elevators"), from: episodes)
        XCTAssertEqual(pick?.episode.id, "b")
        XCTAssertEqual(pick?.matchedTopic, false)
    }
}
