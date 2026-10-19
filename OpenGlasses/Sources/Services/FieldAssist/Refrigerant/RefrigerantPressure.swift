import Foundation

/// The atmosphere a gauge reads against (Plan IS P0, amendment 2026-10-19).
///
/// A gauge shows pressure above local atmospheric pressure. The saturation tables are absolute, so a
/// gauge reading becomes absolute by adding the atmosphere. Without an altitude that is the standard
/// sea-level 101.325 kPa, and the answer says so; with one it is the ISA barometric formula
/// `P = 101.325 × (1 − 2.25577×10⁻⁵ × h)^5.25588` kPa, h in metres.
struct Atmosphere: Equatable {

    static let seaLevelKPa = 101.325
    /// The altitudes the formula is accepted for: the lowest dry land to well above any job site.
    static let altitudeRangeMetres: ClosedRange<Double> = -500...6_000
    static let metresPerFoot = 0.3048

    static let seaLevel = Atmosphere(pressureKPa: seaLevelKPa, altitudeMetres: nil)

    /// Local atmospheric pressure, kPa absolute.
    let pressureKPa: Double
    /// The altitude it was computed for; nil when sea level was assumed.
    let altitudeMetres: Double?

    /// True when no altitude was given and the sea-level atmosphere was assumed.
    var assumesSeaLevel: Bool { altitudeMetres == nil }

    /// The ISA atmosphere at an altitude in metres; nil outside `altitudeRangeMetres`.
    static func at(altitudeMetres metres: Double) -> Atmosphere? {
        guard metres.isFinite, altitudeRangeMetres.contains(metres) else { return nil }
        let pressure = seaLevelKPa * pow(1 - 2.25577e-5 * metres, 5.25588)
        return Atmosphere(pressureKPa: pressure, altitudeMetres: metres)
    }

    /// The ISA atmosphere at an altitude in feet; nil outside the accepted range.
    static func at(altitudeFeet feet: Double) -> Atmosphere? {
        at(altitudeMetres: feet * metresPerFoot)
    }
}

/// Pressure units a refrigeration reading arrives in, and the conversions between gauge and
/// absolute (Plan IS P0). Pure.
enum RefrigerantPressure {

    enum Unit: String, Equatable, CaseIterable {
        case psi
        case kPa
        case bar

        /// kPa per one of this unit (exact for psi to the definition of the pound-force).
        var kPa: Double {
            switch self {
            case .psi: return 6.894757293168361
            case .kPa: return 1
            case .bar: return 100
            }
        }

        /// How a gauge reading in this unit is written: "psig", "kPa(g)", "bar(g)".
        var gaugeSymbol: String {
            switch self {
            case .psi: return "psig"
            case .kPa: return "kPa(g)"
            case .bar: return "bar(g)"
            }
        }

        /// How an absolute reading in this unit is written: "psia", "kPa abs", "bar abs".
        var absoluteSymbol: String {
            switch self {
            case .psi: return "psia"
            case .kPa: return "kPa abs"
            case .bar: return "bar abs"
            }
        }
    }

    /// Absolute pressure in kPa from a gauge reading.
    static func absoluteKPa(gauge value: Double, unit: Unit, atmosphere: Atmosphere = .seaLevel) -> Double {
        value * unit.kPa + atmosphere.pressureKPa
    }

    /// Absolute pressure in kPa from an absolute reading.
    static func absoluteKPa(absolute value: Double, unit: Unit) -> Double {
        value * unit.kPa
    }

    /// A gauge reading, in `unit`, for an absolute pressure in kPa.
    static func gauge(absoluteKPa pressure: Double, unit: Unit, atmosphere: Atmosphere = .seaLevel) -> Double {
        (pressure - atmosphere.pressureKPa) / unit.kPa
    }
}
