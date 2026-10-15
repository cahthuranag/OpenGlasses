import Foundation

/// The source store owns cancellation as well as bytes. Every mutation is serialized, and a
/// tombstone is durable before files disappear: a suspended OCR callback cannot resurrect it.
/// Expensive recognition/encoding happens outside this lock, on the assembler's worker.
final class CapturedManualStore: @unchecked Sendable {
    private final class Shared: @unchecked Sendable {
        let lock = NSLock()
        var store: CapturedManualStore?
    }
    private static let sharedStorage = Shared()
    static var shared: CapturedManualStore? {
        sharedStorage.lock.lock(); defer { sharedStorage.lock.unlock() }
        if let store = sharedStorage.store { return store }
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("CapturedManuals")
        let store = try? CapturedManualStore(root: root)
        sharedStorage.store = store
        return store
    }
    typealias C = CapturedManualContract
    struct Limits: Sendable {
        var pages = 40
        var imageBytes = C.maximumImageBytes
        var storedBytes = 512 * 1_024 * 1_024
        var freeReserve = 32 * 1_024 * 1_024
    }
    struct Metadata: Codable, Equatable, Sendable {
        let captureID: String
        let revision: Int64
        let sessionID: String
        let jobReference: String
        let jobID: String
        let jobRevision: Int64
        let scope: C.Scope
        let unitID: String
        let statedModel: String
        let confirmedModelToken: String
        let serial: String
        let title: String
        let author: String
        let capturedAt: Int64
        let policy: String
        let poolIntent: String
        var conversationThreadID: String? = nil
        var key: String { "\(captureID):\(revision)" }
    }
    struct Image: Codable, Equatable, Sendable {
        let digest: String
        let bytes: Int
    }
    struct Recognized: Codable, Equatable, Sendable {
        let imageDigest: String
        let settingsDigest: String
        let text: String
        let confidenceMilli: Int
        let printedPage: Int
        let failed: Bool
        let redactions: [C.Redaction]
    }
    struct Draft: Codable, Equatable, Sendable {
        let metadata: Metadata
        let languages: [String]
        let languageFallback: Bool
        let encoderVersion: String
        let metadataRedactions: [C.Redaction]
        var images: [Image] = []
        var recognized: [String: Recognized] = [:]
        var stagingComplete = false
        var settingsDigest: String {
            C.digest(Data(([encoderVersion] + languages + [String(languageFallback)] + images.map(\.digest)).joined(separator: "\n").utf8))
        }
    }
    private struct Journal: Codable {
        var current: [String: Int64] = [:]
        var threads: [String: String] = [:]
        var forgotten: Set<String> = []
        var superseded: Set<String> = []
    }
    enum Failure: Error, Equatable {
        case invalidRequest, unavailable, cancelled, limits, missingPage, incomplete, immutableConflict
    }
    let root: URL
    let limits: Limits
    private let lock = NSRecursiveLock()
    private var journal: Journal
    private let writeBytes: @Sendable (Data, URL) throws -> Void
    private let availableBytes: @Sendable () throws -> Int

    init(root: URL, limits: Limits = Limits(),
         availableBytes: @escaping @Sendable () throws -> Int = {
             let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
             let value = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
             guard let capacity = value.volumeAvailableCapacityForImportantUsage else { throw Failure.unavailable }
             return Int(clamping: capacity)
         }, writeBytes: @escaping @Sendable (Data, URL) throws -> Void = { data, url in
             #if os(iOS)
             try data.write(to: url, options: [.atomic, .completeFileProtection])
             #else
             try data.write(to: url, options: .atomic)
             #endif
         }) throws {
        guard limits.pages > 0, limits.pages <= C.maximumPages, limits.imageBytes > 0,
              limits.imageBytes <= C.maximumImageBytes, limits.storedBytes > 0,
              limits.storedBytes <= 8 * C.maximumPDFBytes, limits.freeReserve >= 0,
              limits.freeReserve <= 8 * C.maximumPDFBytes else { throw Failure.invalidRequest }
        self.root = root
        self.limits = limits
        self.writeBytes = writeBytes
        self.availableBytes = availableBytes
        let file = root.appendingPathComponent("journal.json")
        if FileManager.default.fileExists(atPath: file.path) {
            // A corrupt/unreadable journal never means an empty store with no tombstones.
            journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: file))
        } else { journal = Journal() }
        try makeDirectory(root)
    }

    func begin(_ metadata: Metadata, languages: [String], fallback: Bool,
               encoderVersion: String = "jpeg-2200-q80-pdf-v1") throws -> Draft {
        try locked {
            guard Self.identifier(metadata.captureID), Self.identifier(metadata.sessionID), metadata.revision > 0,
                  metadata.revision <= C.maximumSafeInteger, !languages.isEmpty, languages.count <= 16,
                  Set(languages).count == languages.count, languages.allSatisfy(Self.identifier),
                  Self.identifier(encoderVersion), !journal.forgotten.contains(metadata.captureID),
                  !journal.superseded.contains(metadata.key), metadata.policy != "off" else { throw Failure.invalidRequest }
            let safe = Self.redacted(metadata)
            let draft = Draft(metadata: safe.metadata, languages: languages, languageFallback: fallback,
                              encoderVersion: encoderVersion, metadataRedactions: safe.redactions)
            let url = try draftDirectory(metadata.key)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("draft.json").path) {
                let previous = try load(metadata.key)
                guard previous.metadata == draft.metadata, previous.languages == languages,
                      previous.languageFallback == fallback, previous.encoderVersion == encoderVersion else { throw Failure.immutableConflict }
                return previous
            }
            guard !FileManager.default.fileExists(atPath: try finalDirectory(metadata).path) else { throw Failure.immutableConflict }
            try makeDirectory(url)
            try save(draft)
            return draft
        }
    }

    func appendImage(_ data: Data, to key: String) throws {
        try locked {
            var draft = try load(key)
            guard !draft.stagingComplete else { throw Failure.immutableConflict }
            guard draft.images.count < min(limits.pages, C.maximumPages), !data.isEmpty,
                  data.count <= min(limits.imageBytes, C.maximumImageBytes) else { throw Failure.limits }
            try checkSpace(data.count)
            let url = try imageURL(key, index: draft.images.count + 1)
            try write(data, to: url)
            draft.images.append(Image(digest: C.digest(data), bytes: data.count))
            try save(draft)
        }
    }

    func finishStaging(_ key: String) throws {
        try locked {
            var draft = try load(key)
            guard !draft.images.isEmpty else { throw Failure.incomplete }
            draft.stagingComplete = true
            try save(draft)
        }
    }
    func load(_ key: String) throws -> Draft {
        try locked {
            let url = try draftDirectory(key).appendingPathComponent("draft.json")
            let draft = try JSONDecoder().decode(Draft.self, from: boundedData(url, maximum: C.maximumTextBytes + C.maximumManifestBytes))
            guard draft.metadata.key == key, !journal.forgotten.contains(draft.metadata.captureID),
                  !journal.superseded.contains(key) else { throw Failure.cancelled }
            return draft
        }
    }
    func pending() throws -> [Draft] {
        try locked {
            let staging = root.appendingPathComponent("staging")
            guard FileManager.default.fileExists(atPath: staging.path) else { return [] }
            return try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
                .compactMap { url -> Draft? in
                    let parts = url.lastPathComponent.split(separator: ":")
                    guard parts.count == 2, !journal.forgotten.contains(String(parts[0])),
                          !journal.superseded.contains(url.lastPathComponent) else { return nil }
                    return try load(url.lastPathComponent)
                }
        }
    }
    func image(_ key: String, index: Int) throws -> Data {
        try locked {
            let draft = try load(key)
            guard draft.images.indices.contains(index - 1) else { throw Failure.missingPage }
            let data = try boundedData(imageURL(key, index: index), maximum: C.maximumImageBytes)
            let expected = draft.images[index - 1]
            guard data.count == expected.bytes, C.digest(data) == expected.digest else { throw Failure.missingPage }
            return data
        }
    }
    func checkpoint(_ result: Recognized, key: String, page: Int) throws {
        try locked {
            var draft = try load(key)
            guard draft.stagingComplete, draft.images.indices.contains(page - 1),
                  result.imageDigest == draft.images[page - 1].digest,
                  result.settingsDigest == draft.settingsDigest,
                  result.text.utf8.count <= C.maximumTextBytes,
                  !SecretPatterns.containsSensitive(result.text) else { throw Failure.invalidRequest }
            draft.recognized[String(page)] = result
            guard draft.recognized.values.reduce(0, { $0 + $1.text.utf8.count }) <= C.maximumTextBytes else { throw Failure.limits }
            try save(draft)
        }
    }
    func pdf(_ key: String) throws -> Data? {
        try locked {
            _ = try load(key)
            let url = try draftDirectory(key).appendingPathComponent("pages.pdf")
            return FileManager.default.fileExists(atPath: url.path) ? try boundedData(url, maximum: C.maximumPDFBytes) : nil
        }
    }
    func keepPDF(_ data: Data, key: String) throws {
        try locked {
            let draft = try load(key)
            guard draft.stagingComplete, !data.isEmpty, data.count <= C.maximumPDFBytes else { throw Failure.limits }
            if let existing = try pdf(key) {
                guard existing == data else { throw Failure.immutableConflict }
                return
            }
            try checkSpace(data.count)
            try write(data, to: draftDirectory(key).appendingPathComponent("pages.pdf"))
        }
    }
    /// Files become selectable only after the complete validated revision and current-selection
    /// journal are durable. A crash between rename and selection is recoverable from staging.
    func commit(_ key: String, manifest: Data, text: Data, pdfPageCount: Int) throws -> C.Manifest {
        try locked {
            let draft = try load(key)
            guard draft.stagingComplete, draft.recognized.count == draft.images.count,
                  let pdf = try pdf(key) else { throw Failure.incomplete }
            let m = try C.validate(manifest, text: text, pdf: pdf, pdfPageCount: pdfPageCount, expectedScope: draft.metadata.scope)
            guard m.captureID == draft.metadata.captureID, m.captureRevision == draft.metadata.revision,
                  m.sessionID == draft.metadata.sessionID,
                  m.jobReference == draft.metadata.jobReference, m.jobID == draft.metadata.jobID,
                  m.jobRevision == draft.metadata.jobRevision, m.unitID == draft.metadata.unitID,
                  m.statedModel == draft.metadata.statedModel, m.confirmedModelToken == draft.metadata.confirmedModelToken,
                  m.serial == draft.metadata.serial, m.title == draft.metadata.title, m.author == draft.metadata.author,
                  m.capturedAt == draft.metadata.capturedAt, m.capturePolicy == draft.metadata.policy,
                  m.poolIntent == draft.metadata.poolIntent, m.recognitionLanguages == draft.languages,
                  m.recognitionFallback == draft.languageFallback, m.encoderVersion == draft.encoderVersion,
                  m.pages.count == draft.images.count,
                  zip(m.pages, draft.images).allSatisfy({ $0.imageSHA256 == $1.digest && $0.imageBytes == $1.bytes })
            else { throw Failure.invalidRequest }
            let target = try finalDirectory(draft.metadata)
            if FileManager.default.fileExists(atPath: target.path) {
                guard try boundedData(target.appendingPathComponent("manifest.json"), maximum: C.maximumManifestBytes) == manifest,
                      try boundedData(target.appendingPathComponent("text.md"), maximum: C.maximumTextBytes) == text,
                      try boundedData(target.appendingPathComponent("pages.pdf"), maximum: C.maximumPDFBytes) == pdf else { throw Failure.immutableConflict }
            } else {
                try checkSpace(text.count + pdf.count + manifest.count)
                let temporary = root.appendingPathComponent("sealing").appendingPathComponent(key)
                if FileManager.default.fileExists(atPath: temporary.path) { try FileManager.default.removeItem(at: temporary) }
                try makeDirectory(temporary)
                defer { try? FileManager.default.removeItem(at: temporary) }
                try write(text, to: temporary.appendingPathComponent("text.md"))
                try write(pdf, to: temporary.appendingPathComponent("pages.pdf"))
                try write(manifest, to: temporary.appendingPathComponent("manifest.json"))
                try makeDirectory(target.deletingLastPathComponent())
                try FileManager.default.moveItem(at: temporary, to: target)
            }
            var next = journal
            if let old = next.current[m.captureID], old != m.captureRevision {
                guard old < m.captureRevision else { throw Failure.immutableConflict }
                next.superseded.insert("\(m.captureID):\(old)")
            }
            next.current[m.captureID] = m.captureRevision
            next.threads[m.documentID] = draft.metadata.conversationThreadID
            try saveJournal(next)
            try? FileManager.default.removeItem(at: draftDirectory(key))
            return m
        }
    }
    func manifests(currentOnly: Bool = true) throws -> [C.Manifest] {
        try locked {
            var result: [C.Manifest] = []
            if !currentOnly {
                // Erasure includes retained historical revisions and files whose deletion was
                // interrupted after their tombstone was saved.
                for folder in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
                where Self.identifier(folder.lastPathComponent) && folder.lastPathComponent != "staging"
                    && folder.lastPathComponent != "sealing" {
                    guard try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
                    for revision in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                    where Int64(revision.lastPathComponent) != nil {
                        let file = revision.appendingPathComponent("manifest.json")
                        result.append(try C.read(boundedData(file, maximum: C.maximumManifestBytes)))
                    }
                }
                return result
            }
            for (id, revision) in journal.current where !journal.forgotten.contains(id) {
                let key = "\(id):\(revision)"
                if currentOnly && journal.superseded.contains(key) { continue }
                let url = root.appendingPathComponent(id).appendingPathComponent(String(revision)).appendingPathComponent("manifest.json")
                result.append(try C.read(boundedData(url, maximum: C.maximumManifestBytes)))
            }
            return result.sorted { $0.capturedAt > $1.capturedAt }
        }
    }
    func file(_ m: C.Manifest, name: String) throws -> URL {
        try locked {
            guard ["pages.pdf", "text.md", "manifest.json"].contains(name), !journal.forgotten.contains(m.captureID) else { throw Failure.cancelled }
            let folder = try revisionDirectory(id: m.captureID, revision: m.captureRevision)
            let bytes = try boundedData(folder.appendingPathComponent("manifest.json"), maximum: C.maximumManifestBytes)
            guard try C.canonicalBytes(m) == bytes else { throw Failure.immutableConflict }
            let url = folder.appendingPathComponent(name)
            if name == "pages.pdf" || name == "text.md" {
                let data = try boundedData(url, maximum: name == "pages.pdf" ? C.maximumPDFBytes : C.maximumTextBytes)
                guard C.digest(data) == (name == "pages.pdf" ? m.pdfSHA256 : m.textSHA256) else { throw Failure.missingPage }
            }
            return url
        }
    }
    func supersede(id: String, revision: Int64, digest: String) throws {
        try locked {
            let url = try revisionDirectory(id: id, revision: revision).appendingPathComponent("manifest.json")
            let bytes = try boundedData(url, maximum: C.maximumManifestBytes)
            guard C.digest(bytes) == digest else { throw Failure.immutableConflict }
            var next = journal; next.superseded.insert("\(id):\(revision)"); try saveJournal(next)
        }
    }
    /// Capture-level forgetting removes every source revision, incomplete work and metadata.
    /// The content-free capture tombstone survives; derivations are retracted by the coordinator.
    func forget(_ id: String) throws {
        try locked {
            guard Self.identifier(id) else { throw Failure.invalidRequest }
            var next = journal; next.forgotten.insert(id); next.current[id] = nil
            next.threads = next.threads.filter { !$0.key.hasPrefix("captured:" + id + ":") }
            try saveJournal(next)
            let folder = root.appendingPathComponent(id)
            if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
            for directory in ["staging", "sealing"] {
                let staging = root.appendingPathComponent(directory)
                if FileManager.default.fileExists(atPath: staging.path) {
                    for url in try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
                    where url.lastPathComponent.hasPrefix(id + ":") { try FileManager.default.removeItem(at: url) }
                }
            }
        }
    }
    @discardableResult
    func deleteMatching(_ matches: (Metadata, String) -> Bool) throws -> Int {
        try locked {
            var ids = Set<String>()
            for m in try manifests(currentOnly: false) {
                let textURL = try revisionDirectory(id: m.captureID, revision: m.captureRevision).appendingPathComponent("text.md")
                let text = String(decoding: try boundedData(textURL, maximum: C.maximumTextBytes), as: UTF8.self)
                let metadata = Metadata(captureID: m.captureID, revision: m.captureRevision, sessionID: m.sessionID,
                    jobReference: m.jobReference, jobID: m.jobID, jobRevision: m.jobRevision, scope: m.scope,
                    unitID: m.unitID, statedModel: m.statedModel, confirmedModelToken: m.confirmedModelToken,
                    serial: m.serial, title: m.title, author: m.author, capturedAt: m.capturedAt,
                    policy: m.capturePolicy, poolIntent: m.poolIntent, conversationThreadID: journal.threads[m.documentID])
                if matches(metadata, text) { ids.insert(m.captureID) }
            }
            for draft in try pending() {
                if matches(draft.metadata, draft.recognized.values.map(\.text).joined(separator: "\n")) { ids.insert(draft.metadata.captureID) }
            }
            for id in ids { try forget(id) }
            return ids.count
        }
    }

    func removeAll() throws {
        _ = try deleteMatching { _, _ in true }
    }

    private func checkSpace(_ adding: Int) throws {
        guard adding >= 0, adding <= limits.storedBytes, try availableBytes() >= limits.freeReserve + adding else { throw Failure.limits }
        var total = 0
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values.isRegularFile == true { total += values.fileSize ?? 0 }
                guard total <= limits.storedBytes - adding else { throw Failure.limits }
            }
        }
    }
    private func save(_ draft: Draft) throws {
        try write(JSONEncoder().encode(draft), to: draftDirectory(draft.metadata.key).appendingPathComponent("draft.json"))
    }
    private func saveJournal(_ next: Journal) throws {
        try write(JSONEncoder().encode(next), to: root.appendingPathComponent("journal.json")); journal = next
    }
    private func write(_ data: Data, to url: URL) throws {
        try checkSpace(data.count)
        try writeBytes(data, url); try protect(url)
    }
    private func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); try protect(url)
    }
    private func protect(_ url: URL) throws {
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        #endif
        var url = url; var values = URLResourceValues(); values.isExcludedFromBackup = true; try url.setResourceValues(values)
    }
    private func boundedData(_ url: URL, maximum: Int) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= maximum else { throw Failure.limits }
        let bytes = try Data(contentsOf: url); guard bytes.count <= maximum else { throw Failure.limits }; return bytes
    }
    private func draftDirectory(_ key: String) throws -> URL {
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, Self.identifier(String(parts[0])), let revision = Int64(parts[1]),
              revision > 0, revision <= C.maximumSafeInteger, String(revision) == parts[1] else { throw Failure.invalidRequest }
        return root.appendingPathComponent("staging").appendingPathComponent(key)
    }
    private func revisionDirectory(id: String, revision: Int64) throws -> URL {
        guard Self.identifier(id), revision > 0, revision <= C.maximumSafeInteger else { throw Failure.invalidRequest }
        return root.appendingPathComponent(id).appendingPathComponent(String(revision))
    }
    private func finalDirectory(_ metadata: Metadata) throws -> URL { try revisionDirectory(id: metadata.captureID, revision: metadata.revision) }
    private func imageURL(_ key: String, index: Int) throws -> URL { try draftDirectory(key).appendingPathComponent("page-\(index).jpg") }
    private func locked<T>(_ body: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try body() }
    private static func identifier(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= 80 && s != "." && s != ".." && s.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,95].contains($0)
        }
    }
    private static func redacted(_ m: Metadata) -> (metadata: Metadata, redactions: [C.Redaction]) {
        var counts: [String: Int] = [:]
        func clean(_ text: String) -> String {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for p in SecretPatterns.all { counts[p.name, default: 0] += p.regex.numberOfMatches(in: text, range: range) }
            return SecretPatterns.redact(text).redacted
        }
        let safe = Metadata(captureID:m.captureID, revision:m.revision, sessionID:m.sessionID,
            jobReference:clean(m.jobReference), jobID:m.jobID, jobRevision:m.jobRevision, scope:m.scope,
            unitID:m.unitID, statedModel:clean(m.statedModel), confirmedModelToken:clean(m.confirmedModelToken),
            serial:clean(m.serial), title:clean(m.title), author:clean(m.author), capturedAt:m.capturedAt,
            policy:m.policy, poolIntent:m.poolIntent, conversationThreadID:m.conversationThreadID)
        return (safe, counts.filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { C.Redaction(pattern:$0.key, count:$0.value) })
    }
}
