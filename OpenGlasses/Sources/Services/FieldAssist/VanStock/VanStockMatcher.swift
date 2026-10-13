import Foundation

/// Which line of the van somebody means (Plan IH §2).
///
/// Deducting is the easy direction — what was said only has to match one of the lines on this van
/// — and this is what makes it easy. In order: a scanned code already attached to a line, the part
/// number exactly, the vault's supersession in both directions, then the words of the description.
/// Several candidates are handed back to be asked about. It never picks one.
///
/// Pure over the lines and a parts index, so it runs headless with no store around it.
struct VanStockMatcher {

    enum Match: Equatable {
        case one(VanStockItem)
        /// More than one line fits. The technician is asked which.
        case several([VanStockItem])
        case none
    }

    let items: [VanStockItem]
    /// The vault's parts table, for superseded numbers. Empty when there is no vault to ask.
    var partsIndex = VaultPartsIndex(files: [])

    func match(number: String? = nil, description: String? = nil, code: String? = nil) -> Match {
        if let code = code?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty,
           let item = items.first(where: { $0.codes.contains(code) }) {
            return .one(item)
        }

        let wanted = number.map(VaultPartsIndex.normalise).flatMap { $0.isEmpty ? nil : $0 }
        if let wanted {
            let exact = items.filter { $0.number == wanted }
            if let found = Self.result(exact) { return found }
            if let found = Self.result(superseded(wanted)) { return found }
        }

        // The words. With no description, what was given as a number is tried as words, because
        // "45/5 capacitor" arrives in whichever argument the model chose.
        let said = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let words = Self.tokens(said.isEmpty ? (number ?? "") : said)
        guard !words.isEmpty else { return .none }
        let described = items.filter { item in
            // A different number is a different part, however alike the descriptions are.
            if !said.isEmpty, let wanted, let own = item.number, own != wanted { return false }
            let own = Self.tokens("\(item.description) \(item.number ?? "") \(item.bin ?? "")")
            return words.isSubset(of: own)
        }
        return Self.result(described) ?? .none
    }

    /// Lines the vault says are the same part under another number: the number printed on the old
    /// component finds the stock of its replacement, and the new number finds old stock.
    private func superseded(_ wanted: String) -> [VanStockItem] {
        let replacement = partsIndex.part(number: wanted).map { VaultPartsIndex.normalise($0.number) }
        return items.filter { item in
            guard let own = item.number, own != wanted else { return false }
            if own == replacement { return true }
            return partsIndex.part(number: own).map { VaultPartsIndex.normalise($0.number) } == wanted
        }
    }

    private static func result(_ found: [VanStockItem]) -> Match? {
        switch found.count {
        case 0: return nil
        case 1: return .one(found[0])
        default: return .several(found)
        }
    }

    /// Words that say nothing about which part is meant.
    private static let filler: Set<String> = [
        "a", "an", "the", "of", "for", "my", "some", "any", "part", "number", "one", "ones", "and",
    ]

    /// Lowercased letter-and-digit runs, plural "s" dropped, filler removed. "45/5 capacitors" and
    /// "Capacitor, dual run, 45/5 µF" share `45`, `5` and `capacitor`.
    static func tokens(_ text: String) -> Set<String> {
        let runs = text.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
        return Set(runs.compactMap { run in
            let word = run.count > 3 && run.hasSuffix("s") && !run.hasSuffix("ss") ? String(run.dropLast()) : run
            return filler.contains(word) ? nil : word
        })
    }
}
