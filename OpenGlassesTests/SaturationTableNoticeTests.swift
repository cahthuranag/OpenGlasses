import XCTest
@testable import OpenGlasses

/// CoolProp's MIT licence and attribution travel with the tables generated from it (Plan IS P0 exit
/// test): the in-app attributions name it at the version the tables were generated with, and the
/// generator is pinned to that same version.
@MainActor
final class SaturationTableNoticeTests: XCTestCase {

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private func bundledVersions() throws -> Set<String> {
        Set(try SaturationTableCatalog.designations.map {
            try XCTUnwrap(SaturationTableCatalog.table(for: $0), $0).libraryVersion
        })
    }

    func testEveryTableWasGeneratedWithOneVersion() throws {
        XCTAssertEqual(try bundledVersions().count, 1)
    }

    func testAttributionsNameCoolPropAtTheTablesVersionWithItsLicence() throws {
        let version = try XCTUnwrap(try bundledVersions().first)
        let view = try source("OpenGlasses/Sources/App/Views/AttributionsView.swift")
        let start = try XCTUnwrap(view.range(of: "name: \"CoolProp \(version)\""),
                                  "AttributionsView has no CoolProp \(version) row")
        let row = String(view[start.lowerBound...].prefix(400))
        XCTAssertTrue(row.contains("license: \"MIT\""), row)
        XCTAssertTrue(row.contains("Ian H. Bell and other CoolProp developers"), row)
        XCTAssertTrue(view.contains("rows(referenceData)"), "the reference-data section is not shown")
    }

    func testTheGeneratorIsPinnedToTheTablesVersion() throws {
        let version = try XCTUnwrap(try bundledVersions().first)
        let script = try source("Scripts/generate-pt-tables.py")
        XCTAssertTrue(script.contains("PINNED_COOLPROP = \"\(version)\""), "generator pin differs from the tables")
        XCTAssertTrue(script.contains("CoolProp==\(version)"), "setup instructions name another version")
    }

    func testEveryTableCarriesTheLicenceLine() throws {
        for designation in SaturationTableCatalog.designations {
            let table = try XCTUnwrap(SaturationTableCatalog.table(for: designation))
            XCTAssertEqual(table.licence,
                           "CoolProp is MIT licensed. Copyright (c) 2012-2018 Ian H. Bell and other CoolProp developers.",
                           designation)
        }
    }
}
