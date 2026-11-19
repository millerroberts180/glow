import CoreGraphics
import Foundation

/// One press of a brightness key, as the event tap reads it.
struct BrightnessKeyPress: Equatable, Sendable {
    enum Direction: Sendable { case up, down }
    var direction: Direction
    /// Option and Shift were held: a quarter of the step, as macOS does.
    var quarterStep: Bool
    /// The step size chosen in Settings › Controls.
    var step: KeyStep = .likeMacOS
}

/// Where a brightness key goes. Glow either leaves the press to macOS untouched or takes it
/// and changes every target itself, the built-in screen included (through DisplayServices).
/// It never does both, so no display ever moves twice for one press.
enum KeyRoute: Equatable, Sendable {
    case macOS
    case glow([PersistentDisplayIdentity])
}

enum BrightnessKeyRouting {
    /// macOS's brightness keys move in sixteenths; with Option and Shift, in quarters of that.
    /// Glow's step size can be set in percent instead (`KeyStep`).
    static let steps = 16.0
    static let quarterSteps = 64.0

    /// Mac only goes to macOS, as do the times Glow can't act: demo displays, safe mode and
    /// before discovery finds anything. Every other target is Glow's, even when the target
    /// leaves the built-in out, so that macOS doesn't change it behind Glow's back.
    static func route(
        target: ControlTarget,
        displays: [DisplaySnapshot],
        focused: PersistentDisplayIdentity?,
        pointerDisplay: CGDirectDisplayID?,
        demoMode: Bool,
        safeMode: Bool
    ) -> KeyRoute {
        guard !demoMode, !safeMode, !displays.isEmpty else { return .macOS }
        switch target {
        case .macOnly:
            return .macOS
        case .all:
            return .glow(displays.map(\.id))
        case .underCursor:
            return .glow(displays.filter { $0.connection.displayID == pointerDisplay }.map(\.id))
        case .focused:
            let chosen = focused.flatMap { id in displays.first { $0.id == id } } ?? displays.first { !$0.isBuiltIn }
            return .glow([chosen].compactMap { $0?.id })
        }
    }

    /// The next value on the step grid in the key's direction. A value between steps (from
    /// a slider) moves to the next grid line rather than a full step past it; `tolerance`
    /// keeps rounding to the setting's own step from holding a value in place.
    static func next(from value: Double, range: ClosedRange<Double>, press: BrightnessKeyPress, tolerance: Double = 0.5) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0, value.isFinite else { return min(range.upperBound, max(range.lowerBound, value)) }
        let step = span * (press.quarterStep ? press.step.fineFraction : press.step.fraction)
        let offset = value - range.lowerBound
        let index = switch press.direction {
        case .up: ((offset + tolerance) / step).rounded(.down) + 1
        case .down: ((offset - tolerance) / step).rounded(.up) - 1
        }
        return min(range.upperBound, max(range.lowerBound, range.lowerBound + index * step))
    }
}

extension GlowStore {
    /// A brightness key from the event tap. Returns true when Glow took the press, so the
    /// tap swallows it; false hands it to macOS. Each target steps from its latest value,
    /// pending writes included, by the step chosen in Settings › Controls.
    func handleBrightnessKey(_ press: BrightnessKeyPress, pointerDisplay: CGDirectDisplayID?) -> Bool {
        let press = BrightnessKeyPress(direction: press.direction, quarterStep: press.quarterStep && fineAdjustment, step: keyStep)
        return stepBrightness(press, pointerDisplay: pointerDisplay) != .macOS
    }

    /// One tick of a held key: 1% on every target, matched displays along their curves.
    /// Returns why the ramp should stop, or nil to go on.
    func rampBrightness(_ direction: BrightnessKeyPress.Direction, pointerDisplay: CGDirectDisplayID?) -> KeyHoldStop? {
        switch stepBrightness(BrightnessKeyPress(direction: direction, quarterStep: false, step: .percent1), pointerDisplay: pointerDisplay) {
        case .macOS: .notGlows
        case .paused: .paused
        case .unmoved: .rangeEnd
        case .moved: nil
        }
    }

    private enum KeyStepOutcome { case macOS, paused, unmoved, moved }

    private func stepBrightness(_ press: BrightnessKeyPress, pointerDisplay: CGDirectDisplayID?) -> KeyStepOutcome {
        let route = BrightnessKeyRouting.route(
            target: controlTarget, displays: displays, focused: focusedDisplayID,
            pointerDisplay: pointerDisplay, demoMode: demoMode, safeMode: safeMode
        )
        guard case let .glow(targets) = route else { return .macOS }
        guard pauseReason == nil else { return .paused }
        // With every display as the target, matched displays follow their curves.
        let match = controlTarget == .all ? brightnessMatch : BrightnessMatchSettings()
        var moved = false
        for (id, next) in MatchFollow.keyPlan(press: press, targets: targets, displays: displays, match: match) {
            guard next != displays.first(where: { $0.id == id })?.brightnessSetting?.matchNumber else { continue }
            update(displayID: id, capabilityID: .brightness, proposed: .number(next), follow: false)
            moved = true
        }
        return moved ? .moved : .unmoved
    }
}
