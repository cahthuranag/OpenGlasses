import Foundation

/// Which line of a refrigeration circuit a gauge reads (Plan IS P1).
enum GaugeRole: String, Equatable, CaseIterable {
    case suction
    case liquid
    case discharge

    /// The saturation curve a pressure in this role is looked up on: suction and discharge are
    /// vapour (dew point), the liquid line is liquid (bubble point).
    var curve: SaturationCurve { self == .liquid ? .bubble : .dew }
}

/// Which line a temperature probe is clamped on.
enum ProbeLine: String, Equatable, CaseIterable {
    case suction
    case liquid
    case discharge
}

/// A pressure exactly as an instrument displayed it, in a unit `RefrigerantPressure` knows
/// (Plan IS P1). A compound gauge's vacuum scale (inHg) is held as a negative gauge pressure in kPa.
struct GaugePressure: Equatable {
    enum Reference: Equatable { case gauge, absolute }

    /// In `unit`; negative only for a vacuum.
    let value: Double
    let unit: RefrigerantPressure.Unit
    let reference: Reference

    func absoluteKPa(atmosphere: Atmosphere) -> Double {
        reference == .absolute
            ? RefrigerantPressure.absoluteKPa(absolute: value, unit: unit)
            : RefrigerantPressure.absoluteKPa(gauge: value, unit: unit, atmosphere: atmosphere)
    }

    /// Parse a displayed pressure: psig/psi, psia, kPa / kPa(g), kPa abs, MPa, bar / bar(g),
    /// bar abs, and inHg (vacuum). Nil for anything else — an unknown unit is never guessed at.
    static func parse(value: Double, unit raw: String) -> GaugePressure? {
        guard value.isFinite else { return nil }
        let token = raw.lowercased().filter { !" ()._\u{00A0}".contains($0) }
        switch token {
        case "psi", "psig", "lb/in2", "lbf/in2":
            return GaugePressure(value: value, unit: .psi, reference: .gauge)
        case "psia":
            return GaugePressure(value: value, unit: .psi, reference: .absolute)
        case "kpa", "kpag", "kpagauge":
            return GaugePressure(value: value, unit: .kPa, reference: .gauge)
        case "kpaa", "kpaabs", "kpaabsolute":
            return GaugePressure(value: value, unit: .kPa, reference: .absolute)
        case "mpa", "mpag":
            return GaugePressure(value: value * 1000, unit: .kPa, reference: .gauge)
        case "mpaa", "mpaabs":
            return GaugePressure(value: value * 1000, unit: .kPa, reference: .absolute)
        case "bar", "barg", "bargauge":
            return GaugePressure(value: value, unit: .bar, reference: .gauge)
        case "bara", "barabs", "barabsolute":
            return GaugePressure(value: value, unit: .bar, reference: .absolute)
        case "inhg", "inhgvac", "\"hg", "inchesofmercury", "inhgvacuum":
            // A compound gauge's vacuum scale counts down from atmosphere: 10 inHg is 10 inHg *below*
            // it, whichever sign the display carries.
            return GaugePressure(value: -abs(value) * 3.386389, unit: .kPa, reference: .gauge)
        default:
            return nil
        }
    }
}

/// Assigns suction, liquid and discharge to the readings of one photograph, from the instrument's
/// own labels (Plan IS P1). Pure.
///
/// **A role is never guessed.** It comes from what the instrument shows, in this order:
/// 1. A role word printed on it: SUCTION / SUCT, LIQUID / LIQ, DISCHARGE / DISCH / HEAD.
/// 2. A side word: LOW / LO / LP is suction; HIGH / HI / HP is the high side, taken as the liquid
///    line — where the high-side hose connects on a split system — and said as "high side" in the
///    answer, so the technician hears which port it was.
/// 3. A colour the model reports: blue is the low side, red the high side (yellow, the utility
///    hose, carries no role).
///
/// The technician's answer to a question (`Hints`) outranks all three. Cues that disagree on one
/// reading (LOW on a red gauge, LIQUID on a blue one), or two readings claiming one role, leave
/// both unresolved, and the caller asks: "Is the left gauge suction?". Temperatures follow the same
/// rules for their line, because digital manifolds print a clamp's reading beside its side.
enum GaugeRoleResolver {

    /// The technician's answers: for a role, which reading it is — a position ("left", "middle",
    /// "right") or the value shown ("118").
    struct Hints: Equatable {
        var gauges: [GaugeRole: String] = [:]
        var probes: [ProbeLine: String] = [:]

        init(gauges: [GaugeRole: String] = [:], probes: [ProbeLine: String] = [:]) {
            self.gauges = gauges
            self.probes = probes
        }

        var isEmpty: Bool { gauges.isEmpty && probes.isEmpty }
    }

    /// Why a reading has the role it has.
    enum Basis: Equatable {
        /// A role word printed on the instrument ("SUCTION").
        case roleWord(String)
        /// LOW or HIGH printed on the instrument.
        case sideWord(String)
        /// The colour the model reported.
        case colour(String)
        /// The technician said so.
        case technician

        /// True when the role was read from the high side rather than named as the liquid line.
        var isHighSide: Bool {
            switch self {
            case .sideWord(let word): return Cue.side(of: word) == .high
            case .colour(let colour): return Cue.side(ofColour: colour) == .high
            case .roleWord, .technician: return false
            }
        }
    }

    struct Gauge: Equatable {
        let reading: InstrumentReading
        let pressure: GaugePressure
        /// "left", "middle", "right" — only when every pressure in the frame has a region.
        let position: String?
    }

    struct Probe: Equatable {
        let reading: InstrumentReading
        let scale: TemperatureScale
        let position: String?
    }

    struct ResolvedGauge: Equatable {
        let gauge: Gauge
        let role: GaugeRole
        let basis: Basis
    }

    struct ResolvedProbe: Equatable {
        let probe: Probe
        let line: ProbeLine
        let basis: Basis
    }

    struct Resolution: Equatable {
        var gauges: [GaugeRole: ResolvedGauge] = [:]
        var probes: [ProbeLine: ResolvedProbe] = [:]
        /// Pressures with no role, or whose role could not be told, in frame order.
        var unresolvedGauges: [Gauge] = []
        var unresolvedProbes: [Probe] = []

        var hasAnyPressure: Bool { !gauges.isEmpty || !unresolvedGauges.isEmpty }

        /// The question to ask when `role` is needed and unresolved, or nil when it is resolved or
        /// there is nothing in the frame to ask about.
        ///
        /// Suction is asked about the leftmost unresolved gauge and the high side about the
        /// rightmost — the order a manifold is usually read in. That is only the order of the
        /// questions; the answer still comes from the technician.
        func question(for role: GaugeRole) -> String? {
            guard gauges[role] == nil,
                  let candidate = role == .suction ? unresolvedGauges.first : unresolvedGauges.last
            else { return nil }
            let what = GaugeRoleResolver.describe(candidate)
            switch role {
            case .suction: return "Is \(what) suction?"
            case .liquid: return "Is \(what) on the liquid line?"
            case .discharge: return "Is \(what) on the discharge line?"
            }
        }

        /// The question to ask when the probe on `line` is needed and unresolved: about an
        /// unassigned probe in the frame if there is one, otherwise for the temperature itself.
        func probeQuestion(for line: ProbeLine) -> String {
            if probes[line] == nil, let candidate = unresolvedProbes.first {
                return "Is \(GaugeRoleResolver.describe(candidate)) on the \(line.rawValue) line?"
            }
            return "What's the \(line.rawValue) line temperature?"
        }
    }

    // MARK: - Resolving

    static func resolve(_ readings: [InstrumentReading], hints: Hints = Hints()) -> Resolution {
        let gauges = positioned(readings.compactMap { reading -> (InstrumentReading, GaugePressure)? in
            guard isPressure(reading), let pressure = GaugePressure.parse(value: reading.value, unit: reading.unit)
            else { return nil }
            return (reading, pressure)
        }).map { Gauge(reading: $0.0.0, pressure: $0.0.1, position: $0.1) }

        let probes = positioned(readings.compactMap { reading -> (InstrumentReading, TemperatureScale)? in
            guard let scale = temperatureScale(reading) else { return nil }
            return (reading, scale)
        }).map { Probe(reading: $0.0.0, scale: $0.0.1, position: $0.1) }

        var resolution = Resolution()

        // Gauges.
        var claims: [GaugeRole: [(Gauge, Basis)]] = [:]
        var unclaimed: [Gauge] = []
        for gauge in gauges {
            if let (role, basis) = hintedRole(for: gauge, hints: hints.gauges)
                ?? cueRole(gauge.reading).map({ (Self.gaugeRole(for: $0.cue), $0.basis) }) {
                claims[role, default: []].append((gauge, basis))
            } else {
                unclaimed.append(gauge)
            }
        }
        for (role, claimants) in claims {
            // A technician's answer settles a tie; anything else claiming one role twice is asked.
            let decided = claimants.filter { $0.1 == .technician }
            if decided.count == 1 {
                resolution.gauges[role] = ResolvedGauge(gauge: decided[0].0, role: role, basis: .technician)
                unclaimed += claimants.filter { $0.1 != .technician }.map(\.0)
            } else if claimants.count == 1 {
                resolution.gauges[role] = ResolvedGauge(gauge: claimants[0].0, role: role, basis: claimants[0].1)
            } else {
                unclaimed += claimants.map(\.0)
            }
        }
        resolution.unresolvedGauges = leftToRight(gauges.filter { gauge in unclaimed.contains(gauge) },
                                                  position: \.position)

        // Probes.
        var lineClaims: [ProbeLine: [(Probe, Basis)]] = [:]
        var unclaimedProbes: [Probe] = []
        for probe in probes {
            if let (line, basis) = hintedLine(for: probe, hints: hints.probes, all: probes)
                ?? cueRole(probe.reading).map({ (Self.probeLine(for: $0.cue), $0.basis) }) {
                lineClaims[line, default: []].append((probe, basis))
            } else {
                unclaimedProbes.append(probe)
            }
        }
        for (line, claimants) in lineClaims {
            let decided = claimants.filter { $0.1 == .technician }
            if decided.count == 1 {
                resolution.probes[line] = ResolvedProbe(probe: decided[0].0, line: line, basis: .technician)
                unclaimedProbes += claimants.filter { $0.1 != .technician }.map(\.0)
            } else if claimants.count == 1 {
                resolution.probes[line] = ResolvedProbe(probe: claimants[0].0, line: line, basis: claimants[0].1)
            } else {
                unclaimedProbes += claimants.map(\.0)
            }
        }
        resolution.unresolvedProbes = leftToRight(probes.filter { probe in unclaimedProbes.contains(probe) },
                                                  position: \.position)
        return resolution
    }

    // MARK: - Describing a reading

    /// "the left gauge (118 psig)" or, with no position, "the gauge reading 118 psig".
    static func describe(_ gauge: Gauge) -> String {
        let shown = "\(DomainCalcTool.oneDecimal(gauge.reading.value)) \(gauge.reading.unit)"
        if let position = gauge.position { return "the \(position) gauge (\(shown))" }
        return "the gauge reading \(shown)"
    }

    /// "the left probe (50 °F)" or "the probe reading 50 °F".
    static func describe(_ probe: Probe) -> String {
        let shown = "\(DomainCalcTool.oneDecimal(probe.reading.value)) \(probe.scale.symbol)"
        if let position = probe.position { return "the \(position) probe (\(shown))" }
        return "the probe reading \(shown)"
    }

    // MARK: - Cues

    /// What a reading's own text and colour say, reduced to one of four cues.
    enum Cue: Equatable {
        case suction, liquid, discharge
        case low, high

        enum Side { case low, high }

        static func side(of word: String) -> Side? {
            switch word.lowercased() {
            case "low", "lo", "lp": return .low
            case "high", "hi", "hp": return .high
            default: return nil
            }
        }

        static func side(ofColour colour: String) -> Side? {
            let words = GaugeRoleResolver.words(colour)
            if words.contains("blue") { return .low }
            if words.contains("red") { return .high }
            return nil
        }

        var side: Side {
            switch self {
            case .suction, .low: return .low
            case .liquid, .discharge, .high: return .high
            }
        }
    }

    private static let roleWords: [String: Cue] = [
        "suction": .suction, "suct": .suction,
        "liquid": .liquid, "liq": .liquid,
        "discharge": .discharge, "disch": .discharge, "head": .discharge,
    ]

    /// The cue a reading carries, or nil when it carries none or its cues disagree.
    static func cueRole(_ reading: InstrumentReading) -> (cue: Cue, basis: Basis)? {
        let text = [reading.label, reading.instrument, reading.quantity].compactMap { $0 }.joined(separator: " ")
        let tokens = words(text)

        let named = Set(tokens.compactMap { roleWords[$0] })
        let namedWord = tokens.first { roleWords[$0] != nil }
        let sides = Set(tokens.compactMap { Cue.side(of: $0) })
        let sideWord = tokens.first { Cue.side(of: $0) != nil }
        let colourSide = reading.color.flatMap(Cue.side(ofColour:))

        guard named.count <= 1, sides.count <= 1 else { return nil }
        let side = sides.first
        if let role = named.first {
            // A role word and a side word or colour that point at opposite sides is a disagreement.
            if let side, side != role.side { return nil }
            if let colourSide, colourSide != role.side { return nil }
            return (role, .roleWord(namedWord ?? ""))
        }
        if let side {
            if let colourSide, colourSide != side { return nil }
            return (side == .low ? .low : .high, .sideWord(sideWord ?? ""))
        }
        if let colourSide, let colour = reading.color {
            return (colourSide == .low ? .low : .high, .colour(colour))
        }
        return nil
    }

    private static func gaugeRole(for cue: Cue) -> GaugeRole {
        switch cue {
        case .suction, .low: return .suction
        case .liquid, .high: return .liquid
        case .discharge: return .discharge
        }
    }

    private static func probeLine(for cue: Cue) -> ProbeLine {
        switch cue {
        case .suction, .low: return .suction
        case .liquid, .high: return .liquid
        case .discharge: return .discharge
        }
    }

    // MARK: - Hints

    private static func hintedRole(for gauge: Gauge, hints: [GaugeRole: String]) -> (GaugeRole, Basis)? {
        for role in GaugeRole.allCases {
            guard let hint = hints[role] else { continue }
            if matches(hint, position: gauge.position, value: gauge.reading.value) { return (role, .technician) }
        }
        return nil
    }

    private static func hintedLine(for probe: Probe, hints: [ProbeLine: String],
                                   all: [Probe]) -> (ProbeLine, Basis)? {
        for line in ProbeLine.allCases {
            guard let hint = hints[line] else { continue }
            // "the probe" with only one probe in the frame names it.
            if all.count == 1, ["probe", "it", "yes", "the probe", "that one"].contains(hint.lowercased()) {
                return (line, .technician)
            }
            if matches(hint, position: probe.position, value: probe.reading.value) { return (line, .technician) }
        }
        return nil
    }

    /// A hint names a reading by its position or by the number it shows.
    private static func matches(_ hint: String, position: String?, value: Double) -> Bool {
        let text = hint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return false }
        if let position, words(text).contains(position) { return true }
        let numeric = text.filter { $0.isNumber || $0 == "." || $0 == "-" }
        if let number = Double(numeric) { return abs(number - value) < 0.05 }
        return false
    }

    // MARK: - Reading kinds and positions

    static func isPressure(_ reading: InstrumentReading) -> Bool {
        GaugePressure.parse(value: reading.value, unit: reading.unit) != nil
    }

    static func temperatureScale(_ reading: InstrumentReading) -> TemperatureScale? {
        switch reading.unit.lowercased().replacingOccurrences(of: "°", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) {
        case "f", "degf", "deg f", "fahrenheit": return .fahrenheit
        case "c", "degc", "deg c", "celsius": return .celsius
        default: return nil
        }
    }

    /// Each element with "left"/"right" (two) or "left"/"middle"/"right" (three), by the horizontal
    /// centre of its region — only when every element has a region; otherwise no positions at all,
    /// and the question names the value instead.
    private static func positioned<T>(_ items: [(InstrumentReading, T)]) -> [((InstrumentReading, T), String?)] {
        let centres = items.map { item -> Double? in
            guard let region = item.0.region, region.count == 4 else { return nil }
            return region[0] + region[2] / 2
        }
        guard (2...3).contains(items.count), centres.allSatisfy({ $0 != nil }) else {
            return items.map { ($0, nil) }
        }
        let names = items.count == 2 ? ["left", "right"] : ["left", "middle", "right"]
        let order = centres.enumerated().sorted { ($0.element ?? 0) < ($1.element ?? 0) }.map(\.offset)
        // Two displays at the same place cannot be told apart by position.
        let sorted = order.map { centres[$0] ?? 0 }
        guard zip(sorted, sorted.dropFirst()).allSatisfy({ $1 - $0 > 0.02 }) else {
            return items.map { ($0, nil) }
        }
        var result = items.map { ($0, Optional<String>.none) }
        for (rank, index) in order.enumerated() { result[index].1 = names[rank] }
        return result
    }

    /// Left, middle, right when every item has a position; frame order otherwise.
    private static func leftToRight<T>(_ items: [T], position: (T) -> String?) -> [T] {
        let rank = ["left": 0, "middle": 1, "right": 2]
        guard items.allSatisfy({ position($0).flatMap { rank[$0] } != nil }) else { return items }
        return items.sorted { (position($0).flatMap { rank[$0] } ?? 0) < (position($1).flatMap { rank[$0] } ?? 0) }
    }

    /// Lowercased alphanumeric words.
    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
