import SwiftUI

/// The calibration window's steps: choose the reference and method, compare at each
/// point, check the curves, save.
struct MatchCalibrationView: View {
    @Bindable var session: MatchSession

    var body: some View {
        VStack(spacing: 0) {
            header
            Form { content }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            Divider()
            MatchFooter(session: session)
        }
        .frame(width: MatchWindowController.size.width, height: MatchWindowController.size.height)
        .background(GlowTokens.Surface.canvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: GlowTokens.Space.s1) {
            Text(title).font(GlowTokens.Typography.title3)
            Text(subtitle)
                .font(GlowTokens.Typography.callout)
                .foregroundStyle(GlowTokens.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, GlowTokens.Space.s6)
        // Clear of the transparent title bar.
        .padding(.top, 34)
        .accessibilityElement(children: .combine)
    }

    private var referenceName: String { session.reference?.name ?? "the reference" }

    private var title: String {
        switch session.step {
        case .intro: "Match Displays"
        case .compare(let index): session.method == .quick ? "Match the grey" : "Point \(index + 1) of \(session.levels.count)"
        case .review: "Check and save"
        case .settling: "One moment"
        case .finished: "Something didn’t go back"
        }
    }

    private var subtitle: String {
        switch session.step {
        case .intro:
            "A grey patch fills each display. You set each one to look as bright as the reference, and Glow keeps them together after."
        case .compare(let index):
            session.method == .quick
                ? "Set each display so its grey looks as bright as \(referenceName)’s. Look at each in turn, not side by side."
                : "\(referenceName) is at \(matchValueText(session.referenceValue(at: index), of: session.reference)). Set each display so its grey looks as bright."
        case .review:
            "Each display will follow \(referenceName) along its curve."
        case .settling:
            "Setting your displays’ brightness…"
        case .finished:
            session.problem ?? ""
        }
    }

    @ViewBuilder private var content: some View {
        switch session.step {
        case .intro: MatchIntro(session: session)
        case .compare: MatchCompare(session: session)
        case .review: MatchReview(session: session)
        case .settling:
            Section {
                HStack(spacing: GlowTokens.Space.s2) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for each display to confirm its brightness.")
                        .foregroundStyle(GlowTokens.Text.secondary)
                }
            }
        case .finished:
            Section {
                StatusLabel(title: session.problem ?? "Done.", systemImage: "exclamationmark.triangle.fill", tone: .warning)
            }
        }
    }
}

/// A brightness value as the display's own controls show it.
@MainActor func matchValueText(_ value: Double?, of display: DisplaySnapshot?) -> String {
    guard let value else { return "—" }
    return "\(CapabilityValue.number(value).description)\(display?.brightnessSetting?.unit ?? "")"
}

private struct MatchIntro: View {
    @Bindable var session: MatchSession

    var body: some View {
        Section {
            LabeledContent {
                MenuPicker(
                    label: "Reference",
                    options: session.candidates.map { .init(value: $0.id, title: $0.name) },
                    selection: $session.referenceID
                )
            } label: {
                DetailLabel(title: "Reference", detail: "The others are set to look like it.")
            }
            .disabled(session.candidates.count < 2)
        }

        Section("Method") {
            VStack(alignment: .leading, spacing: GlowTokens.Space.s2) {
                VisualChoice(
                    options: MatchMethod.allCases.map { .init(value: $0, title: $0.title) },
                    selection: $session.method,
                    artHeight: 52
                ) { method, selected in
                    MatchMethodArt(method: method, highlighted: selected)
                }
                Text(session.method.detail)
                    .font(GlowTokens.Typography.caption)
                    .foregroundStyle(GlowTokens.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, GlowTokens.Space.s0_5)
        }

        Section {
            if let reason = session.unavailableReason ?? session.startProblem {
                StatusLabel(title: reason, systemImage: "exclamationmark.circle", tone: .warning)
            }
            ForEach(session.candidates.filter { $0.brightnessRoute == .software }) { display in
                note("\(display.name) uses software dimming, so matching dims its picture, not its backlight.", symbol: "circle.lefthalf.filled")
            }
            if session.candidates.contains(where: \.isBuiltIn), !session.store.isDemoData {
                note("If your Mac adjusts its brightness automatically, the built-in display may drift while you match. You can turn that off in System Settings › Displays.", symbol: "sun.max")
            }
            note("This lines up how bright your displays look. It doesn’t match their color.", symbol: "eye")
        }
    }

    private func note(_ text: String, symbol: String) -> some View {
        Label {
            Text(text)
                .font(GlowTokens.Typography.caption)
                .foregroundStyle(GlowTokens.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(GlowTokens.Text.secondary)
        }
    }
}

/// One comparison: the reference, the stand-in patches when there are no screens, and a
/// slider for each display being matched. The calibration window shows it, and setup
/// shows it inside its own window, as sections of a grouped form.
struct MatchCompare: View {
    let session: MatchSession

    var body: some View {
        if let pause = session.store.pauseReason {
            Section { PauseNotice(reason: pause) }
        }
        Section {
            if let reference = session.reference {
                LabeledContent {
                    Text(matchValueText(session.value(of: reference.id), of: reference))
                        .monospacedDigit()
                        .foregroundStyle(GlowTokens.Text.secondary)
                } label: {
                    DetailLabel(title: reference.name, detail: "Reference. Its grey is the one to match.")
                }
            }
            if !session.patches.showsOnScreens {
                MatchPatchStrip(session: session)
            }
        }
        Section {
            ForEach(session.adjustable) { display in
                MatchSliderRow(session: session, display: display)
            }
            if let problem = session.problem {
                StatusLabel(title: problem, systemImage: "exclamationmark.triangle.fill", tone: .warning)
            }
        } header: {
            Text("Adjust")
        } footer: {
            FooterNote("← → change the highlighted display, with Shift for bigger steps. ↑ ↓ choose another.")
        }
    }
}

private struct MatchSliderRow: View {
    let session: MatchSession
    let display: DisplaySnapshot

    var body: some View {
        let selected = session.adjustingID == display.id
        HStack(spacing: GlowTokens.Space.s2) {
            Capsule()
                .fill(selected ? GlowTokens.Accent.primary : Color.clear)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: GlowTokens.Space.s1) {
                HStack {
                    Text(display.name)
                    Spacer()
                    Text(matchValueText(session.value(of: display.id), of: display))
                        .monospacedDigit()
                        .foregroundStyle(GlowTokens.Text.secondary)
                }
                if let bounds = session.bounds(of: display.id), bounds.lowerBound < bounds.upperBound {
                    Slider(value: Binding(
                        get: { session.value(of: display.id) ?? bounds.lowerBound },
                        set: { session.set(display.id, to: $0) }
                    ), in: bounds)
                    .labelsHidden()
                    .accessibilityLabel("\(display.name) brightness")
                } else {
                    Text("At its brightest already, so it stays here.")
                        .font(GlowTokens.Typography.caption)
                        .foregroundStyle(GlowTokens.Text.secondary)
                }
                if display.brightnessRoute == .software {
                    Text("Software dimming: this dims the picture, not the backlight.")
                        .font(GlowTokens.Typography.caption)
                        .foregroundStyle(GlowTokens.Text.secondary)
                }
            }
        }
        .padding(.vertical, GlowTokens.Space.s0_5)
        .contentShape(Rectangle())
        .onTapGesture { session.adjustingID = display.id }
    }
}

/// Demo displays have no screens, so the window draws each one's patch, lit by its level.
private struct MatchPatchStrip: View {
    let session: MatchSession

    var body: some View {
        VStack(alignment: .leading, spacing: GlowTokens.Space.s1_5) {
            HStack(spacing: GlowTokens.Space.s2) {
                ForEach(session.members.compactMap(session.display)) { display in
                    let level = session.value(of: display.id).flatMap { display.brightnessSetting?.matchLevel(of: $0) } ?? 0
                    VStack(spacing: GlowTokens.Space.s1) {
                        RoundedRectangle(cornerRadius: GlowTokens.Radius.control, style: .continuous)
                            .fill(Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: GlowTokens.Radius.control, style: .continuous)
                                    .fill(MatchPatchView.grey.opacity(0.15 + 0.85 * level))
                            )
                            .frame(height: 40)
                        Text(display.name)
                            .font(GlowTokens.Typography.tileTitle)
                            .foregroundStyle(GlowTokens.Text.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Text("Demo displays have no screens, so these tiles stand in for the grey patches.")
                .font(GlowTokens.Typography.caption)
                .foregroundStyle(GlowTokens.Text.secondary)
        }
        .accessibilityHidden(true)
    }
}

private struct MatchReview: View {
    let session: MatchSession

    var body: some View {
        Section {
            ForEach(session.calibrations, id: \.pair) { calibration in
                if let display = session.display(calibration.pair.display) {
                    HStack(spacing: GlowTokens.Space.s3) {
                        MatchCurveArt(curve: calibration.curve)
                            .frame(width: 84, height: 52)
                        DetailLabel(title: display.name, detail: summary(of: calibration, display: display))
                    }
                    .padding(.vertical, GlowTokens.Space.s0_5)
                }
            }
            if let problem = session.problem {
                StatusLabel(title: problem, systemImage: "exclamationmark.triangle.fill", tone: .warning)
            }
        } footer: {
            FooterNote("When the brightness keys change every display, matched displays follow these curves. Each display’s own slider still sets it alone. Saving puts \(session.reference?.name ?? "the reference") back where it was.")
        }
    }

    private func summary(of calibration: MatchCalibration, display: DisplaySnapshot) -> String {
        switch calibration.method {
        case .quick:
            "With \(session.reference?.name ?? "the reference") at \(matchValueText(session.referenceValue(at: 0), of: session.reference)), it looked the same at \(matchValueText(session.value(of: display.id), of: display)). The rest follows in proportion."
        case .guided:
            "\(calibration.curve.points.count - 1) comparison points, from dim to full."
        }
    }
}

private struct MatchFooter: View {
    let session: MatchSession
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: GlowTokens.Space.s2) {
            if session.method == .guided, let index = session.pointIndex {
                HStack(spacing: GlowTokens.Space.s1_5) {
                    ForEach(session.levels.indices, id: \.self) { point in
                        Circle()
                            .fill(point == index ? GlowTokens.Accent.primary : (contrast == .increased ? GlowTokens.Text.secondary : GlowTokens.Text.tertiary))
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Point \(index + 1) of \(session.levels.count)")
            }
            Spacer()
            switch session.step {
            case .finished:
                Button("Close") { session.close() }
                    .keyboardShortcut(.defaultAction)
            default:
                Button("Cancel") { Task { await session.cancel() } }
                    .keyboardShortcut(.cancelAction)
                    .disabled(session.step == .settling)
                if canGoBack {
                    Button("Back") { session.back() }
                }
                Button(primaryTitle) { primary() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canGoOn)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, GlowTokens.Space.s5)
        .padding(.vertical, 14)
    }

    private var canGoBack: Bool {
        switch session.step {
        case .compare(let index): index > 0
        case .review: true
        default: false
        }
    }

    private var canGoOn: Bool {
        switch session.step {
        case .intro: session.canStart
        case .compare, .review: true
        default: false
        }
    }

    private var primaryTitle: String {
        switch session.step {
        case .intro: "Start"
        case .compare(let index): index + 1 < session.levels.count ? "Next" : "Review"
        default: "Save Match"
        }
    }

    private func primary() {
        if session.step == .review {
            Task { await session.save() }
        } else {
            session.next()
        }
    }
}
