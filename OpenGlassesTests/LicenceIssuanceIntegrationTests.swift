import Foundation
import CryptoKit
import XCTest
@testable import OpenGlasses

/// The vendor package sources are compiled only into this test bundle. Production verification stays untouched.
@MainActor
final class LicenceIssuanceIntegrationTests: XCTestCase {
    private let licenceKey = Curve25519.Signing.PrivateKey()
    private let profileKey = Curve25519.Signing.PrivateKey()
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var saved: OrgEnrolmentRecord?
    private var storedCode: String?
    private var response = Data()
    private var departures = 0
    private var cleared = 0
    private var settings: [SettingKey: ProfileValue] = [:]
    private var localRecords = ["job": "fixture job", "report": "fixture report", "manual": "fixture manual", "credential": "fixture token"]
    private var personalMemory = "fixture personal memory"
    private var publicKey: String { licenceKey.publicKey.rawRepresentation.base64EncodedString() }
    private var profileKeys: [String: String] { ["fixture-profile": profileKey.publicKey.rawRepresentation.base64EncodedString()] }
    private var grant: PartnerGrant {
        PartnerGrant(partnerId: "fixture", packs: ["hvac_rtu", "electrical", "other"], maxTermDays: 365,
                     maxSeatsPerCode: 10, seatQuota: 100, pilotsAllowed: true, maxPilotDays: 14,
                     validFrom: clock.addingTimeInterval(-86_400), validUntil: clock.addingTimeInterval(400 * 86_400),
                     prices: PriceTable(currency: "XXX", taxTreatment: "fictional", perSeatByTermDays: [365: 100]), maxUnpaidSeats: 10)
    }
    private var request: IssuanceRequest {
        IssuanceRequest(licensee: "Fixture Ltd", seats: 2, termDays: 365, packs: ["hvac_rtu", "electrical"],
                        reference: "fixture-order", profile: "https://fixture.invalid/p/customer")
    }
    private func evidence(_ code: String) -> FieldAssistEntitlementEvidenceSet {
        LiveFieldAssistEntitlementProvider(storePurchases: VerifiedStorePurchaseRecorder(), licensePublicKeyBase64: publicKey,
                                           licenseCode: { code }).evidence()
    }
    func testLibraryPayloadBytesAndPackEntitlementsMatchExistingGeneratorContract() throws {
        let p = try IssuancePolicy.validate(request, grant: grant, ledger: Ledger(), catalog: VerifiedPackCatalog(verifiedKeys: grant.packs), now: clock).get()
        let app = LicenseService.LicensePayload(feature: "field_assist", licensee: p.licensee, issued: p.issued,
                                                expires: p.expires, tier: p.tier, plan: p.plan, seats: p.seats,
                                                reference: p.reference, packs: p.packs, profile: p.profile)
        let bytes = try IssuanceWire.encoder().encode(p)
        XCTAssertEqual(bytes, try LicenseService.encoder.encode(app))
        let legacy = try LicenseService.makeCode(payload: app, privateKeyBase64: licenceKey.rawRepresentation.base64EncodedString())
        let generated = try IssuanceWire.code(p, signer: licenceKey.signature(for:))
        XCTAssertEqual(try LicenseService.decode(code: generated, publicKeyBase64: publicKey), app)
        XCTAssertEqual(try LicenseService.decode(code: legacy, publicKeyBase64: publicKey), app)
        // CryptoKit intentionally randomizes Ed25519 signatures. A fixed valid signature pins exact code assembly.
        let signature = try XCTUnwrap(Data(base64Encoded: String(legacy.split(separator: ".")[1])))
        XCTAssertEqual(try IssuanceWire.code(p, signer: { input in XCTAssertEqual(input, bytes); return signature }), legacy)
        for code in [generated, legacy] {
            let set = evidence(code)
            let decision = FieldAssistEntitlementEvaluator.decide(set, now: clock)
            XCTAssertTrue(decision.isGranted); XCTAssertEqual(decision.tier, .team); XCTAssertEqual(decision.expiresAt, p.expires)
            let packs = FieldAssistEntitlementEvaluator.livePacks(set, now: clock)
            XCTAssertEqual(packs, ["hvac_rtu", "electrical"])
            XCTAssertTrue(VaultPackAccess.isUnlocked(productId: "fixture.hvac", licensePack: "hvac_rtu", purchasedProducts: [], licensedPacks: packs, capabilities: FieldAssistCapability.capabilities(for: set, now: clock)))
            XCTAssertFalse(VaultPackAccess.isUnlocked(productId: "fixture.other", licensePack: "other", purchasedProducts: [], licensedPacks: packs, capabilities: FieldAssistCapability.capabilities(for: set, now: clock)))
            XCTAssertEqual(FieldAssistEntitlementEvaluator.livePacks(set, now: try XCTUnwrap(p.expires)), [])
        }
        XCTAssertEqual(LiveFieldAssistEntitlementProvider.licenseIDHash(for: generated), String(IssuanceWire.digest(Data(generated.utf8)).prefix(16)))
    }
    private func manager() -> OrgProfileManager {
        var s = OrgProfileManager.Seams()
        s.verificationKeys = profileKeys; s.licenceKey = publicKey
        s.now = { self.clock }; s.loadRecord = { self.saved }; s.saveRecord = { self.saved = $0 }
        s.readSetting = { self.settings[$0] }; s.writeSetting = { self.settings[$0] = $1 }
        s.storedLicenceCode = { self.storedCode }
        s.activateLicence = { code in _ = try LicenseService.decode(code: code, publicKeyBase64: self.publicKey); self.storedCode = code }
        s.clearLicence = { self.cleared += 1; self.storedCode = nil }
        s.resolvableVaultIds = { [] }; s.installEnvelope = { _, _ in }; s.clearEnvelope = {}
        s.fetch = { _ in self.response }; s.activeJobId = { nil }; s.withholdLicence = { _ in }
        s.beginDeparture = { _, _, _ in self.departures += 1; self.localRecords.removeAll() }
        s.closeManagedAccess = { _ in XCTFail("the profile lease must not lapse") }
        s.loadModels = { [] }; s.saveModels = { _ in }; s.activeModelId = { "" }; s.setActiveModelId = { _ in }
        return OrgProfileManager(seams: s)
    }
    func testProvisionalLapsePreservesStateAndDailyHostedRenewalRestoresEntitlement() async throws {
        let issued = clock
        var book = try SalesBook()
        let provisional = try XCTUnwrap(book.order(id: "fixture-order", request: request, grant: grant,
            catalog: VerifiedPackCatalog(verifiedKeys: grant.packs), profileId: "customer", bankDetails: "FIXTURE", operatorId: "fixture", now: issued, signer: licenceKey.signature(for:)))
        let document = try provisional.profileDocument(profileId: "customer", keyID: "fixture-profile", signer: profileKey.signature(for:))
        response = Data(document.utf8)
        let m = manager()
        let service = OrgEnrolmentService(manager: m, fetch: { _ in self.response }, isPastOnboarding: { false }, licenceKey: publicKey)
        XCTAssertEqual(service.openLicence(provisional.code), .enrolling(licensee: "Fixture Ltd"))
        for _ in 0..<200 {
            if case .reviewing = service.stage { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        guard case .reviewing(let review) = service.stage else { return XCTFail("profile enrolment failed") }
        try m.apply(review).get()
        XCTAssertEqual(storedCode, provisional.code)
        XCTAssertTrue(FieldAssistEntitlementEvaluator.decide(evidence(try XCTUnwrap(storedCode)), now: clock).satisfies(.team))
        let before = localRecords
        clock = issued.addingTimeInterval(35 * 86_400)
        _ = m.evaluateLease()
        XCTAssertFalse(m.contentLocked, "the profile lease remains live during a billing lapse")
        XCTAssertFalse(FieldAssistEntitlementEvaluator.decide(evidence(try XCTUnwrap(storedCode)), now: clock).isGranted)
        XCTAssertEqual(FieldAssistEntitlementEvaluator.livePacks(evidence(try XCTUnwrap(storedCode)), now: clock), [])
        XCTAssertEqual(localRecords, before); XCTAssertEqual(personalMemory, "fixture personal memory")
        XCTAssertEqual(departures, 0); XCTAssertEqual(cleared, 0); XCTAssertNotNil(saved)
        // The daily fetch continues even though the firm's entitlement has expired.
        clock = issued.addingTimeInterval(40 * 86_400)
        let paid = try XCTUnwrap(book.recordPayment(Payment(id: "fixture-payment", invoiceNumber: "INV-000001", amountMinor: 200,
            receivedAt: clock, bankReference: "fixture transfer"), confirmed: true, operatorId: "fixture-vendor", now: clock, signer: licenceKey.signature(for:)))
        response = Data(try paid.profileDocument(profileId: "customer", keyID: "fixture-profile", signer: profileKey.signature(for:)).utf8)
        await m.renewIfDue()
        XCTAssertEqual(storedCode, paid.code)
        XCTAssertEqual(try LicenseService.decode(code: paid.code, publicKeyBase64: publicKey).expires, issued.addingTimeInterval(365 * 86_400))
        XCTAssertTrue(FieldAssistEntitlementEvaluator.decide(evidence(try XCTUnwrap(storedCode)), now: clock).satisfies(.team))
        XCTAssertEqual(FieldAssistEntitlementEvaluator.livePacks(evidence(try XCTUnwrap(storedCode)), now: clock), ["hvac_rtu", "electrical"])
        XCTAssertEqual(localRecords, before); XCTAssertEqual(departures, 0); XCTAssertEqual(cleared, 0)
    }
    func testOfficeInlineBindingStopsAtTheSameProvisionalExpiryAndPaidTermRestoresIt() throws {
        // Office inline delivery and hosted enrolment are distinct existing routes. Never weaken either verifier.
        let issued = clock
        let admin = Curve25519.Signing.PrivateKey()
        let profile = ConfigProfile(keyId: "fixture-profile", profileId: "customer", organizationName: "Fixture Ltd",
            issued: issued, leaseDays: 365, officeAuthority: .init(organizationID: "fixture-org",
                administratorPublicKey: admin.publicKey.rawRepresentation.base64EncodedString(), transportPolicy: "privateLan"), schemaVersion: 2)
        let doc = try IssuanceWire.profile(profile, signer: profileKey.signature(for:))
        func code(_ days: Int) throws -> String {
            try IssuanceWire.code(IssuedLicensePayload(licensee: "Fixture Ltd", issued: issued,
                expires: issued.addingTimeInterval(Double(days) * 86_400), tier: "team", seats: 2,
                organizationID: "fixture-org", profileID: "customer"), signer: licenceKey.signature(for:))
        }
        let provisional = try code(35), full = try code(365)
        func verify(_ code: String) throws {
            _ = try OfficeInlineEntitlement.verify(profileDocument: doc, licenceCode: code, profileKeys: profileKeys, licenceKey: publicKey, now: clock)
        }
        XCTAssertNoThrow(try verify(provisional))
        clock = issued.addingTimeInterval(35 * 86_400)
        XCTAssertThrowsError(try verify(provisional)) {
            XCTAssertEqual($0 as? OfficeInlineEntitlement.Refusal, .notCurrentlyValid)
            XCTAssertEqual(OfficeFieldConnectionPolicy.afterFailure($0), .stop(.managementLapsed))
        }
        XCTAssertNoThrow(try verify(full))
    }
    /// JS P0b's key-for-life rule: the key opens the first code, long expired, and enrolment ends on the profile's current code.
    func testOneActivationKeyOpensAnExpiredFirstCodeAndEnrolsOnTheProfilesCurrentCode() async throws {
        let start = clock
        let preset = ProfilePreset(id: "fixture-preset", version: 1, leaseDays: 365,
                                   settings: ["privacyFilterEnabled": .init(value: .bool(true), disposition: "ceiling")],
                                   choices: .init(settings: ["refrigerationUnits": .init(disposition: "default", values: [.string("kPa,C,kg")])]))
        let catalog = VerifiedPackCatalog(verifiedKeys: grant.packs)
        var book = try SalesBook()
        let signUp = try book.signUp(NewCustomer(customerId: "fixture-customer", licensee: "Fixture Ltd", organizationID: "fixture-org",
                                                 profileId: "customer", selection: .init(settings: ["refrigerationUnits": .string("kPa,C,kg")])),
                                     orderId: "fixture-order", order: .init(seats: 2, termDays: 365, packs: ["hvac_rtu"], reference: "fixture"),
                                     preset: preset, profileBase: "https://fixture.invalid", grant: grant, catalog: catalog,
                                     bankDetails: "FIXTURE", operatorId: "fixture", now: start, signer: licenceKey.signature(for:))
        let sealed = signUp.sealedFile, file = signUp.customer.activationFile
        // Paid, then renewed and paid again: the profile now carries a code issued long after the sealed one.
        clock = start.addingTimeInterval(10 * 86_400)
        _ = try book.recordPayment(Payment(id: "fixture-payment", invoiceNumber: "INV-000001", amountMinor: 200, receivedAt: clock, bankReference: "fixture"),
                                   confirmed: true, operatorId: "fixture-vendor", now: clock, signer: licenceKey.signature(for:))
        clock = start.addingTimeInterval(300 * 86_400)
        _ = try book.order(id: "fixture-renewal", customerId: "fixture-customer", order: .init(seats: 2, termDays: 365, packs: ["hvac_rtu"], reference: "renewal"),
                           renewalOf: "fixture-order", grant: grant, catalog: catalog, bankDetails: "FIXTURE", operatorId: "fixture", now: clock, signer: licenceKey.signature(for:))
        let renewed = try XCTUnwrap(book.recordPayment(Payment(id: "fixture-renewal-payment", invoiceNumber: "INV-000002", amountMinor: 200, receivedAt: clock, bankReference: "fixture"),
                                                       confirmed: true, operatorId: "fixture-vendor", now: clock, signer: licenceKey.signature(for:)))
        clock = start.addingTimeInterval(400 * 86_400)
        XCTAssertFalse(FieldAssistEntitlementEvaluator.decide(evidence(signUp.code.code), now: clock).isGranted, "the sealed first code has long expired")
        response = Data(try book.profileDocument(customerId: "fixture-customer", code: renewed.code, preset: preset, grant: grant,
                                                 keyID: "fixture-profile", issued: clock, signer: profileKey.signature(for:)).utf8)
        let resolver = ActivationKeyResolver(directory: try XCTUnwrap(URL(string: "https://fixture.invalid/a")), fetch: { url in
            (url.lastPathComponent == file ? 200 : 404, Data(sealed.utf8))
        })
        let m = manager()
        let service = OrgEnrolmentService(manager: m, fetch: { _ in self.response }, isPastOnboarding: { false }, licenceKey: publicKey,
                                          profileKeys: profileKeys, now: { self.clock }, activationResolver: resolver)
        guard case .licence(let entered) = await service.resolveEntry(signUp.activationKey) else { return XCTFail("the key did not resolve") }
        XCTAssertEqual(entered, signUp.code.code)
        XCTAssertEqual(service.openLicence(entered), .enrolling(licensee: "Fixture Ltd"))
        for _ in 0..<200 {
            if case .reviewing = service.stage { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        guard case .reviewing(let review) = service.stage else { return XCTFail("profile enrolment failed: \(service.stage)") }
        XCTAssertNil(review.licenceToActivate, "the profile's later-issued code wins over the entered one")
        XCTAssertTrue(review.result.drops.isEmpty, "\(review.result.drops)")
        try m.apply(review).get()
        XCTAssertEqual(storedCode, renewed.code)
        XCTAssertTrue(FieldAssistEntitlementEvaluator.decide(evidence(try XCTUnwrap(storedCode)), now: clock).satisfies(.team))
        // Nothing was re-sealed: the key's file is the one written at sign-up.
        XCTAssertEqual(book.ledger.customers["fixture-customer"]?.activationFile, file)
        XCTAssertTrue(book.ledger.retiredActivationFiles(for: "fixture-customer").isEmpty)
    }
    func testPresetProfileWithAnAdministratorVerifierVerifiesAndAppliesWithoutDrops() throws {
        XCTAssertEqual(ProfileContract.passcodeIterationRange, AdminSecrets.iterationRange)
        let model = ProfileContract.AIModel(provider: "anthropic", model: "claude-sonnet-5-5")
        let preset = ProfilePreset(id: "fixture-field-assist", version: 1, edition: "fieldAssist", leaseDays: 365,
                                   lockdown: .init(open: ["voice"]),
                                   settings: ["privacyFilterEnabled": .init(value: .bool(true), disposition: "ceiling")],
                                   choices: .init(aiModels: [model]))
        var book = try SalesBook()
        let signUp = try book.signUp(NewCustomer(customerId: "fixture-customer", licensee: "Fixture Ltd", organizationID: "fixture-org",
                                                 profileId: "customer", selection: .init(aiModel: model)),
                                     orderId: "fixture-order", order: .init(seats: 2, termDays: 365, packs: ["hvac_rtu"], reference: "fixture"),
                                     preset: preset, profileBase: "https://fixture.invalid", grant: grant,
                                     catalog: VerifiedPackCatalog(verifiedKeys: grant.packs), bankDetails: "FIXTURE", operatorId: "fixture",
                                     now: clock, signer: licenceKey.signature(for:))
        let salt = Data((0..<16).map { UInt8($0 * 7) })
        let hash = try XCTUnwrap(AdminSecrets.pbkdf2("fixture passcode", salt: salt, iterations: 210_000))
        try book.setAdminPasscode(customerId: "fixture-customer", verifier: .init(salt: salt.base64EncodedString(), iterations: 210_000, hash: hash.base64EncodedString()),
                                  preset: preset, grant: grant, operatorId: "fixture-setup-link", now: clock)
        let document = try book.profileDocument(customerId: "fixture-customer", code: signUp.code.code, preset: preset, grant: grant,
                                                keyID: "fixture-profile", issued: clock, signer: profileKey.signature(for:))
        guard case .profile(let profile) = try ProfileVerification.verify(document, keys: profileKeys) else { return XCTFail("not a profile") }
        XCTAssertNil(ProfileVerification.enrolmentRefusal(for: profile, now: clock, licenceKey: publicKey))
        XCTAssertEqual(profile.licenceCode, signUp.code.code); XCTAssertEqual(profile.organizationName, "Fixture Ltd")
        let result = ProfileApplier.apply(profile: profile, resolvableVaultIds: [])
        XCTAssertTrue(result.drops.isEmpty, "\(result.drops)")
        guard case .success(let passcode) = AdminSecrets.resolve(try XCTUnwrap(profile.adminPasscode)) else { return XCTFail("verifier refused") }
        XCTAssertEqual(AdminSecrets.pbkdf2("fixture passcode", salt: passcode.salt, iterations: passcode.iterations), passcode.hash)
    }
    func testSealedActivationFileOpensWithTheExistingAppContract() throws {
        let payload = try IssuancePolicy.validate(request, grant: grant, ledger: Ledger(), catalog: VerifiedPackCatalog(verifiedKeys: grant.packs), now: clock).get()
        let code = try IssuanceWire.code(payload, signer: licenceKey.signature(for:))
        let canonical = ActivationKeyMint.generate()
        guard case .key(let key) = ActivationKey.read(ActivationKeyMint.display(canonical)) else { return XCTFail("invalid minted key") }
        XCTAssertEqual(key.fileName, ActivationKeyMint.fileName(canonical))
        XCTAssertEqual(key.open(Data(try ActivationKeyMint.seal(code, canonical: canonical).utf8)), code)
    }
}
