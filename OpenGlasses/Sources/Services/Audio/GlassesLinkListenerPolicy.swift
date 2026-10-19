import AVFoundation

/// How the idle wake-word listener rides out the glasses' link going down and coming back.
///
/// Device-traced on a tester's locked iPhone (iOS 27.2, build 520, idle mic *Same as Microphone*):
/// the glasses' data link dropped in a pocket, the app stopped the listener for it ("glasses out
/// of use"), and with no audio running iOS suspended the app and let its session go. The link came
/// back a minute or two later, the reconnect hook re-tuned the session — `setCategory` then
/// `setActive` — and from the background iOS refused it with `cannotInterruptOthers`; the three
/// listen attempts after it failed on a dead session, and nothing listened until the app was
/// brought to the front. Five times in one afternoon, read by the wearer as "locked for more than
/// five minutes and the wake word no longer works".
///
/// Two rules follow, both pure so every row is a test:
///
/// - **A link drop keeps the listener** when one is wanted. The route has already moved to the
///   phone's own mic (or will, with the hands-free port gone); the engine rebuilds itself on the
///   new format and keeps the session active, which is what keeps the app awake. Nothing about a
///   link drop is a reason to open the microphone that was closed — a listener nobody asked for
///   stays stopped.
/// - **A link return in the background never re-tunes a live session.** The idle hands-free
///   shape is already mixable with both Bluetooth options, so the returned port only has to be
///   *preferred* again (`setPreferredInput`, allowed from the background) and the listener
///   restarted on it. In the foreground the re-tune works and is kept, and a session with no
///   route at all (iOS let it go) has nothing to keep: the re-tune is attempted as before, since
///   it does succeed inside the grace after a hand-back.
enum GlassesLinkListenerPolicy {

    /// What the idle listener does when the glasses' link (or their audio route) goes away.
    enum OnLinkLoss: Equatable {
        /// Nothing was listening by the wearer's choice: leave it so.
        case stop
        /// Keep the listener up on whatever input remains — the phone's mic — so the session
        /// stays active and the app stays awake for the reconnect.
        case continueOnRemainingInput
    }

    static func onLinkLoss(listenerWanted: Bool) -> OnLinkLoss {
        listenerWanted ? .continueOnRemainingInput : .stop
    }

    /// How the listener takes the glasses back when their link or audio route returns.
    enum OnLinkReturn: Equatable {
        /// Re-tune the session onto the plan's mic (`setCategory` → `setActive`) and restart.
        case reconfigure
        /// The session is live and may not be re-tuned from here: prefer the plan's port on it
        /// as it is and restart the listener.
        case keepSession
    }

    static func onLinkReturn(appInForeground: Bool, sessionHasRoute: Bool) -> OnLinkReturn {
        if appInForeground { return .reconfigure }
        return sessionHasRoute ? .keepSession : .reconfigure
    }
}

/// The name of a route-change reason, for a log.
///
/// `String(describing:)` on the imported `AVAudioSession.RouteChangeReason` yields
/// "AVAudioSessionRouteChangeReason(rawValue: 2)", which the token vocabulary rejects — every
/// route change in a support report read `detail=unnamed`, and the one question such a trace is
/// read for (did the device go away, or did the category change?) could not be answered.
enum RouteChangeReasonName {
    static func token(_ reason: AVAudioSession.RouteChangeReason) -> String {
        switch reason {
        case .unknown: return "unknown"
        case .newDeviceAvailable: return "newDeviceAvailable"
        case .oldDeviceUnavailable: return "oldDeviceUnavailable"
        case .categoryChange: return "categoryChange"
        case .override: return "override"
        case .wakeFromSleep: return "wakeFromSleep"
        case .noSuitableRouteForCategory: return "noSuitableRouteForCategory"
        case .routeConfigurationChange: return "routeConfigurationChange"
        @unknown default: return "other"
        }
    }
}
