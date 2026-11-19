import Foundation

/// Brightness Match's maths. Every level here is a fraction of one display's own brightness
/// range, 0 its lowest and 1 its highest, so a curve maps the reference's range onto the
/// matched display's and can't leave it: software dimming's range starts at 10 %, a
/// monitor's may end at 255, and both still run 0 to 1 here.
enum MatchCurve {
    /// Guided Match's comparison points, as fractions of the reference's range.
    static let guidedLevels: [Double] = [0.2, 0.4, 0.6, 0.8, 1.0]
    /// How many points a guided curve takes.
    static let guidedPoints = 3...5

    /// Quick Match's curve from its one comparison: at `reference`, the display looked as
    /// bright at `display`. Nil when the reference is at its lowest, where there's nothing
    /// to scale from.
    ///
    /// A ratio, not an offset. A backlight's light rises roughly in proportion to its level,
    /// so two displays that look alike at one level keep the same ratio of light at the
    /// others, and both reach their darkest together. An offset would move every level by
    /// the same amount: one display would sit at its floor while the other was still lit,
    /// or never reach its top. One point can't show the real shape; Guided Match measures it.
    static func quick(reference: Double, display: Double) -> BrightnessCurve? {
        let reference = clamp(reference), display = clamp(display)
        guard reference > 0 else { return nil }
        let ratio = display / reference
        var points = [CalibrationPoint(reference: reference, display: display)]
        if ratio > 1 {
            // Brighter than the reference's scale allows: full brightness from here up.
            points.append(.init(reference: reference / display, display: 1))
            points.append(.init(reference: 1, display: 1))
        } else {
            points.append(.init(reference: 1, display: ratio))
        }
        return BrightnessCurve(points: anchored(points))
    }

    /// Guided Match's curve: straight lines through each comparison point. Nil unless there
    /// are 3 to 5 of them.
    static func guided(_ points: [CalibrationPoint]) -> BrightnessCurve? {
        guard guidedPoints.contains(points.count) else { return nil }
        return BrightnessCurve(points: anchored(points))
    }

    /// Adds both displays' lowest level as the curve's start, for the same reason Quick
    /// Match is a ratio: below the first comparison, both dim together to their darkest.
    /// Points at the same reference level keep only the brightest.
    private static func anchored(_ points: [CalibrationPoint]) -> [CalibrationPoint] {
        var byReference: [Double: Double] = [0: 0]
        for point in points {
            let reference = clamp(point.reference)
            byReference[reference] = max(byReference[reference] ?? 0, clamp(point.display))
        }
        return byReference.sorted { $0.key < $1.key }.map { CalibrationPoint(reference: $0.key, display: $0.value) }
    }

    static func clamp(_ level: Double) -> Double {
        guard level.isFinite else { return 0 }
        return min(1, max(0, level))
    }
}

extension BrightnessCurve {
    /// The curve run backwards: the lowest reference level at which the matched display
    /// reaches `display`. Used to step a matched group whose reference isn't connected.
    func referenceLevel(for display: Double) -> Double {
        let target = MatchCurve.clamp(display)
        guard let first = points.first, let last = points.last else { return target }
        if target <= first.display { return first.reference }
        // The first segment that reaches the target starts below it, so it isn't flat.
        for (low, high) in zip(points, points.dropFirst()) where target <= high.display {
            return low.reference + (target - low.display) / (high.display - low.display) * (high.reference - low.reference)
        }
        return last.reference
    }
}

extension CapabilityDescriptor {
    /// The setting's range, for a range setting.
    var matchRange: (minimum: Double, maximum: Double, step: Double)? {
        guard case let .range(minimum, maximum, step) = kind, maximum > minimum else { return nil }
        return (minimum, maximum, step)
    }

    /// Where `value` sits in this setting's range, from 0 to 1.
    func matchLevel(of value: Double) -> Double? {
        guard let range = matchRange else { return nil }
        return MatchCurve.clamp((value - range.minimum) / (range.maximum - range.minimum))
    }

    /// The value at `level` of this setting's range, on its own steps.
    func matchValue(at level: Double) -> Double? {
        guard let range = matchRange else { return nil }
        let value = range.minimum + MatchCurve.clamp(level) * (range.maximum - range.minimum)
        let snapped = range.step > 0 ? range.minimum + ((value - range.minimum) / range.step).rounded() * range.step : value
        return min(range.maximum, max(range.minimum, snapped))
    }

    /// The value now, pending writes included, as a number.
    var matchNumber: Double? {
        if case let .number(value) = currentValue { value } else { nil }
    }
}

extension DisplaySnapshot {
    var brightnessSetting: CapabilityDescriptor? { capabilities.first { $0.id == .brightness } }

    /// How Glow changes this display's brightness now; a match remembers it.
    var brightnessRoute: ControlRoute { brightnessSetting?.route ?? .unavailable }

    /// Brightness Glow can set and has a reading for: what matching needs.
    var matchableBrightness: CapabilityDescriptor? {
        guard let brightness = brightnessSetting, brightness.isSafelyEditable, brightness.matchRange != nil, brightness.matchNumber != nil else { return nil }
        return brightness
    }
}
