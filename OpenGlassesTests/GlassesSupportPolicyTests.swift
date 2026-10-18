import XCTest
@testable import OpenGlasses

/// Plan JE — the store copy offers no glasses; every other copy does. The install channel is the
/// only input, so the whole rule is a table.
final class GlassesSupportPolicyTests: XCTestCase {

    override func tearDown() {
        GlassesSupportPolicy.overrideForTesting = nil
        super.tearDown()
    }

    func testOnlyTheStoreCopySuspendsTheGlasses() {
        XCTAssertEqual(GlassesSupportPolicy.verdict(channel: .appStore), .notInThisVersion)
        XCTAssertEqual(GlassesSupportPolicy.verdict(channel: .testFlight), .supported,
                       "TestFlight is the same upload with the glasses on")
        XCTAssertEqual(GlassesSupportPolicy.verdict(channel: .development), .supported,
                       "a contributor's own build keeps the glasses")
        XCTAssertEqual(GlassesSupportPolicy.verdict(channel: .simulator), .supported)
    }

    func testTheReasonNamesTheAppAndNoPlan() {
        let reason = GlassesSupportPolicy.unavailableReason(appName: "Avenkin")
        XCTAssertEqual(reason, "Smart glasses aren't supported in this version of Avenkin.")
        XCTAssertFalse(reason.contains("JE"), "plan letters never reach a rendered string")
        XCTAssertFalse(reason.lowercased().contains("meta"),
                       "the store copy does not explain Meta's release channel to a store user")
    }

    func testTheOverrideDecidesCurrentAndIsSupported() {
        GlassesSupportPolicy.overrideForTesting = .notInThisVersion
        XCTAssertEqual(GlassesSupportPolicy.current, .notInThisVersion)
        XCTAssertFalse(GlassesSupportPolicy.isSupported)
        XCTAssertEqual(GlassesSupportPolicy.reportLine, "Glasses: not in this version (store copy)")

        GlassesSupportPolicy.overrideForTesting = .supported
        XCTAssertTrue(GlassesSupportPolicy.isSupported)
        XCTAssertEqual(GlassesSupportPolicy.reportLine, "Glasses: offered by this copy")
    }

    /// The test host is the simulator (or a development build under testability), never a store
    /// install: without an override the glasses are offered, which is what every other glasses test
    /// in this bundle assumes.
    func testTheTestHostOffersGlasses() {
        GlassesSupportPolicy.overrideForTesting = nil
        XCTAssertTrue(GlassesSupportPolicy.isSupported)
    }
}
