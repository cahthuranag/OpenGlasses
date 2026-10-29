import XCTest
@testable import OpenGlasses

/// What a listed model is for, across providers (support report 2026-10-29: a speech-only Gemini
/// model was chosen as the assistant). List rows are built from each provider's documented shape;
/// ids are the documented families, and nothing here ran against a live key.
final class ModelKindClassifierTests: XCTestCase {

    private func kind(_ provider: LLMProvider, _ id: String,
                      _ metadata: ModelListMetadata = .none) -> ModelKind {
        ModelKindClassifier.kind(provider: provider, id: id, metadata: metadata)
    }

    // MARK: - Words in the id

    func testOpenAIFamiliesAreLabelledByTheirIds() {
        let rows: [(String, ModelKind)] = [
            ("gpt-5", .chat), ("gpt-4o-mini", .chat), ("o3-mini", .chat), ("chatgpt-4o-latest", .chat),
            ("tts-1", .speech), ("tts-1-hd", .speech), ("gpt-4o-mini-tts", .speech),
            ("whisper-1", .transcription), ("gpt-4o-transcribe", .transcription),
            ("gpt-realtime", .realtime), ("gpt-4o-realtime-preview", .realtime),
            ("gpt-4o-audio-preview", .realtime),
            ("gpt-image-1", .image), ("dall-e-3", .image),
            ("sora-2", .video),
            ("text-embedding-3-small", .embedding),
            ("omni-moderation-latest", .moderation),
            ("computer-use-preview", .other),
        ]
        for (id, expected) in rows { XCTAssertEqual(kind(.openai, id), expected, id) }
    }

    func testGeminiFamiliesAreLabelledByTheirIds() {
        let rows: [(String, ModelKind)] = [
            ("gemini-3.8-flash", .chat), ("gemini-3.5-flash-lite", .chat), ("gemma-3-27b-it", .chat),
            ("gemini-flash-latest", .chat),
            ("gemini-3.8-flash-tts", .speech), ("gemini-2.5-pro-preview-tts", .speech),
            ("gemini-2.5-flash-native-audio-latest", .realtime), ("gemini-2.0-flash-live-001", .realtime),
            ("gemini-2.5-flash-image", .image), ("imagen-4.0-generate-001", .image),
            ("veo-3.0-generate-001", .video), ("lyria-realtime-exp", .music),
            ("gemini-embedding-001", .embedding), ("aqa", .other),
            ("gemini-2.5-computer-use-preview", .other), ("gemini-robotics-er-1.5-preview", .other),
        ]
        for (id, expected) in rows { XCTAssertEqual(kind(.gemini, id), expected, id) }
    }

    func testGroqAndXAIFamiliesAreLabelledByTheirIds() {
        XCTAssertEqual(kind(.groq, "qwen/qwen3.8-27b"), .chat)
        XCTAssertEqual(kind(.groq, "openai/gpt-oss-120b"), .chat)
        XCTAssertEqual(kind(.groq, "whisper-large-v3-turbo"), .transcription)
        XCTAssertEqual(kind(.groq, "canopylabs/orpheus-v1-english"), .speech)
        XCTAssertEqual(kind(.groq, "meta-llama/llama-prompt-guard-2-22m"), .moderation)
        XCTAssertEqual(kind(.groq, "openai/gpt-oss-safeguard-20b"), .moderation)

        XCTAssertEqual(kind(.xai, "grok-4.7"), .chat)
        XCTAssertEqual(kind(.xai, "grok-code-fast-1"), .chat)
        XCTAssertEqual(kind(.xai, "grok-imagine-image"), .image)
        XCTAssertEqual(kind(.xai, "grok-voice"), .realtime)
        XCTAssertEqual(kind(.xai, "grok-build"), .other)
    }

    func testPerProviderRowsOnlyApplyToTheirProvider() {
        XCTAssertEqual(kind(.minimax, "speech-2.6-hd"), .speech)
        XCTAssertEqual(kind(.minimax, "MiniMax-M2.7"), .chat)
        XCTAssertEqual(kind(.qwen, "wan2.2-t2v-plus"), .video)
        // The same words under another provider are not read that way.
        XCTAssertEqual(kind(.custom, "speech-2.6-hd"), .chat)
        XCTAssertEqual(kind(.custom, "grok-build"), .chat)
    }

    /// Whole words, never substrings: a name that merely contains a kind's letters stays chat.
    func testOnlyWholeWordsCount() {
        for id in ["imaginary-model", "embedded-chat-7b", "livestock-advisor", "guardian-13b",
                   "deliver-3b", "attstts-x"] {
            XCTAssertEqual(kind(.custom, id), .chat, id)
        }
    }

    /// Unknown means chat, so a custom server's own model is never labelled away.
    func testUnknownIdsAreChat() {
        for id in ["llama3.2:latest", "my-finetune-v2", "qwen2.5-coder:14b", "mistral-small-3.2"] {
            XCTAssertEqual(kind(.custom, id), .chat, id)
        }
    }

    func testListsThatAreChatByConstructionAreChat() {
        XCTAssertEqual(kind(.anthropic, "claude-sonnet-5"), .chat)
        XCTAssertEqual(kind(.chatgpt, "gpt-5.5-tts-imaginary"), .chat)
    }

    // MARK: - The list's own field

    func testMistralCapabilitiesDecide() {
        let chat = ModelListMetadata(row: ["capabilities": ["completion_chat": true, "audio_speech": false]])
        XCTAssertEqual(kind(.mistral, "voxtral-small-latest", chat), .chat)
        let speech = ModelListMetadata(row: ["capabilities": ["completion_chat": false, "audio_speech": true]])
        XCTAssertEqual(kind(.mistral, "voxtral-tts-imaginary", speech), .speech)
        let ocr = ModelListMetadata(row: ["capabilities": ["completion_chat": false, "ocr": true]])
        XCTAssertEqual(kind(.mistral, "mistral-ocr-latest", ocr), .ocr)
        // No flag decides it: the id does.
        let none = ModelListMetadata(row: ["capabilities": ["completion_chat": false]])
        XCTAssertEqual(kind(.mistral, "mistral-embed", none), .embedding)
    }

    /// OpenRouter's output modalities settle it, chat included: a model that answers in text is
    /// never relabelled by a word in its id.
    func testOutputModalitiesDecide() {
        let text = ModelListMetadata(row: ["architecture": ["output_modalities": ["text"]]])
        XCTAssertEqual(kind(.openrouter, "openai/gpt-4o-audio-preview", text), .chat)
        let image = ModelListMetadata(row: ["architecture": ["output_modalities": ["image"]]])
        XCTAssertEqual(kind(.openrouter, "vendor/painter-1", image), .image)
        let speech = ModelListMetadata(row: ["architecture": ["output_modalities": ["speech"]]])
        XCTAssertEqual(kind(.openrouter, "vendor/narrator-1", speech), .speech)
        // DeepSeek puts the field at the top level.
        let deepseek = ModelListMetadata(row: ["output_modalities": ["text"]])
        XCTAssertEqual(kind(.deepseek, "deepseek-flash", deepseek), .chat)
    }

    func testGeminiMethodsDecideWhenThereIsNoChatMethod() {
        let live = ModelListMetadata(row: ["supportedGenerationMethods": ["bidiGenerateContent"]])
        XCTAssertEqual(kind(.gemini, "gemini-imaginary-preview", live), .realtime)
        let embed = ModelListMetadata(row: ["supportedGenerationMethods": ["embedContent", "countTokens"]])
        XCTAssertEqual(kind(.gemini, "text-embedding-004", embed), .embedding)
        let predict = ModelListMetadata(row: ["supportedGenerationMethods": ["predict"]])
        XCTAssertEqual(kind(.gemini, "imagen-4.0-generate-001", predict), .image)
        XCTAssertEqual(kind(.gemini, "gemini-unnamed-predictor", predict), .other)
        // A speech model lists the chat method too: the id decides.
        let tts = ModelListMetadata(row: ["supportedGenerationMethods": ["generateContent", "countTokens"]])
        XCTAssertEqual(kind(.gemini, "gemini-3.8-flash-tts", tts), .speech)
        XCTAssertEqual(kind(.gemini, "gemini-3.8-flash", tts), .chat)
    }

    // MARK: - The lists as the pickers receive them

    func testTheGeminiListKeepsEveryModelLabelled() {
        let rows: [[String: Any]] = [
            ["name": "models/gemini-3.8-flash", "displayName": "Gemini 3.8 Flash",
             "supportedGenerationMethods": ["generateContent"]],
            ["name": "models/gemini-3.8-flash-tts", "displayName": "Gemini 3.8 Flash TTS",
             "supportedGenerationMethods": ["generateContent"]],
            ["name": "models/gemini-embedding-001", "supportedGenerationMethods": ["embedContent"]],
        ]
        let models = ModelFetcher.geminiModels(rows)
        XCTAssertEqual(models.map(\.id), ["gemini-3.8-flash", "gemini-3.8-flash-tts", "gemini-embedding-001"])
        XCTAssertEqual(models.map(\.kind), [.chat, .speech, .embedding])
    }

    func testAnOpenAIShapedListIsLabelledPerProvider() {
        let rows: [[String: Any]] = [["id": "gpt-5"], ["id": "tts-1"], ["id": "whisper-1"], ["object": "list"]]
        let models = ModelFetcher.openAICompatibleModels(rows, provider: .openai)
        XCTAssertEqual(models.map(\.id), ["gpt-5", "tts-1", "whisper-1"])
        XCTAssertEqual(models.map(\.kind), [.chat, .speech, .transcription])
    }

    /// A list that leads with a speech or embedding model never starts the wearer on it.
    func testThePickerStartsOnAChatModel() {
        let models = [
            ModelFetcher.RemoteModel(id: "aaa-tts", name: "aaa-tts", kind: .speech),
            ModelFetcher.RemoteModel(id: "gpt-5", name: "gpt-5"),
            ModelFetcher.RemoteModel(id: "gpt-4o", name: "gpt-4o"),
        ]
        XCTAssertEqual(ModelFetcher.initialChoice(in: models, preferring: ["gpt-4o"]), "gpt-4o")
        XCTAssertEqual(ModelFetcher.initialChoice(in: models, preferring: ["absent"]), "gpt-5")
        XCTAssertEqual(ModelFetcher.initialChoice(in: models, preferring: ["aaa-tts"]), "gpt-5")
        let withDefault = models + [ModelFetcher.RemoteModel(id: "picked", name: "picked", isDefault: true)]
        XCTAssertEqual(ModelFetcher.initialChoice(in: withDefault, preferring: ["gpt-4o"]), "picked")
        XCTAssertNil(ModelFetcher.initialChoice(in: [models[0]], preferring: []))
    }

    // MARK: - Typed and saved ids

    func testATypedIdTakesTheListsLabelThenItsOwnWords() {
        let listed = [ModelFetcher.RemoteModel(id: "vendor/narrator-1", name: "Narrator", kind: .speech)]
        XCTAssertEqual(ModelClassifierTyped.kind(.openrouter, " vendor/narrator-1 ", listed), .speech)
        XCTAssertEqual(ModelClassifierTyped.kind(.gemini, "gemini-3.8-flash-tts", []), .speech)
        XCTAssertEqual(ModelClassifierTyped.kind(.groq, "qwen/qwen3.8-27b", []), .chat)
        XCTAssertNil(ModelClassifierTyped.kind(.groq, " \n", []))
    }

    func testEveryKindThatCantAnswerSaysSoAndChatSaysNothing() {
        for kind in ModelKind.allCases {
            if kind.isChat {
                XCTAssertNil(kind.assistantWarning)
                XCTAssertNil(kind.savedModelWarning)
            } else {
                XCTAssertTrue(kind.assistantWarning?.contains("Choose a chat model") ?? false, kind.rawValue)
                XCTAssertTrue(kind.savedModelWarning?.contains(kind.label) ?? false, kind.rawValue)
                XCTAssertTrue(kind.spokenUnavailableRow(name: "X").contains("can't be your assistant"), kind.rawValue)
            }
            XCTAssertFalse(kind.label.isEmpty)
        }
    }
}

/// The typed-id entry point, named so the assertions above read in one line.
private enum ModelClassifierTyped {
    static func kind(_ provider: LLMProvider, _ id: String, _ listed: [ModelFetcher.RemoteModel]) -> ModelKind? {
        ModelKindClassifier.kind(provider: provider, typedID: id, listed: listed)
    }
}
