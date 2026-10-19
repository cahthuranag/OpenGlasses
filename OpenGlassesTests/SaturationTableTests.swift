import XCTest
@testable import OpenGlasses

/// The bundled saturation tables and `SaturationTable`'s lookups (Plan IS P0): the catalog and the
/// bundle agree, both grids have the planned shape, out-of-range is refused by name, glide is right
/// for a glide blend and a near-azeotrope, and the °C/kPa and °F/psig grids agree.
@MainActor
final class SaturationTableTests: XCTestCase {

    private func load(_ designation: String) throws -> SaturationTable {
        try XCTUnwrap(SaturationTableCatalog.table(for: designation), designation)
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    // MARK: - Catalog and bundle

    func testEveryCatalogTableIsInTheAppBundle() throws {
        for designation in SaturationTableCatalog.designations {
            XCTAssertNotNil(Bundle.main.url(forResource: designation, withExtension: "json"),
                            "\(designation).json is not in the app bundle")
            XCTAssertEqual(try load(designation).designation, designation)
        }
    }

    func testTheCatalogListsExactlyTheGeneratedFiles() throws {
        let folder = Self.repoRoot.appendingPathComponent("OpenGlasses/Sources/Resources/Refrigerants")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
        XCTAssertEqual(Set(files), Set(SaturationTableCatalog.designations))
    }

    func testThePlannedFirstSetIsPresent() {
        let firstSet = ["R-22", "R-32", "R-134a", "R-404A", "R-407A", "R-407C", "R-410A", "R-507A",
                        "R-290", "R-600a", "R-744", "R-1234yf"]
        XCTAssertTrue(Set(firstSet).isSubset(of: Set(SaturationTableCatalog.designations)))
    }

    func testEveryTableCarriesItsSource() throws {
        for designation in SaturationTableCatalog.designations {
            let table = try load(designation)
            XCTAssertTrue(table.source.contains("CoolProp \(table.libraryVersion)"), designation)
            XCTAssertTrue(table.licence.contains("MIT"), designation)
            XCTAssertEqual(table.generatedWith, "Scripts/generate-pt-tables.py", designation)
            XCTAssertEqual(table.sourceName, "CoolProp \(table.libraryVersion)", designation)
            XCTAssertFalse(table.equationOfState.isEmpty, designation)
        }
    }

    func testBothGridsHaveThePlannedShape() throws {
        for designation in SaturationTableCatalog.designations where designation != "R-744" {
            let table = try load(designation)
            XCTAssertEqual(table.fahrenheit.start, -40)
            XCTAssertEqual(table.fahrenheit.end, 150)
            XCTAssertEqual(table.fahrenheit.step, 1)
            XCTAssertEqual(table.celsius.start, -40)
            XCTAssertEqual(table.celsius.end, 65)
            XCTAssertEqual(table.celsius.step, 0.5)
            for grid in [table.fahrenheit, table.celsius] {
                let count = Int(((grid.end - grid.start) / grid.step).rounded()) + 1
                XCTAssertEqual(grid.dew.count, count, designation)
                XCTAssertEqual(grid.bubble.count, count, designation)
            }
            XCTAssertEqual(table.fahrenheit.dew.count, 191, designation)
            XCTAssertEqual(table.celsius.dew.count, 211, designation)
            XCTAssertFalse(table.endsAtCriticalPoint, designation)
        }
    }

    func testSeriesAreStrictlyIncreasing() throws {
        for designation in SaturationTableCatalog.designations {
            let table = try load(designation)
            for grid in [table.fahrenheit, table.celsius] {
                for series in [grid.dew, grid.bubble] {
                    XCTAssertTrue(zip(series, series.dropFirst()).allSatisfy { $0 < $1 }, designation)
                }
            }
        }
    }

    func testBubblePressureIsNeverBelowDewPressure() throws {
        for designation in SaturationTableCatalog.designations {
            let table = try load(designation)
            for grid in [table.fahrenheit, table.celsius] {
                XCTAssertTrue(zip(grid.bubble, grid.dew).allSatisfy { $0 >= $1 }, designation)
            }
        }
    }

    func testCarbonDioxideStopsAtItsCriticalPoint() throws {
        let table = try load("R-744")
        XCTAssertTrue(table.endsAtCriticalPoint)
        XCTAssertEqual(table.fahrenheit.end, 87)
        XCTAssertEqual(table.celsius.end, 30.5)
        let criticalF = TemperatureScale.fahrenheit.fromKelvin(table.criticalTemperatureK)
        XCTAssertEqual(criticalF, 87.76, accuracy: 0.01)
        XCTAssertLessThan(table.fahrenheit.end, criticalF)
        XCTAssertGreaterThan(table.fahrenheit.end + table.fahrenheit.step, criticalF)
    }

    // MARK: - Designations

    func testDesignationsNormalise() {
        XCTAssertEqual(SaturationTableCatalog.designation(for: "410a"), "R-410A")
        XCTAssertEqual(SaturationTableCatalog.designation(for: "R410A"), "R-410A")
        XCTAssertEqual(SaturationTableCatalog.designation(for: "r-410a"), "R-410A")
        XCTAssertEqual(SaturationTableCatalog.designation(for: " R 22 "), "R-22")
        XCTAssertEqual(SaturationTableCatalog.designation(for: "R-1234YF"), "R-1234yf")
        XCTAssertEqual(SaturationTableCatalog.designation(for: "1234yf"), "R-1234yf")
        XCTAssertEqual(SaturationTableCatalog.designation(for: "HFC-134a"), "R-134a")
        XCTAssertEqual(SaturationTableCatalog.designation(for: "HCFC-22"), "R-22")
        XCTAssertEqual(SaturationTableCatalog.designation(for: "propane"), "R-290")
        XCTAssertEqual(SaturationTableCatalog.designation(for: "Isobutane"), "R-600a")
        XCTAssertEqual(SaturationTableCatalog.designation(for: "CO2"), "R-744")
        XCTAssertEqual(SaturationTableCatalog.designation(for: "R744"), "R-744")
    }

    func testUnknownDesignationsFindNothing() {
        // Never a neighbouring refrigerant's table: decision 3.
        XCTAssertNil(SaturationTableCatalog.designation(for: "R-999"))
        XCTAssertNil(SaturationTableCatalog.designation(for: "R-448A"))
        XCTAssertNil(SaturationTableCatalog.designation(for: "R-410"))
        XCTAssertNil(SaturationTableCatalog.designation(for: ""))
        XCTAssertNil(SaturationTableCatalog.table(for: "R-449A"))
    }

    // MARK: - Lookups and refusals

    func testOnGridValuesAreReturnedExactly() throws {
        let table = try load("R-22")
        let value = try table.absolutePressureKPa(atTemperature: 50, scale: .fahrenheit, curve: .dew).get()
        XCTAssertEqual(value, table.fahrenheit.dew[90])
        let back = try table.temperature(atAbsoluteKPa: value, scale: .fahrenheit, curve: .dew).get()
        XCTAssertEqual(back, 50, accuracy: 1e-9)
        let last = try table.absolutePressureKPa(atTemperature: 150, scale: .fahrenheit, curve: .bubble).get()
        XCTAssertEqual(last, table.fahrenheit.bubble.last)
    }

    func testPressureBelowTheTableIsRefusedByName() throws {
        let table = try load("R-410A")
        let result = table.temperature(atAbsoluteKPa: 50, scale: .fahrenheit, curve: .dew)
        XCTAssertEqual(result, .failure(.pressureBelowTable(designation: "R-410A",
                                                            minimumKPa: table.fahrenheit.dew[0])))
    }

    func testPressureAboveTheTableIsRefusedByName() throws {
        let table = try load("R-410A")
        let result = table.temperature(atAbsoluteKPa: 10_000, scale: .celsius, curve: .bubble)
        XCTAssertEqual(result, .failure(.pressureAboveTable(designation: "R-410A",
                                                            maximumKPa: try XCTUnwrap(table.celsius.bubble.last),
                                                            aboveCritical: false)))
    }

    func testPressureAboveCarbonDioxidesCriticalPointSaysSo() throws {
        let table = try load("R-744")
        guard case .failure(.pressureAboveTable(let designation, _, let aboveCritical)) =
                table.temperature(atAbsoluteKPa: 8_000, scale: .fahrenheit, curve: .dew) else {
            return XCTFail("expected a refusal")
        }
        XCTAssertEqual(designation, "R-744")
        XCTAssertTrue(aboveCritical)
    }

    func testTemperatureOutsideTheGridIsRefused() throws {
        let table = try load("R-134a")
        XCTAssertEqual(table.absolutePressureKPa(atTemperature: 151, scale: .fahrenheit, curve: .dew),
                       .failure(.temperatureOutOfTable(designation: "R-134a", minimum: -40, maximum: 150,
                                                       scale: .fahrenheit)))
        XCTAssertEqual(table.absolutePressureKPa(atTemperature: -40.5, scale: .celsius, curve: .bubble),
                       .failure(.temperatureOutOfTable(designation: "R-134a", minimum: -40, maximum: 65,
                                                       scale: .celsius)))
        let co2 = try load("R-744")
        if case .success = co2.absolutePressureKPa(atTemperature: 31, scale: .celsius, curve: .dew) {
            XCTFail("R-744 has no saturation pressure above its critical point")
        }
    }

    // MARK: - Glide

    func testR407CGlideIsAboutTenDegreesFahrenheit() throws {
        let table = try load("R-407C")
        for psig in [40.0, 63, 80, 120] {
            let kPa = RefrigerantPressure.absoluteKPa(gauge: psig, unit: .psi)
            let glide = try table.glide(atAbsoluteKPa: kPa, scale: .fahrenheit).get()
            XCTAssertEqual(glide, 10.5, accuracy: 1.5, "R-407C glide at \(psig) psig")
        }
        // In metric the same glide is about 5.5 to 6 K.
        let kPa = RefrigerantPressure.absoluteKPa(gauge: 435, unit: .kPa)
        XCTAssertEqual(try table.glide(atAbsoluteKPa: kPa, scale: .celsius).get(), 6.1, accuracy: 0.6)
    }

    func testR410AGlideIsNearZero() throws {
        let table = try load("R-410A")
        for psig in [60.0, 118, 300, 400] {
            let kPa = RefrigerantPressure.absoluteKPa(gauge: psig, unit: .psi)
            let glide = try table.glide(atAbsoluteKPa: kPa, scale: .fahrenheit).get()
            XCTAssertGreaterThanOrEqual(glide, 0)
            XCTAssertLessThan(glide, 0.3, "R-410A glide at \(psig) psig")
        }
    }

    func testSingleComponentRefrigerantsHaveNoGlide() throws {
        for designation in ["R-22", "R-32", "R-134a", "R-290", "R-600a", "R-744", "R-1234yf"] {
            let table = try load(designation)
            XCTAssertTrue(table.isSingleComponent, designation)
            XCTAssertEqual(table.fahrenheit.dew, table.fahrenheit.bubble, designation)
            XCTAssertEqual(table.celsius.dew, table.celsius.bubble, designation)
        }
        for designation in ["R-404A", "R-407A", "R-407C", "R-410A", "R-454B", "R-507A"] {
            XCTAssertFalse(try load(designation).isSingleComponent, designation)
        }
    }

    // MARK: - The two grids agree

    func testMinusFortyRowsAgreeExactly() throws {
        for designation in SaturationTableCatalog.designations {
            let table = try load(designation)
            XCTAssertEqual(table.fahrenheit.dew[0], table.celsius.dew[0], designation)
            XCTAssertEqual(table.fahrenheit.bubble[0], table.celsius.bubble[0], designation)
        }
    }

    func testTenCelsiusAndFiftyFahrenheitAgreeWithinATenthOfAKilopascal() throws {
        for designation in SaturationTableCatalog.designations {
            let table = try load(designation)
            for curve in SaturationCurve.allCases {
                let celsius = try table.absolutePressureKPa(atTemperature: 10, scale: .celsius, curve: curve).get()
                let fahrenheit = try table.absolutePressureKPa(atTemperature: 50, scale: .fahrenheit, curve: curve).get()
                XCTAssertEqual(celsius, fahrenheit, accuracy: 0.1, "\(designation) \(curve)")
            }
        }
    }

    func testMetricAndImperialLookupsRoundTrip() throws {
        // A gauge reading in psig on the °F grid and the same pressure in kPa(g) on the °C grid give
        // the same saturation temperature, to the interpolation error.
        for designation in SaturationTableCatalog.designations {
            let table = try load(designation)
            for psig in [5.0, 35, 68.5, 118, 160] {
                let fromPsig = RefrigerantPressure.absoluteKPa(gauge: psig, unit: .psi)
                let kPaGauge = RefrigerantPressure.gauge(absoluteKPa: fromPsig, unit: .kPa)
                let fromKPa = RefrigerantPressure.absoluteKPa(gauge: kPaGauge, unit: .kPa)
                XCTAssertEqual(fromKPa, fromPsig, accuracy: 1e-9)
                for curve in SaturationCurve.allCases {
                    guard case .success(let tempF) = table.temperature(atAbsoluteKPa: fromPsig,
                                                                       scale: .fahrenheit, curve: curve),
                          case .success(let tempC) = table.temperature(atAbsoluteKPa: fromKPa,
                                                                       scale: .celsius, curve: curve) else {
                        continue   // outside this refrigerant's range on one grid: refused on both
                    }
                    XCTAssertEqual(TemperatureScale.celsius.convert(tempF, from: .fahrenheit), tempC,
                                   accuracy: 0.02, "\(designation) \(curve) at \(psig) psig")
                }
            }
        }
    }

    func testPressureUnitsRoundTripAtSeaLevelAndAltitude() throws {
        let altitude = try XCTUnwrap(Atmosphere.at(altitudeMetres: 1_500))
        for atmosphere in [Atmosphere.seaLevel, altitude] {
            let absolute = RefrigerantPressure.absoluteKPa(gauge: 118, unit: .psi, atmosphere: atmosphere)
            let kPaGauge = RefrigerantPressure.gauge(absoluteKPa: absolute, unit: .kPa, atmosphere: atmosphere)
            let barGauge = RefrigerantPressure.gauge(absoluteKPa: absolute, unit: .bar, atmosphere: atmosphere)
            XCTAssertEqual(kPaGauge, 118 * 6.894757293168361, accuracy: 1e-9)
            XCTAssertEqual(barGauge, kPaGauge / 100, accuracy: 1e-12)
            XCTAssertEqual(RefrigerantPressure.gauge(absoluteKPa: absolute, unit: .psi, atmosphere: atmosphere),
                           118, accuracy: 1e-9)
            XCTAssertEqual(RefrigerantPressure.absoluteKPa(gauge: barGauge, unit: .bar, atmosphere: atmosphere),
                           absolute, accuracy: 1e-9)
            XCTAssertEqual(absolute - atmosphere.pressureKPa, kPaGauge, accuracy: 1e-9)
        }
        XCTAssertEqual(RefrigerantPressure.absoluteKPa(absolute: 2, unit: .bar), 200)
    }

    func testTemperatureConversions() {
        XCTAssertEqual(TemperatureScale.celsius.convert(-40, from: .fahrenheit), -40, accuracy: 1e-9)
        XCTAssertEqual(TemperatureScale.fahrenheit.convert(100, from: .celsius), 212, accuracy: 1e-9)
        XCTAssertEqual(TemperatureScale.celsius.toKelvin(0), 273.15, accuracy: 1e-12)
        XCTAssertEqual(TemperatureScale.fahrenheit.differenceSymbol, "°F")
        XCTAssertEqual(TemperatureScale.celsius.differenceSymbol, "K")
    }

    // MARK: - Atmosphere

    func testSeaLevelIsTheStandardAtmosphere() {
        XCTAssertEqual(Atmosphere.seaLevel.pressureKPa, 101.325)
        XCTAssertTrue(Atmosphere.seaLevel.assumesSeaLevel)
        XCTAssertEqual(try XCTUnwrap(Atmosphere.at(altitudeMetres: 0)).pressureKPa, 101.325, accuracy: 1e-9)
    }

    func testAltitudeFollowsTheISAFormula() throws {
        // 101.325 × (1 − 2.25577e-5 × 1500)^5.25588 = 84.556 kPa.
        let metres = try XCTUnwrap(Atmosphere.at(altitudeMetres: 1_500))
        XCTAssertEqual(metres.pressureKPa, 84.556, accuracy: 0.001)
        XCTAssertFalse(metres.assumesSeaLevel)
        // 5,000 ft is 1,524 m.
        let feet = try XCTUnwrap(Atmosphere.at(altitudeFeet: 5_000))
        XCTAssertEqual(feet.altitudeMetres ?? 0, 1_524, accuracy: 1e-9)
        XCTAssertEqual(feet.pressureKPa, 84.307, accuracy: 0.001)
    }

    func testAltitudeOutsideTheAcceptedRangeIsRefused() {
        XCTAssertNil(Atmosphere.at(altitudeMetres: 7_000))
        XCTAssertNil(Atmosphere.at(altitudeMetres: -600))
        XCTAssertNil(Atmosphere.at(altitudeMetres: .nan))
        XCTAssertNil(Atmosphere.at(altitudeFeet: 25_000))
    }

    func testAltitudeLowersTheSaturationTemperatureForTheSameGaugeReading() throws {
        let table = try load("R-410A")
        let altitude = try XCTUnwrap(Atmosphere.at(altitudeFeet: 5_000))
        let seaLevel = try table.temperature(atAbsoluteKPa: RefrigerantPressure.absoluteKPa(gauge: 118, unit: .psi),
                                             scale: .fahrenheit, curve: .dew).get()
        let high = try table.temperature(atAbsoluteKPa: RefrigerantPressure.absoluteKPa(gauge: 118, unit: .psi,
                                                                                        atmosphere: altitude),
                                         scale: .fahrenheit, curve: .dew).get()
        XCTAssertEqual(seaLevel, 39.84, accuracy: 0.05)
        XCTAssertEqual(high, 38.75, accuracy: 0.05)
    }
}
