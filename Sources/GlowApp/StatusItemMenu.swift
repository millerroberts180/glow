import AppKit

/// The menu Glow's menu-bar mark shows on a right-click or a Control-click: Refresh Displays,
/// Settings… and Quit Glow. A left click still opens Glow Desk. MenuBarExtra has no right-click of its own, so a local event
/// monitor takes the click on Glow's status-bar window before MenuBarExtra sees it, and pops
/// this menu up under the mark instead.
@MainActor
final class StatusItemMenu: NSObject {
    private let store: GlowStore
    private let openSettings: (GlowSettingsPane?) -> Void
    private var monitor: Any?

    init(store: GlowStore, openSettings: @escaping (GlowSettingsPane?) -> Void) {
        self.store = store
        self.openSettings = openSettings
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            // Local monitors run on the main thread, as each event is dispatched.
            let shown = MainActor.assumeIsolated { self?.popUp(for: event) ?? false }
            return shown ? nil : event
        }
    }

    /// A right-click, or the left button with Control held, as anywhere on the Mac.
    nonisolated static func opensMenu(_ type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> Bool {
        type == .rightMouseDown || (type == .leftMouseDown && modifiers.contains(.control))
    }

    /// The menu as it is now: Refresh waits while displays are being read.
    func menu(isDiscovering: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let refresh = NSMenuItem(title: "Refresh Displays", action: #selector(refreshDisplays), keyEquivalent: "")
        refresh.isEnabled = !isDiscovering
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        let quit = NSMenuItem(title: "Quit Glow", action: #selector(quitGlow), keyEquivalent: "q")
        for item in [refresh, settings, quit] { item.target = self }
        menu.items = [refresh, settings, .separator(), quit]
        return menu
    }

    /// Shows the menu when this is a menu click on Glow's mark, held down the way a menu-bar
    /// menu holds its item while it's open.
    private func popUp(for event: NSEvent) -> Bool {
        guard Self.opensMenu(event.type, modifiers: event.modifierFlags),
              let window = event.window, let button = Self.statusButton(in: window.contentView) else { return false }
        button.highlight(true)
        defer { button.highlight(false) }
        // In screen points: its top-left corner at the mark's bottom-left, under the menu bar.
        _ = menu(isDiscovering: store.isDiscovering).popUp(positioning: nil, at: NSPoint(x: window.frame.minX, y: window.frame.minY), in: nil)
        return true
    }

    /// The status-bar button in a window. Only a status item's window has one, and the mark
    /// is Glow's only status item.
    static func statusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        return view.subviews.lazy.compactMap { statusButton(in: $0) }.first
    }

    @objc private func refreshDisplays() { Task { await store.refresh() } }
    @objc private func showSettings() { openSettings(nil) }
    @objc private func quitGlow() { NSApp.terminate(nil) }
}
