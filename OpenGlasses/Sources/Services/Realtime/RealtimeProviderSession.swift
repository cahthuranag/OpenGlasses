import Foundation
import UIKit

/// Normalized provider interface used by the common coordinator. Gemini retains its tested
/// resumption/model-retirement protocol code, while using the same ordered socket transport.
@MainActor
final class RealtimeProviderSession {
    let model: RealtimeModelConfig
    private let gemini: GeminiLiveService?
    private let json: RealtimeJSONSessionService?
    var onAudioReceived: ((Data) -> Void)?
    var onTurnComplete: (() -> Void)?
    var onInterrupted: (() -> Void)?
    var onDisconnected: ((String?) -> Void)?
    var onInputTranscription: ((String) -> Void)?
    /// The wearer started speaking, as the server's voice activity detection heard it (Plan HY P1:
    /// idle activity). JSON protocols report a speech-start; Gemini Live reports the barge-in it
    /// causes (`interrupted`), which is the only speech-start that wire carries.
    var onUserSpeechStarted: (() -> Void)?
    var onOutputTranscription: ((String) -> Void)?
    var onReconnected: (() -> Void)?
    var onReconnectExhausted: (() -> Void)?
    var onToolCall: ((GeminiToolCall) -> Void)?
    var onToolCallCancellation: ((GeminiToolCallCancellation) -> Void)?
    var onOperationRejected: ((String) -> Void)?
    var playedAudioMilliseconds: (() -> Int)? {
        didSet { json?.playedAudioMilliseconds = playedAudioMilliseconds }
    }
    var connectionState: RealtimeConnectionState { gemini?.connectionState ?? json?.connectionState ?? .disconnected }
    var isModelSpeaking: Bool { gemini?.isModelSpeaking ?? json?.isModelSpeaking ?? false }
    var isUserSpeaking: Bool { json?.isUserSpeaking ?? false }
    var reconnecting: Bool { gemini?.reconnecting ?? json?.reconnecting ?? false }
    var hasResumptionHandle: Bool { gemini?.hasResumptionHandle ?? false }
    var lastConnectResumedContext: Bool { gemini?.lastConnectResumedContext ?? false }
    var videoFramesSent: Int { gemini?.videoFramesSent ?? 0 }
    var lastCloseReason: String? { gemini?.lastCloseReason }
    var inputTranscriptionIsDelta: Bool { gemini != nil }
    var hasSentAudio: Bool { json?.hasSentAudio ?? true }

    init(model: RealtimeModelConfig) {
        self.model = model
        if model.profile == .geminiLiveV1 { gemini = GeminiLiveService(); json = nil }
        else { gemini = nil; json = RealtimeJSONSessionService() }
        gemini?.configureConnection(model)
        gemini?.onAudioReceived = { [weak self] in self?.onAudioReceived?($0) }
        gemini?.onTurnComplete = { [weak self] in self?.onTurnComplete?() }
        gemini?.onInterrupted = { [weak self] in self?.onUserSpeechStarted?(); self?.onInterrupted?() }
        gemini?.onDisconnected = { [weak self] in self?.onDisconnected?($0) }
        gemini?.onInputTranscription = { [weak self] in self?.onInputTranscription?($0) }
        gemini?.onOutputTranscription = { [weak self] in self?.onOutputTranscription?($0) }
        gemini?.onReconnected = { [weak self] in self?.onReconnected?() }
        gemini?.onReconnectExhausted = { [weak self] in self?.onReconnectExhausted?() }
        gemini?.onToolCall = { [weak self] in self?.onToolCall?($0) }
        gemini?.onToolCallCancellation = { [weak self] in self?.onToolCallCancellation?($0) }
        json?.onAudioReceived = { [weak self] in self?.onAudioReceived?($0) }
        json?.onTurnComplete = { [weak self] in self?.onTurnComplete?() }
        json?.onInterrupted = { [weak self] in self?.onInterrupted?() }
        json?.onDisconnected = { [weak self] in self?.onDisconnected?($0) }
        json?.onInputTranscription = { [weak self] in self?.onInputTranscription?($0) }
        json?.onUserSpeechStarted = { [weak self] in self?.onUserSpeechStarted?() }
        json?.onOutputTranscription = { [weak self] in self?.onOutputTranscription?($0) }
        json?.onReconnected = { [weak self] in self?.onReconnected?() }
        json?.onReconnectExhausted = { [weak self] in self?.onReconnectExhausted?() }
        json?.onOperationRejected = { [weak self] in self?.onOperationRejected?($0) }
        json?.onToolCall = { [weak self] call in
            guard let self else { return }
            let args = call.argumentsJSON.data(using: .utf8).flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            } ?? [:]
            if let batch = GeminiToolCall(json: ["toolCall": ["functionCalls": [["id": call.callId, "name": call.name, "args": args]]]]) {
                self.onToolCall?(batch)
            }
        }
    }
    func configure(systemInstruction: String, toolDeclarations: [[String: Any]], recoveredContext: String? = nil) {
        let ready = connectionState == .ready
        gemini?.configure(systemInstruction: systemInstruction, toolDeclarations: toolDeclarations)
        json?.configure(model: model, systemInstruction: systemInstruction,
                        toolDeclarations: ToolDeclarations.openAIRealtimeTools(declarations: toolDeclarations))
        if ready {
            json?.updateConfiguration()
            if let recoveredContext, !recoveredContext.isEmpty {
                gemini?.sendText(recoveredContext, completeTurn: false)
            }
        }
    }
    func connect() async -> Bool {
        if let gemini { return await gemini.connect() }
        return await json?.connect() ?? false
    }
    func disconnect() { gemini?.disconnect(); json?.disconnect() }
    func sendAudio(data: Data) { gemini?.sendAudio(data: data); json?.sendAudio(data: data) }
    func setMuted(_ muted: Bool) { json?.setMuted(muted) }
    func cancelResponse() { json?.cancelResponse() }
    func sendVideoFrame(image: UIImage) { gemini?.sendVideoFrame(image: image); json?.sendImage(image: image) }
    func sendHighResImage(jpegData: Data) { gemini?.sendHighResImage(jpegData: jpegData); json?.sendHighResImage(jpegData: jpegData) }
    func sendText(_ text: String, completeTurn: Bool) { gemini?.sendText(text, completeTurn: completeTurn); json?.sendText(text, completeTurn: completeTurn) }
    func updateContext(_ text: String, key: String) {
        gemini?.sendText(text, completeTurn: false)
        json?.updateContext(text, key: key)
    }
    func speakText(_ text: String) { json?.speakText(text) }
    func sendToolResponse(_ response: [String: Any]) {
        if let gemini { gemini.sendToolResponse(response); return }
        guard let toolResponse = response["toolResponse"] as? [String: Any],
              let functions = toolResponse["functionResponses"] as? [[String: Any]] else { return }
        for function in functions {
            guard let id = function["id"] as? String, let output = function["response"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: output),
                  let text = String(data: data, encoding: .utf8) else { continue }
            json?.sendToolResult(id: id, output: text)
        }
    }
}
