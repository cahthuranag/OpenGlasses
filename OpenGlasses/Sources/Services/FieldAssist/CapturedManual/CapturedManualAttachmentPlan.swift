import Foundation

extension AttachmentBudget {
    /// A manual is useful as PDF + text or text alone. Counts are measured saved-file bytes;
    /// room already used by the work order, JSON, transcript and clips is reserved first.
    struct ManualPartition: Equatable {
        enum File: String, Equatable { case pdf, text }
        let attached: [File]
        let omitted: [File]
        let reason: String?
        var note: String? {
            guard !omitted.isEmpty else { return nil }
            let files = omitted.map { $0 == .pdf ? "photographed pages PDF" : "recognised manual text" }.joined(separator:" and ")
            return "The \(files) stayed on this phone. \(reason ?? "Share the omitted files separately if needed.")"
        }
    }

    func partitionManual(pdfBytes: Int?, textBytes: Int?, reservedBytes: Int = 0,
                         officeAudience: Bool) -> ManualPartition {
        let all: [ManualPartition.File] = [.pdf,.text]
        guard officeAudience else {
            return .init(attached:[],omitted:all,reason:"Photographed manuals are internal job evidence; this destination is not the configured office.")
        }
        guard carriesFiles else {
            return .init(attached:[],omitted:all,reason:"This channel cannot carry the manual files. Share them separately.")
        }
        let reserved = max(0,reservedBytes)
        func fits(_ sizes: [Int?]) -> Bool {
            var total = reserved
            for size in sizes {
                guard let size, size > 0, perFileBytes.map({size <= $0}) ?? true else {return false}
                let (next,overflow) = total.addingReportingOverflow(size)
                guard !overflow else {return false};total = next
            }
            return totalBytes.map {total <= $0} ?? true
        }
        if channel != .messages, fits([pdfBytes,textBytes]) {
            return .init(attached:all,omitted:[],reason:nil)
        }
        if fits([textBytes]) {
            return .init(attached:[.text],omitted:[.pdf],reason:channel == .messages
                ? "Messages offers the recognised text only; share the pages separately."
                : "The pages do not fit beside the report's other files; share them separately.")
        }
        return .init(attached:[],omitted:all,reason:"The manual files do not fit, or their sizes could not be verified. Share them separately.")
    }
}
