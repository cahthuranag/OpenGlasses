import Foundation

/// Plan GU §2 — switch first, then listen.
///
/// A turn used to start recording on whatever input the engine already had and move the route to
/// the glasses' hands-free mic *afterwards*; the engine stops itself when its input format
/// changes (built-in 48 kHz → HFP 16 kHz), and the turn heard nothing. The order is now: change
/// the route, wait until it is really there **and** carrying sound, build the engine on that
/// input, and only then play the tone that means "talk now". A slow link falls back to the phone
/// mic at the deadline, so it never eats the request.
///
/// Pure sequencing: the service feeds it what it observes and does what it says.
enum TurnMicHandoff {

    /// How long a turn waits for its mic before falling back to the phone. Provisional — P2
    /// measures the real switch time on the glasses.
    static let deadline: TimeInterval = 2.0

    /// Below this RMS a buffer is the all-zero (or near) output of a half-up link, not a room.
    /// A real microphone in a silent room still reads well above it.
    static let liveFrameRMSFloor: Float = 1e-6

    /// How many consecutive buffers above the floor count as "live" — one could be a click.
    static let liveFramesRequired = 2

    /// The least time between two engine rebuilds while the hand-off waits for frames.
    ///
    /// The wait loop runs every 40 ms and used to rebuild the engine on every pass that found it
    /// stopped. On a session iOS had let go (a locked phone after the glasses' link flapped) the
    /// engine starts and stops at once, so a 2.9 s hand-off logged thirty-five `engineStarted`
    /// lines and did thirty-five full tap installs for nothing. A rebuild every 300 ms gives a
    /// half-up link the same chances within the deadline and is quiet when there are none.
    static let rebuildInterval: TimeInterval = 0.3

    /// Whether a stopped engine may be rebuilt now, `rebuildInterval` after the last attempt.
    static func shouldRebuild(lastAttempt: Date?, now: Date) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= rebuildInterval
    }

    /// Which mic this turn should be heard on.
    ///
    /// - The conversation mic is the phone → phone.
    /// - Glasses the wearer stood down from, or has taken off (worn == false), are not where the
    ///   request will come from → phone directly, no waiting (Greig, 2026-10-01: off the face with
    ///   the link up, replies go to the phone).
    /// - The route's port is not there at all (glasses away, earbuds in their case) → phone
    ///   directly: waiting two seconds for a device that is not in the list helps nobody.
    /// - Otherwise the conversation mic.
    ///
    /// "Glasses not in use" is read as *stood down or doffed* rather than `GlassesUse.inUse`
    /// because `inUse` is the Meta link: glasses that pair only as a Bluetooth headset are never
    /// "in use" by that measure and must keep their mic.
    static func target(micRoute: MicRoute, glassesStoodDown: Bool, glassesWorn: Bool?,
                       routePortAvailable: Bool) -> MicRoute {
        switch micRoute {
        case .phone:
            return .phone
        case .glasses:
            if glassesStoodDown || glassesWorn == false { return .phone }
            return routePortAvailable ? .glasses : .phone
        case .headset:
            return routePortAvailable ? .headset : .phone
        }
    }

    /// Why a turn whose conversation mic is Bluetooth was put on the phone instead — the one line
    /// a support report needs to tell "glasses taken off" from "the port vanished". A fixed token,
    /// never a device name.
    enum PhoneReason: String, Equatable {
        case stoodDown, notWorn, portUnavailable
    }

    /// The reason `target` answered `.phone` for a Bluetooth conversation mic, or nil when it did
    /// not (or the wearer chose the phone, which is not a fallback). Mirrors `target` exactly.
    static func phoneReason(micRoute: MicRoute, glassesStoodDown: Bool, glassesWorn: Bool?,
                            routePortAvailable: Bool) -> PhoneReason? {
        switch micRoute {
        case .phone:
            return nil
        case .glasses:
            if glassesStoodDown { return .stoodDown }
            if glassesWorn == false { return .notWorn }
            return routePortAvailable ? nil : .portUnavailable
        case .headset:
            return routePortAvailable ? nil : .portUnavailable
        }
    }

    /// How many times, and how far apart, the conversation route's port is re-read when it is
    /// missing straight after the category switch but was there just before it. About 360 ms in
    /// all: long enough for a hands-free port that blinks out of `availableInputs` across a
    /// category change to come back, short against the hand-off's own `deadline`, which only
    /// starts counting afterwards.
    static let portRecheckAttempts = 3
    static let portRecheckInterval: TimeInterval = 0.12

    /// Whether a missing port is worth re-reading before the turn falls back to the phone.
    ///
    /// Only for a Bluetooth route, and only when the port was observed before the switch (listed
    /// in `availableInputs`, or the live input) — the idle listener was on it moments ago, so its
    /// absence now is the switch, not the glasses leaving. A port that was not there before the
    /// switch (glasses in their case, an idle phone-mic session that lists no hands-free inputs)
    /// falls back at once, as before.
    static func shouldRecheckPort(wanted: MicRoute, portAvailable: Bool, portSeenBeforeSwitch: Bool) -> Bool {
        wanted != .phone && !portAvailable && portSeenBeforeSwitch
    }

    /// How a turn reaches its conversation session.
    enum SessionSwitch: Equatable {
        /// Re-tune the session to the conversation shape: non-mixable (other audio pauses), then
        /// once mixable if that is refused (`MicRoutePolicy.conversationRetryOptions`).
        case reconfigure
        /// Leave the live idle session exactly as it is — mixable, hands-free allowed, the
        /// glasses' mic already the input — and only prefer the route's port.
        case keepIdleSession
        /// Stop the engine, hand the session back (a real deactivation), and activate it afresh
        /// in the mixable hands-free shape the idle Bluetooth hold uses; then prefer the route's
        /// port. If that activation is refused the idle shape is put back and the turn goes to
        /// the phone, as before.
        case freshActivation
    }

    /// Whether a turn re-tunes the session or keeps the idle one it already has.
    ///
    /// From the background (phone locked, in a pocket) iOS refuses to re-tune an active session
    /// in place: on a tester's iPhone (iOS 27.2) both the non-mixable conversation shape *and*
    /// the mixable retry — option for option the idle hold that was already active — failed with
    /// `cannotInterruptOthers`, and the refused attempt left the hands-free port out of
    /// `availableInputs`, so the turn and its reply went to the phone mic and loudspeaker in the
    /// pocket. A fresh activation after a real hand-back succeeds there; a re-tune of the live
    /// session does not. So when the app is not in the foreground and the idle listener is
    /// running on a session that already lists the wanted Bluetooth route's port (the wake phrase
    /// was heard on it moments ago), the turn keeps that session: request and reply stay on the
    /// glasses, at the cost of not pausing other audio.
    ///
    /// A backgrounded turn with nothing live to keep — the idle listener on the phone's own mic,
    /// the default (`WakeListenMic.iPhone`), lists no hands-free inputs at all — still cannot be
    /// re-tuned there. What does work from the background is a **fresh** activation after a real
    /// deactivation: on the same device, every conversation's hand-back (engine stopped, session
    /// deactivated with notify) was followed by the idle hands-free shape activating cleanly with
    /// the phone locked, engine up on the glasses' 16 kHz input a second later. So such a turn
    /// takes that path (`.freshActivation`) — but only when `sessionFreeToHandBack`: nothing else
    /// rides the session (no TTS or other coexisting rider, no shared-tap consumer such as a
    /// recording or captions, which a deactivation would cut off) and no realtime session or
    /// expert call owns it (`HandBackDecision.decide(...) == .deactivate`).
    ///
    /// Everything else reconfigures as before: the foreground (where pausing other audio works
    /// and is wanted), the phone route, and a backgrounded turn whose session is not free to hand
    /// back (it keeps today's attempt, and the phone if that is refused).
    static func sessionSwitch(wanted: MicRoute, appInForeground: Bool, portSeenBeforeSwitch: Bool,
                              engineRunning: Bool, sessionFreeToHandBack: Bool) -> SessionSwitch {
        guard wanted != .phone, !appInForeground else { return .reconfigure }
        if portSeenBeforeSwitch && engineRunning { return .keepIdleSession }
        return sessionFreeToHandBack ? .freshActivation : .reconfigure
    }

    /// Whether a follow-up turn takes the conversation's Bluetooth mic back from the phone.
    ///
    /// A conversation whose first turn landed on the phone used to keep it for every follow-up:
    /// the route was decided once, at the first pause hold, and never looked at again. On a
    /// tester's iPhone a locked-phone turn went to the phone mic and loudspeaker, the app was
    /// brought to the front 20 seconds later, and the three follow-ups after it all stayed on the
    /// phone with the glasses connected and in use. So at each follow-up's start the turn is
    /// re-read: it retakes the conversation mic when
    ///
    /// - this conversation's turn is on the phone (`turnMic == .phone`) although the wearer's
    ///   conversation mic is Bluetooth,
    /// - the app is in the foreground now, where the switch is allowed,
    /// - the phone was not chosen in the foreground — a turn put on the phone there saw the port
    ///   missing (or fell back at the deadline) with nothing stopping the switch, and is not
    ///   re-asked on every follow-up of the same conversation; it was chosen from the background,
    ///   where the switch itself was what failed,
    /// - and the glasses are not stood down or off the face *now*: those still mean the phone.
    ///
    /// Whether the port is really there is the retake's own question — it goes the ordinary way
    /// (`target` with the port read after the switch) and lands on the phone again if it is not.
    static func shouldRetakeAfterPhoneTurn(turnMic: MicRoute?, micRoute: MicRoute, glassesStoodDown: Bool,
                                           glassesWorn: Bool?, appInForeground: Bool,
                                           phoneChosenInForeground: Bool) -> Bool {
        guard turnMic == .phone, micRoute != .phone, appInForeground, !phoneChosenInForeground else { return false }
        return target(micRoute: micRoute, glassesStoodDown: glassesStoodDown, glassesWorn: glassesWorn,
                      routePortAvailable: true) != .phone
    }

    /// An interruption can put the session on the idle phone mic without changing the stored
    /// conversation route. Reconcile the actual input at a foreground turn boundary as well.
    static func shouldRepairConversationRoute(turnMic: MicRoute?, actualMic: MicRoute?, micRoute: MicRoute,
                                               glassesStoodDown: Bool, glassesWorn: Bool?,
                                               appInForeground: Bool) -> Bool {
        guard appInForeground, micRoute != .phone, turnMic == micRoute, actualMic != micRoute else { return false }
        return target(micRoute: micRoute, glassesStoodDown: glassesStoodDown, glassesWorn: glassesWorn,
                      routePortAvailable: true) == micRoute
    }

    enum State: Equatable {
        /// The route has been asked for; `currentRoute.inputs` does not show it yet.
        case waitingForRoute
        /// The route is there; the engine has been rebuilt on it and its first buffers are awaited.
        case waitingForFrames
        /// Recording may start on this mic.
        case live(MicRoute)
        /// The deadline passed; the turn is moving to the phone mic.
        case fellBack
    }

    enum Event: Equatable {
        /// The route the session's live input resolves to (`MicRoutePolicy.resolvedRoute`).
        case routeObserved(MicRoute?)
        /// The rebuilt engine delivered `liveFramesRequired` buffers above the floor.
        case framesNonSilent
        /// `deadline` passed.
        case deadline
    }

    enum Action: Equatable {
        case none
        /// The route is right: (re)build the engine on the live input format.
        case buildEngine
        /// Play the tone and start recording on this mic.
        case startTurn(on: MicRoute)
        /// Point the session at the phone mic, build the engine there, then start the turn on it.
        case fallBackToPhone
    }

    /// One turn's hand-off.
    struct Machine: Equatable {
        let target: MicRoute
        private(set) var state: State = .waitingForRoute

        init(target: MicRoute) { self.target = target }

        mutating func handle(_ event: Event) -> Action {
            switch (state, event) {
            case (.waitingForRoute, .routeObserved(let route)):
                guard route == target else { return .none }
                state = .waitingForFrames
                return .buildEngine

            case (.waitingForFrames, .framesNonSilent):
                state = .live(target)
                return .startTurn(on: target)

            case (.waitingForRoute, .deadline), (.waitingForFrames, .deadline):
                // On the phone there is nowhere further to fall: start anyway, as the app always
                // did — the dictation path's own no-speech timeout still bounds it.
                if target == .phone {
                    state = .live(.phone)
                    return .startTurn(on: .phone)
                }
                state = .fellBack
                return .fallBackToPhone

            default:
                // Frames before the route, a second route report, anything after a terminal
                // state: nothing to do. In particular nothing here can start a turn twice.
                return .none
            }
        }
    }

    /// Whether one captured buffer counts towards "live".
    static func isLiveFrame(rms: Float) -> Bool {
        rms > liveFrameRMSFloor
    }
}
