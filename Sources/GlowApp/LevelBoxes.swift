import SwiftUI

/// A brightness or volume range as a row of boxes sees it: sixteen boxes, like macOS’s own
/// brightness overlay, each a sixteenth of the range. Every value it gives lands on one of
/// the setting's steps.
struct LevelBoxScale: Equatable {
    static let boxCount = 16

    var minimum: Double
    var maximum: Double
    var step: Double
    var count = LevelBoxScale.boxCount

    /// How far along the range a value sits, from 0 to 1.
    func fraction(of value: Double) -> Double {
        guard maximum > minimum else { return 0 }
        return min(1, max(0, (value - minimum) / (maximum - minimum)))
    }

    /// The value at a fraction of the range, rounded to the setting's step.
    func value(atFraction fraction: Double) -> Double {
        let raw = minimum + min(1, max(0, fraction)) * (maximum - minimum)
        guard step > 0 else { return raw }
        let snapped = minimum + ((raw - minimum) / step).rounded() * step
        return min(maximum, max(minimum, snapped))
    }

    /// The value with the first `boxes` boxes lit and the rest dark.
    func value(ofBoxes boxes: Int) -> Double {
        value(atFraction: Double(boxes) / Double(count))
    }

    /// How full each box is at a value, from 0 to 1, first box first. The box at the boundary
    /// fills in proportion: 47 % is seven full boxes and an eighth 52 % full.
    func fills(at value: Double) -> [Double] {
        let lit = fraction(of: value) * Double(count)
        return (0..<count).map { min(1, max(0, lit - Double($0))) }
    }

    /// A click on box `box`, counted from 1, lights it and every box before it. When the level
    /// already sits exactly there it steps down one box instead, so a click on the first box
    /// reaches the lowest level.
    func valueForClick(onBox box: Int, current: Double) -> Double {
        let target = value(ofBoxes: box)
        return target == current ? stepped(current, by: -1) : target
    }

    /// The level `boxes` box edges above the value, or below it when negative. On a short
    /// range two boxes can round to the same value, so each step goes to the next edge whose
    /// value differs; at either end the value stays.
    func stepped(_ current: Double, by boxes: Int) -> Double {
        let edges = (0...count).map { value(ofBoxes: $0) }
        var level = current
        for _ in 0..<abs(boxes) {
            level = (boxes > 0 ? edges.first { $0 > level } : edges.last { $0 < level }) ?? level
        }
        return level
    }
}

/// Where the boxes sit across a width: `count` boxes of one width with `gap` between them.
/// Drawing and pointing both use it, so a click lands on the box that's drawn there.
struct LevelBoxGeometry: Equatable {
    var width: Double
    var gap: Double
    var count = LevelBoxScale.boxCount

    var boxWidth: Double { max(0, (width - gap * Double(count - 1)) / Double(count)) }

    /// The leading edge of box `index`, counted from 0.
    func minX(of index: Int) -> Double { Double(index) * (boxWidth + gap) }

    /// The box under a point, counted from 0. A point in a gap belongs to the nearer box, and
    /// one past either end to the box at that end.
    func box(at x: Double) -> Int {
        let pitch = boxWidth + gap
        guard pitch > 0 else { return 0 }
        return min(count - 1, max(0, Int(((x + gap / 2) / pitch).rounded(.down))))
    }

    /// The fraction of the range a point stands for, drawn the way the boxes fill: every box
    /// before it, and its share of its own box. A point in a gap fills the box before it.
    func fraction(at x: Double) -> Double {
        guard boxWidth > 0 else { return 0 }
        let clamped = min(width, max(0, x))
        let index = min(count - 1, Int((clamped / (boxWidth + gap)).rounded(.down)))
        let within = min(1, (clamped - minX(of: index)) / boxWidth)
        return (Double(index) + within) / Double(count)
    }
}

/// A level as sixteen rounded boxes in place of a slider, for someone who chose boxes in
/// Settings › Controls. A click lights a box and the ones before it, and a click on the top
/// lit box steps down one; a drag sets any level between. The arrow keys and VoiceOver's
/// adjust move one box at a time.
struct LevelBoxes: View {
    let scale: LevelBoxScale
    /// No reading yet draws every box dark.
    let value: Double?
    /// What VoiceOver calls the row and reads as its value.
    let label: String
    let spokenValue: String
    let propose: (Double) -> Void
    /// Snapshots stand in for the pointer resting over this box, counted from 0, and for
    /// keyboard focus.
    var hoverOverride: Int?
    var focusOverride = false

    @State private var hovered: Int?
    @State private var isDragging = false
    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled

    /// How far a press moves before it's a drag rather than a click on one box.
    private static let dragSlop: CGFloat = 3

    var body: some View {
        let level = value ?? scale.minimum
        let fills = scale.fills(at: level)
        let pointed = isEnabled ? hoverOverride ?? hovered : nil
        GeometryReader { proxy in
            let geometry = LevelBoxGeometry(width: proxy.size.width, gap: GlowTokens.Space.levelBoxGap, count: scale.count)
            ZStack(alignment: .leading) {
                ForEach(0..<scale.count, id: \.self) { index in
                    box(fill: fills[index], isHovered: index == pointed)
                        .frame(width: geometry.boxWidth)
                        .offset(x: geometry.minX(of: index))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(drag(geometry, from: level))
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hovered = geometry.box(at: point.x)
                case .ended: hovered = nil
                }
            }
        }
        .frame(height: GlowTokens.Size.levelBoxHeight)
        // Like a slider: focused from the keyboard when keyboard navigation is on, never by a
        // click or as the popover opens.
        .focusable(isEnabled, interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled()
        .overlay {
            RoundedRectangle(cornerRadius: GlowTokens.Radius.levelBoxFocus, style: .continuous)
                .strokeBorder(GlowTokens.Accent.glow, lineWidth: 2)
                .padding(-GlowTokens.Space.s1)
                .opacity(isFocused || focusOverride ? 1 : 0)
                .allowsHitTesting(false)
        }
        .onKeyPress(keys: [.leftArrow, .downArrow, .rightArrow, .upArrow]) { press in
            guard isEnabled else { return .ignored }
            move(by: press.key == .rightArrow || press.key == .upArrow ? 1 : -1, from: level)
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(spokenValue)
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: move(by: 1, from: level)
            case .decrement: move(by: -1, from: level)
            @unknown default: break
            }
        }
    }

    /// One box: the quiet tile fill, lit with the accent from its leading edge as far as the
    /// level reaches. The box under the pointer lifts like an action button does, its accent
    /// a little lighter.
    private func box(fill: Double, isHovered: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: GlowTokens.Radius.levelBox, style: .continuous)
        let lit = !isEnabled ? GlowTokens.Text.tertiary : isHovered ? GlowTokens.Accent.lifted : GlowTokens.Accent.primary
        return shape
            .fill(isHovered ? GlowTokens.Surface.tileHover : GlowTokens.Surface.tile)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(lit)
                    .scaleEffect(x: fill, anchor: .leading)
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(isHovered ? GlowTokens.Accent.glow : GlowTokens.Border.tile, lineWidth: isHovered ? 1.5 : 1)
            }
            .animation(GlowTokens.Motion.press, value: isHovered)
    }

    /// A press that stays put is a click on its box; once it moves, the level follows it.
    private func drag(_ geometry: LevelBoxGeometry, from level: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                guard isEnabled else { return }
                if !isDragging, abs(drag.translation.width) < Self.dragSlop { return }
                isDragging = true
                hovered = geometry.box(at: drag.location.x)
                set(scale.value(atFraction: geometry.fraction(at: drag.location.x)), from: level)
            }
            .onEnded { drag in
                defer { isDragging = false }
                guard isEnabled, !isDragging else { return }
                set(scale.valueForClick(onBox: geometry.box(at: drag.startLocation.x) + 1, current: level), from: level)
            }
    }

    private func move(by boxes: Int, from level: Double) {
        set(scale.stepped(level, by: boxes), from: level)
    }

    private func set(_ next: Double, from level: Double) {
        if next != level || value == nil { propose(next) }
    }
}
