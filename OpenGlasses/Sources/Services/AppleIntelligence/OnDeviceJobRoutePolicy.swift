import Foundation

/// Where a Field Assist job turn goes when the active configuration is Apple's on-device model.
///
/// The on-device model has a 4,096-token window shared by its instructions, its tool definitions
/// and the answer. A job turn carries the job and the manual passages — tens of thousands of
/// characters on the cloud turns of a field day — and a single manual lookup returns about three
/// thousand. It cannot hold them: a field report showed "open a new job" overflow the window on a
/// brand-new conversation. So while a job is open (paused included), or the turn opens, closes or
/// switches one, the turn goes to the first other configuration that can serve it — a cloud model
/// or a downloaded local model, in the wearer's fallback order — and the wearer is told once per
/// process why.
///
/// When nothing else is configured, or the offline hand-off deliberately put the turn on the phone,
/// the turn stays on the device and gets a compact job summary instead of the manuals
/// (`AppleOnDeviceInstructions`).
///
/// Pure: the caller works out which configurations are usable and whether the turn is about a job.
enum OnDeviceJobRoutePolicy {

    /// A configuration the turn could be handed to, in the order it should be tried.
    struct Alternative: Equatable {
        let id: String
        /// The name the wearer gave it, for the one spoken sentence.
        let name: String
        let provider: LLMProvider
        /// The model id, a public catalog name, for the privacy log.
        let model: String
    }

    struct Inputs: Equatable {
        /// A job is open, paused or not.
        var jobOpen: Bool
        /// The turn itself opens, closes or switches a job ("open a new job").
        var jobTurn: Bool
        var activeProvider: LLMProvider
        /// Usable configurations other than the active one, in preference order.
        var alternatives: [Alternative]
        /// The offline hand-off chose the on-device brain for this turn.
        var offlineHandoff: Bool
        /// The sentence has already been said in this process.
        var announcedThisProcess: Bool
    }

    enum StayReason: String, Equatable {
        /// The phone is offline and the hand-off put the turn here on purpose.
        case offlineHandoff
        /// No other configuration can take the turn.
        case noAlternative
    }

    enum Route: Equatable {
        /// Not a job turn on the on-device model: nothing changes.
        case unchanged
        /// Hand the turn to `to`; `announce` says whether to speak the sentence first.
        case handOff(to: Alternative, announce: Bool)
        /// Stay on the device, with the compact job summary.
        case stayOnDevice(StayReason)
    }

    static func decide(_ inputs: Inputs) -> Route {
        guard inputs.activeProvider == .appleOnDevice, inputs.jobOpen || inputs.jobTurn else {
            return .unchanged
        }
        if inputs.offlineHandoff { return .stayOnDevice(.offlineHandoff) }
        guard let target = inputs.alternatives.first(where: { isEligible($0.provider) }) else {
            return .stayOnDevice(.noAlternative)
        }
        return .handOff(to: target, announce: !inputs.announcedThisProcess)
    }

    /// A cloud model or a downloaded local model — anything but Apple's on-device model again.
    static func isEligible(_ provider: LLMProvider) -> Bool {
        provider != .appleOnDevice
    }

    /// The wearer's fallback order first, then the remaining saved configurations — the cascade's
    /// own order — keeping only the usable ones that are not the active configuration.
    static func orderedAlternatives(activeId: String, saved: [ModelConfig], fallbackOrder: [String],
                                    isUsable: (ModelConfig) -> Bool) -> [Alternative] {
        let byId = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = [activeId]
        var ordered: [ModelConfig] = []
        for id in fallbackOrder + saved.map(\.id) {
            guard !seen.contains(id), let config = byId[id] else { continue }
            seen.insert(id)
            ordered.append(config)
        }
        return ordered
            .filter { isEligible($0.llmProvider) && isUsable($0) }
            .map { Alternative(id: $0.id, name: $0.name, provider: $0.llmProvider, model: $0.model) }
    }

    /// The sentence said before the first handed-off answer in a process.
    static func notice(modelName: String) -> String {
        let name = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Using \(name.isEmpty ? "another model" : name) for this job; Apple Intelligence can't hold the manuals."
    }
}
