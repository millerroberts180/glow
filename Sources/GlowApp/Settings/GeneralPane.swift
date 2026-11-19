import SwiftUI

/// What people change most: starting at login, the overlay, and which displays Glow uses.
struct GeneralPane: View {
    @Bindable var store: GlowStore
    @Bindable var loginItem: LoginItem

    var body: some View {
        Form {
            Section {
                DetailToggle(title: "Open at login", detail: loginItem.detail, isOn: $loginItem.isOn)
                    .disabled(!loginItem.canRegister)
                if loginItem.needsApproval {
                    LabeledContent("Login Items") {
                        Button {
                            loginItem.openSystemSettings()
                        } label: {
                            ActionLabel(title: "Open Login Items…", symbol: "gearshape")
                        }
                        .buttonStyle(ActionButtonStyle())
                    }
                }
                DetailToggle(
                    title: "Show overlay on change",
                    detail: "A small panel on the display you changed shows its new value, then fades.",
                    isOn: $store.showOverlayOnChange
                )
            }

            Section {
                DetailToggle(title: "Use demo displays", detail: demoDetail, isOn: demoBinding)
                    .disabled(GlowStore.realDisplaysForced)
                LabeledContent {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        ActionLabel(title: store.isDiscovering ? "Refreshing…" : "Refresh Displays", symbol: "arrow.clockwise")
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(store.isDiscovering)
                } label: {
                    DetailLabel(title: "Look for displays", detail: "Finds displays again and rereads what each one supports.")
                }
            } header: {
                Text("Displays")
            } footer: {
                FooterNote("Everyday controls stay in the menu bar. Glow opens this window only when you ask.")
            }

            Section("Help") {
                LabeledContent {
                    Button {
                        SetupPresenter.current?.show(tutorialOnly: true)
                    } label: {
                        ActionLabel(title: "Open Tutorial…", symbol: "questionmark.circle")
                    }
                    .buttonStyle(ActionButtonStyle())
                } label: {
                    DetailLabel(title: "Tutorial", detail: "Walks through your displays, matching their brightness and the brightness keys again.")
                }
            }

            Section {
                LabeledContent {
                    Button {
                        NSApp.terminate(nil)
                    } label: {
                        ActionLabel(title: "Quit Glow", symbol: "power")
                    }
                    .buttonStyle(ActionButtonStyle())
                } label: {
                    DetailLabel(
                        title: "Leave the menu bar",
                        detail: "The brightness keys go back to macOS and software dimming is undone. Your displays keep the rest of their settings."
                    )
                }
            }
        }
        .formStyle(.grouped)
        // Login Items can change in System Settings while this window is closed, and macOS
        // doesn't announce it: read it on opening, and keep reading while approval waits.
        .task(id: loginItem.needsApproval) {
            loginItem.refresh()
            while loginItem.needsApproval, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                loginItem.refresh()
            }
        }
    }

    private var demoDetail: String {
        if GlowStore.realDisplaysForced { return "Off for this launch: Glow was started to use your real displays." }
        return store.demoMode
            ? "Three sample displays, so every control can be tried without a monitor. Nothing is sent to real hardware."
            : "Glow is using the displays connected to this Mac."
    }

    /// Switching rediscovers displays, so it goes through the store rather than a plain write.
    private var demoBinding: Binding<Bool> {
        Binding(get: { store.demoMode }, set: { store.setDemoMode($0) })
    }
}
