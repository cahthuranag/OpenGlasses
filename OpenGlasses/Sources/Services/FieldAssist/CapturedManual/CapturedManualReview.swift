import Foundation

/// Optional signed-vault metadata. A decoded value is a claim; only the authenticated Office
/// assignment/archive path may establish its trust, and indexing must reach Ready before reuse.
struct CapturedManualReview: Codable, Equatable, Sendable {
    struct Origin: Codable, Equatable, Sendable {
        let captureID: String
        let captureRevision: Int64
        let bundleSHA256: String
        let pageCount: Int
    }
    struct Page: Codable, Equatable, Sendable {
        let index: Int
        let originIndex: Int
        let capturePage: Int
        let printedPage: Int
        let textOffset: Int
        let textBytes: Int
    }
    let version: Int
    let origins: [Origin]
    let pageCount: Int
    let ocrPages: Int
    let failedPages: Int
    let lowConfidencePages: Int
    let pages: [Page]
    let organizationID: String
    let technician: String
    let jobReference: String
    let capturedAt: Int64
    let reviewerID: String
    let reviewerName: String
    let approvedAt: Int64

    var valid: Bool {
        guard version == 1,(1...256).contains(pageCount),(1...256).contains(origins.count),
              pages.count == pageCount,ocrPages >= 0,failedPages >= 0,
              ocrPages <= pageCount,failedPages == pageCount - ocrPages,
              (0...ocrPages).contains(lowConfidencePages),capturedAt > 0,approvedAt >= capturedAt,
              Self.identifier(organizationID),Self.identifier(reviewerID),
              Self.plain(technician,maximum:160),Self.plain(jobReference,maximum:120),
              Self.plain(reviewerName,maximum:160),!reviewerName.isEmpty else {return false}
        var originKeys = Set<String>()
        for origin in origins {
            guard Self.identifier(origin.captureID),origin.captureRevision > 0,
                  (1...256).contains(origin.pageCount),origin.bundleSHA256.utf8.count == 64,
                  origin.bundleSHA256.allSatisfy({$0.isASCII && ($0.isNumber || ("a"..."f").contains(String($0)))}),
                  originKeys.insert("\(origin.captureID):\(origin.captureRevision)").inserted else {return false}
        }
        for (offset,page) in pages.enumerated() {
            guard page.index == offset + 1,origins.indices.contains(page.originIndex),
                  (1...origins[page.originIndex].pageCount).contains(page.capturePage),
                  (0...9_999).contains(page.printedPage),page.textOffset >= 0,page.textBytes >= 0 else {return false}
        }
        // Naming an origin replaces its whole revision; a subset cannot silently retire the
        // uncopied pages of a local book. Merges must map all the pages of every named origin.
        for index in origins.indices {
            let mapped = pages.filter {$0.originIndex == index}.map(\.capturePage)
            guard mapped.count == origins[index].pageCount,
                  Set(mapped) == Set(1...origins[index].pageCount) else {return false}
        }
        return true
    }
    func citationName(title: String) -> String {
        func date(_ seconds:Int64) -> String {String(ISO8601DateFormatter().string(from:Date(timeIntervalSince1970:Double(seconds))).prefix(10))}
        func label(_ value:String) -> String {value.replacingOccurrences(of:",",with:" ·")}
        return "Reviewed photographed manual · \(label(title)) · photographed by \(label(technician)) at job \(label(jobReference)) on \(date(capturedAt)) · approved by \(label(reviewerName)) on \(date(approvedAt))"
    }
    /// The review archive carries page-fenced text. Ordinary Page N/footer heuristics never
    /// determine physical page identity, including for corrected text and empty failed pages.
    func pageTexts(_ data: Data) throws -> [(number:Int,text:String)] {
        guard valid,data.count <= CapturedManualContract.maximumTextBytes else {throw CapturedManualStore.Failure.invalidRequest}
        var offset = 0
        let result = try pages.map { page -> (number:Int,text:String) in
            let header = Data("## Page \(page.index)\n\n".utf8)
            guard page.textOffset <= data.count,page.textBytes <= data.count - page.textOffset,
                  page.textOffset == offset + header.count,data.subdata(in:offset..<page.textOffset) == header else {
                throw CapturedManualStore.Failure.invalidRequest
            }
            let end = page.textOffset + page.textBytes
            guard data.count - end >= 2,data.subdata(in:end..<(end+2)) == Data([10,10]),
                  let body = String(data:data.subdata(in:page.textOffset..<end),encoding:.utf8) else {throw CapturedManualStore.Failure.invalidRequest}
            offset = end + 2;return (page.index,body)
        }
        guard offset == data.count else {throw CapturedManualStore.Failure.invalidRequest}
        return result
    }
    private static func plain(_ text:String,maximum:Int) -> Bool {
        text.utf8.count <= maximum && !text.unicodeScalars.contains {$0.value < 32 || $0.value == 127}
    }
    private static func identifier(_ text:String) -> Bool {
        !text.isEmpty && text.utf8.count <= 160 && text.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 || $0 == 46
        }
    }
}
