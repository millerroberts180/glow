import SwiftUI

/// The brightness keys' four targets as four equal buttons, each a symbol over a short name.
/// VoiceOver and the tooltip say the full name.
struct KeyTargetChoice: View {
    @Binding var selection: ControlTarget

    var body: some View {
        HStack(spacing: GlowTokens.Space.s1_5) {
            ForEach(ControlTarget.allCases) { target in
                let selected = target == selection
                Button { selection = target } label: {
                    VStack(spacing: GlowTokens.Space.s0_5) {
                        ChoiceSymbol(name: target.symbol, isLit: selected)
                        Text(target.shortTitle)
                            .foregroundStyle(selected ? GlowTokens.Text.primary : GlowTokens.Text.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, GlowTokens.Space.s0_5)
                }
                .buttonStyle(ActionButtonStyle(compact: true, isSelected: selected, rounded: true))
                .help(target.title)
                .accessibilityLabel(target.title)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}

extension ControlTarget {
    /// The name on the popover's button, short enough for four on one line.
    var shortTitle: String {
        switch self {
        case .all: "All"
        case .underCursor: "Cursor"
        case .focused: "Focused"
        case .macOnly: "Mac"
        }
    }

    var symbol: String {
        switch self {
        case .all: "display.2"
        case .underCursor: "cursorarrow"
        case .focused: "scope"
        case .macOnly: "laptopcomputer"
        }
    }
}

/// The person's scenes as their symbols, the one on the desk now chosen, then the way to make
/// another. Scenes that don't fit on the line give way to "…", which opens them all in Settings.
struct SceneStrip: View {
    let scenes: [GlowScene]
    let activeID: String?
    let canApply: Bool
    let apply: (GlowScene) -> Void
    let newScene: () -> Void
    let showAll: () -> Void

    var body: some View {
        // Every scene if they fit, else one fewer at a time; never a second line.
        ViewThatFits(in: .horizontal) {
            ForEach((0...scenes.count).reversed(), id: \.self) { shown in
                row(showing: shown)
            }
        }
    }

    private func row(showing shown: Int) -> some View {
        HStack(spacing: GlowTokens.Space.s1) {
            ForEach(scenes.prefix(shown)) { scene in
                let active = scene.id == activeID
                Button { apply(scene) } label: {
                    ChoiceSymbol(name: scene.symbol, isLit: active)
                }
                .buttonStyle(ActionButtonStyle(compact: true, isSelected: active, rounded: true))
                .disabled(!canApply)
                .help(scene.name)
                .accessibilityLabel(scene.name)
                .accessibilityValue(active ? "Active" : "")
            }
            if shown < scenes.count {
                iconButton("ellipsis", "All Scenes…", action: showAll)
            }
            iconButton("plus", "New Scene…", action: newScene)
        }
        .fixedSize()
    }

    private func iconButton(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ChoiceSymbol(name: symbol, isLit: true)
        }
        .buttonStyle(ActionButtonStyle(compact: true, rounded: true))
        .help(title)
        .accessibilityLabel(title)
    }
}

/// A popover button's symbol in a square of its own, so a row of them lines up: accent when
/// it's chosen or does something, quiet when it's one of the choices not taken.
private struct ChoiceSymbol: View {
    let name: String
    let isLit: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Image(systemName: name)
            .font(GlowTokens.Typography.actionSymbol)
            .foregroundStyle(!isEnabled ? GlowTokens.Text.tertiary : isLit ? GlowTokens.Accent.primary : GlowTokens.Text.secondary)
            .frame(width: GlowTokens.Size.popoverSymbol, height: GlowTokens.Size.popoverSymbol)
            .accessibilityHidden(true)
    }
}
