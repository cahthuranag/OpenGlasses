import XCTest
@testable import OpenGlasses

/// `InstrumentPlausibility`'s per-refrigerant bands (Plan IS P1): each one is a saturation-
/// temperature window converted through the refrigerant's own table, held in SI, and never a typed
/// pressure.
final class RefrigerantPressureBandTests: XCTestCase {

    private typealias Plausibility = InstrumentPlausibility

    private func table(_ designation: String) throws -> SaturationTable {
        try XCTUnwrap(SaturationTableCatalog.table(for: designation))
    }

    func testABandIsTheWindowConvertedThroughTheTable() throws {
        let r410a = try table("R-410A")
        let band = try XCTUnwrap(Plausibility.refrigerantBand(table: r410a, role: .suction, application: .cooling))
        let window = Plausibility.saturationWindowCelsius(role: .suction, application: .cooling)
        XCTAssertEqual(band.lowKPa,
                       try r410a.absolutePressureKPa(atTemperature: window.lowerBound, scale: .celsius, curve: .dew).get())
        XCTAssertEqual(band.highKPa,
                       try r410a.absolutePressureKPa(atTemperature: window.upperBound, scale: .celsius, curve: .dew).get())
        XCTAssertEqual(band.windowKelvin.lowerBound, window.lowerBound + 273.15, accuracy: 1e-9, "held in SI")
    }

    func testTheLiquidLineIsReadOnTheBubbleCurve() throws {
        let r407c = try table("R-407C")
        let band = try XCTUnwrap(Plausibility.refrigerantBand(table: r407c, role: .liquid, application: .cooling))
        XCTAssertEqual(band.lowKPa, try r407c.absolutePressureKPa(atTemperature: 15, scale: .celsius, curve: .bubble).get())
        XCTAssertNotEqual(band.lowKPa, try r407c.absolutePressureKPa(atTemperature: 15, scale: .celsius, curve: .dew).get(),
                          "a blend's curves differ, and the liquid line is liquid")
    }

    func testThirtyPsigSuctionOnR410AInCoolingIsOutOfBandAndAWorkingOneIsIn() throws {
        let band = try XCTUnwrap(Plausibility.refrigerantBand(table: try table("R-410A"), role: .suction,
                                                               application: .cooling))
        XCTAssertFalse(band.contains(absoluteKPa: RefrigerantPressure.absoluteKPa(gauge: 30, unit: .psi)))
        XCTAssertTrue(band.contains(absoluteKPa: RefrigerantPressure.absoluteKPa(gauge: 118, unit: .psi)))
        XCTAssertTrue(band.contains(absoluteKPa: RefrigerantPressure.absoluteKPa(gauge: 820, unit: .kPa)))
    }

    func testTheBandsDependOnTheRefrigerant() throws {
        // 140 psig is a working R-410A suction and not an R-22 one in cooling (R-22 at 140 psig is
        // a dew point near 26 °C, above the comfort-cooling window).
        let r22 = try XCTUnwrap(Plausibility.refrigerantBand(table: try table("R-22"), role: .suction,
                                                             application: .cooling))
        let r410a = try XCTUnwrap(Plausibility.refrigerantBand(table: try table("R-410A"), role: .suction,
                                                               application: .cooling))
        XCTAssertFalse(r22.contains(absoluteKPa: RefrigerantPressure.absoluteKPa(gauge: 140, unit: .psi)))
        XCTAssertTrue(r410a.contains(absoluteKPa: RefrigerantPressure.absoluteKPa(gauge: 140, unit: .psi)))
        XCTAssertTrue(r22.contains(absoluteKPa: RefrigerantPressure.absoluteKPa(gauge: 68, unit: .psi)))
    }

    func testAWindowPastTheTableHasNoUpperBound() throws {
        let r744 = try table("R-744")
        XCTAssertTrue(r744.endsAtCriticalPoint)
        let band = try XCTUnwrap(Plausibility.refrigerantBand(table: r744, role: .discharge, application: .refrigeration))
        XCTAssertNil(band.highKPa, "above the critical point the lookup's own refusal speaks")
        XCTAssertTrue(band.contains(absoluteKPa: 9_000))
    }

    func testAnUnspecifiedApplicationIsTheWidestWindow() {
        for role in GaugeRole.allCases {
            let wide = Plausibility.saturationWindowCelsius(role: role, application: .unspecified)
            for application in Plausibility.RefrigerantApplication.allCases {
                let window = Plausibility.saturationWindowCelsius(role: role, application: application)
                XCTAssertLessThanOrEqual(wide.lowerBound, window.lowerBound, "\(role) \(application)")
                XCTAssertGreaterThanOrEqual(wide.upperBound, window.upperBound, "\(role) \(application)")
            }
        }
    }

    func testEveryBundledTableYieldsABandForEveryRoleAndApplication() throws {
        for designation in SaturationTableCatalog.designations {
            let table = try table(designation)
            for role in GaugeRole.allCases {
                for application in Plausibility.RefrigerantApplication.allCases {
                    let band = try XCTUnwrap(Plausibility.refrigerantBand(table: table, role: role,
                                                                           application: application),
                                             "\(designation) \(role) \(application)")
                    if let high = band.highKPa { XCTAssertLessThan(band.lowKPa, high) }
                }
            }
        }
    }
}
