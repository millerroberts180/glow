import SwiftUI

/// The sheet for a new or saved scene: its name and symbol, and per display which settings
/// it includes at which values. Edits a copy; nothing changes until Save, and nothing is
/// sent to a display from here.
struct SceneEditor: View {
    @Bindable var store: GlowStore
    let isNew: Bool
    @State private var scene: GlowScene
    @State private var confirmingDelete = false
    /// What the name goes back to when the symbol gives none.
    private let defaultName: String

    static let size = CGSize(width: 560, height: 600)

    init(store: GlowStore, draft: SceneDraft) {
        self.store = store
        isNew = draft.isNew
        _scene = State(initialValue: draft.scene)
        defaultName = GlowScene.defaultName(startingFrom: draft.scene.name, isNew: draft.isNew)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $scene.name)
                    VStack(alignment: .leading, spacing: GlowTokens.Space.s1_5) {
                        Text("Symbol")
                        // The name follows the symbol until the person names the scene.
                        VisualChoice(
                            options: SceneSymbol.all.map { .init(value: $0.symbol, title: $0.name) },
                            selection: Binding(get: { scene.symbol }, set: { scene.wear($0, defaultName: defaultName) }),
                            artHeight: 32
                        ) { symbol, selected in
                            Image(systemName: symbol)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(selected ? GlowTokens.Accent.primary : GlowTokens.Text.secondary)
                        }
                    }
                    .padding(.vertical, GlowTokens.Space.s0_5)
                }
                ForEach(connected) { display in
                    displaySection(display)
                }
                ForEach(away, id: \.identity) { part in
                    awaySection(part)
                }
                if connected.isEmpty, away.isEmpty {
                    Section {
                        Text("Connect a display to choose what this scene sets.")
                            .foregroundStyle(GlowTokens.Text.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            buttons
                .padding(GlowTokens.Space.s4)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .confirmationDialog("Delete “\(scene.name)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Scene", role: .destructive) {
                store.deleteScene(id: scene.id)
                close()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your displays stay as they are.")
        }
    }

    // MARK: - Displays

    private var connected: [DisplaySnapshot] { store.displays.filter(\.isConnected) }

    /// The scene's displays that aren't connected now. Their settings are kept as they are
    /// and can only be removed until the display is back.
    private var away: [SceneDisplay] {
        scene.displays.filter { part in !part.settings.isEmpty && !connected.contains(where: { $0.id == part.identity }) }
    }

    // A grouped form lays out a footer on a section inside a ForEach as part of a single
    // row, so these sections end with a caption row instead.
    private func displaySection(_ display: DisplaySnapshot) -> some View {
        let offered = display.osdSections.flatMap(\.capabilities).filter { $0.canBeInScene || $0.risk == .destructive }
        let others = display.capabilities.filter { $0.presentation == .osd && !$0.canBeInScene && $0.risk != .destructive }.count
        return Section {
            ForEach(offered) { descriptor in
                settingRow(descriptor, on: display)
            }
            if offered.isEmpty {
                Text("Nothing on this connection can be part of a scene.")
                    .foregroundStyle(GlowTokens.Text.secondary)
            }
            if others > 0 {
                FooterNote(others == 1
                    ? "1 more setting on this connection is read-only or an action, so it can’t be part of a scene."
                    : "\(others) more settings on this connection are read-only or actions, so they can’t be part of a scene.")
            }
        } header: {
            HStack {
                Text(display.name)
                Spacer()
                Button {
                    useCurrentValues(on: display)
                } label: {
                    ActionLabel(title: "Use Current Values", symbol: "eyedropper")
                }
                .buttonStyle(ActionButtonStyle(compact: true))
                .disabled(scene.part(for: display.id)?.settings.isEmpty ?? true)
                .help("Sets every included setting to what \(display.name) shows now")
            }
        }
    }

    @ViewBuilder private func settingRow(_ descriptor: CapabilityDescriptor, on display: DisplaySnapshot) -> some View {
        let value = scene.part(for: display.id)?.setting(descriptor.id)?.value
        let reading = descriptor.confirmedValue
        LabeledContent {
            if let value, descriptor.canBeInScene {
                CapabilityControl(display: display, descriptor: descriptor.showing(value)) { proposed in
                    if let checked = try? descriptor.validated(proposed) { scene.set(checked, for: descriptor, on: display) }
                }
            }
        } label: {
            // The check leads, so a note under the name doesn't push it aside.
            HStack(alignment: .firstTextBaseline, spacing: GlowTokens.Space.s2) {
                CheckButton(title: "Include \(descriptor.label)", showsTitle: false, isOn: Binding(
                    get: { value != nil },
                    set: { include in scene.set(include ? reading : nil, for: descriptor, on: display) }
                ))
                VStack(alignment: .leading, spacing: GlowTokens.Space.s0_5) {
                    HStack(spacing: GlowTokens.Space.s1_5) {
                        Text(descriptor.label)
                        if descriptor.canBeInScene, descriptor.requiresConfirmation { AsksFirstTag() }
                    }
                    if let note = note(for: descriptor, hasReading: reading != nil, included: value != nil) {
                        Text(note)
                            .font(GlowTokens.Typography.caption)
                            .foregroundStyle(GlowTokens.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            // A setting can join only with a value Glow has read; it never starts from a guess.
            .disabled(!descriptor.canBeInScene || (value == nil && reading == nil))
        }
    }

    private func note(for descriptor: CapabilityDescriptor, hasReading: Bool, included: Bool) -> String? {
        if descriptor.risk == .destructive { return "Never part of a scene: it can turn the display off." }
        if !included, !hasReading { return "No reading yet, so it can’t be added." }
        if descriptor.requiresConfirmation { return "Glow asks before applying it, since the display may go blank." }
        return nil
    }

    private func awaySection(_ part: SceneDisplay) -> some View {
        Section {
            ForEach(part.settings, id: \.capability) { setting in
                LabeledContent {
                    Button {
                        scene.remove(setting.capability, from: part.identity)
                    } label: {
                        ActionLabel(title: "Remove", symbol: "minus.circle")
                    }
                    .buttonStyle(ActionButtonStyle(compact: true))
                    .help("Remove from this scene")
                    .accessibilityLabel("Remove \(setting.label) from this scene")
                } label: {
                    HStack(spacing: GlowTokens.Space.s1_5) {
                        Text(setting.text(on: nil))
                        if setting.asksFirst(on: nil) { AsksFirstTag() }
                    }
                }
            }
            FooterNote("Kept as saved. Connect the display to change these values.")
        } header: {
            Text("\(part.name) · not connected")
        }
    }

    // MARK: - Buttons

    private var canSave: Bool {
        !scene.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && scene.settingCount > 0
    }

    /// Only Save has a symbol, so it reads as the sheet's main action; Return still saves
    /// and Esc still cancels.
    private var buttons: some View {
        HStack {
            if !isNew {
                Button("Delete Scene…", role: .destructive) { confirmingDelete = true }
                    .buttonStyle(ActionButtonStyle())
            }
            Spacer()
            if !canSave {
                Text(scene.settingCount == 0 ? "Include at least one setting" : "Name the scene")
                    .font(GlowTokens.Typography.caption)
                    .foregroundStyle(GlowTokens.Text.secondary)
            }
            Button("Cancel", role: .cancel) { close() }
                .buttonStyle(ActionButtonStyle())
                .keyboardShortcut(.cancelAction)
            Button {
                store.saveScene(scene)
                close()
            } label: {
                ActionLabel(title: isNew ? "Save Scene" : "Save", symbol: "checkmark")
            }
            .buttonStyle(ActionButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
    }

    private func useCurrentValues(on display: DisplaySnapshot) {
        for setting in scene.part(for: display.id)?.settings ?? [] {
            guard let descriptor = display.capabilities.first(where: { $0.id == setting.capability }),
                  let reading = descriptor.confirmedValue else { continue }
            scene.set(reading, for: descriptor, on: display)
        }
    }

    private func close() { store.sceneState.draft = nil }
}

/// "Asks first": a change Glow confirms before making, because the display may go blank.
struct AsksFirstTag: View {
    var body: some View {
        Text("Asks first")
            .font(GlowTokens.Typography.sectionLabel)
            .foregroundStyle(GlowTokens.Status.warningText)
            .padding(.horizontal, GlowTokens.Space.s1_5)
            .padding(.vertical, GlowTokens.Space.s0_5)
            .background(GlowTokens.Surface.subtle, in: .capsule)
            .accessibilityLabel("Asks first")
    }
}

extension CapabilityDescriptor {
    /// A copy that shows a scene's value as if it were current, for the editor's controls.
    func showing(_ value: CapabilityValue) -> CapabilityDescriptor {
        var copy = self
        copy.currentValue = value
        copy.pendingValue = nil
        copy.freshness = .confirmed
        copy.reliability.lastFailure = nil
        return copy
    }
}

extension GlowScene {
    /// Includes a setting at a value, changes its value, or with nil leaves it out.
    mutating func set(_ value: CapabilityValue?, for descriptor: CapabilityDescriptor, on display: DisplaySnapshot) {
        let index = displays.firstIndex(where: { $0.identity == display.id }) ?? {
            displays.append(SceneDisplay(identity: display.id, name: display.name, settings: []))
            return displays.count - 1
        }()
        displays[index].name = display.name
        displays[index].settings.removeAll { $0.capability == descriptor.id }
        if let value {
            displays[index].settings.append(SceneSetting(descriptor.id, value, describedBy: descriptor))
            displays[index].settings.sort { $0.order(on: display) < $1.order(on: display) }
        }
    }

    mutating func remove(_ capability: CapabilityIdentifier, from identity: PersistentDisplayIdentity) {
        guard let index = displays.firstIndex(where: { $0.identity == identity }) else { return }
        displays[index].settings.removeAll { $0.capability == capability }
    }
}
