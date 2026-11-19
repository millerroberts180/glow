#if DEBUG
import AppKit
import SwiftUI

/// Settings › Reading's part of `--snapshot-ui`, light and dark, to `<folder>/reading/`: the
/// Reading pane as it opens and with every other choice made; a display just reread, with a
/// setting changed on the display; the same display read a few minutes ago; what someone hid
/// on a real display; and Connection with the codes the catalog doesn't know. Leaves the demo
/// desk's choices as it found them.
@MainActor
enum ReadingSnapshots {
    static let suiteName = "app.glow.snapshots.reading"

    static func render(store: GlowStore, to folder: URL, appearances: [(NSAppearance.Name, String)]) {
        let url = folder.appendingPathComponent("reading")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // Only these shots read, so a scheduled reread can't land between them.
        store.reading.loop?.cancel()
        let detail = CGSize(width: GlowTokens.Size.settingsWindow.width - GlowTokens.Size.settingsSidebarWidth, height: 980)
        let tall = CGSize(width: detail.width, height: 1_900)
        let savedReading = store.settings.value.reading
        let savedLastSet = store.settings.value.lastSet

        // A real desk, so Hide applies: the demo displays as the hardware adapter would report them.
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removePersistentDomain(forName: suiteName)
        let adapter = MockDisplayAdapter { generation in
            DemoData.displays(generation: generation).filter { $0.identity == DemoData.dellIdentity }.map { display in
                var display = display
                display.isDemo = false
                return display
            }
        }
        adapter.readDelay = .zero
        let real = GlowStore(settings: GlowSettingsStore(defaults: defaults), demoDisplays: false, adapter: adapter)
        wait { await real.refresh() }
        if let dell = real.displays.first {
            let hideable = dell.osdSections.flatMap(\.capabilities).filter(\.canBeHidden).map(\.id)
            let chosen = [CapabilityIdentifier.pictureMode, .sharpness].filter(hideable.contains)
            for id in chosen.isEmpty ? Array(hideable.suffix(2)) : chosen {
                real.hide(id, on: dell.id)
            }
            real.selectedDisplayID = dell.id
        }

        for (appearance, suffix) in appearances {
            func shot<V: View>(_ name: String, _ view: V, size: CGSize) {
                save(view, size: size, appearance: appearance, to: url.appendingPathComponent("\(name)-\(suffix).png"))
            }
            // Every display read just now, so the age doesn't depend on how long the shots before took.
            for display in store.displays { store.reading.lastRead[display.id] = Date() }
            store.settings.value.reading = ReadingSettings()
            shot("pane-reading", pane(.reading, ReadingPane(store: store)), size: detail)
            // Every other choice, with values kept for two real displays.
            store.settings.value.reading.freshness = .always
            store.settings.value.reading.atLaunch = .restore
            store.settings.value.reading.patience = .patient
            var kept = LastSetValues()
            kept.record([.brightness: .number(40)], on: DemoData.dellIdentity)
            kept.record([.brightness: .number(55)], on: DemoData.lgIdentity)
            store.settings.value.lastSet = kept
            shot("pane-reading-chosen", pane(.reading, ReadingPane(store: store)), size: detail)
            store.settings.value.reading = savedReading
            store.settings.value.lastSet = savedLastSet

            // The Dell's brightness and volume turned with its own buttons, then Read Again.
            if let dell = store.displays.first(where: { $0.identity == DemoData.dellIdentity }),
               let mock = store.adapter as? MockDisplayAdapter {
                store.selectedDisplayID = dell.id
                mock.simulateChangeOnDisplay(.number(30), capability: .brightness, display: dell.id)
                mock.simulateChangeOnDisplay(.number(55), capability: .volume, display: dell.id)
                wait { await store.readAgain(dell.id) }
                shot("pane-displays-changed", pane(.displays, DisplaysPane(store: store)), size: tall)
                // Three minutes on, the marks are gone and the age says so.
                store.clearChangeMarks(now: Date().addingTimeInterval(ReadingSchedule.markDuration + 1))
                store.reading.lastRead[dell.id] = Date().addingTimeInterval(-185)
                shot("pane-displays-read-age", pane(.displays, DisplaysPane(store: store)), size: tall)
                // Put the demo Dell back for the shots after these.
                mock.simulateChangeOnDisplay(dell.capabilities.first(where: { $0.id == .brightness })?.currentValue ?? .number(60), capability: .brightness, display: dell.id)
                mock.simulateChangeOnDisplay(dell.capabilities.first(where: { $0.id == .volume })?.currentValue ?? .number(35), capability: .volume, display: dell.id)
                wait { await store.readAgain(dell.id) }
                store.clearChangeMarks(now: Date().addingTimeInterval(ReadingSchedule.markDuration + 1))
            }

            shot("pane-displays-hidden", pane(.displays, DisplaysPane(store: real)), size: tall)
            shot("pane-connection-reported", pane(.connection, ConnectionDetailsPane(store: real)), size: CGSize(width: detail.width, height: 2_750))
        }
        defaults.removePersistentDomain(forName: suiteName)
    }

    private static func pane<V: View>(_ pane: GlowSettingsPane, _ content: V) -> some View {
        VStack(spacing: 0) {
            PaneHeader(pane: pane).frame(height: GlowTokens.Size.paneHeaderHeight)
            Divider().opacity(0.6)
            content
        }
        .background(GlowTokens.Surface.canvas)
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
#endif
