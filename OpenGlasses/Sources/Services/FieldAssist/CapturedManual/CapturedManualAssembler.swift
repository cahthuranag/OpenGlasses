import Foundation

/// Work is deliberately performed by a detached caller, never by the UI actor. No SDK/network
/// is involved. The production adapters and tests both use this persisted state machine.
struct CapturedManualAssembler: Sendable {
    typealias C = CapturedManualContract
    typealias S = CapturedManualStore
    struct Reading: Sendable {
        let text: String
        let confidence: Float
    }
    let store: S
    let read: @Sendable (Data, [String], Bool) async throws -> Reading
    /// Takes verified normalised image bytes one page at a time through the supplied accessor.
    let makePDF: @Sendable (S.Draft, @Sendable (Int) throws -> Data) throws -> Data
    let pageCount: @Sendable (Data) throws -> Int
    var allowed: @Sendable (S.Metadata) async -> Bool = { _ in true }
    var progress: @Sendable (Int, Int) async -> Void = { _, _ in }

    func assemble(_ key: String) async throws -> C.Manifest {
        var draft = try store.load(key)
        guard draft.stagingComplete else { throw S.Failure.incomplete }
        guard await allowed(draft.metadata) else { throw S.Failure.unavailable }
        // Persist the PDF before the first recognition call. Resuming OCR reuses its exact bytes
        // rather than trusting the current clock or encoder defaults to reproduce it.
        if try store.pdf(key) == nil {
            let pdf = try makePDF(draft) { index in try store.image(key, index: index) }
            try Task.checkCancellation()
            guard await allowed(draft.metadata) else { throw S.Failure.unavailable }
            try store.keepPDF(pdf, key: key)
        }
        for index in 1...draft.images.count {
            try Task.checkCancellation()
            guard await allowed(draft.metadata) else { throw S.Failure.unavailable }
            draft = try store.load(key)
            if let saved = draft.recognized[String(index)], saved.imageDigest == draft.images[index - 1].digest,
               saved.settingsDigest == draft.settingsDigest {
                await progress(index, draft.images.count)
                continue
            }
            let result: Reading
            let failed: Bool
            do {
                result = try await read(store.image(key, index: index), draft.languages, draft.languageFallback)
                failed = false
            } catch is CancellationError { throw CancellationError() }
            catch { result = Reading(text: "", confidence: 0); failed = true }
            try Task.checkCancellation()
            guard await allowed(draft.metadata) else { throw S.Failure.unavailable }
            guard result.text.utf8.count <= C.maximumTextBytes else { throw S.Failure.limits }
            let safe = Self.redact(result.text)
            let confidence = result.confidence.isFinite ? Int((min(1, max(0, result.confidence)) * 1000).rounded(.down)) : 0
            let page = S.Recognized(imageDigest: draft.images[index - 1].digest, settingsDigest: draft.settingsDigest,
                text: safe.text, confidenceMilli: failed ? 0 : confidence,
                printedPage: failed ? 0 : PrintedPageNumberFinder.find(in: safe.text) ?? 0,
                failed: failed, redactions: safe.redactions)
            try store.checkpoint(page, key: key, page: index)
            await progress(index, draft.images.count)
            await Task.yield()
        }
        draft = try store.load(key)
        let (manifest, text) = try bundle(draft)
        try Task.checkCancellation()
        guard await allowed(draft.metadata) else { throw S.Failure.unavailable }
        return try store.commit(key, manifest: C.canonicalBytes(manifest), text: text,
                                pdfPageCount: pageCount(try requiredPDF(key)))
    }

    private func requiredPDF(_ key: String) throws -> Data {
        guard let pdf = try store.pdf(key) else { throw S.Failure.incomplete }; return pdf
    }
    private func bundle(_ draft: S.Draft) throws -> (C.Manifest, Data) {
        var text = Data()
        var pages: [C.Page] = []
        var counts: [String: Int] = [:]
        for r in draft.metadataRedactions { counts[r.pattern, default: 0] += r.count }
        for (i, image) in draft.images.enumerated() {
            guard let p = draft.recognized[String(i + 1)], p.imageDigest == image.digest,
                  p.settingsDigest == draft.settingsDigest else { throw S.Failure.incomplete }
            text.append(Data("## Page \(i + 1)\n\n".utf8))
            pages.append(C.Page(index:i+1, imageSHA256:image.digest, imageBytes:image.bytes,
                textOffset:text.count, textBytes:p.text.utf8.count, confidenceMilli:p.confidenceMilli,
                printedPage:p.printedPage, ocrStatus:p.failed ? "failed" : "recognized"))
            text.append(Data(p.text.utf8)); text.append(Data([10,10]))
            guard text.count <= C.maximumTextBytes else { throw S.Failure.limits }
            for r in p.redactions { counts[r.pattern, default: 0] += r.count }
        }
        let m = draft.metadata
        let pdf = try requiredPDF(m.key)
        let manifest = C.Manifest(version:1, kind:C.kind, captureID:m.captureID, captureRevision:m.revision,
            sessionID:m.sessionID, jobReference:m.jobReference, jobID:m.jobID, jobRevision:m.jobRevision,
            vaultID:m.scope.vaultID, ownershipScope:m.scope.ownershipScope, organizationID:m.scope.organizationID,
            enrolmentID:m.scope.enrolmentID, unitID:m.unitID, statedModel:m.statedModel,
            confirmedModelToken:m.confirmedModelToken, serial:m.serial, title:m.title, author:m.author,
            capturedAt:m.capturedAt, capturePolicy:m.policy, poolIntent:m.poolIntent, encoderVersion:draft.encoderVersion,
            pageCount:pages.count, ocrPages:pages.filter { $0.ocrStatus == "recognized" }.count,
            failedPages:pages.filter { $0.ocrStatus == "failed" }.count,
            lowConfidencePages:pages.filter { $0.confidenceMilli < 500 }.count,
            recognitionLanguages:draft.languages, recognitionFallback:draft.languageFallback, pages:pages,
            redactions:counts.sorted { $0.key < $1.key }.map { C.Redaction(pattern:$0.key,count:$0.value) },
            textSHA256:C.digest(text), textBytes:text.count, pdfSHA256:C.digest(pdf), pdfBytes:pdf.count)
        return (manifest, text)
    }
    private static func redact(_ text: String) -> (text: String, redactions: [C.Redaction]) {
        let range = NSRange(text.startIndex..<text.endIndex, in:text)
        let redactions = SecretPatterns.all.compactMap { p -> C.Redaction? in
            let count = p.regex.numberOfMatches(in:text, range:range)
            return count > 0 ? C.Redaction(pattern:p.name,count:count) : nil
        }.sorted { $0.pattern < $1.pattern }
        return (SecretPatterns.redact(text).redacted, redactions)
    }
}

enum PrintedPageNumberFinder {
    static func find(in text: String) -> Int? {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in:.whitespaces) }
        let edges = Array(lines.prefix(1)) + Array(lines.suffix(1))
        let regex = try! NSRegularExpression(pattern:#"(?i)^(?:page\s+)?(?:[—–-]\s*)?([0-9]{1,3})(?:\s*[—–-])?$"#)
        let numbers = Set(edges.compactMap { line -> Int? in
            let range = NSRange(line.startIndex..<line.endIndex, in:line)
            guard let match = regex.firstMatch(in:line, range:range), let r = Range(match.range(at:1),in:line),
                  let number = Int(line[r]), number > 0 else { return nil }
            return number
        })
        return numbers.count == 1 ? numbers.first : nil
    }
}

/// Device/vault preferences resolve to Vision's actual supported identifiers. The production
/// reader receives these exact values; unrelated OCR callers keep their automatic defaults.
struct CapturedManualLanguages: Equatable, Sendable {
    let identifiers: [String]
    let fallback: Bool
    static func resolve(preferred: [String], supported: [String]) -> Self {
        func normal(_ s: String) -> String { s.replacingOccurrences(of:"_",with:"-").lowercased() }
        var values: [String] = []
        var fallback = false
        for language in preferred + ["en-US"] {
            let wanted = normal(language)
            let match = supported.first { normal($0) == wanted }
                ?? supported.first { normal($0).split(separator:"-").first == wanted.split(separator:"-").first }
            guard let match else { fallback = true; continue }
            if !values.contains(match) { values.append(match) }
        }
        // Vision normally supports English. If it doesn't, use supported automatic detection
        // explicitly; never invent an unsupported recognition identifier.
        if values.isEmpty, let first = supported.first { values = [first]; fallback = true }
        return Self(identifiers:values, fallback:fallback)
    }
}
