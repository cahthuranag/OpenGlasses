import Foundation

/// How the app authenticates to a FHIR server.
enum FHIRAuthMode: String, Codable, CaseIterable, Identifiable {
    /// Open/anonymous endpoint — nothing is held in the credential store.
    case none
    /// Pre-obtained OAuth bearer token.
    case bearerToken
    /// SMART on FHIR client credentials.
    case clientSecret

    var id: String { rawValue }

    /// True when the mode is backed by a value in the credential store. Switching away from a
    /// secret-bearing mode clears that value: a credential must not outlive the reason to hold it.
    var usesStoredSecret: Bool { self != .none }
}

/// Public, non-secret FHIR connection metadata — the only part of the FHIR setup allowed into
/// `UserDefaults`. It carries no token, no client secret, and no clinical identifier;
/// ``FHIRCredential`` and ``FHIRPrivateContext`` hold those in protected storage, keyed by
/// ``serverID``.
///
/// `serverID` is opaque and stable for the life of a server entry, so editing the URL does not
/// orphan the protected values stored beside it.
struct FHIRServerConfiguration: Codable, Equatable {
    var serverID: String
    var baseURL: String
    var authMode: FHIRAuthMode
    var clientID: String
    /// `MedicalPlatform.rawValue`. Stored as a string so an unknown value from a newer build
    /// degrades to the generic FHIR platform instead of failing the whole decode.
    var platformType: String

    init(serverID: String = UUID().uuidString,
         baseURL: String = "",
         authMode: FHIRAuthMode = .bearerToken,
         clientID: String = "",
         platformType: String = MedicalPlatform.fhir.rawValue) {
        self.serverID = serverID
        self.baseURL = baseURL
        self.authMode = authMode
        self.clientID = clientID
        self.platformType = platformType
    }

    /// The complete set of keys this type may ever encode. Tests assert the encoded payload
    /// against it, so a future field cannot quietly reintroduce a secret or a clinical identifier
    /// into preferences.
    static let encodedKeys: Set<String> = ["serverID", "baseURL", "authMode", "clientID", "platformType"]

    var platform: MedicalPlatform { MedicalPlatform(rawValue: platformType) ?? .fhir }

    var isConfigured: Bool { !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Resource endpoint for a FHIR resource type, or nil when the base URL is unusable.
    func endpoint(for resourceType: String) -> URL? {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        return URL(string: base.hasSuffix("/") ? "\(base)\(resourceType)" : "\(base)/\(resourceType)")
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverID = try container.decodeIfPresent(String.self, forKey: .serverID) ?? UUID().uuidString
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        authMode = (try? container.decode(FHIRAuthMode.self, forKey: .authMode)) ?? .bearerToken
        clientID = try container.decodeIfPresent(String.self, forKey: .clientID) ?? ""
        platformType = try container.decodeIfPresent(String.self, forKey: .platformType) ?? MedicalPlatform.fhir.rawValue
    }
}

/// Secret credentials for one FHIR server. Lives only in the Keychain and in memory for the
/// duration of a single request; never encoded into preferences, logs, or export metadata.
struct FHIRCredential: Codable, Equatable {
    var bearerToken: String?
    var clientSecret: String?

    init(bearerToken: String? = nil, clientSecret: String? = nil) {
        self.bearerToken = trimmedOrNil(bearerToken)
        self.clientSecret = trimmedOrNil(clientSecret)
    }

    var isEmpty: Bool { bearerToken == nil && clientSecret == nil }
}

/// Clinical identifiers for one FHIR server. Regulated medical data, so it is stored beside the
/// credential in protected storage rather than in preferences — separately namespaced, so a query
/// for one cannot return the other.
struct FHIRPrivateContext: Codable, Equatable {
    var patientID: String?
    var practitionerID: String?

    init(patientID: String? = nil, practitionerID: String? = nil) {
        self.patientID = trimmedOrNil(patientID)
        self.practitionerID = trimmedOrNil(practitionerID)
    }

    var isEmpty: Bool { patientID == nil && practitionerID == nil }
}

/// Everything one FHIR request needs, assembled at request-construction time and discarded after.
/// There is deliberately no API that returns every server's secrets at once.
struct FHIRRequestContext {
    let configuration: FHIRServerConfiguration
    let credential: FHIRCredential
    let privateContext: FHIRPrivateContext
}

/// User-facing failures across the medical credential and export lifecycle. Deliberately closed
/// over app-side conditions: a server response body may contain PHI and is never echoed here.
enum MedicalExportError: LocalizedError, Equatable {
    case serverNotConfigured
    case migrationPending
    case credentialLocked
    case credentialMissing
    case protectedStorageUnavailable
    case exportSetupFailed
    case exportWriteFailed

    /// The sentence lives on ``MedicalExportFailure``, so a thrown error and a classified failure
    /// can never word the same condition two ways.
    var errorDescription: String? { MedicalExportFailure(self).message }
}

/// Trimmed value, or `nil` when the string is empty or whitespace only, so "cleared" and
/// "never set" collapse to one state in protected storage.
private func trimmedOrNil(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
    return trimmed
}
