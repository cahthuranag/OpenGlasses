import XCTest
@testable import OpenGlasses

/// The removed and retiring OpenAI realtime IDs, and the once-only rewrite of saved models.
final class OpenAIRealtimeModelRetirementTests: XCTestCase {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day))!
    }
    private func model(_ id: String, provider: String = "openai") -> RealtimeModelConfig {
        var model = RealtimeProviderCatalog.template(provider)!.modelConfiguration()
        model.apiKey = "fixture-key"
        model.model = id
        return model
    }

    func testEveryPublishedIDMapsToItsTwoPointOneReplacement() {
        let expected: [String: String] = [
            "gpt-4o-realtime-preview": "gpt-realtime-2.1",
            "gpt-4o-realtime-preview-2024-12-17": "gpt-realtime-2.1",
            "gpt-4o-realtime-preview-2025-06-03": "gpt-realtime-2.1",
            "gpt-4o-mini-realtime-preview": "gpt-realtime-2.1-mini",
            "gpt-4o-mini-realtime-preview-2024-12-17": "gpt-realtime-2.1-mini",
            "gpt-realtime": "gpt-realtime-2.1",
            "gpt-realtime-2025-08-28": "gpt-realtime-2.1",
            "gpt-4o-realtime": "gpt-realtime-2.1",
            "gpt-realtime-mini": "gpt-realtime-2.1-mini",
            "gpt-realtime-mini-2025-12-15": "gpt-realtime-2.1-mini",
            "gpt-4o-mini-realtime": "gpt-realtime-2.1-mini",
            " GPT-Realtime ": "gpt-realtime-2.1",
        ]
        for (id, replacement) in expected {
            XCTAssertEqual(OpenAIRealtimeModelRetirement.entry(for: id)?.replacement, replacement, id)
        }
    }

    func testCurrentAndUnrelatedIDsAreNotInTheTable() {
        for id in ["gpt-realtime-2.1", "gpt-realtime-2.1-mini", "gpt-realtime-1.5", "gpt-realtime-2025-12-01",
                   "gpt-4o", "qwen-omni-turbo-realtime", ""] {
            XCTAssertNil(OpenAIRealtimeModelRetirement.entry(for: id), id)
        }
        for replacement in Set(OpenAIRealtimeModelRetirement.entries.map(\.replacement)) {
            XCTAssertNil(OpenAIRealtimeModelRetirement.entry(for: replacement), "a replacement is never itself retiring")
        }
    }

    func testRemovalDatesFollowOpenAIsPage() {
        XCTAssertTrue(OpenAIRealtimeModelRetirement.isRemoved("gpt-4o-realtime-preview-2024-12-17", on: day(2026, 10, 29)))
        XCTAssertTrue(OpenAIRealtimeModelRetirement.isRemoved("gpt-4o-mini-realtime-preview", on: day(2026, 5, 7)))
        XCTAssertFalse(OpenAIRealtimeModelRetirement.isRemoved("gpt-4o-realtime-preview", on: day(2026, 5, 6)))
        XCTAssertFalse(OpenAIRealtimeModelRetirement.isRemoved("gpt-realtime", on: day(2027, 1, 19)))
        XCTAssertTrue(OpenAIRealtimeModelRetirement.isRemoved("gpt-realtime", on: day(2027, 1, 20)))
        XCTAssertTrue(OpenAIRealtimeModelRetirement.isRemoved("gpt-realtime-mini-2025-12-15", on: day(2027, 1, 20)))
        XCTAssertFalse(OpenAIRealtimeModelRetirement.isRemoved("gpt-realtime-2.1", on: day(2030, 1, 1)))
    }

    func testRewriteMovesOpenAIModelsOnlyAndKeepsEverythingElse() throws {
        let preview = model("gpt-4o-realtime-preview-2024-12-17")
        let mini = model("gpt-realtime-mini")
        let current = model("gpt-realtime-2.1")
        let compatible = model("gpt-realtime", provider: "compatible")
        let rewrite = try XCTUnwrap(OpenAIRealtimeModelRetirement.rewriting([preview, mini, current, compatible]))
        XCTAssertEqual(rewrite.models.map(\.model), ["gpt-realtime-2.1", "gpt-realtime-2.1-mini", "gpt-realtime-2.1", "gpt-realtime"],
                       "a compatible server's model names are its own")
        XCTAssertEqual(rewrite.models.map(\.id), [preview, mini, current, compatible].map(\.id))
        XCTAssertEqual(rewrite.models.map(\.apiKey), Array(repeating: "fixture-key", count: 4))
        XCTAssertEqual(rewrite.models.map(\.profileID), [preview, mini, current, compatible].map(\.profileID))
        XCTAssertEqual(rewrite.renames.map(\.from), ["gpt-4o-realtime-preview-2024-12-17", "gpt-realtime-mini"])
        XCTAssertNil(OpenAIRealtimeModelRetirement.rewriting(rewrite.models), "a second pass changes nothing")
        XCTAssertNil(OpenAIRealtimeModelRetirement.rewriting([current, compatible]))
    }

    func testRewriteNamesEachMoveOnce() throws {
        let rewrite = try XCTUnwrap(OpenAIRealtimeModelRetirement.rewriting([model("gpt-realtime"), model("gpt-realtime")]))
        XCTAssertEqual(rewrite.renames.count, 1)
    }

    func testNoticeNamesTheOldAndNewIDs() throws {
        let retiring = try XCTUnwrap(OpenAIRealtimeModelRetirement.rewriting([model("gpt-realtime")]))
        let before = try XCTUnwrap(OpenAIRealtimeModelRetirement.notice(for: retiring.renames, on: day(2026, 10, 29)))
        XCTAssertTrue(before.contains("gpt-realtime ") && before.contains("gpt-realtime-2.1"), before)
        XCTAssertTrue(before.contains("2027"), "a retiring ID says when: \(before)")
        let after = try XCTUnwrap(OpenAIRealtimeModelRetirement.notice(for: retiring.renames, on: day(2027, 2, 1)))
        XCTAssertFalse(after.contains("2027"), after)
        XCTAssertTrue(after.contains("gpt-realtime-2.1"), after)

        let both = try XCTUnwrap(OpenAIRealtimeModelRetirement.rewriting([model("gpt-4o-realtime-preview"), model("gpt-realtime-mini")]))
        let list = try XCTUnwrap(OpenAIRealtimeModelRetirement.notice(for: both.renames, on: day(2026, 10, 29)))
        for id in ["gpt-4o-realtime-preview", "gpt-realtime-2.1", "gpt-realtime-mini", "gpt-realtime-2.1-mini"] {
            XCTAssertTrue(list.contains(id), "\(id) missing from: \(list)")
        }
        XCTAssertNil(OpenAIRealtimeModelRetirement.notice(for: []))
    }

    func testNoticeWordingCarriesNoPlanLetters() throws {
        let rewrite = try XCTUnwrap(OpenAIRealtimeModelRetirement.rewriting([model("gpt-realtime"), model("gpt-4o-mini-realtime")]))
        for renames in [Array(rewrite.renames.prefix(1)), rewrite.renames] {
            for date in [day(2026, 10, 29), day(2027, 2, 1)] {
                let notice = try XCTUnwrap(OpenAIRealtimeModelRetirement.notice(for: renames, on: date))
                XCTAssertNil(notice.range(of: #"\bPlan\b|\bKC\b|\bP1\b"#, options: .regularExpression), notice)
            }
        }
    }

    func testTheOpenAITemplateDefaultsToTheReplacement() {
        XCTAssertEqual(RealtimeProviderCatalog.template("openai")?.model, "gpt-realtime-2.1")
        XCTAssertNil(OpenAIRealtimeModelRetirement.entry(for: RealtimeProviderCatalog.template("openai")!.model))
    }

    func testTheLiveSessionTranscribesWithTheLiveModel() {
        XCTAssertEqual(OpenAIRealtimeGAAdapter.transcriptionModel, "gpt-live-transcribe")
    }
}

/// The rewrite and the legacy shortcut against the real Keychain-backed stores.
final class OpenAIRealtimeModelIDMigrationTests: XCTestCase {
    private var savedLive: Data??
    private var savedChat: Data??
    private var flags: [String: Any] = [:]
    private let flagKeys = ["realtimeModelsMigrated_v1", "realtimeModelsMigrated_v2", "realtimeModelsMigrated_v3",
                            Config.pendingRealtimeModelNoticeKey, "activeModelId"]
    private let october = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"),
                                                                                    year: 2026, month: 10, day: 29))!
    private let february = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"),
                                                                                     year: 2027, month: 2, day: 1))!

    override func setUp() {
        savedLive = .some(KeychainService.data(for: "savedRealtimeModels"))
        savedChat = .some(KeychainService.data(for: "savedModelConfigs"))
        for key in flagKeys { flags[key] = UserDefaults.standard.object(forKey: key); UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.set(true, forKey: "realtimeModelsMigrated_v1")
        UserDefaults.standard.set(true, forKey: "realtimeModelsMigrated_v2")
    }
    override func tearDown() {
        KeychainService.setData(savedLive ?? nil, for: "savedRealtimeModels")
        KeychainService.setData(savedChat ?? nil, for: "savedModelConfigs")
        for key in flagKeys {
            if let value = flags[key] { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }
    private func live(_ id: String, provider: String = "openai") -> RealtimeModelConfig {
        var model = RealtimeProviderCatalog.template(provider)!.modelConfiguration()
        model.apiKey = "fixture-key"; model.model = id
        return model
    }

    func testRewriteRunsOnceLeavesOneNoticeAndSetsItsFlag() {
        XCTAssertTrue(Config.setSavedRealtimeModels([live("gpt-realtime"), live("gpt-realtime", provider: "compatible")]))
        XCTAssertTrue(Config.migrateOpenAIRealtimeModelIDsIfNeeded(on: october))
        XCTAssertEqual(Config.savedRealtimeModels.map(\.model), ["gpt-realtime-2.1", "gpt-realtime"])
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "realtimeModelsMigrated_v3"))
        let notice = Config.takePendingRealtimeModelNotice()
        XCTAssertTrue(notice?.contains("gpt-realtime-2.1") == true, notice ?? "no notice")
        XCTAssertNil(Config.takePendingRealtimeModelNotice(), "the notice is shown once")
        // Once flagged it never runs again, even if a retiring ID is saved by hand.
        XCTAssertTrue(Config.setSavedRealtimeModels([live("gpt-realtime")]))
        XCTAssertTrue(Config.migrateRealtimeModelsIfNeeded())
        XCTAssertEqual(Config.savedRealtimeModels.first?.model, "gpt-realtime")
        XCTAssertNil(Config.takePendingRealtimeModelNotice())
    }

    func testARejectedKeychainWriteLeavesTheFlagUnsetAndRetries() {
        XCTAssertTrue(Config.setSavedRealtimeModels([live("gpt-realtime-mini")]))
        XCTAssertFalse(Config.migrateOpenAIRealtimeModelIDsIfNeeded(on: october, save: { _ in false }))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "realtimeModelsMigrated_v3"))
        XCTAssertEqual(Config.savedRealtimeModels.first?.model, "gpt-realtime-mini")
        XCTAssertNil(Config.takePendingRealtimeModelNotice(), "no notice for a move that did not happen")
        XCTAssertTrue(Config.migrateOpenAIRealtimeModelIDsIfNeeded(on: october))
        XCTAssertEqual(Config.savedRealtimeModels.first?.model, "gpt-realtime-2.1-mini")
    }

    func testNothingToMoveSetsTheFlagWithoutANotice() {
        XCTAssertTrue(Config.setSavedRealtimeModels([live("gpt-realtime-2.1")]))
        XCTAssertTrue(Config.migrateRealtimeModelsIfNeeded())
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "realtimeModelsMigrated_v3"))
        XCTAssertEqual(Config.savedRealtimeModels.first?.model, "gpt-realtime-2.1")
        XCTAssertNil(Config.takePendingRealtimeModelNotice())
    }

    @MainActor func testPendingNoticeIsPostedOnceAsAWarning() {
        UserDefaults.standard.set("fixture notice", forKey: Config.pendingRealtimeModelNoticeKey)
        let center = NoticeCenter(now: { 0 })
        Config.postPendingRealtimeModelNotice(to: center)
        XCTAssertEqual(center.current?.text, "fixture notice")
        XCTAssertEqual(center.current?.severity, .warning)
        center.dismissCurrent()
        Config.postPendingRealtimeModelNotice(to: center)
        XCTAssertNil(center.current)
    }

    func testTheLegacyShortcutSkipsRemovedIDs() {
        var removed = ModelConfig.defaultConfig(for: .openai)
        removed.apiKey = "fixture-key"; removed.model = "gpt-4o-realtime-preview-2024-12-17"
        var retiring = ModelConfig.defaultConfig(for: .openai)
        retiring.id = "retiring"; retiring.apiKey = "fixture-key"; retiring.model = "gpt-realtime"
        Config.setSavedModels([removed, retiring])
        XCTAssertEqual(Config.openAIRealtimeModelConfig(on: october)?.model, "gpt-realtime",
                       "a removed ID is skipped; a retiring one still works until its date")
        XCTAssertNil(Config.openAIRealtimeModelConfig(on: february), "after 2027-01-20 neither connects")
    }

    func testTheLegacyShortcutKeepsAWorkingID() {
        var current = ModelConfig.defaultConfig(for: .openai)
        current.apiKey = "fixture-key"; current.model = "gpt-realtime-2.1"
        Config.setSavedModels([current])
        XCTAssertEqual(Config.openAIRealtimeModelConfig(on: february)?.model, "gpt-realtime-2.1")
    }
}
