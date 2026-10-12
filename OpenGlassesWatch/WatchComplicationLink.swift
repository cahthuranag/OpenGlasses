import Foundation

/// What a tap on a complication asks the watch app to do.
///
/// A complication on a watch face cannot run code: a tap opens the watch app and nothing else, so
/// a `Button(intent:)` there is never pressed. Each complication therefore carries one of these
/// links as its `widgetURL`, and the watch app — the only process on the wrist that can reach the
/// phone — sends the command when it opens. Compiled into the watch app, the watch widget and the
/// phone's unit tests, so the two ends cannot drift.
enum WatchComplicationLink {
    /// Private to the watch: the system hands a `widgetURL` straight to the app that owns the
    /// widget, so this is never registered and never opens from anywhere else.
    static let scheme = "avenkin-watch"
    static let host = "complication"

    /// The phone-side command each complication sends. Raw values are the watch protocol's own
    /// vocabulary (`WatchConnectivityManager.commandToken`).
    enum Command: String, CaseIterable {
        case toggleListen
        case toggleRecord
        case capturePhoto
    }

    static func url(for command: Command) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/" + command.rawValue
        // The three pieces are fixed ASCII, so this cannot fail.
        return components.url!
    }

    /// The command a link names, or nil for anything that is not one of ours.
    static func command(from url: URL) -> Command? {
        guard url.scheme?.lowercased() == scheme, url.host == host else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1 else { return nil }
        return Command(rawValue: parts[0])
    }
}

/// A complication's command, held until the phone can take it.
///
/// A tap usually cold-launches the watch app, and the link arrives before the session with the
/// phone has finished activating. The command waits here for that — briefly. It is never queued
/// for later delivery: a "start listening" that lands minutes after the tap opens a microphone
/// nobody asked for.
struct PendingComplicationCommand: Equatable {
    /// How long a tap stays worth acting on.
    static let lifetime: TimeInterval = 8

    let command: WatchComplicationLink.Command
    let requestedAt: Date

    func isLive(at now: Date) -> Bool {
        let age = now.timeIntervalSince(requestedAt)
        return age >= 0 && age <= Self.lifetime
    }
}

/// The watch's half of a dictated question: the command and the key its text travels under.
///
/// The phone names the same two strings in `WatchDictation`; `WatchComplicationTests` holds the
/// pair together, since the two targets share no code that both could read them from.
enum WatchDictationWire {
    static let command = "askText"
    static let textKey = "text"
}
