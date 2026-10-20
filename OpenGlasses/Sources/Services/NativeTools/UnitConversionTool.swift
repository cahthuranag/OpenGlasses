import Foundation

/// Converts between units using Foundation's Measurement APIs.
struct UnitConversionTool: NativeTool {
    let name = "convert_units"
    let description = "Convert a value from one unit to another. Supports length, weight, temperature, volume, speed, area, time, and data storage."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "value": [
                "type": "number",
                "description": "The numeric value to convert"
            ],
            "from_unit": [
                "type": "string",
                "description": "Source unit, e.g. 'miles', 'kg', 'fahrenheit', 'liters', 'mph'"
            ],
            "to_unit": [
                "type": "string",
                "description": "Target unit, e.g. 'kilometers', 'pounds', 'celsius', 'gallons', 'kph'"
            ]
        ],
        "required": ["value", "from_unit", "to_unit"]
    ]

    func execute(args: [String: Any]) async throws -> String {
        guard let value = args["value"] as? Double else {
            return "Missing or invalid value."
        }
        guard let fromStr = args["from_unit"] as? String else {
            return "Missing source unit."
        }
        guard let toStr = args["to_unit"] as? String else {
            return "Missing target unit."
        }

        let from = fromStr.lowercased().trimmingCharacters(in: .whitespaces)
        let to = toStr.lowercased().trimmingCharacters(in: .whitespaces)

        guard let fromUnit = Self.resolveUnit(from),
              let toUnit = Self.resolveUnit(to) else {
            return "I don't recognize one of those units. Supported: miles, km, meters, feet, inches, yards, pounds, kg, grams, ounces, fahrenheit, celsius, kelvin, liters, gallons, cups, tablespoons, teaspoons, ml, mph, kph, m/s, acres, hectares, sqft, sqm, hours, minutes, seconds, days, bytes, KB, MB, GB, TB."
        }

        // Verify same dimension
        guard type(of: fromUnit).self == type(of: toUnit).self else {
            return "Can't convert between \(fromStr) and \(toStr) — they're different types of measurement."
        }

        let measurement = Measurement(value: value, unit: fromUnit)
        let converted = measurement.converted(to: toUnit)

        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 4
        formatter.numberFormatter.minimumFractionDigits = 0

        let fromFormatted = formatter.string(from: measurement)
        let toFormatted = formatter.string(from: converted)

        return "\(fromFormatted) is \(toFormatted)."
    }

    /// `value` in `from` converted to `to`, or nil when either unit is unknown or the two measure
    /// different things. What a rule chain's `convert` step runs through (Plan JJ P2).
    nonisolated static func convert(_ value: Double, from: String, to: String) -> Double? {
        guard let fromUnit = resolveUnit(from.lowercased().trimmingCharacters(in: .whitespaces)),
              let toUnit = resolveUnit(to.lowercased().trimmingCharacters(in: .whitespaces)),
              type(of: fromUnit) == type(of: toUnit) else { return nil }
        return Measurement(value: value, unit: fromUnit).converted(to: toUnit).value
    }

    /// Whether the converter knows the unit at all.
    nonisolated static func knowsUnit(_ name: String) -> Bool {
        resolveUnit(name.lowercased().trimmingCharacters(in: .whitespaces)) != nil
    }

    // MARK: - Unit Resolution

    nonisolated private static func resolveUnit(_ name: String) -> Dimension? {
        switch name {
        // Length
        case "miles", "mile", "mi": return UnitLength.miles
        case "kilometers", "kilometer", "km", "kms": return UnitLength.kilometers
        case "meters", "meter", "m": return UnitLength.meters
        case "centimeters", "centimeter", "cm": return UnitLength.centimeters
        case "millimeters", "millimeter", "mm": return UnitLength.millimeters
        case "feet", "foot", "ft": return UnitLength.feet
        case "inches", "inch", "in": return UnitLength.inches
        case "yards", "yard", "yd": return UnitLength.yards

        // Weight
        case "pounds", "pound", "lbs", "lb": return UnitMass.pounds
        case "kilograms", "kilogram", "kg", "kgs": return UnitMass.kilograms
        case "grams", "gram", "g": return UnitMass.grams
        case "ounces", "ounce", "oz": return UnitMass.ounces
        case "stones", "stone", "st": return UnitMass.stones
        case "milligrams", "milligram", "mg": return UnitMass.milligrams

        // Temperature
        case "fahrenheit", "f", "°f": return UnitTemperature.fahrenheit
        case "celsius", "c", "°c", "centigrade": return UnitTemperature.celsius
        case "kelvin", "k": return UnitTemperature.kelvin

        // Volume
        case "liters", "liter", "l", "litres", "litre": return UnitVolume.liters
        case "milliliters", "milliliter", "ml": return UnitVolume.milliliters
        case "gallons", "gallon", "gal": return UnitVolume.gallons
        case "cups", "cup": return UnitVolume.cups
        case "tablespoons", "tablespoon", "tbsp": return UnitVolume.tablespoons
        case "teaspoons", "teaspoon", "tsp": return UnitVolume.teaspoons
        case "pints", "pint", "pt": return UnitVolume.pints
        case "quarts", "quart", "qt": return UnitVolume.quarts
        case "fluid ounces", "fluid ounce", "fl oz", "floz": return UnitVolume.fluidOunces

        // Speed
        case "mph", "miles per hour": return UnitSpeed.milesPerHour
        case "kph", "km/h", "kmh", "kilometers per hour": return UnitSpeed.kilometersPerHour
        case "m/s", "meters per second": return UnitSpeed.metersPerSecond
        case "knots", "knot", "kn": return UnitSpeed.knots

        // Area
        case "acres", "acre": return UnitArea.acres
        case "hectares", "hectare", "ha": return UnitArea.hectares
        case "sqft", "square feet", "sq ft": return UnitArea.squareFeet
        case "sqm", "square meters", "sq m": return UnitArea.squareMeters
        case "sqkm", "square kilometers", "sq km": return UnitArea.squareKilometers
        case "sqmi", "square miles", "sq mi": return UnitArea.squareMiles

        // Time
        case "hours", "hour", "hr", "hrs": return UnitDuration.hours
        case "minutes", "minute", "min", "mins": return UnitDuration.minutes
        case "seconds", "second", "sec", "secs": return UnitDuration.seconds

        // Data storage
        case "bytes", "byte", "b": return UnitInformationStorage.bytes
        case "kb", "kilobytes", "kilobyte": return UnitInformationStorage.kilobytes
        case "mb", "megabytes", "megabyte": return UnitInformationStorage.megabytes
        case "gb", "gigabytes", "gigabyte": return UnitInformationStorage.gigabytes
        case "tb", "terabytes", "terabyte": return UnitInformationStorage.terabytes

        default: return nil
        }
    }
}
