import AppKit
@testable import GlowApp

/// The right-click menu tests' AppKit side, kept apart for the same reason as
/// `SettingsFixture`: with only the Command Line Tools, a file can't import both
/// Foundation and Testing.
enum StatusMenuFixture {
    struct Item: Equatable {
        var title: String
        /// "⌘," for Command-comma; empty without a shortcut.
        var shortcut = ""
        var isEnabled = true
        /// Whether choosing it reaches the menu's own action.
        var acts = true
    }

    /// The menu's items as the menu shows them, a separator as "—".
    @MainActor static func items(isDiscovering: Bool) -> [Item] {
        var items: [Item] = []
        SettingsFixture.withSuite { defaults in
            let store = GlowStore(settings: GlowSettingsStore(defaults: defaults), demoDisplays: true)
            let statusMenu = StatusItemMenu(store: store, openSettings: { _ in })
            items = statusMenu.menu(isDiscovering: isDiscovering).items.map { item in
                guard !item.isSeparatorItem else { return Item(title: "—", acts: false) }
                let command = item.keyEquivalentModifierMask == .command ? "⌘" : ""
                return Item(title: item.title,
                            shortcut: item.keyEquivalent.isEmpty ? "" : command + item.keyEquivalent.uppercased(),
                            isEnabled: item.isEnabled,
                            acts: item.target === statusMenu && item.action != nil)
            }
        }
        return items
    }

    /// Which clicks on the mark open the menu, by name.
    static var clicksThatOpenMenu: [String] {
        let clicks: [(String, NSEvent.EventType, NSEvent.ModifierFlags)] = [
            ("right", .rightMouseDown, []),
            ("control-left", .leftMouseDown, .control),
            ("left", .leftMouseDown, []),
            ("command-left", .leftMouseDown, .command),
            ("option-left", .leftMouseDown, .option),
            ("right-up", .rightMouseUp, []),
            ("left-up", .leftMouseUp, .control)
        ]
        return clicks.filter { StatusItemMenu.opensMenu($0.1, modifiers: $0.2) }.map(\.0)
    }
}
