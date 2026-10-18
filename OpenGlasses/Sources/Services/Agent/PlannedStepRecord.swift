import Foundation

/// A `Codable` projection of one `AgentStep`, so a plan run can be written down (Plan IW).
///
/// `AgentStep` itself stays non-`Codable`: its `args` bag is JSON-shaped `[String: Any]` and may
/// carry the wearer's words (a message body, a search query). The record keeps only what the trail
/// needs — which tool, which of its actions, and the planner's one-line reason.
struct PlannedStepRecord: Codable, Equatable, Sendable {
    static let rationaleLength = 200

    let tool: String
    /// The step's `action` argument, lower-cased and trimmed, when it has one.
    let actionKey: String?
    let rationale: String

    init(tool: String, actionKey: String?, rationale: String) {
        self.tool = tool
        let key = actionKey?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.actionKey = (key?.isEmpty ?? true) ? nil : key
        self.rationale = ActivityEntry.clamp(rationale, to: Self.rationaleLength)
    }

    init(_ step: AgentStep) {
        self.init(tool: step.tool, actionKey: step.args["action"] as? String, rationale: step.rationale)
    }
}

extension AgentStep {
    /// What a plan run records about this step; never its arguments.
    var record: PlannedStepRecord { PlannedStepRecord(self) }
}
