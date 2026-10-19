import XCTest
@testable import OpenGlasses

/// A gauge reading on the job record (Plan IS P1): a `SpokenReading`-shaped entry with the method
/// `instrument_reading`, the photo it was read from, and the refrigerant with its source — and a
/// record written before these fields existed still reads.
@MainActor
final class InstrumentReadingRecordTests: XCTestCase {

    private var tempRoot: URL!
    private var previousEntitlement: FieldAssistEntitlementProvider!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstrumentReadingRecordTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        UserDefaults.standard.set(true, forKey: "fieldAssistEnabled")
        previousEntitlement = EntitlementTestScope.grant()
        VaultRegistry.shared.resetCache()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: "fieldAssistEnabled")
        EntitlementTestScope.restore(previousEntitlement)
        super.tearDown()
    }

    func testAnInstrumentReadingIsRecordedWithItsMethodPhotoAndRefrigerant() throws {
        let service = FieldSessionService(sessionsRoot: tempRoot)
        _ = try service.startSession(vaultId: "refrigeration", assetId: nil)
        XCTAssertNil(service.activeRefrigerant, "no refrigerant until one is written down")
        service.recordIdentityField(name: "Refrigerant", value: "R-410A", source: .nameplate)
        let refrigerant = try XCTUnwrap(service.activeRefrigerant)
        XCTAssertEqual(refrigerant.value, "R-410A")
        XCTAssertEqual(refrigerant.source, .nameplate)

        let reading = try XCTUnwrap(service.recordInstrumentReading(
            quantity: "suction pressure", value: "118", unit: "psig", method: SpokenReading.instrumentReadingMethod,
            photoId: "photo-1.jpg", refrigerant: "R-410A", refrigerantSource: "nameplate", at: Date()))
        XCTAssertTrue(reading.isInstrumentReading)
        XCTAssertEqual(service.activeSession?.spokenReadings, [reading])

        let record = try XCTUnwrap(service.workRecord())
        XCTAssertTrue(record.summaryLines.contains("  Suction pressure 118 psig — read from the gauge photo (R-410A)"),
                      record.summary)
        XCTAssertEqual(record.readings, [reading.id])
    }

    func testACorrectionIsSaidButKeepsTheRefrigerant() throws {
        let service = FieldSessionService(sessionsRoot: tempRoot)
        _ = try service.startSession(vaultId: "refrigeration", assetId: nil)
        _ = service.recordInstrumentReading(quantity: "suction pressure", value: "118", unit: "psig",
                                            method: SpokenReading.instrumentReadingMethod, photoId: "p.jpg",
                                            refrigerant: "R-410A", refrigerantSource: "nameplate", at: Date())
        let correction = try XCTUnwrap(service.correctReading(value: "120", unit: nil))
        XCTAssertNil(correction.method, "a correction is the technician's word")
        XCTAssertNil(correction.photoId)
        XCTAssertEqual(correction.refrigerant, "R-410A")
        XCTAssertEqual(correction.unit, "psig")
    }

    func testTheNewFieldsRoundTripAndAnOldRecordStillReads() throws {
        let reading = SpokenReading(id: "r1", quantity: "suction pressure", value: "118", unit: "psig",
                                    at: Date(timeIntervalSince1970: 1_800_000_000),
                                    method: "instrument_reading", photoId: "photo-1.jpg",
                                    refrigerant: "R-410A", refrigerantSource: "nameplate")
        let data = try JSONEncoder().encode(reading)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["photo_id"] as? String, "photo-1.jpg")
        XCTAssertEqual(json["refrigerant_source"] as? String, "nameplate")
        XCTAssertEqual(try JSONDecoder().decode(SpokenReading.self, from: data), reading)

        let old = Data(#"{"id":"r0","quantity":"supply air","value":"140","unit":"°F","unit_scope":"initial","at":800000000}"#.utf8)
        let decoded = try JSONDecoder().decode(SpokenReading.self, from: old)
        XCTAssertNil(decoded.method)
        XCTAssertNil(decoded.refrigerant)
        XCTAssertFalse(decoded.isInstrumentReading)
    }
}
