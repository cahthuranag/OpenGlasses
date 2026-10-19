import XCTest
@testable import OpenGlasses

/// Shared fixtures for Plan HV: the fictional dual-fuel vault under `Fixtures/SiteSystemVault`
/// and builders for site documents. Every model, serial, site and identifier is invented.
enum SiteSystemFixtures {

    /// `OpenGlassesTests/Fixtures/SiteSystemVault`, located from this source file.
    static var vaultDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/SiteSystemVault", isDirectory: true)
    }

    static let siteFile = "sites/hillside-house.json"
    static let vaultId = "site_system_example"

    static func exampleData() throws -> Data {
        try Data(contentsOf: vaultDirectory.appendingPathComponent(siteFile))
    }

    static func exampleDocument() throws -> SiteSystemDocument {
        try XCTUnwrap(SiteSystemDocument.decode(exampleData()))
    }

    static func coreFiles() throws -> [(filename: String, contents: String)] {
        try ["safety.md", "models.md"].map {
            (filename: $0, contents: try String(contentsOf: vaultDirectory.appendingPathComponent($0), encoding: .utf8))
        }
    }

    static func modelIndex() throws -> VaultModelIndex {
        VaultModelIndex(vaultName: "Fictional Dual-Fuel Example", files: try coreFiles())
    }

    static func covered() throws -> SiteSystemValidator.ModelCovered {
        SiteSystemValidator.modelCovered(by: try modelIndex())
    }

    static func modelKey() throws -> (String) -> String {
        SiteSystemMatcher.modelKey(index: try modelIndex())
    }

    /// The example as a mutable JSON object, to change one thing per test.
    static func exampleObject() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: exampleData()) as? [String: Any])
    }

    static func data(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// A minimal valid document: one site, the given units.
    static func document(id: String, name: String? = nil, units: [[String: Any]],
                         locations: [[String: String]]? = nil, extra: [String: Any] = [:]) -> [String: Any] {
        var object: [String: Any] = [
            "format": SiteSystemDocument.format, "version": 1, "id": id, "name": name ?? "Site \(id)",
            "units": units,
        ]
        if let locations { object["external_location_ids"] = locations }
        for (key, value) in extra { object[key] = value }
        return object
    }

    static func unit(_ id: String, model: String, serial: String? = nil, label: String? = nil,
                     covered: Bool? = nil, externalIDs: [[String: String]]? = nil) -> [String: Any] {
        var unit: [String: Any] = ["id": id, "model": model]
        if let serial { unit["serial"] = serial }
        if let label { unit["label"] = label }
        if let covered { unit["covered"] = covered }
        if let externalIDs { unit["external_ids"] = externalIDs }
        return unit
    }

    static func decoded(_ object: [String: Any]) throws -> SiteSystemDocument {
        try XCTUnwrap(SiteSystemDocument.decode(data(object)))
    }

    /// The fixture vault copied to `root`, optionally with its manifest and site files replaced.
    @discardableResult
    static func copyVault(to root: URL, id: String = vaultId, sites: [String: [String: Any]]? = nil,
                          listed: [String]? = nil, withoutSites: Bool = false) throws -> URL {
        let fm = FileManager.default
        let dir = root.appendingPathComponent(id, isDirectory: true)
        try? fm.removeItem(at: dir)
        try fm.copyItem(at: vaultDirectory, to: dir)
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: dir.appendingPathComponent("manifest.json"))) as? [String: Any])
        manifest["id"] = id
        if withoutSites {
            manifest.removeValue(forKey: "sites")
            try? fm.removeItem(at: dir.appendingPathComponent("sites"))
        }
        if let sites {
            try? fm.removeItem(at: dir.appendingPathComponent("sites"))
            try fm.createDirectory(at: dir.appendingPathComponent("sites"), withIntermediateDirectories: true)
            for (path, object) in sites {
                try data(object).write(to: dir.appendingPathComponent(path))
            }
            manifest["sites"] = listed ?? sites.keys.sorted()
        } else if let listed {
            manifest["sites"] = listed
        }
        try data(manifest).write(to: dir.appendingPathComponent("manifest.json"))
        return dir
    }
}
