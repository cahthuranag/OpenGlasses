import Foundation

/// One of the speech-recognition engines OpenGlasses can transcribe dictation through.
enum ASREngine: String, CaseIterable, Equatable {
    /// On-device SenseVoice (sherpa-onnx / ONNX-CPU) — offline, private, runs backgrounded.
    case onDevice
    /// Apple `SFSpeechRecognizer` — the historical engine; may use server-side recognition.
    case appleSpeech
    /// Deepgram's streaming recogniser (Plan JM P2): the question's audio streams to Deepgram with
    /// the wearer's own key while they speak. Chosen only, never picked by `.auto`.
    case deepgram
    /// OpenAI's transcription endpoint (Plan JM P2): the whole question is uploaded when the turn
    /// ends, with the OpenAI API key. Chosen only, never picked by `.auto`.
    case openAI

    /// Whether this engine sends the wearer's audio to a third-party recogniser the wearer chose.
    /// Apple Speech is not counted here: it is the platform's recogniser, not a vendor the app
    /// adds, and has been the default since the first build.
    var isCloud: Bool {
        switch self {
        case .deepgram, .openAI: return true
        case .onDevice, .appleSpeech: return false
        }
    }

    /// How audio reaches the engine during a turn — the three shapes `TranscriptionService` runs.
    enum CaptureShape: Equatable {
        /// Buffers stream into `SFSpeechAudioBufferRecognitionRequest`; partials arrive as spoken.
        case appleStreaming
        /// The utterance's PCM is accumulated and decoded (or uploaded) once, when the turn ends.
        case wholeUtterance
        /// Buffers stream to a cloud socket; partials and finals arrive as spoken.
        case cloudStreaming
    }

    var captureShape: CaptureShape {
        switch self {
        case .appleSpeech: return .appleStreaming
        case .onDevice, .openAI: return .wholeUtterance
        case .deepgram: return .cloudStreaming
        }
    }
}

/// The user's ASR-engine preference (Additional Capabilities #8 — the on-device SenseVoice tier;
/// Plan JM P2 — the two cloud recognisers). Persisted as a raw string in
/// `Config.asrEnginePreference`; drives `ASREngineSelector`.
enum ASREnginePreference: String, CaseIterable, Identifiable, Codable {
    /// Best available given what's configured — Apple Speech today, on-device once its model is present.
    case auto
    /// Prefer the on-device (offline, private) engine; fall back to Apple Speech when unavailable.
    case onDevice
    /// Always use Apple Speech.
    case appleSpeech
    /// Deepgram's cloud recogniser with the wearer's own key. Off under HIPAA.
    case deepgram
    /// OpenAI's transcription endpoint with the OpenAI API key. Off under HIPAA.
    case openAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return String(localized: "Auto")
        case .onDevice: return String(localized: "On-Device (SenseVoice)")
        case .appleSpeech: return "Apple Speech"
        case .deepgram: return String(localized: "Cloud (Deepgram)")
        case .openAI: return String(localized: "Cloud (OpenAI)")
        }
    }

    var detail: String {
        switch self {
        case .auto: return String(localized: "Use Apple Speech, switching to the offline on-device recognizer once its model is downloaded.")
        case .onDevice: return String(localized: "Prefer the offline, private on-device recognizer. Falls back to Apple Speech when its model isn't installed.")
        case .appleSpeech: return String(localized: "Always use Apple's speech recognizer.")
        case .deepgram: return String(localized: "The audio of each question you ask streams to Deepgram while you speak, charged to your own Deepgram key. Not available in HIPAA mode. Without a connection, recognition falls back to Auto for that question.")
        case .openAI: return String(localized: "The audio of each question you ask is uploaded to OpenAI when you stop speaking, charged to your own OpenAI API key, so the answer starts after the upload. It uses the OpenAI API key, not a ChatGPT sign-in, which can't transcribe. Not available in HIPAA mode. Without a connection, recognition falls back to Auto for that question.")
        }
    }

    /// The cloud engine this preference chooses, or nil for an on-phone/Apple preference.
    var cloudEngine: ASREngine? {
        switch self {
        case .deepgram: return .deepgram
        case .openAI: return .openAI
        case .auto, .onDevice, .appleSpeech: return nil
        }
    }

    var isCloud: Bool { cloudEngine != nil }
}

/// Pure engine-selection policy for speech recognition (Additional Capabilities #8, Plan JM P2).
/// Given what's available (Apple Speech authorized, the SenseVoice model present + binary compiled
/// in, each cloud recogniser keyed and allowed), the user's preference, whether we're online and
/// whether HIPAA mode is on, it produces the ordered fallback chain the transcriber walks. No SDK /
/// audio state is touched — a value computation, fully unit-testable headlessly.
///
/// Mirrors `TTSEngineSelector`: `.appleSpeech` is the guaranteed terminal (always available, no model),
/// and an explicit `.onDevice` preference never silently falls back to the cloud-capable Apple engine
/// when offline.
///
/// **Cloud engines (Plan JM P2).** A chosen cloud engine goes first only when it is ready and the
/// phone is online; the rest of the chain is the `.auto` chain, so a cloud preference offline (or
/// unkeyed, or pinned off) behaves exactly as `.auto` for that turn. `.auto` never picks a cloud
/// engine. Under HIPAA the cloud cases are stripped from the chain whatever the readiness says —
/// the caller already folds HIPAA into `deepgramReady`/`openAIReady`, and this is the second lock.
enum ASREngineSelector {

    /// What each engine can do right now. The caller folds the live signals into these booleans.
    struct Availability: Equatable {
        /// Apple `SFSpeechRecognizer` is available + authorized.
        var appleSpeechReady: Bool
        /// SenseVoice model files present **and** the sherpa-onnx binary is compiled in.
        var onDeviceReady: Bool
        /// Network is reachable (Apple Speech can use server-side recognition; on-device never needs it).
        var online: Bool
        /// Deepgram dictation may run: keyed, chosen, not pinned off by an organisation, not HIPAA
        /// (`CloudDictationGate`). Online-ness is `online`, not folded in here.
        var deepgramReady: Bool
        /// OpenAI dictation may run, on the same terms as `deepgramReady`.
        var openAIReady: Bool

        init(appleSpeechReady: Bool, onDeviceReady: Bool, online: Bool,
             deepgramReady: Bool = false, openAIReady: Bool = false) {
            self.appleSpeechReady = appleSpeechReady
            self.onDeviceReady = onDeviceReady
            self.online = online
            self.deepgramReady = deepgramReady
            self.openAIReady = openAIReady
        }

        func isReady(_ engine: ASREngine) -> Bool {
            switch engine {
            case .appleSpeech: return appleSpeechReady
            case .onDevice: return onDeviceReady
            case .deepgram: return deepgramReady
            case .openAI: return openAIReady
            }
        }
    }

    /// Ordered engines to try, best-first. The first element is the chosen engine; the rest are the
    /// fallback order. `.appleSpeech` is appended as the guaranteed terminal whenever it's ready.
    static func chain(preference: ASREnginePreference, availability: Availability, hipaa: Bool) -> [ASREngine] {
        // The on-phone chain. A cloud preference contributes its fallback as `.auto` would.
        let local = localChain(preference: preference.isCloud ? .auto : preference, availability: availability)

        var result = local
        if let cloud = preference.cloudEngine, !hipaa, availability.online, availability.isReady(cloud) {
            result.insert(cloud, at: 0)
        }
        // Belt and braces: whatever readiness said, HIPAA mode never lets a cloud engine into the chain.
        if hipaa { result.removeAll(where: \.isCloud) }
        return result
    }

    /// The single engine to transcribe through — the head of `chain(...)`, or nil when nothing is
    /// available (e.g. Apple Speech unauthorized and no on-device model).
    static func select(preference: ASREnginePreference, availability: Availability, hipaa: Bool) -> ASREngine? {
        chain(preference: preference, availability: availability, hipaa: hipaa).first
    }

    /// The pre-P2 chain over Apple Speech and the on-device engine. Never contains a cloud engine.
    private static func localChain(preference: ASREnginePreference, availability: Availability) -> [ASREngine] {
        var order: [ASREngine]
        switch preference {
        case .auto, .appleSpeech, .deepgram, .openAI:
            // Cloud-capable Apple Speech first (today's behaviour); on-device is the offline fallback.
            order = [.appleSpeech, .onDevice]
        case .onDevice:
            // Explicit offline/private choice: on-device first, Apple Speech only as a last resort.
            order = [.onDevice, .appleSpeech]
        }

        // For `.auto`, prefer the **on-device** engine when we're offline — Apple Speech may need the
        // network and degrade, while SenseVoice is fully local.
        if preference == .auto, !availability.online, availability.onDeviceReady,
           let appleIdx = order.firstIndex(of: .appleSpeech),
           let onDeviceIdx = order.firstIndex(of: .onDevice),
           onDeviceIdx > appleIdx {
            order.remove(at: onDeviceIdx)
            order.insert(.onDevice, at: appleIdx)
        }

        var result = order.filter { availability.isReady($0) }
        // Apple Speech is the terminal fallback when it's available; if neither is, the chain is empty
        // and the caller reports an error (no recognizer at all is a real, surfaced failure).
        if availability.appleSpeechReady, !result.contains(.appleSpeech) {
            result.append(.appleSpeech)
        }
        return result
    }
}
