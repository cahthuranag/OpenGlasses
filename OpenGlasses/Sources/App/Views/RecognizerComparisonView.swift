import SwiftUI

/// Developer → Compare recognisers (Plan JM P3): the kept question through every recogniser, one
/// at a time, each scored by word error rate against what the wearer says they said. A thin view
/// over `RecognizerComparisonRunner`; the scoring is `RecognizerComparison`.
struct RecognizerComparisonView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var transcription: TranscriptionService
    @ObservedObject private var runner: RecognizerComparisonRunner
    @Environment(\.appAccent) private var accent
    @AppStorage("recognizerComparisonEnabled") private var keepEnabled = false

    /// The runner, and with it the session, lives as long as the app does — leaving the screen
    /// keeps the table — and nowhere else: nothing is written.
    @MainActor private static var sharedRunner: RecognizerComparisonRunner?

    init(appState: AppState) {
        self.appState = appState
        _transcription = ObservedObject(wrappedValue: appState.transcriptionService)
        let runner = Self.sharedRunner
            ?? RecognizerComparisonRunner.live(onDeviceEngine: appState.transcriptionService.onDeviceRecognizer)
        Self.sharedRunner = runner
        _runner = ObservedObject(wrappedValue: runner)
    }

    var body: some View {
        OGScrollPage {
            OGNotice(
                text: "Runs the last question through every recogniser, one at a time. Type what you actually said to score each one by word error rate. Nothing on this screen is saved.",
                systemImage: "waveform"
            )
            keptSection
            referenceSection
            resultsSection
            sessionSection
        }
        .textSelection(.enabled)
        .tint(accent)
        .navigationTitle("Compare recognisers")
    }

    // MARK: - The kept question

    private var keptSection: some View {
        OGSection(header: "Last question") {
            if let utterance = transcription.lastUtterance {
                OGRow("Length", icon: "waveform", showsChevron: false) {
                    OGRowValue(verbatim: String(format: "%.1f s", utterance.duration))
                }
                OGDivider()
                OGRow("Kept at", icon: "clock", showsChevron: false) {
                    OGRowValue(verbatim: utterance.capturedAt.formatted(date: .omitted, time: .standard))
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No question kept yet")
                        .font(.body)
                    Text(keepEnabled
                         ? "Keeping is on. Ask a question and it appears here."
                         : "Keeping is off. Turn on \u{201C}Keep the last question for recogniser comparison\u{201D} in the Developer panel, then ask a question.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - The reference and the run

    private var referenceSection: some View {
        VStack(spacing: 12) {
            OGSection(header: "What you actually said") {
                TextField("What you actually said", text: $runner.reference, axis: .vertical)
                    .lineLimit(2...6)
                    .autocorrectionDisabled()
                    .padding(16)
                OGDivider()
                OGRow("Pass vocabulary hints", isOn: $runner.useHints, icon: "text.book.closed")
            }
            Button {
                guard let utterance = transcription.lastUtterance else { return }
                let vocabulary = runner.useHints ? appState.dictationVocabulary() : []
                Task { await runner.run(utterance, vocabulary: vocabulary) }
            } label: {
                if runner.isRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Running…")
                    }
                } else {
                    Text("Run")
                }
            }
            .buttonStyle(.ogProminent)
            .disabled(transcription.lastUtterance == nil || runner.isRunning)
        }
    }

    // MARK: - Results

    private var resultsSection: some View {
        OGSection(
            header: "Results",
            footer: "A cloud recogniser runs only when it is the one chosen under Recognizer, with its key saved, and never under HIPAA or an organisation's pin. Otherwise its row says Not configured and nothing is sent."
        ) {
            if runner.rows.isEmpty && !runner.isRunning {
                Text("Run the comparison to see each recogniser's transcript here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(runner.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { OGDivider() }
                    resultRow(row)
                }
                if let running = runner.running {
                    if !runner.rows.isEmpty { OGDivider() }
                    HStack(spacing: 8) {
                        Text(verbatim: running.displayName)
                            .font(.body.weight(.semibold))
                        Spacer()
                        ProgressView()
                    }
                    .padding(16)
                }
            }
        }
    }

    private func resultRow(_ row: RecognizerComparison.Row) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: row.engine.displayName)
                    .font(.body.weight(.semibold))
                Spacer()
                if row.outcome != .notConfigured {
                    Text(verbatim: String(format: "%.2f s", row.elapsed))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            switch row.outcome {
            case .transcribed:
                Text(verbatim: row.transcript.isEmpty ? "—" : row.transcript)
                    .font(.callout)
                if let score = row.score(against: runner.reference) {
                    Text(verbatim: "WER \(RecognizerComparison.percent(score.rate))% · "
                         + "S \(score.substitutions) · I \(score.insertions) · D \(score.deletions)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(accent)
                }
            case .notConfigured:
                Text("Not configured")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .failed(let token):
                Text("Failed")
                    .font(.callout)
                    .foregroundStyle(.red)
                Text(verbatim: row.message ?? token)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Session

    private var sessionSection: some View {
        OGSection(
            header: "Session",
            footer: "Each question you add becomes rows in one table, scored against what you typed for it. Kept in memory until the app quits; the newest 50 rows are kept."
        ) {
            Button {
                runner.addToSession()
            } label: {
                OGRow("Add to session", icon: "plus.circle", showsChevron: false) {
                    OGRowValue(verbatim: "\(runner.session.utteranceCount) · \(runner.session.entries.count)")
                }
            }
            .buttonStyle(.plain)
            .disabled(runner.rows.isEmpty || runner.addedToSession || runner.isRunning)
            OGDivider()
            Button {
                UIPasteboard.general.string = runner.session.table()
            } label: {
                OGRow("Copy table", icon: "doc.on.doc", mutedIcon: true, showsChevron: false) {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
            .disabled(runner.session.isEmpty)
            OGDivider()
            Button {
                runner.clearSession()
            } label: {
                OGRow("Clear session", icon: "trash", mutedIcon: true, showsChevron: false) {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
            .disabled(runner.session.isEmpty)
        }
    }
}
