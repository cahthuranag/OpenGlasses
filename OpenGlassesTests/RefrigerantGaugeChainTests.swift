import XCTest
@testable import OpenGlasses

/// A photograph of the gauges taken to an answer (Plan IS P1): the chain to superheat and
/// subcooling in both unit systems, pressures only without a refrigerant, the re-look line for an
/// out-of-band pressure, and questions where a role or a line temperature cannot be told. Model
/// output comes from fixtures through the instrument-reading schema; no model is called.
final class RefrigerantGaugeChainTests: XCTestCase {

    private typealias Chain = RefrigerantGaugeChain

    private func readings(_ items: [[String: Any]]) throws -> [InstrumentReading] {
        let json: [String: Any] = ["readings": items, "summary": "Fixture.", "confidence": 0.9]
        return try InstrumentReadingSchema().makeCard(from: json, context: nil).readings
    }

    private func item(_ quantity: String, _ value: Double, _ unit: String, label: String? = nil,
                      color: String? = nil, confidence: Double = 0.9) -> [String: Any] {
        var item: [String: Any] = ["quantity": quantity, "value": value, "unit": unit, "confidence": confidence]
        if let label { item["label"] = label }
        if let color { item["color"] = color }
        return item
    }

    private func table(_ designation: String) throws -> SaturationTable {
        try XCTUnwrap(SaturationTableCatalog.table(for: designation))
    }

    private func run(_ items: [[String: Any]], _ configure: (inout Chain.Request) throws -> Void) throws -> Chain.Outcome {
        var request = Chain.Request()
        try configure(&request)
        return Chain.run(readings: try readings(items), request: request) { SaturationTableCatalog.table(for: $0) }
    }

    private func shown(_ value: Double) -> String { DomainCalcTool.oneDecimal(value) }

    /// An analog manifold on an R-410A system: 118 psig on the blue LOW gauge, 380 psig on the red
    /// HIGH gauge, a suction clamp at 50 °F and a liquid clamp at 104 °F.
    private var imperialManifold: [[String: Any]] {
        [
            item("pressure", 118, "psig", label: "LOW", color: "blue"),
            item("pressure", 380, "psig", label: "HIGH", color: "red"),
            item("temperature", 50, "°F", label: "SUCTION"),
            item("temperature", 104, "°F", label: "LIQUID"),
        ]
    }

    private let nameplate = RefrigerantIdentity(designation: "R-410A", source: .nameplate)

    // MARK: - The chain, imperial

    func testSuperheatFromAnAnalogManifoldInPsigAndFahrenheit() throws {
        let outcome = try run(imperialManifold) {
            $0.calculations = [.superheat]
            $0.refrigerant = nameplate
            $0.units = .imperial
        }
        XCTAssertTrue(outcome.text.hasPrefix(
            "Superheat 10.2 °F: suction 118 psig is 39.8 °F dew for R-410A, line 50 °F."), outcome.text)
        XCTAssertTrue(outcome.text.contains("Saturation data: CoolProp 8.0.0. R-410A from the nameplate."), outcome.text)
        XCTAssertTrue(outcome.text.contains("Assumes sea-level atmosphere"), outcome.text)
        XCTAssertEqual(outcome.answered, [.superheat])
        XCTAssertFalse(outcome.asksQuestion)
        XCTAssertFalse(outcome.asksRecapture)
    }

    func testSubcoolingFromTheHighSideIsSaidAsTheHighSide() throws {
        let outcome = try run(imperialManifold) {
            $0.calculations = [.subcool]
            $0.refrigerant = nameplate
        }
        let kPa = RefrigerantPressure.absoluteKPa(gauge: 380, unit: .psi)
        let bubble = try table("R-410A").temperature(atAbsoluteKPa: kPa, scale: .fahrenheit, curve: .bubble).get()
        XCTAssertTrue(outcome.text.hasPrefix(
            "Subcooling \(shown(bubble - 104)) °F: high side 380 psig is \(shown(bubble)) °F bubble for R-410A, line 104 °F."),
            outcome.text)
    }

    func testBothCalculationsInOneTurn() throws {
        let outcome = try run(imperialManifold) { $0.refrigerant = nameplate }
        XCTAssertEqual(outcome.answered, [.superheat, .subcool])
        XCTAssertTrue(outcome.text.contains("Superheat 10.2 °F"), outcome.text)
        XCTAssertTrue(outcome.text.contains("Subcooling "), outcome.text)
        XCTAssertEqual(outcome.recordable.map(\.quantity), [
            "suction pressure", "high side pressure", "suction line temperature", "liquid line temperature",
        ])
        XCTAssertEqual(outcome.recordable.first?.value, "118")
        XCTAssertEqual(outcome.recordable.first?.unit, "psig")
        XCTAssertTrue(outcome.recordable.allSatisfy(\.fromInstrument))
    }

    // MARK: - The chain, metric

    func testSuperheatFromADigitalManifoldInKPaAndCelsius() throws {
        let outcome = try run([
            item("suction pressure", 820, "kPa", label: "SUCTION"),
            item("temperature", 10, "°C", label: "SUCTION"),
        ]) {
            $0.calculations = [.superheat]
            $0.refrigerant = RefrigerantIdentity(designation: "R-410A", source: .technician)
            $0.units = .metric
        }
        XCTAssertTrue(outcome.text.hasPrefix(
            "Superheat 5.4 K: suction 820 kPa is 4.6 °C dew for R-410A, line 10 °C."), outcome.text)
        XCTAssertTrue(outcome.text.contains("R-410A as you said."), outcome.text)
    }

    func testSubcoolingInBarWithTheSameAnswerInKelvinAsInFahrenheit() throws {
        let gaugeBar = 380 * RefrigerantPressure.Unit.psi.kPa / 100
        let liquidC = TemperatureScale.celsius.convert(104, from: .fahrenheit)
        let metric = try run([
            item("pressure", gaugeBar, "bar", label: "LIQ"),
            item("temperature", liquidC, "°C", label: "LIQ"),
        ]) {
            $0.calculations = [.subcool]
            $0.refrigerant = nameplate
            $0.units = RefrigerationUnits(pressure: .bar, temperature: .celsius, mass: .kg)
        }
        let kPa = RefrigerantPressure.absoluteKPa(gauge: 380, unit: .psi)
        let bubbleC = try table("R-410A").temperature(atAbsoluteKPa: kPa, scale: .celsius, curve: .bubble).get()
        XCTAssertTrue(metric.text.hasPrefix(
            "Subcooling \(shown(bubbleC - liquidC)) K: liquid \(shown(gaugeBar)) bar is \(shown(bubbleC)) °C bubble"),
            metric.text)
        let bubbleF = try table("R-410A").temperature(atAbsoluteKPa: kPa, scale: .fahrenheit, curve: .bubble).get()
        XCTAssertEqual((bubbleC - liquidC) * 1.8, bubbleF - 104, accuracy: 0.1,
                       "the same subcooling in either unit set")
    }

    func testAnswersFollowTheTechniciansUnitsWhateverTheGaugeShows() throws {
        let outcome = try run([item("pressure", 118, "psig", label: "LOW"), item("temperature", 50, "°F", label: "LOW")]) {
            $0.calculations = [.superheat]
            $0.refrigerant = nameplate
            $0.units = .metric
        }
        let kPa = RefrigerantPressure.absoluteKPa(gauge: 118, unit: .psi) - Atmosphere.seaLevelKPa
        XCTAssertTrue(outcome.text.contains("suction \(shown(kPa)) kPa (118 psig on the gauge)"), outcome.text)
        XCTAssertTrue(outcome.text.contains(" K: "), "a metric difference is in kelvin: \(outcome.text)")
        XCTAssertTrue(outcome.text.contains("line 10 °C"), outcome.text)
    }

    func testABlendSaysItsGlideAndUsesTheDewPoint() throws {
        let outcome = try run([item("pressure", 63, "psig", label: "LOW"), item("temperature", 55, "°F", label: "SUCTION")]) {
            $0.calculations = [.superheat]
            $0.refrigerant = RefrigerantIdentity(designation: "R-407C", source: .nameplate)
        }
        let kPa = RefrigerantPressure.absoluteKPa(gauge: 63, unit: .psi)
        let glide = try table("R-407C").glide(atAbsoluteKPa: kPa, scale: .fahrenheit).get()
        XCTAssertTrue(outcome.text.contains("Glide \(shown(glide)) °F at that pressure, so superheat uses the dew point."),
                      outcome.text)
    }

    func testASpokenLineTemperatureOutranksTheProbe() throws {
        let outcome = try run(imperialManifold) {
            $0.calculations = [.superheat]
            $0.refrigerant = nameplate
            $0.spokenLines = [.suction: .init(value: 52, scale: .fahrenheit)]
        }
        XCTAssertTrue(outcome.text.contains("line 52 °F"), outcome.text)
        XCTAssertTrue(outcome.recordable.contains {
            $0.quantity == "suction line temperature" && $0.value == "52" && !$0.fromInstrument
        })
    }

    func testAnAltitudeCorrectsTheGaugeAndSaysSo() throws {
        let outcome = try run(imperialManifold) {
            $0.calculations = [.superheat]
            $0.refrigerant = nameplate
            $0.atmosphere = try XCTUnwrap(Atmosphere.at(altitudeMetres: 1500))
            $0.altitudeText = "1500 m"
        }
        XCTAssertTrue(outcome.text.contains("Corrected for altitude 1500 m."), outcome.text)
        XCTAssertFalse(outcome.text.contains("sea-level"), outcome.text)
    }

    // MARK: - No refrigerant → pressures only

    func testWithoutARefrigerantThereArePressuresOnlyAndAQuestion() throws {
        let outcome = try run(imperialManifold) { $0.units = .imperial }
        XCTAssertEqual(outcome.text,
            "Readings: suction 118 psig, high side 380 psig, suction line 50 °F, liquid line 104 °F. "
            + "No saturation temperatures without the refrigerant. Which refrigerant is it? "
            + "It's on the nameplate; I won't assume one.")
        XCTAssertTrue(outcome.asksQuestion)
        XCTAssertTrue(outcome.answered.isEmpty)
        XCTAssertFalse(outcome.text.contains("dew"), "no saturation temperature without a refrigerant")
        XCTAssertEqual(outcome.recordable.count, 4, "the pressures are still recorded")
    }

    func testARefrigerantWithNoTableGivesPressuresOnly() throws {
        let outcome = try run(imperialManifold) {
            $0.refrigerant = RefrigerantIdentity(designation: "R-12", source: .technician)
        }
        XCTAssertTrue(outcome.text.hasPrefix("No saturation table for R-12, so pressures only."), outcome.text)
        XCTAssertFalse(outcome.text.contains("dew"))
    }

    // MARK: - Out of band → re-look

    func testThirtyPsigSuctionOnR410AInCoolingAsksForARelook() throws {
        let outcome = try run([item("pressure", 30, "psig", label: "LOW"), item("temperature", 50, "°F", label: "SUCTION")]) {
            $0.calculations = [.superheat]
            $0.refrigerant = nameplate
            $0.application = .cooling
        }
        let kPa = RefrigerantPressure.absoluteKPa(gauge: 30, unit: .psi)
        let dew = try table("R-410A").temperature(atAbsoluteKPa: kPa, scale: .fahrenheit, curve: .dew).get()
        XCTAssertEqual(outcome.text,
            "Re-look at the suction gauge: 30 psig is a \(shown(dew)) °F dew point for R-410A, "
            + "outside the 14 to 68 °F range for a suction line in cooling. "
            + "Check the reading and the hose before I give a number.")
        XCTAssertTrue(outcome.asksRecapture)
        XCTAssertTrue(outcome.answered.isEmpty, "no confident answer on an out-of-band reading")
        XCTAssertFalse(outcome.recordable.contains { $0.quantity == "suction pressure" },
                       "a reading flagged for a re-look is not recorded")
    }

    func testTheSameReadingWithNoApplicationIsNotFlagged() throws {
        let outcome = try run([item("pressure", 30, "psig", label: "LOW"), item("temperature", 0, "°F", label: "SUCTION")]) {
            $0.calculations = [.superheat]
            $0.refrigerant = nameplate
        }
        XCTAssertEqual(outcome.answered, [.superheat], "the unspecified window is wide: \(outcome.text)")
    }

    func testSwappedHosesInCoolingAreCaughtOnTheHighSide() throws {
        let outcome = try run([item("pressure", 118, "psig", label: "HIGH"), item("temperature", 104, "°F", label: "LIQUID")]) {
            $0.calculations = [.subcool]
            $0.refrigerant = nameplate
            $0.application = .cooling
            $0.units = .metric
        }
        XCTAssertTrue(outcome.text.hasPrefix("Re-look at the high side gauge:"), outcome.text)
        XCTAssertTrue(outcome.text.contains(
            "°C bubble point for R-410A, outside the 15 to 65 °C range for a high side line in cooling."), outcome.text)
    }

    // MARK: - Questions instead of guesses

    func testAnUnlabelledManifoldIsAskedNotGuessed() throws {
        let fixture: [[String: Any]] = [
            ["quantity": "pressure", "value": 118, "unit": "psig", "confidence": 0.9, "region": [0.1, 0.3, 0.3, 0.3]],
            ["quantity": "pressure", "value": 380, "unit": "psig", "confidence": 0.9, "region": [0.6, 0.3, 0.3, 0.3]],
        ]
        let outcome = try run(fixture) {
            $0.calculations = [.superheat]
            $0.refrigerant = nameplate
        }
        XCTAssertEqual(outcome.text, "Is the left gauge (118 psig) suction?")
        XCTAssertTrue(outcome.asksQuestion)
        XCTAssertTrue(outcome.recordable.isEmpty, "nothing is recorded under a role nobody confirmed")

        let answered = try run(fixture) {
            $0.calculations = [.superheat]
            $0.refrigerant = nameplate
            $0.hints = .init(gauges: [.suction: "left"])
            $0.spokenLines = [.suction: .init(value: 50, scale: .fahrenheit)]
        }
        XCTAssertTrue(answered.text.hasPrefix("Superheat 10.2 °F: suction 118 psig"), answered.text)
    }

    func testAMissingLineTemperatureIsAskedFor() throws {
        let outcome = try run([item("pressure", 118, "psig", label: "LOW")]) {
            $0.calculations = [.superheat]
            $0.refrigerant = nameplate
        }
        XCTAssertEqual(outcome.text, "What's the suction line temperature?")
        XCTAssertTrue(outcome.asksQuestion)
    }

    func testASingleGaugeAnswersWhatItCanAndSaysWhatIsMissing() throws {
        let outcome = try run([item("pressure", 118, "psig", label: "LOW"), item("temperature", 50, "°F", label: "SUCTION")]) {
            $0.refrigerant = nameplate
        }
        XCTAssertEqual(outcome.answered, [.superheat])
        XCTAssertTrue(outcome.text.contains("I can't see a liquid or high-side gauge in the picture."), outcome.text)
    }

    // MARK: - Unclear readings

    func testALowConfidenceGaugeIsRecapturedNotUsed() throws {
        let outcome = try run([item("pressure", 118, "psig", label: "LOW", confidence: 0.3)]) {
            $0.refrigerant = nameplate
        }
        XCTAssertEqual(outcome.text, "Re-capture the gauges: the pressure wasn't clear enough to read.")
        XCTAssertTrue(outcome.asksRecapture)
    }

    func testNoPressureInThePicture() throws {
        let outcome = try run([item("temperature", 50, "°F")]) { $0.refrigerant = nameplate }
        XCTAssertTrue(outcome.text.hasPrefix("I can't read a pressure in the picture."), outcome.text)
    }
}
