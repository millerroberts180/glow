import SwiftUI

/// Settings › Reading: how Glow keeps what it shows true to each display, what it does as it
/// opens, wake, and how long it waits for slow displays (ADR 0002). Reading never changes a
/// display; only At launch and Wake put values back, and only when chosen.
struct ReadingPane: View {
    @Bindable var store: GlowStore

    var body: some View {
        Form {
            if let reason = store.pauseReason {
                Section { PauseNotice(reason: reason) }
            }

            Section {
                // Three choices are too wide to sit beside the label, so they go under it.
                VStack(alignment: .leading, spacing: GlowTokens.Space.s2) {
                    DetailLabel(title: "Keep readings fresh", detail: store.readingFreshness.detail)
                    ChoiceButtons(
                        label: "Keep readings fresh",
                        options: ReadingFreshness.allCases.map { .init(value: $0, title: $0.title) },
                        selection: $store.readingFreshness
                    )
                }
                .padding(.vertical, GlowTokens.Space.s0_5)
                LabeledContent {
                    Button {
                        Task { await store.readAll() }
                    } label: {
                        ActionLabel(title: isReading ? "Reading…" : "Read All", symbol: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(!canRead)
                } label: {
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        DetailLabel(title: "Read every display", detail: readAllDetail(now: context.date))
                    }
                }
            } header: {
                Text("Readings")
            } footer: {
                FooterNote("Reading never changes a display. A setting you’re changing is left alone until the change lands, and a display that doesn’t answer is asked less often.")
            }

            Section {
                VStack(alignment: .leading, spacing: GlowTokens.Space.s2) {
                    DetailLabel(title: "When Glow opens", detail: store.launchReading.detail)
                    ChoiceButtons(
                        label: "When Glow opens",
                        options: LaunchReading.allCases.map { .init(value: $0, title: $0.title) },
                        selection: $store.launchReading
                    )
                }
                .padding(.vertical, GlowTokens.Space.s0_5)
                if store.launchReading == .restore {
                    LabeledContent("What Glow last set") {
                        Text(lastSetSummary)
                            .foregroundStyle(GlowTokens.Text.secondary)
                    }
                }
            } header: {
                Text("At launch")
            } footer: {
                FooterNote("Demo displays are never changed as Glow opens.")
            }

            Section {
                DetailToggle(
                    title: "Reapply settings after wake",
                    detail: "Some displays forget brightness and other settings while they sleep. Once your displays are awake and Glow can write again, it puts back what it last set, if a display lost it. Input and power are never changed.",
                    isOn: $store.reapplyAfterWake
                )
            } header: {
                Text("Wake")
            }

            Section {
                VStack(alignment: .leading, spacing: GlowTokens.Space.s2) {
                    DetailLabel(title: "Patience", detail: store.readingPatience.detail)
                    ChoiceButtons(
                        label: "Patience",
                        options: ReadingPatience.allCases.map { .init(value: $0, title: $0.title) },
                        selection: $store.readingPatience
                    )
                }
                .padding(.vertical, GlowTokens.Space.s0_5)
            } header: {
                Text("Slow displays")
            }
        }
        .formStyle(.grouped)
    }

    private var isReading: Bool { !store.reading.readingNow.isEmpty }

    private var canRead: Bool {
        store.pauseReason == nil && !store.isDiscovering && !isReading && !store.displays.isEmpty
    }

    private func readAllDetail(now: Date) -> String {
        if store.displays.isEmpty { return "No displays to read." }
        if store.pauseReason != nil { return "Reading waits while changes are paused." }
        return store.oldestReadingAge(now: now)
    }

    /// How many real displays Glow has kept values for, in words.
    private var lastSetSummary: String {
        let kept = store.settings.value.lastSet.displays.count
        return switch kept {
        case 0: "Nothing yet"
        case 1: "Kept for 1 display"
        default: "Kept for \(kept) displays"
        }
    }
}
