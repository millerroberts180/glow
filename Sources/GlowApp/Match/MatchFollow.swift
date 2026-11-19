import Foundation

/// How matched displays move with their reference: along their curves, from wherever the
/// reference goes, instead of stepping from their own levels.
enum MatchFollow {
    /// The new brightness of each target for one key press. A matched group's reference
    /// takes its step and its matched displays follow their curves to the reference's new
    /// level. When the reference isn't connected, the group steps on the reference's scale,
    /// worked back from its first matched display. Everything else steps on its own.
    ///
    /// A matched display never moves against the key: if its own slider took it past its
    /// curve, it waits there until the curve catches up.
    static func keyPlan(
        press: BrightnessKeyPress, targets: [PersistentDisplayIdentity],
        displays: [DisplaySnapshot], match: BrightnessMatchSettings
    ) -> [(PersistentDisplayIdentity, Double)] {
        let targetSet = Set(targets)
        let groups = Dictionary(grouping: match.active(among: displays).filter { targetSet.contains($0.pair.display) }, by: \.pair.reference)
        var plan: [PersistentDisplayIdentity: Double] = [:]
        var handled = Set<PersistentDisplayIdentity>()

        for (referenceID, calibrations) in groups {
            let level: Double
            if let reference = displays.first(where: { $0.id == referenceID }) {
                guard targetSet.contains(referenceID), let setting = reference.matchableBrightness,
                      let range = setting.matchRange, let current = setting.matchNumber else { continue }
                let next = BrightnessKeyRouting.next(from: current, range: range.minimum...range.maximum, press: press, tolerance: range.step / 2)
                plan[referenceID] = next
                handled.insert(referenceID)
                level = setting.matchLevel(of: next) ?? 0
            } else {
                let ordered = calibrations.sorted { $0.pair.display.id < $1.pair.display.id }
                guard let lead = ordered.first, let setting = displays.first(where: { $0.id == lead.pair.display })?.matchableBrightness,
                      let current = setting.matchNumber, let displayLevel = setting.matchLevel(of: current) else { continue }
                // Half a percent of slack, as a slider value between steps gets.
                level = BrightnessKeyRouting.next(from: lead.curve.referenceLevel(for: displayLevel), range: 0...1, press: press, tolerance: 0.005)
            }
            for calibration in calibrations {
                guard let setting = displays.first(where: { $0.id == calibration.pair.display })?.matchableBrightness,
                      let current = setting.matchNumber, let target = setting.matchValue(at: calibration.curve.value(for: level)) else { continue }
                plan[calibration.pair.display] = press.direction == .up ? max(current, target) : min(current, target)
                handled.insert(calibration.pair.display)
            }
        }

        for id in targets where !handled.contains(id) {
            guard let setting = displays.first(where: { $0.id == id })?.matchableBrightness,
                  let range = setting.matchRange, let current = setting.matchNumber else { continue }
            plan[id] = BrightnessKeyRouting.next(from: current, range: range.minimum...range.maximum, press: press, tolerance: range.step / 2)
        }
        // In the order the targets came, so writes go out in a steady order.
        return targets.compactMap { id in plan[id].map { (id, $0) } }
    }

    /// Where each display matched to `referenceID` goes when the reference is set to
    /// `value` directly, as its slider does with "Move matched displays together" on.
    static func followers(
        of referenceID: PersistentDisplayIdentity, at value: Double,
        displays: [DisplaySnapshot], match: BrightnessMatchSettings
    ) -> [(PersistentDisplayIdentity, Double)] {
        guard let level = displays.first(where: { $0.id == referenceID })?.brightnessSetting?.matchLevel(of: value) else { return [] }
        return match.active(among: displays)
            .filter { $0.pair.reference == referenceID }
            .compactMap { calibration in
                guard let setting = displays.first(where: { $0.id == calibration.pair.display })?.matchableBrightness,
                      let target = setting.matchValue(at: calibration.curve.value(for: level)) else { return nil }
                return (calibration.pair.display, target)
            }
    }
}

extension GlowStore {
    var brightnessMatch: BrightnessMatchSettings {
        get { settings.value.brightnessMatch }
        set {
            settings.value.brightnessMatch = newValue
            refreshMatchStatus()
        }
    }

    var moveMatchedTogether: Bool {
        get { brightnessMatch.moveTogether }
        set { brightnessMatch.moveTogether = newValue }
    }

    func matchState(of display: DisplaySnapshot) -> MatchState {
        brightnessMatch.state(of: display, among: displays)
    }

    /// Displays whose brightness Glow can set now, by any route.
    var matchCandidates: [DisplaySnapshot] {
        guard !(safeMode && !demoMode) else { return [] }
        return displays.filter { $0.matchableBrightness != nil }
    }

    /// Whether any connected display has a match, current or not, to forget.
    var hasMatchToForget: Bool {
        displays.contains { display in
            if case .notMatched = matchState(of: display) { false } else { true }
        }
    }

    /// Forgets the matches of every connected display. Brightness stays where it is.
    func forgetMatch() {
        brightnessMatch.forget(Set(displays.map(\.id)))
    }

    /// With "Move matched displays together" on, a change to a reference's brightness
    /// moves its matched displays along their curves. Each matched display's own slider
    /// still sets that display alone, since it isn't a reference.
    func followMatchedDisplays(from displayID: PersistentDisplayIdentity, capabilityID: CapabilityIdentifier, value: CapabilityValue) {
        guard moveMatchedTogether, capabilityID == .brightness, case let .number(level) = value else { return }
        for (id, target) in MatchFollow.followers(of: displayID, at: level, displays: displays, match: brightnessMatch) {
            update(displayID: id, capabilityID: .brightness, proposed: .number(target), follow: false)
        }
    }
}
