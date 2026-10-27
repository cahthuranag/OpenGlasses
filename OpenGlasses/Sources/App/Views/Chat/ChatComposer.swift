import SwiftUI
import PhotosUI

/// Reusable chat composer: text input + optional photo attach (vision-gated) + send.
/// Used by the Chat tab (`ChatThreadView`) and, wrapped, by the Voice tab's inline chat input.
/// Owns its own draft/attachment state; the host decides what `onSend` does.
struct ChatComposer: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.appAccent) private var accent

    var placeholder: String = String(localized: "Type a message...")
    /// Focus the text field as soon as the composer appears.
    var autoFocus: Bool = false
    /// When set, a mic button is shown leading; tapping it runs this (e.g. switch back to voice).
    var voiceAction: (() -> Void)? = nil
    /// The leading button's glyph and spoken label — the mic by default; the transcript review
    /// shows a cancel instead (Plan JM P1).
    var voiceActionSymbol: String = "mic.fill"
    var voiceActionLabel: LocalizedStringKey = "Switch to voice input"
    /// Text the field starts with — a transcript under review (Plan JM P1).
    var initialText: String? = nil
    /// Called once, the first time the wearer touches or changes the seeded text.
    var onEdit: (() -> Void)? = nil
    /// The auto-send countdown drawn round the send button, while a transcript is under review.
    var review: PendingTranscript? = nil
    /// When set, a paperclip button is shown; tapping it runs this (e.g. open a file importer).
    var onAttachDocument: (() -> Void)? = nil
    /// Called with the trimmed text and optional image data when the user sends.
    var onSend: (String, Data?) -> Void

    @State private var messageText = ""
    @State private var attachedImage: UIImage?
    @State private var attachedImageData: Data?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var didSeedText = false
    @State private var didReportEdit = false
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The drawn glass circle keeps its shipped diameter; `tapTarget` is the
    /// hit area laid around it, so a 36pt button is still a 44pt target.
    @ScaledMetric(relativeTo: .body) private var glassCircle: CGFloat = 36
    @ScaledMetric(relativeTo: .body) private var tapTarget: CGFloat = 44
    @ScaledMetric(relativeTo: .title) private var sendGlyph: CGFloat = 32

    private var visionEnabled: Bool { Config.hasVisionCapableModel }
    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !appState.isProcessing
    }

    var body: some View {
        VStack(spacing: 8) {
            if let image = attachedImage { attachmentPreview(image) }
            if let review, reduceMotion { countdownCaption(review) }
            inputRow
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .onAppear {
            if let initialText, !didSeedText {
                didSeedText = true
                messageText = initialText
            }
            if autoFocus { isTextFieldFocused = true }
        }
        .onChange(of: messageText) { _, newValue in
            guard didSeedText, let initialText, newValue != initialText else { return }
            reportEdit()
        }
        .onChange(of: isTextFieldFocused) { _, focused in
            if focused, initialText != nil { reportEdit() }
        }
    }

    private func reportEdit() {
        guard !didReportEdit else { return }
        didReportEdit = true
        onEdit?()
    }

    /// Reduce Motion: a plain caption instead of the moving ring.
    private func countdownCaption(_ review: PendingTranscript) -> some View {
        TimelineView(.periodic(from: review.startedAt, by: 1)) { context in
            Group {
                if case .counting(let remaining) = review.state(at: context.date) {
                    Text("Sending in \(Int(remaining.rounded(.up))) s")
                } else if review.isHeld {
                    Text("Tap send when it's right")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
    }

    /// The countdown ring round the send button: a thin accent stroke that fills as the send nears.
    @ViewBuilder
    private var countdownRing: some View {
        if let review, !reduceMotion, !review.isHeld {
            TimelineView(.animation) { context in
                Circle()
                    .trim(from: 0, to: review.countdown.progress(
                        at: context.date.timeIntervalSince(review.startedAt)))
                    .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: sendGlyph + 6, height: sendGlyph + 6)
            }
            .accessibilityHidden(true)
        }
    }

    /// What VoiceOver hears on the send button while a transcript waits.
    private func sendAccessibilityValue(at date: Date) -> String {
        guard let review else { return "" }
        if case .counting(let remaining) = review.state(at: date) {
            return String(localized: "Sends by itself in \(Int(remaining.rounded(.up))) seconds")
        }
        return ""
    }

    private func attachmentPreview(_ image: UIImage) -> some View {
        HStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    Button {
                        attachedImage = nil
                        attachedImageData = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                            .frame(width: tapTarget, height: tapTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Remove attached photo")
                    // The glyph keeps the corner it was drawn on: the offset is
                    // half the (now 44pt) target minus the inset it used to sit at.
                    .offset(x: tapTarget / 2 - 2, y: -(tapTarget / 2 - 2)),
                    alignment: .topTrailing
                )
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            // Keyboard dismiss — only while editing.
            if isTextFieldFocused {
                Button {
                    isTextFieldFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color(.label))
                        .frame(width: glassCircle, height: glassCircle)
                        .glassEffect(in: .circle)
                        .frame(width: tapTarget, height: tapTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Dismiss keyboard")
                .transition(.opacity)
            }

            // Optional voice button (e.g. switch back to voice input).
            if let voiceAction {
                Button {
                    voiceAction()
                } label: {
                    Image(systemName: voiceActionSymbol)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color(.label))
                        .frame(width: glassCircle, height: glassCircle)
                        .glassEffect(in: .circle)
                        .frame(width: tapTarget, height: tapTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(voiceActionLabel)
            }

            // Document attach (Chat tab only).
            if let onAttachDocument {
                Button(action: onAttachDocument) {
                    Image(systemName: "paperclip")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color(.label))
                        .frame(width: glassCircle, height: glassCircle)
                        .glassEffect(in: .circle)
                        .frame(width: tapTarget, height: tapTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Attach document")
            }

            // Photo attach (only for vision-capable models).
            if visionEnabled {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color(.label))
                        .frame(width: glassCircle, height: glassCircle)
                        .glassEffect(in: .circle)
                        .frame(width: tapTarget, height: tapTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Attach photo")
                .onChange(of: selectedPhotoItem) { _, item in
                    Task {
                        guard let item else { return }
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            attachedImageData = data
                            attachedImage = UIImage(data: data)
                        }
                        selectedPhotoItem = nil
                    }
                }
            }

            TextField(placeholder, text: $messageText, axis: .vertical)
                .accessibilityIdentifier("chat-message-composer")
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isTextFieldFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(in: .rect(cornerRadius: 20))
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: sendGlyph))
                    .foregroundStyle(canSend ? accent : Color(.tertiaryLabel))
                    .overlay { countdownRing }
                    .frame(minWidth: tapTarget, minHeight: tapTarget)
                    .contentShape(Rectangle())
            }
            .disabled(!canSend)
            .accessibilityLabel("Send message")
            .accessibilityValue(sendAccessibilityValue(at: Date()))
        }
        .padding(.horizontal, 16)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isTextFieldFocused)
    }

    private func send() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !appState.isProcessing else { return }
        let image = attachedImageData
        didReportEdit = true   // clearing the field after a send is not an edit
        messageText = ""
        attachedImage = nil
        attachedImageData = nil
        onSend(text, image)
    }
}
