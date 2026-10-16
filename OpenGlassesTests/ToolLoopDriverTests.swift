import XCTest
@testable import OpenGlasses

/// Plan BG P3 — the shared tool-loop driver + dispatcher that replaced the four duplicated provider
/// loops. Exercised here with a synthetic adapter + in-memory history, no network.
@MainActor
final class ToolLoopDriverTests: XCTestCase {

    // MARK: - ToolDispatcher

    func testDispatcherExecutesWellFormedCallAndTracksStatus() async {
        var statuses: [ToolCallStatus] = []
        let dispatcher = ToolDispatcher(
            execute: { name, args, _, _ in .completed("ran \(name) with \(args["x"] ?? "?")") },
            onStatus: { statuses.append($0) }
        )
        let outcome = await dispatcher.dispatch(
            ToolInvocation(id: "1", name: "calc", arguments: ["x": 5])
        )
        XCTAssertTrue(outcome.result.isSuccess)
        XCTAssertNil(outcome.yieldReason)
        XCTAssertEqual(statuses, [.executing("calc"), .completed("calc")])
    }

    func testDispatcherReturnsParseErrorForNilArgumentsWithoutExecuting() async {
        var executed = false
        let dispatcher = ToolDispatcher(
            execute: { _, _, _, _ in executed = true; return .completed("should not run") },
            onStatus: { _ in }
        )
        let outcome = await dispatcher.dispatch(
            ToolInvocation(id: "1", name: "weather", arguments: nil)
        )
        XCTAssertFalse(executed, "Malformed args must not reach the executor")
        guard case .failure(let msg) = outcome.result else { return XCTFail("expected failure") }
        XCTAssertTrue(msg.contains("Could not parse the arguments for 'weather'"))
    }

    func testDispatcherReportsFailureStatus() async {
        var statuses: [ToolCallStatus] = []
        let dispatcher = ToolDispatcher(
            execute: { _, _, _, _ in .failedBeforeExecution(reason: "boom") },
            onStatus: { statuses.append($0) }
        )
        _ = await dispatcher.dispatch(ToolInvocation(id: "1", name: "t", arguments: [:]))
        XCTAssertEqual(statuses, [.executing("t"), .failed("t", "Failed")])
    }

    func testYieldReasonParsedFromSuccessfulYieldCall() {
        let reason = ToolDispatcher.yieldReason(
            name: "yield_to_human",
            result: .success("YIELD_TO_HUMAN: check the stove\nWaiting for you to say \"done\" or \"continue\" when ready.")
        )
        XCTAssertEqual(reason, "check the stove")
    }

    func testYieldReasonNilForOtherTools() {
        XCTAssertNil(ToolDispatcher.yieldReason(name: "calc", result: .success("YIELD_TO_HUMAN: x")))
        XCTAssertNil(ToolDispatcher.yieldReason(name: "yield_to_human", result: .failure("nope")))
        XCTAssertNil(ToolDispatcher.yieldReason(name: "yield_to_human", result: .success("plain text")))
    }

    // MARK: - runToolLoop

    /// Builds an adapter whose `performTurn` replays a scripted list of turns and records history +
    /// dispatched calls into shared arrays for assertions.
    private func makeScriptedAdapter(
        label: String = "Test",
        turns: [AssistantTurn],
        execute: @escaping (String, [String: Any], String?, String?) async -> ToolExecutionOutcome
            = { name, _, _, _ in .completed("ok:\(name)") },
        history: Box<[String]>,
        statuses: Box<[ToolCallStatus]>
    ) -> ProviderLoopAdapter {
        var index = 0
        return ProviderLoopAdapter(
            label: label,
            dispatcher: ToolDispatcher(execute: execute, onStatus: { statuses.value.append($0) }),
            performTurn: {
                defer { index += 1 }
                guard index < turns.count else {
                    // Keep returning tool calls to force the loop to exhaust iterations.
                    return turns.last ?? AssistantTurn(text: "")
                }
                return turns[index]
            },
            appendAssistantToolCall: { _ in history.value.append("assistant:toolcall") },
            appendToolResults: { outcomes in
                history.value.append("results:" + outcomes.map { $0.invocation.name }.joined(separator: ",")) },
            finalize: { turn in history.value.append("final:\(turn.text)"); return turn.text }
        )
    }

    func testLoopReturnsFinalAnswerWithNoTools() async throws {
        let history = Box<[String]>([]), statuses = Box<[ToolCallStatus]>([])
        let adapter = makeScriptedAdapter(
            turns: [AssistantTurn(text: "hello")],
            history: history, statuses: statuses
        )
        let result = try await runToolLoop(maxIterations: 5, adapter: adapter,
                                           setStatus: { statuses.value.append($0) })
        XCTAssertEqual(result, "hello")
        XCTAssertEqual(history.value, ["final:hello"])
        XCTAssertEqual(statuses.value.last, .idle)
    }

    func testLoopDispatchesToolsThenReturnsFinalAnswer() async throws {
        let history = Box<[String]>([]), statuses = Box<[ToolCallStatus]>([])
        let adapter = makeScriptedAdapter(
            turns: [
                AssistantTurn(text: "", toolCalls: [ToolInvocation(id: "1", name: "calc", arguments: [:])]),
                AssistantTurn(text: "done")
            ],
            history: history, statuses: statuses
        )
        let result = try await runToolLoop(maxIterations: 5, adapter: adapter,
                                           setStatus: { statuses.value.append($0) })
        XCTAssertEqual(result, "done")
        XCTAssertEqual(history.value, ["assistant:toolcall", "results:calc", "final:done"])
    }

    func testLoopShortCircuitsOnYield() async throws {
        let history = Box<[String]>([]), statuses = Box<[ToolCallStatus]>([])
        let adapter = makeScriptedAdapter(
            turns: [AssistantTurn(text: "", toolCalls: [
                ToolInvocation(id: "1", name: "yield_to_human", arguments: [:]),
                ToolInvocation(id: "2", name: "never", arguments: [:])
            ])],
            execute: { name, _, _, _ in
                name == "yield_to_human" ? .completed("YIELD_TO_HUMAN: your turn") : .completed("ran")
            },
            history: history, statuses: statuses
        )
        let result = try await runToolLoop(maxIterations: 5, adapter: adapter,
                                           setStatus: { statuses.value.append($0) })
        XCTAssertEqual(result, "your turn")
        // Only the yielding call was dispatched — the second tool never ran. It is still answered:
        // the assistant message names both calls, and a call with no result breaks the next request.
        XCTAssertEqual(history.value, ["assistant:toolcall", "results:yield_to_human,never"])
        XCTAssertEqual(statuses.value.last, .yielded("yield_to_human"))
    }

    /// A yield in the middle of a turn: what ran keeps its result, the yield keeps its own, and
    /// everything after it is answered as not run without being executed.
    func testYieldAnswersEveryCallOfTheTurnAndRunsNothingAfterIt() async throws {
        let history = Box<[String]>([]), statuses = Box<[ToolCallStatus]>([])
        let executed = Box<[String]>([])
        let appended = Box<[ToolDispatchOutcome]>([])
        var served = false
        let adapter = ProviderLoopAdapter(
            label: "Test",
            dispatcher: ToolDispatcher(
                execute: { name, _, _, _ in
                    executed.value.append(name)
                    return name == "yield_to_human" ? .completed("YIELD_TO_HUMAN: your turn") : .completed("ran")
                },
                onStatus: { statuses.value.append($0) }),
            performTurn: {
                XCTAssertFalse(served, "a yield ends the loop; no second request is made")
                served = true
                return AssistantTurn(text: "", toolCalls: [
                    ToolInvocation(id: "1", name: "first", arguments: [:]),
                    ToolInvocation(id: "2", name: "yield_to_human", arguments: [:]),
                    ToolInvocation(id: "3", name: "send_message", arguments: [:]),
                    ToolInvocation(id: "4", name: "last", arguments: [:])
                ])
            },
            appendAssistantToolCall: { _ in history.value.append("assistant:toolcall") },
            appendToolResults: { appended.value.append(contentsOf: $0) },
            finalize: { $0.text })

        let result = try await runToolLoop(maxIterations: 5, adapter: adapter,
                                           setStatus: { statuses.value.append($0) })

        XCTAssertEqual(result, "your turn")
        XCTAssertEqual(executed.value, ["first", "yield_to_human"], "nothing after the yield runs")
        XCTAssertEqual(appended.value.map { $0.invocation.id }, ["1", "2", "3", "4"],
                       "every call the assistant message names has a result")
        XCTAssertEqual(appended.value[0].outcome, .completed("ran"))
        for unrun in appended.value.suffix(2) {
            XCTAssertEqual(unrun.outcome,
                           .failedBeforeExecution(reason: ToolDispatcher.notRunAfterYield(unrun.invocation.name)))
            XCTAssertEqual(unrun.retryDisposition, .safeToRetry, "nothing happened, so it may be asked for again")
            XCTAssertNil(unrun.yieldReason)
        }
    }

    /// The budget is spent but the tools already ran, so the turn is put into words rather than
    /// thrown away as a server failure — and a call the wrap-up asks for is answered, not run.
    func testExhaustedLoopWrapsUpWithoutRunningMoreTools() async throws {
        let history = Box<[String]>([]), statuses = Box<[ToolCallStatus]>([])
        var executed = 0
        // Every turn calls a tool → the loop never reaches a final answer by itself.
        let adapter = makeScriptedAdapter(
            turns: [AssistantTurn(text: "", toolCalls: [ToolInvocation(id: "1", name: "loop", arguments: [:])])],
            execute: { name, _, _, _ in executed += 1; return .completed("ok:\(name)") },
            history: history, statuses: statuses
        )
        let result = try await runToolLoop(maxIterations: 3, adapter: adapter,
                                           setStatus: { statuses.value.append($0) })
        XCTAssertEqual(executed, 3, "dispatched exactly maxIterations times, never in the wrap-up")
        XCTAssertEqual(result, ToolLoopBudget.spokenFallback)
        XCTAssertEqual(history.value.filter { $0.hasPrefix("results:") }.count, 4,
                       "the wrap-up's calls get answers so the history stays well-formed")
        XCTAssertEqual(history.value.last, "final:\(ToolLoopBudget.spokenFallback)")
        XCTAssertEqual(statuses.value.last, .idle)
    }

    func testExhaustedLoopUsesTheWrapUpAnswerWhenItHasOne() async throws {
        let history = Box<[String]>([]), statuses = Box<[ToolCallStatus]>([])
        let call = AssistantTurn(text: "", toolCalls: [ToolInvocation(id: "1", name: "task", arguments: [:])])
        let adapter = makeScriptedAdapter(
            turns: [call, call, AssistantTurn(text: "Closed the ignitor task.")],
            history: history, statuses: statuses
        )
        let result = try await runToolLoop(maxIterations: 2, adapter: adapter,
                                           setStatus: { statuses.value.append($0) })
        XCTAssertEqual(result, "Closed the ignitor task.")
        XCTAssertEqual(history.value.filter { $0.hasPrefix("results:") }.count, 2)
    }

    func testWrapUpCallsAreAnsweredAsNotRun() async throws {
        var appended: [ToolDispatchOutcome] = []
        let call = AssistantTurn(text: "Done so far.", toolCalls: [ToolInvocation(id: "1", name: "task", arguments: [:])])
        let adapter = ProviderLoopAdapter(
            label: "Test",
            dispatcher: ToolDispatcher(execute: { _, _, _, _ in .completed("ok") }, onStatus: { _ in }),
            performTurn: { call },
            appendAssistantToolCall: { _ in },
            appendToolResults: { appended = $0 },
            finalize: { $0.text }
        )
        let result = try await runToolLoop(maxIterations: 1, adapter: adapter, setStatus: { _ in })
        XCTAssertEqual(result, "Done so far.", "the wrap-up's own words are kept")
        XCTAssertEqual(appended.map(\.outcome), [.failedBeforeExecution(reason: ToolLoopBudget.notRun("task"))])
    }
}

/// Reference wrapper so escaping closures can mutate captured test state.
final class Box<T> {
    var value: T
    init(_ value: T) { self.value = value }
}
