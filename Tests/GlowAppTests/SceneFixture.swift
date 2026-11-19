import Foundation
@testable import GlowApp

/// Scene tests' Foundation side: an async defaults suite, so a store can apply scenes and
/// save its library without touching the test runner's own defaults.
enum SceneFixture {
    @MainActor static func withSuite(_ body: (UserDefaults) async throws -> Void) async rethrows {
        let name = "app.glow.tests.scenes.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try await body(defaults)
    }

    /// The library as saved, read back the way the next launch would read it.
    @MainActor static func savedLibrary(_ settings: GlowSettingsStore) throws -> SceneLibrary {
        settings.flush()
        return try JSONDecoder().decode(GlowSettings.self, from: JSONEncoder().encode(settings.value)).sceneLibrary
    }
}
