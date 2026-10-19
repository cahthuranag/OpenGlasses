import Foundation

/// Where the refrigerant designation came from (Plan IS P1, decision 3: it is never assumed).
enum RefrigerantSource: String, Equatable, CaseIterable {
    /// Read off the unit's nameplate.
    case nameplate
    /// The technician said it.
    case technician
    /// Shown on the equipment's own display or control board.
    case display

    init(identity source: DeviceIdentityField.Source) {
        switch source {
        case .nameplate: self = .nameplate
        case .spoken: self = .technician
        case .display: self = .display
        }
    }

    /// "from the nameplate", "as you said", "from the unit's display".
    var phrase: String {
        switch self {
        case .nameplate: return "from the nameplate"
        case .technician: return "as you said"
        case .display: return "from the unit's display"
        }
    }
}

/// A refrigerant and where it came from.
struct RefrigerantIdentity: Equatable {
    let designation: String
    let source: RefrigerantSource
}

/// One photograph of a manifold or a digital gauge set, taken to an answer (Plan IS P1).
///
/// Pure: readings in (already decoded by `instrument_reading`), sentences and recordable readings
/// out. The camera, the model and the job record are the tool's business (`RefrigerantGaugeTool`);
/// this is the part that decides what may be said.
///
/// - Roles come from `GaugeRoleResolver`; one it cannot tell is asked, never guessed.
/// - Without a refrigerant there are pressures, not saturation temperatures (decision 3).
/// - A pressure outside the refrigerant's band (`InstrumentPlausibility.refrigerantBand`) asks for
///   a re-look instead of an answer.
/// - The calculation runs in SI through `RefrigerantLineCalculation`, the same lookup
///   `domain_calc` uses, and the answer is rendered in the technician's units.
enum RefrigerantGaugeChain {

    /// The confidence a reading needs before it is used — the instrument-reading schema's floor.
    static let confidenceFloor = InstrumentReadingSchema().confidenceFloor

    struct LineTemperature: Equatable {
        let value: Double
        let scale: TemperatureScale
    }

    struct Request: Equatable {
        /// Superheat, subcooling or both, in the order asked.
        var calculations: [RefrigerantLineCalculation.Kind] = [.superheat, .subcool]
        var refrigerant: RefrigerantIdentity?
        /// Line temperatures the technician said, which outrank a probe in the frame.
        var spokenLines: [ProbeLine: LineTemperature] = [:]
        var hints = GaugeRoleResolver.Hints()
        var units: RefrigerationUnits = .imperial
        var atmosphere: Atmosphere = .seaLevel
        /// "1200 m" when an altitude was given.
        var altitudeText: String?
        var application: InstrumentPlausibility.RefrigerantApplication = .unspecified
    }

    /// A reading the record should hold, shaped like a `SpokenReading`.
    struct RecordableReading: Equatable {
        /// What makes it the same reading on a second call about the same photograph.
        let key: String
        let quantity: String
        /// As the instrument displayed it (or as the technician said it).
        let value: String
        let unit: String?
        /// True for a value read off the photograph; false for one the technician said.
        let fromInstrument: Bool
    }

    struct Outcome: Equatable {
        var lines: [String] = []
        /// A question is waiting for the technician: a role, a line temperature or the refrigerant.
        var asksQuestion = false
        /// A reading has to be looked at again before it is trusted.
        var asksRecapture = false
        var answered: [RefrigerantLineCalculation.Kind] = []
        var recordable: [RecordableReading] = []

        var text: String { lines.joined(separator: " ") }
    }

    static func run(readings: [InstrumentReading], request: Request,
                    table tableFor: (String) -> SaturationTable?) -> Outcome {
        var outcome = Outcome()
        let usable = readings.filter {
            ($0.confidence ?? 0) >= confidenceFloor && !InstrumentPlausibility.isImplausible($0)
        }
        let unclearPressure = readings.contains { !usable.contains($0) && GaugeRoleResolver.isPressure($0) }
        let resolution = GaugeRoleResolver.resolve(usable, hints: request.hints)

        guard resolution.hasAnyPressure else {
            outcome.asksRecapture = true
            outcome.lines.append(unclearPressure
                ? "Re-capture the gauges: the pressure wasn't clear enough to read."
                : "I can't read a pressure in the picture. Point the camera squarely at the manifold or the gauge display and ask again.")
            return outcome
        }

        // Decision 3: no refrigerant, no saturation temperatures.
        guard let refrigerant = request.refrigerant else {
            outcome.lines.append(readingsLine(resolution, request: request, excluding: []))
            outcome.lines.append("No saturation temperatures without the refrigerant. Which refrigerant is it? "
                + "It's on the nameplate; I won't assume one.")
            outcome.asksQuestion = true
            outcome.recordable = recordable(resolution, request: request, excluding: [])
            return outcome
        }
        guard let table = tableFor(refrigerant.designation) else {
            outcome.lines.append("No saturation table for \(refrigerant.designation), so pressures only.")
            outcome.lines.append(readingsLine(resolution, request: request, excluding: []))
            outcome.recordable = recordable(resolution, request: request, excluding: [])
            return outcome
        }

        let units = request.units
        let scale = units.temperature.scale
        var flagged: Set<UUID> = []
        for kind in request.calculations {
            let role: GaugeRole = kind == .superheat ? .suction : .liquid
            let line: ProbeLine = kind == .superheat ? .suction : .liquid
            guard let gauge = resolution.gauges[role] else {
                if let question = resolution.question(for: role) {
                    outcome.lines.append(question)
                    outcome.asksQuestion = true
                } else if unclearPressure {
                    outcome.lines.append("Re-capture the gauges: the \(role == .suction ? "suction" : "liquid") reading wasn't clear.")
                    outcome.asksRecapture = true
                } else {
                    outcome.lines.append(role == .suction
                        ? "I can't see a suction gauge in the picture."
                        : "I can't see a liquid or high-side gauge in the picture.")
                }
                continue
            }
            let side = sideName(gauge)
            let absoluteKPa = gauge.gauge.pressure.absoluteKPa(atmosphere: request.atmosphere)
            if let band = InstrumentPlausibility.refrigerantBand(table: table, role: role,
                                                                 application: request.application),
               !band.contains(absoluteKPa: absoluteKPa) {
                outcome.lines.append(recaptureLine(gauge, side: side, band: band, table: table,
                                                   absoluteKPa: absoluteKPa, request: request))
                outcome.asksRecapture = true
                flagged.insert(gauge.gauge.reading.id)
                continue
            }
            guard let lineTemperature = request.spokenLines[line]
                ?? resolution.probes[line].map({ LineTemperature(value: $0.probe.reading.value, scale: $0.probe.scale) })
            else {
                outcome.lines.append(resolution.probeQuestion(for: line))
                outcome.asksQuestion = true
                continue
            }
            switch RefrigerantLineCalculation.compute(kind, table: table, absoluteKPa: absoluteKPa,
                                                      lineTemperature: lineTemperature.value,
                                                      lineScale: lineTemperature.scale, scale: scale) {
            case .failure(let error):
                outcome.lines.append(refusal(error, side: side, gauge: gauge, request: request, table: table))
                outcome.asksRecapture = true
            case .success(let result):
                outcome.lines.append(contentsOf: sentences(kind, result: result, side: side, gauge: gauge,
                                                           table: table, request: request))
                outcome.answered.append(kind)
            }
        }
        if !outcome.answered.isEmpty {
            outcome.lines.append(sourceLine(table: table, refrigerant: refrigerant, request: request))
        }
        outcome.recordable = recordable(resolution, request: request, excluding: flagged)
        return outcome
    }

    // MARK: - Sentences

    /// "Superheat 11 °F: suction 118 psig is 39 °F dew for R-410A, line 50 °F.", then the glide for
    /// a blend and the floodback or flash-gas line when the number is negative.
    private static func sentences(_ kind: RefrigerantLineCalculation.Kind, result: RefrigerantLineCalculation.Output,
                                  side: String, gauge: GaugeRoleResolver.ResolvedGauge,
                                  table: SaturationTable, request: Request) -> [String] {
        let scale = request.units.temperature.scale
        let deg = " " + scale.symbol
        let diff = " " + scale.differenceSymbol
        let title = kind == .superheat ? "Superheat" : "Subcooling"
        let point = kind == .superheat ? "dew" : "bubble"
        var lines = ["\(title) \(fmt(result.difference))\(diff): \(side) \(pressureText(gauge.gauge, request: request)) "
            + "is \(fmt(result.saturation))\(deg) \(point) for \(table.designation), line \(fmt(result.line))\(deg)."]
        if let glide = result.glide, abs(glide) >= 0.05 {
            lines.append("Glide \(fmt(glide))\(diff) at that pressure, so "
                + (kind == .superheat ? "superheat uses the dew point." : "subcooling uses the bubble point."))
        }
        if kind == .superheat, result.difference < 0 {
            lines.append("Negative superheat suggests liquid floodback — recheck readings.")
        }
        if kind == .subcool, result.difference < 0 {
            lines.append("Negative subcool suggests undercharge or flash gas — recheck.")
        }
        return lines
    }

    private static func sourceLine(table: SaturationTable, refrigerant: RefrigerantIdentity,
                                   request: Request) -> String {
        var line = "Saturation data: \(table.sourceName). \(table.designation) \(refrigerant.source.phrase). "
        if let altitude = request.altitudeText, !request.atmosphere.assumesSeaLevel {
            line += "Corrected for altitude \(altitude)."
        } else {
            line += "Assumes sea-level atmosphere; give an altitude to correct it."
        }
        return line
    }

    /// "Re-look at the suction gauge: 30 psig is a -16 °F dew point for R-410A, outside the 14 to
    /// 68 °F range for a suction line in cooling. Check the reading and the hose before I give a
    /// number."
    private static func recaptureLine(_ gauge: GaugeRoleResolver.ResolvedGauge, side: String,
                                      band: InstrumentPlausibility.RefrigerantPressureBand,
                                      table: SaturationTable, absoluteKPa: Double, request: Request) -> String {
        let scale = request.units.temperature.scale
        let deg = " " + scale.symbol
        let point = gauge.role.curve == .dew ? "dew point" : "bubble point"
        let saturation: String
        switch table.temperature(atAbsoluteKPa: absoluteKPa, scale: scale, curve: gauge.role.curve) {
        case .success(let value): saturation = "is a \(fmt(value))\(deg) \(point) for \(table.designation)"
        case .failure: saturation = "is below what the \(table.designation) table covers"
        }
        let low = fmt(scale.fromKelvin(band.windowKelvin.lowerBound))
        let window = band.highKPa == nil
            ? "below the \(low)\(deg) minimum"
            : "outside the \(low) to \(fmt(scale.fromKelvin(band.windowKelvin.upperBound)))\(deg) range"
        return "Re-look at the \(side) gauge: \(pressureText(gauge.gauge, request: request)) \(saturation), "
            + "\(window) for a \(side) line\(request.application.phrase). "
            + "Check the reading and the hose before I give a number."
    }

    private static func refusal(_ error: SaturationLookupError, side: String,
                                gauge: GaugeRoleResolver.ResolvedGauge, request: Request,
                                table: SaturationTable) -> String {
        let shown = "\(side) \(pressureText(gauge.gauge, request: request))"
        switch error {
        case .pressureAboveTable(_, _, let aboveCritical):
            return aboveCritical
                ? "The \(shown) is above \(table.designation)'s critical point: there is no saturation temperature there."
                : "The \(shown) is above what the \(table.designation) table covers: no saturation temperature is given outside it."
        case .pressureBelowTable:
            return "The \(shown) is below what the \(table.designation) table covers: no saturation temperature is given outside it."
        case .temperatureOutOfTable:
            return "The \(shown) is outside the \(table.designation) table."
        }
    }

    /// "Readings: suction 118 psig, high side 380 psig, the gauge reading 75 psig, suction line 50 °F."
    private static func readingsLine(_ resolution: GaugeRoleResolver.Resolution, request: Request,
                                     excluding flagged: Set<UUID>) -> String {
        var parts: [String] = []
        for role in GaugeRole.allCases {
            guard let gauge = resolution.gauges[role], !flagged.contains(gauge.gauge.reading.id) else { continue }
            parts.append("\(sideName(gauge)) \(pressureText(gauge.gauge, request: request))")
        }
        for gauge in resolution.unresolvedGauges {
            parts.append("\(GaugeRoleResolver.describe(gauge)) (role not confirmed)")
        }
        let scale = request.units.temperature.scale
        for line in ProbeLine.allCases {
            if let spoken = request.spokenLines[line] {
                parts.append("\(line.rawValue) line \(fmt(scale.convert(spoken.value, from: spoken.scale))) \(scale.symbol)")
            } else if let probe = resolution.probes[line] {
                parts.append("\(line.rawValue) line "
                    + "\(fmt(scale.convert(probe.probe.reading.value, from: probe.probe.scale))) \(scale.symbol)")
            }
        }
        return "Readings: " + parts.joined(separator: ", ") + "."
    }

    // MARK: - Recording

    private static func recordable(_ resolution: GaugeRoleResolver.Resolution, request: Request,
                                   excluding flagged: Set<UUID>) -> [RecordableReading] {
        var out: [RecordableReading] = []
        for role in GaugeRole.allCases {
            guard let gauge = resolution.gauges[role], !flagged.contains(gauge.gauge.reading.id) else { continue }
            let reading = gauge.gauge.reading
            out.append(RecordableReading(key: reading.id.uuidString, quantity: "\(sideName(gauge)) pressure",
                                         value: fmt(reading.value), unit: reading.unit, fromInstrument: true))
        }
        for line in ProbeLine.allCases {
            if let spoken = request.spokenLines[line] {
                out.append(RecordableReading(key: "spoken-\(line.rawValue)-\(spoken.value)-\(spoken.scale.rawValue)",
                                             quantity: "\(line.rawValue) line temperature",
                                             value: fmt(spoken.value), unit: spoken.scale.symbol,
                                             fromInstrument: false))
            } else if let probe = resolution.probes[line] {
                let reading = probe.probe.reading
                out.append(RecordableReading(key: reading.id.uuidString,
                                             quantity: "\(line.rawValue) line temperature",
                                             value: fmt(reading.value), unit: reading.unit, fromInstrument: true))
            }
        }
        return out
    }

    // MARK: - Rendering

    /// "suction", "liquid", "high side", "discharge".
    static func sideName(_ gauge: GaugeRoleResolver.ResolvedGauge) -> String {
        switch gauge.role {
        case .suction: return "suction"
        case .liquid: return gauge.basis.isHighSide ? "high side" : "liquid"
        case .discharge: return "discharge"
        }
    }

    /// The gauge pressure in the technician's unit — "118 psig", "820 kPa", "8.2 bar" — with the
    /// display's own value beside it when the display used another unit or read absolute.
    static func pressureText(_ gauge: GaugeRoleResolver.Gauge, request: Request) -> String {
        let unit = request.units.pressure
        let absoluteKPa = gauge.pressure.absoluteKPa(atmosphere: request.atmosphere)
        let shown = RefrigerantPressure.gauge(absoluteKPa: absoluteKPa, unit: unit.unit, atmosphere: request.atmosphere)
        var text = "\(fmt(shown)) \(unit.gaugeLabel)"
        // A display in another unit, an absolute one, or one converted on the way in (MPa, a vacuum
        // in inHg) is also given as it was shown, so the technician can match it to the gauge.
        if gauge.pressure.unit != unit.unit || gauge.pressure.reference == .absolute
            || gauge.pressure.value != gauge.reading.value {
            text += " (\(fmt(gauge.reading.value)) \(gauge.reading.unit) on the gauge)"
        }
        return text
    }

    private static func fmt(_ value: Double) -> String { DomainCalcTool.oneDecimal(value) }
}
