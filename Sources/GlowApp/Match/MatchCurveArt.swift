import SwiftUI

/// A saved or about-to-be-saved curve, drawn: the reference's level across, the matched
/// display's up, with a dot at each comparison point.
struct MatchCurveArt: View {
    let curve: BrightnessCurve

    var body: some View {
        Canvas { context, size in
            let inset = CGRect(x: 6, y: 6, width: size.width - 12, height: size.height - 12)
            let point = { (p: CalibrationPoint) in CGPoint(x: inset.minX + inset.width * p.reference, y: inset.maxY - inset.height * p.display) }
            var axis = Path()
            axis.move(to: CGPoint(x: inset.minX, y: inset.minY))
            axis.addLine(to: CGPoint(x: inset.minX, y: inset.maxY))
            axis.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
            context.stroke(axis, with: .color(GlowTokens.Text.tertiary), lineWidth: 1)
            // The same line for both displays at once, for comparison.
            var same = Path()
            same.move(to: CGPoint(x: inset.minX, y: inset.maxY))
            same.addLine(to: CGPoint(x: inset.maxX, y: inset.minY))
            context.stroke(same, with: .color(GlowTokens.Border.tile), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            guard let first = curve.points.first else { return }
            var line = Path()
            line.move(to: point(first))
            curve.points.dropFirst().forEach { line.addLine(to: point($0)) }
            if let last = curve.points.last, last.reference < 1 {
                line.addLine(to: point(CalibrationPoint(reference: 1, display: last.display)))
            }
            context.stroke(line, with: .color(GlowTokens.Accent.primary), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            for p in curve.points where p.reference > 0 {
                let center = point(p)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)), with: .color(GlowTokens.Accent.primary))
            }
        }
        .background(RoundedRectangle(cornerRadius: GlowTokens.Radius.control, style: .continuous).fill(GlowTokens.Surface.tile))
        .accessibilityHidden(true)
    }
}
