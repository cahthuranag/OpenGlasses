import CryptoKit
import Foundation

/// Plan IF P0: immutable source bytes only. No capture, indexing, entitlement or delivery caller.
/// See Contracts/captured-manual.md. The caller supplies its independently established scope
/// and the physical PDF page count; accepting a manifest grants no permission to publish it.
enum CapturedManualContract {
    static let kind = "avenkin.captured-manual"
    static let maximumManifestBytes = 131_072
    static let maximumPages = 256
    static let maximumTextBytes = 8_388_608
    static let maximumPDFBytes = 134_217_728
    static let maximumImageBytes = 4_194_304
    static let maximumSafeInteger: Int64 = 9_007_199_254_740_991

    struct Scope: Codable, Equatable, Sendable {
        let ownershipScope: String
        let organizationID: String
        let enrolmentID: String
        let vaultID: String
    }

    struct Page: Codable, Equatable, Sendable {
        let index: Int
        let imageSHA256: String
        let imageBytes: Int
        let textOffset: Int
        let textBytes: Int
        /// Integer thousandths, avoiding platform-dependent floating point encodings.
        let confidenceMilli: Int
        /// Zero means unknown; never inferred from the capture index.
        let printedPage: Int
        let ocrStatus: String
    }

    struct Redaction: Codable, Equatable, Sendable {
        let pattern: String
        let count: Int
    }

    struct Manifest: Codable, Equatable, Sendable {
        let version: Int
        let kind: String
        let captureID: String
        let captureRevision: Int64
        let sessionID: String
        let jobReference: String
        let jobID: String
        let jobRevision: Int64
        let vaultID: String
        let ownershipScope: String
        let organizationID: String
        let enrolmentID: String
        let unitID: String
        let statedModel: String
        /// Confirmed exact identity only. Never a near/partial vault match or a serial.
        let confirmedModelToken: String
        let serial: String
        let title: String
        let author: String
        let capturedAt: Int64
        let capturePolicy: String
        let poolIntent: String
        let encoderVersion: String
        let pageCount: Int
        let ocrPages: Int
        let failedPages: Int
        let lowConfidencePages: Int
        let recognitionLanguages: [String]
        let recognitionFallback: Bool
        let pages: [Page]
        let redactions: [Redaction]
        let textSHA256: String
        let textBytes: Int
        let pdfSHA256: String
        let pdfBytes: Int

        var scope: Scope {
            Scope(ownershipScope: ownershipScope, organizationID: organizationID,
                  enrolmentID: enrolmentID, vaultID: vaultID)
        }

        /// Stable across sends. Delivery revision is a separate OfficeReport counter.
        var documentID: String { "captured:\(captureID):\(captureRevision)" }
    }

    enum Refusal: Error, Equatable {
        case malformed, invalidFields, wrongScope, alteredContent, invalidPages
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Canonical JSON, fixed member order, raw UTF-8, no slash/HTML escaping. All control
    /// characters use lower-case six-byte unicode escapes, including LF/TAB. No normalization.
    static func canonicalBytes(_ m: Manifest) throws -> Data {
        guard valid(m) else { throw Refusal.invalidFields }
        func s(_ key: String, _ value: String) -> String { "\"\(key)\":" + quoted(value) }
        func n<T: BinaryInteger>(_ key: String, _ value: T) -> String { "\"\(key)\":\(value)" }
        let pages = m.pages.map { p in
            "{" + [n("index", p.index), s("imageSHA256", p.imageSHA256), n("imageBytes", p.imageBytes),
                   n("textOffset", p.textOffset), n("textBytes", p.textBytes),
                   n("confidenceMilli", p.confidenceMilli), n("printedPage", p.printedPage),
                   s("ocrStatus", p.ocrStatus)].joined(separator: ",") + "}"
        }
        let redactions = m.redactions.map { r in
            "{" + [s("pattern", r.pattern), n("count", r.count)].joined(separator: ",") + "}"
        }
        let members = [
            n("version", m.version), s("kind", m.kind), s("captureID", m.captureID),
            n("captureRevision", m.captureRevision), s("sessionID", m.sessionID), s("jobReference", m.jobReference),
            s("jobID", m.jobID), n("jobRevision", m.jobRevision), s("vaultID", m.vaultID),
            s("ownershipScope", m.ownershipScope), s("organizationID", m.organizationID), s("enrolmentID", m.enrolmentID),
            s("unitID", m.unitID), s("statedModel", m.statedModel), s("confirmedModelToken", m.confirmedModelToken),
            s("serial", m.serial), s("title", m.title), s("author", m.author), n("capturedAt", m.capturedAt),
            s("capturePolicy", m.capturePolicy), s("poolIntent", m.poolIntent), s("encoderVersion", m.encoderVersion),
            n("pageCount", m.pageCount), n("ocrPages", m.ocrPages), n("failedPages", m.failedPages),
            n("lowConfidencePages", m.lowConfidencePages),
            "\"recognitionLanguages\":[" + m.recognitionLanguages.map(quoted).joined(separator: ",") + "]",
            "\"recognitionFallback\":\(m.recognitionFallback ? "true" : "false")",
            "\"pages\":[" + pages.joined(separator: ",") + "]",
            "\"redactions\":[" + redactions.joined(separator: ",") + "]",
            s("textSHA256", m.textSHA256), n("textBytes", m.textBytes), s("pdfSHA256", m.pdfSHA256), n("pdfBytes", m.pdfBytes),
        ]
        let bytes = Data(("{" + members.joined(separator: ",") + "}").utf8)
        guard bytes.count <= maximumManifestBytes else { throw Refusal.invalidFields }
        return bytes
    }

    /// Re-encoding rejects duplicate, unknown, missing, reordered, escaped and fractional
    /// spellings, including inside arrays. The input is bounded before decoding.
    static func read(_ bytes: Data) throws -> Manifest {
        guard !bytes.isEmpty, bytes.count <= maximumManifestBytes,
              let m = try? JSONDecoder().decode(Manifest.self, from: bytes) else { throw Refusal.malformed }
        let canonical = try canonicalBytes(m)
        guard bytes == canonical else { throw Refusal.malformed }
        return m
    }

    static func validate(_ bytes: Data, text: Data, pdf: Data, pdfPageCount: Int,
                         expectedScope: Scope) throws -> Manifest {
        let m = try read(bytes)
        guard m.scope == expectedScope else { throw Refusal.wrongScope }
        guard text.count == m.textBytes, digest(text) == m.textSHA256,
              pdf.count == m.pdfBytes, digest(pdf) == m.pdfSHA256 else { throw Refusal.alteredContent }
        guard pdfPageCount == m.pageCount, String(data: text, encoding: .utf8) != nil else { throw Refusal.invalidPages }
        // Exact markdown furniture and separators leave no unaccounted text (including secrets)
        // between page ranges. UTF-8 boundaries are checked independently of the declared digest.
        var offset = 0
        for p in m.pages {
            let header = Data("## Page \(p.index)\n\n".utf8)
            guard offset + header.count == p.textOffset,
                  text.subdata(in: offset..<p.textOffset) == header else { throw Refusal.invalidPages }
            let end = p.textOffset + p.textBytes
            guard String(data: text.subdata(in: p.textOffset..<end), encoding: .utf8) != nil,
                  end + 2 <= text.count, text.subdata(in: end..<(end + 2)) == Data([10, 10]) else {
                throw Refusal.invalidPages
            }
            offset = end + 2
        }
        guard offset == text.count else { throw Refusal.invalidPages }
        return m
    }

    private static func valid(_ m: Manifest) -> Bool {
        guard m.version == 1, m.kind == kind, identifier(m.captureID), identifier(m.sessionID),
              positive(m.captureRevision), positive(m.capturedAt), identifier(m.vaultID),
              optionalIdentifier(m.unitID), display(m.jobReference, maximum: 120),
              (m.jobID.isEmpty && m.jobRevision == 0) || (identifier(m.jobID) && positive(m.jobRevision)),
              (m.ownershipScope == "personal" && m.organizationID.isEmpty && m.enrolmentID.isEmpty)
                || (m.ownershipScope == "organization" && identifier(m.organizationID) && identifier(m.enrolmentID)),
              display(m.statedModel, maximum: 160), display(m.confirmedModelToken, maximum: 160),
              m.confirmedModelToken.isEmpty || !m.statedModel.isEmpty,
              display(m.serial, maximum: 160), !m.title.isEmpty, display(m.title, maximum: 240),
              display(m.author, maximum: 160), identifier(m.encoderVersion),
              ["jobOnly", "reviewToPool"].contains(m.capturePolicy),
              ["jobOnly", "reviewToPool"].contains(m.poolIntent),
              m.poolIntent != "reviewToPool" || (m.capturePolicy == "reviewToPool" && m.ownershipScope == "organization"),
              (1...maximumPages).contains(m.pageCount), m.pages.count == m.pageCount,
              m.ocrPages >= 0, m.failedPages >= 0, m.ocrPages <= m.pageCount, m.failedPages <= m.pageCount,
              m.ocrPages + m.failedPages == m.pageCount,
              m.lowConfidencePages >= 0, m.lowConfidencePages <= m.pageCount,
              !m.recognitionLanguages.isEmpty, m.recognitionLanguages.count <= 16,
              m.recognitionLanguages.allSatisfy(identifier), Set(m.recognitionLanguages).count == m.recognitionLanguages.count,
              hex(m.textSHA256), hex(m.pdfSHA256), (1...maximumTextBytes).contains(m.textBytes),
              (1...maximumPDFBytes).contains(m.pdfBytes), m.redactions.count <= 64 else { return false }
        var end = 0
        var recognized = 0
        var low = 0
        for (index, p) in m.pages.enumerated() {
            guard p.index == index + 1, hex(p.imageSHA256), (1...maximumImageBytes).contains(p.imageBytes),
                  p.textOffset >= end, p.textOffset <= m.textBytes, p.textBytes >= 0,
                  p.textBytes <= m.textBytes - p.textOffset, (0...1000).contains(p.confidenceMilli),
                  (0...9999).contains(p.printedPage), ["recognized", "failed"].contains(p.ocrStatus),
                  p.ocrStatus != "failed" || (p.textBytes == 0 && p.confidenceMilli == 0 && p.printedPage == 0) else { return false }
            end = p.textOffset + p.textBytes
            if p.ocrStatus == "recognized" { recognized += 1 }
            if p.confidenceMilli < 500 { low += 1 }
        }
        guard recognized == m.ocrPages, low == m.lowConfidencePages else { return false }
        for (i, r) in m.redactions.enumerated() {
            guard identifier(r.pattern), r.count > 0, r.count <= 1_000_000,
                  i == 0 || m.redactions[i - 1].pattern < r.pattern else { return false }
        }
        return true
    }

    private static func quoted(_ value: String) -> String {
        var out = "\""
        for c in value.unicodeScalars {
            switch c.value {
            case 0...31: out += String(format: "\\u%04x", c.value)
            case 34: out += "\\\""
            case 92: out += "\\\\"
            default: out.unicodeScalars.append(c)
            }
        }
        return out + "\""
    }

    private static func identifier(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= 80 && s != "." && s != ".." && s.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0)
        }
    }
    private static func optionalIdentifier(_ s: String) -> Bool { s.isEmpty || identifier(s) }
    private static func positive(_ n: Int64) -> Bool { n > 0 && n <= maximumSafeInteger }
    private static func display(_ s: String, maximum: Int) -> Bool {
        s.utf8.count <= maximum && s.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value != 127 }
    }
    private static func hex(_ s: String) -> Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
