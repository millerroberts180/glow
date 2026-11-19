import AppKit
import Foundation
import Observation
import SwiftUI

/// Which display the brightness keys change. Stored by its raw value, so the titles can
/// change without losing anyone's choice.
enum ControlTarget: String, CaseIterable, Identifiable, Codable, Sendable {
    case all, underCursor, focused, macOnly
    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All displays"
        case .underCursor: "Under cursor"
        case .focused: "Focused"
        case .macOnly: "Mac only"
        }
    }
}

@MainActor @Observable
final class GlowStore {
    private(set) var displays: [DisplaySnapshot] = []
    private(set) var generation: UInt64 = 0
    private(set) var isDiscovering = false
    private(set) var lastMessage: String?
    /// The Settings pane on show; nil only for the moment the sidebar is clicked between rows.
    var selectedPane: GlowSettingsPane? {
        didSet { if let selectedPane { settings.value.lastPane = selectedPane } }
    }
    var selectedDisplayID: PersistentDisplayIdentity?
    var focusedDisplayID: PersistentDisplayIdentity?
    var demoMode: Bool
    /// Shift was held at launch: Glow reads displays but changes nothing until it's reopened.
    let safeMode: Bool
    /// Set while writes are paused for sleep, wake or a display change; shown in the UI.
    private(set) var pauseReason: String?
    /// How often Glow Desk has opened and how many brightness-key presses have changed a
    /// display this launch. Setup ticks its steps off by them.
    var glowDeskOpens = 0
    var keyPressesMoved = 0
    private var started = false
    /// Each setting's writes, newest value first in line; see `WriteCoalescer`.
    private let writes = WriteCoalescer<String, CapabilityValue>()
    /// What each setting showed before its current run of writes, to go back to if it fails.
    @ObservationIgnored private var runPriors: [String: CapabilityValue] = [:]
    private var resumeTask: Task<Void, Never>?
    private var systemObservers: [NSObjectProtocol] = []

    /// Scenes live in `Scenes/`; this holds what their UI shares.
    let sceneState = SceneState()
    /// Reading (Settings › Reading) lives in `Reading/`; this holds what its UI shares.
    let reading = ReadingState()
    /// The last value Glow set and saw confirmed for each setting this launch, for
    /// "Reapply settings after wake".
    private(set) var setByGlow: [PersistentDisplayIdentity: [CapabilityIdentifier: CapabilityValue]] = [:]
    /// Preferences, saved across launches.
    let settings: GlowSettingsStore
    private let demoAdapter = MockDisplayAdapter()
    let hardwareAdapter: HardwareDisplayAdapter
    /// Tests pass their own adapter to see what Glow writes.
    private let injectedAdapter: (any DisplayAdapter)?
    private let pipeline = DisplayWritePipeline()
    private let overlays = OverlayCoordinator()

    /// `demoDisplays` overrides Settings for this store only; tests pass `true` so they
    /// never reach real hardware.
    init(settings: GlowSettingsStore = GlowSettingsStore(), demoDisplays: Bool? = nil, safeMode: Bool = false, adapter: (any DisplayAdapter)? = nil) {
        self.settings = settings
        self.safeMode = safeMode
        injectedAdapter = adapter
        hardwareAdapter = HardwareDisplayAdapter(safeMode: safeMode)
        demoMode = demoDisplays ?? (!Self.realDisplaysForced && settings.value.useDemoDisplays)
        selectedPane = settings.value.lastPane
        focusedDisplayID = settings.value.focusedDisplay
    }

    /// `GLOW_REAL_DISPLAYS=1` turns demo displays off for one launch, whatever Settings says.
    static var realDisplaysForced: Bool { ProcessInfo.processInfo.environment["GLOW_REAL_DISPLAYS"] == "1" }

    var controlTarget: ControlTarget {
        get { settings.value.controlTarget }
        set { settings.value.controlTarget = newValue }
    }

    var showOverlayOnChange: Bool {
        get { settings.value.showOverlayOnChange }
        set { settings.value.showOverlayOnChange = newValue }
    }

    var levelStyle: LevelStyle {
        get { settings.value.levelStyle }
        set { settings.value.levelStyle = newValue }
    }

    var keyStep: KeyStep {
        get { settings.value.keyStep }
        set { settings.value.keyStep = newValue }
    }

    var fineAdjustment: Bool {
        get { settings.value.fineAdjustment }
        set { settings.value.fineAdjustment = newValue }
    }

    var matchMethod: MatchMethod {
        get { settings.value.matchMethod }
        set { settings.value.matchMethod = newValue }
    }

    /// The focused display someone chose. Discovery can stand in another display while that
    /// one is away; the saved choice stays until they pick again.
    var chosenFocusedDisplayID: PersistentDisplayIdentity? {
        get { focusedDisplayID }
        set {
            focusedDisplayID = newValue
            // A demo display isn't on anyone's desk, so choosing one isn't saved.
            if !demoMode { settings.value.focusedDisplay = newValue }
        }
    }

    var adapter: any DisplayAdapter { injectedAdapter ?? (demoMode ? demoAdapter : hardwareAdapter) }
    var isDemoData: Bool { displays.contains(where: \.isDemo) }

    func start() async {
        guard !started else { return }
        started = true
        // NSApp is nil when the store runs outside the app (tests, previews).
        NSApp?.setActivationPolicy(.accessory)
        observeSystemEvents()
        await refresh()
        // Reading: rereads, launch restore and Patience (Reading/GlowStore+Reading.swift).
        await startReading()
    }

    enum DisplayEvent: Sendable { case sleep, wake, reconfigure }

    /// Pauses writes around sleep, wake and display changes, then rediscovers once things
    /// settle. A display change bumps the topology generation, so any write that was in
    /// flight for the old layout is rejected rather than replayed.
    func handle(_ event: DisplayEvent) {
        resumeTask?.cancel()
        pauseReason = switch event {
        case .sleep: "Displays are asleep"
        case .wake: "Waiting for displays to wake"
        case .reconfigure: "Displays are reconnecting"
        }
        let pipeline = pipeline
        resumeTask = Task {
            await pipeline.setSuspended(true)
            guard event != .sleep else { return }
            // MonitorControl waits 1 s after a reconfigure and 3 s after wake; DDC replies
            // are unreliable before then.
            try? await Task.sleep(for: event == .wake ? .seconds(2) : .seconds(1))
            guard !Task.isCancelled else { return }
            await rediscover()
            guard !Task.isCancelled else { return }
            await pipeline.setSuspended(false)
            pauseReason = nil
            if event == .wake { await reapplyAfterWakeIfChosen() }
        }
    }

    private func observeSystemEvents() {
        guard systemObservers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let events: [(NotificationCenter, Notification.Name, DisplayEvent)] = [
            (workspace, NSWorkspace.willSleepNotification, .sleep),
            (workspace, NSWorkspace.screensDidSleepNotification, .sleep),
            (workspace, NSWorkspace.didWakeNotification, .wake),
            (workspace, NSWorkspace.screensDidWakeNotification, .wake),
            (.default, NSApplication.didChangeScreenParametersNotification, .reconfigure)
        ]
        systemObservers = events.map { center, name, event in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handle(event) }
            }
        }
    }

    /// Refresh Displays: looks again, and tries every DDC/CI profile on connections that
    /// stayed silent.
    func refresh() async {
        hardwareAdapter.retestSilentConnections()
        await rediscover()
    }

    /// Discovery after sleep, wake or a display change. Displays show as discovery finds
    /// them, so a monitor that takes seconds to check holds up no other.
    private func rediscover() async {
        isDiscovering = true
        generation &+= 1
        let currentGeneration = generation
        await pipeline.setTopologyGeneration(currentGeneration)
        let discovered = await adapter.discover(generation: currentGeneration) { [weak self] partial in
            guard let self, generation == currentGeneration else { return }
            show(partial)
        }
        // A newer refresh started while this one read; its result wins.
        guard generation == currentGeneration else { return }
        show(discovered)
        isDiscovering = false
    }

    /// Puts discovery's displays on show. A display still being checked that's already
    /// showing keeps what it showed until its own check finishes, so a refresh doesn't
    /// blank it; a new one shows as being checked.
    private func show(_ discovered: [DisplaySnapshot]) {
        let shown = Dictionary(displays.map { ($0.id, $0) }) { first, _ in first }
        // Reading: stamps the reading time and keeps hidden settings hidden.
        displays = applyingCorrections(to: settings.value.brightnessMatch.annotated(discovered)).map { display in
            guard display.isChecking, let earlier = shown[display.id], !earlier.isChecking else { return display }
            return earlier
        }
        selectedDisplayID = selectedDisplayID.flatMap { id in displays.contains(where: { $0.id == id }) ? id : nil } ?? displays.first?.id
        // The saved choice comes back with its display; until then an external display, or
        // the only display, stands in.
        focusedDisplayID = [demoMode ? nil : settings.value.focusedDisplay, focusedDisplayID].compactMap { $0 }
            .first(where: { id in displays.contains(where: { $0.id == id }) })
            ?? displays.first(where: { !$0.isBuiltIn })?.id ?? displays.first?.id
    }

    func setDemoMode(_ enabled: Bool) {
        demoMode = enabled
        settings.value.useDemoDisplays = enabled
        settings.value.choseDemoDisplays = true
        // Demo displays can't undo software dimming, so hand the real ones back first.
        if enabled, SoftwareDimmer.shared.isDimmingAnything { SoftwareDimmer.shared.restore() }
        setByGlow = [:]
        started = false
        Task { await start() }
    }

    /// `follow` lets a reference's matched displays move with it, when that's switched on.
    /// The value shows at once and goes to the display as soon as the write ahead of it is
    /// done; a run of changes (a held key, a dragged slider) reads back only its last value,
    /// and only that one is confirmed.
    func update(displayID: PersistentDisplayIdentity, capabilityID: CapabilityIdentifier, proposed: CapabilityValue, follow: Bool = true) {
        guard let displayIndex = displays.firstIndex(where: { $0.id == displayID }),
              let capabilityIndex = displays[displayIndex].capabilities.firstIndex(where: { $0.id == capabilityID }) else { return }
        let descriptor = displays[displayIndex].capabilities[capabilityIndex]
        do {
            let validated = try descriptor.validated(proposed)
            let writeKey = "\(displayID.id):\(capabilityID.rawValue)"
            if !writes.isRunning(writeKey) { runPriors[writeKey] = descriptor.lastConfirmedValue ?? descriptor.currentValue }
            displays[displayIndex].capabilities[capabilityIndex].pendingValue = validated
            displays[displayIndex].capabilities[capabilityIndex].currentValue = validated
            let display = displays[displayIndex]
            if showOverlayOnChange { overlays.show(display: display, capability: descriptor, value: validated, failed: false, style: levelStyle) }
            let pipeline = pipeline
            let adapter = adapter
            writes.propose(.init(
                send: {
                    do {
                        _ = try await pipeline.write(descriptor: descriptor, value: validated, display: display, adapter: adapter, readBack: false)
                    } catch ControlError.timedOut {
                        // A late reply isn't a refusal; the run's last value is read back.
                    }
                },
                confirm: { try await pipeline.confirm(descriptor: descriptor, value: validated, display: display, adapter: adapter) },
                finish: { [weak self] result in self?.finishWrite(result, key: writeKey, descriptor: descriptor, display: display, proposed: validated) }
            ), for: writeKey)
            if follow { followMatchedDisplays(from: displayID, capabilityID: capabilityID, value: validated) }
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    /// The outcome of a run of `update` writes, for its last value.
    private func finishWrite(_ result: Result<CapabilityValue, any Error>, key: String, descriptor: CapabilityDescriptor, display: DisplaySnapshot, proposed: CapabilityValue) {
        let prior = runPriors.removeValue(forKey: key)
        guard let d = displays.firstIndex(where: { $0.id == display.id && $0.connection.generation == display.connection.generation }),
              let c = displays[d].capabilities.firstIndex(where: { $0.id == descriptor.id }) else { return }
        switch result {
        case let .success(confirmed):
            displays[d].capabilities[c].currentValue = confirmed
            displays[d].capabilities[c].lastConfirmedValue = confirmed
            displays[d].capabilities[c].pendingValue = nil
            displays[d].capabilities[c].freshness = .confirmed
            displays[d].capabilities[c].reliability.successfulWrites += 1
            displays[d].capabilities[c].reliability.lastSuccess = .now
            setByGlow[display.id, default: [:]][descriptor.id] = confirmed
            lastMessage = "\(descriptor.label) confirmed on \(display.name)"
        case let .failure(error):
            let restored = displays[d].capabilities[c].lastConfirmedValue ?? prior
            displays[d].capabilities[c].currentValue = restored
            displays[d].capabilities[c].pendingValue = nil
            displays[d].capabilities[c].freshness = .stale
            displays[d].capabilities[c].reliability.failedWrites += 1
            displays[d].capabilities[c].reliability.lastFailure = error.localizedDescription
            lastMessage = "Couldn’t update this display"
            overlays.show(display: display, capability: descriptor, value: restored ?? proposed, failed: true, style: levelStyle)
        }
    }

    /// Brightness Match's write: no delay, no overlay and no followers, and the caller
    /// waits for the read-back. Anything still queued for the setting is dropped first.
    func confirmWrite(displayID: PersistentDisplayIdentity, capabilityID: CapabilityIdentifier, value: CapabilityValue) async throws -> CapabilityValue {
        let writeKey = "\(displayID.id):\(capabilityID.rawValue)"
        writes.drop(writeKey)
        runPriors[writeKey] = nil
        guard let display = displays.first(where: { $0.id == displayID }),
              let descriptor = display.capabilities.first(where: { $0.id == capabilityID }) else { throw ControlError.displayDisconnected }
        let live = { [self] in
            displays.firstIndex(where: { $0.id == displayID && $0.connection.generation == display.connection.generation }).flatMap { d in
                displays[d].capabilities.firstIndex(where: { $0.id == capabilityID }).map { (d, $0) }
            }
        }
        do {
            let confirmed = try await pipeline.write(descriptor: descriptor, value: value, display: display, adapter: adapter)
            if let (d, c) = live() {
                displays[d].capabilities[c].currentValue = confirmed
                displays[d].capabilities[c].lastConfirmedValue = confirmed
                displays[d].capabilities[c].pendingValue = nil
                displays[d].capabilities[c].freshness = .confirmed
                displays[d].capabilities[c].reliability.successfulWrites += 1
                displays[d].capabilities[c].reliability.lastSuccess = .now
            }
            setByGlow[displayID, default: [:]][capabilityID] = confirmed
            return confirmed
        } catch {
            // Back to the last value read from the display, never the one asked for.
            if let (d, c) = live() {
                displays[d].capabilities[c].currentValue = displays[d].capabilities[c].lastConfirmedValue ?? descriptor.currentValue
                displays[d].capabilities[c].pendingValue = nil
                displays[d].capabilities[c].reliability.failedWrites += 1
                displays[d].capabilities[c].reliability.lastFailure = error.localizedDescription
            }
            throw error
        }
    }

    /// Sets `isAppearanceMatched` again after the saved matches change.
    func refreshMatchStatus() {
        displays = settings.value.brightnessMatch.annotated(displays)
    }

    /// The display and brightness reading the overlay preview shows, preferring an external
    /// display; nil when no display has a brightness reading to show.
    var overlayPreviewSource: (display: DisplaySnapshot, capability: CapabilityDescriptor, value: CapabilityValue)? {
        let readings = displays.compactMap { display in
            display.capabilities.first(where: { $0.id == .brightness }).flatMap { capability in
                capability.currentValue.map { (display: display, capability: capability, value: $0) }
            }
        }
        return readings.first(where: { !$0.display.isBuiltIn }) ?? readings.first
    }

    func previewOverlay() {
        guard let source = overlayPreviewSource else { return }
        overlays.show(display: source.display, capability: source.capability, value: source.value, failed: false, style: levelStyle)
    }

    func showMessage(_ message: String) { lastMessage = message }

    func diagnosticReport() -> String {
        let body = displays.map { display in
            let capabilities = display.capabilities.map { capability in
                "- \(capability.label): evidence=\(capability.evidence.rawValue), route=\(capability.route.rawValue), access=\(capability.access.rawValue), value=\(capability.currentValue?.description ?? "unknown"), reliability=\(capability.reliability.summary)"
            }.joined(separator: "\n")
            let discovery = adapter.discoveryLog(for: display.identity).map { "\n" + $0.reportLines(for: display).joined(separator: "\n") } ?? ""
            return "Display: \(display.name)\nPersistent identity: vendor \(display.identity.vendorID), product \(display.identity.productID), serial [redacted]\nConnection: \(display.connection.transport), generation \(display.connection.generation)\n\(capabilities)\(discovery)"
        }.joined(separator: "\n\n")
        return "Glow diagnostics (no user or file data)\nAdapter: \(adapter.name)\n\(body)"
    }

    // MARK: - Reading (Settings › Reading; see Reading/GlowStore+Reading.swift)

    /// Reading's only way into `displays`: one setting at a time, matched by display,
    /// connection generation and setting, never a whole display. A setting with a change in
    /// flight (`pendingValue`) keeps everything but its presentation, so a reread can't undo
    /// what someone is changing.
    func reviseSetting(_ capability: CapabilityIdentifier, on display: PersistentDisplayIdentity, generation: UInt64, _ change: (inout CapabilityDescriptor) -> Void) {
        guard let d = displays.firstIndex(where: { $0.id == display && $0.connection.generation == generation }),
              let c = displays[d].capabilities.firstIndex(where: { $0.id == capability }) else { return }
        let live = displays[d].capabilities[c]
        var revised = live
        change(&revised)
        if live.pendingValue != nil {
            var kept = live
            kept.presentation = revised.presentation
            revised = kept
        }
        guard revised != live else { return }
        displays[d].capabilities[c] = revised
    }
    // MARK: - End of Reading
}
