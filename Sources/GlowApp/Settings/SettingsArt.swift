import SwiftUI

/// Small drawings for Settings' tiles. Each draws what its choice does; all are decorative
/// and hidden from VoiceOver, since the tile's title carries the meaning.
enum DeviceShape {
    case laptop, monitor

    /// Draws the device in `rect`, its screen filled with `light` and outlined with `ink`.
    static func draw(_ shape: DeviceShape, in rect: CGRect, light: Color?, ink: Color, lineWidth: CGFloat, context: GraphicsContext) {
        let screenHeight = rect.height * (shape == .laptop ? 0.78 : 0.70)
        let screenWidth = min(rect.width * (shape == .laptop ? 0.80 : 1), screenHeight * 1.6)
        let screen = CGRect(x: rect.midX - screenWidth / 2, y: rect.minY, width: screenWidth, height: screenHeight)
        let radius = max(1.5, screenHeight * 0.08)
        let screenPath = Path(roundedRect: screen, cornerRadius: radius, style: .continuous)
        if let light { context.fill(screenPath, with: .color(light)) }
        context.stroke(screenPath, with: .color(ink), lineWidth: lineWidth)
        switch shape {
        case .laptop:
            let deck = CGRect(x: rect.midX - screenWidth * 0.62, y: screen.maxY + lineWidth, width: screenWidth * 1.24, height: max(2, rect.height * 0.09))
            context.fill(Path(roundedRect: deck, cornerRadius: deck.height / 2, style: .continuous), with: .color(ink))
        case .monitor:
            var neck = Path()
            neck.move(to: CGPoint(x: rect.midX, y: screen.maxY))
            neck.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - lineWidth))
            context.stroke(neck, with: .color(ink), style: StrokeStyle(lineWidth: lineWidth * 1.4, lineCap: .round))
            var base = Path()
            base.move(to: CGPoint(x: rect.midX - screenWidth * 0.18, y: rect.maxY - lineWidth))
            base.addLine(to: CGPoint(x: rect.midX + screenWidth * 0.18, y: rect.maxY - lineWidth))
            context.stroke(base, with: .color(ink), style: StrokeStyle(lineWidth: lineWidth * 1.4, lineCap: .round))
        }
    }
}

/// A display, drawn: a laptop for the built-in screen, a monitor otherwise, its screen as
/// bright as the display's brightness reading.
struct DisplayGlyph: View {
    let isBuiltIn: Bool
    /// Brightness from 0 to 1, or nil when there's no reading.
    let level: Double?
    var highlighted = false

    var body: some View {
        Canvas { context, size in
            let ink = highlighted ? GlowTokens.Accent.primary : GlowTokens.Text.secondary
            let light = highlighted
                ? GlowTokens.Accent.primary.opacity(0.12 + 0.30 * (level ?? 0.3))
                : GlowTokens.Text.secondary.opacity(0.08 + 0.18 * (level ?? 0.3))
            let height = min(size.height * 0.78, size.width * 0.5)
            let rect = CGRect(x: (size.width - height * 1.7) / 2, y: (size.height - height) / 2, width: height * 1.7, height: height)
            DeviceShape.draw(isBuiltIn ? .laptop : .monitor, in: rect, light: light, ink: ink, lineWidth: 1.5, context: context)
        }
        .accessibilityHidden(true)
    }
}

/// A desk of three displays, lit to show which ones the brightness keys change.
struct ControlTargetArt: View {
    let target: ControlTarget
    let highlighted: Bool

    var body: some View {
        Canvas { context, size in
            let ink = highlighted ? GlowTokens.Accent.primary : GlowTokens.Text.secondary
            let light = highlighted ? GlowTokens.Accent.primary.opacity(0.55) : GlowTokens.Text.secondary.opacity(0.45)
            let deviceHeight = size.height * 0.46
            let deviceWidth = deviceHeight * 1.45
            let gap = deviceWidth * 0.22
            let total = deviceWidth * 3 + gap * 2
            let lit: [Bool] = switch target {
            case .all: [true, true, true]
            case .underCursor: [false, true, false]
            case .focused: [false, false, true]
            case .macOnly: [true, false, false]
            }
            var screens: [CGRect] = []
            for index in 0..<3 {
                let rect = CGRect(x: (size.width - total) / 2 + CGFloat(index) * (deviceWidth + gap), y: (size.height - deviceHeight) / 2, width: deviceWidth, height: deviceHeight)
                DeviceShape.draw(index == 0 ? .laptop : .monitor, in: rect, light: lit[index] ? light : nil, ink: ink, lineWidth: 1.2, context: context)
                screens.append(rect)
            }
            switch target {
            case .underCursor:
                // A pointer resting on the middle display.
                let tip = CGPoint(x: screens[1].midX + 1, y: screens[1].minY + deviceHeight * 0.22)
                let s = deviceHeight * 0.42
                var arrow = Path()
                arrow.move(to: tip)
                arrow.addLine(to: CGPoint(x: tip.x, y: tip.y + s))
                arrow.addLine(to: CGPoint(x: tip.x + s * 0.28, y: tip.y + s * 0.74))
                arrow.addLine(to: CGPoint(x: tip.x + s * 0.62, y: tip.y + s * 0.74))
                arrow.closeSubpath()
                context.fill(arrow, with: .color(.white))
                context.stroke(arrow, with: .color(ink), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
            case .focused:
                // A front window on the right-hand display.
                let screen = screens[2]
                let window = CGRect(x: screen.midX - deviceWidth * 0.26, y: screen.minY + deviceHeight * 0.14, width: deviceWidth * 0.52, height: deviceHeight * 0.38)
                context.fill(Path(roundedRect: window, cornerRadius: 1.5), with: .color(.white.opacity(0.9)))
                context.stroke(Path(roundedRect: window, cornerRadius: 1.5), with: .color(ink), lineWidth: 1)
            case .all, .macOnly:
                break
            }
        }
        .accessibilityHidden(true)
    }
}

/// Brightness Match's two ways, drawn as curves: one comparison sets a straight line;
/// several points shape a curve.
struct MatchMethodArt: View {
    let method: MatchMethod
    let highlighted: Bool

    var body: some View {
        Canvas { context, size in
            let ink = highlighted ? GlowTokens.Accent.primary : GlowTokens.Text.secondary
            let inset = CGRect(x: size.width * 0.5 - 34, y: 8, width: 68, height: size.height - 16)
            let point = { (x: Double, y: Double) in CGPoint(x: inset.minX + inset.width * x, y: inset.maxY - inset.height * y) }
            var axis = Path()
            axis.move(to: point(0, 1))
            axis.addLine(to: point(0, 0))
            axis.addLine(to: point(1, 0))
            context.stroke(axis, with: .color(GlowTokens.Text.tertiary), lineWidth: 1)
            let samples: [(Double, Double)]
            var line = Path()
            // As `MatchCurve` builds them: Quick a ratio from both displays' darkest through
            // its one point, Guided straight lines through five.
            switch method {
            case .quick:
                samples = [(0.55, 0.5)]
                line.move(to: point(0, 0))
                line.addLine(to: point(1, 0.91))
            case .guided:
                samples = [(0.2, 0.3), (0.4, 0.5), (0.6, 0.64), (0.8, 0.78), (1.0, 0.9)]
                line.move(to: point(0, 0))
                samples.forEach { line.addLine(to: point($0.0, $0.1)) }
            }
            context.stroke(line, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            for (x, y) in samples {
                let center = point(x, y)
                let dot = Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6))
                context.fill(dot, with: .color(ink))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A brightness level two ways, beside a small sun: a slider with its knob, or a row of
/// boxes like macOS's own overlay, the last lit one part full.
struct LevelStyleArt: View {
    let style: LevelStyle
    let highlighted: Bool

    var body: some View {
        Canvas { context, size in
            let ink = highlighted ? GlowTokens.Accent.primary : GlowTokens.Text.secondary
            let level = 0.6
            let width = min(size.width - 24, 96.0)
            let sunRadius = 3.5
            let left = (size.width - width) / 2
            let mid = size.height / 2
            let sun = CGPoint(x: left + sunRadius + 2, y: mid)
            context.fill(Path(ellipseIn: CGRect(x: sun.x - sunRadius, y: sun.y - sunRadius, width: sunRadius * 2, height: sunRadius * 2)), with: .color(ink))
            for ray in 0..<8 {
                let angle = Double(ray) * .pi / 4
                var path = Path()
                path.move(to: CGPoint(x: sun.x + cos(angle) * (sunRadius + 1.5), y: sun.y + sin(angle) * (sunRadius + 1.5)))
                path.addLine(to: CGPoint(x: sun.x + cos(angle) * (sunRadius + 3.5), y: sun.y + sin(angle) * (sunRadius + 3.5)))
                context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
            let track = CGRect(x: sun.x + sunRadius + 8, y: mid, width: left + width - (sun.x + sunRadius + 8), height: 0)
            switch style {
            case .slider:
                let bar = CGRect(x: track.minX, y: mid - 2, width: track.width, height: 4)
                context.fill(Path(roundedRect: bar, cornerRadius: 2), with: .color(ink.opacity(0.25)))
                context.fill(Path(roundedRect: CGRect(x: bar.minX, y: bar.minY, width: bar.width * level, height: bar.height), cornerRadius: 2), with: .color(ink))
                let knob = CGRect(x: bar.minX + bar.width * level - 6, y: mid - 6, width: 12, height: 12)
                context.fill(Path(ellipseIn: knob), with: .color(.white))
                context.stroke(Path(ellipseIn: knob), with: .color(ink), lineWidth: 1)
            case .boxes:
                let count = OverlayBoxes.count
                let gap = 1.5
                let boxWidth = (track.width - gap * Double(count - 1)) / Double(count)
                let fills = OverlayBoxes.fills(level: level + 0.02, count: count)
                for (index, fill) in fills.enumerated() {
                    let box = CGRect(x: track.minX + Double(index) * (boxWidth + gap), y: mid - 3.5, width: boxWidth, height: 7)
                    let shape = Path(roundedRect: box, cornerRadius: 1, style: .continuous)
                    context.fill(shape, with: .color(ink.opacity(0.22)))
                    if fill > 0 {
                        var lit = context
                        lit.clip(to: shape)
                        lit.fill(Path(CGRect(x: box.minX, y: box.minY, width: box.width * fill, height: box.height)), with: .color(ink))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
