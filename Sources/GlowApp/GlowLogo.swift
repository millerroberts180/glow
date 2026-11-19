import AppKit

/// Glow's mark, Aperture Spark: a four-point spark of light drawn as one closed, rounded line
/// with its centre left open. Drawn in code from the geometry in design/logo/generate.py (its
/// 256-unit grid; keep the two in step), as Tuck's, Pulse's and Hum's marks are, so there is no
/// image to bundle and the line takes whatever colour it's given.
enum GlowLogo {
    /// One cut of the spark, by its top-right side: the top tip, the handle leaving it, the
    /// handle arriving at the right tip, and the right tip. The other three sides mirror it.
    private struct Cut {
        let top: CGPoint
        let leaving: CGPoint
        let arriving: CGPoint
        let right: CGPoint
        let weight: CGFloat
    }

    /// The master, centred on the family's optical line, y 126.
    private static let regular = Cut(top: CGPoint(x: 128, y: 48), leaving: CGPoint(x: 137, y: 77),
                                     arriving: CGPoint(x: 168, y: 108), right: CGPoint(x: 216, y: 126), weight: 24)
    /// Below 32 pt: bolder and a little larger, centred on y 128 so the line lands on whole
    /// pixels at 16 px.
    private static let small = Cut(top: CGPoint(x: 128, y: 48), leaving: CGPoint(x: 140, y: 78),
                                   arriving: CGPoint(x: 170, y: 108), right: CGPoint(x: 224, y: 128), weight: 32)

    private static func cut(for side: CGFloat) -> Cut { side < 32 ? small : regular }

    /// The spark in a square of `side` points, y down, to be stroked `lineWidth(side:)` wide
    /// with round joins.
    static func sparkPath(side: CGFloat) -> CGPath {
        let cut = cut(for: side), scale = side / 256
        let centre = CGPoint(x: cut.top.x, y: cut.right.y)
        func point(_ p: CGPoint, _ sx: CGFloat = 1, _ sy: CGFloat = 1) -> CGPoint {
            CGPoint(x: (centre.x + sx * (p.x - centre.x)) * scale, y: (centre.y + sy * (p.y - centre.y)) * scale)
        }
        let path = CGMutablePath()
        path.move(to: point(cut.top))
        path.addCurve(to: point(cut.right), control1: point(cut.leaving), control2: point(cut.arriving))
        path.addCurve(to: point(cut.top, 1, -1), control1: point(cut.arriving, 1, -1), control2: point(cut.leaving, 1, -1))
        path.addCurve(to: point(cut.right, -1, 1), control1: point(cut.leaving, -1, -1), control2: point(cut.arriving, -1, -1))
        path.addCurve(to: point(cut.top), control1: point(cut.arriving, -1, 1), control2: point(cut.leaving, -1, 1))
        path.closeSubpath()
        return path
    }

    static func lineWidth(side: CGFloat) -> CGFloat { cut(for: side).weight * side / 256 }

    /// The menu-bar icon: the small cut as a template image, so the menu bar tints it.
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            draw(in: rect, color: .black)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Glow"
        return image
    }

    /// The mark alone, square, in the given colour: Apricot Terracotta unless told otherwise.
    static func markImage(side: CGFloat, color: NSColor = GlowTokens.Brand.glowColor) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            draw(in: rect, color: color)
            return true
        }
        image.accessibilityDescription = "Glow"
        return image
    }

    private static func draw(in rect: NSRect, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.minY)
        context.addPath(sparkPath(side: rect.width))
        context.setLineWidth(lineWidth(side: rect.width))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(color.cgColor)
        context.strokePath()
    }
}
