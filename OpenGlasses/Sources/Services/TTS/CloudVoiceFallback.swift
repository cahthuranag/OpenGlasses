import Foundation

/// Why a cloud voice turned a request away, when the wearer is the only one who can fix it.
///
/// A network blip or a server error falls through to the next engine and is nobody's business.
/// These two are different: they repeat on every reply until the wearer tops up or corrects the
/// key, and until now the only sign was a worse voice with no explanation (support report,
/// 2026-10-05 — the wearer went looking for a voice setting to undo a change they never made).
enum CloudVoiceRejection: String, Equatable, CaseIterable {
    /// The account has no credit left. ElevenLabs sends this as a 401 whose body names
    /// `quota_exceeded`, so the status alone cannot tell it from a bad key; OpenAI sends a 429
    /// naming `insufficient_quota`, which the status alone would take for a rate limit.
    case outOfCredit
    /// The key, or the voice chosen for it, was refused.
    case refused

    /// What an out-of-credit body says, lower-cased, for each cloud voice. A short list on
    /// purpose: a phrase that also turns up in an ordinary error would latch the voice off.
    static let outOfCreditMarkers = [
        "quota_exceeded",              // ElevenLabs
        "insufficient_quota",          // OpenAI
        "used all available credits",  // xAI
        "spending limit"               // xAI
    ]

    static func classify(statusCode: Int, body: String) -> CloudVoiceRejection? {
        let lowered = body.lowercased()
        if outOfCreditMarkers.contains(where: { lowered.contains($0) }) { return .outOfCredit }
        switch statusCode {
        case 401, 402, 403: return .refused
        default: return nil
        }
    }
}

/// A rejection and the cloud voice that sent it: what the wearer is told, naming the vendor.
struct CloudVoiceNotice: Equatable {
    let engine: TTSEngine
    let rejection: CloudVoiceRejection
    /// The engine taking over is another cloud voice (Auto with more than one set up), so saying
    /// "the built-in voice" would be untrue.
    var nextIsCloud = false

    private var vendor: String { engine.vendorName ?? "The cloud voice" }

    /// Said once, after the reply it interrupted. The path is spoken as words: a wearer who is not
    /// looking at the phone has to be able to find it later from memory.
    ///
    /// The ElevenLabs lines are the ones this notice has always said, kept as their own strings so
    /// their translations still apply; the other vendors share one wording with the name filled in.
    var spokenLine: String {
        if nextIsCloud {
            switch rejection {
            case .outOfCredit:
                return String(localized: "By the way, your \(vendor) credit has run out, so I'm using another voice. You can change voices in the app's Settings, under Connections, then Services and Integrations.")
            case .refused:
                return String(localized: "By the way, \(vendor) refused the voice request, so I'm using another voice. Check the key and voice in the app's Settings, under Connections, then Services and Integrations.")
            }
        }
        switch (engine, rejection) {
        case (.elevenLabs, .outOfCredit):
            return String(localized: "By the way, your ElevenLabs credit has run out, so I'm using the built-in voice. You can change voices in the app's Settings, under Connections, then Services and Integrations.")
        case (.elevenLabs, .refused):
            return String(localized: "By the way, ElevenLabs refused the voice request, so I'm using the built-in voice. Check the key and voice in the app's Settings, under Connections, then Services and Integrations.")
        case (_, .outOfCredit):
            return String(localized: "By the way, your \(vendor) credit has run out, so I'm using the built-in voice. You can change voices in the app's Settings, under Connections, then Services and Integrations.")
        case (_, .refused):
            return String(localized: "By the way, \(vendor) refused the voice request, so I'm using the built-in voice. Check the key and voice in the app's Settings, under Connections, then Services and Integrations.")
        }
    }

    /// The same news for the screen.
    var banner: String {
        if nextIsCloud {
            switch rejection {
            case .outOfCredit:
                return String(localized: "\(vendor) is out of credit, so replies use another voice. Change voices in Settings › Connections › Services & Integrations.")
            case .refused:
                return String(localized: "\(vendor) refused the voice request, so replies use another voice. Check the key and voice in Settings › Connections › Services & Integrations.")
            }
        }
        switch (engine, rejection) {
        case (.elevenLabs, .outOfCredit):
            return String(localized: "ElevenLabs is out of credit, so replies use the built-in voice. Change voices in Settings › Connections › Services & Integrations.")
        case (.elevenLabs, .refused):
            return String(localized: "ElevenLabs refused the voice request, so replies use the built-in voice. Check the key and voice in Settings › Connections › Services & Integrations.")
        case (_, .outOfCredit):
            return String(localized: "\(vendor) is out of credit, so replies use the built-in voice. Change voices in Settings › Connections › Services & Integrations.")
        case (_, .refused):
            return String(localized: "\(vendor) refused the voice request, so replies use the built-in voice. Check the key and voice in Settings › Connections › Services & Integrations.")
        }
    }

    /// What the announcer remembers. ElevenLabs keeps the bare reason it has always stored, so an
    /// episode announced before the other cloud voices existed is not announced a second time.
    var announcementToken: String {
        engine == .elevenLabs ? rejection.rawValue : "\(engine.rawValue).\(rejection.rawValue)"
    }

    /// The cloud voice an announcement token belongs to.
    static func engine(ofToken token: String) -> TTSEngine? {
        guard let dot = token.firstIndex(of: ".") else {
            return CloudVoiceRejection(rawValue: token) != nil ? .elevenLabs : nil
        }
        return TTSEngine(rawValue: String(token[..<dot]))
    }
}

/// When a rejection is worth saying aloud. Once per episode, not once per launch: a wearer who has
/// decided to live with the built-in voice should not be told again every morning. The episode ends
/// when that cloud voice speaks again or the wearer changes its key or voice.
///
/// Each cloud voice has its own episode. With Auto and two cloud voices set up, one refusing every
/// reply and the next speaking, the second's success must not make the first's refusal news again.
struct CloudVoiceFallbackAnnouncer {
    static let defaultsKey = "cloudVoiceFallbackAnnounced"

    var defaults: UserDefaults = .standard

    /// The tokens already said. Read from a list, or from the single string stored before there
    /// was more than one cloud voice.
    private var announced: [String] {
        if let list = defaults.stringArray(forKey: Self.defaultsKey) { return list }
        return defaults.string(forKey: Self.defaultsKey).map { [$0] } ?? []
    }

    private func store(_ tokens: [String]) {
        if tokens.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            defaults.set(tokens, forKey: Self.defaultsKey)
        }
    }

    /// The line to add to this utterance, or nil when this rejection has been said already or the
    /// utterance is not one to append to.
    ///
    /// - Parameter plainReply: an ordinary reply at neutral urgency. An alert or a warning is
    ///   never lengthened with housekeeping, and stays unannounced until the next ordinary reply.
    mutating func lineToSpeak(for notice: CloudVoiceNotice, plainReply: Bool) -> String? {
        let token = notice.announcementToken
        let said = announced
        guard plainReply, !said.contains(token) else { return nil }
        // One reason per cloud voice: a different reason from the same vendor is news.
        store(said.filter { CloudVoiceNotice.engine(ofToken: $0) != notice.engine } + [token])
        return notice.spokenLine
    }

    /// That cloud voice is working, or its key or voice has changed: its next rejection is news.
    /// With no engine, every cloud voice's episode ends.
    func episodeEnded(for engine: TTSEngine? = nil) {
        guard let engine else {
            defaults.removeObject(forKey: Self.defaultsKey)
            return
        }
        let said = announced
        let kept = said.filter { CloudVoiceNotice.engine(ofToken: $0) != engine }
        if kept.count != said.count { store(kept) }
    }
}
