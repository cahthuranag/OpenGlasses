import Foundation
import XCTest
@testable import OpenGlasses

@MainActor
extension CapturedManualIntegrationTests {
    func testCameraRequestFreezesOriginalContextAndIgnoresStaleCancellation() throws {
        let service = ManualCaptureService(sessions:sessions,catalog:catalog,cameraSupported:{true})
        _ = service.start(title:"   ")
        let first = try XCTUnwrap(service.request)
        XCTAssertEqual(first.metadata.title,"Photographed manual")
        XCTAssertEqual(first.metadata.sessionID,sessions.activeSession?.id)
        XCTAssertEqual(first.metadata.unitID,sessions.activeSession?.continuityScope)
        _ = service.start(title:"Duplicate")
        XCTAssertEqual(service.request?.id,first.id)
        service.cancel(requestID:first.id)
        _ = service.start(title:"New request")
        let second = try XCTUnwrap(service.request)
        XCTAssertNotEqual(first.id,second.id)
        service.cancel(requestID:first.id)
        XCTAssertEqual(service.request?.id,second.id)
        sessions.setEquipment(.init(modelToken:"HX40",heading:"HX40",file:"models.md",source:.spoken))
        XCTAssertNil(service.request,"changing the bound unit cancels the unsaved sheet")
        access = false
        _ = service.start()
        XCTAssertNil(service.request)
        XCTAssertTrue(try source.pending().isEmpty,"opening/cancelling a camera never publishes or stages a book")
    }
}
