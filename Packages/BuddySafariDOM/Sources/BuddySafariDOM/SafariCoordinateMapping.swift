import CoreGraphics
import Foundation

// Projects a viewport CSS-pixel rect (as returned by JS getBoundingClientRect)
// into AX screen coordinates.
//
// The caller passes `viewportScreenFrame` — the visible viewport's bounding
// rect in AX screen coords. It is NOT the same as Safari's `AXWebArea` frame:
// AXWebArea in Safari is anchored to the DOCUMENT top, so its origin slides
// up by `scrollY` (in AX points) as the user scrolls. The viewport's
// on-screen position, in contrast, is stable while the user scrolls inside
// the same window. SafariDOMExtractor reshapes AXWebArea into the viewport
// frame before calling here.
//
// Width-only scaling: CSS pixels are square, so a single
// `pointsPerCSSPixel = viewportScreenFrame.width / viewportWidth` is the
// right ratio for both axes and absorbs browser zoom (Cmd+/Cmd-).
//
// Known limitations, intentionally out of scope:
//   - Horizontal scrollbars / odd insets can make `viewportScreenFrame.width`
//     disagree with the visual viewport width. Rare on the target apps.
//   - Pinch zoom (visualViewport.scale / offset) is ignored.
//   - The captured viewport frame goes stale if the user moves or resizes
//     the Safari window between extract and resolve. A fresh `get_ui_tree`
//     refreshes it.
enum SafariCoordinateMapping {
    /// Maps a viewport-relative CSS-pixel rect to AX screen coordinates.
    ///
    /// - Parameters:
    ///   - viewportRect: rect returned by `getBoundingClientRect()` (CSS pixels,
    ///     relative to the visible viewport).
    ///   - viewportWidth: `visualViewport.width` / `innerWidth` in CSS pixels.
    ///   - viewportScreenFrame: AX-coordinate bounding rect of the **visible**
    ///     viewport (NOT the AXWebArea — see file comment).
    static func project(
        viewportRect rect: CGRect,
        viewportWidth: CGFloat,
        viewportScreenFrame: CGRect
    ) -> CGRect {
        let scale: CGFloat = viewportWidth > 0 ? viewportScreenFrame.width / viewportWidth : 1
        return CGRect(
            x: viewportScreenFrame.minX + rect.minX * scale,
            y: viewportScreenFrame.minY + rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }
}
