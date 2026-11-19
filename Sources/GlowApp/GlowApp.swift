import AppKit
import SwiftUI

/// Checks for the debug snapshot flag before the app starts, so rendering never puts
/// Glow in the menu bar.
@main
enum GlowMain {
    @MainActor static func main() {
        #if DEBUG
        if let folder = UISnapshots.folder(in: CommandLine.arguments) {
            UISnapshots.render(to: folder)
            return
        }
        if let command = DisplayProbe.command(in: CommandLine.arguments) {
            exit(DisplayProbe.run(command))
        }
        if SceneSelfTest.requested(in: CommandLine.arguments) {
            Task { exit(await SceneSelfTest.run()) }
            RunLoop.main.run()
        }
        if HoldSelfTest.requested(in: CommandLine.arguments) {
            Task { exit(await HoldSelfTest.run()) }
            RunLoop.main.run()
        }
        #endif
        // Software dimming lives in the gamma table; put it back however Glow ends.
        SoftwareDimmer.installExitRestore()
        GlowApp.main()
    }
}

struct GlowApp: App {
    @NSApplicationDelegateAdaptor(GlowAppDelegate.self) private var delegate
    @ObservedObject private var mark = MenuBarMark.shared

    var body: some Scene {
        MenuBarExtra(isInserted: $mark.isInserted) {
            MenuBarView(store: delegate.store) { pane, display in
                delegate.settingsWindow.show(pane, display: display)
            }
        } label: {
            // Glow's mark as a template image, so the menu bar tints it.
            Image(nsImage: GlowLogo.menuBarImage())
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { delegate.settingsWindow.show() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// Whether Glow's mark is in the menu bar: out of it while Line Apps has the family collapsed into
/// its line.
@MainActor
final class MenuBarMark: ObservableObject {
    static let shared = MenuBarMark()
    /// The name SwiftUI gives Glow's one status item, under which the menu bar keeps its place.
    static let autosaveName = "Item-0"
    /// Announced only when it changes. Taking the mark out, SwiftUI writes `false` back through the
    /// binding; announcing each write would make the scene anew, which writes again, and so on,
    /// keeping Glow's main thread busy for as long as the mark is out.
    var isInserted = true {
        willSet { if newValue != isInserted { objectWillChange.send() } }
    }

    private init() {
        // A quit while collapsed can leave the mark marked hidden, and SwiftUI would open it so.
        LineAppsFold.forgetHidden(name: Self.autosaveName)
    }
}

/// Owns the store, the Settings window and setup for the app's lifetime.
@MainActor
final class GlowAppDelegate: NSObject, NSApplicationDelegate {
    /// Holding Shift as Glow opens starts safe mode: it reads displays and changes nothing.
    let store = GlowAppDelegate.makeStore(safeMode: NSEvent.modifierFlags.contains(.shift))
    private(set) lazy var settingsWindow = SettingsWindowPresenter(store: store)
    private(set) lazy var setup = SetupPresenter(store: store, loginItem: settingsWindow.loginItem)
    /// Right-click on the menu-bar mark: Refresh Displays, Settings… and Quit Glow.
    private lazy var statusMenu = StatusItemMenu(store: store) { [weak self] pane in
        if let pane { self?.settingsWindow.show(pane) } else { self?.settingsWindow.show() }
    }
    /// A press steps once; a held key ramps 1% at a time until it comes up.
    private lazy var keyHold = BrightnessKeyHold(
        press: { [store] press in store.handleBrightnessKey(press, pointerDisplay: BrightnessKeyTap.pointerDisplay()) },
        tick: { [store] direction in store.rampBrightness(direction, pointerDisplay: BrightnessKeyTap.pointerDisplay()) }
    )
    private lazy var keyTap = BrightnessKeyTap { [keyHold] event in keyHold.handle(event) }
    /// Takes the mark out while Line Apps has the family collapsed into its line. SwiftUI makes the
    /// mark anew when it comes back, so its button is found in its window each time.
    private lazy var lineFold = LineAppsFold(
        setHidden: { hidden in MenuBarMark.shared.isInserted = !hidden },
        button: { NSApp.windows.lazy.compactMap { StatusItemMenu.statusButton(in: $0.contentView) }.first },
        name: { MenuBarMark.autosaveName }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        SetupPresenter.current = setup
        LeftoverTrialData.remove()
        statusMenu.install()
        lineFold.start()
        // The tap waits for the Accessibility grant and arms itself once it's given.
        if !store.safeMode { keyTap.start() }
        Task {
            await store.start()
            // Setup opens by itself once; afterwards it's the tutorial in Settings › General.
            if Self.setupRequested || setup.isFirstRun { setup.show(tutorialOnly: false) }
        }
    }

    /// `-GlowSimulatedMonitors` swaps this Mac's displays for simulated DDC/CI monitors
    /// (`SimulatedDisplayAdapter`) in a debug build.
    private static func makeStore(safeMode: Bool) -> GlowStore {
        #if DEBUG
        if let simulated = SimulatedDisplayAdapter.requested(in: CommandLine.arguments, safeMode: safeMode) {
            return GlowStore(safeMode: safeMode, adapter: simulated)
        }
        #endif
        return GlowStore(safeMode: safeMode)
    }

    /// `--setup-ui` opens setup at launch even after it's been seen, to work on it.
    private static var setupRequested: Bool {
        #if DEBUG
        CommandLine.arguments.contains("--setup-ui")
        #else
        false
        #endif
    }

    /// Opening Glow again while it runs, from Finder or Line Apps' menu, opens Settings: the way in
    /// while its mark is collapsed into Line Apps' line.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyTap.stop()
        SoftwareDimmer.shared.restore()
        store.settings.flush()
    }
}
