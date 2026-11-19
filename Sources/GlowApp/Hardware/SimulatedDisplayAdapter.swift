#if DEBUG
import Foundation

/// Simulated DDC/CI monitors in place of this Mac's displays, for trying Glow's hardware
/// path with no monitor that answers. Discovery runs the real `DDCProbe` and profile ladder
/// over each one, and every read and write goes through `DDCControlChannel` to its bytes.
/// It never reaches IOKit, CoreGraphics, DisplayServices or the gamma table.
///
/// `-GlowSimulatedMonitors all`, or a comma-separated list of model IDs, turns it on for
/// one launch of a debug build.
@MainActor
final class SimulatedDisplayAdapter: DisplayAdapter {
    let name = "Glow Simulated Monitors"
    let monitors: [SimulatedMonitor]
    let safeMode: Bool

    /// What the last discovery learned about one monitor.
    struct Connected {
        let monitor: SimulatedMonitor
        let link: (any DDCTransport)?
        let log: DDCDiscoveryLog
        let descriptors: [CapabilityIdentifier: CapabilityDescriptor]
    }

    private(set) var connected: [PersistentDisplayIdentity: Connected] = [:]
    /// The first values Glow read from each monitor, before it changed anything.
    private(set) var baseline: [PersistentDisplayIdentity: [CapabilityIdentifier: CapabilityValue]] = [:]
    private var discovery: Task<[DisplaySnapshot], Never>?
    private var activity = WriteActivity()

    nonisolated static let argument = "-GlowSimulatedMonitors"
    nonisolated static let transport = "Simulated DDC/CI"

    init(monitors: [SimulatedMonitor], safeMode: Bool = false) {
        self.monitors = monitors
        self.safeMode = safeMode
    }

    /// The models `-GlowSimulatedMonitors` names, and any names it doesn't know; nil
    /// without the flag. On its own, or with "all", it means every model.
    nonisolated static func models(in arguments: [String]) -> (models: [SimulatedMonitor.Model], unknown: [String])? {
        guard let index = arguments.firstIndex(of: argument) else { return nil }
        let value = arguments.indices.contains(index + 1) ? arguments[index + 1] : "all"
        guard value != "all", !value.hasPrefix("-") else { return (SimulatedMonitor.Model.all, []) }
        let names = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        return (names.compactMap(SimulatedMonitor.Model.named), names.filter { SimulatedMonitor.Model.named($0) == nil })
    }

    /// The adapter a launch asked for. Once the flag is given, Glow uses it even when no
    /// name matched, so a typo shows no displays rather than reaching real ones.
    static func requested(in arguments: [String], safeMode: Bool) -> SimulatedDisplayAdapter? {
        guard let requested = models(in: arguments) else { return nil }
        if !requested.unknown.isEmpty {
            let known = SimulatedMonitor.Model.all.map(\.id).joined(separator: ", ")
            FileHandle.standardError.write(Data("Glow: no simulated monitor called \(requested.unknown.joined(separator: ", ")). Known: \(known), or all.\n".utf8))
        }
        return SimulatedDisplayAdapter(monitors: requested.models.map { SimulatedMonitor($0) }, safeMode: safeMode)
    }

    func discover(generation: UInt64) async -> [DisplaySnapshot] {
        await discover(generation: generation) { _ in }
    }

    /// One discovery at a time, as on real hardware.
    func discover(generation: UInt64, progress: @escaping @MainActor @Sendable ([DisplaySnapshot]) -> Void) async -> [DisplaySnapshot] {
        let previous = discovery
        let task = Task { [weak self] () -> [DisplaySnapshot] in
            _ = await previous?.value
            return await self?.performDiscovery(generation: generation, progress: progress) ?? []
        }
        discovery = task
        let snapshots = await task.value
        if discovery == task { discovery = nil }
        return snapshots
    }

    func discoveryLog(for display: PersistentDisplayIdentity) -> DDCDiscoveryLog? {
        connected[display]?.log
    }

    func startingValues(for display: PersistentDisplayIdentity) -> [CapabilityIdentifier: CapabilityValue] {
        baseline[display] ?? [:]
    }

    func write(_ value: CapabilityValue, capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws {
        guard !safeMode else { throw ControlError.adapter(HardwareDisplayAdapter.safeModeMessage) }
        guard let state = connected[display] else { throw ControlError.displayDisconnected }
        guard let descriptor = state.descriptors[capability], descriptor.route == .hardware,
              let link = state.link else { throw ControlError.notWritable }
        activity.begin(display)
        defer { activity.end(display) }
        try await DDCControlChannel(link: link).write(value, descriptor: descriptor)
    }

    func read(capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws -> CapabilityValue {
        guard let state = connected[display] else { throw ControlError.displayDisconnected }
        guard let descriptor = state.descriptors[capability], descriptor.route == .hardware,
              let link = state.link else { throw ControlError.notWritable }
        return try await DDCControlChannel(link: link).read(descriptor)
    }

    func lastWrite(to display: PersistentDisplayIdentity) -> ContinuousClock.Instant? { activity.last(display) }

    /// One Get VCP of a reported code the catalog doesn't know, as on real hardware.
    func readReported(code: UInt8, display: PersistentDisplayIdentity) async throws -> ProbeResult {
        guard CapabilityCatalog.readsOnce(code), let state = connected[display], let link = state.link,
              state.descriptors[CapabilityCatalog.uncataloguedID(code)] != nil else { throw ControlError.notWritable }
        do {
            return try await link.read(code: code)
        } catch {
            throw ControlError.timedOut
        }
    }

    // MARK: - Discovery

    /// Every monitor shows at once as being checked, then takes its place as its probe
    /// finishes, as on real hardware.
    private func performDiscovery(generation: UInt64, progress: @MainActor ([DisplaySnapshot]) -> Void) async -> [DisplaySnapshot] {
        let transport = Self.transport
        connected = [:]
        var snapshots = monitors.indices.map { checking(monitors[$0], index: $0, generation: generation) }
        progress(snapshots)
        await withTaskGroup(of: (Int, DDCProbe).self) { group in
            for (index, monitor) in monitors.enumerated() {
                group.addTask {
                    let probe = await DDCProbe.run(transport: transport, profiles: DDCTransportProfile.ladder) { monitor.link(profile: $0) }
                    return (index, probe)
                }
            }
            for await (index, probe) in group {
                let (snapshot, state) = snapshot(for: monitors[index], index: index, probe: probe, generation: generation)
                connected[snapshot.identity] = state
                if baseline[snapshot.identity] == nil {
                    baseline[snapshot.identity] = Dictionary(uniqueKeysWithValues: snapshot.capabilities.compactMap { descriptor in
                        [.safelyProbed, .answeredUnlisted].contains(descriptor.evidence) && descriptor.access.canWrite
                            ? descriptor.currentValue.map { (descriptor.id, $0) } : nil
                    })
                }
                snapshots[index] = snapshot
                progress(snapshots)
            }
        }
        return snapshots
    }

    /// Display IDs no real display has, so nothing reaches CoreGraphics by mistake.
    nonisolated static func displayID(at index: Int) -> UInt32 { 0x5100_0001 + UInt32(index) }

    /// A monitor whose probe hasn't finished: its name, and nothing to change yet.
    private func checking(_ monitor: SimulatedMonitor, index: Int, generation: UInt64) -> DisplaySnapshot {
        DisplaySnapshot(
            identity: Self.identity(of: monitor),
            connection: .init(displayID: Self.displayID(at: index), transport: Self.transport, generation: generation),
            name: "\(monitor.model.name) (simulated)", isBuiltIn: false, isConnected: true,
            capabilities: [], isAppearanceMatched: false, isDemo: false,
            connectionNotes: Self.notes(for: monitor.model) + ["Checking whether this connection carries DDC/CI…"], isChecking: true
        )
    }

    private static func identity(of monitor: SimulatedMonitor) -> PersistentDisplayIdentity {
        PersistentDisplayIdentity(vendorID: monitor.model.vendorID, productID: monitor.model.productID, serialNumber: monitor.model.serialNumber)
    }

    private static func notes(for model: SimulatedMonitor.Model) -> [String] {
        [
            "Simulated monitor: no display is connected. Its capability report is a real \(model.name)’s, from \(model.source)",
            "Simulated quirks: \(model.behaviour)"
        ]
    }

    private func snapshot(for monitor: SimulatedMonitor, index: Int, probe: DDCProbe, generation: UInt64) -> (DisplaySnapshot, Connected) {
        let model = monitor.model
        let identity = Self.identity(of: monitor)
        var notes = Self.notes(for: model)
        if probe.log.workingProfile != nil {
            notes.append("DDC/CI profile: \(probe.log.profileText)")
        } else {
            notes.append("DDC/CI: no reply on any profile tried (\(probe.log.attempts.map(\.profile).uniqued().joined(separator: ", ")))")
        }
        if let raw = probe.capabilityString, MCCSCapabilities.parse(raw) != nil {
            notes.append("Capability report: \(raw.utf8.count) bytes, \(probe.descriptors.count) settings Glow knows")
        } else if probe.log.workingProfile != nil {
            notes.append("No capability report, so Glow read each setting it knows. \(probe.descriptors.count) answered.")
        } else {
            notes.append("No capability report: \(probe.problem ?? "the display didn’t answer")")
        }
        if safeMode { notes.append("Safe mode: reading only, until Glow is reopened") }
        let snapshot = DisplaySnapshot(
            identity: identity,
            connection: .init(displayID: Self.displayID(at: index), transport: Self.transport, generation: generation),
            name: "\(model.name) (simulated)", isBuiltIn: false, isConnected: true,
            capabilities: probe.descriptors, isAppearanceMatched: false, isDemo: false,
            connectionNotes: notes
        )
        let state = Connected(
            monitor: monitor, link: probe.link, log: probe.log,
            descriptors: Dictionary(probe.descriptors.map { ($0.id, $0) }) { first, _ in first }
        )
        return (snapshot, state)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
#endif
