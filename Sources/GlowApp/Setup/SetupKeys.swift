import SwiftUI

/// The brightness keys: Accessibility first, asked for here and noticed when granted, then
/// a press on the real keys, ticked off when Glow takes it. The tutorial shows only the
/// press.
struct KeysStep: View {
    let model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.accessGranted {
                SetupTitle("The brightness keys", "Glow Desk’s Brightness keys choose which displays they change.")
                VStack(alignment: .leading, spacing: GlowTokens.Space.s3) {
                    if !model.tutorialOnly {
                        StatusLabel(title: "Access is on", systemImage: "checkmark.seal.fill", tone: .success)
                    }
                    if let reason = model.keysLeftToMacOS {
                        SetupNote(symbol: "keyboard", text: reason)
                    } else {
                        let line = "Press a brightness key on your keyboard. \(model.keysChange) changes with it."
                        SetupTask(Text(line), spoken: line, done: model.pressedKey)
                    }
                }
            } else {
                SetupTitle("The brightness keys", "To change your displays with your keyboard’s brightness keys, Glow needs Accessibility access. It uses it for those keys only, and never sees what you type.")
                VStack(alignment: .leading, spacing: GlowTokens.Space.s1_5) {
                    Button {
                        model.requestAccess()
                    } label: {
                        ActionLabel(title: "Allow…", symbol: "lock.open")
                    }
                    .buttonStyle(ActionButtonStyle(compact: true))
                    if model.askedForAccess {
                        caption("Turn on Glow in Privacy & Security › Accessibility. This page notices when you do.")
                    }
                    if !model.permission.isBundledApp() {
                        // Under `swift run` the grant attaches to the terminal, so say where the real one is.
                        caption("Glow is running from a terminal, so macOS would give this to the terminal app instead. Open the packaged Glow.app to allow Glow itself.")
                    }
                }
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(GlowTokens.Typography.caption)
            .foregroundStyle(GlowTokens.Text.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
