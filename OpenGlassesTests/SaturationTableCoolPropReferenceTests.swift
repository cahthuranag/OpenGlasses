import XCTest
@testable import OpenGlasses

/// Every bundled saturation table against CoolProp's own values (Plan IS P0 exit test).
///
/// The reference rows below are fixed test data: they were printed by
/// `Scripts/generate-pt-tables.py --check-points` with the pinned CoolProp, at a dozen temperatures
/// per refrigerant — most of them between grid points, so the interpolation is checked as well as
/// the stored values. Regenerating the tables at a new CoolProp version means re-printing these rows
/// in the same change.
@MainActor
final class SaturationTableCoolPropReferenceTests: XCTestCase {

    static let referenceVersion = "8.0.0"

    // CoolProp 8.0.0 (git ae81610e7d23efc57f9d051c8e70a4d66e87537f), printed by Scripts/generate-pt-tables.py --check-points
    // (designation, unit, temperature, dew kPa abs, bubble kPa abs)
    static let reference: [(designation: String, scale: TemperatureScale, temperature: Double, dewKPa: Double, bubbleKPa: Double)] = [
        ("R-22", .fahrenheit, -37.3, 112.7732, 112.7732),
        ("R-22", .fahrenheit, 0.0, 267.0220, 267.0220),
        ("R-22", .fahrenheit, 12.6, 345.1372, 345.1372),
        ("R-22", .fahrenheit, 25.25, 439.9590, 439.9590),
        ("R-22", .fahrenheit, 40.0, 574.0249, 574.0249),
        ("R-22", .fahrenheit, 47.7, 655.1367, 655.1367),
        ("R-22", .fahrenheit, 66.4, 887.6196, 887.6196),
        ("R-22", .fahrenheit, 85.5, 1183.2723, 1183.2723),
        ("R-22", .celsius, -21.3, 233.2580, 233.2580),
        ("R-22", .celsius, 4.75, 579.5547, 579.5547),
        ("R-22", .celsius, 18.2, 865.0885, 865.0885),
        ("R-22", .celsius, 27.9, 1127.9644, 1127.9644),
        ("R-32", .fahrenheit, -37.3, 189.8074, 189.8074),
        ("R-32", .fahrenheit, 0.0, 440.9013, 440.9013),
        ("R-32", .fahrenheit, 12.6, 567.0738, 567.0738),
        ("R-32", .fahrenheit, 25.25, 719.7929, 719.7929),
        ("R-32", .fahrenheit, 40.0, 935.2552, 935.2552),
        ("R-32", .fahrenheit, 47.7, 1065.4766, 1065.4766),
        ("R-32", .fahrenheit, 66.4, 1438.6066, 1438.6066),
        ("R-32", .fahrenheit, 85.5, 1913.6649, 1913.6649),
        ("R-32", .celsius, -21.3, 386.2158, 386.2158),
        ("R-32", .celsius, 4.75, 944.1352, 944.1352),
        ("R-32", .celsius, 18.2, 1402.4382, 1402.4382),
        ("R-32", .celsius, 27.9, 1824.7128, 1824.7128),
        ("R-134a", .fahrenheit, -37.3, 55.3710, 55.3710),
        ("R-134a", .fahrenheit, 0.0, 145.9684, 145.9684),
        ("R-134a", .fahrenheit, 12.6, 194.5170, 194.5170),
        ("R-134a", .fahrenheit, 25.25, 255.0516, 255.0516),
        ("R-134a", .fahrenheit, 40.0, 342.9547, 342.9547),
        ("R-134a", .fahrenheit, 47.7, 397.1999, 397.1999),
        ("R-134a", .fahrenheit, 66.4, 556.1589, 556.1589),
        ("R-134a", .fahrenheit, 85.5, 764.0670, 764.0670),
        ("R-134a", .celsius, -21.3, 125.4424, 125.4424),
        ("R-134a", .celsius, 4.75, 346.6295, 346.6295),
        ("R-134a", .celsius, 18.2, 540.5567, 540.5567),
        ("R-134a", .celsius, 27.9, 724.7644, 724.7644),
        ("R-404A", .fahrenheit, -37.3, 140.1854, 144.6705),
        ("R-404A", .fahrenheit, 0.0, 326.1556, 333.3994),
        ("R-404A", .fahrenheit, 12.6, 419.2626, 427.5404),
        ("R-404A", .fahrenheit, 25.25, 531.6992, 541.0387),
        ("R-404A", .fahrenheit, 40.0, 689.9221, 700.4977),
        ("R-404A", .fahrenheit, 47.7, 785.3542, 796.5600),
        ("R-404A", .fahrenheit, 66.4, 1058.1512, 1070.7869),
        ("R-404A", .fahrenheit, 85.5, 1404.4152, 1418.2539),
        ("R-404A", .celsius, -21.3, 285.7337, 292.4721),
        ("R-404A", .celsius, 4.75, 696.4341, 707.0553),
        ("R-404A", .celsius, 18.2, 1031.7449, 1044.2631),
        ("R-404A", .celsius, 27.9, 1339.6510, 1353.3085),
        ("R-407A", .fahrenheit, -37.3, 101.7925, 137.5390),
        ("R-407A", .fahrenheit, 0.0, 256.5197, 323.5517),
        ("R-407A", .fahrenheit, 12.6, 337.3110, 417.4074),
        ("R-407A", .fahrenheit, 25.25, 436.8138, 531.1427),
        ("R-407A", .fahrenheit, 40.0, 579.5760, 691.6906),
        ("R-407A", .fahrenheit, 47.7, 666.9182, 788.7151),
        ("R-407A", .fahrenheit, 66.4, 920.5523, 1066.4936),
        ("R-407A", .fahrenheit, 85.5, 1248.9277, 1419.3090),
        ("R-407A", .celsius, -21.3, 222.0110, 282.9263),
        ("R-407A", .celsius, 4.75, 585.5091, 698.3075),
        ("R-407A", .celsius, 18.2, 895.7794, 1039.5888),
        ("R-407A", .celsius, 27.9, 1187.0569, 1353.3351),
        ("R-407C", .fahrenheit, -37.3, 92.3839, 128.8521),
        ("R-407C", .fahrenheit, 0.0, 235.3251, 304.6795),
        ("R-407C", .fahrenheit, 12.6, 310.4343, 393.7014),
        ("R-407C", .fahrenheit, 25.25, 403.2241, 501.7595),
        ("R-407C", .fahrenheit, 40.0, 536.7672, 654.5462),
        ("R-407C", .fahrenheit, 47.7, 618.6571, 746.9925),
        ("R-407C", .fahrenheit, 66.4, 857.0654, 1012.0131),
        ("R-407C", .fahrenheit, 85.5, 1166.6966, 1349.1750),
        ("R-407C", .celsius, -21.3, 203.3235, 266.1987),
        ("R-407C", .celsius, 4.75, 542.3258, 660.8485),
        ("R-407C", .celsius, 18.2, 833.7460, 986.3248),
        ("R-407C", .celsius, 27.9, 1108.2919, 1286.0901),
        ("R-410A", .fahrenheit, -37.3, 187.0579, 187.7471),
        ("R-410A", .fahrenheit, 0.0, 433.7863, 435.2768),
        ("R-410A", .fahrenheit, 12.6, 557.4401, 559.3207),
        ("R-410A", .fahrenheit, 25.25, 706.8826, 709.2263),
        ("R-410A", .fahrenheit, 40.0, 917.3715, 920.3545),
        ("R-410A", .fahrenheit, 47.7, 1044.4214, 1047.7840),
        ("R-410A", .fahrenheit, 66.4, 1407.9295, 1412.3530),
        ("R-410A", .fahrenheit, 85.5, 1869.9548, 1875.6566),
        ("R-410A", .celsius, -21.3, 380.1315, 381.4505),
        ("R-410A", .celsius, 4.75, 926.0389, 929.0479),
        ("R-410A", .celsius, 18.2, 1372.7228, 1377.0453),
        ("R-410A", .celsius, 27.9, 1783.4885, 1788.9590),
        ("R-454B", .fahrenheit, -37.3, 170.8128, 180.7460),
        ("R-454B", .fahrenheit, 0.0, 397.1721, 417.8922),
        ("R-454B", .fahrenheit, 12.6, 510.8480, 536.6001),
        ("R-454B", .fahrenheit, 25.25, 648.3983, 679.9684),
        ("R-454B", .fahrenheit, 40.0, 842.4094, 881.7328),
        ("R-454B", .fahrenheit, 47.7, 959.6516, 1003.4197),
        ("R-454B", .fahrenheit, 66.4, 1295.5988, 1351.1463),
        ("R-454B", .fahrenheit, 85.5, 1723.4925, 1792.0291),
        ("R-454B", .celsius, -21.3, 347.8902, 366.3583),
        ("R-454B", .celsius, 4.75, 850.4046, 890.0367),
        ("R-454B", .celsius, 18.2, 1263.0317, 1317.4984),
        ("R-454B", .celsius, 27.9, 1643.3473, 1709.6232),
        ("R-507A", .fahrenheit, -37.3, 148.2578, 148.2822),
        ("R-507A", .fahrenheit, 0.0, 341.2544, 341.4152),
        ("R-507A", .fahrenheit, 12.6, 437.4444, 437.6907),
        ("R-507A", .fahrenheit, 25.25, 553.3687, 553.7244),
        ("R-507A", .fahrenheit, 40.0, 716.1718, 716.6869),
        ("R-507A", .fahrenheit, 47.7, 814.2186, 814.8311),
        ("R-507A", .fahrenheit, 66.4, 1094.0120, 1094.9049),
        ("R-507A", .fahrenheit, 85.5, 1448.3966, 1449.6405),
        ("R-507A", .celsius, -21.3, 299.4233, 299.5493),
        ("R-507A", .celsius, 4.75, 722.8655, 723.3871),
        ("R-507A", .celsius, 18.2, 1066.9551, 1067.8209),
        ("R-507A", .celsius, 27.9, 1382.1642, 1383.3434),
        ("R-290", .fahrenheit, -37.3, 118.5080, 118.5080),
        ("R-290", .fahrenheit, 0.0, 264.6798, 264.6798),
        ("R-290", .fahrenheit, 12.6, 336.4811, 336.4811),
        ("R-290", .fahrenheit, 25.25, 422.4015, 422.4015),
        ("R-290", .fahrenheit, 40.0, 542.1739, 542.1739),
        ("R-290", .fahrenheit, 47.7, 613.8829, 613.8829),
        ("R-290", .fahrenheit, 66.4, 817.0421, 817.0421),
        ("R-290", .fahrenheit, 85.5, 1071.6363, 1071.6363),
        ("R-290", .celsius, -21.3, 233.2775, 233.2775),
        ("R-290", .celsius, 4.75, 547.0790, 547.0790),
        ("R-290", .celsius, 18.2, 797.4838, 797.4838),
        ("R-290", .celsius, 27.9, 1024.2694, 1024.2694),
        ("R-600a", .fahrenheit, -37.3, 30.9632, 30.9632),
        ("R-600a", .fahrenheit, 0.0, 79.5153, 79.5153),
        ("R-600a", .fahrenheit, 12.6, 105.2351, 105.2351),
        ("R-600a", .fahrenheit, 25.25, 137.1354, 137.1354),
        ("R-600a", .fahrenheit, 40.0, 183.2156, 183.2156),
        ("R-600a", .fahrenheit, 47.7, 211.5403, 211.5403),
        ("R-600a", .fahrenheit, 66.4, 294.1647, 294.1647),
        ("R-600a", .fahrenheit, 85.5, 401.5660, 401.5660),
        ("R-600a", .celsius, -21.3, 68.5929, 68.5929),
        ("R-600a", .celsius, 4.75, 185.1369, 185.1369),
        ("R-600a", .celsius, 18.2, 286.0767, 286.0767),
        ("R-600a", .celsius, 27.9, 381.3129, 381.3129),
        ("R-744", .fahrenheit, -37.3, 1061.1230, 1061.1230),
        ("R-744", .fahrenheit, 0.0, 2107.9918, 2107.9918),
        ("R-744", .fahrenheit, 12.6, 2590.4905, 2590.4905),
        ("R-744", .fahrenheit, 25.25, 3151.6357, 3151.6357),
        ("R-744", .fahrenheit, 40.0, 3913.3263, 3913.3263),
        ("R-744", .fahrenheit, 47.7, 4361.2388, 4361.2388),
        ("R-744", .fahrenheit, 66.4, 5610.5255, 5610.5255),
        ("R-744", .fahrenheit, 85.5, 7168.0634, 7168.0634),
        ("R-744", .celsius, -21.3, 1891.8365, 1891.8365),
        ("R-744", .celsius, 4.75, 3944.1291, 3944.1291),
        ("R-744", .celsius, 18.2, 5491.0593, 5491.0593),
        ("R-744", .celsius, 27.9, 6876.1009, 6876.1009),
        ("R-1234yf", .fahrenheit, -37.3, 66.8787, 66.8787),
        ("R-1234yf", .fahrenheit, 0.0, 164.8360, 164.8360),
        ("R-1234yf", .fahrenheit, 12.6, 215.4937, 215.4937),
        ("R-1234yf", .fahrenheit, 25.25, 277.6019, 277.6019),
        ("R-1234yf", .fahrenheit, 40.0, 366.2994, 366.2994),
        ("R-1234yf", .fahrenheit, 47.7, 420.3689, 420.3689),
        ("R-1234yf", .fahrenheit, 66.4, 576.6850, 576.6850),
        ("R-1234yf", .fahrenheit, 85.5, 777.7368, 777.7368),
        ("R-1234yf", .celsius, -21.3, 143.1178, 143.1178),
        ("R-1234yf", .celsius, 4.75, 369.9767, 369.9767),
        ("R-1234yf", .celsius, 18.2, 561.4591, 561.4591),
        ("R-1234yf", .celsius, 27.9, 739.9621, 739.9621),
    ]

    /// Linear interpolation over 1 °F / 0.5 °C steps, plus storage to 0.01 kPa.
    private func pressureTolerance(_ kPa: Double) -> Double { max(0.02, kPa * 2e-4) }

    func testEveryRefrigerantHasADozenReferencePoints() {
        for designation in SaturationTableCatalog.designations {
            XCTAssertEqual(Self.reference.filter { $0.designation == designation }.count, 12, designation)
        }
    }

    func testEveryTableWasGeneratedWithTheReferenceVersion() throws {
        for designation in SaturationTableCatalog.designations {
            let table = try XCTUnwrap(SaturationTableCatalog.table(for: designation), designation)
            XCTAssertEqual(table.libraryVersion, Self.referenceVersion, designation)
        }
    }

    func testSaturationPressuresMatchCoolProp() throws {
        for row in Self.reference {
            let table = try XCTUnwrap(SaturationTableCatalog.table(for: row.designation), row.designation)
            for (curve, expected) in [(SaturationCurve.dew, row.dewKPa), (.bubble, row.bubbleKPa)] {
                let value = try table.absolutePressureKPa(atTemperature: row.temperature, scale: row.scale,
                                                          curve: curve).get()
                XCTAssertEqual(value, expected, accuracy: pressureTolerance(expected),
                               "\(row.designation) \(curve) at \(row.temperature) \(row.scale)")
            }
        }
    }

    func testSaturationTemperaturesMatchCoolProp() throws {
        for row in Self.reference {
            let table = try XCTUnwrap(SaturationTableCatalog.table(for: row.designation), row.designation)
            for (curve, pressure) in [(SaturationCurve.dew, row.dewKPa), (.bubble, row.bubbleKPa)] {
                let value = try table.temperature(atAbsoluteKPa: pressure, scale: row.scale, curve: curve).get()
                // 0.03 °F or 0.02 °C: the interpolation error, far below any gauge's resolution.
                let tolerance = row.scale == .fahrenheit ? 0.03 : 0.02
                XCTAssertEqual(value, row.temperature, accuracy: tolerance,
                               "\(row.designation) \(curve) at \(pressure) kPa \(row.scale)")
            }
        }
    }
}
