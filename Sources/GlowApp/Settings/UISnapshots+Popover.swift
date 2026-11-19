#if DEBUG
import AppKit
import SwiftUI

/// The popover's part of `--snapshot-ui`, light and dark, to `<folder>/popover/`: Glow Desk
/// with boxes in place of sliders on the demo desk, on two displays, at levels between boxes,
/// with a level that can't be set and one that failed, and paused; every box state on its own,
/// the pointer over one included; the sliders again with the popover's rounder buttons; and
/// Settings › General down to Quit Glow, then Settings › Glow without it. Runs on a demo desk
/// and a defaults suite of its own, both gone afterwards.
@MainActor
enum PopoverSnapshots {
    static let suiteName = "app.glow.snapshots.popover"

    static func render(loginItem: LoginItem, to folder: URL, appearances: [(NSAppearance.Name, String)]) {
        let url = folder.appendingPathComponent("popover")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removePersistentDomain(forName: suiteName)
        let settings = GlowSettingsStore(defaults: defaults)
        let store = GlowStore(settings: settings, demoDisplays: true)
        wait { await store.start() }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let own = ownDisplays()
        let tall = CGSize(width: GlowTokens.Size.settingsWindow.width, height: 1_100)

        for (appearance, suffix) in appearances {
            func shot<V: View>(_ name: String, _ view: V, size: CGSize) {
                save(view, size: size, appearance: appearance, to: url.appendingPathComponent("\(name)-\(suffix).png"))
            }
            func popoverShot(_ name: String, desk: YourDesk? = nil) {
                let view = popover(store, desk: desk)
                shot(name, view, size: fitting(view))
            }
            store.levelStyle = .boxes
            popoverShot("boxes")
            // The README's hero: the demo displays as someone's own, with the keys allowed.
            let hero = MenuBarView(store: store, openSettings: { _, _ in }, deskOverride: YourDesk(displays: own),
                                   keyAccessOverride: (isGranted: true, isBundledApp: true))
                .background(GlowTokens.Surface.canvas)
            shot("hero", hero, size: fitting(hero))
            popoverShot("boxes-two-volume", desk: YourDesk(displays: own.filter { $0.isBuiltIn || $0.name.hasPrefix("Dell") }))
            // 47 % is seven boxes and an eighth about half full; 3 % a sliver of the first.
            popoverShot("boxes-mid", desk: YourDesk(displays: own.map { display in
                switch display.name {
                case let name where name.hasPrefix("Dell"): display.setting(.brightness, to: 25).setting(.volume, to: 3)
                case let name where name.hasPrefix("LG"): display.setting(.brightness, to: 90)
                default: display.setting(.brightness, to: 47)
                }
            }))
            // Brightness the Dell listed but Glow hasn't tested, and the LG's last change failed.
            popoverShot("boxes-states", desk: YourDesk(displays: own.filter { !$0.isBuiltIn }.map { display in
                display.name.hasPrefix("Dell") ? display.untested(.brightness) : display.failed(.brightness)
            }))
            shot("boxes-alone", boxStates(), size: fitting(boxStates()))
            // A reread just found the Dell turned with its own buttons, and the built-in
            // changed by macOS: the header says so for a minute.
            popoverShot("boxes-changed", desk: YourDesk(displays: own.filter { $0.isBuiltIn || $0.name.hasPrefix("Dell") }.map { display in
                display.setting(.brightness, to: 30).changedOnDisplay(.brightness)
            }))
            store.levelStyle = .slider
            popoverShot("sliders")
            popoverShot("sliders-two", desk: YourDesk(displays: own.filter { $0.isBuiltIn || $0.name.hasPrefix("Dell") }))
            store.selectedPane = .general
            shot("settings-general-full", GlowSettingsView(store: store, loginItem: loginItem, size: tall), size: tall)
            store.selectedPane = .about
            shot("settings-about", GlowSettingsView(store: store, loginItem: loginItem), size: GlowTokens.Size.settingsWindow)
        }

        // Displays asleep: the boxes stay, dimmed, under the pause notice.
        store.levelStyle = .boxes
        store.handle(.sleep)
        for (appearance, suffix) in appearances {
            let view = popover(store)
            save(view, size: fitting(view), appearance: appearance, to: url.appendingPathComponent("boxes-paused-\(suffix).png"))
        }
        settings.flush()
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// Every look a row of boxes has, each as wide as on a popover row, named beside it.
    private static func boxStates() -> some View {
        let scale = LevelBoxScale(minimum: 0, maximum: 100, step: 1)
        let states: [(title: String, value: Double?, hover: Int?, focused: Bool, enabled: Bool)] = [
            ("No reading", nil, nil, false, true),
            ("0 %", 0, nil, false, true),
            ("6 %", 6, nil, false, true),
            ("47 %", 47, nil, false, true),
            ("100 %", 100, nil, false, true),
            ("Pointer, dark box", 47, 11, false, true),
            ("Pointer, lit box", 47, 3, false, true),
            ("Pointer, edge box", 47, 7, false, true),
            ("Keyboard focus", 47, nil, true, true),
            ("Dimmed", 47, nil, false, false)
        ]
        return VStack(alignment: .leading, spacing: GlowTokens.Space.s3) {
            ForEach(states.indices, id: \.self) { index in
                let state = states[index]
                HStack(spacing: GlowTokens.Space.s2) {
                    Text(state.title)
                        .font(GlowTokens.Typography.caption)
                        .foregroundStyle(GlowTokens.Text.secondary)
                        .frame(width: 100, alignment: .leading)
                    LevelBoxes(scale: scale, value: state.value, label: state.title, spokenValue: "", propose: { _ in },
                               hoverOverride: state.hover, focusOverride: state.focused)
                        .frame(width: GlowTokens.Size.popoverWidth - 2 * GlowTokens.Space.s4 - GlowTokens.Size.sliderSymbol - GlowTokens.Size.percentWidth - 2 * GlowTokens.Space.s2)
                        .disabled(!state.enabled)
                }
            }
        }
        .padding(GlowTokens.Space.s4)
        .background(GlowTokens.Surface.canvas)
    }

    private static func popover(_ store: GlowStore, desk: YourDesk? = nil) -> some View {
        MenuBarView(store: store, openSettings: { _, _ in }, deskOverride: desk)
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

    private static func fitting<V: View>(_ view: V) -> CGSize {
        NSHostingView(rootView: view).fittingSize
    }

    private static func wait(_ work: @escaping @MainActor () async -> Void) {
        var finished = false
        Task {
            await work()
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
        for _ in 0..<6 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        window.contentView = nil
        window.close()
    }
}

private extension DisplaySnapshot {
    /// The display with one setting read at `value`.
    func setting(_ id: CapabilityIdentifier, to value: Double) -> DisplaySnapshot {
        changing(id) { $0.currentValue = .number(value) }
    }

    /// Listed by the display, not yet confirmed by a read: shown, but it can't be changed.
    func untested(_ id: CapabilityIdentifier) -> DisplaySnapshot {
        changing(id) { $0.evidence = .reportedOnly }
    }

    /// The last change didn't take: the value is stale and the row says so.
    func failed(_ id: CapabilityIdentifier) -> DisplaySnapshot {
        changing(id) { descriptor in
            descriptor.freshness = .stale
            descriptor.reliability.lastFailure = "No reply"
        }
    }

    /// A reread found this setting changed outside Glow a moment ago.
    func changedOnDisplay(_ id: CapabilityIdentifier) -> DisplaySnapshot {
        changing(id) { $0.changedOnDisplayAt = Date() }
    }

    private func changing(_ id: CapabilityIdentifier, _ change: (inout CapabilityDescriptor) -> Void) -> DisplaySnapshot {
        var display = self
        if let index = display.capabilities.firstIndex(where: { $0.id == id }) { change(&display.capabilities[index]) }
        return display
    }
}
#endif
