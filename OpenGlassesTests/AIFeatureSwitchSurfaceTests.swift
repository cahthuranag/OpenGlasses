import XCTest
@testable import OpenGlasses

final class AIFeatureSwitchSurfaceTests: XCTestCase {
    func testFeatureSwitchesHaveSettingsSurfacesOrAnExplicitExistingGap() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let views = root.appendingPathComponent("OpenGlasses/Sources/App/Views")
        let paths = try FileManager.default.subpathsOfDirectory(atPath: views.path).filter { $0.hasSuffix(".swift") }
        let source = try paths.map { try String(contentsOf: views.appendingPathComponent($0), encoding: .utf8) }.joined(separator: "\n")
        let existingGaps: Set<String> = [
            "medicationIdentifierEnabled", "healthSafetyAdvisorEnabled", "fitnessCoachingEnabled",
            "safetyAssessmentEnabled", "fieldAssistToolsEnabled", "ambientCaptionsEnabled"
        ]
        let missing = Set(AIFeature.allCases.map { $0.record.disableSwitch.key }.filter { !source.contains($0) })
        XCTAssertEqual(missing, existingGaps)
        for key in ["smartHomeControlEnabled", "aiMessagingEnabled", "healthVaultAIEnabled"] {
            XCTAssertTrue(source.contains("@AppStorage(\"\(key)\")"), "\(key) needs a live Settings binding")
        }
    }
}
