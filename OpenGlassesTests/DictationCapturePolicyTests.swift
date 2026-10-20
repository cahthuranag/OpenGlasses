import XCTest
@testable import OpenGlasses

/// Plan JM P0 — voice processing only on the phone mic, on dictation's own engine, with the
/// developer switch on.
final class DictationCapturePolicyTests: XCTestCase {

    func testTheWholeTable() {
        for route in MicRoute.allCases {
            for engine in [DictationCapturePolicy.EngineOwnership.sharedWithWakeWord, .dedicated] {
                for developerSwitch in [false, true] {
                    let expected = route == .phone && engine == .dedicated && developerSwitch
                    XCTAssertEqual(
                        DictationCapturePolicy.voiceProcessing(route: route, engine: engine,
                                                               developerSwitch: developerSwitch),
                        expected, "\(route) × \(engine) × switch \(developerSwitch)")
                }
            }
        }
    }

    func testNeverOnABluetoothRoute() {
        for route in [MicRoute.glasses, .headset] {
            XCTAssertFalse(DictationCapturePolicy.voiceProcessing(route: route, engine: .dedicated,
                                                                  developerSwitch: true))
        }
    }

    func testNeverOnTheWakeWordListenersEngine() {
        XCTAssertFalse(DictationCapturePolicy.voiceProcessing(route: .phone, engine: .sharedWithWakeWord,
                                                              developerSwitch: true))
    }

    func testOffWithoutTheSwitch() {
        XCTAssertFalse(DictationCapturePolicy.voiceProcessing(route: .phone, engine: .dedicated,
                                                              developerSwitch: false))
    }

    func testTheSwitchDefaultsOff() {
        let key = "dictationVoiceProcessingEnabled"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertFalse(Config.dictationVoiceProcessingEnabled)
    }
}
