import SwiftUI

/// Matching their brightness with Quick Match: choose the reference, set the others until
/// their grey looks the same, and save. With one display, setting its brightness instead.
struct MatchStep: View {
    let model: SetupModel

    var body: some View {
        let stage = model.matchStage
        Group {
            switch stage {
            case .single:
                SingleDisplay(model: model).setupPage()
            case .unavailable(let reason):
                VStack(alignment: .leading, spacing: GlowTokens.Space.s3) {
                    SetupTitle("Match their brightness", "Matching sets your displays to look equally bright, and keeps them that way.")
                    StatusLabel(title: reason, systemImage: "exclamationmark.circle", tone: .warning)
                    SetupNote(symbol: "slider.horizontal.3", text: "You can match them later in Settings › Brightness Match.")
                }
                .setupPage()
            case .pick:
                if let match = model.match { MatchPick(session: match).setupPage() }
            case .adjust:
                if let match = model.match { MatchAdjust(model: model, session: match) }
            case .settling:
                VStack(alignment: .leading, spacing: 0) {
                    SetupTitle("One moment", "Setting your displays’ brightness…")
                    HStack(spacing: GlowTokens.Space.s2) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for each display to confirm its brightness.")
                            .foregroundStyle(GlowTokens.Text.secondary)
                    }
                }
                .setupPage()
            case .matched:
                if let match = model.match { MatchDone(model: model, store: model.store, session: match).setupPage() }
            case .problem(let message):
                VStack(alignment: .leading, spacing: GlowTokens.Space.s3) {
                    SetupTitle("Something didn’t go back", message)
                    Button {
                        model.startOver()
                    } label: {
                        ActionLabel(title: "Try Again", symbol: "arrow.counterclockwise")
                    }
                    .buttonStyle(ActionButtonStyle())
                }
                .setupPage()
            }
        }
        .id(stage)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.18), value: stage)
    }
}

/// One display, or one whose brightness Glow can set: its slider and the keys, and
/// matching for later.
private struct SingleDisplay: View {
    let model: SetupModel

    var body: some View {
        let store = model.store
        VStack(alignment: .leading, spacing: 0) {
            SetupTitle("Set your brightness", store.displays.isEmpty
                ? "Connect a display, and its brightness shows up here."
                : "Drag the slider until the screen looks right to you.")
            VStack(spacing: GlowTokens.Space.s2) {
                ForEach(store.displays) { display in
                    SetupDisplayRow(display: display, store: store, isPaused: store.pauseReason != nil)
                }
            }
            VStack(alignment: .leading, spacing: GlowTokens.Space.s2) {
                if let keys = keysLine {
                    SetupNote(symbol: "keyboard", text: keys)
                }
                SetupNote(symbol: "display.2", text: matchLine)
            }
            .padding(.top, GlowTokens.Space.s4)
        }
    }

    /// What the brightness keys do for the one display Glow can set.
    private var keysLine: String? {
        guard let display = model.store.matchCandidates.first else { return nil }
        if display.isBuiltIn { return "Your keyboard’s brightness keys change it too." }
        if model.store.controlTarget == .macOnly {
            return "The brightness keys are set to change only the Mac’s own display. You can change that in Settings › Controls."
        }
        if model.accessGranted { return "Your keyboard’s brightness keys change it too." }
        return model.tutorialOnly
            ? "For the brightness keys to change it too, allow Glow in Settings › Controls."
            : "For the brightness keys to change it too, allow Glow on the last step."
    }

    private var matchLine: String {
        if model.store.displays.count < 2 {
            return "Matching needs a second display. Connect one, then match them in Settings › Brightness Match."
        }
        let reason = model.match?.unavailableReason ?? ""
        return "\(reason) You can match them later in Settings › Brightness Match."
    }
}

/// Choosing the reference: the display that already looks right.
private struct MatchPick: View {
    @Bindable var session: MatchSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupTitle("Match their brightness", "At the same setting, displays can look brighter or dimmer than each other. Pick the one that looks right. Next, a grey patch fills each display, and you set the others to look the same.")
            VisualChoice(
                options: session.candidates.map { .init(value: Optional($0.id), title: $0.name) },
                selection: $session.referenceID,
                artHeight: GlowTokens.Size.displayArtHeight
            ) { id, selected in
                let display = id.flatMap(session.display)
                DisplayGlyph(isBuiltIn: display?.isBuiltIn ?? false, level: display?.brightnessLevel, highlighted: selected)
                    .padding(GlowTokens.Space.s2)
            }
            VStack(alignment: .leading, spacing: GlowTokens.Space.s2) {
                Text("\(session.reference?.name ?? "The reference") stays as it is. The others change to look like it.")
                    .font(GlowTokens.Typography.caption)
                    .foregroundStyle(GlowTokens.Text.secondary)
                if let problem = session.startProblem {
                    StatusLabel(title: problem, systemImage: "exclamationmark.circle", tone: .warning)
                }
                ForEach(session.candidates.filter { $0.brightnessRoute == .software }) { display in
                    SetupNote(symbol: "circle.lefthalf.filled", text: "\(display.name) dims its picture rather than its backlight, so matching dims the picture.")
                }
                if session.candidates.contains(where: \.isBuiltIn), !session.store.isDemoData {
                    SetupNote(symbol: "sun.max", text: "If your Mac adjusts its brightness automatically, the built-in display may drift while you match. You can turn that off in System Settings › Displays.")
                }
            }
            .padding(.top, GlowTokens.Space.s3)
        }
    }
}

/// Comparing: the calibration window's own controls, in setup's window.
private struct MatchAdjust: View {
    let model: SetupModel
    let session: MatchSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: GlowTokens.Space.s2) {
                SetupTitle("Make them look the same", "Set each display so its grey looks as bright as \(session.reference?.name ?? "the reference")’s. Look at each one in turn, not side by side.")
                if let problem = model.saveProblem {
                    StatusLabel(title: problem, systemImage: "exclamationmark.triangle.fill", tone: .warning)
                }
            }
            .padding(.horizontal, GlowTokens.Space.s8)
            .padding(.top, 34)
            Form { MatchCompare(session: session) }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                // Grouped forms inset their sections by 20; this lines them up with the title.
                .padding(.horizontal, GlowTokens.Space.s3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Saved: the displays side by side, lit as bright as they are, the reference's slider to
/// show them moving together, and where that's set.
private struct MatchDone: View {
    let model: SetupModel
    @Bindable var store: GlowStore
    let session: MatchSession

    var body: some View {
        let members = session.members.compactMap(session.display)
        let reference = members.first
        let shape = RoundedRectangle(cornerRadius: GlowTokens.Radius.tile, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            SetupTitle("Your displays match", "They look alike now, and stay alike as you change their brightness.")
            HStack(spacing: GlowTokens.Space.s3) {
                ForEach(members) { display in
                    VStack(spacing: GlowTokens.Space.s1) {
                        DisplayGlyph(isBuiltIn: display.isBuiltIn, level: display.brightnessLevel, highlighted: true)
                            .frame(height: GlowTokens.Size.displayArtHeight)
                        Text(display.name)
                            .font(GlowTokens.Typography.tileTitle)
                            .foregroundStyle(GlowTokens.Text.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(GlowTokens.Space.s3)
            .background(shape.fill(GlowTokens.Surface.tile))
            .overlay(shape.strokeBorder(GlowTokens.Border.tile))
            .accessibilityElement(children: .combine)
            if let reference {
                VStack(alignment: .leading, spacing: GlowTokens.Space.s1_5) {
                    Text("Try it: move \(reference.name)")
                        .font(GlowTokens.Typography.cardTitle)
                    SetupBrightnessSlider(display: reference, store: store, isPaused: store.pauseReason != nil)
                    Text(store.moveMatchedTogether
                         ? "The others follow it, here and in the menu bar."
                         : "Only \(reference.name) moves while Move matched displays together is off.")
                        .font(GlowTokens.Typography.caption)
                        .foregroundStyle(GlowTokens.Text.secondary)
                }
                .padding(.top, GlowTokens.Space.s5)
            }
            VStack(alignment: .leading, spacing: GlowTokens.Space.s2) {
                CheckButton(title: "Move matched displays together", isOn: $store.moveMatchedTogether)
                Text(store.controlTarget == .all
                     ? "The brightness keys move them together too."
                     : "The brightness keys move them together when they change every display, which you can choose in Settings › Controls.")
                    .font(GlowTokens.Typography.caption)
                    .foregroundStyle(GlowTokens.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let problem = session.problem {
                    StatusLabel(title: problem, systemImage: "exclamationmark.triangle.fill", tone: .warning)
                }
            }
            .padding(.top, GlowTokens.Space.s5)
            Spacer(minLength: GlowTokens.Space.s4)
            HStack {
                FooterNote("Match again, or forget the match, in Settings › Brightness Match.")
                Spacer()
                Button {
                    model.startOver()
                } label: {
                    ActionLabel(title: "Match Again", symbol: "arrow.counterclockwise")
                }
                .buttonStyle(ActionButtonStyle(compact: true))
            }
            .padding(.bottom, GlowTokens.Space.s4)
        }
    }
}
