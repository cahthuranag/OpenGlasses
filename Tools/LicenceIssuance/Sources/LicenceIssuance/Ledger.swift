import Foundation

public struct IssuanceRecord: Codable, Equatable {
    public let issuanceId: String
    public let partnerId: String
    public let grantVersion: Int
    public let operatorId: String
    public let issuedAt: Date
    public let licensee: String
    public let tier: String
    public let plan: String
    public let seats: Int
    public let packs: [String]
    public let expires: Date
    public let reference: String
    public let profile: String?
    public let licenseDigest: String
    public let licenseIDHash: String
    public let replaces: String?
    public let orderId: String?
    public let phase: Phase
    public enum Phase: String, Codable { case manual, provisional, full, pilot }
    public init(id: String, partner: PartnerGrant, operatorId: String, payload: IssuedLicensePayload,
                code: String, replaces: String? = nil, orderId: String? = nil, phase: Phase = .manual) throws {
        guard let expiry = payload.expires, let seats = payload.seats, seats > 0,
              !id.isEmpty, !operatorId.isEmpty else { throw IssuanceRefusal.invalidRequest }
        issuanceId = id; partnerId = partner.partnerId; grantVersion = partner.version; self.operatorId = operatorId
        issuedAt = payload.issued; licensee = payload.licensee; tier = payload.tier ?? "team"; plan = payload.plan ?? "team"
        self.seats = seats; packs = payload.packs ?? []; expires = expiry; reference = payload.reference ?? ""
        profile = payload.profile; licenseDigest = IssuanceWire.digest(Data(code.utf8)); licenseIDHash = String(licenseDigest.prefix(16))
        self.replaces = replaces; self.orderId = orderId; self.phase = phase
    }
}
public struct Invoice: Codable, Equatable {
    public let number: String
    public let orderId: String
    public let partnerId: String
    public let issuedAt: Date
    public let dueAt: Date
    public let seats: Int
    public let termDays: Int
    public let unitMinor: Int64
    public let totalMinor: Int64
    public let currency: String
    public let taxTreatment: String
    public let bankDetails: String
    /// A co-termed seat increase (JS P0b): the whole days left on the live code the total is pro-rated over.
    public let coTermedDays: Int?
    public var paymentReference: String { number }
}
public struct CreditNote: Codable, Equatable {
    public let id: String
    public let invoiceNumber: String
    public let amountMinor: Int64
    public let issuedAt: Date
    public let reason: String
    public init(id: String, invoiceNumber: String, amountMinor: Int64, issuedAt: Date, reason: String) {
        self.id = id; self.invoiceNumber = invoiceNumber; self.amountMinor = amountMinor
        self.issuedAt = issuedAt; self.reason = reason
    }
}
public struct Payment: Codable, Equatable {
    public let id: String
    public let invoiceNumber: String
    public let amountMinor: Int64
    public let receivedAt: Date
    public let bankReference: String
    public init(id: String, invoiceNumber: String, amountMinor: Int64, receivedAt: Date, bankReference: String) {
        self.id = id; self.invoiceNumber = invoiceNumber; self.amountMinor = amountMinor
        self.receivedAt = receivedAt; self.bankReference = bankReference
    }
}
public struct Order: Codable, Equatable {
    public let id: String
    public let partnerId: String
    public let grantVersion: Int
    public let issuedAt: Date
    public let grant: PartnerGrant
    public let request: IssuanceRequest
    public let profileId: String
    public let fullExpiry: Date
    public let renewalOf: String?
    /// The customer this order belongs to (JS P0b). Nil for an order placed without one.
    public let customerId: String?
    /// A co-termed seat increase: the issuance whose seats it adds to and whose expiry it keeps.
    public let increaseOf: String?
    public enum State: String, Codable { case provisional, lapsed, awaitingPayment, paid, active, replaced, credited }
}
/// One atomic journal row per command, including invoice + order + issuance or payment + replacement.
/// No raw code, profile document, activation key or private key is stored.
public enum LedgerEvent: Codable, Equatable {
    case sale(Order, Invoice?, IssuanceRecord?)
    case issuance(IssuanceRecord)
    case payment(Payment, IssuanceRecord?)
    case credit(CreditNote)
    /// JS P0b: a new customer and its first sale in one row, so a customer never exists without its first code.
    case signUp(Customer, Order, Invoice?, IssuanceRecord?)
    case customerChange(CustomerChange)
}
public struct LedgerEntry: Codable, Equatable {
    public let sequence: Int
    public let prevRowHash: String
    public let event: LedgerEvent
    public let rowHash: String
    private struct Body: Encodable { let sequence: Int; let prevRowHash: String; let event: LedgerEvent }
    init(sequence: Int, previous: String, event: LedgerEvent) throws {
        self.sequence = sequence; prevRowHash = previous; self.event = event
        rowHash = try Self.hash(sequence, previous, event)
    }
    static func hash(_ n: Int, _ p: String, _ e: LedgerEvent) throws -> String {
        try IssuanceWire.digest(IssuanceWire.encoder().encode(Body(sequence: n, prevRowHash: p, event: e)))
    }
}
public struct Ledger: Codable, Equatable {
    public private(set) var entries: [LedgerEntry] = []
    public init() {}
    public enum IntegrityError: Error, Equatable { case brokenChain(Int), duplicate, invalidRecord, customerMismatch(Int) }
    public func verify(expectedHead: String? = nil) throws {
        if let expectedHead, expectedHead != (entries.last?.rowHash ?? "genesis") { throw IntegrityError.invalidRecord }
        var previous = "genesis"
        for (index, row) in entries.enumerated() {
            guard row.sequence == index + 1, row.prevRowHash == previous,
                  row.rowHash == (try LedgerEntry.hash(row.sequence, previous, row.event)) else {
                throw IntegrityError.brokenChain(index + 1)
            }
            previous = row.rowHash
        }
        func unique(_ ids: [String]) -> Bool { !ids.contains("") && Set(ids).count == ids.count }
        guard unique(issuances.map(\.issuanceId)), unique(issuances.map(\.licenseDigest)),
              unique(orders.map(\.id)), unique(payments.map(\.id)), unique(credits.map(\.id)),
              invoices.enumerated().allSatisfy({ $0.element.number == Self.invoiceNumber($0.offset + 1) }) else {
            throw IntegrityError.duplicate
        }
        try verifyCustomers()
    }
    /// A customer's name, organisation, profile and address never change, and its orders always name them.
    private func verifyCustomers() throws {
        var known: [String: Customer] = [:]
        func matches(_ o: Order, _ c: Customer) -> Bool {
            o.customerId == c.customerId && o.partnerId == c.partnerId && o.profileId == c.profileId
                && o.request.licensee == c.licensee && o.request.profile == c.profileAddress
        }
        for row in entries {
            switch row.event {
            case .signUp(let c, let o, _, _):
                guard known[c.customerId] == nil, !known.values.contains(where: { $0.profileId == c.profileId || $0.profileAddress == c.profileAddress }),
                      o.increaseOf == nil, o.renewalOf == nil, matches(o, c) else { throw IntegrityError.customerMismatch(row.sequence) }
                known[c.customerId] = c
            case .customerChange(let change):
                let c = change.customer
                guard let old = known[c.customerId], old.licensee == c.licensee, old.organizationID == c.organizationID,
                      old.profileId == c.profileId, old.profileAddress == c.profileAddress else { throw IntegrityError.customerMismatch(row.sequence) }
                known[c.customerId] = c
            case .sale(let o, _, _):
                if let id = o.customerId {
                    guard let c = known[id], matches(o, c) else { throw IntegrityError.customerMismatch(row.sequence) }
                } else if known.values.contains(where: { $0.profileId == o.profileId || $0.profileAddress == o.request.profile }) {
                    throw IntegrityError.customerMismatch(row.sequence)
                }
            default: break
            }
        }
    }
    public mutating func append(_ event: LedgerEvent) throws {
        try verify()
        var candidate = self
        candidate.entries.append(try LedgerEntry(sequence: entries.count + 1, previous: entries.last?.rowHash ?? "genesis", event: event))
        try candidate.verify(); self = candidate
    }
    public static func invoiceNumber(_ n: Int) -> String {
        let digits = String(n)
        return "INV-" + String(repeating: "0", count: max(0, 6 - digits.count)) + digits
    }
    public var issuances: [IssuanceRecord] { entries.compactMap {
        switch $0.event {
        case .issuance(let i): return i
        case .sale(_, _, let i), .payment(_, let i), .signUp(_, _, _, let i): return i
        default: return nil
        }
    } }
    public var orders: [Order] { entries.compactMap {
        switch $0.event { case .sale(let o, _, _), .signUp(_, let o, _, _): return o; default: return nil }
    } }
    public var invoices: [Invoice] { entries.compactMap {
        switch $0.event { case .sale(_, let i, _), .signUp(_, _, let i, _): return i; default: return nil }
    } }
    public var payments: [Payment] { entries.compactMap { if case .payment(let p, _) = $0.event { return p }; return nil } }
    public var credits: [CreditNote] { entries.compactMap { if case .credit(let c) = $0.event { return c }; return nil } }
    public func paymentsMinor(_ invoice: Invoice) -> Int64 { payments.filter { $0.invoiceNumber == invoice.number }.reduce(0) { $0 + $1.amountMinor } }
    public func creditsMinor(_ invoice: Invoice) -> Int64 { credits.filter { $0.invoiceNumber == invoice.number }.reduce(0) { $0 + $1.amountMinor } }
    public func balance(_ invoice: Invoice) -> Int64 { max(0, invoice.totalMinor - paymentsMinor(invoice) - creditsMinor(invoice)) }
    /// Credit notes settle accounting only. They never authorize a paid licence.
    public func isPaid(_ invoice: Invoice) -> Bool { paymentsMinor(invoice) >= invoice.totalMinor }
    public func state(of order: Order, now: Date) -> Order.State {
        if orders.contains(where: { next in
            (next.renewalOf == order.id || issuances.contains { $0.issuanceId == next.increaseOf && $0.orderId == order.id })
                && issuances.contains { $0.orderId == next.id && $0.phase == .full }
        }) { return .replaced }
        if let invoice = invoices.first(where: { $0.orderId == order.id }) {
            if isPaid(invoice) {
                if now >= order.fullExpiry { return .lapsed }
                return issuances.contains { $0.orderId == order.id && $0.phase == .full } ? .active : .paid
            }
            if balance(invoice) == 0 { return .credited }
        }
        if let code = issuances.last(where: { $0.orderId == order.id }) {
            if now >= code.expires { return .lapsed }
            return code.phase == .pilot ? .active : .provisional
        }
        return .awaitingPayment
    }
    /// Half-open period: reissues/replacements never appear as fresh billable seats.
    public func billableIssuances(from: Date, until: Date) -> [IssuanceRecord] {
        issuances.filter { $0.issuedAt >= from && $0.issuedAt < until && $0.replaces == nil && $0.plan != "pilot" }
    }
    public func invoices(from: Date, until: Date) -> [Invoice] { invoices.filter { $0.issuedAt >= from && $0.issuedAt < until } }
    public struct AccountingPeriod: Encodable {
        public let invoices: [Invoice]
        public let creditNotes: [CreditNote]
        public let payments: [Payment]
    }
    public func accounting(from: Date, until: Date) -> AccountingPeriod {
        AccountingPeriod(invoices: invoices(from: from, until: until),
                         creditNotes: credits.filter { $0.issuedAt >= from && $0.issuedAt < until },
                         payments: payments.filter { $0.receivedAt >= from && $0.receivedAt < until })
    }

}
