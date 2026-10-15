import Foundation

/// How a "Clear" of the FHIR credential ended (Plan DL P3.2), and what to tell the person who
/// pressed it. Pure: the device-owner prompt is `OwnerGateAuth.authorize`, and the clear itself is
/// `MedicalExportService.clearCredentialAndPendingExports(authorization:)`.
enum FHIRCredentialClearOutcome: Equatable {
    /// The credential is gone, and so is every export that was waiting to be shared.
    case cleared
    /// Nothing was cleared, because owner authorization was not granted.
    case kept(OwnerAuthorization)

    var didClear: Bool { self == .cleared }

    /// A refusal says that nothing was cleared, so a cancelled prompt can't read as success.
    var message: String {
        switch self {
        case .cleared:
            return String(localized: "Credential cleared, along with any exports waiting to be shared.")
        case .kept(.unavailable):
            return String(localized: "This phone couldn't ask for your passcode, so nothing was cleared. Clearing the credential needs a device passcode.")
        case .kept:
            return String(localized: "Couldn't verify it's you, so nothing was cleared.")
        }
    }
}
