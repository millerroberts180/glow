import AppKit
import SwiftUI

/// The setup window, built the way `HostedWindow` builds Settings: content under a
/// transparent title bar, sized before it's centred, brought forward even when another
/// app is in use.
final class SetupWindowController: NSWindowController, NSWindowDelegate {
    let model: SetupModel
    var onClose: (() -> Void)?
    private var monitor: Any?

    init(store: GlowStore, login: SetupLogin, tutorialOnly: Bool, permission: KeyPermission = .live,
         patches: @escaping @MainActor (GlowStore) -> any MatchPatchPresenting = SetupModel.livePatches) {
        model = SetupModel(store: store, login: login, tutorialOnly: tutorialOnly, permission: permission, patches: patches)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: GlowTokens.Size.setupWindow),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = tutorialOnly ? "Glow Tutorial" : "Set Up Glow"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let hosting = NSHostingController(rootView: SetupView(model: model))
        window.contentViewController = hosting
        // Sized before centring, or it opens off-centre against the menu bar (see HostedWindow).
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        super.init(window: window)
        window.delegate = self
        model.onFinish = { [weak self] in self?.close() }
        model.onPatchesChange = { [weak self] in self?.patchesChanged(showing: $0) }
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // A menu-bar app's activation request can be declined while another app is in
        // use; the window still comes to the front.
        window?.orderFrontRegardless()
        startKeys()
    }

    /// While the grey patches are up, above them on every Space, as the calibration window
    /// is; back among other windows once they're down.
    private func patchesChanged(showing: Bool) {
        guard let window else { return }
        window.level = showing ? NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1) : .normal
        window.collectionBehavior = showing ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
        if showing { window.orderFrontRegardless() }
    }

    private func startKeys() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Local monitors run on the main thread, and the event stays on it.
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return handled ? nil : event
        }
    }

    /// The match's arrow keys while comparing, when this window has the keyboard.
    private func handle(_ event: NSEvent) -> Bool {
        guard event.window === window, model.step == .match, let match = model.match else { return false }
        return match.handleArrowKey(event.keyCode, shift: event.modifierFlags.contains(.shift))
    }

    func windowWillClose(_ notification: Notification) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        // Whatever step it closed on: puts back a match part way, stops the permission
        // check, and counts as seen.
        model.close()
        onClose?()
    }
}

/// Opens setup on first launch, and the tutorial from Settings › General. One window at a
/// time.
@MainActor
final class SetupPresenter {
    /// The app's presenter, so Settings › General can reach it without threading it
    /// through every pane. Set at launch; nil in snapshots and tests.
    static var current: SetupPresenter?

    private let store: GlowStore
    private let loginItem: LoginItem
    private var controller: SetupWindowController?

    init(store: GlowStore, loginItem: LoginItem) {
        self.store = store
        self.loginItem = loginItem
    }

    var isFirstRun: Bool { !store.settings.value.hasCompletedSetup }

    func show(tutorialOnly: Bool) {
        if let controller, controller.model.tutorialOnly == tutorialOnly {
            controller.present()
            return
        }
        controller?.close()
        // Someone may have changed Login Items in System Settings since the last look.
        loginItem.refresh()
        let controller = SetupWindowController(store: store, login: .live(loginItem), tutorialOnly: tutorialOnly)
        controller.onClose = { [weak self] in self?.controller = nil }
        self.controller = controller
        controller.present()
    }
}
