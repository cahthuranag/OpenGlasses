import Foundation
import NaturalLanguage

/// Fetches the contextual models for scripts other than Latin, so a manual is searched with its
/// own script's model rather than by its words alone (Plan JY P1, owner decision 6).
///
/// **When.** While My Manuals or Field Assist is in use, the models for the scripts of the phone's
/// languages are asked for when the feature is turned on or its plan starts, and again at launch
/// if one is missing (`prepareForManualsIfInUse`); adding a manual asks for its own script's
/// model (`DocumentStore.scriptModelRequest`, wired at launch to `requestAndWait`). The Documents
/// library, memory and voice skills never ask: they use a model only if it is already here.
///
/// **Never a prerequisite.** A request needs a network connection and may fail. Indexing waits a
/// bounded `waitLimit` for a download already under way, then finishes with the manual searched
/// by its words; when the model lands, `onArrival` re-indexes the vaults onto it
/// (`VaultEmbeddingUpgrade`).
///
/// The download and the readiness check are seams, so the tests drive every path without
/// Apple's assets (the simulator cannot download them).
@MainActor
final class ScriptModelAssets {

    static let shared = ScriptModelAssets()

    /// Whether a script's model is on the phone — its asset, without loading the model.
    var isReady: (EmbeddingScript) -> Bool = { $0 != .latin && NLContextualBackend.hasAssets(for: $0.contextualLanguage) }
    /// Ask for a script's model; true when it is on the phone afterwards.
    var download: (EmbeddingScript) async -> Bool = { await Embedder.prepareAssets(for: $0) }
    /// How long indexing waits for a download already under way before it finishes by words.
    var waitLimit: Duration = .seconds(20)
    /// Called on the main actor when a requested model has landed.
    var onArrival: ((EmbeddingScript) -> Void)?
    /// Whether My Manuals or Field Assist is in use, so the phone's scripts are fetched ahead.
    var manualsInUse: () -> Bool = {
        Config.fieldAssistActive || (PersonalManualLibrary.canManage && Config.myManualsEnabled)
    }
    /// The phone's languages, in order.
    var preferredLanguages: () -> [String] = { Locale.preferredLanguages }

    private var inFlight: [EmbeddingScript: Task<Bool, Never>] = [:]
    /// What the last request for each script ended in, for the diagnostics.
    private(set) var lastFailed: Set<EmbeddingScript> = []

    /// Whether a download for `script` is under way.
    func isDownloading(_ script: EmbeddingScript) -> Bool { inFlight[script] != nil }

    /// Start fetching a script's model unless it is here or already on its way. Latin is not
    /// this coordinator's: its asset is Field Assist's (`VaultEmbeddingUpgrade.prepareAssets`).
    func request(_ script: EmbeddingScript) {
        guard script != .latin, inFlight[script] == nil, !isReady(script) else { return }
        PrivacyLog.store(.ragDocuments, .modelRequested, detail: PrivacyToken(script.rawValue))
        let started = Date()
        inFlight[script] = Task { @MainActor [weak self] in
            guard let self else { return false }
            let landed = await self.download(script)
            self.inFlight[script] = nil
            if landed { self.lastFailed.remove(script) } else { self.lastFailed.insert(script) }
            PrivacyLog.store(.ragDocuments, landed ? .modelArrived : .modelUnavailable,
                             detail: PrivacyToken(script.rawValue),
                             durationMs: Int(Date().timeIntervalSince(started) * 1000))
            if landed { self.onArrival?(script) }
            return landed
        }
    }

    /// Wait up to `waitLimit` for a download of `script` already under way; true when its model
    /// is on the phone afterwards. Returns at once when nothing is downloading. Polls rather than
    /// awaiting the download, so a slow download never holds indexing past the limit.
    @discardableResult
    func waitIfDownloading(_ script: EmbeddingScript) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: waitLimit)
        let step = min(Duration.milliseconds(250), waitLimit)
        while inFlight[script] != nil, clock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: step)
        }
        return isReady(script)
    }

    /// What adding a manual does: ask for its script's model if it is missing, then wait the
    /// bounded time for it.
    func requestAndWait(_ script: EmbeddingScript) async {
        guard script != .latin, !isReady(script) else { return }
        request(script)
        await waitIfDownloading(script)
    }

    /// Ask for the models of the phone's languages' scripts that are missing, while My Manuals or
    /// Field Assist is in use. Idempotent: a model here or on its way is not asked for again.
    func prepareForManualsIfInUse() {
        guard manualsInUse() else { return }
        for script in EmbeddingScript.aheadOfTime(preferredLanguages: preferredLanguages()) {
            request(script)
        }
    }
}
