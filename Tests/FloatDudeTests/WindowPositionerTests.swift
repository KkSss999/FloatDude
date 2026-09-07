import CoreGraphics
import XCTest
@testable import FloatDude

final class WindowPositionerTests: XCTestCase {
    func testIPhone17ProMaxCanvasIsTheMaximumAt1080pAndLarger() {
        let fullHD = PanelSizePolicy.maximumSize(
            for: CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        )
        let larger = PanelSizePolicy.maximumSize(
            for: CGRect(x: 0, y: 0, width: 2_560, height: 1_440)
        )

        XCTAssertEqual(fullHD, CGSize(width: 440, height: 956))
        XCTAssertEqual(larger, CGSize(width: 440, height: 956))
    }

    func testPanelCanvasScalesProportionallyBelow1080pBeforeSafeFrameClamp() {
        let display = CGRect(x: 0, y: 0, width: 1_600, height: 900)
        let fitted = PanelSizePolicy.fittedPanelSize(
            CGSize(width: 440, height: 956),
            displayFrame: display,
            visibleFrame: display,
            edgeInset: 12
        )

        XCTAssertEqual(fitted.width, 440 * 900 / 1_080, accuracy: 0.01)
        XCTAssertEqual(fitted.height, 956 * 900 / 1_080, accuracy: 0.01)
    }

    func testUsesDisplayContainingCursor() {
        let displays = [
            DisplayGeometry(
                frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 760)
            ),
            DisplayGeometry(
                frame: CGRect(x: 1000, y: 0, width: 1200, height: 900),
                visibleFrame: CGRect(x: 1000, y: 0, width: 1200, height: 860)
            )
        ]

        let origin = WindowPlacementCalculator.origin(
            forPanelSize: CGSize(width: 300, height: 180),
            cursorLocation: CGPoint(x: 2050, y: 450),
            displays: displays
        )

        XCTAssertGreaterThanOrEqual(origin.x, 1000 + WindowPlacementCalculator.defaultEdgeInset)
        XCTAssertLessThanOrEqual(origin.x + 300, 2200 - WindowPlacementCalculator.defaultEdgeInset)
        XCTAssertGreaterThanOrEqual(origin.y, WindowPlacementCalculator.defaultEdgeInset)
        XCTAssertLessThanOrEqual(origin.y + 180, 860 - WindowPlacementCalculator.defaultEdgeInset)
    }

    func testClampsPanelInsideVisibleFrameNearEdges() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let origin = WindowPlacementCalculator.origin(
            forPanelSize: CGSize(width: 300, height: 180),
            cursorLocation: CGPoint(x: 795, y: 595),
            visibleFrame: visibleFrame
        )

        XCTAssertGreaterThanOrEqual(origin.x, 12)
        XCTAssertGreaterThanOrEqual(origin.y, 12)
        XCTAssertLessThanOrEqual(origin.x + 300, 788)
        XCTAssertLessThanOrEqual(origin.y + 180, 588)
    }

    func testAvoidsSelectionAndCursorRectWhenRoomIsAvailable() {
        let selection = CGRect(x: 430, y: 330, width: 180, height: 48)
        let cursor = CGPoint(x: 520, y: 354)
        let panelSize = CGSize(width: 280, height: 160)
        let origin = WindowPlacementCalculator.origin(
            forPanelSize: panelSize,
            cursorLocation: cursor,
            visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 800),
            avoiding: selection
        )

        XCTAssertFalse(CGRect(origin: origin, size: panelSize).intersects(selection))
        XCTAssertFalse(CGRect(origin: origin, size: panelSize).contains(cursor))
    }

    func testSelectionBoundsBecomePrimaryAnchorWhenCursorIsFarAway() {
        let panelSize = CGSize(width: 300, height: 180)
        let selection = CGRect(x: 180, y: 520, width: 220, height: 24)

        let origin = WindowPlacementCalculator.origin(
            forPanelSize: panelSize,
            cursorLocation: CGPoint(x: 1_050, y: 720),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_200, height: 800),
            avoiding: selection
        )

        XCTAssertEqual(origin.x, selection.minX, accuracy: 0.5)
        XCTAssertEqual(origin.y, selection.minY - panelSize.height - 14, accuracy: 0.5)
        XCTAssertFalse(CGRect(origin: origin, size: panelSize).intersects(selection))
    }

    func testSelectionDisplayWinsWhenCursorIsOnAnotherDisplay() {
        let displays = [
            DisplayGeometry(
                frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
                visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 760)
            ),
            DisplayGeometry(
                frame: CGRect(x: 1_000, y: 0, width: 1_200, height: 900),
                visibleFrame: CGRect(x: 1_000, y: 0, width: 1_200, height: 860)
            ),
        ]
        let selection = CGRect(x: 1_300, y: 500, width: 200, height: 24)

        let origin = WindowPlacementCalculator.origin(
            forPanelSize: CGSize(width: 400, height: 236),
            cursorLocation: CGPoint(x: 300, y: 400),
            displays: displays,
            avoiding: selection
        )

        XCTAssertGreaterThanOrEqual(origin.x, 1_012)
        XCTAssertLessThanOrEqual(origin.x + 400, 2_188)
        XCTAssertEqual(origin, CGPoint(x: 1_300, y: 250))
    }

    func testInvalidOffscreenSelectionFallsBackToCursorDisplay() {
        let origin = WindowPlacementCalculator.origin(
            forPanelSize: CGSize(width: 300, height: 180),
            cursorLocation: CGPoint(x: 500, y: 400),
            displays: [DisplayGeometry(
                frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
                visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 760)
            )],
            avoiding: CGRect(x: 50_000, y: 50_000, width: 100, height: 20)
        )

        XCTAssertEqual(origin, CGPoint(x: 514, y: 206))
    }

    func testSelectionAnchorFlipsAboveNearBottomScreenEdge() {
        let panelSize = CGSize(width: 300, height: 220)
        let selection = CGRect(x: 180, y: 24, width: 160, height: 24)

        let origin = WindowPlacementCalculator.origin(
            forPanelSize: panelSize,
            cursorLocation: CGPoint(x: 1_000, y: 700),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_200, height: 800),
            avoiding: selection
        )

        XCTAssertEqual(origin.x, selection.minX, accuracy: 0.5)
        XCTAssertEqual(origin.y, selection.maxY + 14, accuracy: 0.5)
        XCTAssertFalse(CGRect(origin: origin, size: panelSize).intersects(selection))
    }

    func testOversizedPanelIsFittedToVisibleFrame() {
        let size = WindowPlacementCalculator.fittedPanelSize(
            CGSize(width: 1200, height: 900),
            in: CGRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(size, CGSize(width: 776, height: 576))
    }
}
