import Foundation

/// Plan JM P3 — which recogniser hears *this* room best, as a number rather than an impression.
///
/// The pure core of the developer comparison: word error rate against what the wearer says they
/// actually said, a row per engine, and a session of rows that becomes the table the decision is
/// made from. Nothing here records audio, touches the network or persists anything; the runner
/// (`RecognizerComparisonRunner`) and the screen are the edge.
enum RecognizerComparison {

    /// Every recogniser the comparison can run. Apple Speech appears twice: as dictation uses it
    /// (server-capable) and forced on-device, because the gap between the two is half the question.
    enum Engine: String, CaseIterable, Equatable, Sendable {
        case appleSpeech
        case appleSpeechOnDevice
        case onDevice
        case deepgram
        case openAI

        /// The name in the table and on the screen. Vendor and product names, not copy to translate.
        var displayName: String {
            switch self {
            case .appleSpeech: return "Apple Speech"
            case .appleSpeechOnDevice: return "Apple Speech (on-device)"
            case .onDevice: return "On-device (SenseVoice)"
            case .deepgram: return "Deepgram"
            case .openAI: return "OpenAI"
            }
        }

        /// The cloud provider behind a cloud row, whose gate decides whether anything is sent.
        var cloudProvider: CloudDictationProvider? {
            switch self {
            case .deepgram: return .deepgram
            case .openAI: return .openAI
            case .appleSpeech, .appleSpeechOnDevice, .onDevice: return nil
            }
        }
    }

    // MARK: - Word error rate

    /// One alignment of a hypothesis against the reference.
    struct Score: Equatable, Sendable {
        var substitutions: Int
        var insertions: Int
        var deletions: Int
        var referenceWords: Int

        var errors: Int { substitutions + insertions + deletions }

        /// Errors ÷ reference words. 0 when the two agree (and when both are empty); 1 when the
        /// reference has words and the hypothesis none. A hypothesis against an empty reference is
        /// all insertions and scores 1 — there is no reference length to divide by.
        var rate: Double {
            guard referenceWords > 0 else { return errors == 0 ? 0 : 1 }
            return Double(errors) / Double(referenceWords)
        }
    }

    /// Lowercase, punctuation stripped, whitespace collapsed — so case and punctuation never count
    /// as errors. A hyphen between two letters or digits stays (R-410A, 7X-4420-B), a point between
    /// two digits stays (3.5), a comma between two digits joins them (1,200 → 1200), and an
    /// apostrophe joins its word (don't → dont), the same on both sides.
    static func normalize(_ text: String) -> String {
        let chars = Array(text.lowercased())
        var out = ""
        out.reserveCapacity(chars.count)
        for (i, c) in chars.enumerated() {
            let prev: Character? = i > 0 ? chars[i - 1] : nil
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if c.isLetter || c.isNumber {
                out.append(c)
            } else if c == "-" || c == "\u{2011}" {
                // A hyphen (or a non-breaking one) inside a token stays; anywhere else it is a space.
                if let p = prev, let n = next, isWordChar(p), isWordChar(n) {
                    out.append("-")
                } else {
                    out.append(" ")
                }
            } else if c == "." {
                if let p = prev, let n = next, p.isNumber, n.isNumber { out.append(".") } else { out.append(" ") }
            } else if c == "," {
                if let p = prev, let n = next, p.isNumber, n.isNumber { continue }
                out.append(" ")
            } else if c == "'" || c == "’" {
                continue
            } else {
                out.append(" ")
            }
        }
        return out.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber }

    static func words(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init)
    }

    /// Levenshtein alignment over normalised word tokens, with the substitutions, insertions and
    /// deletions of one minimal alignment counted. Ties prefer a match or substitution, then a
    /// deletion, so the counts are deterministic.
    static func wordErrorRate(reference: String, hypothesis: String) -> Score {
        let ref = words(reference)
        let hyp = words(hypothesis)
        let n = ref.count, m = hyp.count
        if n == 0 || m == 0 {
            return Score(substitutions: 0, insertions: m, deletions: n, referenceWords: n)
        }
        // cost[i][j]: edits to turn ref[..<i] into hyp[..<j].
        var cost = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { cost[i][0] = i }
        for j in 0...m { cost[0][j] = j }
        for i in 1...n {
            for j in 1...m {
                let diagonal = cost[i - 1][j - 1] + (ref[i - 1] == hyp[j - 1] ? 0 : 1)
                cost[i][j] = min(diagonal, cost[i - 1][j] + 1, cost[i][j - 1] + 1)
            }
        }
        var i = n, j = m
        var score = Score(substitutions: 0, insertions: 0, deletions: 0, referenceWords: n)
        while i > 0 || j > 0 {
            if i > 0, j > 0 {
                let same = ref[i - 1] == hyp[j - 1]
                if cost[i][j] == cost[i - 1][j - 1] + (same ? 0 : 1) {
                    if !same { score.substitutions += 1 }
                    i -= 1; j -= 1
                    continue
                }
            }
            if i > 0, cost[i][j] == cost[i - 1][j] + 1 {
                score.deletions += 1
                i -= 1
            } else {
                score.insertions += 1
                j -= 1
            }
        }
        return score
    }

    // MARK: - Rows and the session

    enum Outcome: Equatable, Sendable {
        case transcribed
        /// Nothing was sent: the engine is not configured (a cloud engine not chosen, keyed, or
        /// allowed — HIPAA, an organisation pin, local-only medical mode).
        case notConfigured
        /// The engine ran and failed, with a fixed token (never the error's own text).
        case failed(String)

        var token: String {
            switch self {
            case .transcribed: return "transcribed"
            case .notConfigured: return "notConfigured"
            case .failed(let token): return token
            }
        }
    }

    /// One engine's run on one utterance.
    struct Row: Equatable, Sendable, Identifiable {
        var engine: Engine
        var transcript: String
        var elapsed: TimeInterval
        var outcome: Outcome
        /// What the engine itself said when it failed — for the developer screen only, never a log.
        var message: String? = nil

        var id: Engine { engine }

        /// The score against `reference`, when there is one and the engine produced a transcript.
        func score(against reference: String) -> Score? {
            guard outcome == .transcribed, !RecognizerComparison.words(reference).isEmpty else { return nil }
            return RecognizerComparison.wordErrorRate(reference: reference, hypothesis: transcript)
        }
    }

    /// A row kept in the session, with the utterance it belongs to, what was actually said, and
    /// whether vocabulary hints went to the engines on that run.
    struct Entry: Equatable, Sendable {
        var utterance: Int
        var reference: String
        var hints: Bool
        var row: Row

        var score: Score? { row.score(against: reference) }
    }

    /// Rows across utterances, in memory only. Holds the newest `capacity` rows; the oldest go first.
    struct Session: Equatable, Sendable {
        static let capacity = 50

        private(set) var entries: [Entry] = []
        private(set) var utteranceCount = 0

        var isEmpty: Bool { entries.isEmpty }

        /// Add one utterance's rows, numbered after the last.
        mutating func add(rows: [Row], reference: String, hints: Bool) {
            guard !rows.isEmpty else { return }
            utteranceCount += 1
            for row in rows {
                entries.append(Entry(utterance: utteranceCount, reference: reference, hints: hints, row: row))
            }
            if entries.count > Self.capacity {
                entries.removeFirst(entries.count - Self.capacity)
            }
        }

        mutating func clear() {
            entries.removeAll()
            utteranceCount = 0
        }

        /// Corpus WER per engine, hints on and off apart: total errors ÷ total reference words over
        /// the scored rows.
        func summary() -> [(engine: Engine, hints: Bool, utterances: Int, score: Score)] {
            Engine.allCases.flatMap { engine in [true, false].map { (engine, $0) } }.compactMap { engine, hints in
                let scored = entries.filter { $0.row.engine == engine && $0.hints == hints }.compactMap(\.score)
                guard !scored.isEmpty else { return nil }
                let total = scored.reduce(Score(substitutions: 0, insertions: 0, deletions: 0, referenceWords: 0)) {
                    Score(substitutions: $0.substitutions + $1.substitutions,
                          insertions: $0.insertions + $1.insertions,
                          deletions: $0.deletions + $1.deletions,
                          referenceWords: $0.referenceWords + $1.referenceWords)
                }
                return (engine, hints, scored.count, total)
            }
        }

        /// A plain-text table for pasting: one line per row, then the per-engine summary.
        func table() -> String {
            var lines = ["| # | Engine | Hints | WER % | S/I/D | Seconds | Transcript |",
                         "|---|---|---|---|---|---|---|"]
            for entry in entries {
                let row = entry.row
                let wer: String
                let sid: String
                if let score = entry.score {
                    wer = RecognizerComparison.percent(score.rate)
                    sid = "\(score.substitutions)/\(score.insertions)/\(score.deletions)"
                } else {
                    wer = "—"
                    sid = "—"
                }
                let text: String
                switch row.outcome {
                case .transcribed: text = row.transcript
                case .notConfigured: text = "(not configured)"
                case .failed(let token): text = "(failed: \(token))"
                }
                lines.append("| \(entry.utterance) | \(row.engine.displayName) | \(Self.onOff(entry.hints)) | \(wer) | \(sid) | "
                             + "\(String(format: "%.2f", row.elapsed)) | \(Self.cell(text)) |")
            }
            let summary = summary()
            if !summary.isEmpty {
                lines.append("")
                lines.append("| Engine | Hints | Utterances | WER % |")
                lines.append("|---|---|---|---|")
                for line in summary {
                    lines.append("| \(line.engine.displayName) | \(Self.onOff(line.hints)) | \(line.utterances) | "
                                 + "\(RecognizerComparison.percent(line.score.rate)) |")
                }
            }
            return lines.joined(separator: "\n")
        }

        private static func onOff(_ value: Bool) -> String { value ? "on" : "off" }

        private static func cell(_ text: String) -> String {
            text.replacingOccurrences(of: "|", with: "/")
                .components(separatedBy: .newlines).joined(separator: " ")
        }
    }

    /// "12.5" — one decimal place, no percent sign (the column says so).
    static func percent(_ rate: Double) -> String {
        String(format: "%.1f", rate * 100)
    }
}
