import XCTest
@testable import OpenGlasses

/// Plan DL — the stored FHIR credential goes only to the address it was saved with.
final class FHIRCredentialBindingPolicyTests: XCTestCase {

    private let saved = "https://fhir.example.com/r4"

    // MARK: - Same endpoint

    /// The request code (`FHIRServerConfiguration.endpoint(for:)`) trims whitespace and joins
    /// with one slash, so neither is a different server.
    func testTrailingSlashAndWhitespaceAreTheSameEndpoint() {
        XCTAssertTrue(FHIRCredentialBinding.isSameEndpoint(saved, saved))
        XCTAssertTrue(FHIRCredentialBinding.isSameEndpoint(saved, "https://fhir.example.com/r4/"))
        XCTAssertTrue(FHIRCredentialBinding.isSameEndpoint("https://fhir.example.com/r4/", saved))
        XCTAssertTrue(FHIRCredentialBinding.isSameEndpoint(saved, "  https://fhir.example.com/r4 \n"))
    }

    /// Nothing else is folded: a variant is a different address until it is saved, which costs a
    /// re-entered credential at worst and never sends it somewhere it wasn't saved for.
    func testHostCasePortSchemeAndPathVariantsAreDifferentEndpoints() {
        for variant in ["https://FHIR.example.com/r4",
                        "https://fhir.EXAMPLE.com/r4/",
                        "https://fhir.example.com:443/r4",
                        "https://fhir.example.com:8443/r4",
                        "http://fhir.example.com/r4",
                        "https://fhir.example.com/r5",
                        "https://fhir.example.com",
                        "https://fhir.example.com.attacker.test/r4",
                        "https://attacker.test/r4"] {
            XCTAssertFalse(FHIRCredentialBinding.isSameEndpoint(saved, variant), variant)
        }
    }

    func testUnusableAddressesAreNeverTheSameEndpoint() {
        XCTAssertFalse(FHIRCredentialBinding.isSameEndpoint("", ""))
        XCTAssertFalse(FHIRCredentialBinding.isSameEndpoint("   ", saved))
    }

    // MARK: - Connection test

    func testStoredCredentialGoesOnlyToTheSavedAddress() {
        XCTAssertEqual(credential(tested: saved), .stored)
        XCTAssertEqual(credential(tested: "https://fhir.example.com/r4/"), .stored)
        XCTAssertEqual(credential(tested: "https://FHIR.example.com/r4"), .withheld)
        XCTAssertEqual(credential(tested: "https://fhir.example.com:443/r4"), .withheld)
        XCTAssertEqual(credential(tested: "https://attacker.test/r4"), .withheld)
    }

    func testACredentialEnteredForTheTestIsTheOneSent() {
        for tested in [saved, "https://attacker.test/r4"] {
            for stored in [true, false] {
                XCTAssertEqual(credential(tested: tested, stored: stored, entered: true), .entered)
            }
        }
    }

    func testNothingStoredOrEnteredSendsNothing() {
        XCTAssertEqual(credential(tested: saved, stored: false), .none)
        XCTAssertEqual(credential(tested: "https://attacker.test/r4", stored: false), .none)
    }

    func testOnlyStoredAndEnteredCarryAHeader() {
        XCTAssertTrue(FHIRConnectionTestPolicy.Credential.stored.isSent)
        XCTAssertTrue(FHIRConnectionTestPolicy.Credential.entered.isSent)
        XCTAssertFalse(FHIRConnectionTestPolicy.Credential.withheld.isSent)
        XCTAssertFalse(FHIRConnectionTestPolicy.Credential.none.isSent)
    }

    // MARK: - Saving a new address

    func testANewAddressWithAStoredCredentialNeedsTheCredentialEnteredWithIt() {
        XCTAssertFalse(maySave("https://attacker.test/r4", stored: true, entered: false))
        XCTAssertFalse(maySave("https://FHIR.example.com/r4", stored: true, entered: false))
        XCTAssertFalse(maySave("", stored: true, entered: false), "blanking the address re-binds too")
        XCTAssertTrue(maySave("https://attacker.test/r4", stored: true, entered: true))
    }

    func testTheSameAddressOrNoStoredCredentialSavesFreely() {
        XCTAssertTrue(maySave(saved, stored: true, entered: false))
        XCTAssertTrue(maySave("https://fhir.example.com/r4/", stored: true, entered: false))
        XCTAssertTrue(maySave("https://elsewhere.example.com/r4", stored: false, entered: false))
        XCTAssertTrue(FHIRCredentialBinding.maySaveEndpoint(savedBaseURL: "", newBaseURL: " ",
                                                            credentialStored: true, credentialEntered: false))
    }

    // MARK: - Helpers

    private func credential(tested: String, stored: Bool = true,
                            entered: Bool = false) -> FHIRConnectionTestPolicy.Credential {
        FHIRConnectionTestPolicy.credential(savedBaseURL: saved, testedBaseURL: tested,
                                            credentialStored: stored, credentialEntered: entered)
    }

    private func maySave(_ new: String, stored: Bool, entered: Bool) -> Bool {
        FHIRCredentialBinding.maySaveEndpoint(savedBaseURL: saved, newBaseURL: new,
                                              credentialStored: stored, credentialEntered: entered)
    }
}

/// Records every request it answers, so a test can see exactly which headers left the app.
/// Installed on an injected session only, never registered globally.
final class FHIRRecordingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [URLRequest] = []
    nonisolated(unsafe) private static var status = 200

    static func reset(status: Int = 200) {
        lock.lock(); recorded = []; Self.status = status; lock.unlock()
    }

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FHIRRecordingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.recorded.append(request)
        let status = Self.status
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/fhir+json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"resourceType\":\"CapabilityStatement\"}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Plan DL — end to end through `MedicalExportService`, with the server answered locally.
@MainActor
final class FHIRConnectionTestBindingTests: XCTestCase {
    private static let savedURL = "https://fhir.example.com/r4"
    private static let storedToken = "stored-token-7731"

    private var root: URL!
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var secrets: InMemoryFHIRSecretStore!
    private var configStore: FHIRConfigurationStore!
    private var service: MedicalExportService!

    override func setUp() {
        super.setUp()
        FHIRRecordingURLProtocol.reset()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FHIRConnectionTestBindingTests_\(UUID().uuidString)")
        suiteName = "FHIRConnectionTestBindingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        secrets = InMemoryFHIRSecretStore()
        configStore = FHIRConfigurationStore(defaults: defaults, credentials: secrets, contexts: secrets)
        service = MedicalExportService(
            configurationStore: configStore,
            leases: MedicalExportLeaseCoordinator(store: MedicalExportFileStore(root: root,
                                                                               protector: RecordingProtector())),
            transport: FHIRRecordingURLProtocol.session()
        )
        var config = configStore.configuration
        config.baseURL = Self.savedURL
        config.authMode = .bearerToken
        configStore.save(config)
        try? configStore.storeCredential(FHIRCredential(bearerToken: Self.storedToken))
    }

    override func tearDown() {
        FHIRRecordingURLProtocol.reset()
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Connection test

    /// Positive control: the saved address does get the stored credential, so the absence
    /// assertions below are not passing because the stub cannot see the header.
    func testTheSavedAddressGetsTheStoredCredential() async throws {
        for address in [Self.savedURL, Self.savedURL + "/"] {
            FHIRRecordingURLProtocol.reset()
            _ = await service.testConnection(baseURL: address, enteredCredential: "")
            let request = try XCTUnwrap(FHIRRecordingURLProtocol.requests.last, address)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"),
                           "Bearer \(Self.storedToken)", address)
            XCTAssertEqual(request.url?.absoluteString, "https://fhir.example.com/r4/metadata")
        }
    }

    func testAnUnsavedAddressNeverSeesAnAuthorizationHeader() async throws {
        for address in ["https://attacker.test/r4",
                        "https://FHIR.example.com/r4",
                        "https://fhir.example.com:443/r4",
                        "https://fhir.example.com/r4/../other"] {
            FHIRRecordingURLProtocol.reset()
            let message = await service.testConnection(baseURL: address, enteredCredential: "")
            let request = try XCTUnwrap(FHIRRecordingURLProtocol.requests.last, address)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), address)
            for (_, value) in request.allHTTPHeaderFields ?? [:] {
                XCTAssertFalse(value.contains(Self.storedToken), address)
            }
            XCTAssertTrue(message.contains("wasn't sent"), message)
        }
    }

    /// A 401 from an address the credential was withheld from is not "the server refused your
    /// credential" — it never saw one.
    func testAWithheldTestThatIsAskedForACredentialSaysSo() async {
        FHIRRecordingURLProtocol.reset(status: 401)
        let message = await service.testConnection(baseURL: "https://attacker.test/r4", enteredCredential: "")
        XCTAssertNotEqual(message, MedicalExportFailure.credentialRejected.message)
        XCTAssertTrue(message.contains("asks for a credential"), message)
        XCTAssertNil(FHIRRecordingURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization"))
    }

    /// A credential typed for the test goes with it — and it is the typed one, never the stored one.
    func testAnEnteredCredentialIsSentInsteadOfTheStoredOne() async throws {
        _ = await service.testConnection(baseURL: "https://other.example.com/r4", enteredCredential: " typed-9 ")
        let request = try XCTUnwrap(FHIRRecordingURLProtocol.requests.last)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer typed-9")
    }

    func testNothingStoredSendsNoHeader() async throws {
        configStore.clearCredential()
        _ = await service.testConnection(baseURL: Self.savedURL, enteredCredential: "")
        let request = try XCTUnwrap(FHIRRecordingURLProtocol.requests.last)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: - Saving

    func testSavingANewAddressWithoutItsCredentialIsRefusedAndChangesNothing() {
        var edited = configStore.configuration
        edited.baseURL = "https://attacker.test/r4"

        let outcome = service.saveServerSettings(edited, enteredCredential: "",
                                                 privateContext: FHIRPrivateContext(patientID: "p-2"))

        XCTAssertEqual(outcome, .credentialBoundToSavedAddress)
        XCTAssertEqual(configStore.configuration.baseURL, Self.savedURL)
        XCTAssertEqual(try configStore.loadCredential().bearerToken, Self.storedToken)
        XCTAssertNil(try configStore.loadPrivateContext().patientID, "a refused save saves nothing")
        XCTAssertTrue(outcome.message.contains("nothing was saved"), outcome.message)
    }

    func testSavingANewAddressWithItsCredentialRebindsIt() {
        var edited = configStore.configuration
        edited.baseURL = "https://new.example.com/r4"

        let outcome = service.saveServerSettings(edited, enteredCredential: "new-token",
                                                 privateContext: FHIRPrivateContext())

        XCTAssertEqual(outcome, .saved(storedCredential: true))
        XCTAssertEqual(configStore.configuration.baseURL, "https://new.example.com/r4")
        XCTAssertEqual(try configStore.loadCredential().bearerToken, "new-token")
    }

    func testSavingTheSameAddressKeepsTheCredential() {
        var edited = configStore.configuration
        edited.baseURL = Self.savedURL + "/"

        let outcome = service.saveServerSettings(edited, enteredCredential: "",
                                                 privateContext: FHIRPrivateContext(patientID: "p-3"))

        XCTAssertEqual(outcome, .saved(storedCredential: false))
        XCTAssertEqual(try configStore.loadCredential().bearerToken, Self.storedToken)
        XCTAssertEqual(try configStore.loadPrivateContext().patientID, "p-3")
    }

    /// After a refused save the stored credential still only reaches the saved address: the
    /// typed one, which stays in the field, gets a test without it.
    func testARefusedSaveLeavesTheTypedAddressUncredentialed() async throws {
        var edited = configStore.configuration
        edited.baseURL = "https://attacker.test/r4"
        _ = service.saveServerSettings(edited, enteredCredential: "", privateContext: FHIRPrivateContext())

        _ = await service.testConnection(baseURL: edited.baseURL, enteredCredential: "")
        let request = try XCTUnwrap(FHIRRecordingURLProtocol.requests.last)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }
}
