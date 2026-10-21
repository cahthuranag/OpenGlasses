import UIKit
import XCTest
@testable import OpenGlasses

/// Plan JN P3 — where checks of a pictured table live and how they reach a lookup: written into a
/// vault the phone authored, kept beside one it did not, shared and imported, forgotten with the
/// manual, reset by a new PDF, reached by the subject erasure, and the organisation's requirement.
/// Every table, designation, value and name is invented.
@MainActor
final class TableCheckStoreTests: XCTestCase {

    private typealias T = TableChecksTests
    private static let vaultId = "jn_p3_checks"
    private static let secondVaultId = "jn_p3_checks_second"

    private var tempRoot: URL!
    private var previousEntitlement: FieldAssistEntitlementProvider!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TableCheckStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        previousEntitlement = EntitlementTestScope.grant()
        PolicyEnvelope.clear()
    }

    override func tearDown() {
        for id in [Self.vaultId, Self.secondVaultId] {
            VaultImporter.uninstall(id: id)
            TableCheckStore().removeAll(vaultId: id)
        }
        VaultRegistry.shared.reloadUserManifests()
        VaultRegistry.shared.resetCache()
        PolicyEnvelope.clear()
        EntitlementTestScope.restore(previousEntitlement)
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    // MARK: - Fixtures

    private var phoneStore: TableCheckStore { TableCheckStore(directory: tempRoot.appendingPathComponent("phone-store")) }

    private func directory(_ name: String) -> URL {
        let url = tempRoot.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeChecks(_ checks: [TableCheck], to directory: URL) throws {
        try TableChecksFile.encode(checks).write(to: directory.appendingPathComponent(TableChecksFile.fileName))
    }

    private func makePDF(_ text: String) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 600)).pdfData { context in
            context.beginPage()
            NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 14)])
                .draw(in: CGRect(x: 20, y: 20, width: 360, height: 560))
        }
    }

    /// An importable folder: one text manual made from a PDF original, and optionally a
    /// `table-checks.json` at its root.
    private func writeVault(id: String = vaultId, pdf: Data, checks: Data? = nil) -> URL {
        let dir = directory("vault-\(id)-\(UUID().uuidString.prefix(6))")
        let manifest = VaultManifest(id: id, name: "Invented Checks Vault", version: "1.0.0", files: ["safety.md"],
                                     proceduresDir: nil, documentsDir: "documents",
                                     documents: [VaultDocument(file: "book.txt", title: "Invented Book",
                                                               kind: "code_book", source: "book.pdf")],
                                     gating: .init(iap: "enterprise"),
                                     promptRules: ["Never fabricate.", "Cite the source."])
        try? JSONEncoder().encode(manifest).write(to: dir.appendingPathComponent("manifest.json"))
        try? "# Safety\n\nIsolate before work.".write(to: dir.appendingPathComponent("safety.md"), atomically: true, encoding: .utf8)
        let docs = dir.appendingPathComponent("documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try? "INVENTED BOOK\n\n1 SPACINGS\nTable Q7 gives invented spacings for the QMX90 designation."
            .write(to: docs.appendingPathComponent("book.txt"), atomically: true, encoding: .utf8)
        try? pdf.write(to: docs.appendingPathComponent("book.pdf"))
        if let checks { try? checks.write(to: dir.appendingPathComponent(TableChecksFile.fileName)) }
        return dir
    }

    private func source(_ table: ManualTable) -> TableLookup.Source {
        TableLookup.Source(documentId: "d1", documentName: "Invented Book", table: table)
    }

    private func applied(_ checks: [TableCheck], require: Bool = false,
                         table: ManualTable = T.q7(uncertainKey: false, uncertainHeading: false)) -> ManualTable {
        let stored = [DocumentStore.StoredTable(documentId: "d1", documentName: "Invented Book", table: table)]
        return VaultTableChecks.applied(stored, checks: checks, hashes: ["d1": T.bookHash], requireChecked: require)[0].table
    }

    private func lookup(_ table: ManualTable, row: String = "QMX90", column: String = "Spacing") -> String {
        TableLookup.render(TableLookup.resolve(.init(table: "Table Q7", row: row, column: column), in: [source(table)]))
    }

    // MARK: - Where checks live

    func testOnlyAVaultThePhoneAuthoredIsWrittenInto() {
        XCTAssertEqual(VaultTableChecks.home(received: false, pack: false, officeAssigned: false), .vaultFile)
        XCTAssertEqual(VaultTableChecks.home(received: false, pack: false, officeAssigned: true), .phoneStore)
        XCTAssertEqual(VaultTableChecks.home(received: true, pack: false, officeAssigned: false), .phoneStore)
        XCTAssertEqual(VaultTableChecks.home(received: false, pack: true, officeAssigned: false), .phoneStore)
    }

    func testAPhoneOnlyVaultsChecksAreWrittenIntoItsOwnFileStartingFromTheImportedOne() throws {
        let overlay = directory("overlay"), baseline = directory("baseline")
        try writeChecks([T.check(row: ["QZ12"], kind: .confirmed, value: "70", by: "the office reviewer", origin: .vaultFile)],
                        to: baseline)
        try VaultTableChecks.record([T.check(value: "35")], vaultId: "v", overlay: overlay, baseline: baseline,
                                    home: .vaultFile, phoneStore: phoneStore)
        let file = VaultTableChecks.vaultFile(overlay: overlay, baseline: baseline).checks
        XCTAssertEqual(Set(file.map(\.value)), ["70", "35"], "the imported check kept, the phone's added")
        XCTAssertTrue(phoneStore.checks(vaultId: "v").isEmpty, "nothing in the phone's own store")

        // Checking the cell again settles it in the one file.
        try VaultTableChecks.record([T.check(value: "36", at: T.later)], vaultId: "v", overlay: overlay, baseline: baseline,
                                    home: .vaultFile, phoneStore: phoneStore)
        let again = VaultTableChecks.checks(overlay: overlay, baseline: baseline, home: .vaultFile,
                                            phoneStore: phoneStore, vaultId: "v")
        XCTAssertEqual(again.filter { $0.row == ["QMX90"] }.map(\.value), ["36"])
    }

    func testAVaultThePhoneDidNotAuthorIsNeverWrittenIntoAndItsChecksMerge() throws {
        let overlay = directory("overlay"), baseline = directory("baseline")
        try writeChecks([T.check(value: "36", by: "the office reviewer", origin: .vaultFile)], to: baseline)
        try VaultTableChecks.record([T.check(value: "35")], vaultId: "office_vault", overlay: overlay, baseline: baseline,
                                    home: .phoneStore, phoneStore: phoneStore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: overlay.appendingPathComponent(TableChecksFile.fileName).path))
        XCTAssertEqual(VaultTableChecks.vaultFile(overlay: overlay, baseline: baseline).checks.map(\.value), ["36"],
                       "the office's file is as it wrote it")
        let all = VaultTableChecks.checks(overlay: overlay, baseline: baseline, home: .phoneStore,
                                          phoneStore: phoneStore, vaultId: "office_vault")
        XCTAssertEqual(Set(all.map(\.origin)), [.phone, .vaultFile])
        let cell = TableChecks.apply(all, to: T.q7(), documentHash: T.bookHash).table.rows[1].cells[0]
        XCTAssertTrue(cell.uncertain, "the phone and the office disagree; neither wins")

        // The phone checking to the office's value settles it.
        try VaultTableChecks.record([T.check(value: "36", at: T.later)], vaultId: "office_vault", overlay: overlay,
                                    baseline: baseline, home: .phoneStore, phoneStore: phoneStore)
        let settled = VaultTableChecks.checks(overlay: overlay, baseline: baseline, home: .phoneStore,
                                              phoneStore: phoneStore, vaultId: "office_vault")
        XCTAssertFalse(TableChecks.apply(settled, to: T.q7(), documentHash: T.bookHash).table.rows[1].cells[0].uncertain)
    }

    func testThePhoneStoreSurvivesRelaunchAndIsKeptOutOfBackup() throws {
        try phoneStore.save([T.check(value: "35")], vaultId: "office_vault")
        let reopened = TableCheckStore(directory: phoneStore.directory)
        XCTAssertEqual(reopened.checks(vaultId: "office_vault").map(\.value), ["35"])
        XCTAssertEqual(reopened.checks(vaultId: "office_vault").first?.origin, .phone)
        let url = try XCTUnwrap(reopened.url(vaultId: "office_vault"))
        let excluded = try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        XCTAssertEqual(excluded, SensitiveStore.tableChecks.record.backupExcluded)
        XCTAssertEqual(TableCheckStore.fileProtection, .completeUntilFirstUserAuthentication)
        XCTAssertEqual(SensitiveStore.tableChecks.record.protection, .completeUntilFirstUserAuthentication)
        XCTAssertNil(reopened.url(vaultId: "../escape"), "a vault id is never a path")
    }

    // MARK: - Sharing and importing

    func testAnExportedFileImportsOnAFreshStoreAndGivesTheCorrectedCell() throws {
        let checks = [T.check(value: "35"), T.check(value: "99", hash: T.otherHash)]
        let url = try XCTUnwrap(VaultTableChecks.shareFile(checks, documentHash: T.bookHash))
        XCTAssertEqual(url.lastPathComponent, "table-checks.json")
        let shared = TableChecksFile.parse(try Data(contentsOf: url))
        XCTAssertTrue(shared.problems.isEmpty)
        XCTAssertEqual(shared.checks.map(\.value), ["35"], "that manual's checks only")
        XCTAssertNil(try VaultTableChecks.shareFile(checks, documentHash: String(repeating: "c3", count: 32)))

        // The second phone: the file in its vault's folder, read as the vault's own.
        let second = directory("second-baseline")
        try FileManager.default.copyItem(at: url, to: second.appendingPathComponent(TableChecksFile.fileName))
        let imported = VaultTableChecks.checks(overlay: directory("second-overlay"), baseline: second, home: .vaultFile,
                                               phoneStore: TableCheckStore(directory: directory("second-store")),
                                               vaultId: "second")
        let text = lookup(applied(imported))
        XCTAssertTrue(text.contains("\"35\" (the number 35 mm)"), text)
    }

    func testImportingAFolderBringsItsChecksInAndWarnsOfWhatDoesNotRead() throws {
        let pdf = makePDF("Invented Book, Table Q7.")
        let hash = VaultDocumentLedger.hash(of: pdf)
        let file = """
        {"version": 1, "checks": [
          {"document_sha256": "\(hash)", "table": "Table Q7", "row": ["QMX90"], "column": ["Spacing (mm)"],
           "kind": "corrected", "value": "35", "checked_by": "the office reviewer", "checked_at": "2026-10-21T09:30:00Z"},
          {"document_sha256": "\(T.otherHash)", "table": "Table Q7", "row": ["QZ12"], "column": ["Spacing (mm)"],
           "kind": "confirmed", "value": "70", "checked_by": "the office reviewer", "checked_at": "2026-10-21T09:30:00Z"},
          {"document_sha256": "\(hash)", "table": "Table Q7", "kind": "confirmed", "value": "1",
           "checked_by": "the office reviewer", "checked_at": "2026-10-21T09:30:00Z"}
        ]}
        """
        let dir = writeVault(pdf: pdf, checks: Data(file.utf8))
        let report = try VaultImporter.installReporting(from: dir)
        XCTAssertTrue(report.warnings.contains { $0.contains("entry 3") && $0.contains("neither a row nor a column") },
                      "\(report.warnings)")
        XCTAssertTrue(report.warnings.contains { $0.contains("1 check is for a PDF this vault does not hold") },
                      "\(report.warnings)")
        XCTAssertFalse(report.warnings.joined().contains("35"))
        XCTAssertEqual(VaultTableChecks.home(vaultId: Self.vaultId), .vaultFile, "imported on the phone: the phone's own")
        let checks = VaultTableChecks.checks(vaultId: Self.vaultId)
        XCTAssertEqual(checks.count, 2, "the bad entry skipped; the unknown PDF's check kept")
        XCTAssertEqual(Set(checks.map(\.documentHash)), [hash, T.otherHash])
    }

    func testReimportingMergesTheFolderIntoTheChecksThePhoneAlreadyWrote() throws {
        let pdf = makePDF("Invented Book, Table Q7.")
        let hash = VaultDocumentLedger.hash(of: pdf)
        _ = try VaultImporter.installReporting(from: writeVault(pdf: pdf))
        try VaultTableChecks.record([T.check(value: "35", hash: hash)], vaultId: Self.vaultId)
        let overlayFile = VaultImporter.overlayDirectory(for: Self.vaultId).appendingPathComponent(TableChecksFile.fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: overlayFile.path), "written into the vault's own file")
        XCTAssertTrue(TableCheckStore().checks(vaultId: Self.vaultId).isEmpty)

        let office = try TableChecksFile.encode([T.check(value: "36", by: "the office reviewer", at: T.later,
                                                         origin: .vaultFile, hash: hash)])
        _ = try VaultImporter.installReporting(from: writeVault(pdf: pdf, checks: office))
        let checks = VaultTableChecks.checks(vaultId: Self.vaultId)
        XCTAssertEqual(Set(checks.map(\.value)), ["35", "36"], "the phone's check is not hidden by the import")
        XCTAssertEqual(TableChecks.apply(checks, to: T.q7(), documentHash: hash).table.rows[1].cells[0].check?.isDisagreement,
                       true)
    }

    // MARK: - Reset and forgetting

    func testANewPDFStartsUncheckedAndTheOldChecksAreReportedNotApplied() {
        let checks = [T.check(value: "35")]
        let newHash = String(repeating: "d4", count: 32)
        let result = TableChecks.apply(checks, to: [(newHash, T.q7())])
        XCTAssertEqual(result.tables, [T.q7()])
        XCTAssertEqual(result.unmatched, checks)
        let stored = [DocumentStore.StoredTable(documentId: "d1", documentName: "Invented Book", table: T.q7())]
        XCTAssertEqual(VaultTableChecks.applied(stored, checks: checks, hashes: ["d1": newHash], requireChecked: false)[0].table,
                       T.q7())
        XCTAssertEqual(TableChecks.status(of: T.q7()), .notChecked(checked: 0, cells: 6))
    }

    func testForgettingAPDFsChecksTakesThemFromTheStoreAndAPhoneOnlyVaultsFile() throws {
        let overlay = directory("overlay"), baseline = directory("baseline")
        try writeChecks([T.check(value: "35", origin: .vaultFile), T.check(hash: T.otherHash)], to: baseline)
        try writeChecks([T.check(value: "36"), T.check(hash: T.otherHash)], to: overlay)
        try phoneStore.save([T.check(value: "37"), T.check(hash: T.otherHash)], vaultId: "v")
        let removed = VaultTableChecks.forget(documentHashes: [T.bookHash], vaultId: "v", overlay: overlay, baseline: baseline,
                                              home: .vaultFile, phoneStore: phoneStore)
        XCTAssertEqual(removed, 3)
        for directory in [overlay, baseline] {
            let left = VaultTableChecks.vaultFile(overlay: directory, baseline: nil).checks
            XCTAssertEqual(left.map(\.documentHash), [T.otherHash])
        }
        XCTAssertEqual(phoneStore.checks(vaultId: "v").map(\.documentHash), [T.otherHash])
    }

    func testAnOfficeVaultsFileIsLeftAloneWhenItsManualIsForgotten() throws {
        let overlay = directory("overlay"), baseline = directory("baseline")
        try writeChecks([T.check(value: "35", origin: .vaultFile)], to: baseline)
        try phoneStore.save([T.check(value: "37")], vaultId: "office_vault")
        VaultTableChecks.forget(documentHashes: [T.bookHash], vaultId: "office_vault", overlay: overlay, baseline: baseline,
                                home: .phoneStore, phoneStore: phoneStore)
        XCTAssertTrue(phoneStore.checks(vaultId: "office_vault").isEmpty)
        XCTAssertEqual(VaultTableChecks.vaultFile(overlay: overlay, baseline: baseline).checks.count, 1)
    }

    func testRemovingTheManualForgetsItsChecks() async throws {
        let pdf = makePDF("Invented Book, Table Q7.")
        let hash = VaultDocumentLedger.hash(of: pdf)
        let documents = DocumentStore(directory: directory("store"))
        let manifest = try VaultImporter.install(from: writeVault(pdf: pdf))
        VaultRegistry.shared.reloadUserManifests()
        let ledger = try await VaultImporter.syncDocuments(manifest: manifest, into: documents, pictureReader: nil)
        XCTAssertEqual(ledger.entries.first?.tablesHash, hash, "a text manual's tables are its PDF original's")
        try VaultTableChecks.record([T.check(value: "35", hash: hash)], vaultId: Self.vaultId)
        try TableCheckStore().save([T.check(value: "35", hash: hash)], vaultId: Self.vaultId)
        XCTAssertFalse(VaultTableChecks.checks(vaultId: Self.vaultId).isEmpty)

        _ = try await VaultManualRemoval.remove(file: "book.txt", fromVault: Self.vaultId, documentStore: documents)
        XCTAssertTrue(VaultTableChecks.checks(vaultId: Self.vaultId).isEmpty)
        XCTAssertTrue(TableCheckStore().checks(vaultId: Self.vaultId).isEmpty)
    }

    func testUninstallingAVaultTakesThePhonesChecksOfIt() async throws {
        let documents = DocumentStore(directory: directory("store"))
        _ = try VaultImporter.install(from: writeVault(pdf: makePDF("Invented Book.")))
        try TableCheckStore().save([T.check(value: "35")], vaultId: Self.vaultId)
        await VaultImporter.uninstall(id: Self.vaultId, documentStore: documents)
        XCTAssertTrue(TableCheckStore().checks(vaultId: Self.vaultId).isEmpty)
    }

    // MARK: - Subject erasure

    func testErasingADocumentTakesItsChecksByThePDFItsLedgerNames() async throws {
        let vault = directory("jn_p3_erasure")
        try VaultDocumentLedger(entries: [
            .init(file: "book.pdf", title: "Invented Book", documentId: "doc-1", contentHash: T.bookHash, chunkCount: 1),
        ]).save(to: vault)
        try writeChecks([T.check(value: "35"), T.check(hash: T.otherHash)], to: vault)
        try phoneStore.save([T.check(value: "36")], vaultId: "jn_p3_erasure")
        var stores = SubjectErasureCoordinator.Stores()
        stores.tableChecks = phoneStore
        stores.vaultDirectories = [vault]
        let receipts = await SubjectErasureCoordinator(stores: stores).erase(.document(id: "doc-1"))
        let receipt = try XCTUnwrap(receipts.first { $0.store == .tableChecks })
        XCTAssertTrue(receipt.localComplete)
        XCTAssertEqual(receipt.removed, 2)
        XCTAssertEqual(VaultTableChecks.vaultFile(overlay: vault, baseline: nil).checks.map(\.documentHash), [T.otherHash])
        XCTAssertTrue(phoneStore.checks(vaultId: "jn_p3_erasure").isEmpty)
        XCTAssertEqual(try XCTUnwrap(receipts.first { $0.store == .vaultLedger }).removed, 1,
                       "the ledger entry goes after the checks it named")
    }

    func testErasingAPersonTakesTheChecksThatNameThem() async throws {
        let vault = directory("jn_p3_person")
        try writeChecks([T.check(by: "Invented Checker"), T.check(row: ["QZ12"], by: "the vault manager")], to: vault)
        try phoneStore.save([T.check(by: "invented  checker")], vaultId: "office_vault")
        var stores = SubjectErasureCoordinator.Stores()
        stores.tableChecks = phoneStore
        stores.vaultDirectories = [vault]
        let receipts = await SubjectErasureCoordinator(stores: stores).erase(.person("Invented Checker"))
        XCTAssertEqual(try XCTUnwrap(receipts.first { $0.store == .tableChecks }).removed, 2)
        XCTAssertEqual(VaultTableChecks.vaultFile(overlay: vault, baseline: nil).checks.map(\.by), ["the vault manager"])
        XCTAssertTrue(phoneStore.checks(vaultId: "office_vault").isEmpty)

        let none = await SubjectErasureCoordinator(stores: .init()).erase(.person("Invented Checker"))
        XCTAssertNotNil(none.first { $0.store == .tableChecks }?.unsupported, "no store supplied is said, not skipped")
    }

    // MARK: - At lookup time

    func testACorrectedCellIsGivenFromAPictureAndCheckedWithoutCheckItAgainstThePage() {
        let text = lookup(applied([T.check(value: "35")]))
        XCTAssertTrue(text.contains("\"35\" (the number 35 mm)"), text)
        XCTAssertTrue(text.contains("read from a picture of the table on page 31 of Invented Book, checked by the vault manager on "
                                    + TableChecks.day(T.day)), text)
        XCTAssertTrue(text.contains("then checked against the page"), text)
        XCTAssertFalse(text.contains("read the value back to the technician to check against the page"), text)
        XCTAssertFalse(text.contains("3S"), "what was misread is never given")
    }

    func testAnUncheckedCellStillAsksForItToBeCheckedAgainstThePage() {
        let text = lookup(applied([]), row: "QZ12")
        XCTAssertTrue(text.contains("\"70\""), text)
        XCTAssertTrue(text.contains("read the value back to the technician to check against the page"), text)
        XCTAssertFalse(text.contains("checked by"), text)
    }

    func testADisagreeingCellIsRefusedWithTheUnclearWording() {
        let table = applied([T.check(value: "35"), T.check(value: "36", by: "the office reviewer", origin: .vaultFile)])
        let text = lookup(table)
        XCTAssertTrue(text.contains("this cell could not be read clearly from the picture"), text)
        XCTAssertFalse(text.contains("\"35\""), text)
        XCTAssertFalse(text.contains("\"36\""), text)
    }

    func testRequiringChecksRefusesAnUncheckedTableAndGivesACheckedOne() {
        let refused = lookup(applied([], require: true), row: "QZ12")
        XCTAssertTrue(refused.contains("has not been checked against the page yet"), refused)
        XCTAssertTrue(refused.contains("Do not answer from memory"), refused)
        XCTAssertFalse(refused.contains("\"70\""), refused)

        let clear = T.q7(uncertainCell: false, uncertainKey: false, uncertainHeading: false)
        let all = TableCheckModel(table: clear, documentHash: T.bookHash, checks: []).confirmRemaining(by: "the vault manager", at: T.day)
        let given = lookup(applied(all, require: true, table: clear), row: "QZ12")
        XCTAssertTrue(given.contains("\"70\""), given)
        XCTAssertTrue(given.contains("checked by the vault manager"), given)

        // A chain's column search stops on a withheld table too.
        let search = TableLookup.search(.init(table: "Table Q7", row: "", column: "Spacing"), value: 60, rule: .atLeast,
                                        in: [source(applied([], require: true, table: clear))])
        guard case .refused(.unclear(_, _, .notChecked)) = search else { return XCTFail("\(search)") }
    }

    func testAChainStepOnACheckedCellDropsCheckItAgainstThePage() throws {
        let checked = applied([T.check(value: "35")])
        let found = TableLookup.Found(source: source(checked), rows: [checked.rows[1]], columns: [0], between: nil, unreadPages: [])
        let step = ChainLookup(found: found, rule: .exact, asked: "QMX90", byCell: false)
        XCTAssertEqual(step.pictureMark, "from a picture of Table Q7 (Invented spacings), page 31, checked by the vault manager on "
                       + TableChecks.day(T.day))
        let unchecked = applied([])
        let plain = ChainLookup(found: .init(source: source(unchecked), rows: [unchecked.rows[2]], columns: [0], between: nil,
                                             unreadPages: []), rule: .exact, asked: "QZ12", byCell: false)
        XCTAssertEqual(plain.pictureMark, "from a picture of Table Q7 (Invented spacings), page 31: check it against the page")
    }

    func testRowPassagesOfATableWhoseChecksChangedOrWithholdItAreNotSearched() {
        let table = T.q7(uncertainKey: false, uncertainHeading: false)
        let stored = [DocumentStore.StoredTable(documentId: "d1", documentName: "Invented Book", table: table)]
        func withheld(_ checks: [TableCheck], require: Bool = false) -> Set<String> {
            VaultTableChecks.rowPassagesWithheld(
                original: stored,
                applied: VaultTableChecks.applied(stored, checks: checks, hashes: ["d1": T.bookHash], requireChecked: require))
        }
        let key = VaultTableChecks.withheldKey(documentId: "d1", label: "Table Q7")
        XCTAssertEqual(withheld([T.check(row: ["QZ12"], kind: .confirmed, value: "70")]), [], "a confirmation changes nothing")
        XCTAssertEqual(withheld([T.check(row: ["QZ12"], value: "71")]), [key], "a correction: the passage says what was read")
        XCTAssertEqual(withheld([T.check(value: "35"), T.check(value: "36", by: "the office reviewer")]), [key])
        XCTAssertEqual(withheld([], require: true), [key])
        XCTAssertEqual(withheld([]), [])
    }

    // MARK: - The organisation's requirement

    private func apply(_ settings: [String: RawSetting]) -> ProfileApplier.Result {
        let profile = ConfigProfile(keyId: "k", profileId: "p", organizationName: "Invented Electrical",
                                    issued: Date(), leaseDays: 30, settings: settings)
        return ProfileApplier.apply(profile: profile, resolvableVaultIds: [])
    }

    func testRequiringChecksIsACeilingAProfileMayOnlyPinOn() {
        let key = SettingKey.organizationRequiresTableChecks
        XCTAssertEqual(key.kind, .ceiling(pinnedTo: true))
        XCTAssertEqual(apply([key.rawValue: RawSetting(.bool(true), .ceiling)]).ceilings[key], .bool(true))
        let widened = apply([key.rawValue: RawSetting(.bool(false), .ceiling)])
        XCTAssertNil(widened.ceilings[key])
        XCTAssertEqual(widened.drops, [.init(key: key.rawValue, reason: .wrongDirection)])
        XCTAssertEqual(apply([key.rawValue: RawSetting(.bool(true), .default)]).drops,
                       [.init(key: key.rawValue, reason: .dispositionNotAllowed(.default))])
        XCTAssertNotEqual(key.ceilingDescription, key.rawValue)
        XCTAssertFalse(key.ceilingDescription.contains("organization"))
    }

    func testConfigReadsTheRequirementThroughTheEnvelopeAndItIsOffWithoutAProfile() {
        XCTAssertFalse(Config.organizationRequiresTableChecks, "checking is optional by default")
        PolicyEnvelope.install(apply(["organizationRequiresTableChecks": RawSetting(.bool(true), .ceiling)]),
                               organizationName: "Invented Electrical")
        XCTAssertTrue(Config.organizationRequiresTableChecks)
        XCTAssertTrue(PolicyEnvelope.isLocked(.organizationRequiresTableChecks))
        PolicyEnvelope.clear()
        XCTAssertFalse(Config.organizationRequiresTableChecks)
    }
}
