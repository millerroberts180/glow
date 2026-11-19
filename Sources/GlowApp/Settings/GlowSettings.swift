import Foundation
import Observation

/// Everything Glow remembers between launches. Preferences only: display readings,
/// identities from discovery and diagnostics are never stored here.
struct GlowSettings: Codable, Equatable {
    /// Glow shows the real displays unless someone picks the demo in Settings › General.
    var useDemoDisplays = false
    /// Set once someone has turned demo displays on or off themselves. Builds before real
    /// hardware saved `useDemoDisplays: true` as a default; without this, that isn't a choice.
    var choseDemoDisplays = false
    var showOverlayOnChange = true
    var fineAdjustment = true
    var controlTarget: ControlTarget = .all
    /// The display the brightness keys change when the target is Focused.
    var focusedDisplay: PersistentDisplayIdentity?
    var matchMethod: MatchMethod = .quick
    /// Saved Brightness Match curves, versioned on their own.
    var brightnessMatch = BrightnessMatchSettings()
    /// Settings opens where it was left.
    var lastPane: GlowSettingsPane = .displays
    /// Set once the first-run setup has been seen, so it opens by itself only once.
    var hasCompletedSetup = false
    /// The person's own scenes, versioned on their own. Demo examples are never saved here.
    var sceneLibrary = SceneLibrary()
    /// Opt-in: after a wake, put back what Glow last set if a display forgot it.
    var reapplyAfterWake = false
    /// How far one press of a brightness key moves.
    var keyStep: KeyStep = .likeMacOS
    /// Sliders or boxes, in the menu bar and on the overlay.
    var levelStyle: LevelStyle = .slider
    /// Settings › Reading, versioned on its own.
    var reading = ReadingSettings()
    /// What Glow last set on each real display, for At launch › Put back what Glow last set.
    /// Versioned on its own; input and power are never kept.
    var lastSet = LastSetValues()
    /// Settings hidden on real displays by the person, versioned on their own.
    var corrections = DisplayCorrections()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case useDemoDisplays, choseDemoDisplays, showOverlayOnChange, fineAdjustment, controlTarget, focusedDisplay, matchMethod, lastPane, hasCompletedSetup
        case brightnessMatch
        case sceneLibrary = "scenes", reapplyAfterWake
        case keyStep, levelStyle, reading, lastSet, corrections
    }

    /// Each field on its own, so a missing key or one from a newer Glow never resets the rest.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        choseDemoDisplays = try c.decodeIfPresent(Bool.self, forKey: .choseDemoDisplays) ?? choseDemoDisplays
        // An old install's saved `true` was the default of its day, so it moves to real displays once.
        if choseDemoDisplays {
            useDemoDisplays = try c.decodeIfPresent(Bool.self, forKey: .useDemoDisplays) ?? useDemoDisplays
        }
        showOverlayOnChange = try c.decodeIfPresent(Bool.self, forKey: .showOverlayOnChange) ?? showOverlayOnChange
        fineAdjustment = try c.decodeIfPresent(Bool.self, forKey: .fineAdjustment) ?? fineAdjustment
        hasCompletedSetup = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedSetup) ?? hasCompletedSetup
        focusedDisplay = (try? c.decodeIfPresent(PersistentDisplayIdentity.self, forKey: .focusedDisplay)) ?? focusedDisplay
        // Enum values Glow doesn't know (written by a newer version) fall back instead of failing.
        controlTarget = (try? c.decodeIfPresent(ControlTarget.self, forKey: .controlTarget)) ?? controlTarget
        matchMethod = (try? c.decodeIfPresent(MatchMethod.self, forKey: .matchMethod)) ?? matchMethod
        lastPane = (try? c.decodeIfPresent(GlowSettingsPane.self, forKey: .lastPane)) ?? lastPane
        brightnessMatch = (try? c.decodeIfPresent(BrightnessMatchSettings.self, forKey: .brightnessMatch)) ?? brightnessMatch
        sceneLibrary = (try? c.decodeIfPresent(SceneLibrary.self, forKey: .sceneLibrary)) ?? sceneLibrary
        reapplyAfterWake = (try? c.decodeIfPresent(Bool.self, forKey: .reapplyAfterWake)) ?? reapplyAfterWake
        keyStep = (try? c.decodeIfPresent(KeyStep.self, forKey: .keyStep)) ?? keyStep
        levelStyle = (try? c.decodeIfPresent(LevelStyle.self, forKey: .levelStyle)) ?? levelStyle
        reading = (try? c.decodeIfPresent(ReadingSettings.self, forKey: .reading)) ?? reading
        lastSet = (try? c.decodeIfPresent(LastSetValues.self, forKey: .lastSet)) ?? lastSet
        corrections = (try? c.decodeIfPresent(DisplayCorrections.self, forKey: .corrections)) ?? corrections
    }
}

/// How Brightness Match compares displays.
enum MatchMethod: String, CaseIterable, Identifiable, Codable, Sendable {
    case quick, guided
    var id: Self { self }

    var title: String {
        switch self {
        case .quick: "Quick Match"
        case .guided: "Guided Match"
        }
    }

    var detail: String {
        switch self {
        case .quick: "One comparison, at the reference’s brightness now. About 20 seconds, and good enough for most desks."
        case .guided: "Five comparisons, from dim to full, build a curve. Best for a desk you use every day."
        }
    }
}

/// How brightness and volume are drawn: a slider, or a row of boxes like macOS’s own
/// brightness overlay.
enum LevelStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case slider, boxes
    var id: Self { self }
}

/// Holds the settings and saves them as JSON under a versioned key, a moment after the
/// last change.
@MainActor @Observable
final class GlowSettingsStore {
    nonisolated static let key = "settings.v1"

    var value: GlowSettings {
        didSet {
            guard value != oldValue else { return }
            scheduleSave()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let stored = try? JSONDecoder().decode(GlowSettings.self, from: data) {
            value = stored
        } else {
            value = GlowSettings()
        }
    }

    /// A dragged slider or a quick run of clicks changes settings many times a second;
    /// write once they settle.
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes any pending change now. Glow calls it as it quits.
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
