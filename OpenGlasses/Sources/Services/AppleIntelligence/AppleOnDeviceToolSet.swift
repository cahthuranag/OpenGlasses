import Foundation

/// Which native tools Apple's on-device model is offered, and in what order (Plan JD P0).
///
/// The model calls tools through the framework's own constrained decoding, so unlike the MLX path
/// it never has to be taught a markup protocol — but it shares a 4,096-token window between
/// instructions, every tool definition and the conversation. So the set is a **priority list cut
/// to a token budget**, not everything the registry has: what a Field Assist job needs comes first
/// when Field Assist is on, then the everyday on-device essentials, then web search, each kept
/// only while its estimated definition still fits.
///
/// Pure. The registry has already removed disabled and HIPAA-excluded tools from `registered`;
/// this only chooses among what is left.
enum AppleOnDeviceToolSet {

    /// The Field Assist tools a job is run from by voice, in priority order. `field_session` leads
    /// because "open a new job" is the first thing a technician says, and it is the one tool the
    /// Field Assist screen's own prompts depend on.
    ///
    /// `manual_lookup` is not offered: one lookup returns about three thousand characters, which
    /// this window cannot hold beside its instructions and tools. A job turn goes to another model
    /// when one is configured (`OnDeviceJobRoutePolicy`); when none is, the instructions say that
    /// manual answers need a cloud model (`AppleOnDeviceInstructions`).
    ///
    /// `table_lookup` is (Plan JJ P1, decision 7): one cell with its headers, notes and page is a
    /// few hundred characters, which the window holds.
    static let fieldAssistPriority: [String] = [
        "field_session", "reading", "evidence", "deliver_report",
        "parts_request", "van_stock", "table_lookup",
    ]

    /// The everyday tools after the field set: the local MLX path's safe set, which each resolve
    /// their own inputs (`where_am_i`, `get_weather` read the location service directly), so the
    /// model is never asked to supply what it does not have.
    static let everydayPriority: [String] = [
        "get_datetime", "get_weather", "where_am_i", "calendar", "reminder", "set_timer",
        "set_alarm", "calculate", "flashlight", "brightness", "music_control", "step_count",
        "health_summary", "device_info", "activity",
    ]

    /// Last, because it needs the network and its answer is the longest: a real search call,
    /// which the uncertainty re-ask (Plan BI) only ever approximated on this backend.
    static let networkPriority: [String] = ["web_search"]

    /// The token budget for every tool definition together. The lean on-device prompt is around a
    /// thousand tokens and the conversation needs room to breathe inside 4,096, so the definitions
    /// get a little more than a third of the window.
    static let definitionBudgetTokens = 1_500

    struct Candidate: Equatable {
        let name: String
        let estimatedTokens: Int
    }

    /// The priority order for a turn: Field Assist tools first when the feature is on (whether or
    /// not a job is open — opening one is the point), then the everyday set, then the network set.
    /// Only names in `registered` survive. An offline-handoff turn drops what needs the network.
    static func priorityNames(registered: [String], fieldAssistActive: Bool,
                              offlineHandoff: Bool, libraryHasManuals: Bool = false) -> [String] {
        let available = Set(registered)
        var ordered: [String] = []
        if fieldAssistActive { ordered += fieldAssistPriority }
        if !fieldAssistActive && libraryHasManuals { ordered += ["table_lookup", "manual_figure", "show_source"] }
        ordered += everydayPriority
        ordered += networkPriority
        let present = ordered.filter(available.contains)
        return offlineHandoff ? OfflineToolPolicy.offlineNames(present) : present
    }

    /// `candidates` in their given order, kept while the running total stays within `budget`. A
    /// candidate that does not fit is skipped, not the rest: a later, smaller tool may still fit.
    static func fit(_ candidates: [Candidate], budget: Int = definitionBudgetTokens) -> [Candidate] {
        var used = 0
        var kept: [Candidate] = []
        for candidate in candidates where used + candidate.estimatedTokens <= budget {
            used += candidate.estimatedTokens
            kept.append(candidate)
        }
        return kept
    }
}
