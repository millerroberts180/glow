import SwiftUI

/// The finish: open at login, applied on Start Using Glow, and where the tutorial is.
struct FinishStep: View {
    @Bindable var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupTitle("Open at login", loginDetail)
            CheckButton(title: "Open Glow at login", isOn: $model.openAtLogin)
                .disabled(!model.login.canRegister)
            Spacer(minLength: GlowTokens.Space.s4)
            FooterNote("To see how Glow works again, choose Open Tutorial… in Settings › General.")
                .padding(.bottom, GlowTokens.Space.s4)
        }
    }

    private var loginDetail: String {
        model.login.canRegister
            ? "Glow starts in the menu bar when you log in. Set when you click Start Using Glow."
            : model.login.detail()
    }
}
