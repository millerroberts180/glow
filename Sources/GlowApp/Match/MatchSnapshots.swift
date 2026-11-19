#if DEBUG
import AppKit
import SwiftUI

/// Brightness Match's part of `--snapshot-ui`: the pane not matched, matched and out of
/// date, and each calibration step, light and dark, to `<folder>/match/`. Runs on the demo
/// desk and leaves it as it found it.
@MainActor
enum MatchSnapshots {
    static func render(store: GlowStore, to folder: URL, appearances: [(NSAppearance.Name, String)]) {
        let url = folder.appendingPathComponent("match")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let saved = store.brightnessMatch
        let detail = CGSize(width: GlowTokens.Size.settingsWindow.width - GlowTokens.Size.settingsSidebarWidth, height: 900)
        for (appearance, suffix) in appearances {
            func shot<V: View>(_ name: String, _ view: V, size: CGSize) {
                save(view, size: size, appearance: appearance, to: url.appendingPathComponent("\(name)-\(suffix).png"))
            }
            store.brightnessMatch = BrightnessMatchSettings()
            shot("pane-not-matched", pane(store), size: detail)
            store.brightnessMatch = matched(store, dellRoute: nil)
            shot("pane-matched", pane(store), size: detail)
            // The Dell was matched over software dimming and has hardware control now.
            store.brightnessMatch = matched(store, dellRoute: .software)
            shot("pane-out-of-date", pane(store), size: detail)
            store.brightnessMatch = BrightnessMatchSettings()

            let window = MatchWindowController.size
            for (name, reach) in steps {
                let session = MatchSession(store: store, patches: WindowOnlyPatches())
                reach(session)
                // Let the demo displays confirm what the session set.
                wait { try? await Task.sleep(for: .milliseconds(400)) }
                shot("calibration-\(name)", MatchCalibrationView(session: session), size: window)
                wait { await session.cancel() }
            }
            let alone = store.displays.filter(\.isBuiltIn)
            shot("calibration-not-enough", MatchCalibrationView(session: MatchSession(store: store, patches: WindowOnlyPatches(), candidates: alone)), size: window)
            if let mac = alone.first {
                shot("patch", MatchPatchView(patch: MatchPatch(screen: 0, name: mac.name, isReference: true)), size: CGSize(width: 480, height: 300))
            }
        }
        store.brightnessMatch = saved
        // Started now, shown once the store pauses: matching can't start while paused.
        let waiting = MatchSession(store: store, patches: WindowOnlyPatches())
        waiting.method = .quick
        waiting.begin()
        self.waiting = waiting
    }

    private static var waiting: MatchSession?

    /// A calibration step while displays sleep; called once the store is paused.
    static func renderPaused(store: GlowStore, to folder: URL, appearances: [(NSAppearance.Name, String)]) {
        let url = folder.appendingPathComponent("match")
        for (appearance, suffix) in appearances {
            let session = MatchSession(store: store, patches: WindowOnlyPatches())
            save(MatchCalibrationView(session: session), size: MatchWindowController.size, appearance: appearance, to: url.appendingPathComponent("calibration-paused-\(suffix).png"))
            if let waiting {
                save(MatchCalibrationView(session: waiting), size: MatchWindowController.size, appearance: appearance, to: url.appendingPathComponent("calibration-compare-paused-\(suffix).png"))
            }
        }
        // Quick Match changes nothing until a slider moves, so there's nothing to put back.
        if let waiting { wait { await waiting.cancel() } }
        waiting = nil
    }

    private static func pane(_ store: GlowStore) -> some View {
        VStack(spacing: 0) {
            PaneHeader(pane: .match).frame(height: GlowTokens.Size.paneHeaderHeight)
            Divider().opacity(0.6)
            BrightnessMatchPane(store: store)
        }
        .background(GlowTokens.Surface.canvas)
    }

    /// The demo desk matched to the MacBook Pro: the Dell by Guided Match, the LG by Quick.
    private static func matched(_ store: GlowStore, dellRoute: ControlRoute?) -> BrightnessMatchSettings {
        var match = BrightnessMatchSettings()
        guard let mac = store.displays.first(where: \.isBuiltIn),
              let dell = store.displays.first(where: { $0.name.hasPrefix("Dell") }),
              let lg = store.displays.first(where: { $0.name.hasPrefix("LG") }) else { return match }
        let date = Date(timeIntervalSince1970: 1_793_000_000)
        let guided = MatchCurve.guided([.init(reference: 0.2, display: 0.3), .init(reference: 0.4, display: 0.48), .init(reference: 0.6, display: 0.63), .init(reference: 0.8, display: 0.8), .init(reference: 1, display: 0.92)])
        let quick = MatchCurve.quick(reference: 0.72, display: 0.8)
        if let guided {
            match.calibrations.append(MatchCalibration(pair: MatchPair(reference: mac.id, display: dell.id), curve: guided, method: .guided, date: date,
                                                       referenceRoute: mac.brightnessRoute, displayRoute: dellRoute ?? dell.brightnessRoute))
        }
        if let quick {
            match.calibrations.append(MatchCalibration(pair: MatchPair(reference: mac.id, display: lg.id), curve: quick, method: .quick, date: date,
                                                       referenceRoute: mac.brightnessRoute, displayRoute: lg.brightnessRoute))
        }
        return match
    }

    /// Each calibration step, reached the way a person reaches it.
    private static let steps: [(String, @MainActor (MatchSession) -> Void)] = [
        ("intro", { $0.method = .quick }),
        ("quick-compare", { session in
            session.method = .quick
            session.begin()
            if let dell = session.adjustable.first, let value = session.value(of: dell.id) { session.set(dell.id, to: value - 6) }
        }),
        ("guided-point-2", { session in
            session.method = .guided
            session.begin()
            session.next()
        }),
        ("guided-review", { session in
            session.method = .guided
            session.begin()
            // A Dell that runs bright when dim, and an LG that runs dim.
            for (index, level) in session.levels.enumerated() {
                let ids = session.adjustable.map(\.id)
                if let dell = ids.first { session.set(dell, to: 100 * min(1, level * 0.7 + 0.18)) }
                if let lg = ids.last { session.set(lg, to: 100 * level * (0.75 + 0.05 * Double(index))) }
                session.next()
            }
        }),
    ]

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
