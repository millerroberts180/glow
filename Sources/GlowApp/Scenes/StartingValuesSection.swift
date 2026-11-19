import SwiftUI

/// Restore Starting Values (ADR 0001, decision 9): puts back what Glow read from the display
/// when it first found it this launch, through the same checks and confirmations as a
/// scene. Anything Glow didn't read is left alone.
struct StartingValuesSection: View {
    @Bindable var store: GlowStore
    let display: DisplaySnapshot
    @State private var confirming: SceneConfirmation?

    var body: some View {
        let starting = store.startingScene(for: display)
        let applying = store.sceneState.applying == starting.id
        Section {
            LabeledContent {
                Button {
                    restore(starting)
                } label: {
                    ActionLabel(title: applying ? "Restoring…" : "Restore Starting Values", symbol: "arrow.uturn.backward")
                }
                .buttonStyle(ActionButtonStyle(compact: true))
                .disabled(starting.settingCount == 0 || !store.canApplyScenes)
            } label: {
                VStack(alignment: .leading, spacing: GlowTokens.Space.s0_5) {
                    DetailLabel(title: "Starting values", detail: detail(starting))
                    if let result = store.sceneState.restoreResults[display.id] {
                        StatusLabel(title: result.summary(done: "Restored"),
                                    systemImage: result.failed > 0 ? "exclamationmark.circle" : (result.succeeded > 0 ? "checkmark.circle.fill" : "minus.circle"),
                                    tone: result.tone)
                        if let more = result.detail {
                            Text(more)
                                .font(GlowTokens.Typography.caption)
                                .foregroundStyle(GlowTokens.Text.secondary)
                        }
                    }
                }
            }
            .confirmingScene($confirming) { scene, includingAsksFirst in
                run(includingAsksFirst: includingAsksFirst)
            }
        }
    }

    private func detail(_ starting: GlowScene) -> String {
        if store.startingValues(for: display.id).isEmpty {
            return "Glow didn’t read any setting it can change here, so there’s nothing to put back."
        }
        guard let part = starting.part(for: display.id) else { return "Everything Glow read at launch is as it was." }
        let values = part.settings.map { $0.text(on: display) }.joined(separator: " · ")
        return "Puts back what Glow read at launch: \(values)"
    }

    private func restore(_ starting: GlowScene) {
        if let confirmation = store.confirmation(for: starting) {
            confirming = confirmation
        } else {
            run(includingAsksFirst: false)
        }
    }

    private func run(includingAsksFirst: Bool) {
        Task { await store.restoreStartingValues(of: display, includingAsksFirst: includingAsksFirst) }
    }
}
