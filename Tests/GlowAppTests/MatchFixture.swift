import Foundation
@testable import GlowApp

/// Brightness Match tests' Foundation side, kept apart for the same reason as
/// `SettingsFixture`: with only the Command Line Tools, a file can't import both
/// Foundation and Testing.
enum MatchFixture {
    /// A store reading displays from `adapter` only, on a defaults suite of its own.
    @MainActor static func withStore(adapter: any DisplayAdapter, _ body: (GlowStore) async throws -> Void) async rethrows {
        let name = "app.glow.tests.match.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = GlowStore(settings: GlowSettingsStore(defaults: defaults), demoDisplays: false, adapter: adapter)
        try await body(store)
    }

    static func json(_ match: BrightnessMatchSettings) throws -> String {
        String(decoding: try JSONEncoder().encode(match), as: UTF8.self)
    }

    static func decode(_ json: String) throws -> BrightnessMatchSettings {
        try JSONDecoder().decode(BrightnessMatchSettings.self, from: Data(json.utf8))
    }

    static func roundTrip(_ match: BrightnessMatchSettings) throws -> BrightnessMatchSettings {
        try decode(json(match))
    }

    /// One calibration as saved, with its curve's points written in as given.
    static func calibrationJSON(_ calibration: MatchCalibration, points: [(Double, Double)]) throws -> String {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(calibration)) as! [String: Any]
        object["curve"] = ["points": points.map { ["reference": $0.0, "display": $0.1] }]
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}
