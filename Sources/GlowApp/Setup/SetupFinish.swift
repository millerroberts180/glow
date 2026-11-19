import SwiftUI

/// The finish: where Glow lives, the brightness keys' permission, offered once and
/// optional, and open at login, applied on Start Using Glow.
struct FinishStep: View {
    @Bindable var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupTitle("You’re set", "Glow lives in the menu bar, out of the way until you need it.")
            VStack(alignment: .leading, spacing: GlowTokens.Space.s5) {
                FinishRow(title: "In the menu bar", detail: "Click Glow’s mark for every display’s brightness. Right-click it to refresh your displays, open Settings or quit.") {
                    Image(nsImage: GlowLogo.menuBarImage())
                        .foregroundStyle(GlowTokens.Text.primary)
                }
                FinishRow(title: "The brightness keys", detail: keysDetail) {
                    Image(systemName: "sun.max")
                        .foregroundStyle(GlowTokens.Accent.primary)
                } content: {
                    keys
                }
                FinishRow(title: "Open at login", detail: loginDetail) {
                    Image(systemName: "power")
                        .foregroundStyle(GlowTokens.Accent.primary)
                } content: {
                    CheckButton(title: "Open Glow at login", isOn: $model.openAtLogin)
                        .disabled(!model.login.canRegister)
                }
            }
            Spacer(minLength: GlowTokens.Space.s4)
            FooterNote("Settings › General › Open Tutorial… walks through your displays again.")
                .padding(.bottom, GlowTokens.Space.s4)
        }
    }

    private var keysDetail: String {
        model.accessGranted
            ? "Glow hears them now. Choose which displays they change in Settings › Controls."
            : "To change your other displays with them too, Glow needs Accessibility access. It’s used for the keys and nothing else, and you can skip it."
    }

    @ViewBuilder private var keys: some View {
        if model.accessGranted {
            StatusLabel(title: "Access is on", systemImage: "checkmark.seal.fill", tone: .success)
        } else {
            VStack(alignment: .leading, spacing: GlowTokens.Space.s1_5) {
                Button {
                    model.requestAccess()
                } label: {
                    ActionLabel(title: "Allow…", symbol: "lock.open")
                }
                .buttonStyle(ActionButtonStyle(compact: true))
                if model.askedForAccess {
                    Text("Turn on Glow in Privacy & Security › Accessibility. This page notices when you do.")
                        .font(GlowTokens.Typography.caption)
                        .foregroundStyle(GlowTokens.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !model.permission.isBundledApp() {
                    // Under `swift run` the grant attaches to the terminal, so say where the real one is.
                    Text("Glow is running from a terminal, so macOS would give this to the terminal app instead. Open the packaged Glow.app to allow Glow itself.")
                        .font(GlowTokens.Typography.caption)
                        .foregroundStyle(GlowTokens.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var loginDetail: String {
        model.login.canRegister
            ? "Glow starts in the menu bar when you log in. Set when you click Start Using Glow."
            : model.login.detail()
    }
}

/// A place to find Glow, or a choice to make: a symbol on a tile, a name, a line, and the
/// control if there is one.
private struct FinishRow<Art: View, Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var art: () -> Art
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: GlowTokens.Space.s3) {
            art()
                .font(GlowTokens.Typography.cardTitle)
                .frame(width: 40, height: 32)
                .background(RoundedRectangle(cornerRadius: GlowTokens.Radius.control, style: .continuous).fill(GlowTokens.Surface.tile))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: GlowTokens.Space.s1) {
                Text(title).font(GlowTokens.Typography.cardTitle)
                Text(detail)
                    .font(GlowTokens.Typography.callout)
                    .foregroundStyle(GlowTokens.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content()
                    .padding(.top, GlowTokens.Space.s1)
            }
        }
    }
}

extension FinishRow where Content == EmptyView {
    init(title: String, detail: String, @ViewBuilder art: @escaping () -> Art) {
        self.init(title: title, detail: detail, art: art, content: { EmptyView() })
    }
}
