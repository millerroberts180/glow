import SwiftUI

/// Glow Desk, the menu-bar popover: the desk as it is now and the everyday controls, with
/// room around them. One route to depth, More controls…; configuration lives in Settings,
/// and Refresh, Settings and Quit are on a right-click of the menu-bar mark.
struct MenuBarView: View {
    @Bindable var store: GlowStore
    /// Opens Settings, turned to a pane and a display when given.
    let openSettings: (GlowSettingsPane?, PersistentDisplayIdentity?) -> Void
    /// Snapshots stand in a desk of their own; the app always shows the store's.
    var deskOverride: YourDesk?
    /// Snapshots stand in for the Accessibility grant and the app bundle; the app asks macOS.
    var keyAccessOverride: (isGranted: Bool, isBundledApp: Bool)?
    @State private var confirming: SceneConfirmation?
    /// macOS doesn't announce the Accessibility grant, so the popover checks now and then.
    @State private var keysAllowed = KeyAccess.isGranted
    /// Counts openings, so the settle plays each time the popover opens.
    @State private var opens = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let desk = deskOverride ?? YourDesk(store: store)
        VStack(alignment: .leading, spacing: 0) {
            header(desk)
                .padding(.bottom, GlowTokens.Space.s3)
            Divider()
            displays(desk)
                .padding(.vertical, GlowTokens.Space.s4)
            if !desk.displays.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: GlowTokens.Space.s4) {
                    // Nothing to match with one display.
                    if desk.displays.count > 1 { matchLine(desk) }
                    brightnessKeys
                }
                .padding(.vertical, GlowTokens.Space.s3)
            }
            Divider()
            footer
                .padding(.top, GlowTokens.Space.s3)
        }
        .padding(.horizontal, GlowTokens.Space.s4)
        .padding(.vertical, GlowTokens.Space.s3)
        .frame(width: GlowTokens.Size.popoverWidth)
        // Everything is shown from the first frame; it only settles outward a touch as it
        // opens, and under Reduce Motion not at all.
        .keyframeAnimator(initialValue: CGFloat(1), trigger: opens) { content, scale in
            content.scaleEffect(scale, anchor: .top)
        } keyframes: { _ in
            MoveKeyframe(GlowTokens.Motion.popoverStartScale)
            LinearKeyframe(1, duration: GlowTokens.Motion.popoverOpen, timingCurve: .easeOut)
        }
        .onAppear {
            store.glowDeskOpens += 1
            if !reduceMotion { opens += 1 }
        }
        .task { await store.start() }
        .task {
            while !Task.isCancelled {
                keysAllowed = KeyAccess.isGranted
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .confirmingScene($confirming) { scene, includingAsksFirst in
            Task { await store.applyScene(scene, includingAsksFirst: includingAsksFirst) }
        }
    }

    /// The mark, the name, and a word when these aren't the person's own displays or Glow
    /// can't change them. The scenes sit on the line below; a scene that didn't fully apply
    /// says so underneath.
    private func header(_ desk: YourDesk) -> some View {
        VStack(alignment: .leading, spacing: GlowTokens.Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: GlowTokens.Space.s2) {
                Image(nsImage: GlowLogo.markImage(side: GlowTokens.Size.popoverMark))
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    .accessibilityHidden(true)
                Text("Glow").font(GlowTokens.Typography.popoverTitle)
                if let status = headerStatus(desk) {
                    Text(status)
                        .font(GlowTokens.Typography.caption)
                        .foregroundStyle(GlowTokens.Text.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            scenes(desk)
            if let id = store.sceneState.lastApplied, let result = store.sceneState.results[id], result.failed > 0,
               let scene = store.scenes.first(where: { $0.id == id }) {
                StatusLabel(title: "\(scene.name): \(result.summary)", systemImage: "exclamationmark.circle", tone: result.tone)
                    .font(GlowTokens.Typography.caption)
                    .help(result.detail ?? "")
            }
        }
    }

    private func headerStatus(_ desk: YourDesk) -> String? {
        if store.safeMode, !desk.isDemo { return "Safe mode" }
        return desk.isDemo ? "Demo displays" : nil
    }

    /// The person's scenes by their symbols, the one on the desk now chosen, and the way to
    /// make another.
    private func scenes(_ desk: YourDesk) -> some View {
        HStack(spacing: GlowTokens.Space.s2) {
            Text("Scenes")
                .font(GlowTokens.Typography.callout)
                .foregroundStyle(GlowTokens.Text.secondary)
            SceneStrip(
                scenes: store.scenes,
                activeID: store.activeScene?.id,
                canApply: store.canApplyScenes,
                apply: apply,
                newScene: {
                    store.beginNewScene()
                    openSettings(.scenes, nil)
                },
                showAll: { openSettings(.scenes, nil) }
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .disabled(desk.isPaused || desk.displays.isEmpty)
    }

    private func displays(_ desk: YourDesk) -> some View {
        DeskDisplays(desk: desk, store: store) { openSettings(.displays, $0) }
    }

    /// Glow's one outcome: matched in green with words, or a quiet "not yet" and the way to
    /// Brightness Match.
    @ViewBuilder private func matchLine(_ desk: YourDesk) -> some View {
        let matched = desk.displays.allSatisfy(\.isAppearanceMatched)
        HStack(spacing: GlowTokens.Space.s2) {
            Circle()
                .fill(matched ? GlowTokens.Status.success : .clear)
                .strokeBorder(matched ? .clear : GlowTokens.Text.tertiary, lineWidth: 1)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(matched ? "Displays are appearance matched" : "Not matched yet")
                .font(GlowTokens.Typography.callout)
                .foregroundStyle(matched ? GlowTokens.Text.primary : GlowTokens.Text.secondary)
            Spacer(minLength: 0)
            if !matched {
                Button { openSettings(.match, nil) } label: {
                    ActionLabel(title: "Match displays…", symbol: GlowSettingsPane.match.symbol)
                }
                .buttonStyle(ActionButtonStyle(compact: true, rounded: true))
                .fixedSize()
            }
        }
    }

    private var brightnessKeys: some View {
        VStack(alignment: .leading, spacing: GlowTokens.Space.s2) {
            Text("Brightness keys")
                .font(GlowTokens.Typography.callout)
            KeyTargetChoice(selection: $store.controlTarget)
            if let caption = keysCaption {
                HStack(spacing: GlowTokens.Space.s2) {
                    Text(caption)
                        .font(GlowTokens.Typography.caption)
                        .foregroundStyle(GlowTokens.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !keysGranted, isBundledApp, !store.demoMode, !store.safeMode {
                        Button { openSettings(.controls, nil) } label: {
                            ActionLabel(title: "Allow…", symbol: "hand.raised")
                        }
                        .buttonStyle(ActionButtonStyle(compact: true, rounded: true))
                        .fixedSize()
                    }
                }
            }
        }
    }

    private var keysGranted: Bool { keyAccessOverride?.isGranted ?? keysAllowed }
    private var isBundledApp: Bool { keyAccessOverride?.isBundledApp ?? KeyAccess.isBundledApp }

    /// What the keys will actually do, when the buttons alone don't say: they're left to
    /// macOS, or which display Focused means now.
    private var keysCaption: String? {
        // A snapshot of someone's own desk captions it as theirs, not as the demo it's drawn from.
        if deskOverride?.isDemo ?? store.demoMode { return "With demo displays on, the keys work as they do without Glow." }
        if store.safeMode { return "In safe mode, the keys work as they do without Glow." }
        if !keysGranted {
            return isBundledApp
                ? "Glow can’t see the brightness keys yet."
                : "Run from a terminal, the keys work as they do without Glow."
        }
        guard store.controlTarget == .focused else { return nil }
        let focused = store.displays.first(where: { $0.id == store.focusedDisplayID })
        return focused.map { "Focused: \($0.name)" } ?? "Focused: no display connected"
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button { openSettings(.displays, nil) } label: {
                ActionLabel(title: "More controls…", symbol: "slider.horizontal.3")
            }
            .buttonStyle(ActionButtonStyle(compact: true, rounded: true))
            .fixedSize()
        }
    }

    /// Asks first when the scene would make a change that can blank a display.
    private func apply(_ scene: GlowScene) {
        if let confirmation = store.confirmation(for: scene) {
            confirming = confirmation
        } else {
            Task { await store.applyScene(scene) }
        }
    }
}
