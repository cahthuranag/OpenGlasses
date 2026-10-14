import Foundation

/// A part that came off the van on one job (Plan IH §7).
///
/// Kept on the job as well as in the van's log, because the two outlive each other differently: the
/// van's log changes hands with the vehicle, and the job's record stays the job's. This is the
/// quantity the work record was missing — a part on a finished task says it was fitted, not how
/// many, and not that it came from the van.
struct VanStockUse: Codable, Equatable, Identifiable, Sendable {
    /// The movement in the van's log that recorded it, so an undo there takes it off the job too.
    let id: String
    let number: String?
    let description: String
    let quantity: Int
    let unit: VanStockUnit
    /// Whether the part number was found in the manuals.
    let verified: Bool
    let at: Date

    /// "2 × Igniter (22B22)".
    var summary: String {
        let described = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String
        if let number, !number.isEmpty {
            name = described.isEmpty ? number : "\(described) (\(number))"
        } else {
            name = described.isEmpty ? "Unnamed item" : described
        }
        return unit.phrase(quantity, of: name)
    }
}

/// Which parts on a job's finished tasks have no stock entry (Plan IH §7).
///
/// The complaint this plan started from is a part used and never recorded. A part on a finished
/// task is the one place the app already knows something was fitted, so those are compared with
/// what was recorded as used on the job. A part with no entry is asked about — it is never
/// deducted, because a part on a task is not proof of where it came from.
///
/// Pure.
enum VanStockReconciler {

    /// Parts on finished tasks that were neither recorded as used from the van on this job nor
    /// said not to have come from it, in the order the job reached them.
    static func unrecorded(partsUsed: [TaskPart], uses: [VanStockUse], notFromVan: [String]) -> [TaskPart] {
        let recorded = Set(uses.compactMap { $0.number.map(VaultPartsIndex.normalise) })
        let dismissed = Set(notFromVan.map(VaultPartsIndex.normalise))
        var seen = Set<String>()
        return partsUsed.filter { part in
            let number = VaultPartsIndex.normalise(part.number)
            guard !number.isEmpty, seen.insert(number).inserted else { return false }
            return !recorded.contains(number) && !dismissed.contains(number)
        }
    }

    /// "the igniter (22B22) and the pressure switch (14T65)" — for the question at the close.
    static func named(_ parts: [TaskPart]) -> String {
        let names = parts.map { part in
            part.partDescription.map { "\($0) (\(part.number))" } ?? part.number
        }
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }
}
