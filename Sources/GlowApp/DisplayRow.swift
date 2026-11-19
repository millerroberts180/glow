import SwiftUI

/// One display on Glow Desk: its name, how Glow controls it, and its brightness, with volume
/// only when the display has it. Everything else is in Settings › Displays; the row's context
/// menu goes straight there.
struct DisplayRow: View {
    let display: DisplaySnapshot
    let store: GlowStore
    var isPaused = false
    let showSettings: () -> Void

    var body: some View {
        // The pause notice above the rows says why the levels are dimmed, once.
        let status = display.summaryStatus(isPaused: false)
        let levels = levels
        VStack(alignment: .leading, spacing: GlowTokens.Space.s1_5) {
            HStack(alignment: .firstTextBaseline, spacing: GlowTokens.Space.s2) {
                Text(display.name)
                    .font(GlowTokens.Typography.rowTitle)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if case .route = status, let changed = levels.first(where: { $0.changedOnDisplayAt != nil }) {
                    // For a minute after a reread finds a level changed outside Glow, that's
                    // the news; a failure still says so instead.
                    ChangedOnDisplayMark(title: changed.changeMarkTitle, separated: false)
                        .lineLimit(1)
                        .fixedSize()
                } else {
                    // Quiet unless it changes what the slider means: software dimming, or a failure.
                    Text(status.label)
                        .font(GlowTokens.Typography.caption)
                        .foregroundStyle(status == .route(.hardware) ? StatusTone.neutral.text : status.tone.text)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .accessibilityElement(children: .combine)
            ForEach(levels) { descriptor in
                LevelSlider(display: display, descriptor: descriptor, isPaused: isPaused, style: store.levelStyle) {
                    store.update(displayID: display.id, capabilityID: descriptor.id, proposed: $0)
                }
            }
            if status == .route(.software) {
                Text("Dims the picture, not the backlight.")
                    .font(GlowTokens.Typography.caption)
                    .foregroundStyle(GlowTokens.Text.secondary)
                    .padding(.leading, GlowTokens.Size.sliderSymbol + GlowTokens.Space.s2)
            } else if levels.isEmpty, status != .route(.unavailable), status != .checking {
                Text("No everyday controls on this connection")
                    .font(GlowTokens.Typography.caption)
                    .foregroundStyle(GlowTokens.Text.secondary)
            }
        }
        .contextMenu {
            Button("Display Settings…", action: showSettings)
        }
    }

    /// Brightness whenever the connection can set it, dimmed until it's safe to; volume only
    /// when it can be changed.
    private var levels: [CapabilityDescriptor] {
        display.capabilities.filter { descriptor in
            guard descriptor.presentation == .osd, case .range = descriptor.kind else { return false }
            switch descriptor.id {
            case .brightness: return descriptor.route != .unavailable && descriptor.access != .unavailable
            case .volume: return descriptor.isSafelyEditable
            default: return false
            }
        }
        .sorted { $0.id == .brightness && $1.id != .brightness }
    }
}

/// Brightness or volume on a popover row: its symbol, the slider or the boxes the person
/// chose, and the value in tabular figures so the column lines up.
private struct LevelSlider: View {
    let display: DisplaySnapshot
    let descriptor: CapabilityDescriptor
    let isPaused: Bool
    var style: LevelStyle = .slider
    let propose: (CapabilityValue) -> Void

    var body: some View {
        if case let .range(minimum, maximum, step) = descriptor.kind {
            let label = "\(display.name), \(descriptor.label.lowercased())"
            let spoken = "\(descriptor.spokenValue), \(ControlStatus(descriptor: descriptor, isPaused: isPaused).state.label.lowercased())"
            HStack(spacing: GlowTokens.Space.s2) {
                Image(systemName: descriptor.id == .volume ? "speaker.wave.2" : "sun.max")
                    .font(GlowTokens.Typography.caption)
                    .foregroundStyle(GlowTokens.Text.secondary)
                    .frame(width: GlowTokens.Size.sliderSymbol)
                    .accessibilityHidden(true)
                switch style {
                case .slider:
                    Slider(value: descriptor.sliderValue(minimum: minimum, step: step, propose: propose), in: minimum...maximum)
                        .controlSize(.small)
                        .disabled(isPaused || !descriptor.isSafelyEditable)
                        .accessibilityLabel(label)
                        .accessibilityValue(spoken)
                case .boxes:
                    LevelBoxes(
                        scale: LevelBoxScale(minimum: minimum, maximum: maximum, step: step),
                        value: { if case .number(let value) = descriptor.currentValue { value } else { nil } }(),
                        label: label,
                        spokenValue: spoken,
                        propose: { propose(.number($0)) }
                    )
                    .disabled(isPaused || !descriptor.isSafelyEditable)
                }
                Text(descriptor.currentValue.map { "\($0.description)\(descriptor.unit ?? "")" } ?? "–")
                    .font(GlowTokens.Typography.percent)
                    .foregroundStyle(descriptor.freshness == .stale ? GlowTokens.Status.dangerText : GlowTokens.Text.secondary)
                    .frame(width: GlowTokens.Size.percentWidth, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }
}
