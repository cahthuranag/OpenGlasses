import XCTest
@testable import OpenGlasses

/// Fetching the script models ahead of time and the bounded wait (Plan JY P1, decision 6). The
/// download and readiness are injected: the simulator cannot fetch Apple's assets.
@MainActor
final class ScriptModelAssetsTests: XCTestCase {

    private var ready: Set<EmbeddingScript> = []
    private var asked: [EmbeddingScript] = []

    override func setUp() {
        super.setUp()
        ready = []
        asked = []
    }

    private func makeAssets(inUse: Bool = true, languages: [String] = ["en-NZ", "uk-UA", "zh-Hans-CN"],
                            landing: Bool = true) -> ScriptModelAssets {
        let assets = ScriptModelAssets()
        assets.manualsInUse = { inUse }
        assets.preferredLanguages = { languages }
        assets.isReady = { [unowned self] in self.ready.contains($0) }
        assets.download = { @MainActor [unowned self] script in
            self.asked.append(script)
            if landing { self.ready.insert(script) }
            return landing
        }
        assets.waitLimit = .milliseconds(200)
        return assets
    }

    private func settle(_ assets: ScriptModelAssets) async throws {
        for _ in 0..<50 where EmbeddingScript.allCases.contains(where: assets.isDownloading) {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testThePhonesScriptsAreFetchedWhileManualsAreInUse() async throws {
        let assets = makeAssets()
        assets.prepareForManualsIfInUse()
        try await settle(assets)
        XCTAssertEqual(asked, [.cyrillic, .cjk], "Latin is Field Assist's own asset")
    }

    func testNothingIsFetchedWhileNeitherFeatureIsInUse() async throws {
        let assets = makeAssets(inUse: false)
        assets.prepareForManualsIfInUse()
        try await settle(assets)
        XCTAssertEqual(asked, [])
    }

    func testAModelHereOrOnItsWayIsNotAskedForAgain() async throws {
        ready = [.cjk]
        let assets = makeAssets()
        assets.prepareForManualsIfInUse()
        assets.prepareForManualsIfInUse()
        assets.request(.cyrillic)
        try await settle(assets)
        XCTAssertEqual(asked, [.cyrillic])
        assets.request(.latin)
        try await settle(assets)
        XCTAssertEqual(asked, [.cyrillic], "Latin is never this coordinator's")
    }

    func testAFailedDownloadIsRecordedAndAskedForAgainLater() async throws {
        let assets = makeAssets(languages: ["ar"], landing: false)
        var arrivals = 0
        assets.onArrival = { _ in arrivals += 1 }
        assets.prepareForManualsIfInUse()
        try await settle(assets)
        XCTAssertTrue(assets.lastFailed.contains(.arabic))
        XCTAssertEqual(arrivals, 0)
        assets.prepareForManualsIfInUse()
        try await settle(assets)
        XCTAssertEqual(asked, [.arabic, .arabic], "the next launch or switch asks again")
    }

    func testTheWaitReturnsAtOnceWhenNothingIsDownloading() async {
        let assets = makeAssets()
        assets.waitLimit = .seconds(30)
        let started = ContinuousClock.now
        let landed = await assets.waitIfDownloading(.cjk)
        XCTAssertFalse(landed)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(1))
    }

    func testTheWaitIsBoundedWhenTheDownloadIsSlow() async {
        let assets = makeAssets()
        var release: CheckedContinuation<Void, Never>?
        assets.download = { @MainActor _ in
            await withCheckedContinuation { release = $0 }
            return false
        }
        assets.waitLimit = .milliseconds(300)
        let started = ContinuousClock.now
        await assets.requestAndWait(.urdu)
        let elapsed = ContinuousClock.now - started
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(250))
        XCTAssertLessThan(elapsed, .seconds(3))
        XCTAssertTrue(assets.isDownloading(.urdu), "the download carries on after indexing stops waiting")
        release?.resume()
    }
}
