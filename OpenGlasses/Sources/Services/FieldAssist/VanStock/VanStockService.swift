import Foundation

/// What a technician says about the van, turned into movements and a read-back (Plan IH §3).
///
/// The tool parses arguments and the screen shows rows; this is the one place a spoken line is
/// matched, recorded and answered, so the voice and the phone cannot disagree about what a load or
/// a use means. Nothing here touches the network.
@MainActor
final class VanStockService {

    static let shared = VanStockService()

    /// One spoken line: "four flame sensors, part 62-23543-01".
    struct Line: Equatable {
        var part: String?
        var description: String?
        var quantity: Int?
        var unit: String?
        var code: String?
        /// The technician said this is a different part from the similar line already on the van.
        /// Only its number or its code may then match; its description starts a new line.
        var asNew: Bool

        init(part: String? = nil, description: String? = nil, quantity: Int? = nil,
             unit: String? = nil, code: String? = nil, asNew: Bool = false) {
            self.part = part?.trimmingCharacters(in: .whitespacesAndNewlines).vanStockNonEmpty
            self.description = description?.trimmingCharacters(in: .whitespacesAndNewlines).vanStockNonEmpty
            self.quantity = quantity
            self.unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines).vanStockNonEmpty
            self.code = code?.trimmingCharacters(in: .whitespacesAndNewlines).vanStockNonEmpty
            self.asNew = asNew
        }

        /// What to call the line when nothing on the van matches it.
        var reference: String { part ?? description ?? "that code" }
    }

    /// The job that is open, when one is.
    struct Job: Equatable {
        let sessionID: String
        let reference: String?
    }

    /// A model that retries must not load four sensors twice: the same write inside this many
    /// seconds is one write.
    static let duplicateWindow: TimeInterval = 10

    private let store: VanStockStore
    private let verify: @MainActor (String) -> TaskPart
    private let partsIndex: @MainActor () -> VaultPartsIndex
    private let activeJob: @MainActor () -> Job?
    private let now: () -> Date
    private let calendar: Calendar
    private let makeID: () -> String

    private var lastWrite: (signature: String, at: Date, answer: String)?

    init(store: VanStockStore? = nil,
         verify: (@MainActor (String) -> TaskPart)? = nil,
         partsIndex: (@MainActor () -> VaultPartsIndex)? = nil,
         activeJob: (@MainActor () -> Job?)? = nil,
         now: @escaping () -> Date = Date.init,
         calendar: Calendar = .current,
         makeID: @escaping () -> String = { UUID().uuidString }) {
        self.store = store ?? .shared
        self.verify = verify ?? { FieldSessionService.shared.verifyPart($0) }
        self.partsIndex = partsIndex ?? { FieldSessionService.shared.partsIndex }
        self.activeJob = activeJob ?? {
            FieldSessionService.shared.activeSession.map { Job(sessionID: $0.id, reference: $0.jobReference) }
        }
        self.now = now
        self.calendar = calendar
        self.makeID = makeID
    }

    private var composer: VanStockAnswerComposer { VanStockAnswerComposer(now: now(), calendar: calendar) }

    private static let unreadable = "The van stock list on this phone could not be read, so nothing "
        + "was looked up or changed. Tell the technician; do not guess what is on the van."

    // MARK: - Reading

    func check(_ line: Line) -> String {
        guard !store.isUnreadable else { return Self.unreadable }
        let log = store.log
        guard !log.isEmpty else { return composer.emptyVan() }
        switch match(line, in: log) {
        case .one(let item): return composer.check(item, level: log.level(of: item.id))
        case .several(let items): return composer.candidates(items, levels: log.levels)
        case .none: return composer.notOnVan(line.reference)
        }
    }

    func low() -> String {
        guard !store.isUnreadable else { return Self.unreadable }
        let log = store.log
        guard !log.isEmpty else { return composer.emptyVan() }
        let levels = log.levels
        return composer.low(log.lowItems.map { (item: $0, level: levels[$0.id] ?? VanStockLevel(itemID: $0.id)) })
    }

    // MARK: - Writing

    func load(_ lines: [Line], source: VanStockMovement.Source = .spoken) -> String {
        write("load", lines) { log, line, batch, at in
            let quantity = line.quantity ?? 1
            guard quantity >= 1 else { return "Nothing loaded for \(line.reference): the quantity has to be at least 1." }
            switch self.target(line, in: &log, batch: batch, at: at, source: source, mayCreate: true) {
            case .failure(let message): return message
            case .success(let found):
                let before = log.level(of: found.item.id)
                let job = self.activeJob()
                log.record(.loaded, itemID: found.item.id, quantity: quantity, at: at, batch: batch,
                           source: source, id: self.makeID(), jobSessionID: job?.sessionID,
                           jobReference: job?.reference)
                return self.composer.loaded(found.item, quantity: quantity, before: before,
                                            after: log.level(of: found.item.id), created: found.created)
            }
        }
    }

    func use(_ lines: [Line], source: VanStockMovement.Source = .spoken) -> String {
        write("use", lines) { log, line, batch, at in
            let quantity = line.quantity ?? 1
            guard quantity >= 1 else { return "Nothing recorded for \(line.reference): the quantity has to be at least 1." }
            switch self.target(line, in: &log, batch: batch, at: at, source: source, mayCreate: false) {
            case .failure(let message): return message
            case .success(let found):
                let before = log.level(of: found.item.id)
                let job = self.activeJob()
                log.record(.used, itemID: found.item.id, quantity: quantity, at: at, batch: batch,
                           source: source, id: self.makeID(), jobSessionID: job?.sessionID,
                           jobReference: job?.reference)
                return self.composer.used(found.item, quantity: quantity, before: before,
                                          after: log.level(of: found.item.id), jobReference: job?.reference)
            }
        }
    }

    func remove(_ lines: [Line], reason: VanStockMovement.RemovalReason,
                source: VanStockMovement.Source = .spoken) -> String {
        write("remove:\(reason.rawValue)", lines) { log, line, batch, at in
            let quantity = line.quantity ?? 1
            guard quantity >= 1 else { return "Nothing removed for \(line.reference): the quantity has to be at least 1." }
            switch self.target(line, in: &log, batch: batch, at: at, source: source, mayCreate: false) {
            case .failure(let message): return message
            case .success(let found):
                let before = log.level(of: found.item.id)
                log.record(.removed, itemID: found.item.id, quantity: quantity, at: at, batch: batch,
                           source: source, id: self.makeID(), reason: reason)
                return self.composer.removed(found.item, quantity: quantity, reason: reason, before: before,
                                             after: log.level(of: found.item.id))
            }
        }
    }

    func count(_ lines: [Line], source: VanStockMovement.Source = .spoken) -> String {
        write("count", lines) { log, line, batch, at in
            guard let quantity = line.quantity else { return "Say how many \(line.reference) were counted." }
            guard quantity >= 0 else { return "Nothing counted for \(line.reference): a count cannot be below zero." }
            switch self.target(line, in: &log, batch: batch, at: at, source: source, mayCreate: true) {
            case .failure(let message): return message
            case .success(let found):
                log.record(.counted, itemID: found.item.id, quantity: quantity, at: at, batch: batch,
                           source: source, id: self.makeID())
                return self.composer.counted(found.item, after: log.level(of: found.item.id), created: found.created)
            }
        }
    }

    /// Take back the most recent batch.
    func undo(source: VanStockMovement.Source = .spoken) -> String {
        guard !store.isUnreadable else { return Self.unreadable }
        lastWrite = nil
        let at = now()
        let undone = store.update { $0.undoLastBatch(at: at, batch: self.makeID(), source: source, makeID: self.makeID) }
        guard let undone = undone ?? nil else { return composer.nothingToUndo() }
        return composer.undone(undone, items: store.log.items)
    }

    // MARK: - From the screen

    /// Whether there is an entry to take back.
    var canUndo: Bool { !store.isUnreadable && store.log.canUndo }

    /// A count typed on the Van Stock screen. False when nothing was recorded.
    @discardableResult
    func setCount(itemID: String, to quantity: Int) -> Bool {
        lastWrite = nil
        let at = now()
        let batch = makeID()
        let recorded = store.update { log in
            log.record(.counted, itemID: itemID, quantity: quantity, at: at, batch: batch,
                       source: .typed, id: self.makeID()) != nil
        }
        return recorded ?? false
    }

    /// Changes typed on the Van Stock screen, as one batch. A new part number is looked up again,
    /// so a corrected number is not left marked as verified on the strength of the old one.
    @discardableResult
    func edit(itemID: String, _ changes: [VanStockLog.Change]) -> Bool {
        lastWrite = nil
        let at = now()
        let batch = makeID()
        let changed = store.update { log -> Bool in
            var any = false
            for change in changes {
                any = log.edit(itemID: itemID, change, at: at, batch: batch, source: .typed, id: self.makeID()) || any
                if case .number(let number) = change {
                    let verified = number.map { self.verify($0).verified } ?? false
                    any = log.edit(itemID: itemID, .verified(verified), at: at, batch: batch,
                                   source: .typed, id: self.makeID()) || any
                }
            }
            return any
        }
        return changed ?? false
    }

    /// A replacement was asked for: the van now knows something is coming. Nil when the part is
    /// not a line on the van — an order never creates one.
    @discardableResult
    func noteOrdered(number: String, quantity: Int, requestID: String) -> String? {
        guard !store.isUnreadable else { return nil }
        let at = now()
        let batch = makeID()
        let recorded = store.update { log -> VanStockLevel? in
            guard case .one(let item) = VanStockMatcher(items: log.items, partsIndex: self.partsIndex())
                .match(number: number) else { return nil }
            log.record(.ordered, itemID: item.id, quantity: max(quantity, 1), at: at, batch: batch,
                       source: .spoken, id: self.makeID(), requestID: requestID)
            return log.level(of: item.id)
        } ?? nil
        return recorded.map { "The van list now shows \($0.onOrder) asked for and not yet loaded." }
    }

    // MARK: - One write

    private func write(_ action: String, _ lines: [Line],
                       _ apply: (inout VanStockLog, Line, _ batch: String, _ at: Date) -> String) -> String {
        guard !store.isUnreadable else { return Self.unreadable }
        guard !lines.isEmpty else { return "Say which part, and how many." }

        let at = now()
        let signature = action + "|" + lines.map {
            "\($0.part ?? "")~\($0.description ?? "")~\($0.quantity.map(String.init) ?? "")~\($0.unit ?? "")~\($0.code ?? "")~\($0.asNew)"
        }.joined(separator: "|")
        if let last = lastWrite, last.signature == signature,
           at.timeIntervalSince(last.at) < Self.duplicateWindow {
            return "Already recorded a moment ago, not recorded twice. " + last.answer
        }

        let batch = makeID()
        let answers = store.update { log in lines.map { apply(&log, $0, batch, at) } } ?? []
        let answer = answers.joined(separator: "\n")
        lastWrite = (signature, at, answer)
        return answer
    }

    // MARK: - Finding or making the line

    private struct Found {
        let item: VanStockItem
        let created: Bool
    }

    private enum Target {
        case success(Found)
        case failure(String)
    }

    private func match(_ line: Line, in log: VanStockLog, byWords: Bool = true) -> VanStockMatcher.Match {
        let matcher = VanStockMatcher(items: log.items, partsIndex: partsIndex())
        guard byWords else { return matcher.match(number: Self.number(in: line), code: line.code) }
        return matcher.match(number: line.part, description: line.description, code: line.code)
    }

    /// The line a write is about. Only a load or a count may make a new one; anything else that
    /// matches nothing changes nothing.
    private func target(_ line: Line, in log: inout VanStockLog, batch: String, at: Date,
                        source: VanStockMovement.Source, mayCreate: Bool) -> Target {
        switch match(line, in: log, byWords: !(mayCreate && line.asNew)) {
        case .several(let items):
            return .failure(composer.candidates(items, levels: log.levels))
        case .one(let item):
            if let raw = line.unit {
                guard let unit = VanStockUnit(spoken: raw) else { return .failure(Self.unknownUnit(raw)) }
                guard unit == item.unit else {
                    return .failure("\(item.name) is counted in \(item.unit.rawValue), not \(unit.rawValue). Nothing was changed.")
                }
            }
            attach(line, to: item, in: &log, batch: batch, at: at, source: source)
            return .success(Found(item: log.item(id: item.id) ?? item, created: false))
        case .none:
            guard mayCreate else { return .failure(composer.notOnVan(line.reference)) }
            return create(line, in: &log, batch: batch)
        }
    }

    /// What a write can add to a line it matched: a number it did not have, a scanned code, and a
    /// fresh look in the manuals for a number that was not verified last time.
    private func attach(_ line: Line, to item: VanStockItem, in log: inout VanStockLog, batch: String,
                        at: Date, source: VanStockMovement.Source) {
        if item.number == nil, let number = Self.number(in: line) {
            let checked = verify(number)
            log.edit(itemID: item.id, .number(checked.number), at: at, batch: batch, source: source, id: makeID())
            log.edit(itemID: item.id, .verified(checked.verified), at: at, batch: batch, source: source, id: makeID())
        } else if let number = item.number, !item.verified, verify(number).verified {
            log.edit(itemID: item.id, .verified(true), at: at, batch: batch, source: source, id: makeID())
        }
        if let code = line.code {
            log.edit(itemID: item.id, .addCode(code), at: at, batch: batch, source: .scanned, id: makeID())
        }
    }

    private func create(_ line: Line, in log: inout VanStockLog, batch: String) -> Target {
        let number = Self.number(in: line)
        // Words given where a number goes are the description.
        let described = line.description ?? (number == nil ? line.part : nil)
        guard number != nil || described != nil else {
            if line.code != nil {
                return .failure("That code is not on the van list yet. Ask the technician what the part is, "
                    + "then record it again with the code and its part number or description.")
            }
            return .failure("Say what the part is: a part number, a description, or both.")
        }
        var unit = VanStockUnit.each
        if let raw = line.unit {
            guard let spoken = VanStockUnit(spoken: raw) else { return .failure(Self.unknownUnit(raw)) }
            unit = spoken
        }
        let checked = number.map(verify)
        let item = log.addItem(id: makeID(),
                               number: checked?.number ?? number,
                               description: described ?? checked?.partDescription ?? "",
                               unit: unit,
                               codes: line.code.map { [$0] } ?? [],
                               verified: checked?.verified ?? false,
                               batch: batch)
        return .success(Found(item: item, created: true))
    }

    /// The part number in a line, when what was given is one. A part number has no spaces and at
    /// least one digit; words in its place are a description.
    private static func number(in line: Line) -> String? {
        guard let part = line.part, !part.contains(where: \.isWhitespace),
              part.contains(where: \.isNumber) else { return nil }
        let normalised = VaultPartsIndex.normalise(part)
        return normalised.isEmpty ? nil : normalised
    }

    private static func unknownUnit(_ raw: String) -> String {
        "'\(raw)' is not a unit the van list keeps. Use one of: "
            + VanStockUnit.allCases.map(\.rawValue).joined(separator: ", ") + ". Nothing was changed."
    }
}

private extension String {
    var vanStockNonEmpty: String? { isEmpty ? nil : self }
}
