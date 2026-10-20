import Foundation

/// The ordering, prefetch and demotion rules of a streamed reply, as a pure value (Plan HZ P0).
///
/// The old streamer awaited one sentence's playback before *starting* the next one's synthesis,
/// so with a cloud voice every sentence paid a full round trip of silence. This schedule keeps up
/// to `prefetchDepth` sentences synthesising while one plays, and decides — from events, never
/// from time — which sentence to synthesise next, on which engine, and which one may play:
///
/// - **Playback is strictly in order**, however synthesis completes. A sentence that is ready
///   waits for every sentence before it to have played (or to have been given up on).
/// - **Each sentence walks the engine chain** it was enqueued with, falling to the next engine
///   when one fails.
/// - **Per-reply demotion.** Two consecutive failures of one cloud voice inside one reply take that
///   voice out of the chain for every sentence of this reply not yet started, so a flaky network
///   produces one voice change rather than a sentence-by-sentence stutter of timeouts. Each cloud
///   voice is counted and demoted on its own (Plan ID item 5): with Auto and two set up, the
///   second still gets its chance. A schedule is one reply: the next reply starts with a fresh one
///   and tries the cloud voices again.
/// - **Cancellation drops the remainder.** What had played stays played; nothing else plays.
///
/// The driver (`StreamedReplyQueue`) turns `Action`s into synthesis and playback calls and feeds
/// their results back. Nothing here waits, sleeps or touches audio.
struct StreamedReplySchedule {

    static let defaultPrefetchDepth = 2
    static let maximumPrefetchDepth = 3
    /// Consecutive cloud-voice failures that demote the rest of the reply.
    static let cloudFailuresBeforeDemotion = 2

    enum ItemState: Equatable {
        /// Enqueued, not yet sent to an engine.
        case waiting
        case synthesizing(TTSEngine)
        case ready(TTSEngine)
        case playing(TTSEngine)
        /// Played to its end.
        case heard
        /// Ended without being played to its end — every engine failed, the route withheld it, or
        /// playback broke. The reply carries on past it.
        case unheard
        /// Dropped by a cancellation before it played.
        case dropped

        var isTerminal: Bool { self == .heard || self == .unheard || self == .dropped }
    }

    struct Item: Equatable {
        let index: Int
        /// What is spoken. Can grow by one line when the cloud voice turns a sentence down for a
        /// reason the wearer has to act on (`CloudVoiceFallbackAnnouncer`).
        var text: String
        /// The engines this sentence may use, best first, as they were when it was enqueued.
        let chain: [TTSEngine]
        var state: ItemState
    }

    enum Action: Equatable {
        case synthesize(index: Int, engine: TTSEngine)
        case play(index: Int, engine: TTSEngine)
    }

    let prefetchDepth: Int
    private(set) var items: [Item] = []
    /// No more sentences will be enqueued.
    private(set) var isClosed = false
    private(set) var isCancelled = false
    /// The cloud voices taken out of the rest of this reply.
    private(set) var demotedEngines: Set<TTSEngine> = []
    /// A cloud voice has been taken out of the rest of this reply.
    var cloudDemoted: Bool { !demotedEngines.isEmpty }
    private var consecutiveCloudFailures: [TTSEngine: Int] = [:]

    init(prefetchDepth: Int = StreamedReplySchedule.defaultPrefetchDepth) {
        self.prefetchDepth = min(max(prefetchDepth, 1), Self.maximumPrefetchDepth)
    }

    // MARK: - Reading

    /// Sentences played to their end.
    var heardCount: Int { items.filter { $0.state == .heard }.count }

    /// The first sentence that was not played to its end, or nil when every sentence was.
    var firstUnheardIndex: Int? { items.first { $0.state != .heard }?.index }

    /// Every sentence from the first unheard one on — what a replay should start from.
    var unheardTexts: [String] {
        guard let first = firstUnheardIndex else { return [] }
        return items[first...].map(\.text)
    }

    /// The reply is over: no more input will come and every sentence has ended one way or another.
    var isComplete: Bool {
        (isClosed || isCancelled) && items.allSatisfy { $0.state.isTerminal }
    }

    /// The sentence currently playing.
    var playingIndex: Int? {
        items.first { if case .playing = $0.state { return true } else { return false } }?.index
    }

    // MARK: - Events

    mutating func enqueue(_ text: String, chain: [TTSEngine]) -> [Action] {
        guard !isClosed, !isCancelled else { return [] }
        items.append(Item(index: items.count, text: text, chain: chain, state: .waiting))
        return advance()
    }

    /// No more sentences.
    mutating func close() -> [Action] {
        isClosed = true
        return advance()
    }

    mutating func synthesisSucceeded(index: Int, engine: TTSEngine) -> [Action] {
        guard !isCancelled, items.indices.contains(index),
              items[index].state == .synthesizing(engine) else { return [] }
        if engine.isCloud { consecutiveCloudFailures[engine] = 0 }
        items[index].state = .ready(engine)
        return advance()
    }

    /// `appendingText` is a line to add to the sentence for the next engine to say with it.
    mutating func synthesisFailed(index: Int, engine: TTSEngine, appendingText: String? = nil) -> [Action] {
        guard !isCancelled, items.indices.contains(index),
              items[index].state == .synthesizing(engine) else { return [] }
        if engine.isCloud {
            let failures = (consecutiveCloudFailures[engine] ?? 0) + 1
            consecutiveCloudFailures[engine] = failures
            if failures >= Self.cloudFailuresBeforeDemotion { demotedEngines.insert(engine) }
        }
        if let appendingText, !appendingText.isEmpty {
            items[index].text += " " + appendingText
        }
        // The next engine after the one that failed, skipping any this reply has demoted.
        let chain = items[index].chain
        let allowed = effectiveChain(chain)
        let after = chain.firstIndex(of: engine).map { Array(chain[($0 + 1)...]) } ?? []
        if let next = after.first(where: { allowed.contains($0) }) {
            items[index].state = .synthesizing(next)
            return [.synthesize(index: index, engine: next)] + advance()
        }
        items[index].state = .unheard
        return advance()
    }

    /// The playing sentence ended; `completed` when it played to its end.
    mutating func playbackEnded(index: Int, completed: Bool) -> [Action] {
        guard items.indices.contains(index) else { return [] }
        if case .playing = items[index].state {
            items[index].state = completed ? .heard : .unheard
        }
        guard !isCancelled else { return [] }
        return advance()
    }

    /// Drop every sentence that has not played. Returns the indices whose synthesis or playback
    /// was in flight, for the driver to cancel. The sentence playing at the moment of cancellation
    /// is `dropped` too: it was cut short, so it was not heard.
    mutating func cancel() -> [Int] {
        guard !isCancelled else { return [] }
        isCancelled = true
        var inFlight: [Int] = []
        for index in items.indices where !items[index].state.isTerminal {
            switch items[index].state {
            case .synthesizing, .playing: inFlight.append(index)
            default: break
            }
            items[index].state = .dropped
        }
        return inFlight
    }

    // MARK: - Deciding

    /// The chain this reply may still use for a sentence.
    func effectiveChain(_ chain: [TTSEngine]) -> [TTSEngine] {
        guard cloudDemoted else { return chain }
        let demoted = chain.filter { !demotedEngines.contains($0) }
        return demoted.isEmpty ? [.system] : demoted
    }

    private mutating func advance() -> [Action] {
        guard !isCancelled else { return [] }
        var actions: [Action] = []
        playNextIfReady(into: &actions)

        // Keep up to `prefetchDepth` sentences synthesising or synthesised ahead of playback.
        var prefetched = items.filter {
            switch $0.state {
            case .synthesizing, .ready: return true
            default: return false
            }
        }.count
        for index in items.indices where prefetched < prefetchDepth && items[index].state == .waiting {
            guard let engine = effectiveChain(items[index].chain).first else {
                items[index].state = .unheard   // nothing could ever say it
                continue
            }
            items[index].state = .synthesizing(engine)
            actions.append(.synthesize(index: index, engine: engine))
            prefetched += 1
        }

        // A sentence given up on above may have unblocked the next one.
        playNextIfReady(into: &actions)
        return actions
    }

    /// Play the next sentence in order, if it is ready and nothing is playing.
    private mutating func playNextIfReady(into actions: inout [Action]) {
        guard playingIndex == nil,
              let next = items.first(where: { !$0.state.isTerminal }),
              case .ready(let engine) = next.state else { return }
        items[next.index].state = .playing(engine)
        actions.append(.play(index: next.index, engine: engine))
    }
}
