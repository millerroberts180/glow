import Foundation
@testable import GlowApp

/// Foundation helpers for the setup tests, kept apart for the same reason as
/// `SettingsFixture`: with only the Command Line Tools, a file can't import both
/// Foundation and Testing.
enum SetupFixture {
    /// A store on a defaults suite of its own, and a way to read back what it saved. It
    /// shows demo displays and never looks for any, so it can't reach real hardware.
    @MainActor static func withStore(_ body: (GlowStore, _ saved: () -> GlowSettings) throws -> Void) rethrows {
        try SettingsFixture.withSuite { defaults in
            try body(GlowStore(settings: GlowSettingsStore(defaults: defaults), demoDisplays: true), { GlowSettingsStore(defaults: defaults).value })
        }
    }

    /// A store reading displays from `adapter` only, on a defaults suite of its own, and a
    /// way to read back what it saved.
    @MainActor static func withStore(adapter: any DisplayAdapter, safeMode: Bool = false,
                                     _ body: @MainActor (GlowStore, _ saved: () -> GlowSettings) async throws -> Void) async rethrows {
        let name = "app.glow.tests.setup.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = GlowStore(settings: GlowSettingsStore(defaults: defaults), demoDisplays: false, safeMode: safeMode, adapter: adapter)
        try await body(store, { GlowSettingsStore(defaults: defaults).value })
    }

    /// Runs the main run loop for a while, so timers on it fire.
    @MainActor static func spin(seconds: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }
}
