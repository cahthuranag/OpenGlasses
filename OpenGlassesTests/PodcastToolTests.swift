import XCTest
@testable import OpenGlasses

/// Plan JF — `play_podcast` looks the show up, picks the episode, stands the temple-tap trigger
/// down, and opens only a podcasts.apple.com page. Fixtures are invented.
private final class FakePodcastDirectory: PodcastDirectorySearching, @unchecked Sendable {
    var shows: [PodcastShow] = []
    var episodes: [PodcastEpisode] = []
    var searchTerms: [String] = []
    var episodeLookups: [String] = []
    var fails = false

    func searchShows(matching term: String, limit: Int) async throws -> [PodcastShow] {
        if fails { throw URLError(.notConnectedToInternet) }
        searchTerms.append(term)
        return shows
    }

    func episodes(ofShow showID: String, limit: Int) async throws -> [PodcastEpisode] {
        if fails { throw URLError(.notConnectedToInternet) }
        episodeLookups.append(showID)
        return episodes
    }
}

@MainActor
final class PodcastToolTests: XCTestCase {

    private var directory: FakePodcastDirectory!
    private var opened: [URL] = []
    private var openSucceeds = true
    private var standDowns = 0

    private let ledger = PodcastShow(id: "100200300", title: "The Morning Ledger", author: "Harbourline Audio",
                                     pageURL: URL(string: "https://podcasts.apple.com/nz/podcast/the-morning-ledger/id100200300"))

    private func episode(_ id: String, _ title: String, daysAgo: Int, host: String = "podcasts.apple.com") -> PodcastEpisode {
        PodcastEpisode(id: id, title: title, showTitle: "The Morning Ledger",
                       released: Date(timeIntervalSinceNow: -Double(daysAgo) * 86_400), summary: nil,
                       pageURL: URL(string: "https://\(host)/nz/podcast/x/id100200300?i=\(id)"))
    }

    override func setUp() {
        directory = FakePodcastDirectory()
        directory.shows = [ledger]
        directory.episodes = [episode("900099", "The bridge toll", daysAgo: 8), episode("900100", "Harbour dredging", daysAgo: 1)]
        opened = []
        openSucceeds = true
        standDowns = 0
    }

    private func tool() -> PodcastTool {
        var tool = PodcastTool()
        tool.makeEnvironment = { [unowned self] in
            PodcastToolEnvironment(
                directory: self.directory,
                open: { [unowned self] url in
                    self.opened.append(url)
                    return self.openSucceeds
                },
                playbackRequested: { [unowned self] in self.standDowns += 1 })
        }
        return tool
    }

    func testPlayOpensTheLatestEpisodeAndStandsTheTriggerDown() async throws {
        let reply = try await tool().execute(args: ["query": "the latest episode of The Morning Ledger"])
        XCTAssertEqual(directory.searchTerms, ["the morning ledger"])
        XCTAssertEqual(directory.episodeLookups, ["100200300"])
        XCTAssertEqual(opened.map(\.absoluteString), ["https://podcasts.apple.com/nz/podcast/x/id100200300?i=900100"])
        XCTAssertEqual(standDowns, 1)
        XCTAssertEqual(reply, "Opening the latest episode of The Morning Ledger in Podcasts: Harbour dredging.")
    }

    func testAnEpisodeArgumentPicksByTopic() async throws {
        let reply = try await tool().execute(args: ["query": "The Morning Ledger", "episode": "the bridge toll"])
        XCTAssertEqual(opened.last?.query, "i=900099")
        XCTAssertEqual(reply, "Opening The bridge toll, from The Morning Ledger, in Podcasts.")
    }

    func testAnUnmatchedTopicOpensTheLatestAndSaysSo() async throws {
        let reply = try await tool().execute(args: ["query": "an episode of The Morning Ledger about elevators"])
        XCTAssertEqual(opened.last?.query, "i=900100")
        XCTAssertTrue(reply.hasPrefix("I couldn't find an episode of The Morning Ledger about elevators"), reply)
    }

    func testNothingButAnApplePodcastsPageIsEverOpened() async throws {
        directory.episodes = [episode("1", "Elsewhere", daysAgo: 1, host: "example.invalid")]
        let reply = try await tool().execute(args: ["query": "The Morning Ledger"])
        XCTAssertEqual(opened, [])
        XCTAssertEqual(standDowns, 0)
        XCTAssertEqual(reply, PodcastPhraser.noLink("The Morning Ledger"))
    }

    func testNoEpisodesListedOpensTheShowPage() async throws {
        directory.episodes = []
        let reply = try await tool().execute(args: ["query": "The Morning Ledger"])
        XCTAssertEqual(opened, [ledger.pageURL])
        XCTAssertEqual(reply, "Opening The Morning Ledger in Podcasts.")
    }

    func testAMissingPodcastsAppIsSaidPlainly() async throws {
        openSucceeds = false
        let reply = try await tool().execute(args: ["query": "The Morning Ledger"])
        XCTAssertEqual(reply, PodcastPhraser.podcastsAppMissing)
    }

    func testAnUnknownShowAndAnUnreachableDirectoryAreSaidPlainly() async throws {
        directory.shows = []
        let unknown = try await tool().execute(args: ["query": "Nothing Like This"])
        XCTAssertEqual(unknown, PodcastPhraser.noShow("nothing like this"))
        XCTAssertEqual(opened, [])

        directory.fails = true
        let unreachable = try await tool().execute(args: ["query": "The Morning Ledger"])
        XCTAssertEqual(unreachable, PodcastPhraser.directoryUnreachable)
    }

    func testSearchListsShowsWithoutOpeningAnything() async throws {
        directory.shows = [ledger, PodcastShow(id: "2", title: "Ledger Lines", author: nil, pageURL: nil)]
        let reply = try await tool().execute(args: ["action": "search", "query": "ledger"])
        XCTAssertEqual(reply, "Podcasts matching ledger: The Morning Ledger by Harbourline Audio; Ledger Lines. Say which one to play.")
        XCTAssertEqual(opened, [])
        XCTAssertEqual(standDowns, 0)
    }

    func testAnEmptyQueryAsksWhichPodcast() async throws {
        let blank = try await tool().execute(args: ["query": " "])
        XCTAssertEqual(blank, PodcastPhraser.whichPodcast)
        let missing = try await tool().execute(args: [:])
        XCTAssertEqual(missing, PodcastPhraser.whichPodcast)
    }

    func testNameDescriptionAndSemantics() {
        let tool = PodcastTool()
        XCTAssertEqual(tool.name, "play_podcast")
        XCTAssertTrue(tool.description.contains("cannot pause, skip"), "the model must not promise transport")
        XCTAssertTrue(tool.description.contains("music_control"), "music is routed away")
        XCTAssertEqual(tool.executionSemantics.effect, .externalMutation)
        XCTAssertEqual(tool.executionSemantics.idempotency, .intrinsic)
    }
}
