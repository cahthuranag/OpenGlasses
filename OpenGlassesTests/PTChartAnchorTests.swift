import XCTest
@testable import OpenGlasses

/// The anchor points the vault's `pt_charts.md` and `DomainCalcTool` used to carry, checked against
/// the generated tables (Plan IS P0 exit test), and the reduced `pt_charts.md` itself (decision 2).
///
/// Each old anchor (psig at sea level → °F) is converted to absolute at 101.325 kPa and looked up on
/// the °F grid. An anchor within ±1 °F passes as it is. One that is further off is listed with its
/// difference pinned (old minus new, ±0.1 °F) and the reason, so the record of what changed stays in
/// the code rather than in a commit message.
@MainActor
final class PTChartAnchorTests: XCTestCase {

    /// The old single-column tables, exactly as `pt_charts.md` printed them before Plan IS P0.
    static let oldAnchors: [String: [(psig: Double, tempF: Double)]] = [
        "R-410A": [(50, 8), (75, 23), (100, 31), (125, 44), (135, 47), (150, 54),
                   (175, 63), (200, 70), (250, 84), (300, 96), (400, 119), (450, 129)],
        "R-32": [(50, 12), (100, 38), (135, 52), (150, 58), (200, 75), (250, 89),
                 (300, 102), (400, 124)],
        "R-454B": [(50, 9), (100, 35), (135, 49), (150, 55), (200, 73), (250, 87),
                   (300, 100), (400, 124)],
        "R-22": [(50, 25), (75, 44), (100, 59), (125, 72), (150, 83), (200, 102),
                 (250, 117), (300, 130)]
    ]

    /// Which curve the old single column is compared with. R-410A and R-22 have (almost) no glide;
    /// the old R-454B column tracks its bubble point, about 2.7 °F below the dew point.
    static let comparedCurve: [String: SaturationCurve] = [
        "R-410A": .dew, "R-32": .dew, "R-454B": .bubble, "R-22": .dew
    ]

    static let rounded = "The old chart was a hand-entered field approximation, rounded to whole degrees"

    /// Anchors more than 1 °F from CoolProp: (refrigerant, psig) → (old − new in °F, why).
    static let explained: [String: (difference: Double, reason: String)] = [
        "R-410A@50": (6.64, "The old chart put 50 psig at 8 °F; R-410A saturates at about 1.4 °F there. "
                      + "The low end of the old chart was wrong."),
        "R-410A@75": (4.96, "Same low-end error: 75 psig is about 18 °F, not 23 °F."),
        "R-410A@125": (1.14, rounded + ", and read about a degree warm through the middle of its range."),
        "R-410A@150": (1.20, rounded + ", and read about a degree warm through the middle of its range."),
        "R-410A@175": (1.35, rounded + ", and read about a degree warm through the middle of its range."),
        "R-410A@400": (2.35, "The old chart ran warm at the high end: 400 psig is about 116.7 °F."),
        "R-410A@450": (3.46, "The old chart ran warm at the high end: 450 psig is about 125.5 °F."),
        "R-32@50": (11.44, r32),
        "R-32@100": (7.56, r32),
        "R-32@135": (6.20, r32),
        "R-32@150": (6.45, r32),
        "R-32@200": (6.75, r32),
        "R-32@250": (6.77, r32),
        "R-32@300": (7.66, r32),
        "R-32@400": (9.26, r32),
        "R-454B@50": (5.79, "The old R-454B chart's low end was wrong: 50 psig is about 3.2 °F at the "
                      + "bubble point and 5.7 °F at the dew point, not 9 °F."),
        "R-454B@100": (1.30, "A single column for a blend with about 2.7 °F of glide: 35 °F sits between "
                       + "the bubble (33.7 °F) and dew (36.4 °F) points."),
        "R-454B@400": (3.74, "The old chart ran warm at the high end: 400 psig is about 120.3 °F at the "
                       + "bubble point.")
    ]

    static let r32 = "The old R-32 chart was about 6 to 11 °F too warm throughout. It put R-32 above R-410A "
        + "at the same pressure, but R-32 is the higher-pressure refrigerant, so at a given pressure it "
        + "saturates slightly colder (100 psig: R-32 30.4 °F, R-410A 31.5 °F)."

    func testOldAnchorsAgreeOrTheDifferenceIsExplained() throws {
        var checked = 0
        for (designation, anchors) in Self.oldAnchors {
            let table = try XCTUnwrap(SaturationTableCatalog.table(for: designation), designation)
            let curve = try XCTUnwrap(Self.comparedCurve[designation])
            for anchor in anchors {
                let kPa = RefrigerantPressure.absoluteKPa(gauge: anchor.psig, unit: .psi, atmosphere: .seaLevel)
                let new = try table.temperature(atAbsoluteKPa: kPa, scale: .fahrenheit, curve: curve).get()
                let key = "\(designation)@\(Int(anchor.psig))"
                if let explanation = Self.explained[key] {
                    XCTAssertEqual(anchor.tempF - new, explanation.difference, accuracy: 0.1,
                                   "\(key): the explained difference moved — \(explanation.reason)")
                    XCTAssertGreaterThan(abs(anchor.tempF - new), 1, "\(key) is within ±1 °F; drop its explanation")
                } else {
                    XCTAssertEqual(anchor.tempF, new, accuracy: 1, "\(key) differs by more than 1 °F without an explanation")
                }
                checked += 1
            }
        }
        XCTAssertEqual(checked, 36)
    }

    func testEveryExplanationNamesARealAnchor() {
        let keys = Set(Self.oldAnchors.flatMap { designation, anchors in
            anchors.map { "\(designation)@\(Int($0.psig))" }
        })
        XCTAssertTrue(Set(Self.explained.keys).isSubset(of: keys))
    }

    func testR22MatchesTheOldChartThroughout() throws {
        // The one old table that was right everywhere — a check that the conversion itself is sound.
        XCTAssertTrue(Self.explained.keys.allSatisfy { !$0.hasPrefix("R-22@") })
    }

    // MARK: - pt_charts.md is a pointer, not a table (decision 2)

    private static var ptCharts: String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("OpenGlasses/Sources/Resources/Vaults/refrigeration/pt_charts.md")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func testPTChartsPointsAtTheTool() {
        let text = Self.ptCharts
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.contains("domain_calc"))
        XCTAssertTrue(text.contains("dew point"))
        XCTAssertTrue(text.contains("bubble point"))
        XCTAssertTrue(text.contains("sea-level"))
    }

    func testPTChartsCarriesNoSaturationTable() {
        // The old tables had a "Saturation Temp" column; none may come back into the prompt core.
        let text = Self.ptCharts
        XCTAssertFalse(text.contains("Saturation Temp"))
        XCTAssertNil(text.range(of: #"(?m)^\|\s*\d+\s*\|\s*-?\d+\s*\|"#, options: .regularExpression))
        // Small enough to be cheap on every refrigeration turn.
        XCTAssertLessThan(text.count, 1_800)
    }
}
