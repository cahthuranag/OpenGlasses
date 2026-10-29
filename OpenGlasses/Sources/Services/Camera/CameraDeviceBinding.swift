import Foundation

/// Which device the glasses camera session binds to.
///
/// The SDK lists every pair that has been added, in an order that says nothing about which one is
/// connected. Binding to the first listed one is right with one pair and wrong with two: a tester's
/// phone (build 581) listed a pair that was away ahead of the pair being worn, and every one of 68
/// session starts went to the absent pair — `deviceUnavailable`, then `noEligibleDevice` — while
/// the app said "connected" and audio worked.
///
/// So the connection owner's reading wins: the device whose link is connected
/// (`GlassesConnectionSnapshot.connectedDeviceId`). With none connected — a warm-up while the link
/// is still coming up — the first listed device stands in, as before; with nothing listed, the
/// SDK's own `AutoDeviceSelector` chooses.
enum CameraDeviceBinding: Equatable {
    case connected(String)
    case firstListed(String)
    case anyEligible

    static func choose(listed: [String], connected: String?) -> CameraDeviceBinding {
        if let connected { return .connected(connected) }
        if let first = listed.first { return .firstListed(first) }
        return .anyEligible
    }

    var deviceId: String? {
        switch self {
        case .connected(let id), .firstListed(let id): id
        case .anyEligible: nil
        }
    }
}
