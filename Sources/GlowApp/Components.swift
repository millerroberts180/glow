import SwiftUI

/// The single way Glow says how a setting is controlled and whether it can be trusted.
/// Icon, words and colour always travel together.
struct ControlStatus: View {
    enum State: Equatable {
        case route(ControlRoute)
        /// Listed by the display but not yet confirmed by a read.
        case untested
        /// Listed by the display, then refused or contradicted.
        case contradicted
        /// The last change didn't take.
        case failed
        /// Writes are paused while displays sleep or reconnect.
        case paused
        /// Discovery is still asking the display what it supports.
        case checking

        var label: String {
            switch self {
            case .route(let route): route.userLabel
            case .untested: SupportEvidence.reportedOnly.rawValue
            case .contradicted: SupportEvidence.contradictory.rawValue
            case .failed: "Couldn’t update this display"
            // The pause notice above the controls says why.
            case .paused: "Paused"
            case .checking: "Checking connection…"
            }
        }

        var symbol: String {
            switch self {
            case .route(.native): "macbook"
            case .route(.hardware): "checkmark.circle.fill"
            case .route(.software): "circle.lefthalf.filled"
            case .route(.unavailable): "minus.circle"
            case .untested: "questionmark.circle"
            case .contradicted: "exclamationmark.circle"
            case .failed: "exclamationmark.triangle.fill"
            case .paused: "pause.circle"
            case .checking: "ellipsis.circle"
            }
        }

        var tone: StatusTone {
            switch self {
            case .route(.hardware): .success
            case .route(.software): .warning
            case .failed: .danger
            case .contradicted: .warning
            default: .neutral
            }
        }
    }

    let state: State

    init(state: State) { self.state = state }

    /// Derives the state from a descriptor so every surface tells the same story.
    init(descriptor: CapabilityDescriptor, isPaused: Bool = false) {
        if isPaused, descriptor.isSafelyEditable {
            state = .paused
        } else if descriptor.freshness == .stale, descriptor.reliability.lastFailure != nil {
            state = .failed
        } else if descriptor.route == .unavailable || descriptor.access == .unavailable {
            state = .route(.unavailable)
        } else if descriptor.evidence == .reportedOnly {
            state = .untested
        } else if descriptor.evidence == .contradictory {
            state = .contradicted
        } else {
            state = .route(descriptor.route)
        }
    }

    var body: some View {
        StatusLabel(title: state.label, systemImage: state.symbol, tone: state.tone)
            .labelStyle(.titleAndIcon)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.label)
    }
}

/// The colour family of a status. Green is for status only, never a clickable button.
enum StatusTone {
    case neutral, success, warning, danger

    var symbol: Color {
        switch self {
        case .neutral: GlowTokens.Text.secondary
        case .success: GlowTokens.Status.success
        case .warning: GlowTokens.Status.warning
        case .danger: GlowTokens.Status.danger
        }
    }

    var text: Color {
        switch self {
        case .neutral: GlowTokens.Text.secondary
        case .success: GlowTokens.Status.successText
        case .warning: GlowTokens.Status.warningText
        case .danger: GlowTokens.Status.dangerText
        }
    }
}

/// A status in caption size: the symbol in the tone's hue, the words in a deeper shade
/// that stays readable.
struct StatusLabel: View {
    let title: String
    let systemImage: String
    var tone: StatusTone = .neutral

    var body: some View {
        Label {
            Text(title).foregroundStyle(tone.text)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tone.symbol)
        }
        .font(GlowTokens.Typography.caption)
    }
}

extension DisplaySnapshot {
    /// The display's headline status for its card or tile: how its brightness is controlled,
    /// told by the same component as every setting.
    @MainActor func summaryStatus(isPaused: Bool) -> ControlStatus.State {
        if isChecking { return isPaused ? .paused : .checking }
        if let brightness = capabilities.first(where: { $0.id == .brightness }) {
            return ControlStatus(descriptor: brightness, isPaused: isPaused).state
        }
        return isPaused ? .paused : .route(primaryRoute)
    }

    /// Brightness from 0 to 1, for drawing the display lit; nil without a reading.
    var brightnessLevel: Double? {
        guard let brightness = capabilities.first(where: { $0.id == .brightness }),
              case let .number(value) = brightness.currentValue,
              case let .range(minimum, maximum, _) = brightness.kind, maximum > minimum else { return nil }
        return (value - minimum) / (maximum - minimum)
    }

    /// One plain sentence on what this connection allows, for the foot of the Digital OSD.
    /// The transport is quoted as discovery names it ("USB-C through dock"), never recased.
    var connectionSummary: String {
        if isChecking { return "Connection: \(connection.transport). Glow is asking the display what it supports." }
        return switch primaryRoute {
        case .native: "macOS controls this display directly, so Glow uses Apple’s own brightness control."
        case .hardware: "Connection: \(connection.transport). Glow changes the display’s own settings, the way its buttons do."
        case .software: "Connection: \(connection.transport). It doesn’t pass display commands, so Glow dims the picture itself."
        case .unavailable: "Connection: \(connection.transport). Glow can’t change this display over it."
        }
    }
}

extension CapabilityDescriptor {
    /// The value as VoiceOver should say it: "68 percent", or "No reading yet".
    var spokenValue: String {
        guard let currentValue else { return "No reading yet" }
        return switch unit {
        case "%": "\(currentValue.description) percent"
        case let unit?: "\(currentValue.description) \(unit)"
        case nil: currentValue.description
        }
    }
}

struct CapabilityValueText: View {
    let descriptor: CapabilityDescriptor
    var body: some View {
        HStack(spacing: GlowTokens.Space.s1) {
            if descriptor.pendingValue != nil { ProgressView().controlSize(.mini).accessibilityLabel("Updating") }
            Text(descriptor.currentValue.map { "\($0.description)\(descriptor.unit ?? "")" } ?? "No reading yet")
                .monospacedDigit()
                .foregroundStyle(descriptor.freshness == .stale ? GlowTokens.Status.dangerText : GlowTokens.Text.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current value")
        .accessibilityValue(descriptor.spokenValue)
    }
}

/// The control a descriptor asks for, chosen by `CapabilityRenderer` from its schema and
/// never from which setting it is. Every change goes to `propose`, which decides whether
/// it needs a confirmation first.
struct CapabilityControl: View {
    let display: DisplaySnapshot
    let descriptor: CapabilityDescriptor
    var isPaused = false
    let propose: (CapabilityValue) -> Void

    var body: some View {
        control
            .accessibilityLabel("\(display.name), \(descriptor.label.lowercased())")
            .accessibilityValue("\(descriptor.spokenValue), \(ControlStatus(descriptor: descriptor, isPaused: isPaused).state.label.lowercased())")
    }

    @ViewBuilder private var control: some View {
        switch CapabilityRenderer.style(for: descriptor) {
        case .slider:
            if case let .range(minimum, maximum, step) = descriptor.kind {
                HStack(spacing: GlowTokens.Space.s2) {
                    Slider(value: descriptor.sliderValue(minimum: minimum, step: step, propose: propose), in: minimum...maximum)
                        .controlSize(.small)
                        .frame(width: GlowTokens.Size.osdSliderWidth)
                    CapabilityValueText(descriptor: descriptor)
                        .font(GlowTokens.Typography.callout)
                        .frame(minWidth: GlowTokens.Size.valueWidth, alignment: .trailing)
                        .accessibilityHidden(true)
                }
            }
        case .picker:
            if case .options(let options) = descriptor.kind {
                // Without a reading the menu says so, rather than showing the first option.
                MenuPicker(
                    label: descriptor.label,
                    options: options.map { .init(value: $0, title: $0) },
                    selection: Binding<String?>(
                        get: { if case .text(let value) = descriptor.currentValue { value } else { nil } },
                        set: { if let value = $0 { propose(.text(value)) } }
                    ),
                    placeholder: "No reading yet"
                )
            }
        case .toggle:
            // A switch has to look on or off, so without a reading it shows none instead.
            if case .boolean(let isOn) = descriptor.currentValue {
                Toggle(descriptor.label, isOn: Binding(get: { isOn }, set: { propose(.boolean($0)) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            } else {
                CapabilityValueText(descriptor: descriptor)
            }
        case .button:
            Button {
                propose(descriptor.currentValue ?? .boolean(true))
            } label: {
                ActionLabel(title: "Run", symbol: "play.fill")
            }
            .buttonStyle(ActionButtonStyle(compact: true))
        case .readOnly:
            CapabilityValueText(descriptor: descriptor)
        case .unavailable:
            // The status line already says it isn't available; "No reading yet" would
            // suggest one is coming.
            EmptyView()
        }
    }
}

/// How a setting is controlled and how Glow knows: the status, then the evidence when it
/// adds something the status doesn't already say.
struct CapabilityStatusLine: View {
    let descriptor: CapabilityDescriptor
    var isPaused = false

    var body: some View {
        let status = ControlStatus(descriptor: descriptor, isPaused: isPaused)
        HStack(spacing: GlowTokens.Space.s1) {
            status
            // For a minute after a reread finds it changed outside Glow, that's the news.
            if descriptor.changedOnDisplayAt != nil {
                ChangedOnDisplayMark(title: descriptor.changeMarkTitle)
            } else if descriptor.evidence != .unavailable, descriptor.evidence.rawValue != status.state.label {
                // "Not available" would only repeat an unavailable status.
                Text("· \(descriptor.evidence.rawValue)")
                    .font(GlowTokens.Typography.caption)
                    .foregroundStyle(GlowTokens.Text.secondary)
            }
        }
        .lineLimit(1)
    }
}

/// One Digital OSD row: the setting's name over its status, and its control or value on
/// the right.
struct OSDRow: View {
    let display: DisplaySnapshot
    let descriptor: CapabilityDescriptor
    var isPaused = false
    /// Hides the setting on this display, for one that does nothing there; nil when it can't be hidden.
    var onHide: (() -> Void)? = nil
    let propose: (CapabilityValue) -> Void

    var body: some View {
        LabeledContent {
            CapabilityControl(display: display, descriptor: descriptor, isPaused: isPaused, propose: propose)
                // Writes fail while displays reconnect; the control stays put and says why.
                .disabled(isPaused)
        } label: {
            VStack(alignment: .leading, spacing: GlowTokens.Space.s0_5) {
                Text(descriptor.label)
                CapabilityStatusLine(descriptor: descriptor, isPaused: isPaused)
            }
        }
        .contextMenu {
            if let onHide {
                Button("Hide on This Display", systemImage: "eye.slash", action: onHide)
            }
        }
        .accessibilityActions {
            if let onHide {
                Button("Hide on This Display", action: onHide)
            }
        }
    }
}

/// "Changed on the display": a reread found this setting changed outside Glow a moment ago.
/// `separated` leads with the dot that follows a status in a line; the popover's row header
/// shows the mark on its own.
struct ChangedOnDisplayMark: View {
    let title: String
    var separated = true

    var body: some View {
        HStack(spacing: GlowTokens.Space.s1) {
            if separated { Text("·").foregroundStyle(GlowTokens.Text.secondary) }
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(GlowTokens.Accent.primary)
            Text(title).foregroundStyle(GlowTokens.Text.secondary)
        }
        .font(GlowTokens.Typography.caption)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

/// A change that needs a yes first, because the display may go blank or turn off. Names
/// the display and the consequence; cancelling leaves the value as it was.
struct PendingChange: Identifiable {
    let id = UUID()
    let display: DisplaySnapshot
    let descriptor: CapabilityDescriptor
    let value: CapabilityValue

    var title: String {
        if case .action = descriptor.kind { return "\(descriptor.label) on your \(display.name)?" }
        return descriptor.risk == .destructive
            ? "Change \(descriptor.label.lowercased()) on your \(display.name)?"
            : "Switch your \(display.name) to \(value.description)?"
    }

    var message: String {
        descriptor.risk == .destructive
            ? "Your \(display.name) may turn off or lose its settings, and Glow may not be able to undo it. Use the display’s own buttons to recover."
            : "Your \(display.name) may go blank until it finds a signal on \(value.description). If nothing appears, switch back with the display’s own buttons."
    }

    var confirmTitle: String {
        if case .action = descriptor.kind { return descriptor.label }
        return descriptor.risk == .destructive ? "Change \(descriptor.label)" : "Switch to \(value.description)"
    }
}

extension View {
    /// Asks before a change that needs confirming. `onCancel` runs when the answer is no.
    func confirmingChange(_ pending: Binding<PendingChange?>, confirm: @escaping (PendingChange) -> Void, onCancel: @escaping () -> Void) -> some View {
        confirmationDialog(
            pending.wrappedValue?.title ?? "",
            isPresented: Binding(get: { pending.wrappedValue != nil }, set: { if !$0 { pending.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: pending.wrappedValue
        ) { change in
            Button(change.confirmTitle, role: change.descriptor.risk == .destructive ? .destructive : nil) { confirm(change) }
            Button("Cancel", role: .cancel) { onCancel() }
        } message: { change in
            Text(change.message)
        }
    }
}

/// Writes are paused while displays sleep or reconnect. Said calmly: nothing is wrong.
struct PauseNotice: View {
    let reason: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: GlowTokens.Space.s0_5) {
                Text(reason).foregroundStyle(GlowTokens.Text.primary)
                Text("Controls come back once your displays settle.")
                    .font(GlowTokens.Typography.caption)
                    .foregroundStyle(GlowTokens.Text.secondary)
            }
        } icon: {
            Image(systemName: "pause.circle")
                .foregroundStyle(GlowTokens.Text.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Glow was opened with Shift held, so it reads displays and changes nothing.
struct SafeModeNotice: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: GlowTokens.Space.s0_5) {
                Text("Safe mode").foregroundStyle(GlowTokens.Text.primary)
                Text("Glow opened with Shift held, so it’s reading your displays without changing them. Quit and reopen Glow to make changes.")
                    .font(GlowTokens.Typography.caption)
                    .foregroundStyle(GlowTokens.Text.secondary)
            }
        } icon: {
            Image(systemName: "lock.shield")
                .foregroundStyle(GlowTokens.Text.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

extension CapabilityDescriptor {
    /// A slider position that lands on the setting's steps. The slider itself gets no
    /// `step:`, which would draw a tick mark for every one of them.
    @MainActor func sliderValue(minimum: Double, step: Double, propose: @escaping (CapabilityValue) -> Void) -> Binding<Double> {
        Binding(
            get: { if case .number(let value) = currentValue { value } else { minimum } },
            set: { position in
                let value = step > 0 ? minimum + ((position - minimum) / step).rounded() * step : position
                if currentValue != .number(value) { propose(.number(value)) }
            }
        )
    }
}
