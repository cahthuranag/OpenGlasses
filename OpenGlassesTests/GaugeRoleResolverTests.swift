import XCTest
@testable import OpenGlasses

/// `GaugeRoleResolver` over fixture readings (Plan IS P1): roles come from the instrument's own
/// labels and colours, the technician's answer outranks them, and a role that cannot be told is a
/// question — never a guess. The readings are decoded through the instrument-reading schema, the
/// same path a model response takes.
final class GaugeRoleResolverTests: XCTestCase {

    /// Readings exactly as `instrument_reading` would hand them over, from a fixture response.
    private func readings(_ items: [[String: Any]]) throws -> [InstrumentReading] {
        let json: [String: Any] = ["readings": items, "summary": "Fixture.", "confidence": 0.9]
        return try InstrumentReadingSchema().makeCard(from: json, context: nil).readings
    }

    private func pressure(_ value: Double, _ unit: String = "psig", label: String? = nil, color: String? = nil,
                          x: Double? = nil, quantity: String = "pressure",
                          instrument: String = "manifold gauge") -> [String: Any] {
        var item: [String: Any] = ["quantity": quantity, "instrument": instrument, "value": value,
                                   "unit": unit, "confidence": 0.9]
        if let label { item["label"] = label }
        if let color { item["color"] = color }
        if let x { item["region"] = [x, 0.3, 0.2, 0.3] }
        return item
    }

    private func probe(_ value: Double, _ unit: String = "°F", label: String? = nil, x: Double? = nil) -> [String: Any] {
        var item: [String: Any] = ["quantity": "temperature", "instrument": "clamp probe", "value": value,
                                   "unit": unit, "confidence": 0.9]
        if let label { item["label"] = label }
        if let x { item["region"] = [x, 0.7, 0.1, 0.1] }
        return item
    }

    // MARK: - Analog manifold

    func testAnAnalogManifoldResolvesByItsLowAndHighFaces() throws {
        let resolution = GaugeRoleResolver.resolve(try readings([
            pressure(118, label: "LOW", color: "blue", x: 0.1),
            pressure(380, label: "HIGH", color: "red", x: 0.6),
        ]))
        XCTAssertEqual(resolution.gauges[.suction]?.gauge.reading.value, 118)
        XCTAssertEqual(resolution.gauges[.liquid]?.gauge.reading.value, 380)
        XCTAssertEqual(resolution.gauges[.suction]?.basis, .sideWord("low"))
        XCTAssertTrue(resolution.gauges[.liquid]?.basis.isHighSide == true, "HIGH is the high side, said as such")
        XCTAssertTrue(resolution.unresolvedGauges.isEmpty)
        XCTAssertNil(resolution.question(for: .suction))
    }

    func testColourAloneIsACueWhereTheModelReportsIt() throws {
        let resolution = GaugeRoleResolver.resolve(try readings([
            pressure(118, color: "Blue"), pressure(380, color: "red hose"),
        ]))
        XCTAssertEqual(resolution.gauges[.suction]?.basis, .colour("Blue"))
        XCTAssertEqual(resolution.gauges[.liquid]?.gauge.reading.value, 380)
    }

    func testTheYellowUtilityHoseCarriesNoRole() throws {
        let resolution = GaugeRoleResolver.resolve(try readings([pressure(118, color: "yellow")]))
        XCTAssertTrue(resolution.gauges.isEmpty)
        XCTAssertEqual(resolution.question(for: .suction), "Is the gauge reading 118 psig suction?")
    }

    // MARK: - Digital manifold

    func testADigitalManifoldResolvesByItsPrintedRoleWords() throws {
        let resolution = GaugeRoleResolver.resolve(try readings([
            pressure(820, "kPa", label: "SUCTION", instrument: "digital manifold"),
            pressure(2650, "kPa", label: "LIQUID", instrument: "digital manifold"),
            probe(10, "°C", label: "T1 SUCTION"),
            probe(38, "°C", label: "LIQ"),
        ]))
        XCTAssertEqual(resolution.gauges[.suction]?.gauge.pressure,
                       GaugePressure(value: 820, unit: .kPa, reference: .gauge))
        XCTAssertEqual(resolution.gauges[.liquid]?.basis, .roleWord("liquid"))
        XCTAssertFalse(resolution.gauges[.liquid]?.basis.isHighSide == true)
        XCTAssertEqual(resolution.probes[.suction]?.probe.reading.value, 10)
        XCTAssertEqual(resolution.probes[.liquid]?.probe.reading.value, 38)
        XCTAssertEqual(resolution.probes[.liquid]?.probe.scale, .celsius)
    }

    func testARoleWordInTheQuantityCountsAndDischargeIsItsOwnRole() throws {
        let resolution = GaugeRoleResolver.resolve(try readings([
            pressure(118, quantity: "suction pressure"),
            pressure(410, quantity: "head pressure"),
        ]))
        XCTAssertEqual(resolution.gauges[.suction]?.gauge.reading.value, 118)
        XCTAssertEqual(resolution.gauges[.discharge]?.gauge.reading.value, 410)
        XCTAssertNil(resolution.gauges[.liquid], "a discharge reading is never used as the liquid line")
    }

    // MARK: - A single gauge

    func testASingleLabelledGaugeGivesOneRoleAndNoQuestionAboutIt() throws {
        let resolution = GaugeRoleResolver.resolve(try readings([pressure(118, label: "LO")]))
        XCTAssertEqual(resolution.gauges[.suction]?.gauge.reading.value, 118)
        XCTAssertNil(resolution.gauges[.liquid])
        XCTAssertNil(resolution.question(for: .liquid), "nothing left in the frame to ask about")
    }

    func testASingleUnlabelledGaugeIsAskedAboutByItsValue() throws {
        let resolution = GaugeRoleResolver.resolve(try readings([pressure(118)]))
        XCTAssertTrue(resolution.gauges.isEmpty)
        XCTAssertEqual(resolution.question(for: .suction), "Is the gauge reading 118 psig suction?")
    }

    // MARK: - Missing or ambiguous → a question

    func testTwoUnlabelledGaugesAreAskedByPositionNeverRankedByValue() throws {
        let resolution = GaugeRoleResolver.resolve(try readings([
            pressure(380, x: 0.6), pressure(118, x: 0.1),
        ]))
        XCTAssertTrue(resolution.gauges.isEmpty, "the lower pressure is not assumed to be suction")
        XCTAssertEqual(resolution.question(for: .suction), "Is the left gauge (118 psig) suction?")
        XCTAssertEqual(resolution.question(for: .liquid), "Is the right gauge (380 psig) on the liquid line?")
        XCTAssertEqual(resolution.unresolvedGauges.map(\.position), ["left", "right"])
    }

    func testCuesThatDisagreeLeaveTheGaugeUnresolved() throws {
        let resolution = GaugeRoleResolver.resolve(try readings([
            pressure(118, label: "LOW", color: "red", x: 0.1),
            pressure(380, label: "LIQUID", color: "blue", x: 0.6),
        ]))
        XCTAssertTrue(resolution.gauges.isEmpty)
        XCTAssertEqual(resolution.question(for: .suction), "Is the left gauge (118 psig) suction?")
        XCTAssertEqual(resolution.question(for: .liquid), "Is the right gauge (380 psig) on the liquid line?")
    }

    func testTwoGaugesClaimingOneRoleAreBothAsked() throws {
        let resolution = GaugeRoleResolver.resolve(try readings([
            pressure(118, label: "LOW", x: 0.1), pressure(121, label: "LOW", x: 0.6),
        ]))
        XCTAssertNil(resolution.gauges[.suction])
        XCTAssertEqual(resolution.unresolvedGauges.count, 2)
        XCTAssertEqual(resolution.question(for: .suction), "Is the left gauge (118 psig) suction?")
    }

    func testABelowOrAHighlightedWordIsNotASideWord() throws {
        let resolution = GaugeRoleResolver.resolve(try readings([
            pressure(118, instrument: "gauge below the highlighted panel"),
        ]))
        XCTAssertTrue(resolution.gauges.isEmpty)
    }

    func testAnUnlabelledProbeIsAskedAboutAndAMissingOneIsAskedFor() throws {
        let one = GaugeRoleResolver.resolve(try readings([pressure(118, label: "LOW"), probe(50)]))
        XCTAssertNil(one.probes[.suction])
        XCTAssertEqual(one.probeQuestion(for: .suction), "Is the probe reading 50 °F on the suction line?")
        let none = GaugeRoleResolver.resolve(try readings([pressure(118, label: "LOW")]))
        XCTAssertEqual(none.probeQuestion(for: .suction), "What's the suction line temperature?")
    }

    // MARK: - The technician's answer

    func testTheTechniciansAnswerByPositionResolvesTheQuestion() throws {
        let fixture = try readings([pressure(380, x: 0.6), pressure(118, x: 0.1)])
        let resolution = GaugeRoleResolver.resolve(
            fixture, hints: .init(gauges: [.suction: "left", .liquid: "the right one"]))
        XCTAssertEqual(resolution.gauges[.suction]?.gauge.reading.value, 118)
        XCTAssertEqual(resolution.gauges[.suction]?.basis, .technician)
        XCTAssertEqual(resolution.gauges[.liquid]?.gauge.reading.value, 380)
    }

    func testTheTechniciansAnswerByValueWorksWithoutPositions() throws {
        let fixture = try readings([pressure(380), pressure(118)])
        let resolution = GaugeRoleResolver.resolve(fixture, hints: .init(gauges: [.suction: "118"]))
        XCTAssertEqual(resolution.gauges[.suction]?.gauge.reading.value, 118)
        XCTAssertNil(resolution.gauges[.liquid], "only what was answered is resolved")
    }

    func testTheTechnicianOutranksALabel() throws {
        let fixture = try readings([pressure(118, label: "LOW", x: 0.1), pressure(121, x: 0.6)])
        let resolution = GaugeRoleResolver.resolve(fixture, hints: .init(gauges: [.suction: "right"]))
        XCTAssertEqual(resolution.gauges[.suction]?.gauge.reading.value, 121)
        XCTAssertEqual(resolution.unresolvedGauges.map(\.reading.value), [118])
    }

    func testTheOnlyProbeCanBeNamedAsTheProbe() throws {
        let fixture = try readings([pressure(118, label: "LOW"), probe(50)])
        let resolution = GaugeRoleResolver.resolve(fixture, hints: .init(probes: [.suction: "probe"]))
        XCTAssertEqual(resolution.probes[.suction]?.basis, .technician)
    }

    // MARK: - Pressure units

    func testDisplayedPressureUnitsParse() {
        XCTAssertEqual(GaugePressure.parse(value: 118, unit: "PSIG"), .init(value: 118, unit: .psi, reference: .gauge))
        XCTAssertEqual(GaugePressure.parse(value: 132, unit: "psia"), .init(value: 132, unit: .psi, reference: .absolute))
        XCTAssertEqual(GaugePressure.parse(value: 820, unit: "kPa(g)"), .init(value: 820, unit: .kPa, reference: .gauge))
        XCTAssertEqual(GaugePressure.parse(value: 921, unit: "kPa abs"), .init(value: 921, unit: .kPa, reference: .absolute))
        XCTAssertEqual(GaugePressure.parse(value: 0.82, unit: "MPa"), .init(value: 820, unit: .kPa, reference: .gauge))
        XCTAssertEqual(GaugePressure.parse(value: 8.2, unit: "bar"), .init(value: 8.2, unit: .bar, reference: .gauge))
        XCTAssertNil(GaugePressure.parse(value: 50, unit: "°F"))
        XCTAssertNil(GaugePressure.parse(value: 5, unit: "inWC"), "an unknown unit is not guessed at")
    }

    func testAVacuumOnTheCompoundScaleIsBelowAtmosphere() throws {
        let vacuum = try XCTUnwrap(GaugePressure.parse(value: 10, unit: "inHg"))
        XCTAssertEqual(vacuum.absoluteKPa(atmosphere: .seaLevel), 101.325 - 33.86389, accuracy: 1e-6)
        XCTAssertEqual(GaugePressure.parse(value: -10, unit: "inHg"), vacuum, "either sign is a vacuum")
    }
}
