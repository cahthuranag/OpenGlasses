import Foundation

/// Whether this copy of the app offers smart glasses at all (Plan JE).
///
/// One upload serves TestFlight and the App Store: the store build is the TestFlight build
/// promoted. Meta registers a distributed app only for wearers invited to its release channel, and
/// its production channel is not open, so a store user who reaches for the glasses is refused
/// inside Meta AI with nothing to do about it. Rather than ship that, the store copy suspends the
/// glasses: it never configures the Meta SDK (`WearablesBootstrap`), so there is no Bluetooth
/// prompt and no call to Meta, and it shows none of the glasses surfaces — the onboarding step, the
/// Devices & Privacy row, the session card's pill, the widget's line. TestFlight, a contributor's
/// own build and the simulator keep all of it; the Meta frameworks stay linked everywhere.
///
/// Pure: the install channel (`AppBuildIdentity.channel`) is the input. `current` reads it once.
/// Offering glasses on the store is one line here, shipped as an update; there is deliberately no
/// remote switch, so what App Review sees is what store users get.
enum GlassesSupportPolicy {
    enum Verdict: Equatable {
        case supported
        /// Not offered by this copy. `unavailableReason` is the wearer-facing copy.
        case notInThisVersion
    }

    static func verdict(channel: AppBuildIdentity.Channel) -> Verdict {
        channel == .appStore ? .notInThisVersion : .supported
    }

    /// Said wherever a glasses path has to explain itself: one sentence, in the app's own name.
    static func unavailableReason(appName: String = RegistrationFlow.appName) -> String {
        "Smart glasses aren't supported in this version of \(appName)."
    }

    /// The verdict for this copy. Tests set `overrideForTesting`; nothing else writes it.
    static var current: Verdict { overrideForTesting ?? installed }
    static var isSupported: Bool { current == .supported }

    /// For a report's header.
    static var reportLine: String {
        "Glasses: " + (isSupported ? "offered by this copy" : "not in this version (store copy)")
    }

    private static let installed = verdict(channel: AppBuildIdentity.current.channel)

    /// Tests only — never set from app code. Nil reads the real install channel.
    static var overrideForTesting: Verdict?
}
