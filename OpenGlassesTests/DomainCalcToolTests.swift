import XCTest
@testable import OpenGlasses

/// `domain_calc` over the generated saturation tables (Plan IS P0): superheat from the dew point,
/// subcooling from the bubble point, the glide and the source in the answer, either unit set, the
/// sea-level line and the altitude correction, and refusals by name. The old argument names keep
/// working.
@MainActor
final class DomainCalcToolTests: XCTestCase {

    private var tool: DomainCalcTool!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(true, forKey: "fieldAssistEnabled")
        tool = DomainCalcTool()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "fieldAssistEnabled")
        super.tearDown()
    }

    private func run(_ args: [String: Any]) async throws -> String {
        try await tool.execute(args: args)
    }

    private func table(_ designation: String) throws -> SaturationTable {
        try XCTUnwrap(SaturationTableCatalog.table(for: designation))
    }

    /// The tool's one-decimal rendering.
    private func shown(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded.rounded() == rounded ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }

    // MARK: - pt_lookup

    func testPTLookupGivesTheSaturationTemperatureAndSource() async throws {
        let result = try await run(["operation": "pt_lookup", "refrigerant": "R-22", "pressure_psig": 68.5])
        XCTAssertTrue(result.contains("R-22 at 68.5 psig: saturation 40°F"), result)
        XCTAssertTrue(result.contains("single component, no glide"), result)
        XCTAssertTrue(result.contains("Saturation data: CoolProp 8.0.0"), result)
        XCTAssertTrue(result.contains("Assumes sea-level atmosphere"), result)
    }

    func testPTLookupForABlendGivesDewAndBubble() async throws {
        let result = try await run(["operation": "pt_lookup", "refrigerant": "407c", "pressure_psig": 63])
        let kPa = RefrigerantPressure.absoluteKPa(gauge: 63, unit: .psi)
        let dew = try table("R-407C").temperature(atAbsoluteKPa: kPa, scale: .fahrenheit, curve: .dew).get()
        let bubble = try table("R-407C").temperature(atAbsoluteKPa: kPa, scale: .fahrenheit, curve: .bubble).get()
        XCTAssertTrue(result.contains("dew point \(shown(dew))°F"), result)
        XCTAssertTrue(result.contains("bubble point \(shown(bubble))°F"), result)
        XCTAssertTrue(result.contains("glide \(shown(dew - bubble))°F"), result)
        XCTAssertTrue(result.contains("CoolProp 8.0.0, dew and bubble points"), result)
    }

    func testPTLookupInMetric() async throws {
        let result = try await run(["operation": "pt_lookup", "refrigerant": "R-410A", "pressure_kpa": 820])
        XCTAssertTrue(result.contains("R-410A at 820 kPa(g)"), result)
        XCTAssertTrue(result.contains("dew point 4.6°C"), result)
        XCTAssertTrue(result.contains("bubble point 4.5°C"), result)
        XCTAssertTrue(result.contains("glide 0.1K"), result)
    }

    func testPTLookupInBar() async throws {
        let result = try await run(["operation": "pt_lookup", "refrigerant": "R-410A", "pressure_bar": 8.2])
        XCTAssertTrue(result.contains("R-410A at 8.2 bar(g)"), result)
        XCTAssertTrue(result.contains("dew point 4.6°C"), result)
    }

    func testPTLookupByTemperature() async throws {
        let result = try await run(["operation": "pt_lookup", "refrigerant": "R-22", "temperature_f": 40])
        XCTAssertTrue(result.contains("R-22 at 40°F: saturation pressure 68.6 psig"), result)
        let metric = try await run(["operation": "pt_lookup", "refrigerant": "R-1234yf", "temperature_c": 10])
        let kPa = try table("R-1234yf").absolutePressureKPa(atTemperature: 10, scale: .celsius, curve: .dew).get()
        XCTAssertTrue(metric.contains("R-1234yf at 10°C: saturation pressure \(shown(kPa - 101.325)) kPa(g)"), metric)
    }

    func testAbsoluteReadingsSkipTheAtmosphere() async throws {
        let result = try await run(["operation": "pt_lookup", "refrigerant": "R-22", "pressure_kpa": 574.02,
                                    "pressure_reference": "absolute", "altitude_m": 2_000])
        XCTAssertTrue(result.contains("574 kPa abs"), result)
        XCTAssertTrue(result.contains("saturation 4.4°C"), result)
        XCTAssertTrue(result.contains("Absolute pressure: no atmospheric correction"), result)
        XCTAssertFalse(result.contains("sea-level"), result)
    }

    // MARK: - Superheat (dew point)

    func testSuperheatUsesTheDewPointAndSaysTheGlide() async throws {
        let result = try await run([
            "operation": "superheat", "refrigerant": "R-407C",
            "suction_pressure_psig": 63, "suction_line_temp_f": 52
        ])
        let kPa = RefrigerantPressure.absoluteKPa(gauge: 63, unit: .psi)
        let r407c = try table("R-407C")
        let dew = try r407c.temperature(atAbsoluteKPa: kPa, scale: .fahrenheit, curve: .dew).get()
        let glide = try r407c.glide(atAbsoluteKPa: kPa, scale: .fahrenheit).get()
        XCTAssertEqual(dew, 40, accuracy: 0.15)
        XCTAssertTrue(result.hasPrefix("Superheat ≈ \(shown(52 - dew))°F for R-407C"), result)
        XCTAssertTrue(result.contains("suction 63 psig is \(shown(dew))°F at the dew point"), result)
        XCTAssertTrue(result.contains("Glide \(shown(glide))°F at this pressure; this uses the dew point"), result)
        XCTAssertTrue(result.contains("Saturation data: CoolProp 8.0.0, dew point."), result)
        XCTAssertTrue(result.contains("Assumes sea-level atmosphere (101.325 kPa)"), result)
        XCTAssertTrue(result.contains("(Source: superheat_subcool.md)"), result)
    }

    func testSuperheatWithTheOldArgumentNames() async throws {
        // R-410A at 118 psig is about 39.8 °F at the dew point; suction line 55 °F → about 15.2 °F.
        let result = try await run([
            "operation": "superheat", "refrigerant": "R-410A",
            "suction_pressure_psig": 118, "suction_line_temp_f": 55
        ])
        XCTAssertTrue(result.hasPrefix("Superheat ≈ 15.2°F for R-410A"), result)
        XCTAssertTrue(result.contains("is 39.8°F at the dew point"), result)
        XCTAssertTrue(result.contains("Glide 0.2°F"), result)
    }

    func testSuperheatInMetricIsInKelvin() async throws {
        let result = try await run([
            "operation": "superheat", "refrigerant": "R-410A",
            "suction_pressure_kpa": 820, "suction_line_temp_c": 10
        ])
        XCTAssertTrue(result.hasPrefix("Superheat ≈ 5.4K for R-410A"), result)
        XCTAssertTrue(result.contains("suction 820 kPa(g) is 4.6°C at the dew point, suction line 10°C"), result)
    }

    func testTheSameSuperheatInEitherUnitSet() async throws {
        // 118 psig and 50 °F, or the same pressure in kPa(g) and 10 °C: the same superheat in kelvin.
        let kPaGauge = 118 * 6.894757293168361
        let imperial = try table("R-410A").temperature(
            atAbsoluteKPa: RefrigerantPressure.absoluteKPa(gauge: 118, unit: .psi), scale: .fahrenheit, curve: .dew).get()
        let metric = try table("R-410A").temperature(
            atAbsoluteKPa: RefrigerantPressure.absoluteKPa(gauge: kPaGauge, unit: .kPa), scale: .celsius, curve: .dew).get()
        let superheatF = 50 - imperial
        let superheatK = 10 - metric
        XCTAssertEqual(superheatF / 1.8, superheatK, accuracy: 0.02)
        let result = try await run([
            "operation": "superheat", "refrigerant": "R-410A",
            "suction_pressure_kpa": kPaGauge, "suction_line_temp_c": 10
        ])
        XCTAssertTrue(result.hasPrefix("Superheat ≈ \(shown(superheatK))K"), result)
    }

    func testALineTemperatureInTheOtherUnitIsConverted() async throws {
        let result = try await run([
            "operation": "superheat", "refrigerant": "R-410A",
            "suction_pressure_psig": 118, "suction_line_temp_c": 12.78
        ])
        XCTAssertTrue(result.hasPrefix("Superheat ≈ 15.2°F"), result)
    }

    func testAltitudeCorrectsTheGaugeReading() async throws {
        let result = try await run([
            "operation": "superheat", "refrigerant": "R-410A",
            "suction_pressure_psig": 118, "suction_line_temp_f": 55, "altitude_ft": 5_000
        ])
        // 84.3 kPa atmosphere instead of 101.325: the same gauge reading is 38.7 °F, not 39.8 °F.
        XCTAssertTrue(result.contains("is 38.7°F at the dew point"), result)
        XCTAssertTrue(result.hasPrefix("Superheat ≈ 16.3°F"), result)
        XCTAssertTrue(result.contains("Corrected for altitude 5000 ft: atmosphere 84.3 kPa"), result)
        XCTAssertFalse(result.contains("sea-level"), result)

        let metres = try await run([
            "operation": "pt_lookup", "refrigerant": "R-410A", "pressure_kpa": 820, "altitude_m": 1_500
        ])
        XCTAssertTrue(metres.contains("Corrected for altitude 1500 m: atmosphere 84.6 kPa"), metres)
    }

    func testAltitudeOutsideTheRangeIsRefused() async throws {
        let result = try await run([
            "operation": "superheat", "refrigerant": "R-410A",
            "suction_pressure_psig": 118, "suction_line_temp_f": 55, "altitude_m": 9_000
        ])
        XCTAssertTrue(result.contains("altitude is outside"), result)
        XCTAssertFalse(result.contains("Superheat ≈"), result)
    }

    func testNegativeSuperheatWarns() async throws {
        let result = try await run([
            "operation": "superheat", "refrigerant": "R-410A",
            "suction_pressure_psig": 118, "suction_line_temp_f": 35
        ])
        XCTAssertTrue(result.contains("liquid floodback"), result)
    }

    // MARK: - Subcool (bubble point)

    func testSubcoolUsesTheBubblePoint() async throws {
        let result = try await run([
            "operation": "subcool", "refrigerant": "R-407C",
            "liquid_pressure_psig": 225, "liquid_line_temp_f": 90
        ])
        let kPa = RefrigerantPressure.absoluteKPa(gauge: 225, unit: .psi)
        let bubble = try table("R-407C").temperature(atAbsoluteKPa: kPa, scale: .fahrenheit, curve: .bubble).get()
        XCTAssertTrue(result.hasPrefix("Subcooling ≈ \(shown(bubble - 90))°F for R-407C"), result)
        XCTAssertTrue(result.contains("liquid 225 psig is \(shown(bubble))°F at the bubble point"), result)
        XCTAssertTrue(result.contains("this uses the bubble point"), result)
        XCTAssertTrue(result.contains("Saturation data: CoolProp 8.0.0, bubble point."), result)
    }

    func testSubcoolWithTheOldArgumentNames() async throws {
        // R-410A at 300 psig is 95.8 °F at the bubble point; liquid line 86 °F → 9.8 °F.
        let result = try await run([
            "operation": "subcool", "refrigerant": "R-410A",
            "liquid_pressure_psig": 300, "liquid_line_temp_f": 86
        ])
        XCTAssertTrue(result.hasPrefix("Subcooling ≈ 9.8°F for R-410A"), result)
        XCTAssertTrue(result.contains("95.8°F at the bubble point"), result)
    }

    func testSingleComponentSaysNoGlide() async throws {
        let result = try await run([
            "operation": "subcooling", "refrigerant": "R-32",
            "liquid_pressure_psig": 300, "liquid_line_temp_f": 85
        ])
        XCTAssertTrue(result.contains("R-32 is a single component: no glide"), result)
    }

    // MARK: - Refusals

    func testUnknownRefrigerantIsRefused() async throws {
        let result = try await run(["operation": "pt_lookup", "refrigerant": "R-999", "pressure_psig": 100])
        XCTAssertTrue(result.contains("No saturation table for 'R-999'"), result)
        XCTAssertTrue(result.contains("R-410A"), result)
        XCTAssertFalse(result.contains("°F"), result)
    }

    func testMissingRefrigerantIsNeverAssumed() async throws {
        let result = try await run(["operation": "superheat", "suction_pressure_psig": 118, "suction_line_temp_f": 55])
        XCTAssertTrue(result.contains("Specify 'refrigerant'"), result)
        XCTAssertTrue(result.contains("never assumed"), result)
        XCTAssertFalse(result.contains("Superheat ≈"), result)
    }

    func testPressureBelowTheTableIsRefusedByName() async throws {
        let result = try await run(["operation": "pt_lookup", "refrigerant": "R-410A", "pressure_psig": 5])
        XCTAssertTrue(result.contains("5 psig is below the R-410A table, which starts at -40°F (10.7 psig)"), result)
        XCTAssertTrue(result.contains("No saturation temperature is given outside it"), result)
    }

    func testPressureAboveTheTableIsRefusedByName() async throws {
        let result = try await run(["operation": "subcool", "refrigerant": "R-410A",
                                    "liquid_pressure_psig": 700, "liquid_line_temp_f": 100])
        XCTAssertTrue(result.contains("700 psig is above the R-410A table, which ends at 150°F (613.9 psig)"), result)
        XCTAssertFalse(result.contains("Subcooling ≈"), result)
    }

    func testCarbonDioxideAboveItsCriticalPointIsRefused() async throws {
        let result = try await run(["operation": "pt_lookup", "refrigerant": "CO2", "pressure_psig": 1_200])
        XCTAssertTrue(result.contains("above the R-744 table, which ends near its critical point (87.8°F)"), result)
        XCTAssertTrue(result.contains("no saturation temperature"), result)
    }

    func testTemperatureOutsideTheTableIsRefused() async throws {
        let result = try await run(["operation": "pt_lookup", "refrigerant": "R-22", "temperature_f": 160])
        XCTAssertTrue(result.contains("160°F is outside the R-22 table (-40°F to 150°F)"), result)
    }

    func testMissingReadingsAskForThem() async throws {
        let superheat = try await run(["operation": "superheat", "refrigerant": "R-410A", "suction_pressure_psig": 118])
        XCTAssertTrue(superheat.contains("suction line temperature"), superheat)
        let lookup = try await run(["operation": "pt_lookup", "refrigerant": "R-410A"])
        XCTAssertTrue(lookup.contains("for pt_lookup"), lookup)
    }

    func testUnknownOperation() async throws {
        let result = try await run(["operation": "charge", "refrigerant": "R-410A"])
        XCTAssertTrue(result.contains("Unknown operation 'charge'"), result)
    }

    // MARK: - Description

    func testDescriptionSummaryFitsAndNamesTheOperations() {
        let summary = SystemPromptBuilder.summary(tool.description)
        XCTAssertFalse(summary.hasSuffix("…"), summary)
        XCTAssertTrue(summary.contains("superheat (dew point)"), summary)
        XCTAssertTrue(summary.contains("subcool (bubble point)"), summary)
    }

    func testSchemaKeepsTheOldArgumentNames() throws {
        let properties = try XCTUnwrap(tool.parametersSchema["properties"] as? [String: Any])
        for name in ["operation", "refrigerant", "pressure_psig", "suction_pressure_psig", "suction_line_temp_f",
                     "liquid_pressure_psig", "liquid_line_temp_f", "suction_pressure_kpa", "suction_line_temp_c",
                     "liquid_pressure_kpa", "liquid_line_temp_c", "altitude_ft", "altitude_m"] {
            XCTAssertNotNil(properties[name], name)
        }
    }
}
