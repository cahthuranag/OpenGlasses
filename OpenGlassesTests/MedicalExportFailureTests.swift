import XCTest
@testable import OpenGlasses

/// Answers every request locally with whatever the current test scripted: a status and a body, or
/// an error. Installed on an injected session only, never registered globally.
final class FHIRStubURLProtocol: URLProtocol {
    enum Reply {
        case response(status: Int, body: Data)
        case failure(Error)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var scripted: Reply = .response(status: 200, body: Data())

    static func script(_ reply: Reply) {
        lock.lock(); scripted = reply; lock.unlock()
    }

    private static var reply: Reply {
        lock.lock(); defer { lock.unlock() }
        return scripted
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FHIRStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        switch Self.reply {
        case .response(let status, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/fhir+json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Plan DL P3.1 — a FHIR or medical-export failure reaches the wearer as a fixed sentence chosen by
/// status class or error type, never as anything the server sent or an error's own description.
final class MedicalExportFailureClassificationTests: XCTestCase {

    func testStatusClassesMapToFixedFailures() {
        XCTAssertEqual(MedicalExportFailure(httpStatus: 401), .credentialRejected)
        XCTAssertEqual(MedicalExportFailure(httpStatus: 403), .credentialRejected)
        XCTAssertEqual(MedicalExportFailure(httpStatus: 400), .documentRejected)
        XCTAssertEqual(MedicalExportFailure(httpStatus: 404), .documentRejected)
        XCTAssertEqual(MedicalExportFailure(httpStatus: 422), .documentRejected)
        XCTAssertEqual(MedicalExportFailure(httpStatus: 429), .serverUnavailable)
        XCTAssertEqual(MedicalExportFailure(httpStatus: 500), .serverUnavailable)
        XCTAssertEqual(MedicalExportFailure(httpStatus: 503), .serverUnavailable)
        XCTAssertEqual(MedicalExportFailure(httpStatus: 302), .unexpectedResponse)
        XCTAssertEqual(MedicalExportFailure(httpStatus: 0), .unexpectedResponse)
    }

    /// A submission that timed out may have landed; a connection test that timed out wrote nothing.
    func testTimeoutIsOutcomeUnknownOnlyForASubmission() {
        for code in [URLError.Code.timedOut, .networkConnectionLost] {
            XCTAssertEqual(MedicalExportFailure(URLError(code), operation: .submission), .outcomeUnknown)
            XCTAssertEqual(MedicalExportFailure(URLError(code), operation: .connectionTest), .unreachable)
        }
    }

    func testTransportErrorsMapByCode() {
        XCTAssertEqual(MedicalExportFailure(URLError(.notConnectedToInternet)), .unreachable)
        XCTAssertEqual(MedicalExportFailure(URLError(.cannotFindHost)), .unreachable)
        XCTAssertEqual(MedicalExportFailure(URLError(.serverCertificateUntrusted)), .unreachable)
        XCTAssertEqual(MedicalExportFailure(URLError(.badURL)), .invalidServerURL)
        XCTAssertEqual(MedicalExportFailure(URLError(.userAuthenticationRequired)), .credentialRejected)
        XCTAssertEqual(MedicalExportFailure(URLError(.badServerResponse)), .unexpectedResponse)
    }

    func testAppSideErrorsKeepTheirOwnSentence() {
        let errors: [MedicalExportError] = [.serverNotConfigured, .migrationPending, .credentialLocked,
                                            .credentialMissing, .protectedStorageUnavailable,
                                            .exportSetupFailed, .exportWriteFailed]
        for error in errors {
            let failure = MedicalExportFailure(error as Error)
            XCTAssertEqual(failure, MedicalExportFailure(error))
            XCTAssertEqual(error.errorDescription, failure.message,
                           "a thrown error and its classification must word the condition the same way")
        }
    }

    /// An error of a type the classifier does not know is never quoted, however it describes itself.
    func testUnknownErrorDescriptionIsNeverQuoted() {
        let error = NSError(domain: "FHIRServer", code: 422, userInfo: [
            NSLocalizedDescriptionKey: PHI.body,
            NSLocalizedFailureReasonErrorKey: PHI.name,
        ])
        let failure = MedicalExportFailure(error)
        XCTAssertEqual(failure, .failed)
        PHI.assertAbsent(from: failure.message)
    }

    /// The URL error's own description names the host and failing URL; neither surfaces.
    func testURLErrorUserInfoIsNeverQuoted() {
        let error = URLError(.timedOut, userInfo: [
            NSURLErrorFailingURLErrorKey: URL(string: "https://fhir.example.com/r4/Patient/\(PHI.mrn)")!,
            NSLocalizedDescriptionKey: PHI.body,
        ])
        PHI.assertAbsent(from: MedicalExportFailure(error).message)
    }

    func testEveryFailureHasItsOwnNonEmptySentence() {
        let messages = MedicalExportFailure.allCases.map(\.message)
        XCTAssertFalse(messages.contains(where: \.isEmpty))
        XCTAssertEqual(Set(messages).count, messages.count, "two failures share one sentence")
    }

    /// The log line carries the operation and a status or error category — nothing the server said.
    func testLogLinesCarryStatusAndCategoryOnly() {
        let statusLine = PrivacyEventEncoder.encode(MedicalExportFailure.log(.submission, status: 422))
        XCTAssertTrue(statusLine.contains("422"), statusLine)
        XCTAssertTrue(statusLine.contains("submission"), statusLine)

        let error = NSError(domain: "FHIRServer", code: 7, userInfo: [NSLocalizedDescriptionKey: PHI.body])
        let errorLine = PrivacyEventEncoder.encode(MedicalExportFailure.log(.connectionTest, error: error))
        XCTAssertTrue(errorLine.contains("connectionTest"), errorLine)
        PHI.assertAbsent(from: errorLine)
    }
}

/// End to end through `exportToFHIR`, with the server answered locally: whatever the reply body
/// says, the result message is the fixed sentence for the status class.
@MainActor
final class MedicalExportFailureServiceTests: XCTestCase {
    private var root: URL!
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var secrets: InMemoryFHIRSecretStore!
    private var configStore: FHIRConfigurationStore!
    private var service: MedicalExportService!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MedicalExportFailureTests_\(UUID().uuidString)")
        suiteName = "MedicalExportFailureTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        secrets = InMemoryFHIRSecretStore()
        configStore = FHIRConfigurationStore(defaults: defaults, credentials: secrets, contexts: secrets)
        service = MedicalExportService(
            configurationStore: configStore,
            leases: MedicalExportLeaseCoordinator(store: MedicalExportFileStore(root: root,
                                                                               protector: RecordingProtector())),
            transport: FHIRStubURLProtocol.session()
        )
        var config = configStore.configuration
        config.baseURL = "https://fhir.example.com/r4"
        config.authMode = .bearerToken
        configStore.save(config)
        try? configStore.storeCredential(FHIRCredential(bearerToken: "test-token"))
    }

    override func tearDown() {
        FHIRStubURLProtocol.script(.response(status: 200, body: Data()))
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func submit() async -> MedicalExportService.ExportResult {
        await service.exportToFHIR(transcript: "clinical", duration: "01:00", date: Date(),
                                   origin: .automaticTranscription)
    }

    func testRejectionBodyWithPatientTextNeverReachesTheMessage() async {
        for (status, expected) in [(400, MedicalExportFailure.documentRejected),
                                   (401, .credentialRejected),
                                   (403, .credentialRejected),
                                   (422, .documentRejected),
                                   (500, .serverUnavailable)] {
            FHIRStubURLProtocol.script(.response(status: status, body: PHI.operationOutcome))
            let result = await submit()
            XCTAssertFalse(result.success, "HTTP \(status)")
            XCTAssertEqual(result.message, expected.message, "HTTP \(status)")
            PHI.assertAbsent(from: result.message)
        }
    }

    func testTimeoutAfterSendSaysTheOutcomeIsUnknown() async {
        FHIRStubURLProtocol.script(.failure(URLError(.timedOut)))
        let result = await submit()
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, MedicalExportFailure.outcomeUnknown.message)
    }

    func testTransportErrorDescriptionNeverReachesTheMessage() async {
        FHIRStubURLProtocol.script(.failure(NSError(domain: NSURLErrorDomain,
                                                    code: URLError.cannotConnectToHost.rawValue,
                                                    userInfo: [NSLocalizedDescriptionKey: PHI.body])))
        let result = await submit()
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, MedicalExportFailure.unreachable.message)
        PHI.assertAbsent(from: result.message)
    }

    /// The device log gets the status, and nothing of the body that came with it.
    func testRejectionIsLoggedWithoutTheBody() async {
        let sink = LineSink()
        let tap = PrivacyLog.addTap { _, line in sink.record(line) }
        defer { PrivacyLog.removeTap(tap) }

        FHIRStubURLProtocol.script(.response(status: 422, body: PHI.operationOutcome))
        _ = await submit()

        let lines = sink.lines.filter { $0.contains("fhir") }
        XCTAssertTrue(lines.contains { $0.contains("exportFailed") && $0.contains("422") }, "\(lines)")
        for line in lines { PHI.assertAbsent(from: line) }
    }

    func testSuccessIsStillReported() async {
        FHIRStubURLProtocol.script(.response(status: 201, body: PHI.operationOutcome))
        let result = await submit()
        XCTAssertTrue(result.success)
        PHI.assertAbsent(from: result.message)
    }
}

/// Plan DL P3.2 — Clear needs the device owner, and fails closed.
@MainActor
final class FHIRCredentialClearGateTests: XCTestCase {
    private var root: URL!
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var secrets: InMemoryFHIRSecretStore!
    private var configStore: FHIRConfigurationStore!
    private var service: MedicalExportService!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FHIRCredentialClearGateTests_\(UUID().uuidString)")
        suiteName = "FHIRCredentialClearGateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        secrets = InMemoryFHIRSecretStore()
        configStore = FHIRConfigurationStore(defaults: defaults, credentials: secrets, contexts: secrets)
        service = MedicalExportService(
            configurationStore: configStore,
            leases: MedicalExportLeaseCoordinator(store: MedicalExportFileStore(root: root,
                                                                               protector: RecordingProtector()))
        )
        try? configStore.storeCredential(FHIRCredential(bearerToken: "test-token"))
        try? configStore.storePrivateContext(FHIRPrivateContext(patientID: "patient-1", practitionerID: "dr-1"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makePendingExport() throws -> MedicalExportLease {
        try service.createExportLease(transcript: "clinical", duration: "01:00", date: Date(),
                                      format: .plainText, origin: .automaticTranscription)
    }

    func testRefusedAuthorizationClearsNothing() throws {
        for refusal in [OwnerAuthorization.denied, .unavailable] {
            let lease = try makePendingExport()

            let outcome = service.clearCredentialAndPendingExports(authorization: refusal)

            XCTAssertEqual(outcome, .kept(refusal))
            XCTAssertFalse(outcome.didClear)
            XCTAssertTrue(configStore.hasStoredCredential(), "\(refusal) cleared the credential")
            XCTAssertTrue(FileManager.default.fileExists(atPath: lease.fileURL.path),
                          "\(refusal) deleted a pending export")
            XCTAssertTrue(secrets.deletedCredentialIDs.isEmpty)
            service.leases.release(lease)
        }
    }

    func testGrantedAuthorizationClearsCredentialAndPendingExports() throws {
        let lease = try makePendingExport()
        service.leases.beginShare(lease)

        let outcome = service.clearCredentialAndPendingExports(authorization: .granted)

        XCTAssertEqual(outcome, .cleared)
        XCTAssertFalse(configStore.hasStoredCredential())
        XCTAssertEqual(service.leases.activeLeaseCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lease.sessionDirectory.path))
        // Clinical identifiers are edited in place on the same screen; Clear is about the secret.
        XCTAssertEqual(try configStore.loadPrivateContext().patientID, "patient-1")
    }

    /// A refusal must say nothing happened, so a cancelled prompt never reads as a clear.
    func testEachOutcomeSaysWhatHappened() {
        let cleared = FHIRCredentialClearOutcome.cleared.message
        let denied = FHIRCredentialClearOutcome.kept(.denied).message
        let unavailable = FHIRCredentialClearOutcome.kept(.unavailable).message

        XCTAssertEqual(Set([cleared, denied, unavailable]).count, 3)
        XCTAssertTrue(denied.contains("nothing was cleared"), denied)
        XCTAssertTrue(unavailable.contains("nothing was cleared"), unavailable)
        XCTAssertFalse(cleared.contains("nothing"), cleared)
    }
}

// MARK: - Fixtures

/// Patient-like text a FHIR server could plausibly send back in an `OperationOutcome`.
private enum PHI {
    static let name = "Jane Q. Doe"
    static let mrn = "MRN-00417733"
    static let diagnosis = "type 2 diabetes"
    static let body = "Patient \(name) (\(mrn)) DOB 1961-04-12 — \(diagnosis)"

    static let operationOutcome = Data("""
    {"resourceType":"OperationOutcome","issue":[{"severity":"error","code":"invalid",
    "diagnostics":"\(body)","expression":["DocumentReference.subject"]}]}
    """.utf8)

    static func assertAbsent(from text: String, file: StaticString = #filePath, line: UInt = #line) {
        for marker in [name, "Jane", mrn, "1961-04-12", diagnosis, "OperationOutcome", "diagnostics"] {
            XCTAssertFalse(text.contains(marker), "\"\(marker)\" reached: \(text)", file: file, line: line)
        }
    }
}

private final class LineSink: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    func record(_ line: String) {
        lock.lock(); stored.append(line); lock.unlock()
    }

    var lines: [String] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
}
