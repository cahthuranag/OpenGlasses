import Foundation
import CryptoKit

enum WorkizWriteBack {
    static let defaultFieldName = "Field Assist report"
    static let maximumFieldBytes = 60_000
    struct Report: Codable, Equatable {
        let jobID: String
        let clientID: String?
        let marker: String
        let text: String
        let noteHeading: String
        let fieldName: String
        let clientNote: Bool
    }
    static func report(_ record: WorkRecord, fieldName: String = defaultFieldName, clientNote: Bool = false) -> Report? {
        guard record.endedAt != nil, let ref = record.jobFile?.external, ref.system == "workiz",
              WorkizAPI.identifier(ref.jobID, prefix: "JOB-") else { return nil }
        let digest = SHA256.hash(data: record.json).prefix(4).map { String(format: "%02x", $0) }.joined()
        let marker = "Avenkin ref " + digest
        // The customer summary is deterministic work/findings/parts/recommendations. A transcript,
        // photos, attachments, URLs, model prompts and debrief conversation have no path here.
        var lines = record.customerSummaryLines
        if let identity = record.reportedBy { lines.append(contentsOf: identity.supportLines) }
        lines += SpokenReadingLedger.chains(record.spokenReadings ?? []).map { SpokenReadingLedger.line(for: $0) }
        let heading = "Job \(record.jobReference ?? ref.jobNumber ?? ref.jobID) — \((record.endedAt ?? record.startedAt).formatted(date: .abbreviated, time: .omitted))"
        return Report(jobID: ref.jobID, clientID: ref.customerID, marker: marker,
            text: ([marker] + lines).joined(separator: "\n"), noteHeading: heading,
            fieldName: fieldName, clientNote: clientNote)
    }
    static func field(_ fields: [WorkizCustomField], named name: String) throws -> WorkizCustomField {
        let matches = fields.filter { $0.name == name && $0.type == "Large Text" && $0.entityType == "JOB" }
        guard matches.count == 1, let field = matches.first else { throw WorkizFailure.reportField }; return field
    }
    static func isMarker(_ line: String) -> Bool {
        guard line.hasPrefix("Avenkin ref ") else { return false }
        let hex = line.dropFirst(12)
        return hex.count == 8 && hex.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    /// Preserve every byte outside our exact block, including an unmarked preamble.
    static func merging(existing: String, report: Report) throws -> String {
        guard existing.utf8.count <= maximumFieldBytes, isMarker(report.marker),
              report.text.components(separatedBy: "\n").first == report.marker,
              !report.text.components(separatedBy: "\n").dropFirst().contains(where: isMarker) else { throw WorkizFailure.reportTooLarge }
        var lines = existing.components(separatedBy: "\n")
        let matches = lines.indices.filter { lines[$0] == report.marker }
        guard matches.count <= 1 else { throw WorkizFailure.malformed }
        let value: String
        if let start = matches.first {
            let end = lines.indices.first { $0 > start && isMarker(lines[$0]) } ?? lines.endIndex
            lines.replaceSubrange(start..<end, with: report.text.components(separatedBy: "\n") + (end < lines.endIndex ? [""] : []))
            value = lines.joined(separator: "\n")
        } else { value = existing.isEmpty ? report.text : existing + "\n\n" + report.text }
        guard value.utf8.count <= maximumFieldBytes else { throw WorkizFailure.reportTooLarge }
        return value
    }
    static func body(fieldID: String, value: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["customFields": [["id": fieldID, "value": value]]], options: [.sortedKeys])
    }
}
