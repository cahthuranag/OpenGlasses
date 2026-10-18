import Foundation

/// The stored FHIR credential belongs to the server address it was saved with (Plan DL).
///
/// The settings screen lets anyone holding the unlocked phone type a server address. If a
/// connection test sent the stored credential to whatever was typed, pointing the field at a
/// server of one's own would hand over the credential — without the device-owner prompt that
/// Clear asks for. So the credential only ever goes to the saved address, and the saved address
/// only changes together with a credential entered for it.
///
/// Addresses are compared the way the request code builds them,
/// `FHIRServerConfiguration.endpoint(for:)`: surrounding whitespace and a trailing slash are not a
/// different server. Nothing else is folded. A host in different case, an explicit default port,
/// or a different scheme or path is a different address until it is saved, which costs a
/// re-entered credential at worst and never sends the credential somewhere it wasn't saved for.
enum FHIRCredentialBinding {

    /// Whether two base-URL strings name the same endpoint. Two unusable addresses are not the
    /// same address: nothing can be sent to either.
    static func isSameEndpoint(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = FHIRServerConfiguration(baseURL: lhs).endpoint(for: "metadata"),
              let right = FHIRServerConfiguration(baseURL: rhs).endpoint(for: "metadata") else {
            return false
        }
        return left.absoluteString == right.absoluteString
    }

    /// Whether the settings screen may save `newBaseURL` as the server address.
    ///
    /// A new address with a credential still stored for the old one is refused unless a
    /// credential is entered with it: the stored one stays bound to the address it was saved
    /// with. Silently clearing it instead would be a way round Clear's device-owner prompt.
    /// `credentialStored` is `true` when the store cannot tell, so a locked or failing store
    /// refuses rather than re-binding a credential it could not see.
    static func maySaveEndpoint(savedBaseURL: String,
                                newBaseURL: String,
                                credentialStored: Bool,
                                credentialEntered: Bool) -> Bool {
        if isSameEndpoint(savedBaseURL, newBaseURL) { return true }
        // Two blank fields are the same "no server" — nothing is bound to it.
        if savedBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           newBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return !credentialStored || credentialEntered
    }
}

/// Which credential, if any, a FHIR connection test sends. Pure; the request is built by
/// `MedicalExportService.testConnection(baseURL:enteredCredential:)`.
enum FHIRConnectionTestPolicy {

    enum Credential: Equatable {
        /// The credential stored for the saved address, which is the address being tested.
        case stored
        /// A credential typed into the field for this test and not yet saved. The person just
        /// entered it, so sending it where they point the test gives nothing away.
        case entered
        /// A credential is stored, but the address being tested is not the one it was saved with,
        /// so the test checks that the server answers and sends no credential.
        case withheld
        /// Nothing is stored or entered.
        case none

        /// Whether the request carries an `Authorization` header.
        var isSent: Bool { self == .stored || self == .entered }
    }

    static func credential(savedBaseURL: String,
                           testedBaseURL: String,
                           credentialStored: Bool,
                           credentialEntered: Bool) -> Credential {
        if credentialEntered { return .entered }
        guard credentialStored else { return .none }
        return FHIRCredentialBinding.isSameEndpoint(savedBaseURL, testedBaseURL) ? .stored : .withheld
    }
}

/// How saving the FHIR server settings ended, and what the screen says about it.
enum FHIRServerSaveOutcome: Equatable {
    /// Everything was saved. `storedCredential` is true when an entered credential was stored.
    case saved(storedCredential: Bool)
    /// Refused: a credential is stored for the saved address, and none was entered for the new
    /// one. Nothing was saved.
    case credentialBoundToSavedAddress
    case failed(MedicalExportFailure)

    var message: String {
        switch self {
        case .saved:
            return "Configuration saved."
        case .credentialBoundToSavedAddress:
            return String(localized: "The saved credential belongs to the address it was saved with, so nothing was saved. To use a new address, tap Replace and enter its credential, or clear the saved one first.")
        case .failed(let failure):
            return failure.message
        }
    }
}
