import Foundation

/// Refrigeration domain math: saturation (P-T) lookup, superheat and subcooling (Plan IS P0).
///
/// The numbers come from the bundled saturation tables (`SaturationTableCatalog`), generated offline
/// from CoolProp at a pinned version — not from the vault's prompt text, which only points here
/// (decision 2). Superheat is measured from the dew point and subcooling from the bubble point, and
/// the answer says which, how much glide the blend has at that pressure, and the data's source.
///
/// Either unit set is accepted: psig with °F, or kPa(g) / bar(g) with °C. The pressure argument picks
/// the answer's units (psig → °F; kPa or bar → °C and kelvin differences). Gauge readings are taken
/// against sea-level atmosphere unless an altitude is given, and the answer says which. A pressure or
/// temperature outside the table is refused by name, never extrapolated, and the refrigerant is never
/// assumed (decision 3).
@MainActor
final class DomainCalcTool: NativeTool {
    let name = "domain_calc"
    let description = """
    Refrigerant saturation math from CoolProp tables: pt_lookup, superheat (dew point), subcool \
    (bubble point). 'pt_lookup' gives the dew and bubble saturation temperatures at a gauge pressure, or \
    the saturation pressures at a temperature. 'superheat' is suction line temperature minus the dew-point \
    temperature at suction pressure; 'subcool' is the bubble-point temperature at liquid pressure minus \
    liquid line temperature. Pressures in psig (answer in °F) or kPa/bar gauge (answer in °C and K). \
    Gauge pressure assumes sea level unless altitude_ft or altitude_m is given. Never assume the \
    refrigerant: take it from the nameplate or ask.
    """
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "operation": [
                "type": "string",
                "description": "'pt_lookup', 'superheat', or 'subcool'."
            ],
            "refrigerant": [
                "type": "string",
                "description": "Refrigerant designation, from the nameplate or the technician: " +
                    SaturationTableCatalog.designations.joined(separator: ", ") + "."
            ],
            "pressure_psig": [
                "type": "number",
                "description": "For 'pt_lookup': the gauge pressure (psig)."
            ],
            "pressure_kpa": [
                "type": "number",
                "description": "For 'pt_lookup': the gauge pressure (kPa)."
            ],
            "pressure_bar": [
                "type": "number",
                "description": "For 'pt_lookup': the gauge pressure (bar)."
            ],
            "temperature_f": [
                "type": "number",
                "description": "For 'pt_lookup' instead of a pressure: a saturation temperature (°F); answers in psig."
            ],
            "temperature_c": [
                "type": "number",
                "description": "For 'pt_lookup' instead of a pressure: a saturation temperature (°C); answers in kPa(g)."
            ],
            "suction_pressure_psig": [
                "type": "number",
                "description": "For 'superheat': suction-side gauge pressure (psig)."
            ],
            "suction_pressure_kpa": [
                "type": "number",
                "description": "For 'superheat': suction-side gauge pressure (kPa)."
            ],
            "suction_pressure_bar": [
                "type": "number",
                "description": "For 'superheat': suction-side gauge pressure (bar)."
            ],
            "suction_line_temp_f": [
                "type": "number",
                "description": "For 'superheat': measured suction line temperature (°F)."
            ],
            "suction_line_temp_c": [
                "type": "number",
                "description": "For 'superheat': measured suction line temperature (°C)."
            ],
            "liquid_pressure_psig": [
                "type": "number",
                "description": "For 'subcool': liquid-side gauge pressure (psig)."
            ],
            "liquid_pressure_kpa": [
                "type": "number",
                "description": "For 'subcool': liquid-side gauge pressure (kPa)."
            ],
            "liquid_pressure_bar": [
                "type": "number",
                "description": "For 'subcool': liquid-side gauge pressure (bar)."
            ],
            "liquid_line_temp_f": [
                "type": "number",
                "description": "For 'subcool': measured liquid line temperature (°F)."
            ],
            "liquid_line_temp_c": [
                "type": "number",
                "description": "For 'subcool': measured liquid line temperature (°C)."
            ],
            "pressure_reference": [
                "type": "string",
                "description": "'gauge' (default) or 'absolute' when the instrument reads absolute (psia, kPa abs, bar abs)."
            ],
            "altitude_ft": [
                "type": "number",
                "description": "Optional site altitude (feet) to correct gauge pressure for local atmosphere."
            ],
            "altitude_m": [
                "type": "number",
                "description": "Optional site altitude (metres) to correct gauge pressure for local atmosphere."
            ]
        ],
        "required": ["operation", "refrigerant"]
    ]

    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func execute(args: [String: Any]) async throws -> String {
        guard let operation = (args["operation"] as? String)?.lowercased() else {
            return "Specify 'operation': 'pt_lookup', 'superheat', or 'subcool'."
        }
        guard let rawRefrigerant = (args["refrigerant"] as? String)?.trimmingCharacters(in: .whitespaces),
              !rawRefrigerant.isEmpty else {
            return "Specify 'refrigerant' (e.g. 'R-410A'), from the nameplate or the technician. It is never assumed."
        }
        guard let table = SaturationTableCatalog.table(for: rawRefrigerant, bundle: bundle) else {
            return "No saturation table for '\(rawRefrigerant)'. Tables: " +
                SaturationTableCatalog.designations.joined(separator: ", ") +
                ". Give the pressures only, and confirm the refrigerant from the nameplate."
        }
        let site: Site
        switch Self.site(args) {
        case .success(let value): site = value
        case .failure(let message): return message.text
        }
        let absolute = (args["pressure_reference"] as? String)?.lowercased() == "absolute"

        switch operation {
        case "pt_lookup":
            return ptLookup(table: table, args: args, site: site, absolute: absolute)

        case "superheat":
            guard let reading = Self.pressure(args, prefix: "suction_pressure"),
                  let line = Self.temperature(args, prefix: "suction_line_temp") else {
                return "Specify a suction pressure ('suction_pressure_psig', '_kpa' or '_bar') and the suction " +
                    "line temperature ('suction_line_temp_f' or '_c') for superheat."
            }
            return lineCalculation(.superheat, table: table, reading: reading, line: line,
                                   site: site, absolute: absolute)

        case "subcool", "subcooling":
            guard let reading = Self.pressure(args, prefix: "liquid_pressure"),
                  let line = Self.temperature(args, prefix: "liquid_line_temp") else {
                return "Specify a liquid pressure ('liquid_pressure_psig', '_kpa' or '_bar') and the liquid " +
                    "line temperature ('liquid_line_temp_f' or '_c') for subcool."
            }
            return lineCalculation(.subcool, table: table, reading: reading, line: line,
                                   site: site, absolute: absolute)

        default:
            return "Unknown operation '\(operation)'. Use 'pt_lookup', 'superheat', or 'subcool'."
        }
    }

    // MARK: - Operations

    private enum LineCalculation {
        case superheat, subcool

        var kind: RefrigerantLineCalculation.Kind { self == .superheat ? .superheat : .subcool }
        var title: String { self == .superheat ? "Superheat" : "Subcooling" }
        var point: String { self == .superheat ? "dew point" : "bubble point" }
        var side: String { self == .superheat ? "suction" : "liquid" }
    }

    private func lineCalculation(_ calculation: LineCalculation, table: SaturationTable,
                                 reading: PressureReading, line: TemperatureReading,
                                 site: Site, absolute: Bool) -> String {
        let atmosphere = site.atmosphere
        let scale = reading.unit.answerScale
        let pressureKPa = reading.absoluteKPa(atmosphere: atmosphere, absolute: absolute)
        // The same lookup the gauge chain uses (Plan IS P1), so a spoken and a photographed
        // reading give the same number.
        let output: RefrigerantLineCalculation.Output
        switch RefrigerantLineCalculation.compute(calculation.kind, table: table, absoluteKPa: pressureKPa,
                                                  lineTemperature: line.value, lineScale: line.scale,
                                                  scale: scale) {
        case .success(let value): output = value
        case .failure(let error):
            return refusal(error, table: table, reading: reading, atmosphere: atmosphere, absolute: absolute)
        }
        let saturation = output.saturation
        let lineTemp = output.line
        let result = output.difference
        let deg = scale.symbol
        let diff = scale.differenceSymbol
        var answer = "\(calculation.title) ≈ \(fmt(result))\(diff) for \(table.designation): " +
            "\(calculation.side) \(reading.text(absolute: absolute)) is \(fmt(saturation))\(deg) at the " +
            "\(calculation.point), \(calculation.side) line \(fmt(lineTemp))\(deg). "
        answer += glideSentence(table: table, pressureKPa: pressureKPa, scale: scale,
                                using: calculation.point)
        if calculation == .superheat, result < 0 {
            answer += "Negative superheat suggests liquid floodback — recheck readings. "
        }
        if calculation == .subcool, result < 0 {
            answer += "Negative subcool suggests undercharge or flash gas — recheck. "
        }
        answer += atmosphereSentence(site, absolute: absolute)
        answer += "Saturation data: \(table.sourceName), \(calculation.point). (Source: superheat_subcool.md)"
        return answer
    }

    private func ptLookup(table: SaturationTable, args: [String: Any], site: Site,
                          absolute: Bool) -> String {
        let atmosphere = site.atmosphere
        if let reading = Self.pressure(args, prefix: "pressure") {
            let scale = reading.unit.answerScale
            let pressureKPa = reading.absoluteKPa(atmosphere: atmosphere, absolute: absolute)
            let dew = table.temperature(atAbsoluteKPa: pressureKPa, scale: scale, curve: .dew)
            let bubble = table.temperature(atAbsoluteKPa: pressureKPa, scale: scale, curve: .bubble)
            switch (dew, bubble) {
            case (.success(let dewTemp), .success(let bubbleTemp)):
                var answer = "\(table.designation) at \(reading.text(absolute: absolute)): "
                let deg = scale.symbol
                if table.isSingleComponent {
                    answer += "saturation \(fmt(dewTemp))\(deg) (single component, no glide). "
                } else {
                    answer += "dew point \(fmt(dewTemp))\(deg), bubble point \(fmt(bubbleTemp))\(deg) " +
                        "(glide \(fmt(dewTemp - bubbleTemp))\(scale.differenceSymbol)). " +
                        "Use the dew point for superheat and the bubble point for subcooling. "
                }
                answer += atmosphereSentence(site, absolute: absolute)
                answer += "Saturation data: \(table.sourceName), \(table.isSingleComponent ? "saturation" : "dew and bubble points")."
                return answer
            case (.failure(let error), _), (_, .failure(let error)):
                return refusal(error, table: table, reading: reading, atmosphere: atmosphere, absolute: absolute)
            }
        }
        if let temperature = Self.temperature(args, prefix: "temperature") {
            let scale = temperature.scale
            let unit: RefrigerantPressure.Unit = scale == .fahrenheit ? .psi : .kPa
            let dew = table.absolutePressureKPa(atTemperature: temperature.value, scale: scale, curve: .dew)
            let bubble = table.absolutePressureKPa(atTemperature: temperature.value, scale: scale, curve: .bubble)
            switch (dew, bubble) {
            case (.success(let dewKPa), .success(let bubbleKPa)):
                let show: (Double) -> String = { kPa in
                    absolute
                        ? "\(self.fmt(kPa / unit.kPa)) \(unit.absoluteSymbol)"
                        : "\(self.fmt(RefrigerantPressure.gauge(absoluteKPa: kPa, unit: unit, atmosphere: atmosphere))) \(unit.gaugeSymbol)"
                }
                var answer = "\(table.designation) at \(fmt(temperature.value))\(scale.symbol): "
                if table.isSingleComponent {
                    answer += "saturation pressure \(show(dewKPa)). "
                } else {
                    answer += "dew pressure \(show(dewKPa)), bubble pressure \(show(bubbleKPa)). "
                }
                answer += atmosphereSentence(site, absolute: absolute)
                answer += "Saturation data: \(table.sourceName), \(table.isSingleComponent ? "saturation" : "dew and bubble points")."
                return answer
            case (.failure(let error), _), (_, .failure(let error)):
                if case .temperatureOutOfTable(_, let minimum, let maximum, _) = error {
                    return "\(fmt(temperature.value))\(scale.symbol) is outside the \(table.designation) table " +
                        "(\(fmt(minimum))\(scale.symbol) to \(fmt(maximum))\(scale.symbol)). " +
                        "No saturation pressure is given outside it."
                }
                return "\(fmt(temperature.value))\(scale.symbol) is outside the \(table.designation) table."
            }
        }
        return "Specify a gauge pressure ('pressure_psig', 'pressure_kpa' or 'pressure_bar') or a temperature " +
            "('temperature_f' or 'temperature_c') for pt_lookup."
    }

    // MARK: - Sentences

    private func glideSentence(table: SaturationTable, pressureKPa: Double, scale: TemperatureScale,
                               using point: String) -> String {
        if table.isSingleComponent {
            return "\(table.designation) is a single component: no glide. "
        }
        guard case .success(let glide) = table.glide(atAbsoluteKPa: pressureKPa, scale: scale) else {
            return "Uses the \(point). "
        }
        return "Glide \(fmt(glide))\(scale.differenceSymbol) at this pressure; this uses the \(point). "
    }

    private func atmosphereSentence(_ site: Site, absolute: Bool) -> String {
        if absolute { return "Absolute pressure: no atmospheric correction. " }
        guard let altitude = site.altitudeText, !site.atmosphere.assumesSeaLevel else {
            return "Assumes sea-level atmosphere (101.325 kPa); give an altitude to correct it. "
        }
        return "Corrected for altitude \(altitude): atmosphere \(fmt(site.atmosphere.pressureKPa)) kPa. "
    }

    private func refusal(_ error: SaturationLookupError, table: SaturationTable, reading: PressureReading,
                         atmosphere: Atmosphere, absolute: Bool) -> String {
        let scale = reading.unit.answerScale
        let grid = table.grid(scale)
        let edge: (Double) -> String = { kPa in
            absolute
                ? "\(self.fmt(kPa / reading.unit.kPa)) \(reading.unit.absoluteSymbol)"
                : "\(self.fmt(RefrigerantPressure.gauge(absoluteKPa: kPa, unit: reading.unit, atmosphere: atmosphere))) \(reading.unit.gaugeSymbol)"
        }
        switch error {
        case .pressureBelowTable(_, let minimum):
            return "\(reading.text(absolute: absolute)) is below the \(table.designation) table, which starts at " +
                "\(fmt(grid.start))\(scale.symbol) (\(edge(minimum))). No saturation temperature is given outside it."
        case .pressureAboveTable(_, let maximum, let aboveCritical):
            if aboveCritical {
                let critical = scale.fromKelvin(table.criticalTemperatureK)
                return "\(reading.text(absolute: absolute)) is above the \(table.designation) table, which ends near " +
                    "its critical point (\(fmt(critical))\(scale.symbol)); above it there is no saturation " +
                    "temperature. The table's last point is \(fmt(grid.end))\(scale.symbol) (\(edge(maximum)))."
            }
            return "\(reading.text(absolute: absolute)) is above the \(table.designation) table, which ends at " +
                "\(fmt(grid.end))\(scale.symbol) (\(edge(maximum))). No saturation temperature is given outside it."
        case .temperatureOutOfTable(_, let minimum, let maximum, let scale):
            return "Outside the \(table.designation) table (\(fmt(minimum))\(scale.symbol) to \(fmt(maximum))\(scale.symbol))."
        }
    }

    // MARK: - Arguments

    private struct PressureReading {
        let value: Double
        let unit: RefrigerantPressure.Unit

        func absoluteKPa(atmosphere: Atmosphere, absolute: Bool) -> Double {
            absolute
                ? RefrigerantPressure.absoluteKPa(absolute: value, unit: unit)
                : RefrigerantPressure.absoluteKPa(gauge: value, unit: unit, atmosphere: atmosphere)
        }

        func text(absolute: Bool) -> String {
            "\(DomainCalcTool.oneDecimal(value)) \(absolute ? unit.absoluteSymbol : unit.gaugeSymbol)"
        }
    }

    private struct TemperatureReading {
        let value: Double
        let scale: TemperatureScale
    }

    private struct ArgumentProblem: Error { let text: String }

    /// The first pressure given under `<prefix>_psig`, `<prefix>_kpa` or `<prefix>_bar`.
    private static func pressure(_ args: [String: Any], prefix: String) -> PressureReading? {
        if let value = number(args["\(prefix)_psig"]) { return PressureReading(value: value, unit: .psi) }
        if let value = number(args["\(prefix)_kpa"]) { return PressureReading(value: value, unit: .kPa) }
        if let value = number(args["\(prefix)_bar"]) { return PressureReading(value: value, unit: .bar) }
        return nil
    }

    /// The temperature given under `<prefix>_f` or `<prefix>_c`.
    private static func temperature(_ args: [String: Any], prefix: String) -> TemperatureReading? {
        if let value = number(args["\(prefix)_f"]) { return TemperatureReading(value: value, scale: .fahrenheit) }
        if let value = number(args["\(prefix)_c"]) { return TemperatureReading(value: value, scale: .celsius) }
        return nil
    }

    /// The atmosphere the gauge reads against, and the altitude as it was given.
    private struct Site {
        let atmosphere: Atmosphere
        let altitudeText: String?
    }

    private static func site(_ args: [String: Any]) -> Result<Site, ArgumentProblem> {
        if let metres = number(args["altitude_m"]) {
            guard let atmosphere = Atmosphere.at(altitudeMetres: metres) else {
                return .failure(ArgumentProblem(text: altitudeRefusal))
            }
            return .success(Site(atmosphere: atmosphere, altitudeText: "\(wholeNumber(metres)) m"))
        }
        if let feet = number(args["altitude_ft"]) {
            guard let atmosphere = Atmosphere.at(altitudeFeet: feet) else {
                return .failure(ArgumentProblem(text: altitudeRefusal))
            }
            return .success(Site(atmosphere: atmosphere, altitudeText: "\(wholeNumber(feet)) ft"))
        }
        return .success(Site(atmosphere: .seaLevel, altitudeText: nil))
    }

    private static func wholeNumber(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    private static let altitudeRefusal =
        "The altitude is outside what the correction accepts (−500 m to 6,000 m, about −1,640 ft to 19,690 ft)."

    private static func number(_ value: Any?) -> Double? {
        let parsed: Double?
        if let d = value as? Double { parsed = d }
        else if let i = value as? Int { parsed = Double(i) }
        else if let s = value as? String { parsed = Double(s.trimmingCharacters(in: .whitespaces)) }
        else { parsed = nil }
        guard let parsed, parsed.isFinite else { return nil }
        return parsed
    }

    // MARK: - Helpers

    private func fmt(_ value: Double) -> String { Self.oneDecimal(value) }

    /// One decimal place, dropped when it is zero: "39.8", "40", "-40".
    nonisolated static func oneDecimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == 0 { return "0" }
        return rounded.rounded() == rounded ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}

private extension RefrigerantPressure.Unit {
    /// psig answers in °F; kPa and bar answer in °C.
    var answerScale: TemperatureScale { self == .psi ? .fahrenheit : .celsius }
}
