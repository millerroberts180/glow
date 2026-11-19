import SwiftUI

/// Read Again for one display in Settings › Displays: how long ago Glow last read it, and a
/// button that rereads every setting it reports without looking for displays again.
struct ReadAgainSection: View {
    @Bindable var store: GlowStore
    let display: DisplaySnapshot
    /// What the last Read Again found, said plainly, until another display is chosen.
    @State private var found: String?

    var body: some View {
        Section("Reading") {
            if hasSomethingToRead {
                LabeledContent {
                    Button {
                        Task { found = Self.summary(of: await store.readAgain(display.id)) }
                    } label: {
                        ActionLabel(title: isReading ? "Reading…" : "Read Again", symbol: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(ActionButtonStyle(compact: true))
                    .disabled(isReading || store.pauseReason != nil || store.isDiscovering)
                } label: {
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        DetailLabel(title: store.readingAge(for: display.id, now: context.date), detail: detail)
                    }
                }
            } else {
                DetailLabel(title: "Nothing to read", detail: "Glow sets this display without asking it anything, so there’s no reading to refresh.")
            }
        }
        .onChange(of: display.id) { found = nil }
    }

    private var isReading: Bool { store.reading.readingNow.contains(display.id) }

    private var hasSomethingToRead: Bool {
        !display.rereadable(.everything).isEmpty || !display.reportedUncatalogued.isEmpty
    }

    private var detail: String {
        if store.pauseReason != nil { return "Reading waits while changes are paused." }
        if let found { return found }
        return "Rereads every setting this display reports. Nothing is changed."
    }

    /// "Brightness had changed on the display", "Nothing had changed", or that it didn't answer.
    nonisolated static func summary(of outcomes: [ReadingOutcome]) -> String? {
        guard !outcomes.isEmpty else { return nil }
        let read = outcomes.filter(\.wasRead)
        guard !read.isEmpty else {
            return outcomes.contains { if case .failed = $0.result { true } else { false } }
                ? "The display didn’t answer. Glow will try again later."
                : nil
        }
        let changed = read.filter { if case .changed = $0.result { true } else { false } }.count
        return switch changed {
        case 0: "Nothing had changed."
        case 1: "1 setting had changed on the display."
        default: "\(changed) settings had changed on the display."
        }
    }
}

/// What someone hid on a real display because it does nothing there, with Show for each,
/// and a menu to hide another. Hidden settings stay listed in Connection.
struct HiddenSettingsSection: View {
    @Bindable var store: GlowStore
    let display: DisplaySnapshot

    var body: some View {
        let hidden = store.hiddenSettings(on: display.id)
        Section {
            if hidden.isEmpty {
                DetailLabel(title: "Nothing hidden", detail: "If a setting this display reports does nothing, hide it here or with a Control-click on its row.")
            }
            ForEach(hidden, id: \.id) { setting in
                LabeledContent {
                    Button {
                        store.show(setting.id, on: display.id)
                    } label: {
                        ActionLabel(title: "Show", symbol: "eye")
                    }
                    .buttonStyle(ActionButtonStyle(compact: true))
                    .accessibilityLabel("Show \(setting.label)")
                } label: {
                    VStack(alignment: .leading, spacing: GlowTokens.Space.s0_5) {
                        Text(setting.label)
                        StatusLabel(title: "Hidden by you", systemImage: "eye.slash")
                    }
                }
            }
            if !hideable.isEmpty {
                LabeledContent("Hide a setting") {
                    SettingsMenu {
                        ForEach(hideable) { descriptor in
                            Button(descriptor.label) { store.hide(descriptor.id, on: display.id) }
                        }
                    } label: {
                        Text("Choose…")
                    }
                    .accessibilityLabel("Hide a setting")
                }
            }
        } header: {
            Text("Hidden by you")
        } footer: {
            FooterNote("A hidden setting leaves the list above, Glow Desk and scenes, on this display only. Connection still lists it.")
        }
    }

    /// What the display reports that could be hidden, in OSD order.
    private var hideable: [CapabilityDescriptor] {
        display.osdSections.flatMap(\.capabilities).filter(\.canBeHidden)
    }
}
