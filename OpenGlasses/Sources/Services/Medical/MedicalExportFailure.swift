import Foundation

/// What went wrong with a medical export or a FHIR request, in a closed vocabulary (Plan DL P3.1).
///
/// The sentence a wearer sees — and that a tool hands the model to read back aloud — is fixed per
/// case. Nothing a server sent is in it: a FHIR server's reply to a refused write is typically an
/// `OperationOutcome` that can quote the submitted resource, patient reference and all, so the body
/// is never read. Nor is an error's own description quoted: a URL error's names the host, and an
/// unknown error's could say anything. The status code and the error's category go to `PrivacyLog`
/// as a ``SafeErrorSummary``, which is where troubleshooting detail belongs.
enum MedicalExportFailure: Equatable, CaseIterable {
    // Before anything is sent.
    case serverNotConfigured
    case migrationPending
    case credentialLocked
    case credentialMissing
    case protectedStorageUnavailable
    case invalidServerURL
    // Share files.
    case exportSetupFailed
    case exportWriteFailed
    // The server answered, and not with success.
    case credentialRejected
    case documentRejected
    case serverUnavailable
    case unexpectedResponse
    // The transport.
    case unreachable
    /// The request may have arrived: it timed out, or the connection dropped, after it was sent.
    case outcomeUnknown
    case failed

    /// Which request failed. Only the submission can end with its outcome unknown — a connection
    /// test that times out simply did not reach the server, and nothing was written.
    enum Operation: String {
        case submission, connectionTest
    }

    /// Classify a non-success HTTP status by its class. The body that came with it is not an input.
    init(httpStatus status: Int) {
        switch status {
        case 401, 403: self = .credentialRejected
        case 429, 500...599: self = .serverUnavailable
        case 400...499: self = .documentRejected
        default: self = .unexpectedResponse
        }
    }

    /// Classify a thrown error by its type and code. Its description is never read.
    init(_ error: Error, operation: Operation = .submission) {
        if let known = error as? MedicalExportError {
            self.init(known)
            return
        }
        guard let urlError = error as? URLError else {
            self = .failed
            return
        }
        switch urlError.code {
        case .timedOut, .networkConnectionLost:
            self = operation == .submission ? .outcomeUnknown : .unreachable
        case .badURL, .unsupportedURL:
            self = .invalidServerURL
        case .userAuthenticationRequired:
            self = .credentialRejected
        case .badServerResponse, .cannotParseResponse, .zeroByteResource:
            self = .unexpectedResponse
        default:
            self = .unreachable
        }
    }

    init(_ error: MedicalExportError) {
        switch error {
        case .serverNotConfigured: self = .serverNotConfigured
        case .migrationPending: self = .migrationPending
        case .credentialLocked: self = .credentialLocked
        case .credentialMissing: self = .credentialMissing
        case .protectedStorageUnavailable: self = .protectedStorageUnavailable
        case .exportSetupFailed: self = .exportSetupFailed
        case .exportWriteFailed: self = .exportWriteFailed
        }
    }

    /// The fixed sentence for this failure.
    var message: String {
        switch self {
        case .serverNotConfigured:
            return String(localized: "No FHIR server is configured. Add one in Medical Export settings.")
        case .migrationPending:
            return String(localized: "Clinical credentials are still being moved to protected storage. Unlock the device, reopen the app, and try again.")
        case .credentialLocked:
            return String(localized: "Clinical credentials are unavailable while the device is locked. Unlock the device and try again.")
        case .credentialMissing:
            return String(localized: "No credential is stored for this FHIR server. Enter one in Medical Export settings.")
        case .protectedStorageUnavailable:
            return String(localized: "Protected storage is unavailable. Unlock the device and try again.")
        case .invalidServerURL:
            return String(localized: "The FHIR server address isn't valid. Check it in Medical Export settings.")
        case .exportSetupFailed:
            return String(localized: "The export could not be given the required protection, so it was discarded.")
        case .exportWriteFailed:
            return String(localized: "The export file could not be written.")
        case .credentialRejected:
            return String(localized: "The FHIR server didn't accept the credential. Check or replace it in Medical Export settings.")
        case .documentRejected:
            return String(localized: "The FHIR server turned the document down. Check the server settings, or share the transcript instead.")
        case .serverUnavailable:
            return String(localized: "The FHIR server couldn't take the request right now. Try again later.")
        case .unexpectedResponse:
            return String(localized: "The FHIR server sent a reply the app doesn't recognise.")
        case .unreachable:
            return String(localized: "Couldn't reach the FHIR server. Check the connection and the server address.")
        case .outcomeUnknown:
            return String(localized: "The FHIR server didn't answer in time, so it may or may not have the document. Check the record before sending it again.")
        case .failed:
            return String(localized: "The export didn't complete.")
        }
    }

    /// Log a failure through `PrivacyLog`: the operation, and a summary of the status or error.
    @discardableResult
    static func log(_ operation: Operation, status: Int) -> PrivacyEvent {
        PrivacyLog.medical(.fhir, .exportFailed, operation: PrivacyToken(operation.rawValue),
                           error: .http(status: status))
    }

    @discardableResult
    static func log(_ operation: Operation, error: Error) -> PrivacyEvent {
        PrivacyLog.medical(.fhir, .exportFailed, operation: PrivacyToken(operation.rawValue),
                           error: SafeErrorSummary(error))
    }
}
