import XCTest
import CoreGraphics
@testable import OpenGlasses

final class AdaptiveWorkspaceLayoutTests: XCTestCase {
    func testPhoneRotationExposesContextWithoutDeviceChecks() {
        XCTAssertFalse(AdaptiveWorkspaceLayout.resolve(size: CGSize(width: 393, height: 750)).showsContext)
        let landscape = AdaptiveWorkspaceLayout.resolve(size: CGSize(width: 750, height: 330))
        XCTAssertTrue(landscape.showsContext)
        XCTAssertTrue(landscape.isShort)
        XCTAssertGreaterThanOrEqual(landscape.contextWidth, 280)
        XCTAssertGreaterThanOrEqual(750 - landscape.contextWidth - AdaptiveWorkspaceLayout.columnSpacing, 340)
    }

    func testResizingNeverAllocatesLessThanEitherReadableColumn() {
        for width in stride(from: CGFloat(300), through: 1600, by: 7) {
            let layout = AdaptiveWorkspaceLayout.resolve(size: CGSize(width: width, height: 700))
            if layout.showsContext {
                XCTAssertGreaterThanOrEqual(layout.contextWidth, 280)
                XCTAssertLessThanOrEqual(layout.contextWidth, 420)
                XCTAssertGreaterThanOrEqual(width - layout.contextWidth - AdaptiveWorkspaceLayout.columnSpacing, 340)
            } else {
                XCTAssertLessThan(width, 340 + 280 + AdaptiveWorkspaceLayout.columnSpacing)
            }
        }
    }

    func testLargeTextAndNarrowWindowsCollapseTheContext() {
        XCTAssertFalse(AdaptiveWorkspaceLayout.resolve(size: CGSize(width: 600, height: 900)).showsContext)
        XCTAssertFalse(AdaptiveWorkspaceLayout.resolve(size: CGSize(width: 900, height: 700),
                                                       accessibilityText: true).showsContext)
        XCTAssertFalse(AdaptiveWorkspaceLayout.resolve(size: CGSize(width: 750, height: 700),
                                                       minimumPrimaryWidth: 460,
                                                       minimumContextWidth: 380).showsContext)
    }

    func testKeyboardDoesNotMoveAnInlineManualIntoAModal() {
        XCTAssertTrue(AdaptiveWorkspaceLayout.resolve(size: CGSize(width: 750, height: 140)).showsContext)
    }

    func testDockIsBoundedInExpandedWindowsAndPreservesCompactSizing() {
        let compact = AdaptiveWorkspaceLayout.resolve(size: CGSize(width: 393, height: 750))
        XCTAssertEqual(compact.dockReservation(availableHeight: 750, measuredSurface: 310), 310)
        XCTAssertNil(compact.dockReservation(availableHeight: 750, measuredSurface: nil))
        let wide = AdaptiveWorkspaceLayout.resolve(size: CGSize(width: 1000, height: 800))
        XCTAssertEqual(wide.dockReservation(availableHeight: 800, measuredSurface: 80), 460)
        let short = AdaptiveWorkspaceLayout.resolve(size: CGSize(width: 750, height: 330))
        XCTAssertEqual(short.dockReservation(availableHeight: 330, measuredSurface: 80), 80)
    }

    func testUnmeasuredOrInvalidGeometryDoesNotCreateAContextPane() {
        for size in [CGSize.zero, CGSize(width: CGFloat.infinity, height: 800),
                     CGSize(width: 800, height: CGFloat.nan), CGSize(width: 800, height: 0)] {
            XCTAssertFalse(AdaptiveWorkspaceLayout.resolve(size: size).showsContext)
        }
    }
}

final class AdaptiveWorkspacePlacementTests: XCTestCase {
    func testPortraitKeepsTheWholeUsableWindow() {
        let size = CGSize(width: 393, height: 750)
        let placement = AdaptiveWorkspacePlacement.resolve(size: size)
        XCTAssertEqual(placement.primary, CGRect(origin: .zero, size: size))
        XCTAssertNil(placement.context)
        XCTAssertFalse(placement.layout.isShort)
    }

    func testBookColumnsStayOnTheirOwnSidesOfTheReportedDivision() throws {
        let division = CGRect(x: 410, y: 0, width: 24, height: 700)
        let placement = AdaptiveWorkspacePlacement.resolve(size: CGSize(width: 850, height: 700),
                                                            divisions: [division])
        let context = try XCTUnwrap(placement.context)
        XCTAssertLessThanOrEqual(placement.primary.maxX, division.minX)
        XCTAssertGreaterThanOrEqual(context.minX, division.maxX)
        XCTAssertTrue(placement.primary.intersection(division).isEmpty)
        XCTAssertTrue(context.intersection(division).isEmpty)
    }

    func testTabletopPutsTheControlsBelowTheDivisionAndContextAbove() throws {
        let division = CGRect(x: 0, y: 430, width: 900, height: 30)
        let placement = AdaptiveWorkspacePlacement.resolve(size: CGSize(width: 900, height: 900),
                                                            divisions: [division])
        let context = try XCTUnwrap(placement.context)
        XCTAssertGreaterThanOrEqual(placement.primary.minY, division.maxY)
        XCTAssertLessThanOrEqual(context.maxY, division.minY)
        XCTAssertTrue(placement.layout.isShort, "The lower control surface uses the compact status header")
        XCTAssertEqual(placement.primary.height
                       - (placement.layout.dockReservation(availableHeight: placement.primary.height,
                                                           measuredSurface: nil) ?? 0), 250)
    }

    func testLargeTextCollapsesContextWithinAUsableRegion() {
        let division = CGRect(x: 400, y: 0, width: 20, height: 700)
        let placement = AdaptiveWorkspacePlacement.resolve(size: CGSize(width: 1000, height: 700),
                                                            accessibilityText: true, divisions: [division])
        XCTAssertNil(placement.context)
        XCTAssertEqual(placement.primary.width, 580)
        XCTAssertTrue(placement.primary.intersection(division).isEmpty)
    }

    func testRightToLeftKeepsThePrimaryOnTheLeadingSideOfTheDivision() throws {
        let placement = AdaptiveWorkspacePlacement.resolve(
            size: CGSize(width: 1000, height: 700), rightToLeft: true,
            divisions: [CGRect(x: 400, y: 0, width: 20, height: 700)])
        XCTAssertEqual(placement.primary.minX, 420)
        XCTAssertEqual(try XCTUnwrap(placement.context).maxX, 400)
    }

    func testResizingEitherBookRegionNeverCompressesAVisibleColumnBelowItsMinimum() {
        let size = CGSize(width: 1000, height: 700)
        for x in stride(from: CGFloat(100), through: 900, by: 17) {
            let division = CGRect(x: x, y: 0, width: 20, height: size.height)
            let placement = AdaptiveWorkspacePlacement.resolve(size: size, divisions: [division])
            XCTAssertTrue(placement.primary.intersection(division).isEmpty)
            if let context = placement.context {
                XCTAssertGreaterThanOrEqual(placement.primary.width, 340)
                XCTAssertGreaterThanOrEqual(context.width, 280)
                XCTAssertTrue(context.intersection(division).isEmpty)
            }
        }
    }

    func testInactiveAndOutOfWindowDivisionsDoNotChangeTheLayout() {
        let size = CGSize(width: 850, height: 700)
        XCTAssertEqual(AdaptiveWorkspacePlacement.resolve(size: size),
                       AdaptiveWorkspacePlacement.resolve(size: size, divisions: [
                        CGRect(x: 400, y: 0, width: 0, height: 700),
                        CGRect(x: 1000, y: 0, width: 20, height: 700)]))
    }
}

@MainActor
final class ManualFigurePresentationTests: XCTestCase {
    private func request() -> AppState.ManualFigureRequest {
        func stop(_ id: String) -> AppState.ManualFigureRequest.Stop {
            let figure = FieldSessionService.StagedFigure(documentId: id, documentTitle: id, page: 1)
            return .init(presenter: ManualFigurePresenter(figure: figure, sourceURL: nil),
                         sheet: ManualPageSheetModel(
                            citation: figure.citation, documentTitle: id, citedPage: 1,
                            extractedPages: [.init(number: 1, text: "First page"),
                                             .init(number: 2, text: "Second page")]))
        }
        let first = stop("workspace-first")
        return .init(presenter: first.presenter, sheet: first.sheet,
                     others: [stop("workspace-second")])
    }

    func testSourceAndPageSurviveASecondPresentationOfTheSameCitation() {
        let presentation = ManualFigurePresentation(session: nil)
        let request = request()
        let first = presentation.controller(for: request, at: 0)
        first.next()
        presentation.select(1, in: request)

        XCTAssertEqual(presentation.index(for: request), 1)
        XCTAssertTrue(presentation.controller(for: request, at: 0) === first)
        XCTAssertEqual(presentation.controller(for: request, at: 0).model.paging.currentPage, 2)
        XCTAssertEqual(presentation.controller(for: request, at: 1).model.paging.currentPage, 1)
    }

    func testClosingTheReferenceReleasesItsReadingPosition() {
        let presentation = ManualFigurePresentation(session: nil)
        let request = request()
        presentation.controller(for: request, at: 0).next()
        presentation.select(1, in: request)
        presentation.reset()
        XCTAssertEqual(presentation.index(for: request), 0)
        XCTAssertEqual(presentation.controller(for: request, at: 0).model.paging.currentPage, 1)
    }
}
