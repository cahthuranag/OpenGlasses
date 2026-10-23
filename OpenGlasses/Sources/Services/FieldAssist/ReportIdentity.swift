import Foundation
import CryptoKit

struct TechnicianIdentity: Codable, Equatable, Sendable {
    let fullName: String
    let shortName: String
    let technicianID: String

    init(fullName: String = "", shortName: String = "", technicianID: String = "") {
        self.fullName = TechnicianName.clean(fullName)
        self.shortName = TechnicianName.clean(shortName)
        self.technicianID = TechnicianID.clean(technicianID)
    }
}

enum TechnicianID {
    static let limit = 40
    static func clean(_ raw: String) -> String {
        let plain = String(String.UnicodeScalarView(raw.unicodeScalars.filter {
            !LearningCandidateText.isRefused($0)
        })).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(plain.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The four report fields, captured at job start. No credential is ever part of a job record.
struct ReportIdentity: Codable, Equatable, Sendable {
    let company: String
    let fullName: String
    let shortName: String
    private(set) var technicianID: String

    init(company: String = "", licensee: String = "", technician: TechnicianIdentity = .init()) {
        let company = TechnicianName.clean(company)
        self.company = company.isEmpty ? TechnicianName.clean(licensee) : company
        fullName = technician.fullName
        shortName = technician.shortName
        technicianID = technician.technicianID
    }

    var isEmpty: Bool { [company, fullName, shortName, technicianID].allSatisfy(\.isEmpty) }
    /// Customer documents name the person, never their internal technician ID.
    var customerLine: String? {
        let parts = [company, fullName.isEmpty ? shortName : fullName].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    var fromLine: String? {
        let parts = [customerLine, technicianID.isEmpty ? nil : "ID \(technicianID)"].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    var supportLines: [String] {
        var lines: [String] = []
        if !company.isEmpty { lines.append("Company: \(company)") }
        var person = fullName
        if !shortName.isEmpty { person += person.isEmpty ? shortName : " (\(shortName))" }
        if !technicianID.isEmpty { person += person.isEmpty ? "ID \(technicianID)" : ", ID \(technicianID)" }
        if !person.isEmpty { lines.append("Technician: \(person)") }
        return lines
    }
    static func fingerprint(code: String) -> String? {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }
        return SHA256.hash(data: Data(code.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}

extension Config {
    static var technicianFullName: String {
        get { TechnicianName.clean(PolicyEnvelope.string(.technicianFullName,
            stored: UserDefaults.standard.string(forKey: "technicianFullName") ?? "")) }
        set {
            guard !PolicyEnvelope.isLocked(.technicianFullName) else { return }
            let value = TechnicianName.clean(newValue)
            if value.isEmpty { UserDefaults.standard.removeObject(forKey: "technicianFullName") }
            else { UserDefaults.standard.set(value, forKey: "technicianFullName") }
        }
    }
    static var technicianID: String {
        get { TechnicianID.clean(PolicyEnvelope.string(.technicianID,
            stored: UserDefaults.standard.string(forKey: "technicianID") ?? "")) }
        set {
            guard !PolicyEnvelope.isLocked(.technicianID) else { return }
            let value = TechnicianID.clean(newValue)
            if value.isEmpty { UserDefaults.standard.removeObject(forKey: "technicianID") }
            else { UserDefaults.standard.set(value, forKey: "technicianID") }
        }
    }
    @MainActor static var reportIdentity: ReportIdentity? {
        let value = ReportIdentity(company: organizationDisplayName,
            licensee: LicenseService.shared.activeLicense?.licensee ?? "",
            technician: .init(fullName: technicianFullName, shortName: technicianDisplayName,
                              technicianID: technicianID))
        return value.isEmpty ? nil : value
    }
    @MainActor static var reportSupportLines: [String] {
        var lines = reportIdentity?.supportLines ?? []
        if let licence = LicenseService.shared.activeLicense {
            var parts = [TechnicianName.clean(licence.licensee)]
            if let plan = licence.plan { parts.append(TechnicianName.clean(plan)) }
            if let reference = licence.reference { parts.append(TechnicianName.clean(reference)) }
            parts.append("issued " + licence.issued.ISO8601Format().prefix(10))
            if let fingerprint = ReportIdentity.fingerprint(
                code: UserDefaults.standard.string(forKey: LicenseService.storageKey) ?? "") {
                parts.append("fingerprint " + fingerprint)
            }
            lines.append("Licence: " + parts.filter { !$0.isEmpty }.joined(separator: ", "))
        }
        if let enrolment = OrgProfileManager.shared.record?.enrolmentId {
            lines.append("Enrolment: " + enrolment)
        }
        return lines
    }
}


extension FieldSession {
    var reportIdentity: ReportIdentity? {
        guard let externalID = jobFile?.external?.technicianID, !externalID.isEmpty else { return reportedBy }
        return (reportedBy ?? ReportIdentity()).withExternalTechnicianID(externalID)
    }
}

extension ReportIdentity {
    func withExternalTechnicianID(_ value: String) -> ReportIdentity {
        var copy = self
        copy.technicianID = value
        return copy
    }
}
