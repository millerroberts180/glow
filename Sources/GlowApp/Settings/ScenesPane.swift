import SwiftUI

/// The person's scenes: what each sets on which display, Apply, which reports exactly how
/// much took, and the way to make, edit, reorder and delete them.
struct ScenesPane: View {
    @Bindable var store: GlowStore
    @State private var confirming: SceneConfirmation?
    @State private var deleting: GlowScene?

    var body: some View {
        Form {
            if let reason = store.pauseReason {
                Section { PauseNotice(reason: reason) }
            } else if store.safeMode, !store.demoMode {
                Section { SafeModeNotice() }
            }
            if store.demoMode {
                Section {
                    Label {
                        Text("Example scenes for the demo displays. Changes to them aren’t saved, and your own scenes come back when demo displays are off.")
                            .font(GlowTokens.Typography.caption)
                            .foregroundStyle(GlowTokens.Text.secondary)
                    } icon: {
                        Image(systemName: "info.circle").foregroundStyle(GlowTokens.Text.secondary)
                    }
                }
            }
            if store.scenes.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No scenes yet", systemImage: "sparkles")
                    } description: {
                        Text("A scene saves what your displays show now, such as brightness, contrast and volume, so you can put it all back in one click.")
                    } actions: {
                        newSceneButton
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(store.scenes) { scene in
                    sceneSection(scene)
                }
                Section {
                    LabeledContent {
                        newSceneButton
                    } label: {
                        DetailLabel(title: "New scene", detail: newSceneDetail)
                    }
                }
            }
            Section {
            } footer: {
                FooterNote("A scene changes only what each display supports. Glow never turns a display off as part of a scene, and asks first before switching an input.")
            }
        }
        .formStyle(.grouped)
        .confirmingScene($confirming) { scene, includingAsksFirst in
            run(scene, includingAsksFirst: includingAsksFirst)
        }
        .sheet(item: Bindable(store.sceneState).draft) { draft in
            SceneEditor(store: store, draft: draft)
        }
    }

    private var canCapture: Bool { GlowScene.capturing(store.displays, name: "").settingCount > 0 }

    private var newSceneDetail: String {
        canCapture
            ? "Saves what each display shows now. Input stays out unless you add it, and power is never included."
            : "Connect a display Glow can read first."
    }

    private var newSceneButton: some View {
        Button {
            store.beginNewScene()
        } label: {
            ActionLabel(title: "New Scene from Current Settings", symbol: "plus")
        }
        .buttonStyle(ActionButtonStyle())
        .disabled(!canCapture)
    }

    private func sceneSection(_ scene: GlowScene) -> some View {
        Section {
            ForEach(scene.displays, id: \.identity) { part in
                partRow(part)
            }
            // Centred, not baseline-aligned: the result is one or two short lines beside
            // taller buttons.
            HStack {
                resultLabel(for: scene)
                Spacer()
                Button {
                    edit(scene)
                } label: {
                    ActionLabel(title: "Edit…", symbol: "pencil")
                }
                .buttonStyle(ActionButtonStyle(compact: true))
                Button {
                    apply(scene)
                } label: {
                    ActionLabel(title: store.sceneState.applying == scene.id ? "Applying…" : "Apply \(scene.name)", symbol: scene.symbol)
                }
                .buttonStyle(ActionButtonStyle())
                .disabled(!store.canApplyScenes)
            }
            .confirmationDialog(
                "Delete “\(scene.name)”?",
                isPresented: Binding(get: { deleting?.id == scene.id }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete Scene", role: .destructive) { store.deleteScene(id: scene.id) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your displays stay as they are.")
            }
        } header: {
            HStack(spacing: GlowTokens.Space.s1_5) {
                Image(systemName: scene.symbol)
                    .foregroundStyle(GlowTokens.Text.secondary)
                    .accessibilityHidden(true)
                Text(scene.name)
                if store.activeScene?.id == scene.id {
                    Text("Active")
                        .font(GlowTokens.Typography.sectionLabel)
                        .foregroundStyle(GlowTokens.Text.secondary)
                        .padding(.horizontal, GlowTokens.Space.s1_5)
                        .padding(.vertical, GlowTokens.Space.s0_5)
                        .background(GlowTokens.Surface.subtle, in: .capsule)
                        .accessibilityLabel("Active: your displays match this scene")
                }
                Spacer()
                sceneMenu(scene)
            }
        }
    }

    private func sceneMenu(_ scene: GlowScene) -> some View {
        let index = store.scenes.firstIndex(where: { $0.id == scene.id }) ?? 0
        return SettingsMenu {
            Button("Edit…", systemImage: "pencil") { edit(scene) }
            Button("Move Up", systemImage: "arrow.up") { store.moveScene(id: scene.id, by: -1) }
                .disabled(index == 0)
            Button("Move Down", systemImage: "arrow.down") { store.moveScene(id: scene.id, by: 1) }
                .disabled(index == store.scenes.count - 1)
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive) { deleting = scene }
        } label: {
            // In a Text, so the trigger is a line of text tall like the buttons beside it.
            Text(Image(systemName: "ellipsis"))
                .foregroundStyle(GlowTokens.Accent.primary)
        }
        .help("Edit, move or delete \(scene.name)")
        .accessibilityLabel("More for \(scene.name)")
    }

    /// One display's part: its name, then what the scene sets there, in the OSD's order.
    private func partRow(_ part: SceneDisplay) -> some View {
        let display = store.displays.first(where: { $0.id == part.identity && $0.isConnected })
        let settings = part.settings.map { setting in
            var text = setting.text(on: display)
            let descriptor = display?.capabilities.first(where: { $0.id == setting.capability })
            if descriptor?.risk == .destructive {
                text += " (never applied)"
            } else if display != nil, !(descriptor?.canBeInScene ?? false) {
                text += " (not on this connection)"
            } else if setting.asksFirst(on: display) {
                text += " (asks first)"
            }
            return text
        }.joined(separator: " · ")
        return DetailLabel(
            title: display?.name ?? "\(part.name) · not connected",
            detail: display == nil ? "Skipped until it’s back: \(settings)" : settings
        )
    }

    @ViewBuilder private func resultLabel(for scene: GlowScene) -> some View {
        if let result = store.sceneState.results[scene.id] {
            VStack(alignment: .leading, spacing: GlowTokens.Space.s0_5) {
                StatusLabel(title: result.summary,
                            systemImage: result.failed > 0 ? "exclamationmark.circle" : (result.succeeded > 0 ? "checkmark.circle.fill" : "minus.circle"),
                            tone: result.tone)
                if let detail = result.detail {
                    Text(detail)
                        .font(GlowTokens.Typography.caption)
                        .foregroundStyle(GlowTokens.Text.secondary)
                }
            }
        } else {
            let count = scene.settingCount
            Text(count == 1 ? "Sets 1 setting" : "Sets \(count) settings")
                .font(GlowTokens.Typography.caption)
                .foregroundStyle(GlowTokens.Text.secondary)
        }
    }

    private func edit(_ scene: GlowScene) {
        store.sceneState.draft = SceneDraft(scene: scene, isNew: false)
    }

    /// Asks first when the scene would make a change that can blank a display, such as a
    /// new input.
    private func apply(_ scene: GlowScene) {
        if let confirmation = store.confirmation(for: scene) {
            confirming = confirmation
        } else {
            run(scene, includingAsksFirst: false)
        }
    }

    private func run(_ scene: GlowScene, includingAsksFirst: Bool) {
        Task { await store.applyScene(scene, includingAsksFirst: includingAsksFirst) }
    }
}
