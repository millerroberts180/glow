import SwiftUI

/// Settings' panes. The raw values are saved (Settings reopens where it was left), so
/// rename a title freely but keep its case's raw value.
enum GlowSettingsPane: String, CaseIterable, Identifiable, Codable, Sendable {
    case general, displays, match, scenes, controls, connection, about
    case reading

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .displays: "Displays"
        case .match: "Brightness Match"
        case .scenes: "Scenes"
        case .controls: "Controls"
        case .connection: "Connection"
        case .about: "Glow"
        case .reading: "Reading"
        }
    }

    /// The tile's symbol. Glow's own tile draws the mark instead; this stands in elsewhere.
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .displays: "display.2"
        case .match: "circle.lefthalf.filled"
        case .scenes: "sparkles"
        case .controls: "keyboard.fill"
        case .connection: "cable.connector"
        case .about: "info.circle.fill"
        case .reading: "arrow.triangle.2.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .general: GlowTokens.PaneTint.general
        case .displays: GlowTokens.PaneTint.displays
        case .match: GlowTokens.PaneTint.match
        case .scenes: GlowTokens.PaneTint.scenes
        case .controls: GlowTokens.PaneTint.controls
        case .connection: GlowTokens.PaneTint.connection
        case .about: GlowTokens.PaneTint.about
        case .reading: GlowTokens.PaneTint.reading
        }
    }
}
