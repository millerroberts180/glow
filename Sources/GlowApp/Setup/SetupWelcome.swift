import SwiftUI

/// The welcome: the mark, the name, and what Glow is for, in one line. Get Started works
/// from the first frame, and nothing moves.
struct WelcomeStep: View {
    @AccessibilityFocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: GlowTokens.Space.s5) {
            Image(nsImage: GlowLogo.markImage(side: GlowTokens.Size.setupMark))
                .accessibilityHidden(true)
            VStack(spacing: GlowTokens.Space.s1_5) {
                Text("Glow")
                    .font(GlowTokens.Typography.title1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isFocused)
                Text("Every display at the right brightness, set from the menu bar.")
                    .font(GlowTokens.Typography.body)
                    .foregroundStyle(GlowTokens.Text.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, GlowTokens.Space.s8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isFocused = true }
    }
}
