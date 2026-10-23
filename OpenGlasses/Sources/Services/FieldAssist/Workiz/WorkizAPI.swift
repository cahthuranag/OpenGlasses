import Foundation
import CoreFoundation

/// Closed values from the v2 API. Customer email, attachment URLs and money never enter them.
struct WorkizClient: Equatable {
    let id: String?
    let name: String
    let address: String
    let phone: String
}
struct WorkizUser: Equatable, Identifiable {
    let id: String
    let name: String
    let emailAddress: String
    let active: Bool
    let fieldTech: Bool
}
struct WorkizCustomField: Equatable {
    let id: String
    let name: String
    let type: String
    let entityType: String
}
struct WorkizNote: Equatable {
    let id: String
    let text: String
    let author: String
    let timestamp: String
}
struct WorkizJob: Equatable, Identifiable {
    let id: String
    let number: String
    let name: String
    let status: String
    let scheduled: String?
    let jobType: String
    let fault: String
    let client: WorkizClient
    let team: [String]
    let notes: [WorkizNote]
    let attachments: [String]
    /// Only textual fields are retained. Never echo other fields in a PUT.
    let customFields: [String: String]
    var isCancelled: Bool { ["canceled", "cancelled"].contains(status.lowercased()) }
    var isOpen: Bool { !isCancelled && !["done", "done pending approval"].contains(status.lowercased()) }
}
struct WorkizPage<Value> {
    let data: [Value]
    let hasMore: Bool
    let dropped: Int
}

enum WorkizFailure: Error, LocalizedError, Equatable {
    case badKey, permission(String), rateLimited, unavailable, offline, malformed, pageBudget
    case reportField, reportTooLarge, disabled, noteUncertain, notFound, clientMissing
    var errorDescription: String? {
        switch self {
        case .badKey: return "Workiz didn't accept the key — it may have been replaced. Paste the new key in Settings."
        case .permission(let resource):
            let scope = ["Users", "Custom fields"].contains(resource) ? "Read" : "Read & Write"
            return "The Workiz key can't access \(resource). Ask the owner to give it \(resource): \(scope)."
        case .rateLimited: return "Workiz is limiting requests. The report will wait and try again."
        case .unavailable: return "Workiz is unavailable. The report will wait and try again."
        case .offline: return "No connection to Workiz. Your saved jobs and reports are still on this phone."
        case .notFound: return "That job is no longer in Workiz."
        case .malformed: return "Workiz returned a response this phone couldn't read."
        case .pageBudget: return "Workiz returned more pages than this phone can safely load. Narrow the account's job list and refresh."
        case .reportField: return "Create a Large Text field on Workiz jobs called Field Assist report, or check the field name in Settings."
        case .reportTooLarge: return "The Workiz report field is too large to update safely. Ask the owner to review it."
        case .disabled: return "The Workiz connection is off."
        case .clientMissing: return "The report is in Workiz, but this job has no client for the optional note."
        case .noteUncertain: return "The report is in Workiz. A client note may already have been posted; check Workiz before sending another."
        }
    }
    static func status(_ status: Int, resource: String) -> WorkizFailure? {
        switch status {
        case 200..<300: return nil
        case 401: return .badKey
        case 403: return .permission(["Jobs", "Users", "Clients", "Custom fields"].contains(resource) ? resource : "Jobs")
        case 404: return .notFound
        case 429: return .rateLimited
        case 500...599: return .unavailable
        default: return .malformed
        }
    }
}

enum WorkizAPI {
    static let baseURL = URL(string: "https://api.workiz.com/crm/api/v2/")!
    static let maximumBytes = 2_000_000
    static let pageSize = 100
    static let pageBudget = 20

    /// Paths are built from closed resources and validated v2 identifiers; no arbitrary URL seam.
    enum Resource {
        case jobs, job(String), users, customFields, clientNotes(String)
        var path: String {
            switch self {
            case .jobs: return "jobs"
            case .job(let id): return "jobs/" + id
            case .users: return "users"
            case .customFields: return "customfields"
            case .clientNotes(let id): return "clients/" + id + "/notes"
            }
        }
        var permission: String {
            switch self {
            case .jobs, .job: return "Jobs"
            case .users: return "Users"
            case .customFields: return "Custom fields"
            case .clientNotes: return "Clients"
            }
        }
        var valid: Bool {
            switch self {
            case .job(let id): return WorkizAPI.identifier(id, prefix: "JOB-")
            case .clientNotes(let id): return WorkizAPI.identifier(id, prefix: "CL-")
            default: return true
            }
        }
    }
    static func identifier(_ value: String, prefix: String) -> Bool {
        value.hasPrefix(prefix) && value.count > prefix.count && value.count <= 100
            && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }
    }
    static func request(_ resource: Resource, key: String, query: [URLQueryItem] = [],
                        method: String = "GET", body: Data? = nil) throws -> URLRequest {
        guard resource.valid, !key.isEmpty, key.utf8.count <= 4096,
              !key.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw WorkizFailure.badKey }
        switch (resource, method) {
        case (_, "GET"):
            guard body == nil else { throw WorkizFailure.malformed }
        case (.job, "PUT"):
            guard let body, let fields = try object(body)["customFields"] as? [[String: Any]],
                  Set(try object(body).keys) == ["customFields"], fields.count == 1,
                  let field = fields.first, Set(field.keys) == ["id", "value"],
                  let id = field["id"] as? String, identifier(id, prefix: "CF-"),
                  let value = field["value"] as? String, value.utf8.count <= WorkizWriteBack.maximumFieldBytes else { throw WorkizFailure.malformed }
        case (.clientNotes, "POST"):
            guard let body, Set(try object(body).keys) == ["note"],
                  let note = try object(body)["note"] as? String, note.utf8.count <= 65_000 else { throw WorkizFailure.malformed }
        default: throw WorkizFailure.malformed
        }
        var url = URLComponents(url: baseURL.appendingPathComponent(resource.path), resolvingAgainstBaseURL: false)!
        url.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: url.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.timeoutInterval = 25
        return request
    }
    static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= maximumBytes,
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw WorkizFailure.malformed }
        return value
    }
    static func text(_ value: Any?, limit: Int = 1000) -> String {
        guard let value = value as? String else { return "" }
        return String(value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" }.prefix(limit))
    }
    /// JSONSerialization bridges both JSON numbers and booleans through NSNumber.
    static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    static func objects(_ value: Any?) -> [[String: Any]] { Array((value as? [[String: Any]] ?? []).prefix(pageSize)) }
    static func page<T>(_ data: Data, decode: ([String: Any]) -> T?) throws -> WorkizPage<T> {
        let root = try object(data)
        guard let rows = root["data"] as? [Any], rows.count <= pageSize, let more = boolean(root["hasMore"]) else { throw WorkizFailure.malformed }
        let values = rows.compactMap { ($0 as? [String: Any]).flatMap(decode) }
        return WorkizPage(data: values, hasMore: more, dropped: rows.count - values.count)
    }
    static func job(_ data: Data) throws -> WorkizJob {
        guard let job = job(try object(data)) else { throw WorkizFailure.malformed }; return job
    }
    static func job(_ row: [String: Any]) -> WorkizJob? {
        let id = text(row["id"], limit: 101)
        guard identifier(id, prefix: "JOB-"), let number = row["serialId"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite, number.doubleValue > 0, number.doubleValue < 9_007_199_254_740_991,
              number.doubleValue.rounded() == number.doubleValue,
              let status = row["status"] as? String, !status.isEmpty else { return nil }
        let client = row["clientInfo"] as? [String: Any] ?? [:]
        let address = client["addressDetails"] as? [String: Any] ?? [:]
        let customerName = [text(client["firstName"], limit: 120), text(client["lastName"], limit: 120)].filter { !$0.isEmpty }.joined(separator: " ")
        let clientID = text(client["clientId"], limit: 101)
        let rawFields: [[String: Any]]
        if let raw = row["customFields"] {
            guard let fields = raw as? [[String: Any]], fields.count <= pageSize else { return nil }
            rawFields = fields
        } else { rawFields = [] }
        var fieldIDs = Set<String>()
        for field in rawFields {
            let fieldID = text(field["id"], limit: 101)
            if identifier(fieldID, prefix: "CF-"), !fieldIDs.insert(fieldID).inserted { return nil }
        }
        // A truncated or ambiguous snapshot could mistake somebody else's report for an empty field.
        guard !rawFields.contains(where: { ($0["value"] as? String)?.utf8.count ?? 0 > 60_000 }) else { return nil }
        let fields = rawFields.reduce(into: [String: String]()) { result, field in
            let id = text(field["id"], limit: 101)
            if identifier(id, prefix: "CF-"), let value = field["value"] as? String {
                // Refuse oversize fields rather than truncating and later overwriting somebody's block.
                if value.utf8.count <= 60_000 { result[id] = value }
            }
        }
        let rawDate = text(row["date"], limit: 80)
        return WorkizJob(id: id, number: String(number.int64Value), name: text(row["name"]), status: text(status, limit: 80),
            scheduled: boolean(row["isScheduled"]) == false || rawDate.isEmpty ? nil : rawDate,
            jobType: text((row["jobType"] as? [String: Any])?["name"]), fault: text(row["description"], limit: 12_000),
            client: WorkizClient(id: identifier(clientID, prefix: "CL-") ? clientID : nil,
                name: customerName.isEmpty ? text(client["companyName"], limit: 240) : customerName,
                address: ["address", "unit", "city", "state", "zipCode", "country"].map { text(address[$0], limit: 300) }.filter { !$0.isEmpty }.joined(separator: ", "),
                phone: text(client["primaryPhone"], limit: 80)),
            team: objects(row["team"]).map { text($0["id"], limit: 100) }.filter { identifier($0, prefix: "USR-") },
            notes: (row["notes"] as? [[String: Any]] ?? []).sorted { text($0["timestamp"], limit: 80) > text($1["timestamp"], limit: 80) }.prefix(5).map(note), attachments: objects(row["attachments"]).map { text($0["name"], limit: 240) },
            customFields: fields)
    }
    static func user(_ row: [String: Any]) -> WorkizUser? {
        let id = text(row["id"], limit: 101)
        guard identifier(id, prefix: "USR-") else { return nil }
        return WorkizUser(id: id, name: text(row["name"], limit: 120), emailAddress: text(row["emailAddress"], limit: 254), active: boolean(row["active"]) == true, fieldTech: boolean(row["fieldTech"]) == true)
    }
    static func field(_ row: [String: Any]) -> WorkizCustomField? {
        let id = text(row["id"], limit: 101)
        guard identifier(id, prefix: "CF-") else { return nil }
        return WorkizCustomField(id: id, name: text(row["name"], limit: 120), type: text(row["type"], limit: 40), entityType: text(row["entityType"], limit: 20))
    }
    static func note(_ row: [String: Any]) -> WorkizNote {
        WorkizNote(id: text(row["id"], limit: 100), text: text(row["note"], limit: 12_000), author: text(row["techName"], limit: 120), timestamp: text(row["timestamp"] ?? row["createdAt"], limit: 80))
    }
}
