import XCTest
@testable import OpenGlasses

/// Which listed device the glasses camera session binds to.
///
/// The bug these pin down: the session bound to the first device the SDK listed. A tester's phone
/// listed a pair that was away ahead of the pair being worn, and every session start failed while
/// the app read "connected".
final class CameraDeviceBindingTests: XCTestCase {

    func testTheConnectedDeviceWinsOverTheListOrder() {
        let binding = CameraDeviceBinding.choose(listed: ["away", "worn"], connected: "worn")
        XCTAssertEqual(binding, .connected("worn"))
        XCTAssertEqual(binding.deviceId, "worn")
    }

    func testTheConnectedDeviceWinsBeforeTheCameraHasSeenTheList() {
        // The camera's own device listener can lag the connection owner by a beat.
        XCTAssertEqual(CameraDeviceBinding.choose(listed: [], connected: "worn"), .connected("worn"))
    }

    func testWithNothingConnectedTheFirstListedStandsIn() {
        let binding = CameraDeviceBinding.choose(listed: ["a", "b"], connected: nil)
        XCTAssertEqual(binding, .firstListed("a"))
        XCTAssertEqual(binding.deviceId, "a")
    }

    func testWithNothingListedTheSDKChooses() {
        let binding = CameraDeviceBinding.choose(listed: [], connected: nil)
        XCTAssertEqual(binding, .anyEligible)
        XCTAssertNil(binding.deviceId)
    }

    func testTheLoggedRuleNamesTheCaseNotTheDevice() {
        XCTAssertEqual(PrivacyToken.caseName(of: CameraDeviceBinding.connected("secret-id"))?.description,
                       "connected")
        XCTAssertEqual(PrivacyToken.caseName(of: CameraDeviceBinding.firstListed("secret-id"))?.description,
                       "firstListed")
    }
}
