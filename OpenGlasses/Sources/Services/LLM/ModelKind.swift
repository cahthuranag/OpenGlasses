import Foundation

/// What a listed model is for. A provider's model list mixes chat models with speech,
/// transcription, live-voice, image and embedding models, and only a chat model can be the
/// assistant: a speech-only Gemini model chosen as the assistant had every turn refused (support
/// report, 2026-10-29).
enum ModelKind: String, CaseIterable, Equatable, Sendable {
    case chat
    case speech
    case transcription
    case realtime
    case image
    case video
    case music
    case embedding
    case rerank
    case moderation
    case ocr
    /// Recognised as not a conversation model, with no better name (Gemini's `aqa`, a
    /// computer-use model, a list entry that serves no chat method).
    case other

    var isChat: Bool { self == .chat }

    /// The short label a picker shows beside a model that can't be the assistant.
    var label: String {
        switch self {
        case .chat: return String(localized: "Chat")
        case .speech: return String(localized: "Speech output")
        case .transcription: return String(localized: "Transcription")
        case .realtime: return String(localized: "Live voice")
        case .image: return String(localized: "Image generation")
        case .video: return String(localized: "Video generation")
        case .music: return String(localized: "Music generation")
        case .embedding: return String(localized: "Embeddings")
        case .rerank: return String(localized: "Reranking")
        case .moderation: return String(localized: "Safety filter")
        case .ocr: return String(localized: "Text recognition")
        case .other: return String(localized: "Not a chat model")
        }
    }

    /// One sentence saying why such a model can't be the assistant, and what it is for. Nil for chat.
    var assistantWarning: String? {
        switch self {
        case .chat: return nil
        case .speech: return String(localized: "This is a speech model: it reads text aloud and can't answer questions. Choose a chat model for the assistant.")
        case .transcription: return String(localized: "This is a transcription model: it turns speech into text and can't answer questions. Choose a chat model for the assistant.")
        case .realtime: return String(localized: "This is a live voice model: it is for live conversation modes and can't answer here. Choose a chat model for the assistant.")
        case .image: return String(localized: "This is an image model: it makes pictures and can't answer questions. Choose a chat model for the assistant.")
        case .video: return String(localized: "This is a video model: it makes videos and can't answer questions. Choose a chat model for the assistant.")
        case .music: return String(localized: "This is a music model: it makes music and can't answer questions. Choose a chat model for the assistant.")
        case .embedding: return String(localized: "This is an embedding model: it is used for search and can't answer questions. Choose a chat model for the assistant.")
        case .rerank: return String(localized: "This is a reranking model: it orders search results and can't answer questions. Choose a chat model for the assistant.")
        case .moderation: return String(localized: "This is a safety filter: it checks text and can't answer questions. Choose a chat model for the assistant.")
        case .ocr: return String(localized: "This is a text-recognition model: it reads documents and can't answer questions. Choose a chat model for the assistant.")
        case .other: return String(localized: "This isn't a conversation model, so it can't answer as your assistant. Choose a chat model.")
        }
    }
}

extension ModelKind {
    /// The line a saved model's row shows when it can't be the assistant. Nil for chat.
    var savedModelWarning: String? {
        isChat ? nil : String(localized: "\(label) — this model can't answer as your assistant")
    }

    /// What VoiceOver reads for a listed model that can't be chosen as the assistant.
    func spokenUnavailableRow(name: String) -> String {
        String(localized: "\(name), \(label), can't be your assistant")
    }
}

/// What a provider's list says about one model, where it says anything.
struct ModelListMetadata: Equatable, Sendable {
    /// Mistral's `capabilities` flags that are on (`completion_chat`, `audio_speech`, …).
    var capabilities: Set<String>?
    /// OpenRouter's `architecture.output_modalities`, or DeepSeek's `output_modalities`.
    var outputModalities: Set<String>?
    /// Gemini's `supportedGenerationMethods`.
    var generationMethods: Set<String>?

    init(capabilities: Set<String>? = nil, outputModalities: Set<String>? = nil,
         generationMethods: Set<String>? = nil) {
        self.capabilities = capabilities
        self.outputModalities = outputModalities
        self.generationMethods = generationMethods
    }

    /// Read from one row of a provider's list. Fields that are absent stay nil.
    init(row: [String: Any]) {
        if let flags = row["capabilities"] as? [String: Any] {
            capabilities = Set(flags.compactMap { key, value in
                ((value as? Bool) ?? (value as? NSNumber)?.boolValue ?? false) ? key : nil
            })
        }
        let architecture = row["architecture"] as? [String: Any]
        if let modalities = (architecture?["output_modalities"] ?? row["output_modalities"]) as? [String] {
            outputModalities = Set(modalities.map { $0.lowercased() })
        }
        if let methods = row["supportedGenerationMethods"] as? [String] {
            generationMethods = Set(methods)
        }
    }

    static let none = ModelListMetadata()
}

/// Says what a listed model is for, from the list's own field where there is one, then whole
/// words in the id, then a short per-provider table. **Unknown means chat:** a custom server's
/// model that matches nothing is offered as an ordinary chat model, because a wrong label on the
/// wearer's own model is worse than an odd model offered as chat.
///
/// Pure and fixture-tested.
enum ModelKindClassifier {

    static func kind(provider: LLMProvider, id: String,
                     metadata: ModelListMetadata = .none) -> ModelKind {
        if provider == .anthropic || provider == .chatgpt || provider == .appleOnDevice
            || provider == .local {
            // Anthropic's list and the ChatGPT catalog are chat by construction; on-device models
            // are chosen from the app's own list.
            return .chat
        }
        if let decided = fromMetadata(metadata) { return decided }
        let words = Self.words(in: id)
        if let decided = fromProviderRows(provider, words: words) { return decided }
        if let decided = fromSharedWords(words) { return decided }
        // A Gemini entry that serves no chat method is not a chat model, whatever its name.
        if let methods = metadata.generationMethods, !methods.contains("generateContent") {
            return .other
        }
        return .chat
    }

    /// The kind of a model id the wearer typed or saved: the list's own label when the id is in a
    /// list already loaded, else read from the id. Nil for an empty id.
    static func kind(provider: LLMProvider, typedID: String,
                     listed: [ModelFetcher.RemoteModel] = []) -> ModelKind? {
        let id = typedID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        return listed.first(where: { $0.id == id })?.kind ?? kind(provider: provider, id: id)
    }

    /// The id split into lower-case words on `-`, `.`, `_`, `/` and `:`.
    static func words(in id: String) -> [String] {
        id.lowercased()
            .split(whereSeparator: { "-._/: ".contains($0) })
            .map(String.init)
    }

    // MARK: - The list's own field

    /// A kind when the list's own field settles it — chat included, so a model the list says
    /// answers in text is never relabelled by a word in its id (OpenRouter serves
    /// `gpt-4o-audio-preview` as chat). Nil when the field is absent or says nothing either way.
    private static func fromMetadata(_ metadata: ModelListMetadata) -> ModelKind? {
        if let flags = metadata.capabilities {
            if flags.contains("completion_chat") { return .chat }
            if flags.contains("audio_speech") { return .speech }
            if flags.contains("audio_transcription") { return .transcription }
            if flags.contains("ocr") { return .ocr }
            if flags.contains("moderation") { return .moderation }
        }
        if let outputs = metadata.outputModalities, !outputs.isEmpty {
            if outputs.contains("text") { return .chat }
            if outputs.contains("image") { return .image }
            if outputs.contains("video") { return .video }
            if outputs.contains("speech") || outputs.contains("audio") { return .speech }
            if outputs.contains("transcription") { return .transcription }
            if outputs.contains("embeddings") || outputs.contains("embedding") { return .embedding }
            if outputs.contains("rerank") { return .rerank }
            return .other
        }
        if let methods = metadata.generationMethods, !methods.contains("generateContent") {
            if methods.contains("bidiGenerateContent") { return .realtime }
            if methods.contains("embedContent") || methods.contains("batchEmbedContents") { return .embedding }
            // `predict` serves Imagen and Veo; their ids name which.
            return nil
        }
        return nil
    }

    // MARK: - Words in the id

    /// Single words that name a kind wherever they appear as a whole word.
    private static let sharedWords: [String: ModelKind] = [
        "tts": .speech, "orpheus": .speech,
        "whisper": .transcription, "transcribe": .transcription, "asr": .transcription,
        "realtime": .realtime, "live": .realtime,
        "image": .image, "imagen": .image, "dall": .image, "cogview": .image, "imagine": .image,
        "video": .video, "veo": .video, "sora": .video, "hailuo": .video,
        "lyria": .music, "music": .music,
        "embed": .embedding, "embedding": .embedding, "embeddings": .embedding,
        "rerank": .rerank, "reranker": .rerank,
        "moderation": .moderation, "guard": .moderation, "safeguard": .moderation,
        "ocr": .ocr,
        "aqa": .other,
    ]

    /// Two words in a row that name a kind together.
    private static let sharedPairs: [(String, String, ModelKind)] = [
        ("native", "audio", .realtime),
        ("audio", "preview", .realtime),
        ("computer", "use", .other),
    ]

    private static func fromSharedWords(_ words: [String]) -> ModelKind? {
        for (first, second, kind) in sharedPairs {
            if zip(words, words.dropFirst()).contains(where: { $0 == first && $1 == second }) { return kind }
        }
        for word in words {
            if let kind = sharedWords[word] { return kind }
        }
        return nil
    }

    // MARK: - Per-provider rows

    /// Families the shared words miss, where only one provider names them that way.
    private static func fromProviderRows(_ provider: LLMProvider, words: [String]) -> ModelKind? {
        switch provider {
        case .xai:
            // xAI's `/v1/models` mixes voice agents and build models in with chat.
            if words.contains("voice") || words.contains("audio") { return .realtime }
            if words.contains("build") { return .other }
        case .gemini, .geminiVertex:
            if words.contains("robotics") { return .other }
        case .minimax:
            if words.first == "speech" { return .speech }
        case .qwen:
            if words.first.map({ $0.hasPrefix("wan") }) == true { return .video }
        default:
            break
        }
        return nil
    }
}
