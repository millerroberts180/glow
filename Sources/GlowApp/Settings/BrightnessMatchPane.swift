import SwiftUI

/// Where each display stands, how to match them, and the matches Glow keeps.
struct BrightnessMatchPane: View {
    @Bindable var store: GlowStore
    @State private var confirmingForget = false

    var body: some View {
        Form {
            if store.safeMode && !store.demoMode {
                Section { SafeModeNotice() }
            } else if let pause = store.pauseReason {
                Section { PauseNotice(reason: pause) }
            }

            Section {
                ForEach(store.displays) { display in
                    let state = store.matchState(of: display)
                    LabeledContent {
                        MatchStateLabel(state: state)
                    } label: {
                        HStack(spacing: GlowTokens.Space.s3) {
                            DisplayGlyph(isBuiltIn: display.isBuiltIn, level: display.brightnessLevel)
                                .frame(width: 34, height: 24)
                            VStack(alignment: .leading, spacing: GlowTokens.Space.s0_5) {
                                Text(display.name)
                                ControlStatus(state: display.summaryStatus(isPaused: store.pauseReason != nil))
                                ForEach(details(of: display, state: state), id: \.self) { line in
                                    Text(line)
                                        .font(GlowTokens.Typography.caption)
                                        .foregroundStyle(GlowTokens.Text.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if store.displays.isEmpty {
                    Text("No displays to match yet.").foregroundStyle(GlowTokens.Text.secondary)
                }
            } header: {
                Text("Your displays")
            } footer: {
                FooterNote("Brightness Match lines up how bright your displays look, not their slider numbers. It’s an appearance match, not color calibration.")
            }

            Section("How to match") {
                VStack(alignment: .leading, spacing: GlowTokens.Space.s2) {
                    VisualChoice(
                        options: MatchMethod.allCases.map { .init(value: $0, title: $0.title) },
                        selection: $store.matchMethod,
                        artHeight: 52
                    ) { method, selected in
                        MatchMethodArt(method: method, highlighted: selected)
                    }
                    Text(store.matchMethod.detail)
                        .font(GlowTokens.Typography.caption)
                        .foregroundStyle(GlowTokens.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, GlowTokens.Space.s0_5)
                let unavailable = MatchSession.unavailableReason(store: store, candidates: store.matchCandidates)
                LabeledContent {
                    Button {
                        MatchWindowPresenter.shared.show(store: store)
                    } label: {
                        ActionLabel(title: "Match Displays…", symbol: "circle.lefthalf.filled")
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(unavailable != nil)
                } label: {
                    DetailLabel(title: "Calibration", detail: unavailable ?? "Puts a grey patch on each display while you match. Esc puts everything back as it was.")
                }
            }

            Section("Matched displays") {
                DetailToggle(
                    title: "Move matched displays together",
                    detail: "A reference’s own slider moves the displays matched to it. The brightness keys always do when they change every display.",
                    isOn: $store.moveMatchedTogether
                )
                LabeledContent {
                    Button {
                        confirmingForget = true
                    } label: {
                        ActionLabel(title: "Forget Match", symbol: "xmark.circle")
                    }
                    .buttonStyle(ActionButtonStyle(compact: true))
                    .disabled(!store.hasMatchToForget)
                } label: {
                    DetailLabel(title: "Forget Match", detail: "Clears every connected display’s match. Brightness stays where it is.")
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Forget every match?", isPresented: $confirmingForget) {
            Button("Forget Match", role: .destructive) { store.forgetMatch() }
        } message: {
            Text("Brightness stays where it is. You can match again any time.")
        }
    }

    /// The quieter lines under a display's name: what its match is, and what software
    /// dimming means for it.
    private func details(of display: DisplaySnapshot, state: MatchState) -> [String] {
        var lines: [String] = []
        switch state {
        case .reference(let followers):
            lines.append(followers.isEmpty ? "The displays matched to it aren’t connected." : "\(ListFormatter.localizedString(byJoining: followers)) \(followers.count == 1 ? "follows" : "follow") it.")
        case .matched(let calibration):
            lines.append("\(calibration.method.title), \(calibration.date.formatted(date: .abbreviated, time: .omitted)). Follows \(name(of: calibration.pair.reference)).")
        case .outOfDate(_, let was, let now):
            lines.append("Matched over \(was.userLabel.lowercased()), and it’s \(now.userLabel.lowercased()) now. Match again to use it.")
        case .notMatched:
            break
        }
        if display.brightnessRoute == .software {
            lines.append("Matching dims its picture, not its backlight.")
        }
        return lines
    }

    private func name(of id: PersistentDisplayIdentity) -> String {
        store.displays.first { $0.id == id }?.name ?? "a display that isn’t connected"
    }
}

/// A display's Brightness Match status, as a short label.
private struct MatchStateLabel: View {
    let state: MatchState

    var body: some View {
        switch state {
        case .reference(let followers):
            StatusLabel(title: "Reference", systemImage: "scope", tone: followers.isEmpty ? .neutral : .success)
        case .matched:
            StatusLabel(title: "Matched", systemImage: "checkmark.circle.fill", tone: .success)
        case .outOfDate:
            StatusLabel(title: "Match is out of date", systemImage: "exclamationmark.triangle.fill", tone: .warning)
        case .notMatched:
            StatusLabel(title: "Not matched", systemImage: "circle.dashed", tone: .neutral)
        }
    }
}
