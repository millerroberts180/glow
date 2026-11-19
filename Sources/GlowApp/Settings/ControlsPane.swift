import SwiftUI

/// What the brightness keys change, how far a press moves, and how levels look.
struct ControlsPane: View {
    @Bindable var store: GlowStore
    /// macOS doesn't announce the grant, so the pane checks once a second while it's open.
    @State private var keysAllowed = KeyAccess.isGranted

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    if keysAllowed {
                        StatusLabel(title: "Allowed", systemImage: "checkmark.circle.fill", tone: .success)
                    } else {
                        Button {
                            KeyAccess.request()
                        } label: {
                            ActionLabel(title: "Allow…", symbol: "keyboard")
                        }
                        .buttonStyle(ActionButtonStyle())
                        // Under `swift run` the grant would go to the terminal, not Glow.
                        .disabled(!KeyAccess.isBundledApp)
                    }
                } label: {
                    DetailLabel(title: "Brightness keys", detail: keyAccessDetail)
                }
            }
            Section("Brightness keys change") {
                VStack(alignment: .leading, spacing: GlowTokens.Space.s2) {
                    VisualChoice(
                        options: ControlTarget.allCases.map { .init(value: $0, title: $0.title) },
                        selection: $store.controlTarget
                    ) { target, selected in
                        ControlTargetArt(target: target, highlighted: selected)
                    }
                    Text(targetDetail)
                        .font(GlowTokens.Typography.caption)
                        .foregroundStyle(GlowTokens.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, GlowTokens.Space.s0_5)
                LabeledContent {
                    if store.displays.isEmpty {
                        Text("No displays")
                            .foregroundStyle(GlowTokens.Text.secondary)
                    } else {
                        MenuPicker(
                            label: "Focused display",
                            options: store.displays.map { .init(value: $0.id, title: $0.name) },
                            selection: $store.chosenFocusedDisplayID
                        )
                    }
                } label: {
                    DetailLabel(title: "Focused display", detail: "Used when the keys change the focused display")
                }
                // Depends on the choice: it dims rather than disappears.
                .disabled(store.controlTarget != .focused)
            }

            Section {
                LabeledContent {
                    ChoiceButtons(
                        label: "Brightness step",
                        options: KeyStep.allCases.map { .init(value: $0, title: $0.title) },
                        selection: $store.keyStep
                    )
                } label: {
                    DetailLabel(title: "Brightness step", detail: "How far one press moves. Holding a key moves 1% at a time.")
                }
                DetailToggle(
                    title: "Fine adjustment",
                    detail: "Hold Option and Shift with a brightness key for a quarter step, for precise matching.",
                    isOn: $store.fineAdjustment
                )
                LabeledContent {
                    Button {
                        store.previewOverlay()
                    } label: {
                        ActionLabel(title: "Preview Overlay", symbol: "rectangle.bottomhalf.inset.filled")
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(store.overlayPreviewSource == nil)
                } label: {
                    DetailLabel(title: "Overlay", detail: overlayDetail)
                }
            } header: {
                Text("Adjustment")
            } footer: {
                FooterNote(keysFooter)
            }

            Section("Look") {
                VStack(alignment: .leading, spacing: GlowTokens.Space.s2) {
                    VisualChoice(
                        options: LevelStyle.allCases.map { .init(value: $0, title: title(of: $0)) },
                        selection: $store.levelStyle,
                        // Shows the overlay in the new look, when there's a reading to show.
                        onPick: { _ in store.previewOverlay() }
                    ) { style, selected in
                        LevelStyleArt(style: style, highlighted: selected)
                    }
                    Text("How brightness and volume look in the menu bar and on the overlay.")
                        .font(GlowTokens.Typography.caption)
                        .foregroundStyle(GlowTokens.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, GlowTokens.Space.s0_5)
            }
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                keysAllowed = KeyAccess.isGranted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var keyAccessDetail: String {
        if keysAllowed { return "macOS lets Glow see the brightness keys (Accessibility). You can turn this off in Privacy & Security." }
        return KeyAccess.isBundledApp
            ? "To change displays with the brightness keys, macOS needs to let Glow see them (Accessibility). Until then the keys work as they do without Glow."
            : "Open Glow from Glow.app to allow the brightness keys. Run from a terminal, macOS would give the permission to the terminal instead."
    }

    private var keysFooter: String {
        if !keysAllowed { return "Your choices here are saved and take effect once Glow can see the brightness keys." }
        if store.demoMode { return "With demo displays on, the brightness keys work as they do without Glow." }
        return "\(store.keyStep.footer) Mac only leaves the keys to macOS."
    }

    private func title(of style: LevelStyle) -> String {
        switch style {
        case .slider: "Slider"
        case .boxes: "Boxes"
        }
    }

    private var targetDetail: String {
        switch store.controlTarget {
        case .all: "Every display changes together, each from its own level."
        case .underCursor: "Only the display under the pointer changes."
        case .focused: "Only the focused display changes, whichever one is chosen."
        case .macOnly: "Only the Mac’s built-in display changes, as it does without Glow."
        }
    }

    private var overlayDetail: String {
        guard store.overlayPreviewSource != nil else { return "No display has a brightness reading to show yet." }
        return store.showOverlayOnChange
            ? "Shows the panel that appears on a display when its brightness changes."
            : "Shows the panel once. It’s turned off for changes in General."
    }
}
