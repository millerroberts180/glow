import Foundation

/// The byte-level DDC/CI link to one monitor. `DDCLink` over IOAVService is the Apple
/// silicon one (I2C, chip 0x37, source 0x51); Intel's IOFramebuffer I2C isn't built. See
/// docs/adr/0001-capability-driven-control.md.
protocol DDCTransport: Sendable {
    /// The reply to VCP 0xF3, or a thrown error when the monitor doesn't answer.
    func capabilityString() async throws -> String
    /// Get VCP Feature: harmless, changes nothing on the monitor.
    func read(code: UInt8) async throws -> ProbeResult
    /// Set VCP Feature.
    func write(code: UInt8, value: UInt16) async throws
}

/// Builds a display's capability profile: parse what it reports, translate through the
/// catalog, then read each setting once. Only a successful read makes a setting editable.
enum CapabilityDiscovery {
    /// `readReported` gives the one raw read of each reported code the catalog doesn't know
    /// (nil when it wasn't read); without it those codes are listed unread.
    static func profile(
        capabilityString: String?,
        transport: String,
        manufacturerNames: [UInt8: [UInt8: String]] = [:],
        read: (UInt8) -> ProbeResult,
        readReported: ((UInt8) -> ProbeResult?)? = nil
    ) -> [CapabilityDescriptor] {
        guard let capabilityString, let parsed = MCCSCapabilities.parse(capabilityString) else { return [] }
        return CapabilityCatalog.descriptors(from: parsed, transport: transport, manufacturerNames: manufacturerNames)
            .map { descriptor in
                if let readReported, let code = descriptor.reportedCode, CapabilityCatalog.readsOnce(code) {
                    return descriptor.recordingRawReading(readReported(code))
                }
                guard let code = probeCode(for: descriptor) else { return descriptor }
                return descriptor.recordingProbe(read(code))
            }
            .sorted { ($0.presentation == .osd ? 0 : 1, $0.sortOrder) < ($1.presentation == .osd ? 0 : 1, $1.sortOrder) }
    }

    static func profile(
        using link: any DDCTransport,
        transport: String,
        manufacturerNames: [UInt8: [UInt8: String]] = [:]
    ) async -> [CapabilityDescriptor] {
        guard let raw = try? await link.capabilityString(), let parsed = MCCSCapabilities.parse(raw) else { return [] }
        var readings: [UInt8: ProbeResult] = [:]
        for (code, _) in parsed.codes where isProbeable(code) {
            readings[code] = (try? await link.read(code: code)) ?? .noResponse
        }
        return profile(capabilityString: raw, transport: transport, manufacturerNames: manufacturerNames) { readings[$0] ?? .noResponse }
    }

    /// A display that sent no capability report but answers reads: one read of each setting
    /// the catalog knows. What answers is "Answered, not listed by the display". Only
    /// low-risk sliders and switches become editable; nothing listed the rest, so a setting
    /// that could switch inputs or turn the display off stays read-only (ADR 0001 addendum).
    static func unlistedProfile(transport: String, read: (UInt8) -> ProbeResult) -> [CapabilityDescriptor] {
        unlistedCodes.compactMap { code -> CapabilityDescriptor? in
            guard let entry = CapabilityCatalog.entry(for: code) else { return nil }
            let result = read(code)
            // Not listed and not answering: nothing says the display has it.
            guard case .read = result else { return nil }
            var descriptor = CapabilityCatalog.descriptor(for: entry, reportedValues: [], transport: transport, provenance: "Not in a capability report")
                .recordingProbe(result)
            // An answer Glow can't name. Nothing listed it, so "Reported, but test failed"
            // would be untrue; the raw reading stays in Connection details.
            guard descriptor.evidence == .safelyProbed else { return nil }
            descriptor.access = entry.allowsUnlistedWrites ? .readWrite : .readOnly
            descriptor.evidence = .answeredUnlisted
            descriptor.reliability.provenance = "Not in a capability report; the display answered a read"
            return descriptor
        }
    }

    /// Every code the fallback reads, in catalog order.
    static var unlistedCodes: [UInt8] { CapabilityCatalog.entries.map(\.code).filter(isProbeable) }

    /// Codes worth one read: settings shown in the OSD. Actions and anything Glow won't
    /// offer are never touched.
    static func isProbeable(_ code: UInt8) -> Bool {
        guard let entry = CapabilityCatalog.entry(for: code), entry.presentation == .osd else { return false }
        if case .action = entry.encoding { return false }
        return true
    }

    private static func probeCode(for descriptor: CapabilityDescriptor) -> UInt8? {
        guard let code = CapabilityCatalog.entry(for: descriptor.id)?.code, isProbeable(code) else { return nil }
        return code
    }
}

/// Sends one setting over DDC/CI and reads it back, translating through the catalog. A
/// hardware `DisplayAdapter` delegates to this; `DisplayWritePipeline` supplies validation,
/// per-display ordering, retries and the read-back comparison.
struct DDCControlChannel: Sendable {
    let link: any DDCTransport

    func write(_ value: CapabilityValue, descriptor: CapabilityDescriptor) async throws {
        guard let code = CapabilityCatalog.entry(for: descriptor.id)?.code,
              let raw = CapabilityCatalog.encode(value, for: descriptor) else { throw ControlError.notWritable }
        try await link.write(code: code, value: raw)
    }

    func read(_ descriptor: CapabilityDescriptor) async throws -> CapabilityValue {
        guard let code = CapabilityCatalog.entry(for: descriptor.id)?.code else { throw ControlError.notWritable }
        let result: ProbeResult
        do {
            result = try await link.read(code: code)
        } catch DDCError.readFailed {
            // The connection gave up waiting: as transient as silence.
            throw ControlError.timedOut
        }
        switch result {
        case let .read(current, maximum):
            guard let value = CapabilityCatalog.decode(current, maximum: maximum, for: descriptor) else { throw ControlError.readBackMismatch }
            return value
        case .unsupported:
            throw ControlError.notWritable
        case .noResponse:
            // Transient: the pipeline may retry this once.
            throw ControlError.timedOut
        }
    }
}
