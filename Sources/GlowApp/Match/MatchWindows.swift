import AppKit
import SwiftUI

/// The grey patches on real screens: a borderless panel filling each display being
/// matched, above other windows and below the calibration window. Software dimming
/// darkens the screen's gamma, so it dims the patch like everything else.
@MainActor
final class ScreenPatches: MatchPatchPresenting {
    private var panels: [NSPanel] = []

    var showsOnScreens: Bool { true }

    func show(_ patches: [MatchPatch]) {
        hide()
        for patch in patches {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == patch.screen }) else { continue }
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.backgroundColor = NSColor(MatchPatchView.grey)
            panel.isOpaque = true
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: MatchPatchView(patch: patch))
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    func hide() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
    }
}

extension NSScreen {
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// The comparison patch: one flat neutral grey, the same on every display, with a small
/// caption low down so it doesn't sway the comparison.
struct MatchPatchView: View {
    /// Half the light of white in sRGB: bright enough to judge at low levels, and not so
    /// bright that a dim display looks the same as a lit one.
    static let grey = Color(.sRGB, white: 0.735)
    let patch: MatchPatch

    var body: some View {
        ZStack(alignment: .bottom) {
            Self.grey
            Text("\(patch.name) · \(patch.isReference ? "Reference" : "Match this to the reference")")
                .font(GlowTokens.Typography.caption)
                .foregroundStyle(Color(.sRGB, white: 0.5))
                .padding(.bottom, GlowTokens.Space.s10)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .light)
    }
}

/// The calibration window: small, above the patches, with ←/→ to adjust and ↑/↓ to
/// choose the display. Closing it is Cancel.
final class MatchWindowController: NSWindowController, NSWindowDelegate {
    static let size = CGSize(width: 480, height: 580)
    let session: MatchSession
    var onClose: (() -> Void)?
    private var monitor: Any?

    init(session: MatchSession) {
        self.session = session
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Match Displays"
        window.titlebarAppearsTransparent = true
        // Each step names itself in the window.
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentViewController = NSHostingController(rootView: MatchCalibrationView(session: session))
        window.setContentSize(Self.size)
        window.center()
        super.init(window: window)
        window.delegate = self
        session.onFinish = { [weak self] in self?.close() }
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        startKeys()
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

    /// Arrow keys while comparing, when this window has the keyboard.
    private func handle(_ event: NSEvent) -> Bool {
        guard event.window === window else { return false }
        return session.handleArrowKey(event.keyCode, shift: event.modifierFlags.contains(.shift))
    }

    func windowWillClose(_ notification: Notification) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        // Closed without Save or Cancel: put everything back all the same.
        if session.step != .finished {
            let session = session
            Task { await session.cancel() }
        }
        onClose?()
    }
}

/// Opens the calibration window from Settings › Brightness Match. One at a time.
@MainActor
final class MatchWindowPresenter {
    static let shared = MatchWindowPresenter()
    private var controller: MatchWindowController?

    func show(store: GlowStore) {
        if let controller {
            controller.present()
            return
        }
        // Demo displays aren't real screens, so the window draws their patches instead.
        let patches: any MatchPatchPresenting = store.isDemoData ? WindowOnlyPatches() : ScreenPatches()
        let controller = MatchWindowController(session: MatchSession(store: store, patches: patches))
        controller.onClose = { [weak self] in self?.controller = nil }
        self.controller = controller
        controller.present()
    }
}
