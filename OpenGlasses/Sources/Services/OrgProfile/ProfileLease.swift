import Foundation

/// Plan CT PR 2b — how long a phone stays the organisation's without hearing from the profile's URL.
///
/// Pure: every input is a value, so the whole of "is this phone still the firm's" is testable
/// without a clock, a network or a job.
enum ProfileLease {

    /// How far ahead the "Connect to renew by …" warning starts.
    static let warningWindow: TimeInterval = 14 * 86_400
    /// How far the device clock may sit behind the latest time the app has seen before it counts as
    /// wound back. A day, so a time-zone change or a manual correction is not a lapse.
    static let clockSlack: TimeInterval = 86_400
    /// Renewal is attempted at most this often.
    static let renewalInterval: TimeInterval = 86_400

    enum Status: Equatable, Sendable {
        /// In force; renews on its own whenever the phone reaches the profile's URL.
        case live(renewBy: Date)
        /// In force, but the lease ends within `warningWindow`: the person is told when to connect.
        case renewSoon(renewBy: Date)
        /// Ran out unheard — the lease, or the organisation's own term.
        case lapsed(since: Date)
        /// The device clock is behind a time the app has already seen. Treated as a lapse:
        /// otherwise winding the clock back is a lease that never ends.
        case clockWoundBack
        /// The organisation revoked this phone — by a signed revocation document at the profile's
        /// URL, or by naming this enrolment in the profile's revoked list.
        case revoked

        /// Whether the organisation's content may be used right now.
        var isInForce: Bool {
            switch self {
            case .live, .renewSoon: return true
            case .lapsed, .clockWoundBack, .revoked: return false
            }
        }
    }

    static func status(leaseDays: Int, lastRenewed: Date, policyExpiry: Date?,
                       clockHighWater: Date?, revoked: Bool, now: Date) -> Status {
        if revoked { return .revoked }
        if let highWater = clockHighWater, now.addingTimeInterval(clockSlack) < highWater {
            return .clockWoundBack
        }
        let renewBy = lastRenewed.addingTimeInterval(TimeInterval(leaseDays) * 86_400)
        let end = min(renewBy, policyExpiry ?? renewBy)
        if now >= end { return .lapsed(since: end) }
        if now >= end.addingTimeInterval(-warningWindow) { return .renewSoon(renewBy: end) }
        return .live(renewBy: end)
    }

    /// An open job cannot extend the organisation's authority beyond its signed lease.
    /// The old grace fields remain decodable so an older install's deferred lock is cleared.
    struct Lock: Codable, Equatable, Sendable {
        /// Whether an end has been observed. Retained for stored-record compatibility.
        var lapseObserved = false
        /// Legacy deferred job. Always cleared when this version evaluates the lease.
        var deferredForJob: String?

        /// Decide whether the organisation's content is locked now.
        mutating func isLocked(status: Status, activeJob: String?) -> Bool {
            guard !status.isInForce else {
                lapseObserved = false
                deferredForJob = nil
                return false
            }
            lapseObserved = true
            deferredForJob = nil
            return true
        }
    }
}
