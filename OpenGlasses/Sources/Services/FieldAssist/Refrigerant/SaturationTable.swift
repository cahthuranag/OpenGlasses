import Foundation

/// Which side of a refrigerant's two-phase region a saturation value belongs to (Plan IS P0).
///
/// For a single-component refrigerant the two are the same. For a blend with glide they differ:
/// superheat is measured from the dew point (the last drop of liquid boils), subcooling from the
/// bubble point (the first bubble forms).
enum SaturationCurve: String, Equatable, CaseIterable {
    case dew
    case bubble
}

/// The temperature grid, and the unit, a lookup is made in. Each table carries two grids computed
/// directly by CoolProp (neither converted from the other), so a °F question is answered from the
/// °F grid and a °C question from the °C grid.
enum TemperatureScale: String, Equatable, CaseIterable {
    case fahrenheit
    case celsius

    /// The unit's symbol for a temperature ("°F") — and, for a difference, what it is shown as:
    /// a temperature difference in metric is a kelvin ("K"), in imperial a degree Fahrenheit.
    var symbol: String { self == .fahrenheit ? "°F" : "°C" }
    var differenceSymbol: String { self == .fahrenheit ? "°F" : "K" }

    func toKelvin(_ value: Double) -> Double {
        self == .fahrenheit ? (value + 459.67) / 1.8 : value + 273.15
    }

    func fromKelvin(_ kelvin: Double) -> Double {
        self == .fahrenheit ? kelvin * 1.8 - 459.67 : kelvin - 273.15
    }

    /// Convert a temperature in `other` into this scale.
    func convert(_ value: Double, from other: TemperatureScale) -> Double {
        other == self ? value : fromKelvin(other.toKelvin(value))
    }
}

/// Why a saturation lookup gave no number. A lookup outside the generated table is refused, never
/// extrapolated: a fabricated saturation temperature is worse than none.
enum SaturationLookupError: Error, Equatable {
    /// The pressure is below the table's coldest point (kPa absolute).
    case pressureBelowTable(designation: String, minimumKPa: Double)
    /// The pressure is above the table's warmest point (kPa absolute). `aboveCritical` is true when
    /// the table stops at the refrigerant's critical point (R-744) rather than at the grid's end.
    case pressureAboveTable(designation: String, maximumKPa: Double, aboveCritical: Bool)
    /// The temperature is outside the grid.
    case temperatureOutOfTable(designation: String, minimum: Double, maximum: Double, scale: TemperatureScale)
}

/// A refrigerant's saturation (pressure–temperature) table, generated offline from CoolProp by
/// `Scripts/generate-pt-tables.py` and bundled as `<designation>.json` (Plan IS P0).
///
/// Pure: it holds the decoded file and answers by linear interpolation between grid points (1 °F or
/// 0.5 °C apart, so the interpolation error is a few hundredths of a degree). Pressures are absolute,
/// in kPa; gauge readings are converted by `RefrigerantPressure` against a stated atmosphere, so no
/// sea-level assumption is baked into the data.
struct SaturationTable: Decodable, Equatable {

    struct Grid: Decodable, Equatable {
        /// First and last grid temperatures, and the spacing, in the grid's own unit.
        let start: Double
        let end: Double
        let step: Double
        /// Saturation pressures, kPa absolute, one per grid temperature, strictly increasing.
        let dew: [Double]
        let bubble: [Double]

        func series(_ curve: SaturationCurve) -> [Double] {
            curve == .dew ? dew : bubble
        }

        func temperature(at index: Int) -> Double { start + Double(index) * step }
    }

    let designation: String
    /// "pure", "pseudo-pure" (Lemmon's blend model) or "mixture" (CoolProp's predefined blend).
    let model: String
    let equationOfState: String
    let criticalTemperatureK: Double
    let criticalPressureKPa: Double
    let fahrenheit: Grid
    let celsius: Grid
    /// The full citation, as generated.
    let source: String
    let licence: String
    let generatedWith: String
    let libraryVersion: String

    /// The short source line every spoken number carries: "CoolProp 8.0.0".
    var sourceName: String { "CoolProp \(libraryVersion)" }

    /// True for a single-component refrigerant, whose dew and bubble points coincide.
    var isSingleComponent: Bool { model == "pure" }

    /// True when the table ends at the critical point rather than at the grid's end (R-744).
    var endsAtCriticalPoint: Bool { fahrenheit.end < SaturationTableCatalog.gridEndFahrenheit }

    func grid(_ scale: TemperatureScale) -> Grid {
        scale == .fahrenheit ? fahrenheit : celsius
    }

    // MARK: - Lookups

    /// Saturation pressure, kPa absolute, at a temperature.
    func absolutePressureKPa(atTemperature temperature: Double, scale: TemperatureScale,
                             curve: SaturationCurve) -> Result<Double, SaturationLookupError> {
        let grid = grid(scale)
        let values = grid.series(curve)
        guard !values.isEmpty, temperature >= grid.start, temperature <= grid.end else {
            return .failure(.temperatureOutOfTable(designation: designation, minimum: grid.start,
                                                   maximum: grid.end, scale: scale))
        }
        let position = (temperature - grid.start) / grid.step
        let lower = min(Int(position.rounded(.down)), values.count - 1)
        guard lower < values.count - 1 else { return .success(values[lower]) }
        let fraction = position - Double(lower)
        return .success(values[lower] + fraction * (values[lower + 1] - values[lower]))
    }

    /// Saturation temperature at an absolute pressure (kPa), in the scale's unit.
    func temperature(atAbsoluteKPa pressure: Double, scale: TemperatureScale,
                     curve: SaturationCurve) -> Result<Double, SaturationLookupError> {
        let grid = grid(scale)
        let values = grid.series(curve)
        guard let first = values.first, let last = values.last else {
            return .failure(.pressureBelowTable(designation: designation, minimumKPa: 0))
        }
        if pressure < first {
            return .failure(.pressureBelowTable(designation: designation, minimumKPa: first))
        }
        if pressure > last {
            return .failure(.pressureAboveTable(designation: designation, maximumKPa: last,
                                                aboveCritical: endsAtCriticalPoint))
        }
        // Binary search for the bracketing pair; the series is strictly increasing.
        var low = 0
        var high = values.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if values[middle] <= pressure { low = middle } else { high = middle }
        }
        let span = values[high] - values[low]
        let fraction = span > 0 ? (pressure - values[low]) / span : 0
        return .success(grid.start + (Double(low) + fraction) * grid.step)
    }

    /// Temperature glide at an absolute pressure: dew temperature minus bubble temperature, as a
    /// difference in the scale's degrees. Zero (to rounding) for a single-component refrigerant.
    func glide(atAbsoluteKPa pressure: Double, scale: TemperatureScale) -> Result<Double, SaturationLookupError> {
        switch (temperature(atAbsoluteKPa: pressure, scale: scale, curve: .dew),
                temperature(atAbsoluteKPa: pressure, scale: scale, curve: .bubble)) {
        case (.success(let dew), .success(let bubble)): return .success(dew - bubble)
        case (.failure(let error), _), (_, .failure(let error)): return .failure(error)
        }
    }
}

/// The bundled saturation tables and how a spoken or typed designation finds one (Plan IS P0).
///
/// The refrigerant is never assumed (decision 3): a designation that is not in the catalog finds
/// nothing, and the caller says so.
enum SaturationTableCatalog {

    /// Every bundled table, by designation. Each is `<designation>.json` in the app bundle,
    /// generated by `Scripts/generate-pt-tables.py`.
    static let designations: [String] = [
        "R-22", "R-32", "R-134a", "R-404A", "R-407A", "R-407C", "R-410A", "R-454B", "R-507A",
        "R-290", "R-600a", "R-744", "R-1234yf"
    ]

    /// The grid's warmest °F point; a table that stops below it stopped at its critical point.
    static let gridEndFahrenheit = 150.0

    /// Common names for the natural refrigerants, which technicians often say instead of the number.
    private static let aliases: [String: String] = [
        "PROPANE": "R-290", "ISOBUTANE": "R-600a", "CO2": "R-744", "CARBONDIOXIDE": "R-744"
    ]

    /// The catalog designation for "410a", "R410A", "r-410a", "R-1234YF", "propane" or "CO2", or nil
    /// when the catalog has no table for it.
    static func designation(for raw: String) -> String? {
        let key = matchKey(raw)
        guard !key.isEmpty else { return nil }
        if let alias = aliases[key] { return alias }
        return designations.first { matchKey($0) == key }
    }

    /// Load a table from the bundle. Nil when the designation is unknown or the file is missing or
    /// malformed — a missing table is a refusal, never a fallback to another refrigerant's data.
    static func table(for designation: String, bundle: Bundle = .main) -> SaturationTable? {
        guard let canonical = self.designation(for: designation),
              let url = bundle.url(forResource: canonical, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }

    static func decode(_ data: Data) throws -> SaturationTable {
        try JSONDecoder().decode(SaturationTable.self, from: data)
    }

    /// Uppercased, with the leading "R", hyphens, spaces and "HFC-"-style prefixes removed.
    private static func matchKey(_ raw: String) -> String {
        var key = raw.uppercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
        for prefix in ["HFC", "HCFC", "HFO", "HC"] where key.hasPrefix(prefix) && key.count > prefix.count
            && key[key.index(key.startIndex, offsetBy: prefix.count)].isNumber {
            key.removeFirst(prefix.count)
            break
        }
        if key.hasPrefix("R"), key.count > 1, key[key.index(after: key.startIndex)].isNumber {
            key.removeFirst()
        }
        return key
    }
}
