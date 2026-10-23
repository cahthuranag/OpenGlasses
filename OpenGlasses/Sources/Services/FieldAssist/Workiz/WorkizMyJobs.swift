import Foundation
import CryptoKit

enum WorkizMyJobs {
    /// Workiz's unzoned timestamps use the account's timezone. Configure that explicitly; it
    /// defaults to the phone's zone. Never silently interpret a local timestamp as UTC.
    static func date(_ text: String, timeZone: TimeZone) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone; f.dateFormat = "yyyy-MM-dd HH:mm:ss"; f.isLenient = false
        return f.date(from: text)
    }
    static func select(_ jobs: [WorkizJob], technicianID: String, now: Date, timeZone: TimeZone, cap: Int = 100) -> [WorkizJob] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        let end = calendar.date(byAdding: .day, value: 8, to: calendar.startOfDay(for: now))!
        var seen = Set<String>()
        return Array(jobs.reversed().filter { job in
            guard seen.insert(job.id).inserted, job.isOpen, job.team.contains(technicianID) else { return false }
            guard let scheduled = job.scheduled else { return true }
            guard let date = date(scheduled, timeZone: timeZone) else { return false }
            return date >= start && date < end
        }.sorted { a, b in
            let ad = a.scheduled.flatMap { date($0, timeZone: timeZone) } ?? .distantFuture
            let bd = b.scheduled.flatMap { date($0, timeZone: timeZone) } ?? .distantFuture
            return ad == bd ? a.id < b.id : ad < bd
        }.prefix(max(0, cap)))
    }
    /// Two bounded scans: scheduled dates in the window and all jobs created before its end
    /// for unscheduled assignments. Hitting a budget aborts reconciliation, never removes cached jobs.
    static func queries(now: Date, timeZone: TimeZone) -> [[URLQueryItem]] {
        var c = Calendar(identifier: .gregorian); c.timeZone = timeZone
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = timeZone; f.dateFormat = "yyyy-MM-dd"
        let start = f.string(from: c.date(byAdding: .day, value: -1, to: now)!)
        let end = f.string(from: c.date(byAdding: .day, value: 7, to: now)!)
        let scheduled = [URLQueryItem(name: "isOpen", value: "true"), URLQueryItem(name: "dateProperty", value: "date"),
            URLQueryItem(name: "dateOperator", value: "between"), URLQueryItem(name: "date", value: start + "_" + end)]
        // `prev` has no one-year range restriction. It covers old unscheduled assignments too.
        let unscheduled = [URLQueryItem(name: "isOpen", value: "true"), URLQueryItem(name: "dateProperty", value: "created"),
            URLQueryItem(name: "dateOperator", value: "prev"), URLQueryItem(name: "date", value: end)]
        return [scheduled, unscheduled]
    }
}

enum WorkizJobMapper {
    static func map(_ job: WorkizJob, technicianID: String, now: Date, timeZone: TimeZone) -> UpcomingJob {
        let external = ExternalJobReference(system: "workiz", systemName: "Workiz", jobID: job.id,
            jobNumber: job.number, appointmentID: nil, locationID: nil, customerID: job.client.id, technicianID: technicianID, equipmentIDs: nil)
        let notes = job.notes.sorted { $0.timestamp > $1.timestamp }.prefix(5)
            .map { "\($0.author) · \($0.timestamp)\n\($0.text)" }.joined(separator: "\n\n")
        return UpcomingJob(id: "workiz:" + job.id, jobReference: job.number,
            site: JobSite(customer: job.client.name, address: job.client.address, contact: job.client.phone),
            faultReport: FaultReport(text: [job.jobType, job.fault].filter { !$0.isEmpty }.joined(separator: "\n"), source: .connector, receivedAt: now),
            scheduledFor: job.scheduled.flatMap { WorkizMyJobs.date($0, timeZone: timeZone) }, notes: notes,
            attachments: job.attachments, origin: .connector,
            provenance: JobFileProvenance(fileName: "Workiz", signature: .unsigned, signer: nil, receivedAt: now,
                digest: "", external: external, connector: "workiz"), createdAt: now)
    }
}
