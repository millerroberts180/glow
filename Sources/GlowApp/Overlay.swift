import AppKit
import Observation
import SwiftUI

/// What one display's overlay shows. The coordinator keeps one per display and changes it in
/// place, so a held key moves the same panel's level instead of drawing a new one each step.
@MainActor @Observable
final class OverlayModel {
    enum Symbol: Equatable { case brightness, volume, other }

    var displayName = ""
    var capability = ""
    var symbol = Symbol.other
    /// Where the value sits in the setting's range, 0 to 1; nil for a setting without one.
    var level: Double?
    var valueText = ""
    var spokenValue = ""
    var method = ""
    var isSoftware = false
    var failed = false
    var style = LevelStyle.slider

    func show(display: DisplaySnapshot, capability descriptor: CapabilityDescriptor, value: CapabilityValue, failed: Bool, style: LevelStyle) {
        displayName = display.name
        capability = descriptor.label
        symbol = descriptor.id == .brightness ? .brightness : descriptor.id == .volume ? .volume : .other
        level = Self.level(of: value, in: descriptor.kind)
        valueText = value.description + (descriptor.unit ?? "")
        var spoken = descriptor
        spoken.currentValue = value
        spokenValue = spoken.spokenValue
        method = failed ? "Couldn’t update this display" : descriptor.route.userLabel
        isSoftware = descriptor.route == .software
        self.failed = failed
        self.style = style
    }

    static func level(of value: CapabilityValue, in kind: CapabilityKind) -> Double? {
        guard case let .range(minimum, maximum, _) = kind, case let .number(number) = value, maximum > minimum else { return nil }
        return min(1, max(0, (number - minimum) / (maximum - minimum)))
    }

    /// The boxes look needs a level to draw; anything else keeps the slider card.
    var showsBoxes: Bool { style == .boxes && level != nil }
}

/// macOS's brightness overlay draws a level as 16 boxes. Each box is full, empty, or (the one
/// the level falls in) filled from its leading edge by its share: 47% is 7 full boxes and
/// the 8th 52% full. The popover's boxes use the same rule, from `LevelBoxScale`.
enum OverlayBoxes {
    static let count = LevelBoxScale.boxCount

    static func fills(level: Double, count: Int = count) -> [Double] {
        LevelBoxScale(minimum: 0, maximum: 1, step: 0, count: count).fills(at: level)
    }
}

/// The overlay for whichever look is chosen in Settings › Controls.
struct OverlayView: View {
    let model: OverlayModel

    static func size(boxes: Bool) -> CGSize {
        boxes ? CGSize(width: GlowTokens.Size.overlayHUD, height: GlowTokens.Size.overlayHUD)
            : CGSize(width: GlowTokens.Size.overlayWidth, height: GlowTokens.Size.overlayHeight)
    }

    var body: some View {
        let boxes = model.showsBoxes
        let shape = RoundedRectangle(cornerRadius: boxes ? GlowTokens.Radius.overlayHUD : GlowTokens.Radius.window, style: .continuous)
        Group {
            if boxes { BoxesContent(model: model) } else { SliderContent(model: model) }
        }
        .frame(width: Self.size(boxes: boxes).width, height: Self.size(boxes: boxes).height)
        .background { shape.fill(GlowTokens.Surface.overlayTint) }
        .background { HUDMaterial().clipShape(shape) }
        .overlay { shape.strokeBorder(GlowTokens.Border.subtle, lineWidth: 0.5) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.capability), \(model.displayName)")
        .accessibilityValue(model.failed ? "\(model.spokenValue). \(model.method)" : model.spokenValue)
    }
}

/// Glow's original overlay card, with a thin bar for the level.
private struct SliderContent: View {
    let model: OverlayModel

    var body: some View {
        VStack(alignment: .leading, spacing: GlowTokens.Space.s2) {
            Label("Glow", systemImage: model.failed ? "exclamationmark.triangle.fill" : "sun.max.fill")
                .font(GlowTokens.Typography.headline)
                .foregroundStyle(model.failed ? GlowTokens.Status.dangerText : GlowTokens.Text.primary)
            Text(model.displayName).font(GlowTokens.Typography.caption).foregroundStyle(GlowTokens.Text.secondary).lineLimit(1)
            HStack {
                Text(model.capability).fontWeight(.medium)
                Spacer()
                Text(model.valueText).fontWeight(.semibold).monospacedDigit()
            }
            if let level = model.level {
                LevelBar(level: level)
            }
            Text(model.method).font(GlowTokens.Typography.caption).foregroundStyle(model.failed ? GlowTokens.Status.dangerText : GlowTokens.Text.secondary)
        }
        .padding(GlowTokens.Space.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct LevelBar: View {
    let level: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(GlowTokens.Surface.overlayBoxUnlit)
                Capsule().fill(GlowTokens.Accent.primary)
                    .frame(width: proxy.size.width * level)
            }
        }
        .frame(height: GlowTokens.Size.overlayLevelBar)
    }
}

/// A square like macOS's own brightness overlay: the symbol, the boxes, then the display.
private struct BoxesContent: View {
    let model: OverlayModel

    var body: some View {
        let level = model.level ?? 0
        VStack(spacing: GlowTokens.Space.s2) {
            Spacer(minLength: 0)
            symbol(level: level)
                .font(GlowTokens.Typography.overlaySymbol)
                .foregroundStyle(model.failed ? GlowTokens.Status.dangerText : GlowTokens.Text.primary)
                .frame(height: GlowTokens.Size.overlayHUD / 2)
            Spacer(minLength: 0)
            BoxRow(level: level)
            VStack(spacing: GlowTokens.Space.s0_5) {
                Text(model.displayName)
                    .font(GlowTokens.Typography.caption)
                    .foregroundStyle(GlowTokens.Text.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // The line is always there, so the boxes never shift when it appears.
                Text(model.failed ? model.method : model.isSoftware ? "Software dimming" : " ")
                    .font(GlowTokens.Typography.caption)
                    .foregroundStyle(model.failed ? GlowTokens.Status.dangerText : GlowTokens.Text.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, GlowTokens.Space.s5)
        .padding(.vertical, GlowTokens.Space.s4)
    }

    /// The sun dims with the level and the speaker's waves fill with it.
    @ViewBuilder private func symbol(level: Double) -> some View {
        if model.failed {
            Image(systemName: "exclamationmark.triangle.fill")
        } else {
            switch model.symbol {
            case .brightness:
                Image(systemName: level < 0.5 ? "sun.min.fill" : "sun.max.fill")
                    .opacity(0.55 + 0.45 * level)
            case .volume:
                Image(systemName: level == 0 ? "speaker.fill" : "speaker.wave.3.fill", variableValue: level)
            case .other:
                Image(systemName: "slider.horizontal.below.rectangle")
            }
        }
    }
}

private struct BoxRow: View {
    let level: Double

    var body: some View {
        let box = RoundedRectangle(cornerRadius: GlowTokens.Radius.overlayBox, style: .continuous)
        HStack(spacing: GlowTokens.Space.s0_5) {
            ForEach(Array(OverlayBoxes.fills(level: level).enumerated()), id: \.offset) { _, fill in
                box.fill(GlowTokens.Surface.overlayBoxUnlit)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Rectangle().fill(GlowTokens.Surface.overlayBoxLit)
                                .frame(width: proxy.size.width * fill)
                        }
                    }
                    .clipShape(box)
            }
        }
        .frame(height: GlowTokens.Size.overlayBoxHeight)
    }
}

/// The blurred, vibrant HUD material macOS uses for its own overlays.
private struct HUDMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Shows the overlay on the display that changed: one panel per display, made once, whose
/// model each change updates. It fades out `GlowTokens.Motion.overlayLinger` after the last
/// change, or simply goes under Reduce Motion.
@MainActor
final class OverlayCoordinator {
    private var models: [UInt32: OverlayModel] = [:]
    private var panels: [UInt32: NSPanel] = [:]
    private var dismissTasks: [UInt32: Task<Void, Never>] = [:]
    /// False outside the running app (tests, snapshots): the model still changes, but no
    /// panel is made.
    private let presentsPanels: @MainActor () -> Bool

    init(presentsPanels: @escaping @MainActor () -> Bool = { NSApp?.isRunning == true }) {
        self.presentsPanels = presentsPanels
    }

    /// The model for a display's overlay, once anything has been shown on it.
    func model(for displayID: UInt32) -> OverlayModel? { models[displayID] }

    var panelCount: Int { panels.count }

    func show(display: DisplaySnapshot, capability: CapabilityDescriptor, value: CapabilityValue, failed: Bool, style: LevelStyle) {
        let displayID = display.connection.displayID
        let model = models[displayID] ?? OverlayModel()
        models[displayID] = model
        model.show(display: display, capability: capability, value: value, failed: failed, style: style)
        guard presentsPanels() else { return }

        let panel = panels[displayID] ?? makePanel(model: model)
        panels[displayID] = panel
        let size = OverlayView.size(boxes: model.showsBoxes)
        if panel.frame.size != size {
            panel.setContentSize(size)
            panel.invalidateShadow()
        }
        position(panel, displayID: displayID, boxes: model.showsBoxes)
        if panel.alphaValue < 1 {
            // Takes over from a fade already under way.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().alphaValue = 1
            }
        }
        if !panel.isVisible { panel.orderFrontRegardless() }

        dismissTasks[displayID]?.cancel()
        dismissTasks[displayID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(GlowTokens.Motion.overlayLinger))
            guard !Task.isCancelled else { return }
            self?.dismiss(panel, displayID: displayID)
        }
    }

    private func dismiss(_ panel: NSPanel, displayID: UInt32) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            return
        }
        let task = dismissTasks[displayID]
        NSAnimationContext.runAnimationGroup { context in
            context.duration = GlowTokens.Motion.overlayFade
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A change during the fade brought the panel back; leave it up.
                guard self?.dismissTasks[displayID] == task else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        }
    }

    private func makePanel(model: OverlayModel) -> NSPanel {
        let size = OverlayView.size(boxes: model.showsBoxes)
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        return panel
    }

    private func position(_ panel: NSPanel, displayID: UInt32, boxes: Bool) {
        let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let inset = boxes ? GlowTokens.Size.overlayHUDInset : GlowTokens.Size.overlayInset
        panel.setFrameOrigin(.init(x: frame.midX - panel.frame.width / 2, y: frame.minY + inset))
    }
}
