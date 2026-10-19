import UIKit
import XCTest
@testable import OpenGlasses

/// `refrigerant_gauges` end to end, headless (Plan IS P1): a fake still provider in place of the
/// camera, a fixture instrument-reading response in place of the model (through a fresh
/// `StructuredVisionService` and its `analyze` seam), and a fake recorder in place of the job. No
/// `.shared` camera, HUD or session service is touched.
@MainActor
final class RefrigerantGaugeToolTests: XCTestCase {

    // MARK: - Fakes

    private final class StillProvider: FilteredStillProviding {
        var result: FilteredStillResult
        private(set) var scopes: [PrivacyFilterScope] = []
        init(_ result: FilteredStillResult) { self.result = result }
        func filteredStill(for scope: PrivacyFilterScope, source: FilteredStillSource) async -> FilteredStillResult {
            scopes.append(scope)
            return result
        }
    }

    private final class Recorder: RefrigerantReadingFiling {
        var isOpenForEvidence = true
        var activeRefrigerant: DeviceIdentityField?
        private(set) var photos: [Data] = []
        private(set) var readings: [SpokenReading] = []

        func attachPhoto(_ data: Data, caption: String?, origin: JobMediaItem.Origin, filterWasOn: Bool) -> URL? {
            photos.append(data)
            return URL(fileURLWithPath: "/tmp/photo-\(photos.count).jpg")
        }

        func recordInstrumentReading(quantity: String, value: String, unit: String?, method: String?,
                                     photoId: String?, refrigerant: String?, refrigerantSource: String?,
                                     at: Date) -> SpokenReading? {
            let reading = SpokenReading(quantity: quantity, value: value, unit: unit, at: at, method: method,
                                        photoId: photoId, refrigerant: refrigerant,
                                        refrigerantSource: refrigerantSource)
            readings.append(reading)
            return reading
        }
    }

    private static func still() -> FilteredStillResult {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        return .still(FilteredStill(image: image, scope: .visionAssessment))
    }

    /// An analog manifold and two clamps, as a model would return them.
    nonisolated(unsafe) private static let manifoldResponse: [String: Any] = [
        "readings": [
            ["quantity": "pressure", "instrument": "analog manifold", "value": 118, "unit": "psig",
             "confidence": 0.92, "label": "LOW", "color": "blue", "region": [0.1, 0.3, 0.3, 0.4]],
            ["quantity": "pressure", "instrument": "analog manifold", "value": 380, "unit": "psig",
             "confidence": 0.9, "label": "HIGH", "color": "red", "region": [0.6, 0.3, 0.3, 0.4]],
            ["quantity": "temperature", "instrument": "clamp probe", "value": 50, "unit": "°F",
             "confidence": 0.9, "label": "SUCTION"],
        ],
        "summary": "Low side 118 psig, high side 380 psig, suction clamp 50 °F.",
        "confidence": 0.9,
    ]

    private var provider: StillProvider!
    private var recorder: Recorder!
    private var analyzed = 0
    private var sentImages: [Data] = []

    override func setUp() async throws {
        try await super.setUp()
        provider = StillProvider(Self.still())
        recorder = Recorder()
        analyzed = 0
        sentImages = []
    }

    private func makeTool(response: [String: Any] = manifoldResponse,
                          units: RefrigerationUnits = .imperial, active: Bool = true) -> RefrigerantGaugeTool {
        let vision = StructuredVisionService()
        let registry = AssessmentSchemaRegistry()
        registry.register(InstrumentReadingSchema())
        vision.registry = registry
        vision.disclosureLedger = AIDisclosureLedger()
        vision.analyze = { [weak self] _, _, image, _, _ in
            self?.analyzed += 1
            self?.sentImages.append(image)
            return response
        }
        return RefrigerantGaugeTool(cameraService: provider, recorder: recorder,
                                    assess: { data in
                                        try await vision.assess(kind: "instrument_reading", imageData: data, note: nil)
                                    },
                                    units: { units }, fieldAssistActive: { active })
    }

    // MARK: - The one-step answer

    func testSuperheatFromThePhotoIsAnsweredAndRecordedWithThePhotoAndTheRefrigerantSource() async throws {
        recorder.activeRefrigerant = DeviceIdentityField(name: "Refrigerant", value: "R410A", source: .nameplate)
        let tool = makeTool()
        let reply = try await tool.execute(args: ["calculation": "superheat"])

        XCTAssertTrue(reply.hasPrefix("Superheat 10.2 °F: suction 118 psig is 39.8 °F dew for R-410A, line 50 °F."), reply)
        XCTAssertTrue(reply.contains("R-410A from the nameplate."), reply)
        XCTAssertTrue(reply.hasSuffix("Recorded 3 readings on the job."), reply)
        XCTAssertEqual(provider.scopes, [.visionAssessment], "one still, through the chokepoint, for the assessment")
        XCTAssertEqual(analyzed, 1)
        XCTAssertEqual(recorder.photos, sentImages, "the job keeps the bytes the model saw")

        let suction = try XCTUnwrap(recorder.readings.first { $0.quantity == "suction pressure" })
        XCTAssertEqual(suction.value, "118")
        XCTAssertEqual(suction.unit, "psig")
        XCTAssertEqual(suction.method, "instrument_reading")
        XCTAssertEqual(suction.photoId, "photo-1.jpg")
        XCTAssertEqual(suction.refrigerant, "R-410A")
        XCTAssertEqual(suction.refrigerantSource, "nameplate")
        XCTAssertEqual(Set(recorder.readings.map(\.quantity)),
                       ["suction pressure", "high side pressure", "suction line temperature"])
    }

    func testTheTechniciansRefrigerantIsRecordedAsTheirs() async throws {
        recorder.activeRefrigerant = DeviceIdentityField(name: "Refrigerant", value: "R-22", source: .nameplate)
        let reply = try await makeTool().execute(args: ["calculation": "superheat", "refrigerant": "410a"])
        XCTAssertTrue(reply.contains("for R-410A"), "what the technician said this turn wins: \(reply)")
        XCTAssertTrue(reply.contains("R-410A as you said."), reply)
        XCTAssertEqual(recorder.readings.first?.refrigerantSource, "technician")
    }

    func testMetricUnitsRenderTheMetricAnswer() async throws {
        let reply = try await makeTool(units: .metric).execute(args: ["calculation": "superheat", "refrigerant": "R-410A"])
        XCTAssertTrue(reply.hasPrefix("Superheat 5.6 K: suction 813.6 kPa (118 psig on the gauge) is 4.4 °C dew"), reply)
    }

    // MARK: - No refrigerant

    func testWithoutARefrigerantItGivesPressuresAndRecordsThemWithoutOne() async throws {
        let reply = try await makeTool().execute(args: [:])
        XCTAssertTrue(reply.hasPrefix("Readings: suction 118 psig, high side 380 psig, suction line 50 °F."), reply)
        XCTAssertTrue(reply.contains("Which refrigerant is it?"), reply)
        XCTAssertFalse(reply.contains("dew"), reply)
        XCTAssertTrue(recorder.readings.allSatisfy { $0.refrigerant == nil && $0.refrigerantSource == nil })
        XCTAssertEqual(recorder.readings.count, 3)
    }

    // MARK: - A question, then the answer on the same photo

    func testAnAnswerToItsQuestionReusesThePhotoAndRecordsOnce() async throws {
        let unlabelled: [String: Any] = [
            "readings": [
                ["quantity": "pressure", "value": 118, "unit": "psig", "confidence": 0.9, "region": [0.1, 0.3, 0.3, 0.4]],
                ["quantity": "pressure", "value": 380, "unit": "psig", "confidence": 0.9, "region": [0.6, 0.3, 0.3, 0.4]],
            ],
            "summary": "Two gauges.",
        ]
        let tool = makeTool(response: unlabelled)
        let asked = try await tool.execute(args: ["calculation": "superheat", "refrigerant": "R-410A",
                                                  "refrigerant_source": "nameplate"])
        XCTAssertEqual(asked, "Is the left gauge (118 psig) suction?")
        XCTAssertTrue(recorder.readings.isEmpty)

        let answered = try await tool.execute(args: [
            "calculation": "superheat", "refrigerant": "R-410A", "refrigerant_source": "nameplate",
            "suction_gauge": "left", "suction_line_temp_f": 50, "reuse_last_capture": true,
        ])
        XCTAssertTrue(answered.hasPrefix("Superheat 10.2 °F: suction 118 psig"), answered)
        XCTAssertEqual(analyzed, 1, "the follow-up used the same photograph")
        XCTAssertEqual(provider.scopes.count, 1)
        XCTAssertEqual(recorder.photos.count, 1)
        XCTAssertEqual(recorder.readings.map(\.quantity), ["suction pressure", "suction line temperature"])
        XCTAssertNil(recorder.readings.last?.method, "the line temperature was said, not read off the photo")
        XCTAssertNil(recorder.readings.last?.photoId)

        _ = try await tool.execute(args: [
            "calculation": "superheat", "refrigerant": "R-410A", "suction_gauge": "left",
            "suction_line_temp_f": 50, "reuse_last_capture": true,
        ])
        XCTAssertEqual(recorder.readings.count, 2, "the same photo's readings are recorded once")
    }

    // MARK: - Out of band

    func testAnOutOfBandSuctionInCoolingAsksForARelookAndIsNotRecorded() async throws {
        let low: [String: Any] = [
            "readings": [["quantity": "pressure", "value": 30, "unit": "psig", "confidence": 0.95, "label": "LOW"]],
            "summary": "30 psig.",
        ]
        let reply = try await makeTool(response: low).execute(args: [
            "calculation": "superheat", "refrigerant": "R-410A", "application": "cooling", "suction_line_temp_f": 50,
        ])
        XCTAssertTrue(reply.hasPrefix("Re-look at the suction gauge: 30 psig"), reply)
        XCTAssertFalse(reply.contains("Superheat"), reply)
        XCTAssertFalse(recorder.readings.contains { $0.quantity == "suction pressure" })
    }

    // MARK: - Gates

    func testNoJobOpenMeansNoPhotoFiledAndNoRecord() async throws {
        recorder.isOpenForEvidence = false
        let reply = try await makeTool().execute(args: ["calculation": "superheat", "refrigerant": "R-410A"])
        XCTAssertTrue(reply.hasSuffix("Not recorded: no job is open."), reply)
        XCTAssertTrue(recorder.photos.isEmpty)
        XCTAssertTrue(recorder.readings.isEmpty)
    }

    func testAnUnavailableFilterSendsNothingAnywhere() async throws {
        provider.result = .unavailable(.filterUnavailable)
        let reply = try await makeTool().execute(args: ["refrigerant": "R-410A"])
        XCTAssertTrue(reply.hasPrefix("I couldn't get a picture from the camera."), reply)
        XCTAssertEqual(analyzed, 0, "no model call with an unfiltered frame")
        XCTAssertTrue(recorder.photos.isEmpty)
    }

    func testFieldAssistOffRefuses() async throws {
        let reply = try await makeTool(active: false).execute(args: [:])
        XCTAssertTrue(reply.hasPrefix("Field Assist is disabled."), reply)
        XCTAssertTrue(provider.scopes.isEmpty)
    }

    func testABadAltitudeIsRefusedBeforeTheCamera() async throws {
        let reply = try await makeTool().execute(args: ["altitude_m": 9000])
        XCTAssertTrue(reply.hasPrefix("The altitude is outside"), reply)
        XCTAssertTrue(provider.scopes.isEmpty)
    }
}
