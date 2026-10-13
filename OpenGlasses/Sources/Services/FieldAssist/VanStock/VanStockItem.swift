import Foundation

/// How a line of van stock is counted (Plan IH §1).
///
/// A closed list, and whole quantities only: a van carries six capacitors or ten metres of cable,
/// and a fraction is out of scope until somebody needs refrigerant by weight.
enum VanStockUnit: String, Codable, CaseIterable, Sendable {
    case each
    case m
    case ft
    case kg
    case lb
    case l
    case pack

    /// "2 × Flame sensor", "10 m of Thermostat cable", "1 pack of Wire nuts".
    func phrase(_ quantity: Int, of name: String) -> String {
        switch self {
        case .each: return "\(quantity) × \(name)"
        case .pack: return "\(quantity) \(quantity == 1 ? "pack" : "packs") of \(name)"
        case .m, .ft, .kg, .lb, .l: return "\(quantity) \(rawValue) of \(name)"
        }
    }

    /// What a spoken or typed unit means. Nil for anything that is not on the list, so a unit the
    /// app does not keep is refused instead of being filed as `each`.
    init?(spoken raw: String) {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "each", "ea", "unit", "units", "piece", "pieces", "pc", "pcs": self = .each
        case "m", "metre", "metres", "meter", "meters": self = .m
        case "ft", "foot", "feet": self = .ft
        case "kg", "kilo", "kilos", "kilogram", "kilograms": self = .kg
        case "lb", "lbs", "pound", "pounds": self = .lb
        case "l", "litre", "litres", "liter", "liters": self = .l
        case "pack", "packs", "box", "boxes", "bag", "bags": self = .pack
        default: return nil
        }
    }
}

/// One line of stock on the van (Plan IH §1).
///
/// The identifier is separate from the part number on purpose: a number can be corrected, and most
/// of what a van carries — capacitors, contactors, fuses, fittings — is in no manual and may have
/// a description and no number at all.
struct VanStockItem: Codable, Equatable, Identifiable, Sendable {

    /// Who decided what the van should carry of this line: base's baseline, or this truck.
    enum StandardOrigin: String, Codable, Sendable {
        case base
        case van
    }

    let id: String
    /// The part number, normalised with `VaultPartsIndex.normalise`. Nil for a line with none.
    var number: String?
    var description: String
    var unit: VanStockUnit
    /// Warn at or below this.
    var minimum: Int?
    /// What the van should carry; a top-up fills to it.
    var standard: Int?
    var standardSetBy: StandardOrigin?
    /// A short label for where it lives on the van: "left shelf 2".
    var bin: String?
    /// Scanned codes that mean this line. A printed barcode is usually a retail code, not the part
    /// number, so it is remembered here the first time somebody says what it was.
    var codes: [String]
    /// Whether the number was found in the vault when it was last checked. Never a gate.
    var verified: Bool
    /// The batch that created the line, so undoing that batch takes the line away again.
    let createdBatch: String

    init(id: String = UUID().uuidString,
         number: String? = nil,
         description: String,
         unit: VanStockUnit = .each,
         minimum: Int? = nil,
         standard: Int? = nil,
         standardSetBy: StandardOrigin? = nil,
         bin: String? = nil,
         codes: [String] = [],
         verified: Bool = false,
         createdBatch: String) {
        self.id = id
        self.number = number
        self.description = description
        self.unit = unit
        self.minimum = minimum
        self.standard = standard
        self.standardSetBy = standardSetBy
        self.bin = bin
        self.codes = codes
        self.verified = verified
        self.createdBatch = createdBatch
    }

    enum CodingKeys: String, CodingKey {
        case id, number, description, unit, minimum, standard, bin, codes, verified
        case standardSetBy = "standard_set_by"
        case createdBatch = "created_batch"
    }

    /// "Flame sensor (62-23543-01)", "45/5 capacitor", or the bare number for a line nobody
    /// described.
    var name: String {
        let described = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number, !number.isEmpty else { return described.isEmpty ? "Unnamed item" : described }
        return described.isEmpty ? number : "\(described) (\(number))"
    }

    /// "2 × Flame sensor (62-23543-01)".
    func phrase(_ quantity: Int) -> String { unit.phrase(quantity, of: name) }
}
