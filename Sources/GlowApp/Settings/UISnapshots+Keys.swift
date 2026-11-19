#if DEBUG
import AppKit
import SwiftUI

/// The brightness keys' part of `--snapshot-ui`, to `<folder>/keys/`: the overlay in each
/// look at a few levels (one between boxes), on software dimming, for volume and after a
/// failed write, and Settings › Controls with its defaults and with other choices, light
/// and dark. Leaves the store's choices as it found them.
@MainActor
enum KeysSnapshots {
    static func render(store: GlowStore, to folder: URL, appearances: [(NSAppearance.Name, String)]) {
        let url = folder.appendingPathComponent("keys")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let savedStep = store.keyStep
        let savedStyle = store.levelStyle
        defer {
            store.keyStep = savedStep
            store.levelStyle = savedStyle
        }
        guard let dell = store.displays.first(where: { $0.name.hasPrefix("Dell") }),
              let dellBrightness = dell.brightnessSetting,
              let lg = store.displays.first(where: { $0.brightnessSetting?.route == .software }),
              let lgBrightness = lg.brightnessSetting else { return }
        let volume = DemoData.descriptor(.volume, "Speaker volume", .essentials, .range(minimum: 0, maximum: 100, step: 1), .number(35), .hardware, unit: "%")
        let states: [(DisplaySnapshot, CapabilityDescriptor, Double, Bool)] = [
            (dell, dellBrightness, 0, false), (dell, dellBrightness, 47, false), (dell, dellBrightness, 100, false),
            (lg, lgBrightness, 47, false), (dell, volume, 35, false), (dell, dellBrightness, 68, true)
        ]
        let detail = CGSize(width: GlowTokens.Size.settingsWindow.width - GlowTokens.Size.settingsSidebarWidth, height: 1_000)

        for (appearance, suffix) in appearances {
            func shot<V: View>(_ name: String, _ view: V, size: CGSize) {
                save(view, size: size, appearance: appearance, to: url.appendingPathComponent("\(name)-\(suffix).png"))
            }
            for style in LevelStyle.allCases {
                let models = states.map { display, capability, value, failed in
                    let model = OverlayModel()
                    model.show(display: display, capability: capability, value: .number(value), failed: failed, style: style)
                    return model
                }
                let size = OverlayView.size(boxes: style == .boxes)
                let sheet = LazyVGrid(columns: Array(repeating: GridItem(.fixed(size.width), spacing: GlowTokens.Space.s6), count: 3), spacing: GlowTokens.Space.s6) {
                    ForEach(models.indices, id: \.self) { OverlayView(model: models[$0]) }
                }
                .padding(GlowTokens.Space.s6)
                .background(Backdrop())
                let sheetSize = CGSize(width: size.width * 3 + GlowTokens.Space.s6 * 4, height: size.height * 2 + GlowTokens.Space.s6 * 3)
                shot("hud-\(style.rawValue)", sheet, size: sheetSize)
            }
            store.keyStep = .likeMacOS
            store.levelStyle = .slider
            shot("pane-controls", pane(store), size: detail)
            store.keyStep = .percent5
            store.levelStyle = .boxes
            shot("pane-controls-chosen", pane(store), size: detail)
        }
    }

    private static func pane(_ store: GlowStore) -> some View {
        VStack(spacing: 0) {
            PaneHeader(pane: .controls).frame(height: GlowTokens.Size.paneHeaderHeight)
            Divider().opacity(0.6)
            ControlsPane(store: store)
        }
        .background(GlowTokens.Surface.canvas)
    }

    /// Something busy behind the overlay, as a desktop would be.
    private struct Backdrop: View {
        var body: some View {
            LinearGradient(colors: [GlowTokens.PaneTint.displays, GlowTokens.PaneTint.controls, GlowTokens.PaneTint.match], startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(0.55)
                .background(GlowTokens.Surface.canvas)
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
