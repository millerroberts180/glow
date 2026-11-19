import Foundation
@testable import GlowApp

/// Foundation helpers for the settings tests. They live apart from the tests because, with
/// only the Command Line Tools, a file importing both Foundation and Testing needs an
/// overlay the tools don't ship.
enum SettingsFixture {
    static func decode(_ json: String) throws -> GlowSettings {
        try JSONDecoder().decode(GlowSettings.self, from: Data(json.utf8))
    }

    static func roundTrip(_ settings: GlowSettings) throws -> GlowSettings {
        try JSONDecoder().decode(GlowSettings.self, from: JSONEncoder().encode(settings))
    }

    /// A defaults suite of its own, removed when the test is done.
    @MainActor static func withSuite(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "app.glow.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    /// Which of the trial's leftovers and Glow's own settings are still there after the cleanup.
    @MainActor static func keysLeftAfterTrialCleanup() -> [String] {
        var left: [String] = []
        withSuite { defaults in
            let keys = LeftoverTrialData.defaultsKeys + [GlowSettingsStore.key]
            for key in keys { defaults.set(Data([1]), forKey: key) }
            LeftoverTrialData.removeDefaults(from: defaults)
            left = keys.filter { defaults.object(forKey: $0) != nil }
        }
        return left
    }

    static func hasSavedSettings(_ defaults: UserDefaults) -> Bool {
        defaults.data(forKey: GlowSettingsStore.key) != nil
    }

    static func saveUnreadableSettings(_ defaults: UserDefaults) {
        defaults.set(Data("not settings".utf8), forKey: GlowSettingsStore.key)
    }
}
