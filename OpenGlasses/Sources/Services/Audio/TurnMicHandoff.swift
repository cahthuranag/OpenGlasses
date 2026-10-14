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
