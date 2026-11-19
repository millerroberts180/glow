import SwiftUI

/// Your displays: each one Glow found, how it sets that display's brightness in plain
/// words, and a slider that sets it now.
struct DisplaysStep: View {
    let model: SetupModel

    var body: some View {
        let desk = model.deskOverride ?? YourDesk(store: model.store)
        VStack(alignment: .leading, spacing: 0) {
            SetupTitle("Your displays", detail(desk))
            switch desk.state {
            case .reading:
                HStack(spacing: GlowTokens.Space.s2) {
                    ProgressView().controlSize(.small)
                    Text("Looking for your displays…")
                        .foregroundStyle(GlowTokens.Text.secondary)
                }
                .padding(.vertical, GlowTokens.Space.s3)
            case .none:
                SetupNote(symbol: "display", text: "No displays found yet. Connect one, and it shows up here.")
            case .demo, .builtInOnly, .ready:
                VStack(spacing: GlowTokens.Space.s2) {
                    ForEach(desk.displays) { display in
                        SetupDisplayRow(display: display, store: model.store, isPaused: desk.isPaused)
                    }
                }
            }
            VStack(alignment: .leading, spacing: GlowTokens.Space.s2) {
                if desk.isPaused {
                    SetupNote(symbol: "pause.circle", text: ControlError.suspended.errorDescription ?? "")
                }
                if desk.state == .demo {
                    SetupNote(symbol: "sparkles.rectangle.stack", text: "These are Glow’s demo displays, not yours. Turn off Use demo displays in Settings › General to see your own.")
                }
                if !desk.displays.isEmpty {
                    FooterNote("The same sliders are a click away on Glow’s mark in the menu bar.")
                }
            }
            .padding(.top, GlowTokens.Space.s4)
        }
    }

    private func detail(_ desk: YourDesk) -> String {
        switch desk.displays.count {
        case 0: "Glow looks for every display connected to your Mac."
        case 1: "Glow found one display. Its slider sets the brightness right now."
        default: "Glow found \(desk.displays.count) displays. Each slider sets that display’s brightness right now."
        }
    }
}

/// One display in setup: drawn as bright as it is, how Glow sets its brightness, and a
/// slider for it.
struct SetupDisplayRow: View {
    let display: DisplaySnapshot
    let store: GlowStore
    var isPaused = false

    var body: some View {
        let status = display.summaryStatus(isPaused: isPaused)
        let shape = RoundedRectangle(cornerRadius: GlowTokens.Radius.tile, style: .continuous)
        HStack(alignment: .center, spacing: GlowTokens.Space.s3) {
            DisplayGlyph(isBuiltIn: display.isBuiltIn, level: display.brightnessLevel)
                .frame(width: 56, height: 40)
            VStack(alignment: .leading, spacing: GlowTokens.Space.s1) {
                HStack(alignment: .firstTextBaseline, spacing: GlowTokens.Space.s2) {
                    Text(display.name)
                        .font(GlowTokens.Typography.cardTitle)
                        .lineLimit(1)
                    Spacer(minLength: GlowTokens.Space.s2)
                    ControlStatus(state: status)
                        .font(GlowTokens.Typography.caption)
                        .fixedSize()
                }
                Text(Self.howGlowSetsIt(status))
                    .font(GlowTokens.Typography.caption)
                    .foregroundStyle(GlowTokens.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                SetupBrightnessSlider(display: display, store: store, isPaused: isPaused)
            }
        }
        .padding(GlowTokens.Space.s3)
        .background(shape.fill(GlowTokens.Surface.tile))
        .overlay(shape.strokeBorder(GlowTokens.Border.tile))
    }

    /// How Glow sets this display's brightness, in a sentence anyone can follow.
    static func howGlowSetsIt(_ state: ControlStatus.State) -> String {
        switch state {
        case .route(.native): "Glow sets it through macOS, the same way the brightness keys do."
        case .route(.hardware): "Glow changes the display’s own brightness, as its buttons do."
        case .route(.software): "Glow dims the picture, since this connection can’t reach the display’s own brightness."
        case .route(.unavailable): "Glow can’t change this display’s brightness over this connection."
        case .untested: "The display lists a brightness setting but hasn’t answered for it yet, so Glow leaves it alone."
        case .contradicted: "The display lists a brightness setting but didn’t answer as expected, so Glow leaves it alone."
        case .failed: "Its last change didn’t take. Try the slider again."
        case .paused: "Paused while your displays sleep or reconnect."
        case .checking: "Glow is still asking this display what it supports."
        }
    }
}

/// A display's brightness in setup: the sun, the slider and the value. It writes through
/// the store, as the popover's slider does.
struct SetupBrightnessSlider: View {
    let display: DisplaySnapshot
    let store: GlowStore
    var isPaused = false

    var body: some View {
        if let descriptor = display.brightnessSetting, case let .range(minimum, maximum, step) = descriptor.kind,
           descriptor.route != .unavailable, descriptor.access != .unavailable {
            HStack(spacing: GlowTokens.Space.s2) {
                Image(systemName: "sun.max")
                    .font(GlowTokens.Typography.caption)
                    .foregroundStyle(GlowTokens.Text.secondary)
                    .frame(width: GlowTokens.Size.sliderSymbol)
                    .accessibilityHidden(true)
                Slider(value: descriptor.sliderValue(minimum: minimum, step: step) {
                    store.update(displayID: display.id, capabilityID: .brightness, proposed: $0)
                }, in: minimum...maximum)
                .controlSize(.small)
                .disabled(isPaused || !descriptor.isSafelyEditable)
                .accessibilityLabel("\(display.name), brightness")
                .accessibilityValue(descriptor.spokenValue)
                Text(descriptor.currentValue.map { "\($0.description)\(descriptor.unit ?? "")" } ?? "–")
                    .font(GlowTokens.Typography.percent)
                    .foregroundStyle(GlowTokens.Text.secondary)
                    .frame(width: GlowTokens.Size.percentWidth, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }
}
