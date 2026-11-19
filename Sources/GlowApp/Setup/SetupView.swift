import SwiftUI

/// The setup window's content: the step, then a footer with progress and its buttons.
struct SetupView: View {
    let model: SetupModel

    var body: some View {
        VStack(spacing: 0) {
            step
                .id(model.step)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            SetupFooter(model: model)
        }
        .frame(width: GlowTokens.Size.setupWindow.width, height: GlowTokens.Size.setupWindow.height)
        .background(GlowTokens.Surface.canvas)
    }

    @ViewBuilder private var step: some View {
        switch model.step {
        case .welcome: WelcomeStep()
        case .displays: DisplaysStep(model: model).setupPage()
        case .match: MatchStep(model: model)
        case .finish: FinishStep(model: model).setupPage()
        }
    }
}

/// Progress dots on the left; Back, or Cancel while matching, and the main button on the
/// right.
private struct SetupFooter: View {
    let model: SetupModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: GlowTokens.Space.s2) {
            HStack(spacing: GlowTokens.Space.s1_5) {
                ForEach(model.steps, id: \.self) { step in
                    Circle()
                        .fill(step == model.step ? GlowTokens.Accent.primary : (contrast == .increased ? GlowTokens.Text.secondary : GlowTokens.Text.tertiary))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(model.stepNumber) of \(model.steps.count)")
            Spacer()
            if model.isMatching {
                // Puts every display back; Esc does the same.
                Button("Cancel") { model.cancel() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.matchStage == .settling)
            } else if !model.isFirst {
                Button("Back") { change { model.back() } }
            }
            if model.showsNotNow {
                Button("Not Now") { change { model.next() } }
            }
            Button {
                change { model.primary() }
            } label: {
                ActionLabel(title: model.primaryTitle, symbol: primarySymbol)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canGoOn)
        }
        .buttonStyle(ActionButtonStyle())
        .padding(.horizontal, GlowTokens.Space.s5)
        .padding(.vertical, 14)
    }

    private var primarySymbol: String {
        if model.showsNotNow { return "circle.lefthalf.filled" }
        return model.isMatching || model.isLast ? "checkmark" : "arrow.right"
    }

    /// Steps cross-fade, which also suits Reduce Motion: nothing moves.
    private func change(_ body: () -> Void) {
        withAnimation(.easeOut(duration: 0.18), body)
    }
}

/// A step's title, and one or two sentences saying what to do. VoiceOver moves to the
/// title as the step appears, so Continue and Back say where they went.
struct SetupTitle: View {
    let title: String
    let detail: String
    @AccessibilityFocusState private var isFocused: Bool

    init(_ title: String, _ detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GlowTokens.Space.s1_5) {
            Text(title)
                .font(GlowTokens.Typography.setupTitle)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isFocused)
                .onAppear { isFocused = true }
            Text(detail)
                .font(GlowTokens.Typography.body)
                .foregroundStyle(GlowTokens.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, GlowTokens.Space.s4)
    }
}

/// A word on the person's desk or what comes next: a symbol and a line, on a soft tile.
struct SetupNote: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: GlowTokens.Space.s2) {
            Image(systemName: symbol)
                .foregroundStyle(GlowTokens.Text.secondary)
                .frame(width: GlowTokens.Size.sliderSymbol)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(GlowTokens.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(GlowTokens.Typography.callout)
        .padding(GlowTokens.Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: GlowTokens.Radius.tile, style: .continuous).fill(GlowTokens.Surface.subtle))
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// A step's page: the window's margins, clear of the transparent title bar.
    func setupPage() -> some View {
        padding(.horizontal, GlowTokens.Space.s8)
            .padding(.top, 34)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
