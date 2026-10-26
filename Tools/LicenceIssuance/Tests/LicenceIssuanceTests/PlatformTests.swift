import XCTest
@testable import LicenceIssuance

/// The service writes the ledger and signs on Linux; the manual tools read and verify it on macOS. Both
/// must encode the same bytes, so these digests are pinned and the suite runs on both platforms.
final class PlatformTests: XCTestCase {
    let issued = Date(timeIntervalSince1970: 1_800_000_000)
    /// A fixed signature keeps codes deterministic; nothing here verifies it.
    let signer: ByteSigner = { _ in Data(repeating: 0xA5, count: 64) }

    func digest<T: Encodable>(_ value: T, profile: Bool = false) throws -> String {
        IssuanceWire.digest(try IssuanceWire.encoder(profile: profile).encode(value))
    }

    func testLicencePayloadProfileAndLedgerBytesMatchAcrossPlatforms() throws {
        let payload = IssuedLicensePayload(licensee: "Fixture Ltd / Ōtautahi", issued: issued, expires: issued.addingTimeInterval(365 * 86_400),
                                           tier: "team", plan: "team", seats: 2, reference: "o1", packs: ["electrical", "hvac"],
                                           profile: "https://fixture.invalid/p/customer")
        XCTAssertEqual(try digest(payload), "6e8879cc39b32bb83a72502c82595a40231b96107c4680d1106dbcaa37807046")
        let code = try IssuanceWire.code(payload, signer: signer)
        let input = ProfileContract.Input(profileId: "customer", organizationName: "Fixture Ltd / Ōtautahi", leaseDays: 365, licenceCode: code,
                                          vaultPack: .init(packId: "fixture.hvac", documentsSource: "https://fixture.invalid/docs"),
                                          settings: ["privacyFilterEnabled": .init(value: .bool(true), disposition: "ceiling"),
                                                     "fieldAssistDefaultTrades": .init(value: .strings(["electrical", "refrigeration_hvac"]), disposition: "default")],
                                          aiModel: .init(provider: "openrouter", model: "fixture/model", baseURL: "https://fixture.invalid/v1"),
                                          edition: "fieldAssist", lockdown: .init(open: ["voice"], closedTools: ["send_via"]))
        XCTAssertEqual(try digest(ProfileContract.document(input, keyId: "fixture", issued: issued, adminPasscode: nil), profile: true), "af4a8bee8e8ec1b96712a81b7502398c23864765278177f11f544c3860e305da")

        let grant = PartnerGrant(partnerId: "fixture", packs: ["hvac", "electrical"], maxTermDays: 365, maxSeatsPerCode: 10, seatQuota: 30,
                                 pilotsAllowed: false, maxPilotDays: 14, validFrom: issued.addingTimeInterval(-86_400),
                                 validUntil: issued.addingTimeInterval(400 * 86_400),
                                 prices: PriceTable(currency: "XXX", taxTreatment: "fixture", perSeatByTermDays: [365: 100, 730: 180]), maxUnpaidSeats: 10)
        let preset = ProfilePreset(id: "fixture", version: 1, leaseDays: 365,
                                   choices: .init(settings: ["refrigerationUnits": .init(disposition: "default", values: [.string("kPa,C,kg")])]))
        var book = try SalesBook()
        _ = try book.signUp(NewCustomer(customerId: "c1", licensee: "Fixture Ltd", organizationID: "fixture-org", profileId: "customer",
                                        selection: .init(settings: ["refrigerationUnits": .string("kPa,C,kg")])),
                            orderId: "o1", order: .init(seats: 2, termDays: 365, packs: ["hvac"], reference: "ref"), preset: preset,
                            profileBase: "https://fixture.invalid", grant: grant, catalog: VerifiedPackCatalog(verifiedKeys: ["hvac", "electrical"]),
                            bankDetails: "FIXTURE", operatorId: "fixture", now: issued, signer: signer)
        _ = try book.recordPayment(Payment(id: "p1", invoiceNumber: "INV-000001", amountMinor: 200, receivedAt: issued, bankReference: "ref"),
                                   confirmed: true, operatorId: "fixture", now: issued, signer: signer)
        // The sign-up row names a random activation file, so pin its order (grant, price table and all) and the payment's event.
        XCTAssertEqual(try digest(book.ledger.orders[0]), "6a0827e916257921069e662a5f74a50068fff382eb153338246babcd5221e796")
        XCTAssertEqual(try digest(book.ledger.entries[1].event), "3c20e91b8901090a09584db3c0d269cf5ebef2736486eadece7a242c3b0b9dab")
        // And a journal written on one platform verifies on the other.
        let reread = try IssuanceWire.decoder().decode(Ledger.self, from: IssuanceWire.encoder().encode(book.ledger))
        XCTAssertNoThrow(try reread.verify(expectedHead: book.ledger.entries.last?.rowHash))
    }
}
