import Foundation
@testable import GlowApp

/// Foundation helpers for the reading tests, kept apart from them for the same reason as
/// `SettingsFixture`.
enum ReadingFixture {
    /// A fixed moment, plus `seconds`, so schedules are checked against a clock tests own.
    static func date(_ seconds: Double = 0) -> Date {
        Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds)
    }

    static func seconds(_ date: Date?) -> Double? {
        date.map { $0.timeIntervalSinceReferenceDate - 800_000_000 }
    }

    @MainActor static func withSuite(_ body: (UserDefaults) async throws -> Void) async rethrows {
        let name = "app.glow.tests.reading.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try await body(defaults)
    }

    /// The settings as saved, read back the way the next launch would read them.
    @MainActor static func saved(_ settings: GlowSettingsStore) throws -> GlowSettings {
        settings.flush()
        return try JSONDecoder().decode(GlowSettings.self, from: JSONEncoder().encode(settings.value))
    }

    static func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    static func json<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    /// A store on `adapter` whose reading clock and "is Glow open" the test owns, started,
    /// with its background loop stopped so only the test's own ticks read.
    @MainActor static func store(
        _ defaults: UserDefaults, adapter: MockDisplayAdapter, clock: ReadingTestClock,
        freshness: ReadingFreshness = .whileOpen, safeMode: Bool = false,
        prepare: (GlowSettingsStore) -> Void = { _ in }
    ) async -> GlowStore {
        let settings = GlowSettingsStore(defaults: defaults)
        settings.value.reading.freshness = freshness
        prepare(settings)
        let store = GlowStore(settings: settings, demoDisplays: false, safeMode: safeMode, adapter: adapter)
        store.reading.now = { clock.now }
        store.reading.isGlowOpen = { clock.isOpen }
        await store.start()
        store.reading.loop?.cancel()
        return store
    }

    /// The demo displays as real ones, the way the hardware adapter would report them.
    @MainActor static func realAdapter() -> MockDisplayAdapter {
        let adapter = MockDisplayAdapter { generation in
            DemoData.displays(generation: generation).map { display in
                var display = display
                display.isDemo = false
                return display
            }
        }
        adapter.readDelay = .zero
        return adapter
    }
}

/// The clock and the "is Glow open" answer a reading test controls.
@MainActor final class ReadingTestClock {
    var seconds: Double = 0
    var isOpen = true
    var now: Date { ReadingFixture.date(seconds) }
}
