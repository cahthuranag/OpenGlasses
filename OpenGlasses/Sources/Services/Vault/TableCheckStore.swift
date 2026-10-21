import Foundation

/// Where the checks of a vault's pictured tables live, and how they reach a lookup (Plan JN P3).
///
/// - **A vault this phone authored** (imported from a folder on the phone, or a bundled one): the
///   checks made here are written into the vault's own `table-checks.json`, through the overlay
///   that holds every edit the phone makes to a vault (`Documents/Vaults/{id}/`, written
///   atomically, as the vault's other files are). The first write starts from the file the vault
///   was imported with; from then on that one file is the vault's checks. A later import of the
///   folder with a file in it is merged in (`mergeImported`), so a check from another phone or the
///   office lands beside this phone's and a disagreement shows.
/// - **A vault the phone did not author** (assigned by the organisation's office, received from a
///   link, or a signed pack): the folder is its publisher's and the phone never writes into it.
///   The phone's checks are kept in [[TableCheckStore]], keyed the same way, and merged with the
///   vault's own file when tables are loaded.
///
/// Every check reaches a lookup the same way: `checks(vaultId:)`, applied by [[TableChecks]].
enum VaultTableChecks {

    enum Home: Equatable {
        /// The vault's own `table-checks.json`.
        case vaultFile
        /// The phone's own store, beside a vault it may not write into.
        case phoneStore
    }

    /// Where this phone's checks of `vaultId` go.
    static func home(vaultId: String) -> Home {
        home(received: VaultImporter.receipt(for: vaultId) != nil,
             pack: VaultImporter.installedPack(for: vaultId) != nil,
             officeAssigned: officeAssignedVaultIds().contains(vaultId))
    }

    /// Pure: a vault received from anywhere — the office, a link, a signed pack — is not the
    /// phone's to write into.
    static func home(received: Bool, pack: Bool, officeAssigned: Bool) -> Home {
        received || pack || officeAssigned ? .phoneStore : .vaultFile
    }

    /// The vaults the organisation's office has installed on this phone.
    static func officeAssignedVaultIds() -> Set<String> {
        guard let file = OfficeManualService.defaultLedgerFile() else { return [] }
        return Set(OfficeManualService.readLedger(file).entries.filter { $0.state == .installed }.map(\.vaultID))
    }

    // MARK: Reading

    /// The vault's own file: the phone's copy when it has written one, else the one it was
    /// imported with.
    static func vaultFile(overlay: URL, baseline: URL?) -> TableChecksFile.Parsed {
        for directory in [overlay, baseline].compactMap({ $0 }) {
            let url = directory.appendingPathComponent(TableChecksFile.fileName)
            if let data = try? Data(contentsOf: url) { return TableChecksFile.parse(data) }
        }
        return TableChecksFile.Parsed()
    }

    /// Every check that applies to the vault's tables: its file's, and the phone's own store's
    /// when the vault is not the phone's to write into.
    static func checks(overlay: URL, baseline: URL?, home: Home, phoneStore: TableCheckStore,
                       vaultId: String) -> [TableCheck] {
        let file = vaultFile(overlay: overlay, baseline: baseline).checks
        guard home == .phoneStore else { return file }
        return TableChecks.merged(file, phoneStore.checks(vaultId: vaultId))
    }

    static func checks(vaultId: String) -> [TableCheck] {
        checks(overlay: VaultImporter.overlayDirectory(for: vaultId), baseline: baselineRoot(vaultId),
               home: home(vaultId: vaultId), phoneStore: TableCheckStore(), vaultId: vaultId)
    }

    /// The read-only root a vault was installed from: the app bundle for a built-in vault, else
    /// its imported baseline.
    static func baselineRoot(_ vaultId: String) -> URL? {
        if let bundled = Bundle.main.url(forResource: "Vaults/\(vaultId)", withExtension: nil) { return bundled }
        let imported = VaultImporter.baselineDirectory(for: vaultId)
        return FileManager.default.fileExists(atPath: imported.path) ? imported : nil
    }

    /// Each indexed document's table PDF hash, by document id, from the vault's ledger.
    static func documentHashes(_ ledger: VaultDocumentLedger) -> [String: String] {
        Dictionary(ledger.entries.map { ($0.documentId, $0.tablesHash) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Writing

    /// Record checks made on this phone, where this vault keeps them, in one write. Each replaces
    /// an earlier check of the same target there.
    static func record(_ checks: [TableCheck], vaultId: String, overlay: URL, baseline: URL?, home: Home,
                       phoneStore: TableCheckStore) throws {
        guard !checks.isEmpty else { return }
        switch home {
        case .vaultFile:
            let current = vaultFile(overlay: overlay, baseline: baseline).checks
            try writeVaultFile(checks.reduce(current) { TableChecks.recording($1, into: $0) }, overlay: overlay)
        case .phoneStore:
            try phoneStore.save(checks.reduce(phoneStore.checks(vaultId: vaultId)) { TableChecks.recording($1, into: $0) },
                                vaultId: vaultId)
        }
    }

    static func record(_ checks: [TableCheck], vaultId: String) throws {
        try record(checks, vaultId: vaultId, overlay: VaultImporter.overlayDirectory(for: vaultId),
                   baseline: baselineRoot(vaultId), home: home(vaultId: vaultId), phoneStore: TableCheckStore())
    }

    /// The vault's file as the phone writes it: atomically, beside its other files.
    static func writeVaultFile(_ checks: [TableCheck], overlay: URL) throws {
        try FileManager.default.createDirectory(at: overlay, withIntermediateDirectories: true)
        try TableChecksFile.encode(checks).write(to: overlay.appendingPathComponent(TableChecksFile.fileName),
                                                 options: .atomic)
    }

    /// A newly imported file joined to the checks this phone already wrote into the vault: both
    /// kept, so one that disagrees shows. Only when the phone has a copy of its own; otherwise the
    /// imported file is the vault's file as it is.
    static func mergeImported(_ imported: [TableCheck], overlay: URL) throws {
        let url = overlay.appendingPathComponent(TableChecksFile.fileName)
        guard let data = try? Data(contentsOf: url) else { return }
        let own = TableChecksFile.parse(data).checks
        try writeVaultFile(TableChecks.merged(own, imported), overlay: overlay)
    }

    /// Forget every check of the PDFs of `documentHashes`: the phone's store, and — for a vault the
    /// phone authored — the vault's own file, both the phone's copy and the one it was imported
    /// with. Returns how many went.
    @discardableResult
    static func forget(documentHashes: Set<String>, vaultId: String, overlay: URL, baseline: URL?,
                       home: Home, phoneStore: TableCheckStore) -> Int {
        guard !documentHashes.isEmpty else { return 0 }
        var removed = phoneStore.forget(documentHashes: documentHashes, vaultId: vaultId)
        guard home == .vaultFile else { return removed }
        for directory in [overlay, baseline].compactMap({ $0 }) {
            let url = directory.appendingPathComponent(TableChecksFile.fileName)
            guard let data = try? Data(contentsOf: url) else { continue }
            let checks = TableChecksFile.parse(data).checks
            let kept = TableChecks.forgetting(documentHashes: documentHashes, from: checks)
            guard kept.count != checks.count else { continue }
            removed += checks.count - kept.count
            try? writeVaultFile(kept, overlay: directory)
        }
        return removed
    }

    /// The checks of one PDF as a `table-checks.json` for the share sheet, in a fresh temporary
    /// folder. Nil when there are none.
    static func shareFile(_ checks: [TableCheck], documentHash: String) throws -> URL? {
        let mine = checks.filter { $0.documentHash == documentHash }
        guard !mine.isEmpty else { return nil }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TableChecks-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(TableChecksFile.fileName)
        try TableChecksFile.encode(mine).write(to: url, options: .atomic)
        return url
    }

    // MARK: Photographed manuals (Plan JN P4)

    /// The checks that apply to the tables of the manuals photographed against `vaultId`: the
    /// phone's own store, where checks of a photographed manual are always kept (it is the phone's
    /// own book and in no vault's folder), merged with the vault's checks, so a shared file brought
    /// back in through the vault is honoured too. A captured table is keyed by its revision's
    /// bundle digest, so no check of a vault manual can apply to it, nor one of its to a vault manual.
    static func capturedChecks(vaultId: String, phoneStore: TableCheckStore = TableCheckStore()) -> [TableCheck] {
        TableChecks.merged(checks(vaultId: vaultId), phoneStore.checks(vaultId: vaultId))
    }

    /// The checks a check view shows: a photographed manual's, or a vault manual's.
    static func checks(vaultId: String, photographed: Bool) -> [TableCheck] {
        photographed ? capturedChecks(vaultId: vaultId) : checks(vaultId: vaultId)
    }

    /// Record checks made on this phone: a photographed manual's in the phone's own store, a vault
    /// manual's where its vault keeps them.
    static func record(_ checks: [TableCheck], vaultId: String, photographed: Bool) throws {
        guard photographed else { return try record(checks, vaultId: vaultId) }
        try record(checks, vaultId: vaultId, overlay: VaultImporter.overlayDirectory(for: vaultId),
                   baseline: baselineRoot(vaultId), home: .phoneStore, phoneStore: TableCheckStore())
    }

    // MARK: At lookup time

    /// The vault's stored tables with its checks applied, as `table_lookup` and `rule_chain` read
    /// them; with `requireChecked`, a table read from a picture and not checked is withheld.
    static func applied(_ stored: [DocumentStore.StoredTable], checks: [TableCheck], hashes: [String: String],
                        requireChecked: Bool) -> [DocumentStore.StoredTable] {
        guard !checks.isEmpty || requireChecked else { return stored }
        return stored.map { entry in
            let table = TableChecks.apply(checks, to: entry.table, documentHash: hashes[entry.documentId],
                                          requireChecked: requireChecked).table
            return DocumentStore.StoredTable(documentId: entry.documentId, documentName: entry.documentName, table: table)
        }
    }

    /// The tables whose stored row passages must not be searched once checks are applied:
    /// `"documentId#label"` for a table read from a picture that is withheld, has a cell whose
    /// checks disagree, or has a cell corrected to something other than what was read — its
    /// passage still says what was read. Its values come from `table_lookup` only.
    static func rowPassagesWithheld(original: [DocumentStore.StoredTable],
                                    applied: [DocumentStore.StoredTable]) -> Set<String> {
        var out = Set<String>()
        for (before, after) in zip(original, applied) where after.table.source.isRecognised {
            let changed = zip(before.table.rows, after.table.rows).contains { old, new in
                zip(old.cells, new.cells).contains { was, now in
                    now.check?.isDisagreement == true
                        || (now.check != nil && TableChecks.normalised(was.text) != TableChecks.normalised(now.text))
                }
            }
            if after.table.uncheckedWithheld || changed {
                out.insert(withheldKey(documentId: after.documentId, label: after.table.label))
            }
        }
        return out
    }

    static func withheldKey(documentId: String, label: String) -> String {
        "\(documentId)#\(TableChecks.normalised(label).lowercased())"
    }
}

extension VaultDocumentLedger.Entry {
    /// The hash of the PDF the document's tables were read from — the document itself when it is
    /// a PDF, else the original it was made from (`VaultDocumentExtractor.tablesSource`). What a
    /// table check is keyed by.
    var tablesHash: String {
        (file as NSString).pathExtension.lowercased() == "pdf" ? contentHash : (sourceContentHash ?? contentHash)
    }
}

/// The checks this phone made of tables in vaults it did not author (Plan JN P3): one
/// `table-checks.json`-shaped file per vault in Application Support. Registered in
/// `DataStoreRegistry` as `tableChecks`.
///
/// It names who checked (this phone's name for whoever manages the vault) and what the page
/// prints in a cell. Written with first-unlock protection, since a lookup reads it from a voice
/// turn with the phone locked, and kept out of the backup, because the subject erasure reaches it.
/// A check goes with the manual it checks, and all of a vault's with the vault.
struct TableCheckStore {
    static let fileProtection = FileProtectionType.completeUntilFirstUserAuthentication

    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? DeliveryQueueStore.defaultDirectory()
            .appendingPathComponent("table-checks", isDirectory: true)
    }

    /// One vault's file. An id that is not a plain file name has none.
    func url(vaultId: String) -> URL? {
        guard !vaultId.isEmpty, vaultId.count <= 128, !vaultId.hasPrefix("."),
              vaultId.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "_-.".unicodeScalars.contains($0) })
        else { return nil }
        return directory.appendingPathComponent("\(vaultId).json")
    }

    /// The phone's checks of one vault, every one marked as made on a phone.
    func checks(vaultId: String) -> [TableCheck] {
        guard let url = url(vaultId: vaultId), let data = try? Data(contentsOf: url) else { return [] }
        return TableChecksFile.parse(data).checks.map { check in
            var check = check
            check.origin = .phone
            return check
        }
    }

    func save(_ checks: [TableCheck], vaultId: String) throws {
        guard var url = url(vaultId: vaultId) else { return }
        guard !checks.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try TableChecksFile.encode(checks).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try? FileManager.default.setAttributes([.protectionKey: Self.fileProtection], ofItemAtPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Drop the checks of the PDFs of `documentHashes` from one vault's file. Returns how many went.
    @discardableResult
    func forget(documentHashes: Set<String>, vaultId: String) -> Int {
        let checks = checks(vaultId: vaultId)
        let kept = TableChecks.forgetting(documentHashes: documentHashes, from: checks)
        guard kept.count != checks.count else { return 0 }
        try? save(kept, vaultId: vaultId)
        return checks.count - kept.count
    }

    /// Drop every check made under `name`, in every vault's file — the subject erasure's reach.
    @discardableResult
    func forget(checkedBy name: String) -> Int {
        let wanted = TableChecks.normalised(name).lowercased()
        guard !wanted.isEmpty else { return 0 }
        var removed = 0
        for vaultId in vaultIds() {
            let checks = checks(vaultId: vaultId)
            let kept = checks.filter { TableChecks.normalised($0.by).lowercased() != wanted }
            guard kept.count != checks.count else { continue }
            removed += checks.count - kept.count
            try? save(kept, vaultId: vaultId)
        }
        return removed
    }

    func removeAll(vaultId: String) {
        guard let url = url(vaultId: vaultId) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func vaultIds() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }
}
