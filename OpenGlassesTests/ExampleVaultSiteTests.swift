import XCTest
@testable import OpenGlasses

/// Plan HV P0 — the worked example. FR's invented product line has not landed, so the example is
/// a test fixture vault (`Fixtures/SiteSystemVault`) with invented models, serials and sites, and
/// never goes into the real-product example folder.
@MainActor
final class ExampleVaultSiteTests: XCTestCase {

    private typealias F = SiteSystemFixtures

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    func testTheFixtureIsAWholeValidVaultWithOneSite() throws {
        let result = VaultValidator.validate(directory: F.vaultDirectory)
        XCTAssertTrue(result.isValid, "\(result.issues)")
        XCTAssertEqual(result.manifest?.siteFiles, [F.siteFile])
        let document = try F.exampleDocument()
        // Generic, not one trade's: every kind it uses is from the shared vocabulary.
        XCTAssertEqual(Set(document.connections?.map(\.kind) ?? []), [.fluid, .communication])
        XCTAssertEqual(document.integrations?.map(\.kind), [.cloudPortal])
    }

    func testNoExampleVaultInTheRepositoryCarriesSites() throws {
        // The real-product examples describe products, never a customer's site.
        let examples = Self.repoRoot.appendingPathComponent("examples/vaults", isDirectory: true)
        let folders = (try? FileManager.default.contentsOfDirectory(at: examples, includingPropertiesForKeys: nil)) ?? []
        guard !folders.isEmpty else { throw XCTSkip("no example vaults found") }
        for folder in folders {
            let manifestURL = folder.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL) else { continue }
            let manifest = try JSONDecoder().decode(VaultManifest.self, from: data)
            XCTAssertNil(manifest.sites, folder.lastPathComponent)
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("sites").path),
                           folder.lastPathComponent)
        }
    }

    func testTheGuidesWorkedExampleIsTheFixture() throws {
        let guideURL = Self.repoRoot.appendingPathComponent("docs/field-assist-vault-guide.md")
        guard let guide = try? String(contentsOf: guideURL, encoding: .utf8) else { throw XCTSkip("guide not found") }
        let marker = "\"format\": \"avenkin.site-system\""
        let start = try XCTUnwrap(guide.range(of: marker), "the guide shows a site document")
        let open = try XCTUnwrap(guide[..<start.lowerBound].lastIndex(of: "{"))
        let close = try XCTUnwrap(guide[start.upperBound...].range(of: "\n```")).lowerBound
        let json = Data(guide[open..<close].utf8)
        let result = SiteSystemValidator.check(json, path: F.siteFile, modelCovered: try F.covered())
        XCTAssertEqual(result.issues, [], "the guide's example passes the validator")
        XCTAssertEqual(result.document, try F.exampleDocument(), "the guide and the fixture say the same thing")
    }

    func testEveryValueInTheFixtureIsInvented() throws {
        let text = try String(decoding: F.exampleData(), as: UTF8.self)
            + String(contentsOf: F.vaultDirectory.appendingPathComponent("models.md"), encoding: .utf8)
        XCTAssertTrue(try String(contentsOf: F.vaultDirectory.appendingPathComponent("safety.md"), encoding: .utf8)
            .contains("invented for testing"))
        XCTAssertFalse(text.contains("://"))
        XCTAssertFalse(text.contains("@"))
    }
}
