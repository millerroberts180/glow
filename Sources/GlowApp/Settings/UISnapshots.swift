#if DEBUG
import AppKit
import SwiftUI

/// `swift run Glow --snapshot-ui <folder>` (debug builds): renders every Settings pane, the
/// popover on several desks, the menu-bar mark and the confirmation prompt, light and dark, to
/// PNGs off screen, with demo displays and a throwaway defaults suite that is deleted
/// afterwards. Every setup step goes to `<folder>/setup/`.
/// Known artifact: the transparent title-bar strip renders white off screen, so a dark-mode
/// pane header can look blank. Check that in a real window.
@MainActor
enum UISnapshots {
    static let suiteName = "app.glow.snapshots"

    static func folder(in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--snapshot-ui"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func render(to folder: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removePersistentDomain(forName: suiteName)
        let settings = GlowSettingsStore(defaults: defaults)
        let store = GlowStore(settings: settings)
        store.setDemoMode(true)
        wait { await store.start() }
        // start() makes Glow a menu-bar app; keep this run out of sight instead.
        app.setActivationPolicy(.prohibited)
        let loginItem = LoginItem()
        let url = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let appearances: [(NSAppearance.Name, String)] = [(.aqua, "light"), (.darkAqua, "dark")]
        let dell = store.displays.first(where: { $0.name.hasPrefix("Dell") })

        for (appearance, suffix) in appearances {
            func shot<V: View>(_ name: String, _ view: V, size: CGSize) {
                save(view, size: size, appearance: appearance, to: url.appendingPathComponent("\(name)-\(suffix).png"))
            }
            let window = GlowTokens.Size.settingsWindow
            store.selectedDisplayID = dell?.id
            for pane in GlowSettingsPane.allCases {
                store.selectedPane = pane
                shot("settings-\(pane.rawValue)", GlowSettingsView(store: store, loginItem: loginItem), size: window)
            }
            // Every demo display's Digital OSD, and the longest ones in full.
            store.selectedPane = .displays
            for display in store.displays {
                store.selectedDisplayID = display.id
                shot("settings-displays-\(slug(display.name))", GlowSettingsView(store: store, loginItem: loginItem), size: window)
            }
            store.selectedDisplayID = dell?.id
            let tall = CGSize(width: window.width, height: 1_560)
            shot("settings-displays-full", GlowSettingsView(store: store, loginItem: loginItem, size: tall), size: tall)
            store.selectedPane = .connection
            let taller = CGSize(width: window.width, height: 4_000)
            shot("settings-connection-full", GlowSettingsView(store: store, loginItem: loginItem, size: taller), size: taller)
            // A scene that only partly took, as Apply reports it.
            let detail = CGSize(width: window.width - GlowTokens.Size.settingsSidebarWidth, height: window.height)
            store.sceneState.results = ["demo-work": SceneResult(succeeded: 2, failed: 1, skipped: 1), "demo-night": SceneResult(succeeded: 3, failed: 0)]
            store.sceneState.lastApplied = "demo-work"
            shot("pane-scenes-partial", paneAlone(.scenes, ScenesPane(store: store)), size: detail)
            shot("popover", popover(store), size: fitting(popover(store)))
            // More scenes than fit on one line: the rest wait behind "…".
            let examples = store.scenes
            store.scenes = examples + SceneSymbol.all.map { GlowScene(name: $0.name, symbol: $0.symbol, displays: []) }
            shot("popover-many-scenes", popover(store), size: fitting(popover(store)))
            store.scenes = examples
            // A new scene from the demo desk, in the editor sheet.
            let draft = SceneDraft(scene: store.newSceneFromCurrentSettings(), isNew: true)
            shot("scene-editor", SceneEditor(store: store, draft: draft).background(GlowTokens.Surface.canvas), size: SceneEditor.size)
            // The same scene once the moon is picked: its name follows, to Night.
            var night = draft.scene
            night.wear("moon", defaultName: night.name)
            shot("scene-editor-symbol", SceneEditor(store: store, draft: SceneDraft(scene: night, isNew: true)).background(GlowTokens.Surface.canvas), size: SceneEditor.size)
            if let presentation = store.scenes.first(where: { $0.id == "demo-presentation" }), let confirmation = store.confirmation(for: presentation) {
                saveSceneAlert(confirmation, appearance: appearance, to: url.appendingPathComponent("confirm-scene-\(suffix).png"))
            }

            // The popover on other desks: someone's own displays (Native with Software dimming,
            // then two that are matched), one display, still reading, a monitor still being
            // checked, and none.
            let own = ownDisplays()
            let desks: [(String, YourDesk)] = [
                ("popover-two", YourDesk(displays: own.filter { $0.isBuiltIn || $0.name.hasPrefix("LG") })),
                ("popover-two-matched", YourDesk(displays: own.filter(\.isAppearanceMatched))),
                ("popover-one", YourDesk(displays: own.filter(\.isBuiltIn))),
                ("popover-reading", YourDesk(displays: [], isReading: true)),
                ("popover-checking", YourDesk(displays: own.filter { $0.isBuiltIn || $0.name.hasPrefix("LG") }.map { display in
                    guard !display.isBuiltIn else { return display }
                    var display = display
                    display.capabilities = []
                    display.isChecking = true
                    return display
                }, isReading: true)),
                ("popover-none", YourDesk(displays: [])),
                ("popover-long-name", YourDesk(displays: own.filter { $0.isBuiltIn || $0.name.hasPrefix("LG") }.map { display in
                    var display = display
                    if !display.isBuiltIn { display.name = "LG UltraFine 27 on the left of the desk" }
                    return display
                }))
            ]
            for (name, desk) in desks {
                shot(name, popover(store, desk: desk), size: fitting(popover(store, desk: desk)))
            }
            shot("menubar-icon", menuBarIcon(), size: CGSize(width: 220, height: 64))
            if let dell, let input = dell.capabilities.first(where: { $0.requiresConfirmation && $0.isSafelyEditable }) {
                saveAlert(PendingChange(display: dell, descriptor: input, value: .text("HDMI 1")), appearance: appearance, to: url.appendingPathComponent("confirm-change-\(suffix).png"))
            }
        }

        // The window Glow really opens, built by the same controller, kept off screen.
        store.selectedPane = .displays
        store.selectedDisplayID = dell?.id
        for (appearance, suffix) in appearances {
            saveRealWindow(store: store, loginItem: loginItem, appearance: appearance, to: url.appendingPathComponent("window-displays-\(suffix).png"))
        }
        renderSetup(store: store, loginItem: loginItem, to: url.appendingPathComponent("setup"), appearances: appearances)
        renderScenes(store: store, loginItem: loginItem, to: url, appearances: appearances)
        renderUnlistedConnection(to: url, appearances: appearances)
        MatchSnapshots.render(store: store, to: url, appearances: appearances)
        KeysSnapshots.render(store: store, to: url, appearances: appearances)
        PopoverSnapshots.render(loginItem: loginItem, to: url, appearances: appearances)
        ReadingSnapshots.render(store: store, to: url, appearances: appearances)

        // Paused: displays asleep. Controls stay visible and say so.
        store.handle(.sleep)
        MatchSnapshots.renderPaused(store: store, to: url, appearances: appearances)
        for (appearance, suffix) in appearances {
            store.selectedPane = .displays
            store.selectedDisplayID = dell?.id
            save(GlowSettingsView(store: store, loginItem: loginItem), size: GlowTokens.Size.settingsWindow, appearance: appearance, to: url.appendingPathComponent("settings-displays-paused-\(suffix).png"))
            save(popover(store), size: fitting(popover(store)), appearance: appearance, to: url.appendingPathComponent("popover-paused-\(suffix).png"))
        }

        settings.flush()
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// The person's own scenes before there are any, on the demo desk without its examples;
    /// then a demo scene applied, so the Dell's starting values differ, and restored.
    private static func renderScenes(store: GlowStore, loginItem: LoginItem, to url: URL, appearances: [(NSAppearance.Name, String)]) {
        let empty = GlowStore(settings: GlowSettingsStore(defaults: UserDefaults(suiteName: suiteName) ?? .standard), demoDisplays: false, adapter: MockDisplayAdapter())
        wait { await empty.refresh() }
        let deskless = GlowStore(settings: GlowSettingsStore(defaults: UserDefaults(suiteName: suiteName) ?? .standard), demoDisplays: false, adapter: MockDisplayAdapter(displays: { _ in [] }))
        wait { await deskless.refresh() }
        let detail = CGSize(width: GlowTokens.Size.settingsWindow.width - GlowTokens.Size.settingsSidebarWidth, height: GlowTokens.Size.settingsWindow.height)
        let tall = CGSize(width: GlowTokens.Size.settingsWindow.width, height: 1_560)
        for (appearance, suffix) in appearances {
            save(paneAlone(.scenes, ScenesPane(store: empty)), size: detail, appearance: appearance, to: url.appendingPathComponent("pane-scenes-empty-\(suffix).png"))
            save(popover(empty), size: fitting(popover(empty)), appearance: appearance, to: url.appendingPathComponent("popover-no-scenes-\(suffix).png"))
            // Glow bundled, without the Accessibility grant: the keys' caption offers Allow….
            let allow = popover(empty, keyAccess: (isGranted: false, isBundledApp: true))
            save(allow, size: fitting(allow), appearance: appearance, to: url.appendingPathComponent("popover-keys-allow-\(suffix).png"))
            // A saved scene opened for editing, then again with none of its displays connected.
            if let work = store.scenes.first(where: { $0.id == "demo-work" }) {
                save(SceneEditor(store: empty, draft: SceneDraft(scene: work, isNew: false)).background(GlowTokens.Surface.canvas),
                     size: SceneEditor.size, appearance: appearance, to: url.appendingPathComponent("scene-editor-saved-\(suffix).png"))
                save(SceneEditor(store: deskless, draft: SceneDraft(scene: work, isNew: false)).background(GlowTokens.Surface.canvas),
                     size: SceneEditor.size, appearance: appearance, to: url.appendingPathComponent("scene-editor-away-\(suffix).png"))
            }
        }
        guard let night = store.scenes.first(where: { $0.id == "demo-night" }),
              let dell = store.displays.first(where: { $0.name.hasPrefix("Dell") }) else { return }
        wait { await store.applyScene(night) }
        store.selectedPane = .displays
        store.selectedDisplayID = dell.id
        for (appearance, suffix) in appearances {
            save(GlowSettingsView(store: store, loginItem: loginItem, size: tall), size: tall, appearance: appearance, to: url.appendingPathComponent("settings-displays-restore-\(suffix).png"))
            save(popover(store), size: fitting(popover(store)), appearance: appearance, to: url.appendingPathComponent("popover-scene-applied-\(suffix).png"))
        }
        wait { await store.restoreStartingValues(of: dell) }
        for (appearance, suffix) in appearances {
            save(GlowSettingsView(store: store, loginItem: loginItem, size: tall), size: tall, appearance: appearance, to: url.appendingPathComponent("settings-displays-restored-\(suffix).png"))
        }
    }

    /// Connection details for a monitor that sent no capability report but answered reads.
    private static func renderUnlistedConnection(to url: URL, appearances: [(NSAppearance.Name, String)]) {
        let adapter = MockDisplayAdapter(displays: { [DemoData.unlistedDisplay(generation: $0)] })
        let unlisted = GlowStore(settings: GlowSettingsStore(defaults: UserDefaults(suiteName: suiteName) ?? .standard), demoDisplays: false, adapter: adapter)
        wait { await unlisted.refresh() }
        let size = CGSize(width: GlowTokens.Size.settingsWindow.width - GlowTokens.Size.settingsSidebarWidth, height: 2_100)
        for (appearance, suffix) in appearances {
            save(paneAlone(.connection, ConnectionDetailsPane(store: unlisted)), size: size, appearance: appearance, to: url.appendingPathComponent("pane-connection-unlisted-\(suffix).png"))
        }
    }

    private static func popover(_ store: GlowStore, desk: YourDesk? = nil, keyAccess: (isGranted: Bool, isBundledApp: Bool)? = nil) -> some View {
        MenuBarView(store: store, openSettings: { _, _ in }, deskOverride: desk, keyAccessOverride: keyAccess)
            .background(GlowTokens.Surface.canvas)
    }

    /// The demo displays with the demo badge taken off, standing in for someone's own.
    private static func ownDisplays() -> [DisplaySnapshot] {
        DemoData.displays(generation: 0).map { display in
            var display = display
            display.isDemo = false
            return display
        }
    }

    /// The menu-bar mark as the menu bar tints it, at size and four times over.
    private static func menuBarIcon() -> some View {
        HStack(spacing: 24) {
            Image(nsImage: GlowLogo.menuBarImage())
            Image(nsImage: GlowLogo.menuBarImage())
                .resizable()
                .frame(width: 72, height: 72)
            Image(nsImage: GlowLogo.markImage(side: GlowTokens.Size.popoverMark))
        }
        .foregroundStyle(GlowTokens.Text.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GlowTokens.Surface.canvas)
    }

    private static func paneAlone<V: View>(_ pane: GlowSettingsPane, _ content: V) -> some View {
        VStack(spacing: 0) {
            PaneHeader(pane: pane).frame(height: GlowTokens.Size.paneHeaderHeight)
            Divider().opacity(0.6)
            content
        }
        .background(GlowTokens.Surface.canvas)
    }

    private static func slug(_ name: String) -> String {
        name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).first.map(String.init) ?? "display"
    }

    private static func fitting<V: View>(_ view: V) -> CGSize {
        let hosting = NSHostingView(rootView: view)
        return hosting.fittingSize
    }

    /// Runs async work to completion on the main actor before rendering continues.
    private static func wait(_ work: @escaping @MainActor () async -> Void) {
        let task = Task { await work() }
        var finished = false
        Task {
            await task.value
            finished = true
        }
        while !finished {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private static func save<V: View>(_ view: V, size: CGSize, appearance: NSAppearance.Name, to url: URL) {
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderBack(nil)
        settle(hosting)
        write(hosting, to: url)
        // Close it, or every earlier window keeps redrawing as the store changes.
        window.contentView = nil
        window.close()
    }

    /// Settings as `SettingsWindowPresenter` builds it, with the title bar and window
    /// buttons, never shown. Prints its size and sidebar width, which should be the tokens'.
    private static func saveRealWindow(store: GlowStore, loginItem: LoginItem, appearance: NSAppearance.Name, to url: URL) {
        let controller = HostedWindow(title: "Glow Settings", size: GlowTokens.Size.settingsWindow, sidebar: true) {
            GlowSettingsView(store: store, loginItem: loginItem)
        }
        guard let window = controller.window, let frameView = window.contentView?.superview else { return }
        window.appearance = NSAppearance(named: appearance)
        window.setFrameOrigin(CGPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)
        settle(frameView)
        let sidebar = splitView(in: frameView)?.arrangedSubviews.first?.frame.width ?? 0
        print("window \(appearance.rawValue): content \(window.contentLayoutRect.size), sidebar \(sidebar) pt")
        write(frameView, to: url)
        window.contentViewController = nil
        window.close()
    }

    /// Every setup step in the window `SetupWindowController` builds, off screen, in each
    /// state it has: your displays as the demo desk, reading, with none, one, your own,
    /// once Glow Desk has opened and while paused; the match choosing on three displays and
    /// on two, comparing, saving, matched, a display that didn't go back, and paused; the
    /// keys asking, asked, under `swift run`, allowed, pressed and left to macOS; open at
    /// login under `swift run` and in Glow.app; and the tutorial. Every desk but the first
    /// is demo displays of its own through a mock adapter, so the stores after this are
    /// untouched. Ticks come from the same counts the app keeps: an opening of Glow Desk,
    /// and a brightness key handled by the store, which writes only to its mock adapter.
    private static func renderSetup(store: GlowStore, loginItem: LoginItem, to folder: URL, appearances: [(NSAppearance.Name, String)]) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let asked = KeyPermission(isGranted: { false }, request: {}, isBundledApp: { true })
        let granted = KeyPermission(isGranted: { true }, request: {}, isBundledApp: { true })
        let terminal = KeyPermission(isGranted: { false }, request: {}, isBundledApp: { false })
        let live = SetupLogin.live(loginItem)
        let bundled = SetupLogin(canRegister: true, isOn: { false }, detail: { "" }, set: { _ in })
        let own = ownDisplays()
        let suite = "\(suiteName).setup"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        func mock(_ pick: @escaping ([DisplaySnapshot]) -> [DisplaySnapshot]) -> MockDisplayAdapter {
            MockDisplayAdapter(displays: { pick(DemoData.displays(generation: $0)) })
        }
        /// A desk of demo displays on a defaults suite of its own.
        func desk(_ adapter: MockDisplayAdapter) -> GlowStore {
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            let desk = GlowStore(settings: GlowSettingsStore(defaults: defaults), demoDisplays: false, adapter: adapter)
            wait { await desk.refresh() }
            return desk
        }
        let none = desk(mock { _ in [] })
        let single = desk(mock { Array($0.prefix(1)) })
        for (appearance, suffix) in appearances {
            func file(_ name: String) -> URL { folder.appendingPathComponent("setup-\(name)-\(suffix).png") }
            func open(_ step: SetupModel.Step, on desk: GlowStore = store, tutorialOnly: Bool = false, permission: KeyPermission = asked,
                      login: SetupLogin = live, showing override: YourDesk? = nil) -> SetupWindowController {
                let controller = SetupWindowController(store: desk, login: login, tutorialOnly: tutorialOnly, permission: permission,
                                                       patches: { _ in WindowOnlyPatches() })
                controller.model.deskOverride = override
                controller.model.step = step
                controller.window?.appearance = NSAppearance(named: appearance)
                controller.window?.setFrameOrigin(CGPoint(x: -20_000, y: -20_000))
                controller.window?.orderBack(nil)
                return controller
            }
            func shoot(_ controller: SetupWindowController, _ name: String, after seconds: Double = 0.3) {
                guard let frame = controller.window?.contentView?.superview else { return }
                pause(frame, for: seconds)
                write(frame, to: file(name))
            }
            func close(_ controller: SetupWindowController) {
                controller.window?.contentViewController = nil
                controller.close()
            }
            func one(_ step: SetupModel.Step, _ name: String, on desk: GlowStore = store, tutorialOnly: Bool = false,
                     permission: KeyPermission = asked, login: SetupLogin = live, showing override: YourDesk? = nil) {
                let controller = open(step, on: desk, tutorialOnly: tutorialOnly, permission: permission, login: login, showing: override)
                shoot(controller, name)
                close(controller)
            }

            one(.displays, "1-displays-demo")
            // Read on a desk with none yet, and one display alone: no match step, so three dots.
            one(.displays, "1-displays-reading", on: none, showing: YourDesk(displays: [], isReading: true))
            one(.displays, "1-displays-none", on: none)
            one(.displays, "1-displays-one", on: single, showing: YourDesk(displays: Array(own.prefix(1))))
            one(.displays, "1-displays-own", showing: YourDesk(displays: own))
            // Glow Desk opening, as MenuBarView counts it, ticks the step off.
            let opening = open(.displays, showing: YourDesk(displays: own))
            store.glowDeskOpens += 1
            shoot(opening, "1-displays-opened")
            close(opening)

            // Choosing on three displays, then a whole Quick Match on two: the Dell set a
            // little dimmer than it was, saved, and matched.
            one(.match, "2-match-pick-three")
            let two = desk(mock { $0.filter { $0.isBuiltIn || $0.name.hasPrefix("Dell") } })
            let matching = open(.match, on: two)
            shoot(matching, "2-match-pick")
            matching.model.startMatch()
            if let session = matching.model.match, let dell = session.adjustable.first {
                session.set(dell.id, to: 55)
            }
            shoot(matching, "2-match-adjust", after: 0.5)
            // Each display's write takes the mock 90 ms, so this catches it saving.
            let saving = Task { await matching.model.saveMatch() }
            shoot(matching, "2-match-settling", after: 0.04)
            wait { await saving.value }
            shoot(matching, "2-match-matched")
            close(matching)
            // Cancelled after the Dell stopped answering: it can't be put back.
            let silent = mock { $0.filter { $0.isBuiltIn || $0.name.hasPrefix("Dell") } }
            let failing = open(.match, on: desk(silent))
            failing.model.startMatch()
            if let session = failing.model.match, let dell = session.adjustable.first {
                session.set(dell.id, to: 55)
            }
            pause(failing.window?.contentView ?? NSView(), for: 0.5)
            silent.silentDisplays = [DemoData.dellIdentity]
            wait { await failing.model.cancelMatch() }
            shoot(failing, "2-match-problem")
            close(failing)

            one(.keys, "3-keys")
            let asking = open(.keys)
            asking.model.requestAccess()
            shoot(asking, "3-keys-asked")
            close(asking)
            one(.keys, "3-keys-swift-run", permission: terminal)
            // Allowed on someone's own desk, then a key press the store takes.
            let keyed = desk(mock { $0 })
            let pressing = open(.keys, on: keyed, permission: granted)
            shoot(pressing, "3-keys-allowed")
            _ = keyed.handleBrightnessKey(BrightnessKeyPress(direction: .up, quarterStep: false), pointerDisplay: nil)
            shoot(pressing, "3-keys-pressed")
            close(pressing)
            // Demo displays leave the keys to macOS.
            one(.keys, "3-keys-left-to-macos", permission: granted)

            one(.finish, "4-finish-swift-run")
            one(.finish, "4-finish", login: bundled)

            // Displays asleep: Glow Desk's pause notice, and matching waits.
            let asleep = desk(mock { $0 })
            asleep.handle(.sleep)
            one(.displays, "1-displays-paused", on: asleep)
            one(.match, "2-match-unavailable", on: asleep)

            // Reopened from Settings: the same steps without the permission or open at login.
            one(.displays, "tutorial-displays", tutorialOnly: true)
            one(.match, "tutorial-match", tutorialOnly: true)
            one(.keys, "tutorial-keys", on: keyed, tutorialOnly: true, permission: granted)
            one(.displays, "tutorial-displays-one", on: single, tutorialOnly: true)
        }
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }

    /// Lets a window run, animations and all, for a while before it's drawn.
    private static func pause(_ view: NSView, for seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: min(end, Date().addingTimeInterval(0.02)))
        }
    }

    private static func splitView(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView { return split }
        return view.subviews.lazy.compactMap(splitView(in:)).first
    }

    private static func settle(_ view: NSView) {
        for _ in 0..<6 {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    /// The confirmation as macOS draws it, from the same copy the dialog uses.
    private static func saveAlert(_ change: PendingChange, appearance: NSAppearance.Name, to url: URL) {
        let alert = NSAlert()
        alert.messageText = change.title
        alert.informativeText = change.message
        alert.addButton(withTitle: change.confirmTitle)
        alert.addButton(withTitle: "Cancel")
        alert.window.appearance = NSAppearance(named: appearance)
        alert.layout()
        guard let view = alert.window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        write(view, to: url)
    }

    /// A scene's confirmation as macOS draws it, with its three answers.
    private static func saveSceneAlert(_ confirmation: SceneConfirmation, appearance: NSAppearance.Name, to url: URL) {
        let alert = NSAlert()
        alert.messageText = confirmation.title
        alert.informativeText = confirmation.message
        alert.addButton(withTitle: confirmation.confirmTitle)
        alert.addButton(withTitle: confirmation.declineTitle)
        alert.addButton(withTitle: "Cancel")
        alert.window.appearance = NSAppearance(named: appearance)
        alert.layout()
        guard let view = alert.window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        write(view, to: url)
    }

    private static func write(_ view: NSView, to url: URL) {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
