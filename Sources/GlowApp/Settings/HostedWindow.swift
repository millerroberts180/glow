import AppKit
import SwiftUI

/// A plain window hosting one SwiftUI view. Created on first use and kept while Glow runs,
/// so reopening is instant and the pane stays where it was.
final class HostedWindow<Content: View>: NSWindowController {
    /// `sidebar`: content runs under a transparent title bar, the way System Settings and
    /// other sidebar windows look.
    init(title: String, size: CGSize, sidebar: Bool = false, @ViewBuilder content: () -> Content) {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if sidebar { style.insert(.fullSizeContentView) }
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        if sidebar {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        }
        let hosting = NSHostingController(rootView: content())
        window.contentViewController = hosting
        // The window takes its size from the view only once the view loads. Size it now,
        // or center() centres an empty window and the real one opens off to the right,
        // up against the menu bar.
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // A menu-bar app's activation request can be declined while another app is in
        // use; the window still comes to the front.
        window?.orderFrontRegardless()
    }
}

/// Opens Glow Settings from the popover, ⌘, and "Show settings", turning it to a pane or
/// a display first when asked.
@MainActor
final class SettingsWindowPresenter {
    let loginItem = LoginItem()
    private let store: GlowStore
    private var controller: HostedWindow<GlowSettingsView>?

    init(store: GlowStore) {
        self.store = store
    }

    func show(_ pane: GlowSettingsPane? = nil, display: PersistentDisplayIdentity? = nil) {
        if let pane { store.selectedPane = pane }
        if let display { store.selectedDisplayID = display }
        // Someone may have changed Login Items in System Settings since the last look.
        loginItem.refresh()
        let controller = controller ?? HostedWindow(title: "Glow Settings", size: GlowTokens.Size.settingsWindow, sidebar: true) {
            GlowSettingsView(store: store, loginItem: loginItem)
        }
        self.controller = controller
        // Settings first, then close Glow Desk. Closed the other way round, with no other Glow
        // window open, Glow Desk hands the Mac back to the app in use before it opened, and
        // Settings comes up in front but not in use.
        controller.present()
        Self.closeGlowDesk()
    }

    /// Glow Desk stays open when one of its buttons opens Settings, and would cover it.
    /// MenuBarExtra has no way to close it, so click the mark, as closing Glow Desk by hand
    /// does. Closing its window (SwiftUI's MenuBarExtraWindow) directly would leave the mark
    /// thinking it's still open, and the next click on it would do nothing.
    private static func closeGlowDesk() {
        let windows = NSApp.windows
        guard windows.contains(where: { $0.isVisible && String(describing: type(of: $0)).contains("MenuBarExtraWindow") }),
              let mark = windows.lazy.compactMap({ StatusItemMenu.statusButton(in: $0.contentView) }).first else { return }
        mark.performClick(nil)
    }
}
