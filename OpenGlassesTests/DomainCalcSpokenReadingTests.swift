import XCTest
@testable import OpenGlasses

/// A superheat or subcool said aloud — the voice way on when `refrigerant_gauges` has no usable
/// picture — gets the gauge reader's treatment in `domain_calc`: the refrigerant's plausibility
/// band, so an out-of-band value is asked again, and with a job open the pressure and line
/// temperature are recorded as spoken readings, once per call. A fake recorder stands in for the
/// job; no shared service is touched.
@MainActor
final class DomainCalcSpokenReadingTests: XCTestCase {

    private final class Recorder: RefrigerantReadingFiling {
        var isOpenForEvidence = true
        var activeRefrigerant: DeviceIdentityField?
        private(set) var readings: [SpokenReading] = []

        func attachPhoto(_ data: Data, caption: String?, origin: JobMediaItem.Origin, filterWasOn: Bool) -> URL? { nil }

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

    private var recorder: Recorder!
    private var tool: DomainCalcTool!

    override func setUp() {
        super.setUp()
        recorder = Recorder()
        tool = DomainCalcTool(recorder: recorder, now: { Date(timeIntervalSince1970: 1_790_000_000) })
    }

    // MARK: - Out of band

    func testAnOutOfBandSpokenSuctionIsAskedAgainAndNotRecorded() async throws {
        let reply = try await tool.execute(args: [
            "operation": "superheat", "refrigerant": "R-410A", "application": "cooling",
            "suction_pressure_psig": 30, "suction_line_temp_f": 50,
        ])
        XCTAssertTrue(reply.hasPrefix("That's a -"), reply)
        XCTAssertTrue(reply.contains("°F dew point for R-410A, outside the 14 to 68°F range for a suction line in cooling. Did you say 30 psig?"), reply)
        XCTAssertFalse(reply.contains("Superheat ≈"), reply)
        XCTAssertTrue(recorder.readings.isEmpty)
    }

    func testAnOutOfBandSpokenLiquidIsAskedAgainOnTheBubblePoint() async throws {
        let reply = try await tool.execute(args: [
            "operation": "subcool", "refrigerant": "R-410A",
            "liquid_pressure_psig": 30, "liquid_line_temp_f": 20,
        ])
        XCTAssertTrue(reply.contains("°F bubble point for R-410A"), reply)
        XCTAssertTrue(reply.contains("for a liquid line. Did you say 30 psig?"), reply)
        XCTAssertTrue(recorder.readings.isEmpty)
    }

    func testAMetricSpokenValueIsCheckedInItsOwnUnits() async throws {
        // 120 kPa(g) R-410A is far below any comfort-cooling evaporator.
        let reply = try await tool.execute(args: [
            "operation": "superheat", "refrigerant": "R-410A", "application": "cooling",
            "suction_pressure_kpa": 120, "suction_line_temp_c": 10,
        ])
        XCTAssertTrue(reply.contains("°C dew point for R-410A, outside the -10 to 20°C range"), reply)
        XCTAssertTrue(reply.contains("Did you say 120 kPa(g)?"), reply)
    }

    // MARK: - In band

    func testAnInBandSpokenSuperheatIsAnsweredAndRecordedOnceAsSpoken() async throws {
        let reply = try await tool.execute(args: [
            "operation": "superheat", "refrigerant": "R-410A", "refrigerant_source": "nameplate",
            "application": "cooling", "suction_pressure_psig": 118, "suction_line_temp_f": 55,
        ])
        XCTAssertTrue(reply.hasPrefix("Superheat ≈"), reply)
        XCTAssertTrue(reply.hasSuffix("Recorded 2 readings on the job."), reply)
        XCTAssertEqual(recorder.readings.map(\.quantity), ["suction pressure", "suction line temperature"],
                       "each value once")

        let pressure = recorder.readings[0]
        XCTAssertEqual(pressure.value, "118")
        XCTAssertEqual(pressure.unit, "psig")
        XCTAssertNil(pressure.method, "said aloud: the spoken method, never instrument_reading")
        XCTAssertFalse(pressure.isInstrumentReading)
        XCTAssertNil(pressure.photoId)
        XCTAssertEqual(pressure.refrigerant, "R-410A")
        XCTAssertEqual(pressure.refrigerantSource, "nameplate")

        let line = recorder.readings[1]
        XCTAssertEqual(line.value, "55")
        XCTAssertEqual(line.unit, "°F")
        XCTAssertEqual(line.refrigerantSource, "nameplate")
    }

    func testTheRefrigerantSourceDefaultsToTheTechnician() async throws {
        _ = try await tool.execute(args: [
            "operation": "subcool", "refrigerant": "R-410A", "liquid_pressure_psig": 300, "liquid_line_temp_f": 86,
        ])
        XCTAssertEqual(recorder.readings.map(\.quantity), ["liquid pressure", "liquid line temperature"])
        XCTAssertTrue(recorder.readings.allSatisfy { $0.refrigerantSource == "technician" && $0.method == nil })
    }

    func testNoJobOpenMeansNothingIsRecorded() async throws {
        recorder.isOpenForEvidence = false
        let reply = try await tool.execute(args: [
            "operation": "superheat", "refrigerant": "R-410A", "suction_pressure_psig": 118, "suction_line_temp_f": 55,
        ])
        XCTAssertTrue(reply.hasPrefix("Superheat ≈"), reply)
        XCTAssertFalse(reply.contains("Recorded"), reply)
        XCTAssertTrue(recorder.readings.isEmpty)
    }

    func testALookupIsNeverRecorded() async throws {
        _ = try await tool.execute(args: ["operation": "pt_lookup", "refrigerant": "R-410A", "pressure_psig": 118])
        XCTAssertTrue(recorder.readings.isEmpty)
    }

    func testWithoutARecorderTheAnswerIsUnchanged() async throws {
        let args: [String: Any] = ["operation": "superheat", "refrigerant": "R-410A",
                                   "suction_pressure_psig": 118, "suction_line_temp_f": 55]
        let plain = try await DomainCalcTool().execute(args: args)
        recorder.isOpenForEvidence = false
        let withRecorder = try await tool.execute(args: args)
        XCTAssertEqual(plain, withRecorder)
    }

    // MARK: - What the model is told

    func testTheDescriptionAndSchemaCoverTheVoicePath() throws {
        XCTAssertTrue(tool.description.contains("refrigerant_gauges"), tool.description)
        let properties = try XCTUnwrap(tool.parametersSchema["properties"] as? [String: Any])
        XCTAssertNotNil(properties["refrigerant_source"])
        XCTAssertNotNil(properties["application"])
        XCTAssertEqual(tool.parametersSchema["required"] as? [String], ["operation", "refrigerant"],
                       "the new arguments are optional")
    }
}
