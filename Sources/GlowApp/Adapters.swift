import AppKit
import CoreGraphics
import Foundation

@MainActor
protocol DisplayAdapter: Sendable {
    var name: String { get }
    func discover(generation: UInt64) async -> [DisplaySnapshot]
    /// Discovery that shows its work: `progress` gets every display as it stands, first with
    /// external displays still being checked (`isChecking`), then again as each one finishes.
    /// Returns the finished displays, as `discover(generation:)` does.
    func discover(generation: UInt64, progress: @escaping @MainActor @Sendable ([DisplaySnapshot]) -> Void) async -> [DisplaySnapshot]
    func write(_ value: CapabilityValue, capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws
    func read(capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws -> CapabilityValue
    /// What DDC/CI discovery tried for one display, for Connection details.
    func discoveryLog(for display: PersistentDisplayIdentity) -> DDCDiscoveryLog?
    /// When this adapter last finished writing to a display: now while a write is under way,
    /// nil if it never has. Rereads keep clear of it (ADR 0002, decision 2).
    func lastWrite(to display: PersistentDisplayIdentity) -> ContinuousClock.Instant?
    /// One Get VCP of a code the display reported and the catalog doesn't know, for
    /// Connection details. Nothing ever writes such a code.
    func readReported(code: UInt8, display: PersistentDisplayIdentity) async throws -> ProbeResult
    /// The values first read from a display this launch, before Glow changed anything
    /// (ADR 0001, decision 9). Only settings it read and could change are kept.
    func startingValues(for display: PersistentDisplayIdentity) -> [CapabilityIdentifier: CapabilityValue]
}

extension DisplayAdapter {
    func discover(generation: UInt64, progress: @escaping @MainActor @Sendable ([DisplaySnapshot]) -> Void) async -> [DisplaySnapshot] {
        await discover(generation: generation)
    }
    func discoveryLog(for display: PersistentDisplayIdentity) -> DDCDiscoveryLog? { nil }
    func startingValues(for display: PersistentDisplayIdentity) -> [CapabilityIdentifier: CapabilityValue] { [:] }
    func lastWrite(to display: PersistentDisplayIdentity) -> ContinuousClock.Instant? { nil }
    func readReported(code: UInt8, display: PersistentDisplayIdentity) async throws -> ProbeResult { throw ControlError.notWritable }
}

/// When an adapter's writes to each display started and finished, so rereads can keep
/// clear of them.
struct WriteActivity {
    private var underWay: [PersistentDisplayIdentity: Int] = [:]
    private var finished: [PersistentDisplayIdentity: ContinuousClock.Instant] = [:]

    mutating func begin(_ display: PersistentDisplayIdentity) { underWay[display, default: 0] += 1 }

    mutating func end(_ display: PersistentDisplayIdentity) {
        underWay[display] = max(0, (underWay[display] ?? 1) - 1)
        finished[display] = .now
    }

    func last(_ display: PersistentDisplayIdentity) -> ContinuousClock.Instant? {
        (underWay[display] ?? 0) > 0 ? .now : finished[display]
    }
}

@MainActor
final class MockDisplayAdapter: DisplayAdapter {
    let name = "Glow Demo Adapter"
    private var values: [PersistentDisplayIdentity: [CapabilityIdentifier: CapabilityValue]] = [:]
    private let makeDisplays: (UInt64) -> [DisplaySnapshot]
    private var activity = WriteActivity()
    private var reads: [String: Int] = [:]
    private var writes: [String: Int] = [:]
    /// How long a demo read takes. Tests set it to zero.
    var readDelay: Duration = .milliseconds(35)
    /// Displays that never answer a read, like a monitor with DDC/CI turned off.
    var silentDisplays: Set<PersistentDisplayIdentity> = []
    /// What each demo display answers to a Get VCP of a code the catalog doesn't know.
    var reportedReadings: [PersistentDisplayIdentity: [UInt8: ProbeResult]] = [DemoData.dellIdentity: DemoData.dellReadings]

    /// The three demo displays, unless a snapshot asks for others.
    init(displays: @escaping (UInt64) -> [DisplaySnapshot] = DemoData.displays) {
        makeDisplays = displays
    }

    func discoveryLog(for display: PersistentDisplayIdentity) -> DDCDiscoveryLog? {
        DemoData.discoveryLogs[display]
    }

    func discover(generation: UInt64) async -> [DisplaySnapshot] {
        let displays = makeDisplays(generation)
        values = Dictionary(uniqueKeysWithValues: displays.map { display in
            (display.identity, Dictionary(uniqueKeysWithValues: display.capabilities.compactMap { descriptor in
                descriptor.currentValue.map { (descriptor.id, $0) }
            }))
        })
        return displays
    }

    func write(_ value: CapabilityValue, capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws {
        activity.begin(display)
        defer { activity.end(display) }
        writes["\(display.id):\(capability.rawValue)", default: 0] += 1
        try await Task.sleep(for: .milliseconds(90))
        guard values[display] != nil else { throw ControlError.displayDisconnected }
        values[display]?[capability] = value
    }

    func read(capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws -> CapabilityValue {
        reads["\(display.id):\(capability.rawValue)", default: 0] += 1
        if readDelay > .zero { try await Task.sleep(for: readDelay) }
        guard !silentDisplays.contains(display) else { throw ControlError.timedOut }
        guard let value = values[display]?[capability] else { throw ControlError.notWritable }
        return value
    }

    func lastWrite(to display: PersistentDisplayIdentity) -> ContinuousClock.Instant? { activity.last(display) }

    func readReported(code: UInt8, display: PersistentDisplayIdentity) async throws -> ProbeResult {
        guard CapabilityCatalog.readsOnce(code) else { throw ControlError.notWritable }
        reads["\(display.id):\(CapabilityCatalog.uncataloguedID(code).rawValue)", default: 0] += 1
        if readDelay > .zero { try await Task.sleep(for: readDelay) }
        guard !silentDisplays.contains(display) else { throw ControlError.timedOut }
        return reportedReadings[display]?[code] ?? .noResponse
    }

    /// Demo mode's "changed on the display": the value a person set with the monitor's own
    /// buttons, which the next reread finds.
    func simulateChangeOnDisplay(_ value: CapabilityValue, capability: CapabilityIdentifier, display: PersistentDisplayIdentity) {
        guard values[display] != nil else { return }
        values[display]?[capability] = value
    }

    /// How many times a setting was read, or written, on a display, for tests.
    func readCount(_ capability: CapabilityIdentifier, on display: PersistentDisplayIdentity) -> Int {
        reads["\(display.id):\(capability.rawValue)"] ?? 0
    }

    func writeCount(_ capability: CapabilityIdentifier, on display: PersistentDisplayIdentity) -> Int {
        writes["\(display.id):\(capability.rawValue)"] ?? 0
    }

    var totalWrites: Int { writes.values.reduce(0, +) }
    var totalReads: Int { reads.values.reduce(0, +) }
}

enum DemoData {
    static func descriptor(
        _ id: CapabilityIdentifier, _ label: String, _ category: CapabilityCategory,
        _ kind: CapabilityKind, _ value: CapabilityValue?, _ route: ControlRoute,
        access: CapabilityAccess = .readWrite, evidence: SupportEvidence = .safelyProbed,
        unit: String? = nil, rawCode: String? = nil, risk: DestructiveRisk = .none,
        provenance: String = "Demo response with confirmed read-back"
    ) -> CapabilityDescriptor {
        CapabilityDescriptor(
            id: id, label: label, category: category, kind: kind, access: access, unit: unit,
            evidence: evidence, currentValue: value, freshness: value == nil ? .unknown : .confirmed,
            route: route, transport: route == .native ? "Internal" : "USB-C through dock",
            reliability: .init(successfulWrites: 0, failedWrites: 0, lastSuccess: nil, lastFailure: nil, provenance: "Demo adapter; no physical connection test. \(provenance)"),
            risk: risk, rawCode: rawCode, pendingValue: nil, lastConfirmedValue: value
        )
    }

    /// A capability report in the shape a Dell U2723QE-class monitor returns. It is demo
    /// data, not a capture from a physical monitor.
    static let dellCapabilityString = "(prot(monitor)type(LCD)model(U2723QE)cmds(01 02 03 07 0C E3 F3)vcp(02 04 05 08 10 12 14(01 04 05 08 0B) 16 18 1A 52 60(0F 11 12 1B) 62 87 8D(01 02) AC AE B2 B6 C6 C8 C9 D6(01 04 05) DC(00 03 05) DF E0 E1 E2(00 1D 02 04) F0(00 05) F1 F2)mswhql(1)asset_eep(40)mccs_ver(2.1))"

    /// What the demo monitor answers to one harmless read of each code.
    static let dellReadings: [UInt8: ProbeResult] = [
        0x10: .read(current: 68, maximum: 100), 0x12: .read(current: 78, maximum: 100),
        0x62: .read(current: 35, maximum: 100), 0x8D: .read(current: 2, maximum: 2),
        0x60: .read(current: 0x1B, maximum: 0), 0x14: .read(current: 0x01, maximum: 0),
        0xDC: .read(current: 0x00, maximum: 0), 0x87: .read(current: 50, maximum: 100),
        0x16: .read(current: 50, maximum: 100), 0x18: .read(current: 50, maximum: 100), 0x1A: .read(current: 50, maximum: 100),
        // Reported, then refused: the OSD must show this as a failed test, not a control.
        0xD6: .unsupported,
        // Reported codes the catalog doesn't know: read once, shown raw in Connection details.
        0xE0: .read(current: 0, maximum: 1), 0xE1: .read(current: 0, maximum: 100),
        0xE2: .read(current: 0x1D, maximum: 0), 0xF0: .read(current: 0x05, maximum: 0),
        0xF1: .unsupported
    ]

    static let macIdentity = PersistentDisplayIdentity(vendorID: 1552, productID: 40978, serialNumber: 1)
    static let dellIdentity = PersistentDisplayIdentity(vendorID: 4268, productID: 41200, serialNumber: 783245)
    static let lgIdentity = PersistentDisplayIdentity(vendorID: 7789, productID: 23305, serialNumber: 1001)
    static let unlistedIdentity = PersistentDisplayIdentity(vendorID: 0x05E3, productID: 0x1000, serialNumber: 2002)

    /// A monitor that sends no capability report but answers reads. Not one of the three
    /// demo displays; the Connection details snapshot shows it, to check the fallback.
    static let unlistedReadings: [UInt8: ProbeResult] = [
        0x10: .read(current: 60, maximum: 100), 0x12: .read(current: 50, maximum: 100),
        0x62: .read(current: 20, maximum: 100), 0x8D: .read(current: 2, maximum: 2),
        0x60: .read(current: 0x0F, maximum: 0), 0x14: .read(current: 0x05, maximum: 0),
        0x87: .read(current: 5, maximum: 10), 0x72: .read(current: 0x78, maximum: 0),
        0xCC: .read(current: 0x02, maximum: 0), 0xD6: .read(current: 0x01, maximum: 0),
        0xC0: .read(current: 1_234, maximum: 0)
    ]

    static func unlistedDisplay(generation: UInt64) -> DisplaySnapshot {
        let transport = "DisplayPort through hub"
        // The same fallback path the hardware adapter takes when a report never comes.
        let answered = CapabilityDiscovery.unlistedProfile(transport: transport) { unlistedReadings[$0] ?? .noResponse }
            .map { descriptor in
                var descriptor = descriptor
                descriptor.reliability.provenance = "Demo adapter; no physical connection test. \(descriptor.reliability.provenance)"
                return descriptor
            }
        return DisplaySnapshot(
            identity: unlistedIdentity, connection: .init(displayID: 4, transport: transport, generation: generation),
            name: "Demo monitor without a report", isBuiltIn: false, isConnected: true,
            capabilities: answered + [
                descriptor(.resolution, "Resolution", .display, .text, .text("2560 × 1440"), .native, access: .readOnly),
                descriptor(.refreshRate, "Refresh rate", .display, .text, .text("144 Hz"), .native, access: .readOnly)
            ].ordered(from: 40), isAppearanceMatched: false, isDemo: true,
            connectionNotes: [
                "Demo display: no physical connection test",
                "DDC/CI profile: \(DDCTransportProfile.standard.summary)",
                "No capability report, so Glow read each setting it knows. \(answered.count) answered."
            ]
        )
    }

    /// What discovery would have logged for each demo display. Demo logs time nothing.
    static let discoveryLogs: [PersistentDisplayIdentity: DDCDiscoveryLog] = {
        let reportedCodes = MCCSCapabilities.parse(dellCapabilityString)?.codes.map(\.code) ?? []
        let dellCodes = reportedCodes.filter(CapabilityDiscovery.isProbeable) + reportedCodes.filter(CapabilityCatalog.readsOnce)
        let dell = DDCDiscoveryLog(
            attempts: [.init(profile: "Standard", request: "capability report", answered: true, detail: "\(dellCapabilityString.utf8.count) bytes")],
            workingProfile: .standard, capabilityString: dellCapabilityString,
            readings: dellCodes.map { .init(code: $0, result: DDCProbe.describe(dellReadings[$0] ?? .noResponse)) }
        )
        let silent = "The display took too long to answer."
        let lg = DDCDiscoveryLog(
            attempts: [
                .init(profile: "Standard", request: "capability report", answered: false, detail: silent),
                .init(profile: "Standard", request: "Get VCP 0x10 (brightness)", answered: false, detail: "no response"),
                .init(profile: "Slower timing", request: "Get VCP 0x10 (brightness)", answered: false, detail: "no response"),
                .init(profile: "Alternate address", request: "Get VCP 0x10 (brightness)", answered: false, detail: "no response")
            ],
            capabilityProblem: silent
        )
        let unlisted = DDCDiscoveryLog(
            attempts: [
                .init(profile: "Standard", request: "capability report", answered: false, detail: silent),
                .init(profile: "Standard", request: "Get VCP 0x10 (brightness)", answered: true, detail: DDCProbe.describe(unlistedReadings[0x10] ?? .noResponse))
            ],
            workingProfile: .standard, capabilityProblem: silent,
            readings: CapabilityDiscovery.unlistedCodes.map { .init(code: $0, result: DDCProbe.describe(unlistedReadings[$0] ?? .noResponse)) }
        )
        return [dellIdentity: dell, lgIdentity: lg, unlistedIdentity: unlisted]
    }()

    static func displays(generation: UInt64) -> [DisplaySnapshot] {
        let mac = macIdentity
        let dell = dellIdentity
        let lg = lgIdentity
        let dellTransport = "USB-C through dock"
        // The Dell's OSD comes out of the same parse → catalog → probe path a hardware
        // adapter uses; only the bytes are canned.
        let reported = CapabilityDiscovery.profile(
            capabilityString: dellCapabilityString,
            transport: dellTransport,
            manufacturerNames: [0x60: [0x1B: "USB-C"]],
            read: { dellReadings[$0] ?? .noResponse },
            readReported: { dellReadings[$0] ?? .noResponse }
        ).map { descriptor in
            var descriptor = descriptor
            descriptor.reliability.provenance = "Demo adapter; no physical connection test. \(descriptor.reliability.provenance)"
            return descriptor
        }
        return [
            DisplaySnapshot(
                identity: mac, connection: .init(displayID: 1, transport: "Internal", generation: generation),
                name: "MacBook Pro", isBuiltIn: true, isConnected: true,
                capabilities: [
                    descriptor(.brightness, "Brightness", .essentials, .range(minimum: 0, maximum: 100, step: 1), .number(72), .native, unit: "%"),
                    descriptor(.hdr, "High dynamic range", .display, .toggle, .boolean(true), .native, access: .readOnly, provenance: "CoreGraphics display mode"),
                    descriptor(.resolution, "Resolution", .display, .text, .text("3024 × 1964"), .native, access: .readOnly),
                    descriptor(.refreshRate, "Refresh rate", .display, .text, .text("ProMotion · up to 120 Hz"), .native, access: .readOnly)
                ].ordered(from: 20), isAppearanceMatched: true, isDemo: true
            ),
            DisplaySnapshot(
                identity: dell, connection: .init(displayID: 2, transport: dellTransport, generation: generation),
                name: "Dell U2723QE", isBuiltIn: false, isConnected: true,
                capabilities: reported + [
                    descriptor(.resolution, "Resolution", .display, .text, .text("3840 × 2160"), .native, access: .readOnly),
                    descriptor(.refreshRate, "Refresh rate", .display, .text, .text("60 Hz"), .native, access: .readOnly),
                    descriptor(.hdr, "High dynamic range", .display, .toggle, .boolean(false), .native, access: .readOnly),
                    descriptor(.usbPower, "USB-C power delivery", .connectivity, .text, .text("90 W available"), .native, access: .readOnly, evidence: .inferred, provenance: "Demo USB-C connection profile")
                ].ordered(from: 20), isAppearanceMatched: true, isDemo: true
            ),
            DisplaySnapshot(
                identity: lg, connection: .init(displayID: 3, transport: "HDMI through adapter", generation: generation),
                name: "LG UltraFine 27", isBuiltIn: false, isConnected: true,
                capabilities: [
                    // No capability report crosses this adapter, so Glow dims the picture itself
                    // and says so, rather than claiming hardware brightness.
                    descriptor(.brightness, "Brightness", .essentials, .range(minimum: 0, maximum: 100, step: 1), .number(80), .software, evidence: .inferred, unit: "%", provenance: "The display didn't answer over this HDMI adapter; Glow dims the picture instead"),
                    descriptor(.volume, "Speaker volume", .essentials, .range(minimum: 0, maximum: 100, step: 1), nil, .unavailable, access: .unavailable, evidence: .unavailable, unit: "%", rawCode: "VCP 0x62", provenance: "No reply over this connection"),
                    descriptor(.resolution, "Resolution", .display, .text, .text("3840 × 2160"), .native, access: .readOnly),
                    descriptor(.refreshRate, "Refresh rate", .display, .text, .text("60 Hz"), .native, access: .readOnly)
                ].ordered(from: 0), isAppearanceMatched: false, isDemo: true
            )
        ]
    }
}

private extension Array where Element == CapabilityDescriptor {
    /// Keeps hand-listed descriptors in the order written, after any catalog entries.
    func ordered(from base: Int) -> [CapabilityDescriptor] {
        enumerated().map { offset, descriptor in
            var descriptor = descriptor
            descriptor.sortOrder = base + offset
            return descriptor
        }
    }
}

actor DisplayWritePipeline {
    private var topologyGeneration: UInt64 = 0
    private var lockedDisplays: Set<PersistentDisplayIdentity> = []
    /// Writes waiting for a display's lock, first come first served.
    private var waiters: [PersistentDisplayIdentity: [(id: UInt64, resume: CheckedContinuation<Void, Error>)]] = [:]
    private var nextWaiter: UInt64 = 0
    private var isSuspended = false

    func setTopologyGeneration(_ generation: UInt64) { topologyGeneration = generation }

    /// While displays sleep, wake or reconfigure, a DDC write can land on the wrong monitor
    /// or wedge its controller, so writes fail fast with `.suspended` instead of queueing.
    func setSuspended(_ suspended: Bool) { isSuspended = suspended }

    /// Writes `value` and reads it back, trying once more if the reply is late or differs.
    /// With `readBack` false it writes once and returns the validated value unconfirmed: a
    /// step in a run whose last value `confirm` checks.
    func write(
        descriptor: CapabilityDescriptor,
        value: CapabilityValue,
        display: DisplaySnapshot,
        adapter: any DisplayAdapter,
        readBack: Bool = true
    ) async throws -> CapabilityValue {
        let startGeneration = display.connection.generation
        let validated = try descriptor.validated(value)
        guard !isSuspended else { throw ControlError.suspended }
        guard startGeneration == topologyGeneration else { throw ControlError.staleTopology }
        try await lock(display.identity)
        defer { unlock(display.identity) }

        guard readBack else {
            guard !isSuspended else { throw ControlError.suspended }
            try await adapter.write(validated, capability: descriptor.id, display: display.identity)
            guard startGeneration == topologyGeneration else { throw ControlError.staleTopology }
            return validated
        }
        return try await confirmed(validated, descriptor: descriptor, display: display, adapter: adapter, startGeneration: startGeneration, writeFirst: true)
    }

    /// Reads back the last value of a run that `write(readBack: false)` already sent. If the
    /// reply is late or differs, it writes the value again and reads once more.
    func confirm(
        descriptor: CapabilityDescriptor,
        value: CapabilityValue,
        display: DisplaySnapshot,
        adapter: any DisplayAdapter
    ) async throws -> CapabilityValue {
        let startGeneration = display.connection.generation
        let validated = try descriptor.validated(value)
        guard !isSuspended else { throw ControlError.suspended }
        guard startGeneration == topologyGeneration else { throw ControlError.staleTopology }
        try await lock(display.identity)
        defer { unlock(display.identity) }
        return try await confirmed(validated, descriptor: descriptor, display: display, adapter: adapter, startGeneration: startGeneration, writeFirst: false)
    }

    private func confirmed(
        _ validated: CapabilityValue,
        descriptor: CapabilityDescriptor,
        display: DisplaySnapshot,
        adapter: any DisplayAdapter,
        startGeneration: UInt64,
        writeFirst: Bool
    ) async throws -> CapabilityValue {
        var lastError: Error = ControlError.timedOut
        for attempt in 0..<2 {
            do {
                guard !isSuspended else { throw ControlError.suspended }
                if writeFirst || attempt > 0 {
                    try await adapter.write(validated, capability: descriptor.id, display: display.identity)
                }
                let confirmed = try await adapter.read(capability: descriptor.id, display: display.identity)
                guard startGeneration == topologyGeneration else { throw ControlError.staleTopology }
                guard confirmed == validated else { throw ControlError.readBackMismatch }
                return confirmed
            } catch let error as ControlError {
                lastError = error
                // Retrying a stale or invalid request can target a newly connected display
                // or repeat a setting the adapter has already rejected. Only transient
                // response failures are safe to retry.
                switch error {
                case .timedOut, .readBackMismatch:
                    continue
                default:
                    throw error
                }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// One write at a time per display, in the order they asked.
    private func lock(_ identity: PersistentDisplayIdentity) async throws {
        guard lockedDisplays.contains(identity) else {
            lockedDisplays.insert(identity)
            return
        }
        nextWaiter &+= 1
        let id = nextWaiter
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (resume: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    resume.resume(throwing: CancellationError())
                } else {
                    waiters[identity, default: []].append((id, resume))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id, for: identity) }
        }
    }

    /// Hands the lock straight to the next writer waiting for the display, if there is one.
    private func unlock(_ identity: PersistentDisplayIdentity) {
        guard var queue = waiters[identity], !queue.isEmpty else {
            lockedDisplays.remove(identity)
            return
        }
        let next = queue.removeFirst()
        waiters[identity] = queue.isEmpty ? nil : queue
        next.resume.resume()
    }

    private func cancelWaiter(_ id: UInt64, for identity: PersistentDisplayIdentity) {
        guard let index = waiters[identity]?.firstIndex(where: { $0.id == id }),
              let waiter = waiters[identity]?.remove(at: index) else { return }
        if waiters[identity]?.isEmpty == true { waiters[identity] = nil }
        waiter.resume.resume(throwing: CancellationError())
    }
}
