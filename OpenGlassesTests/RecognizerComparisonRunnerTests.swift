import XCTest
@testable import OpenGlasses

/// Plan JM P3 — the comparison runner with fake engines: the order, one engine at a time, a cloud
/// engine the gate refuses is never called, and a throwing engine becomes a failed row.
@MainActor
final class RecognizerComparisonRunnerTests: XCTestCase {

    private let utterance = KeptUtterance(samples: Array(repeating: 0.1, count: 16_000),
                                          sampleRate: 16_000, capturedAt: Date(timeIntervalSince1970: 1_000))

    private enum FakeFailure: Error { case boom }

    /// A record of what the fakes saw, and how many ran at once.
    private final class Log {
        var calls: [RecognizerComparison.Engine] = []
        var vocabularies: [[String]] = []
        var inFlight = 0
        var maxInFlight = 0
    }

    private func slot(_ engine: RecognizerComparison.Engine, _ log: Log,
                      availability: RecognizerComparisonRunner.Availability = .ready,
                      result: Result<String, Error> = .success("heard")) -> RecognizerComparisonRunner.Slot {
        .init(engine: engine, availability: { availability }, transcribe: { _, vocabulary in
            log.calls.append(engine)
            log.vocabularies.append(vocabulary)
            log.inFlight += 1
            log.maxInFlight = max(log.maxInFlight, log.inFlight)
            try? await Task.sleep(nanoseconds: 5_000_000)
            log.inFlight -= 1
            return try result.get()
        })
    }

    func testEnginesRunInOrderOneAtATime() async {
        let log = Log()
        let runner = RecognizerComparisonRunner(slots: [
            slot(.appleSpeech, log), slot(.appleSpeechOnDevice, log), slot(.onDevice, log),
            slot(.deepgram, log), slot(.openAI, log),
        ])
        let rows = await runner.run(utterance, vocabulary: ["R-410A"])
        XCTAssertEqual(log.calls, [.appleSpeech, .appleSpeechOnDevice, .onDevice, .deepgram, .openAI])
        XCTAssertEqual(rows.map(\.engine), log.calls)
        XCTAssertEqual(log.maxInFlight, 1, "never two recognisers at once — the timings would lie")
        XCTAssertEqual(log.vocabularies, Array(repeating: ["R-410A"], count: 5))
        XCTAssertTrue(rows.allSatisfy { $0.outcome == .transcribed && $0.transcript == "heard" })
        XCTAssertFalse(runner.isRunning)
        XCTAssertNil(runner.running)
        XCTAssertEqual(runner.ranOn, utterance.capturedAt)
        XCTAssertTrue(runner.ranWithHints)
    }

    func testEachRowIsTimedOnItsOwnEngine() async {
        let log = Log()
        let runner = RecognizerComparisonRunner(slots: [slot(.appleSpeech, log), slot(.openAI, log)])
        var tick: TimeInterval = 0
        runner.now = {
            defer { tick += 1 }
            return Date(timeIntervalSince1970: tick * tick)   // 0, 1, 4, 9: each span differs
        }
        let rows = await runner.run(utterance, vocabulary: [])
        XCTAssertEqual(rows.map(\.elapsed), [1, 5], "start and end are read around each engine alone")
    }

    func testANotConfiguredCloudEngineIsNeverCalled() async {
        let log = Log()
        let runner = RecognizerComparisonRunner(slots: [
            slot(.appleSpeech, log),
            slot(.deepgram, log, availability: .notConfigured),
            slot(.openAI, log, availability: .notConfigured),
        ])
        let rows = await runner.run(utterance, vocabulary: [])
        XCTAssertEqual(log.calls, [.appleSpeech], "nothing is sent for a not-configured engine")
        XCTAssertEqual(rows.map(\.outcome), [.transcribed, .notConfigured, .notConfigured])
        XCTAssertEqual(rows[1].elapsed, 0)
    }

    func testAHiddenEngineHasNoRow() async {
        let log = Log()
        let runner = RecognizerComparisonRunner(slots: [
            slot(.appleSpeech, log), slot(.appleSpeechOnDevice, log, availability: .hidden),
            slot(.onDevice, log, availability: .hidden),
        ])
        let rows = await runner.run(utterance, vocabulary: [])
        XCTAssertEqual(rows.map(\.engine), [.appleSpeech])
        XCTAssertEqual(log.calls, [.appleSpeech])
    }

    func testAThrowingEngineYieldsAFailedRowAndTheRestStillRun() async {
        let log = Log()
        let runner = RecognizerComparisonRunner(slots: [
            slot(.openAI, log, result: .failure(OpenAIDictationError.http(500))),
            slot(.onDevice, log, result: .failure(FakeFailure.boom)),
            slot(.appleSpeech, log, result: .failure(RecognizerComparisonError.timedOut)),
            slot(.deepgram, log),
        ])
        let rows = await runner.run(utterance, vocabulary: [])
        XCTAssertEqual(rows.map(\.outcome), [.failed("http500"), .failed("failed"), .failed("timedOut"), .transcribed])
        XCTAssertNotNil(rows[0].message, "the engine's own sentence is for the screen")
    }

    func testFailureTokensAreFixed() {
        XCTAssertEqual(RecognizerComparisonRunner.token(for: OpenAIDictationError.noKey), "noKey")
        XCTAssertEqual(RecognizerComparisonRunner.token(for: RecognizerComparisonError.stoppedEarly("gateClosed")),
                       "stopped-gateClosed")
        XCTAssertEqual(RecognizerComparisonRunner.token(for: CancellationError()), "cancelled")
        XCTAssertEqual(RecognizerComparisonRunner.token(for: FakeFailure.boom), "failed")
        XCTAssertEqual(RecognizerComparisonRunner.token(for: ASRError.modelUnavailable), "onDeviceFailed")
    }

    func testAddToSessionOncePerRun() async {
        let log = Log()
        let runner = RecognizerComparisonRunner(slots: [slot(.appleSpeech, log), slot(.openAI, log)])
        await runner.run(utterance, vocabulary: [])
        runner.reference = "heard"
        runner.addToSession()
        runner.addToSession()
        XCTAssertEqual(runner.session.entries.count, 2)
        XCTAssertEqual(runner.session.utteranceCount, 1)
        XCTAssertTrue(runner.addedToSession)

        XCTAssertEqual(runner.session.entries.first?.hints, false, "no hints were passed on that run")

        await runner.run(utterance, vocabulary: ["R-454B"])
        XCTAssertFalse(runner.addedToSession, "a new run can be added")
        runner.addToSession()
        XCTAssertEqual(runner.session.utteranceCount, 2)
        XCTAssertEqual(runner.session.entries.last?.hints, true)
        runner.clearSession()
        XCTAssertTrue(runner.session.isEmpty)
    }

    // MARK: - The live slots never bypass the gate

    private func gate(open: Bool) -> CloudDictationGate {
        CloudDictationGate(preference: { .deepgram }, optedIn: { open }, keyPresent: { _ in true },
                           hipaa: { !open }, orgPinnedOff: { false }, medicalAllows: { _ in true })
    }

    func testLiveCloudSlotsAreNotConfiguredWhenTheGateIsClosed() {
        let runner = RecognizerComparisonRunner.live(onDeviceEngine: OnDeviceASREngine(),
                                                     gate: { self.gate(open: false) })
        let cloud = runner.slots.filter { $0.engine.cloudProvider != nil }
        XCTAssertEqual(cloud.map(\.engine), [.deepgram, .openAI])
        XCTAssertTrue(cloud.allSatisfy { $0.availability() == .notConfigured },
                      "HIPAA on: both cloud rows say not configured and nothing is sent")
    }

    func testLiveCloudSlotsFollowTheChosenProvider() {
        let runner = RecognizerComparisonRunner.live(onDeviceEngine: OnDeviceASREngine(),
                                                     gate: { self.gate(open: true) })
        let availability = Dictionary(uniqueKeysWithValues: runner.slots.map { ($0.engine, $0.availability()) })
        XCTAssertEqual(availability[.deepgram], .ready)
        XCTAssertEqual(availability[.openAI], .notConfigured,
                       "the gate allows only the recogniser chosen in the picker")
        XCTAssertEqual(runner.slots.map(\.engine),
                       [.appleSpeech, .appleSpeechOnDevice, .onDevice, .deepgram, .openAI])
    }

    // MARK: - Feeding the kept samples

    func testBuffersCoverTheUtteranceInTenthSecondChunks() {
        var samples = Array(repeating: Float(0), count: 25_000)
        samples[0] = 0.5
        samples[24_999] = -0.25
        let kept = KeptUtterance(samples: samples, sampleRate: 16_000, capturedAt: Date())
        let buffers = RecognizerComparisonRunner.buffers(for: kept)
        XCTAssertEqual(buffers.count, 16)
        XCTAssertEqual(buffers.map { Int($0.frameLength) }.reduce(0, +), 25_000)
        XCTAssertEqual(buffers.first?.frameLength, 1_600)
        XCTAssertEqual(buffers.first?.format.sampleRate, 16_000)
        XCTAssertEqual(buffers.first?.format.channelCount, 1)
        XCTAssertEqual(buffers.first?.floatChannelData?[0][0], 0.5)
        XCTAssertEqual(buffers.last.map { $0.floatChannelData![0][Int($0.frameLength) - 1] }, -0.25)
        XCTAssertTrue(RecognizerComparisonRunner.buffers(
            for: KeptUtterance(samples: [], sampleRate: 16_000, capturedAt: Date())).isEmpty)
    }
}
