import XCTest
import CoreGraphics
@testable import BuddySafariDOM

final class SafariCoordinateMappingTests: XCTestCase {
    // Live capture against online.moysklad.ru at scrollY=0: pointing at "Товары"
    // landed under the nav row before the width-only scale fix. Use the captured
    // viewport rect (= AXWebArea at scroll 0) and CSS rect to lock the mapping.
    func testProject_usesWidthScaleForBothAxes() {
        let viewportFrame = CGRect(x: 0, y: 85, width: 1512, height: 897)
        let viewportWidth: CGFloat = 1512
        let rect = CGRect(x: 280, y: 75, width: 52, height: 13)

        let projected = SafariCoordinateMapping.project(
            viewportRect: rect,
            viewportWidth: viewportWidth,
            viewportScreenFrame: viewportFrame
        )

        XCTAssertEqual(projected.minX, 280, accuracy: 0.001)
        XCTAssertEqual(projected.minY, 160, accuracy: 0.001)
        XCTAssertEqual(projected.width, 52, accuracy: 0.001)
        XCTAssertEqual(projected.height, 13, accuracy: 0.001)
    }

    func testProject_translatesByViewportOrigin() {
        let viewportFrame = CGRect(x: 100, y: 200, width: 800, height: 600)

        let projected = SafariCoordinateMapping.project(
            viewportRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            viewportWidth: 800,
            viewportScreenFrame: viewportFrame
        )

        XCTAssertEqual(projected.minX, 100, accuracy: 0.001)
        XCTAssertEqual(projected.minY, 200, accuracy: 0.001)
    }

    func testProject_appliesBrowserZoomUniformly() {
        // Browser zoomed to 150%: rendered viewport in AX-pt is 1.5x CSS viewport.
        let viewportFrame = CGRect(x: 0, y: 0, width: 1500, height: 900)
        let projected = SafariCoordinateMapping.project(
            viewportRect: CGRect(x: 100, y: 200, width: 50, height: 20),
            viewportWidth: 1000,
            viewportScreenFrame: viewportFrame
        )

        XCTAssertEqual(projected.minX, 150, accuracy: 0.001)
        XCTAssertEqual(projected.minY, 300, accuracy: 0.001)
        XCTAssertEqual(projected.width, 75, accuracy: 0.001)
        XCTAssertEqual(projected.height, 30, accuracy: 0.001)
    }

    func testProject_zeroViewportWidthFallsBackToIdentityScale() {
        let viewportFrame = CGRect(x: 50, y: 60, width: 0, height: 0)
        let projected = SafariCoordinateMapping.project(
            viewportRect: CGRect(x: 10, y: 20, width: 30, height: 40),
            viewportWidth: 0,
            viewportScreenFrame: viewportFrame
        )

        XCTAssertEqual(projected.minX, 60, accuracy: 0.001)
        XCTAssertEqual(projected.minY, 80, accuracy: 0.001)
        XCTAssertEqual(projected.width, 30, accuracy: 0.001)
        XCTAssertEqual(projected.height, 40, accuracy: 0.001)
    }

    // Regression: Safari's AXWebArea is anchored to the document top, so after
    // a deep scroll its origin goes deeply negative (-1061 here). Projecting a
    // sticky toolbar button (viewport y=16) directly against AXWebArea.minY
    // gives an AX y of -1045 — far above the screen — and offscreenInfo emits
    // direction:.above. SafariDOMExtractor must reshape AXWebArea into the
    // viewport's stable screen rect before projection; this test pins that
    // behavior.
    func testViewportScreenFrame_anchorsAcrossDeepScroll() {
        // Live capture from online.moysklad.ru at scrollY=1146:
        let webAreaFrame = CGRect(x: 0, y: -1061, width: 1512, height: 2043)
        let viewport = SafariDOMExtractor.Viewport(
            w: 1512, h: 897,
            scrollX: 0, scrollY: 1146,
            dpr: 2,
            visualOffsetX: 0, visualOffsetY: 0,
            visualScale: 1
        )

        let viewportFrame = SafariDOMExtractor.viewportScreenFrame(
            webAreaFrame: webAreaFrame,
            viewport: viewport
        )

        // 85 = Safari chrome height; this should hold regardless of scrollY.
        XCTAssertEqual(viewportFrame.minY, 85, accuracy: 0.001)
        XCTAssertEqual(viewportFrame.minX, 0, accuracy: 0.001)
        XCTAssertEqual(viewportFrame.width, 1512, accuracy: 0.001)

        // Sticky save button: rect.y=16 must land at AX y=101 (visible), not at
        // -1045 (off the top of every screen).
        let stickyButton = CGRect(x: 32, y: 16, width: 99, height: 28)
        let projected = SafariCoordinateMapping.project(
            viewportRect: stickyButton,
            viewportWidth: CGFloat(viewport.w),
            viewportScreenFrame: viewportFrame
        )
        XCTAssertEqual(projected.minY, 101, accuracy: 0.001)
        XCTAssertEqual(projected.minX, 32, accuracy: 0.001)
    }

    func testViewportScreenFrame_stableUnderScroll() {
        let viewport0 = SafariDOMExtractor.Viewport(
            w: 1512, h: 897, scrollX: 0, scrollY: 0, dpr: 2,
            visualOffsetX: 0, visualOffsetY: 0, visualScale: 1
        )
        let viewport1 = SafariDOMExtractor.Viewport(
            w: 1512, h: 897, scrollX: 0, scrollY: 1146, dpr: 2,
            visualOffsetX: 0, visualOffsetY: 0, visualScale: 1
        )
        // AXWebArea at scrollY=0: minY=85, height=897 (viewport-sized).
        let waf0 = CGRect(x: 0, y: 85, width: 1512, height: 897)
        // After scrolling 1146 down: doc top has moved up by 1146 in AX-pt.
        let waf1 = CGRect(x: 0, y: -1061, width: 1512, height: 2043)

        let f0 = SafariDOMExtractor.viewportScreenFrame(webAreaFrame: waf0, viewport: viewport0)
        let f1 = SafariDOMExtractor.viewportScreenFrame(webAreaFrame: waf1, viewport: viewport1)

        XCTAssertEqual(f0.minY, f1.minY, accuracy: 0.001)
        XCTAssertEqual(f0.minX, f1.minX, accuracy: 0.001)
    }
}
