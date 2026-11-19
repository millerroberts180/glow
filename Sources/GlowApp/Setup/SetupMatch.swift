import SwiftUI

/// Matching their brightness with Quick Match: choose the reference, set the others until
/// their grey looks the same, and save. The words are the calibration window's.
struct MatchStep: View {
    let model: SetupModel

    var body: some View {
        let stage = model.matchStage
        Group {
            switch stage {
            case .unavailable(let reason):
                VStack(alignment: .leading, spacing: 0) {
                    SetupTitle("Match their brightness", reason)
                    FooterNote("You can match them later in Settings › Brightness Match.")
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
                if let match = model.match { MatchDone(session: match).setupPage() }
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

/// Choosing the reference: the display that already looks right.
private struct MatchPick: View {
    @Bindable var session: MatchSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupTitle("Match their brightness", "Pick the display that looks right. A grey patch then fills each display, and you set the others to look as bright.")
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
                if let problem = session.startProblem {
                    StatusLabel(title: problem, systemImage: "exclamationmark.circle", tone: .warning)
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
                SetupTitle("Match the grey", "Set each display so its grey looks as bright as \(session.reference?.name ?? "the reference")’s. Look at each in turn, not side by side.")
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

/// Saved: what the match does in Glow Desk, and where it's changed.
private struct MatchDone: View {
    let session: MatchSession

    var body: some View {
        let reference = session.members.first.flatMap(session.display)
        VStack(alignment: .leading, spacing: 0) {
            SetupTitle("Your displays match", "Move \(reference?.name ?? "the reference") in Glow Desk, and the others follow it.")
            if let problem = session.problem {
                StatusLabel(title: problem, systemImage: "exclamationmark.triangle.fill", tone: .warning)
                    .padding(.bottom, GlowTokens.Space.s3)
            }
            FooterNote("Match again, or forget the match, in Settings › Brightness Match.")
        }
    }
}
