import XCTest
@testable import OpenGlasses

/// Plan HU, decided 2026-10-20 — a job update that changes one of the office's warnings (a
/// `warning` site requirement or a `warning` flag) reads the changed warning once, as it arrives,
/// and never repeats one the job already had. Wired on the job-file revision path.
@MainActor
final class OfficeWarningChangesTests: XCTestCase {

    private typealias F = OfficeHistoryFixtures

    private let newHazard = OfficeSiteRequirements.Item(kind: .hazard, text: "Live works on the roof today.",
                                                        severity: .warning)

    // MARK: - The policy

    func testAnUnchangedJobSaysNothing() {
        XCTAssertNil(OfficeWarningChanges.spoken(from: F.job(), to: F.job()))
        // A change to something else — an info item, the history's visits — says nothing either.
        var revised = F.job()
        revised.siteRequirements = F.requirements(F.requirements().items.map {
            $0.severity == .info ? .init(kind: .access, text: "Use the south gate.", severity: .info) : $0
        })
        revised.officeHistory = F.history(units: [.init(serial: F.serial)])
        XCTAssertNil(OfficeWarningChanges.spoken(from: F.job(), to: revised))
    }

    func testANewOrRewordedWarningRequirementIsRead() {
        var revised = F.job()
        revised.siteRequirements = F.requirements(F.requirements().items + [newHazard])
        XCTAssertEqual(OfficeWarningChanges.spoken(from: F.job(), to: revised),
                       "The office changed a warning on Job 1007. Site requirements: Hazard: Live works on the roof today.")

        var reworded = F.job()
        reworded.siteRequirements = F.requirements([
            .init(kind: .hazard, text: F.hazard, severity: .warning),
            .init(kind: .induction, text: "Induction now at reception.", severity: .warning),
        ])
        let changes = OfficeWarningChanges.changed(from: F.job(), to: reworded)
        XCTAssertEqual(changes.requirements, ["Induction: Induction now at reception."], "only the one that changed")
        XCTAssertTrue(changes.flags.isEmpty)
    }

    func testAnItemNewlyMarkedAWarningIsRead() {
        var revised = F.job()
        revised.siteRequirements = F.requirements(F.requirements().items.map {
            $0.severity == .info ? .init(kind: $0.kind, text: $0.text, severity: .warning) : $0
        })
        XCTAssertEqual(OfficeWarningChanges.changed(from: F.job(), to: revised).requirements, ["Access: \(F.access)"])
    }

    func testANewWarningFlagIsReadAndAnOldOneIsNot() {
        var revised = F.job()
        let flag = OfficeServiceHistory.Flag(kind: .recurringFailure, unit: F.serial, text: "Flame loss again.",
                                             evidence: ["1001"], severity: .warning)
        revised.officeHistory = F.history(flags: F.history().flags + [flag])
        let changes = OfficeWarningChanges.changed(from: F.job(), to: revised)
        XCTAssertEqual(changes.flags, ["Recurring failure: Flame loss again."])
        XCTAssertEqual(OfficeWarningChanges.spoken(from: F.job(), to: revised),
                       "The office changed a warning on Job 1007. Office flag: Recurring failure: Flame loss again.")
    }

    func testAWarningTheUpdateRemovesIsNotRead() {
        var revised = F.job()
        revised.siteRequirements = F.requirements([.init(kind: .hazard, text: F.hazard, severity: .warning)])
        revised.officeHistory = F.history(flags: [])
        XCTAssertNil(OfficeWarningChanges.spoken(from: F.job(), to: revised))
    }

    func testASecondUnitArrivingDoesNotMakeAnOldFlagNew() {
        // Its wording gains "on serial …", but the office's flag is the same flag.
        var revised = F.job(equipment: [KnownEquipment(model: "FX-90", serial: F.serial),
                                        KnownEquipment(model: "FX-40", serial: F.secondSerial)])
        revised.officeHistory = F.history(units: F.history().units + [.init(serial: F.secondSerial)])
        XCTAssertNil(OfficeWarningChanges.spoken(from: F.job(), to: revised))
    }

    // MARK: - The revision path

    /// A signed format-3 job file at a revision, with the given site requirements.
    private func revision(_ number: Int, requirements: String, notes: String = "Gate code 4411.") throws -> Data {
        let json = #"{"job_id":"job-77","revision":\#(number),"job_reference":"1007","notes":"\#(notes)","equipment":[{"model":"FX-90","serial":"FX90S001"}],"site_requirements":{"as_of":"2026-10-07T18:00:00Z","items":[\#(requirements)]}}"#
        return try JobFileFormat3Fixtures.file(json, key: JobFileFormat3Fixtures.fixtureKey)
    }

    private let hazardJSON = #"{"kind":"hazard","text":"Asbestos register: boiler-room ceiling.","severity":"warning"}"#
    private let roofJSON = #"{"kind":"hazard","text":"Live works on the roof today.","severity":"warning"}"#

    func testARevisionThatChangesAWarningReadsItOnceAsItIsAccepted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Warn-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = UpcomingJobStore(directory: root)
        var said: [String] = []
        let files = JobFileService(seams: .init(
            store: { store },
            organisationKey: { JobFileFormat3Fixtures.fixturePublicKey },
            organisationName: { "Fixture Services Ltd" },
            now: { F.now },
            fieldAssistActive: { true },
            speak: { said.append($0) }))

        func accept(_ data: Data, _ decision: JobFileDecision, line: UInt = #line) throws -> UpcomingJob {
            files.handle(data: data, fileName: "1007.ogjob")
            guard case .review = files.stage else {
                XCTFail("expected a review, got \(files.stage)", line: line)
                throw CancellationError()
            }
            let written = try XCTUnwrap(files.accept(decision), line: line)
            files.dismiss()
            return written
        }

        let first = try accept(revision(1, requirements: hazardJSON), .add)
        XCTAssertTrue(said.isEmpty, "a new job says nothing as it is added: its warnings are Start's to say")

        let second = try accept(revision(2, requirements: hazardJSON + "," + roofJSON), .update)
        XCTAssertEqual(second.id, first.id, "a revision replaces the job it revises")
        XCTAssertEqual(said, ["The office changed a warning on Job 1007. Site requirements: Hazard: Live works on the roof today."])

        // The next revision changes only the notes: the warning it still carries is not said again.
        _ = try accept(revision(3, requirements: hazardJSON + "," + roofJSON, notes: "Bring the long ladder."), .update)
        XCTAssertEqual(said.count, 1, "the same warning is not repeated")
    }

    func testTheRevisionPathIsWhereTheChangeIsRead() throws {
        // A started job is never changed by a job file, and Plan HN's open-job updates are not
        // built, so the revision of a job ahead is the one place a changed warning arrives today.
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("OpenGlasses/Sources/Services/FieldAssist/Job/JobFileService.swift"),
                                encoding: .utf8)
        XCTAssertTrue(source.contains("OfficeWarningChanges.spoken(from: existing, to: written)"))
    }
}
