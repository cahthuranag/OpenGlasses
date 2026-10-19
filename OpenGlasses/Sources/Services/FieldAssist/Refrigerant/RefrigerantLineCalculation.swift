import Foundation

/// Superheat and subcooling from one pressure and one line temperature (Plan IS P0, shared by P1).
///
/// Pure. `domain_calc` and the gauge chain (`RefrigerantGaugeChain`) both run through here, so a
/// number spoken from a photograph and one asked for by voice come from the same lookup:
/// superheat from the dew point, subcooling from the bubble point, never extrapolated.
enum RefrigerantLineCalculation {

    enum Kind: Equatable, CaseIterable {
        case superheat
        case subcool

        /// Superheat is measured from the dew point, subcooling from the bubble point.
        var curve: SaturationCurve { self == .superheat ? .dew : .bubble }
    }

    struct Output: Equatable {
        /// The saturation temperature at the pressure, in the answer's scale.
        let saturation: Double
        /// The line temperature, converted into the answer's scale.
        let line: Double
        /// Superheat (line − dew) or subcooling (bubble − line), in the answer scale's degrees.
        let difference: Double
        /// Dew minus bubble at this pressure for a blend; nil for a single-component refrigerant or
        /// when either curve has no value here.
        let glide: Double?
    }

    /// - Parameters:
    ///   - absoluteKPa: the pressure, kPa absolute (a gauge reading plus the atmosphere).
    ///   - lineTemperature: the measured line temperature, in `lineScale`.
    ///   - scale: the scale the answer is given in.
    static func compute(_ kind: Kind, table: SaturationTable, absoluteKPa: Double,
                        lineTemperature: Double, lineScale: TemperatureScale,
                        scale: TemperatureScale) -> Result<Output, SaturationLookupError> {
        switch table.temperature(atAbsoluteKPa: absoluteKPa, scale: scale, curve: kind.curve) {
        case .failure(let error):
            return .failure(error)
        case .success(let saturation):
            let line = scale.convert(lineTemperature, from: lineScale)
            let difference = kind == .superheat ? line - saturation : saturation - line
            var glide: Double?
            if !table.isSingleComponent, case .success(let value) = table.glide(atAbsoluteKPa: absoluteKPa, scale: scale) {
                glide = value
            }
            return .success(Output(saturation: saturation, line: line, difference: difference, glide: glide))
        }
    }
}
