import SwiftUI

/// Choose a display, then its Digital OSD: every setting its connection exposes, in the
/// order and wording the catalog gives, then Glow's own settings for it.
struct DisplaysPane: View {
    @Bindable var store: GlowStore
    @State private var pending: PendingChange?
    /// Bumped when a confirmation is cancelled, so a picker that showed the new value
    /// redraws with the old one.
    @State private var cancelCount = 0

    var body: some View {
        Form {
            if let reason = store.pauseReason {
                Section { PauseNotice(reason: reason) }
            } else if store.safeMode, !store.demoMode {
                Section { SafeModeNotice() }
            }
            if store.displays.isEmpty {
                Section {
                    ContentUnavailableView(
                        store.isDiscovering ? "Reading your displays…" : "No displays found",
                        systemImage: "display",
                        description: Text("Connect a display, or turn on demo displays in General.")
                    )
                }
            } else {
                Section {
                    DisplayChooser(displays: store.displays, selection: $store.selectedDisplayID, isPaused: isHeld)
                }
            }
            if let display = selectedDisplay {
                ForEach(display.osdSections, id: \.category) { section in
                    Section(section.category.rawValue) {
                        ForEach(section.capabilities) { descriptor in
                            OSDRow(display: display, descriptor: descriptor, isPaused: isHeld,
                                   onHide: hideAction(descriptor, on: display)) { value in
                                propose(value, for: descriptor, on: display)
                            }
                            .id("\(descriptor.id.rawValue)-\(cancelCount)")
                        }
                    }
                }
                glowSection(display)
                StartingValuesSection(store: store, display: display)
                ReadAgainSection(store: store, display: display)
                // Hidden settings are kept per real display; demo displays have none.
                if !display.isDemo {
                    HiddenSettingsSection(store: store, display: display)
                }
                aboutSection(display)
            }
        }
        .formStyle(.grouped)
        .confirmingChange($pending) { change in
            store.update(displayID: change.display.id, capabilityID: change.descriptor.id, proposed: change.value)
        } onCancel: {
            cancelCount += 1
        }
    }

    /// While writes are paused, the controls wait.
    private var isHeld: Bool { store.pauseReason != nil }

    private var selectedDisplay: DisplaySnapshot? {
        store.displays.first(where: { $0.id == store.selectedDisplayID }) ?? store.displays.first
    }

    private func propose(_ value: CapabilityValue, for descriptor: CapabilityDescriptor, on display: DisplaySnapshot) {
        if descriptor.requiresConfirmation {
            pending = PendingChange(display: display, descriptor: descriptor, value: value)
        } else {
            store.update(displayID: display.id, capabilityID: descriptor.id, proposed: value)
        }
    }

    /// Hide on This Display, for a setting a real display reports.
    private func hideAction(_ descriptor: CapabilityDescriptor, on display: DisplaySnapshot) -> (() -> Void)? {
        guard !display.isDemo, descriptor.canBeHidden else { return nil }
        return { store.hide(descriptor.id, on: display.id) }
    }

    private func glowSection(_ display: DisplaySnapshot) -> some View {
        Section("Glow") {
            LabeledContent {
                Button {
                    store.selectedPane = .match
                } label: {
                    ActionLabel(title: "Open Brightness Match", symbol: GlowSettingsPane.match.symbol)
                }
                .buttonStyle(ActionButtonStyle(compact: true))
            } label: {
                VStack(alignment: .leading, spacing: GlowTokens.Space.s0_5) {
                    Text("Brightness Match")
                    MatchStatus(isMatched: display.isAppearanceMatched)
                }
            }
            // Four choices are too wide to sit beside the label, so they go under it.
            VStack(alignment: .leading, spacing: GlowTokens.Space.s2) {
                DetailLabel(title: "Control mode", detail: "Which displays the brightness keys change")
                ChoiceButtons(
                    label: "Control mode",
                    options: ControlTarget.allCases.map { .init(value: $0, title: $0.title) },
                    selection: $store.controlTarget
                )
            }
            .padding(.vertical, GlowTokens.Space.s0_5)
            LabeledContent {
                Button {
                    store.selectedPane = .scenes
                } label: {
                    ActionLabel(title: "Open Scenes", symbol: GlowSettingsPane.scenes.symbol)
                }
                .buttonStyle(ActionButtonStyle(compact: true))
            } label: {
                DetailLabel(title: "Scenes", detail: sceneDetail(display))
            }
        }
    }

    private func aboutSection(_ display: DisplaySnapshot) -> some View {
        Section("About this connection") {
            LabeledContent {
                Button {
                    store.selectedPane = .connection
                } label: {
                    ActionLabel(title: "Open Connection", symbol: GlowSettingsPane.connection.symbol)
                }
                .buttonStyle(ActionButtonStyle(compact: true))
            } label: {
                DetailLabel(title: display.connectionSummary, detail: hiddenDetail(display))
            }
        }
    }

    private func sceneDetail(_ display: DisplaySnapshot) -> String {
        let names = store.scenes.filter { $0.part(for: display.id) != nil }.map(\.name)
        guard !names.isEmpty else { return "Not part of any scene yet" }
        return "Part of " + names.formatted(.list(type: .and))
    }

    private func hiddenDetail(_ display: DisplaySnapshot) -> String {
        let count = display.capabilities.filter { $0.presentation == .connectionDetailsOnly }.count
        return switch count {
        case 0: "Connection lists how Glow reached each setting."
        case 1: "1 more item the display reports is listed only in Connection."
        default: "\(count) more items the display reports are listed only in Connection."
        }
    }
}

/// "Appearance matched" with a green check, or a quiet "Not matched yet". Status, never a
/// button.
struct MatchStatus: View {
    let isMatched: Bool

    var body: some View {
        StatusLabel(title: isMatched ? "Appearance matched" : "Not matched yet",
                    systemImage: isMatched ? "checkmark.circle.fill" : "circle.dashed",
                    tone: isMatched ? .success : .neutral)
    }
}

/// The connected displays as tiles: each drawn, named, with how Glow controls it.
struct DisplayChooser: View {
    let displays: [DisplaySnapshot]
    @Binding var selection: PersistentDisplayIdentity?
    var isPaused = false

    var body: some View {
        HStack(spacing: GlowTokens.Space.s2) {
            ForEach(displays) { display in
                tile(display)
            }
        }
        .padding(.vertical, GlowTokens.Space.s1)
    }

    private func tile(_ display: DisplaySnapshot) -> some View {
        let selected = display.id == (selection ?? displays.first?.id)
        let status = display.summaryStatus(isPaused: isPaused)
        let shape = RoundedRectangle(cornerRadius: GlowTokens.Radius.tile, style: .continuous)
        return Button {
            selection = display.id
        } label: {
            VStack(spacing: GlowTokens.Space.s1_5) {
                DisplayGlyph(isBuiltIn: display.isBuiltIn, level: display.brightnessLevel, highlighted: selected)
                    .frame(maxWidth: .infinity)
                    .frame(height: GlowTokens.Size.displayArtHeight)
                    .background(shape.fill(selected ? GlowTokens.Surface.tileChosen : GlowTokens.Surface.tile))
                    .overlay(shape.strokeBorder(selected ? GlowTokens.Accent.primary : GlowTokens.Border.tile, lineWidth: selected ? 2 : 1))
                    .shadow(color: selected ? GlowTokens.Accent.glow : .clear, radius: 5)
                VStack(spacing: GlowTokens.Space.s0_5) {
                    Text(display.name)
                        .font(selected ? GlowTokens.Typography.tileTitleChosen : GlowTokens.Typography.tileTitle)
                        .foregroundStyle(selected ? GlowTokens.Text.primary : GlowTokens.Text.secondary)
                    ControlStatus(state: status)
                }
                .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Labelled on the button itself, so VoiceOver keeps its press action.
        .accessibilityLabel("\(display.name), \(status.label.lowercased())")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
