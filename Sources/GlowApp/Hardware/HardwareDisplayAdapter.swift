import AppKit
import CoreGraphics
import Foundation

/// This Mac's real displays. Discovery only reads: DisplayServices for Apple and built-in
/// screens, DDC/CI over IOAVService for external monitors, the gamma table for everything
/// else. Writes come only from `DisplayWritePipeline`, which confirms each by reading back.
@MainActor
final class HardwareDisplayAdapter: DisplayAdapter {
    let name = "Glow Hardware Adapter"
    /// Started with Shift held: reads everything, changes nothing (ADR 0001, decision 9).
    let safeMode: Bool
    /// The first profile discovery tries; the rest of `DDCTransportProfile.ladder` follows.
    let profile: DDCTransportProfile

    /// What the last discovery learned about one display.
    struct Connected {
        let facts: DisplayFacts
        let match: DDCServiceMatcher.Match?
        /// Reopened when Patience changes; see `patience`.
        var link: (any DDCTransport)?
        /// What DDC/CI discovery tried; nil for displays it doesn't reach.
        let log: DDCDiscoveryLog?
        let descriptors: [CapabilityIdentifier: CapabilityDescriptor]
    }

    private(set) var connected: [PersistentDisplayIdentity: Connected] = [:]
    /// The first values Glow read from each display this launch, before it changed anything.
    private(set) var baseline: [PersistentDisplayIdentity: [CapabilityIdentifier: CapabilityValue]] = [:]
    private var discovery: Task<[DisplaySnapshot], Never>?
    /// The profile each connection answered on, and which stayed silent.
    private var routes = DDCRouteMemory()
    private var activity = WriteActivity()

    /// Settings › Reading › Patience, for every read and write from now on. Changing it
    /// reopens each connection's link on the adjusted profile; discovery's ladder doesn't
    /// change (ADR 0002, decision 6).
    var patience: ReadingPatience = .normal {
        didSet {
            guard patience != oldValue else { return }
            for (id, state) in connected {
                guard let registryID = state.match?.candidate.registryID, let working = state.log?.workingProfile,
                      let link = DisplayRegistry.link(registryID: registryID, profile: patience.profile(from: working)) else { continue }
                connected[id]?.link = link
            }
        }
    }

    static let safeModeMessage = "Glow started in safe mode, so it isn’t changing displays. Quit and reopen Glow to make changes."

    init(safeMode: Bool = false, profile: DDCTransportProfile = .standard) {
        self.safeMode = safeMode
        self.profile = profile
    }

    func discover(generation: UInt64) async -> [DisplaySnapshot] {
        await discover(generation: generation) { _ in }
    }

    /// One discovery at a time: a second one waits for the first, then reads again, so two
    /// never talk to one display's bus together.
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

    /// Refresh Displays: the next discovery tries every profile again on connections that
    /// stayed silent.
    func retestSilentConnections() {
        routes.forgetSilence()
    }

    func write(_ value: CapabilityValue, capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws {
        guard !safeMode else { throw ControlError.adapter(Self.safeModeMessage) }
        guard let state = connected[display] else { throw ControlError.displayDisconnected }
        guard let descriptor = state.descriptors[capability] else { throw ControlError.notWritable }
        activity.begin(display)
        defer { activity.end(display) }
        switch descriptor.route {
        case .hardware:
            guard let link = state.link else { throw ControlError.notWritable }
            try await DDCControlChannel(link: link).write(value, descriptor: descriptor)
        case .native:
            guard capability == .brightness, case let .number(percent) = value, let native = NativeBrightness.shared,
                  native.setBrightness(Float(percent / 100), on: state.facts.displayID) else { throw ControlError.notWritable }
        case .software:
            guard capability == .brightness, case let .number(percent) = value,
                  SoftwareDimmer.shared.setLevel(percent / 100, on: state.facts.displayID) else { throw ControlError.notWritable }
        case .unavailable:
            throw ControlError.notWritable
        }
    }

    func read(capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws -> CapabilityValue {
        guard let state = connected[display] else { throw ControlError.displayDisconnected }
        guard let descriptor = state.descriptors[capability] else { throw ControlError.notWritable }
        switch descriptor.route {
        case .hardware:
            guard let link = state.link else { throw ControlError.notWritable }
            return try await DDCControlChannel(link: link).read(descriptor)
        case .native:
            guard capability == .brightness, let level = NativeBrightness.shared?.brightness(state.facts.displayID) else { throw ControlError.timedOut }
            return .number(NativeBrightness.percent(level))
        case .software:
            guard capability == .brightness, let level = SoftwareDimmer.shared.level(of: state.facts.displayID) else { throw ControlError.timedOut }
            return .number((level * 100).rounded())
        case .unavailable:
            throw ControlError.notWritable
        }
    }

    func lastWrite(to display: PersistentDisplayIdentity) -> ContinuousClock.Instant? { activity.last(display) }

    /// One Get VCP of a code the display reported and the catalog doesn't know. There's no
    /// write counterpart anywhere: `DDCControlChannel` only writes catalogued codes.
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

    /// Every display shows at once: the built-in, and any display Glow can't reach over
    /// DDC/CI, as they are; the rest as being checked. Each of those takes its place as its
    /// own probe finishes, so a slow or silent monitor holds up no other display.
    private func performDiscovery(generation: UInt64, progress: @MainActor ([DisplaySnapshot]) -> Void) async -> [DisplaySnapshot] {
        let displayIDs = DisplayRegistry.onlineDisplays()
        let facts = displayIDs.map(DisplayRegistry.facts(for:))
        let candidates = await Task.detached(priority: .userInitiated) { DisplayRegistry.externalServices() }.value
        let matches = DDCServiceMatcher.assign(facts, to: candidates)
        SoftwareDimmer.shared.keepOnly(Set(displayIDs))
        let identities = Self.identities(of: facts)

        // Each external display is read on its own bus queue, all at once, starting with the
        // profile it last answered on.
        let ladder = [profile] + DDCTransportProfile.ladder.filter { $0 != profile }
        var plans: [CGDirectDisplayID: (key: DDCRouteKey, profiles: [DDCTransportProfile], quick: Bool)] = [:]
        for display in facts where !display.isBuiltIn {
            guard let match = matches[display.displayID] else { continue }
            let key = DDCRouteKey(display, registryID: match.candidate.registryID)
            let plan = routes.plan(for: key, ladder: ladder)
            plans[display.displayID] = (key, plan.profiles, plan.quick)
        }
        connected = [:]
        var snapshots = facts.indices.map { index in
            let display = facts[index]
            return record(display, identity: identities[index], match: matches[display.displayID], probe: nil,
                          checking: plans[display.displayID] != nil, generation: generation)
        }
        progress(snapshots)

        await withTaskGroup(of: (Int, DDCProbe).self) { group in
            for (index, display) in facts.enumerated() {
                guard let match = matches[display.displayID], let plan = plans[display.displayID] else { continue }
                let label = Self.transportLabel(match.candidate.transport)
                let registryID = match.candidate.registryID
                group.addTask {
                    let probe = await DDCProbe.run(transport: label, profiles: plan.profiles, quick: plan.quick) { profile in
                        DisplayRegistry.link(registryID: registryID, profile: profile)
                    }
                    return (index, probe)
                }
            }
            for await (index, probe) in group {
                let display = facts[index]
                if let key = plans[display.displayID]?.key { routes.record(probe.log, for: key) }
                snapshots[index] = record(display, identity: identities[index], match: matches[display.displayID], probe: probe,
                                          checking: false, generation: generation)
                progress(snapshots)
            }
        }
        return snapshots
    }

    /// Each display's identity. Two identical monitors with no serial would share one; they're
    /// kept apart for this launch by their display ID.
    private static func identities(of facts: [DisplayFacts]) -> [PersistentDisplayIdentity] {
        var seen = Set<PersistentDisplayIdentity>()
        return facts.map { display in
            var identity = PersistentDisplayIdentity(vendorID: display.vendorID, productID: display.productID, serialNumber: display.serialNumber)
            if !seen.insert(identity).inserted {
                identity = PersistentDisplayIdentity(vendorID: display.vendorID, productID: display.productID, serialNumber: 0x8000_0000 | display.displayID)
                seen.insert(identity)
            }
            return identity
        }
    }

    /// One display as discovery has it so far, and what Glow keeps to reach it. The baseline
    /// comes from the first finished reading, never from a display still being checked.
    private func record(
        _ display: DisplayFacts, identity: PersistentDisplayIdentity, match: DDCServiceMatcher.Match?,
        probe: DDCProbe?, checking: Bool, generation: UInt64
    ) -> DisplaySnapshot {
        let (snapshot, state) = snapshot(for: display, identity: identity, match: match, probe: probe, checking: checking, generation: generation)
        connected[identity] = state
        if !checking, baseline[identity] == nil {
            baseline[identity] = Dictionary(uniqueKeysWithValues: snapshot.capabilities.compactMap { descriptor in
                [.safelyProbed, .answeredUnlisted].contains(descriptor.evidence) && descriptor.access.canWrite
                    ? descriptor.currentValue.map { (descriptor.id, $0) } : nil
            })
        }
        return snapshot
    }

    /// What a finished probe found, for Connection details.
    private static func probeNotes(_ probe: DDCProbe?, settings: Int) -> [String] {
        var notes: [String] = []
        if let log = probe?.log, log.workingProfile != nil {
            notes.append("DDC/CI profile: \(log.profileText)")
        } else {
            let tried = probe?.log.attempts.map(\.profile).uniqued() ?? []
            notes.append("DDC/CI: no reply\(tried.isEmpty ? "" : " on any profile tried (\(tried.joined(separator: ", ")))")")
        }
        if let raw = probe?.capabilityString, MCCSCapabilities.parse(raw) != nil {
            notes.append("Capability report: \(raw.utf8.count) bytes, \(settings) settings Glow knows")
        } else if probe?.log.workingProfile != nil {
            notes.append("No capability report, so Glow read each setting it knows. \(settings) answered.")
        } else {
            notes.append("No capability report: \(probe?.problem ?? "the display didn’t answer")")
        }
        return notes
    }

    nonisolated static func transportLabel(_ transport: String?) -> String {
        switch transport?.uppercased() {
        case "DP": "DisplayPort"
        case "HDMI": "HDMI"
        case let other?: other
        case nil: "External connection"
        }
    }

    /// `checking`: its probe hasn't finished, so it shows only what's known without DDC/CI.
    private func snapshot(
        for display: DisplayFacts, identity: PersistentDisplayIdentity,
        match: DDCServiceMatcher.Match?, probe: DDCProbe?, checking: Bool, generation: UInt64
    ) -> (DisplaySnapshot, Connected) {
        let native = NativeBrightness.shared.flatMap { $0.canChange(display.displayID) ? $0 : nil }
        let transport = display.isBuiltIn ? "Internal" : Self.transportLabel(match?.candidate.transport)
        var notes: [String] = []
        var descriptors = probe?.descriptors ?? []

        if display.isBuiltIn || native != nil {
            notes.append("Brightness through macOS’s own control (DisplayServices)")
        } else if let match {
            notes.append("Matched to its DDC service by \(match.reasons.joined(separator: ", "))")
            if checking {
                notes.append("Checking whether this connection carries DDC/CI…")
            } else {
                notes += Self.probeNotes(probe, settings: descriptors.count)
            }
        } else {
            notes.append("No DDC service matched this display")
        }
        if safeMode { notes.append("Safe mode: reading only, until Glow is reopened") }
        var link = probe?.link
        if patience == .patient, let working = probe?.log.workingProfile, let match {
            link = DisplayRegistry.link(registryID: match.candidate.registryID, profile: working.patient) ?? link
            notes.append("Patience: \(working.patient.differencesFromStandard.joined(separator: "; "))")
        }

        // Brightness: native first, then the display's own (DDC), then software dimming. While
        // DDC/CI is being checked there's no brightness yet, rather than dimming that a
        // moment later might not be needed.
        let ddcBrightness = descriptors.first { $0.id == .brightness }
        if let native {
            descriptors.removeAll { $0.id == .brightness }
            descriptors.insert(nativeBrightness(display, native: native, transport: transport), at: 0)
        } else if !checking, ddcBrightness?.isSafelyEditable != true {
            descriptors.removeAll { $0.id == .brightness }
            let reason = ddcBrightness.map { "The display listed brightness, but \($0.reliability.lastFailure.map(\.sentenceFragment) ?? "it didn’t answer a read")" }
                ?? (probe?.log.workingProfile == nil ? "The display didn’t answer DDC over this connection"
                    : probe?.capabilityString == nil ? "The display didn’t answer a brightness read" : "The display doesn’t list brightness")
            descriptors.insert(softwareBrightness(display, transport: transport, reason: reason), at: 0)
        }
        descriptors += readOnlyFacts(display, transport: transport)

        let snapshot = DisplaySnapshot(
            identity: identity,
            connection: .init(displayID: display.displayID, transport: transport, generation: generation),
            name: display.name, isBuiltIn: display.isBuiltIn, isConnected: true,
            capabilities: descriptors, isAppearanceMatched: false, isDemo: false,
            connectionNotes: notes, isChecking: checking
        )
        let state = Connected(
            facts: display, match: match, link: link, log: probe?.log,
            descriptors: Dictionary(descriptors.map { ($0.id, $0) }) { first, _ in first }
        )
        return (snapshot, state)
    }

    private func nativeBrightness(_ display: DisplayFacts, native: NativeBrightness, transport: String) -> CapabilityDescriptor {
        let level = native.brightness(display.displayID)
        let value = level.map { CapabilityValue.number(NativeBrightness.percent($0)) }
        return CapabilityDescriptor(
            id: .brightness, label: "Brightness", category: .essentials,
            kind: .range(minimum: 0, maximum: 100, step: 1), access: .readWrite, unit: "%",
            evidence: value == nil ? .contradictory : .safelyProbed, currentValue: value,
            freshness: value == nil ? .unknown : .confirmed, route: .native, transport: transport,
            reliability: .init(successfulWrites: 0, failedWrites: 0, lastSuccess: nil,
                               lastFailure: value == nil ? "macOS offers brightness control but didn’t answer a read." : nil,
                               provenance: "Read through macOS’s own brightness control"),
            risk: .none, rawCode: nil, pendingValue: nil, lastConfirmedValue: value
        )
    }

    private func softwareBrightness(_ display: DisplayFacts, transport: String, reason: String) -> CapabilityDescriptor {
        let level = SoftwareDimmer.shared.level(of: display.displayID)
        let value = level.map { CapabilityValue.number(($0 * 100).rounded()) }
        return CapabilityDescriptor(
            id: .brightness, label: "Brightness", category: .essentials,
            kind: .range(minimum: SoftwareDimmer.floor * 100, maximum: 100, step: 1),
            access: value == nil ? .unavailable : .readWrite, unit: "%",
            evidence: value == nil ? .unavailable : .inferred, currentValue: value,
            freshness: value == nil ? .unknown : .confirmed, route: value == nil ? .unavailable : .software, transport: transport,
            reliability: .init(successfulWrites: 0, failedWrites: 0, lastSuccess: nil, lastFailure: nil,
                               provenance: "\(reason). Glow dims the picture instead; the backlight doesn’t change"),
            risk: .none, rawCode: nil, pendingValue: nil, lastConfirmedValue: value
        )
    }

    private func readOnlyFacts(_ display: DisplayFacts, transport: String) -> [CapabilityDescriptor] {
        let mode = CGDisplayCopyDisplayMode(display.displayID)
        let refresh = mode?.refreshRate ?? 0
        func fact(_ id: CapabilityIdentifier, _ label: String, _ value: String, order: Int) -> CapabilityDescriptor {
            CapabilityDescriptor(
                id: id, label: label, category: .display, kind: .text, access: .readOnly,
                unit: nil, evidence: .safelyProbed, currentValue: .text(value), freshness: .confirmed,
                route: .native, transport: transport,
                reliability: .init(successfulWrites: 0, failedWrites: 0, lastSuccess: nil, lastFailure: nil, provenance: "CoreGraphics active mode"),
                risk: .none, rawCode: nil, pendingValue: nil, lastConfirmedValue: .text(value), sortOrder: order
            )
        }
        return [
            fact(.resolution, "Resolution", "\(mode?.pixelWidth ?? 0) × \(mode?.pixelHeight ?? 0)", order: 40),
            fact(.refreshRate, "Refresh rate", refresh > 0 ? "\(Int(refresh.rounded())) Hz" : "Managed by macOS", order: 41)
        ]
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private extension String {
    /// "The display didn't answer a read." as it reads mid-sentence.
    var sentenceFragment: String {
        let trimmed = hasSuffix(".") ? String(dropLast()) : self
        return trimmed.prefix(1).lowercased() + trimmed.dropFirst()
    }
}
