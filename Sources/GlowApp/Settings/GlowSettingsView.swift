import SwiftUI

/// The Settings window's content: a sidebar of panes, like System Settings, and the chosen
/// pane under a header naming it.
struct GlowSettingsView: View {
    @Bindable var store: GlowStore
    let loginItem: LoginItem
    var size = GlowTokens.Size.settingsWindow

    var body: some View {
        NavigationSplitView {
            // The desk first, then the app's own settings.
            // Glow's own pane comes last, as About does in Tuck and Hum.
            List(selection: $store.selectedPane) {
                Section("Desk") {
                    SidebarRow(pane: .displays)
                    SidebarRow(pane: .match)
                    SidebarRow(pane: .scenes)
                }
                Section("App") {
                    SidebarRow(pane: .controls)
                    SidebarRow(pane: .reading)
                    SidebarRow(pane: .general)
                }
                Section("Support") {
                    SidebarRow(pane: .connection)
                    SidebarRow(pane: .about)
                }
            }
            .listStyle(.sidebar)
            // On the list itself: any further out, macOS 15 drops the column width along
            // with the toggle, and the sidebar opens at its 140 pt minimum, cutting off
            // "Brightness Match".
            .toolbar(removing: .sidebarToggle)
            // Room between the title bar and the first row. Not contentMargins: that applies
            // only from the window's second update, so the first row would open against the
            // window buttons.
            .safeAreaPadding(.top, GlowTokens.Space.s3)
            .navigationSplitViewColumnWidth(GlowTokens.Size.settingsSidebarWidth)
        } detail: {
            let shown = store.selectedPane ?? .displays
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    // In the title bar, level with the window buttons.
                    PaneHeader(pane: shown)
                        .frame(height: max(proxy.safeAreaInsets.top, GlowTokens.Size.paneHeaderHeight))
                    Divider().opacity(0.6)
                    detail(shown)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .ignoresSafeArea(.container, edges: .top)
            }
            // Read by VoiceOver and the Window menu; the title bar hides it.
            .navigationTitle(shown.title)
        }
        .frame(width: size.width, height: size.height)
        // Clicking empty sidebar space would leave nothing chosen.
        .onChange(of: store.selectedPane) { old, new in
            if new == nil { store.selectedPane = old }
        }
    }

    @ViewBuilder private func detail(_ pane: GlowSettingsPane) -> some View {
        switch pane {
        case .general: GeneralPane(store: store, loginItem: loginItem)
        case .displays: DisplaysPane(store: store)
        case .match: BrightnessMatchPane(store: store)
        case .scenes: ScenesPane(store: store)
        case .controls: ControlsPane(store: store)
        case .connection: ConnectionDetailsPane(store: store)
        case .about: AboutPane()
        case .reading: ReadingPane(store: store)
        }
    }
}

/// What you're looking at, in the title bar above the pane: its tile and its name.
struct PaneHeader: View {
    let pane: GlowSettingsPane

    var body: some View {
        HStack(spacing: GlowTokens.Space.s2) {
            PaneTile(pane: pane, size: GlowTokens.Size.headerTile)
            Text(pane.title)
                .font(GlowTokens.Typography.paneTitle)
            Spacer()
        }
        .padding(.horizontal, GlowTokens.Space.s5)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A pane's tinted symbol tile, for the sidebar and the header. Glow's own is the app icon:
/// the mark in white on its colour, as Tuck's About tile is Tuck's icon.
struct PaneTile: View {
    let pane: GlowSettingsPane
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        glyph
            .frame(width: size, height: size)
            .background(shape.fill(pane.tint.gradient))
            .overlay(shape.strokeBorder(.white.opacity(0.15)))
            .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var glyph: some View {
        if pane == .about {
            Image(nsImage: GlowLogo.markImage(side: size * 0.78, color: .white))
        } else {
            Image(systemName: pane.symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// One pane in the sidebar: a small tinted tile, then its name.
struct SidebarRow: View {
    let pane: GlowSettingsPane

    var body: some View {
        Label {
            Text(pane.title).font(GlowTokens.Typography.sidebarRow)
        } icon: {
            PaneTile(pane: pane, size: GlowTokens.Size.sidebarTile)
        }
        .padding(.vertical, 1)
        .tag(pane)
    }
}
