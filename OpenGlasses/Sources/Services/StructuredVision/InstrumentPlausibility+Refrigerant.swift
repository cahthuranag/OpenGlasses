import Foundation

/// Per-refrigerant pressure bands (Plan IS P1).
///
/// The quantity bands above only ask whether an instrument can show a number at all. A gauge on a
/// refrigeration circuit can be asked more: a 30 psig "suction" on an R-410A system in cooling is a
/// −16 °F evaporator, which no comfort system runs at. That is a misread gauge, a swapped hose or a
/// system in real trouble, and in every case the right answer is a re-look, not a confident
/// superheat built on it.
///
/// **Method.** No pressure is typed in. Each band is a *saturation-temperature window* for a line
/// (suction, liquid or discharge) in an application (cooling, heating, refrigeration, or not said),
/// converted into pressure through the refrigerant's own bundled table (`SaturationTable`, P0) on
/// the curve that line is read on: suction and discharge on the dew curve, the liquid line on the
/// bubble curve. The windows are deliberately wide — they mark what a working system of that kind
/// does not do, not a diagnostic range — and a window that runs past the table is clamped to it.
/// Where the window's warm end lies beyond the table (R-744 near its critical point, or a hot
/// condenser), the band has no upper bound: the lookup's own refusal speaks there instead.
///
/// Bands are held in SI: the window in kelvin, the pressures in kPa absolute.
extension InstrumentPlausibility {

    /// What the system is doing, as the technician said it. It narrows the suction window; an
    /// unspecified application gets the widest one.
    enum RefrigerantApplication: String, Equatable, CaseIterable {
        /// Comfort cooling: an air conditioner, or a heat pump in cooling.
        case cooling
        /// A heat pump in heating.
        case heating
        /// A cooler, freezer or other refrigeration system.
        case refrigeration
        case unspecified

        /// " in cooling", " in heating", " on refrigeration", or nothing.
        var phrase: String {
            switch self {
            case .cooling: return " in cooling"
            case .heating: return " in heating"
            case .refrigeration: return " on refrigeration"
            case .unspecified: return ""
            }
        }
    }

    /// The saturation-temperature window, °C, a working system shows on `role` in `application`.
    ///
    /// - Suction: a comfort-cooling evaporator saturates a little above or below freezing
    ///   (−10…20 °C covers a dirty filter to a lightly loaded coil); a heat pump's outdoor coil in
    ///   heating follows the weather down (−35…20 °C); refrigeration runs colder still (to the
    ///   table's −40 °C, up to 10 °C for a medium-temperature case). Unspecified: −40…30 °C.
    /// - Liquid and discharge: a working condenser saturates above the air it rejects to — 15 °C
    ///   and up in cooling and heating, 10 °C and up in refrigeration, and −10 °C and up when
    ///   nothing is said (a system just started on a cold day). The warm end is the table's.
    static func saturationWindowCelsius(role: GaugeRole,
                                        application: RefrigerantApplication) -> ClosedRange<Double> {
        switch (role, application) {
        case (.suction, .cooling): return -10...20
        case (.suction, .heating): return -35...20
        case (.suction, .refrigeration): return -40...10
        case (.suction, .unspecified): return -40...30
        case (_, .cooling), (_, .heating): return 15...65
        case (_, .refrigeration): return 10...65
        case (_, .unspecified): return -10...65
        }
    }

    /// One band: a saturation window and the absolute pressures it converts to.
    struct RefrigerantPressureBand: Equatable {
        let designation: String
        let role: GaugeRole
        let application: RefrigerantApplication
        /// The window, kelvin, as clamped to the table.
        let windowKelvin: ClosedRange<Double>
        /// The lowest plausible pressure, kPa absolute.
        let lowKPa: Double
        /// The highest plausible pressure, kPa absolute; nil when the window runs past the table.
        let highKPa: Double?

        func contains(absoluteKPa pressure: Double) -> Bool {
            guard pressure >= lowKPa else { return false }
            if let highKPa { return pressure <= highKPa }
            return true
        }
    }

    /// The band for a role on this refrigerant, converted through its table. Nil only when the
    /// table cannot give a pressure at the window's edge (a malformed table).
    static func refrigerantBand(table: SaturationTable, role: GaugeRole,
                                application: RefrigerantApplication) -> RefrigerantPressureBand? {
        let window = saturationWindowCelsius(role: role, application: application)
        let grid = table.grid(.celsius)
        let low = max(window.lowerBound, grid.start)
        let high = min(window.upperBound, grid.end)
        guard low <= high,
              case .success(let lowKPa) = table.absolutePressureKPa(atTemperature: low, scale: .celsius,
                                                                    curve: role.curve) else { return nil }
        var highKPa: Double?
        if window.upperBound <= grid.end {
            guard case .success(let value) = table.absolutePressureKPa(atTemperature: high, scale: .celsius,
                                                                       curve: role.curve) else { return nil }
            highKPa = value
        }
        return RefrigerantPressureBand(designation: table.designation, role: role, application: application,
                                       windowKelvin: (low + 273.15)...(high + 273.15),
                                       lowKPa: lowKPa, highKPa: highKPa)
    }
}
