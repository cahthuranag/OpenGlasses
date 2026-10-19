import Foundation

/// The units a technician reads refrigeration numbers in (Plan IS P1, amendment 2026-10-19:
/// "Defaults by jurisdiction, always a setting").
///
/// Pure. Pressure is kPa, bar or psi (always shown as a gauge reading), temperature °C or °F, and
/// mass kg or lb. The calculation itself runs in SI (kPa absolute, kelvin); this only decides how an
/// answer is rendered, and a reading in any unit is still understood.
///
/// Stored as one string, `<pressure>,<temperature>,<mass>` (`"kPa,C,kg"`), at the `UserDefaults` key
/// `refrigerationUnits`, so an organisation profile can offer a starting value through the same key
/// (`SettingKey.refrigerationUnits`). An empty or unreadable value means "the region's default".
struct RefrigerationUnits: Equatable {

    enum Pressure: String, CaseIterable, Identifiable {
        case kPa
        case bar
        case psi

        var id: String { rawValue }

        var unit: RefrigerantPressure.Unit {
            switch self {
            case .kPa: return .kPa
            case .bar: return .bar
            case .psi: return .psi
            }
        }

        /// How a gauge reading in this unit is spoken and printed: "psig", "kPa", "bar". A manifold
        /// reads relative to atmosphere, so "820 kPa" on a gauge is a gauge pressure; only psi has a
        /// spoken gauge suffix of its own.
        var gaugeLabel: String {
            switch self {
            case .kPa: return "kPa"
            case .bar: return "bar"
            case .psi: return "psig"
            }
        }
    }

    enum Temperature: String, CaseIterable, Identifiable {
        case celsius = "C"
        case fahrenheit = "F"

        var id: String { rawValue }

        var scale: TemperatureScale { self == .celsius ? .celsius : .fahrenheit }

        /// "°C" / "°F".
        var label: String { scale.symbol }
    }

    enum Mass: String, CaseIterable, Identifiable {
        case kg
        case lb

        var id: String { rawValue }

        var label: String { rawValue }
    }

    var pressure: Pressure
    var temperature: Temperature
    var mass: Mass

    /// kPa, °C and kg.
    static let metric = RefrigerationUnits(pressure: .kPa, temperature: .celsius, mass: .kg)
    /// psig, °F and lb.
    static let imperial = RefrigerationUnits(pressure: .psi, temperature: .fahrenheit, mass: .lb)
    /// psig and °F at the gauges, kilograms for refrigerant quantities: Canadian rules state
    /// quantities in kilograms while US-built gauge sets dominate (open question 7 asks whether
    /// crews work this way; it is a default, and always a setting).
    static let canadian = RefrigerationUnits(pressure: .psi, temperature: .fahrenheit, mass: .kg)

    /// The default for an App Store storefront (ISO 3166-1 alpha-2, as `StorefrontReader` gives it;
    /// alpha-3 is accepted too). Australia and New Zealand are metric, Canada is `canadian`, and
    /// everywhere else — the US included, and an unknown storefront — is imperial.
    static func regionDefault(forStorefront code: String?) -> RefrigerationUnits {
        switch code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "AU", "AUS", "NZ", "NZL": return .metric
        case "CA", "CAN": return .canadian
        default: return .imperial
        }
    }

    /// The stored choice when there is a readable one, otherwise the region's default.
    static func effective(stored: String?, storefront: String?) -> RefrigerationUnits {
        stored.flatMap(RefrigerationUnits.init(encoded:)) ?? regionDefault(forStorefront: storefront)
    }

    init(pressure: Pressure, temperature: Temperature, mass: Mass) {
        self.pressure = pressure
        self.temperature = temperature
        self.mass = mass
    }

    /// Parse `"kPa,C,kg"`. Case-insensitive, spaces ignored, "°C"/"°F" and "psig" accepted. Nil
    /// for anything that is not exactly one pressure, one temperature and one mass unit.
    init?(encoded: String) {
        let parts = encoded.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "°", with: "").lowercased()
        }
        guard parts.count == 3 else { return nil }
        let pressure: Pressure
        switch parts[0] {
        case "kpa": pressure = .kPa
        case "bar": pressure = .bar
        case "psi", "psig": pressure = .psi
        default: return nil
        }
        let temperature: Temperature
        switch parts[1] {
        case "c": temperature = .celsius
        case "f": temperature = .fahrenheit
        default: return nil
        }
        let mass: Mass
        switch parts[2] {
        case "kg": mass = .kg
        case "lb", "lbs": mass = .lb
        default: return nil
        }
        self.init(pressure: pressure, temperature: temperature, mass: mass)
    }

    /// `"kPa,C,kg"` — what is stored.
    var encoded: String { "\(pressure.rawValue),\(temperature.rawValue),\(mass.rawValue)" }

    /// "kPa, °C and kg" — for the Settings footer and an organisation's starting-value line.
    var spokenList: String { "\(pressure.gaugeLabel), \(temperature.label) and \(mass.label)" }
}

/// Where the technician's refrigeration units are read from: the stored setting, or the storefront's
/// default when nothing readable is stored.
@MainActor
enum RefrigerationUnitsSetting {

    /// The `UserDefaults` key, which is also the organisation-profile key.
    nonisolated static let key = "refrigerationUnits"

    /// The units in force on this phone now.
    static var current: RefrigerationUnits {
        MarketAvailability.shared.startReading()
        return RefrigerationUnits.effective(stored: UserDefaults.standard.string(forKey: key),
                                            storefront: MarketAvailability.shared.storefront)
    }

    /// The default this phone's storefront gives, whatever is stored.
    static var regionDefault: RefrigerationUnits {
        MarketAvailability.shared.startReading()
        return RefrigerationUnits.regionDefault(forStorefront: MarketAvailability.shared.storefront)
    }
}
