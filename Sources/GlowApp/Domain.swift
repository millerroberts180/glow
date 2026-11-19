import Foundation

struct PersistentDisplayIdentity: Hashable, Codable, Sendable, Identifiable {
    let vendorID: UInt32
    let productID: UInt32
    let serialNumber: UInt32
    var id: String { "\(vendorID)-\(productID)-\(serialNumber)" }
}

struct ConnectionIdentity: Hashable, Codable, Sendable, Identifiable {
    let displayID: UInt32
    let transport: String
    let generation: UInt64
    var id: String { "\(displayID)-\(transport)-\(generation)" }
}

struct CapabilityIdentifier: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { rawValue = value }

    static let brightness: Self = "brightness"
    static let contrast: Self = "contrast"
    static let volume: Self = "volume"
    static let mute: Self = "mute"
    static let input: Self = "input-source"
    static let preset: Self = "picture-preset"
    static let power: Self = "power"
    static let resolution: Self = "resolution"
    static let refreshRate: Self = "refresh-rate"
    static let hdr: Self = "hdr"
    static let usbPower: Self = "usb-c-power"
    static let pictureMode: Self = "picture-mode"
    static let sharpness: Self = "sharpness"
    static let redGain: Self = "red-gain"
    static let greenGain: Self = "green-gain"
    static let blueGain: Self = "blue-gain"
}

/// Digital OSD sections, in the order Settings › Displays shows them.
enum CapabilityCategory: String, Codable, CaseIterable, Sendable {
    case essentials = "Essentials"
    case display = "Display"
    case connectivity = "Connectivity"
    case glow = "Glow"
}

enum CapabilityAccess: String, Codable, Sendable {
    case readWrite, readOnly, writeOnly, unavailable
    var canRead: Bool { self == .readWrite || self == .readOnly }
    var canWrite: Bool { self == .readWrite || self == .writeOnly }
}

enum CapabilityKind: Hashable, Codable, Sendable {
    case range(minimum: Double, maximum: Double, step: Double)
    case options([String])
    case toggle
    case action
    case text
}

enum CapabilityValue: Hashable, Codable, Sendable, CustomStringConvertible {
    case number(Double)
    case text(String)
    case boolean(Bool)

    var description: String {
        switch self {
        case .number(let value): value.formatted(.number.precision(.fractionLength(0...1)))
        case .text(let value): value
        case .boolean(let value): value ? "On" : "Off"
        }
    }
}

enum SupportEvidence: String, Codable, Sendable {
    case reportedOnly = "Reported, not tested"
    case safelyProbed = "Tested successfully"
    case contradictory = "Reported, but test failed"
    case inferred = "Inferred from connection"
    /// Listed by the monitor, but Glow doesn't know what the code means, so it never writes it.
    case reportedUninterpreted = "Reported, not interpreted"
    case unavailable = "Not available"
    /// The display sent no capability report, but answered a read of this code.
    case answeredUnlisted = "Answered, not listed by the display"
}

enum ControlRoute: String, Codable, Sendable, CaseIterable {
    case native, hardware, software, unavailable

    var userLabel: String {
        switch self {
        case .native: "Native control"
        case .hardware: "Hardware control"
        case .software: "Software dimming"
        case .unavailable: "Not available on this connection"
        }
    }
}

enum ValueFreshness: String, Codable, Sendable { case confirmed, stale, unknown }
enum DestructiveRisk: String, Codable, Sendable { case none, disruptive, destructive }

struct ReliabilityState: Hashable, Codable, Sendable {
    var successfulWrites: Int
    var failedWrites: Int
    var lastSuccess: Date?
    var lastFailure: String?
    var provenance: String

    var summary: String {
        let total = successfulWrites + failedWrites
        guard total > 0 else { return "Not yet tested" }
        return "\(successfulWrites) of \(total) writes confirmed"
    }
}

struct CapabilityDescriptor: Identifiable, Hashable, Codable, Sendable {
    let id: CapabilityIdentifier
    var label: String
    var category: CapabilityCategory
    var kind: CapabilityKind
    var access: CapabilityAccess
    var unit: String?
    var evidence: SupportEvidence
    var currentValue: CapabilityValue?
    var freshness: ValueFreshness
    var route: ControlRoute
    var transport: String
    var reliability: ReliabilityState
    var risk: DestructiveRisk
    var rawCode: String?
    var pendingValue: CapabilityValue?
    var lastConfirmedValue: CapabilityValue?
    /// Position within its OSD section; catalog entries set this so new codes land in a sensible place.
    var sortOrder: Int = 0
    var presentation: CapabilityPresentation = .osd
    /// The raw code behind each option name, for adapters that send codes (input 0x0F = "DisplayPort 1").
    var rawOptions: [RawOption] = []
    /// When a reread last found this setting changed outside Glow, for the "Changed on the
    /// display" mark; cleared after a minute (ADR 0002, decision 4).
    var changedOnDisplayAt: Date?

    var isSafelyEditable: Bool {
        access.canWrite && route != .unavailable && presentation == .osd
            && evidence != .reportedOnly && evidence != .contradictory && evidence != .reportedUninterpreted
    }

    func validated(_ proposed: CapabilityValue) throws -> CapabilityValue {
        guard isSafelyEditable else { throw ControlError.notWritable }
        switch (kind, proposed) {
        case let (.range(minimum, maximum, step), .number(value)):
            guard minimum.isFinite, maximum.isFinite, step.isFinite, step > 0,
                  minimum <= maximum, value.isFinite else { throw ControlError.invalidValue }
            let clamped = min(maximum, max(minimum, value))
            let snapped = minimum + ((clamped - minimum) / step).rounded() * step
            return .number(min(maximum, max(minimum, snapped)))
        case let (.options(options), .text(value)) where options.contains(value): return proposed
        case (.toggle, .boolean): return proposed
        case (.action, _): return proposed
        case (.text, .text): return proposed
        default: throw ControlError.invalidValue
        }
    }
}

struct RawOption: Hashable, Codable, Sendable {
    let code: UInt16
    let name: String
}

struct DisplaySnapshot: Identifiable, Hashable, Codable, Sendable {
    let identity: PersistentDisplayIdentity
    var connection: ConnectionIdentity
    var name: String
    var isBuiltIn: Bool
    var isConnected: Bool
    var capabilities: [CapabilityDescriptor]
    var isAppearanceMatched: Bool
    var isDemo: Bool
    /// How Glow reached this display, in words, for Connection details.
    var connectionNotes: [String] = []
    /// Discovery is still asking this display over DDC/CI what it supports. Its settings
    /// arrive when it answers or stays silent.
    var isChecking = false
    var id: PersistentDisplayIdentity { identity }

    /// The Digital OSD: every setting this connection exposes, grouped and ordered, without
    /// anything that belongs only in Connection details. Empty sections are left out.
    var osdSections: [(category: CapabilityCategory, capabilities: [CapabilityDescriptor])] {
        CapabilityCategory.allCases.compactMap { category in
            let members = capabilities
                .filter { $0.category == category && $0.presentation == .osd }
                .sorted { $0.sortOrder < $1.sortOrder }
            return members.isEmpty ? nil : (category, members)
        }
    }

    /// How Glow controls this display overall, for its card: the route of its brightness
    /// control, or the best route any setting has.
    var primaryRoute: ControlRoute {
        if let brightness = capabilities.first(where: { $0.id == .brightness }) { return brightness.route }
        let routes = Set(capabilities.filter(\.isSafelyEditable).map(\.route))
        return [ControlRoute.native, .hardware, .software].first(where: routes.contains) ?? .unavailable
    }
}

enum CapabilityControlStyle: Equatable, Sendable {
    case slider, picker, toggle, button, readOnly, unavailable
}

enum CapabilityRenderer {
    static func style(for descriptor: CapabilityDescriptor) -> CapabilityControlStyle {
        guard descriptor.access != .unavailable, descriptor.route != .unavailable else { return .unavailable }
        guard descriptor.isSafelyEditable else { return .readOnly }
        return switch descriptor.kind {
        case .range: .slider
        case .options: .picker
        case .toggle: .toggle
        case .action: .button
        case .text: .readOnly
        }
    }
}

enum ControlError: Error, Equatable, LocalizedError, Sendable {
    case displayDisconnected, staleTopology, notWritable, invalidValue, timedOut, readBackMismatch
    /// Writes are paused while displays sleep, wake or reconfigure.
    case suspended
    case adapter(String)

    var errorDescription: String? {
        switch self {
        case .displayDisconnected: "This display disconnected."
        case .staleTopology: "The display connection changed before the update completed."
        case .notWritable: "This setting cannot be changed on this connection."
        case .invalidValue: "That value is not supported by this display."
        case .timedOut: "The display did not respond in time."
        case .readBackMismatch: "The display did not confirm the requested value."
        case .suspended: "Glow paused changes while your displays reconnect."
        case .adapter(let message): message
        }
    }
}

struct CalibrationPoint: Hashable, Codable, Sendable {
    let reference: Double
    let display: Double
}

struct BrightnessCurve: Hashable, Codable, Sendable {
    let points: [CalibrationPoint]

    init(points: [CalibrationPoint]) {
        var lastReference = -Double.infinity
        var lastDisplay = 0.0
        self.points = points.sorted { $0.reference < $1.reference }.map { point in
            let reference = max(lastReference, min(1, max(0, point.reference)))
            let display = max(lastDisplay, min(1, max(0, point.display)))
            lastReference = reference
            lastDisplay = display
            return CalibrationPoint(reference: reference, display: display)
        }
    }

    func value(for reference: Double) -> Double {
        guard let first = points.first else { return min(1, max(0, reference)) }
        let target = min(1, max(0, reference))
        if target <= first.reference { return first.display }
        for pair in zip(points, points.dropFirst()) where target <= pair.1.reference {
            let span = pair.1.reference - pair.0.reference
            guard span > 0 else { return pair.1.display }
            let fraction = (target - pair.0.reference) / span
            return pair.0.display + fraction * (pair.1.display - pair.0.display)
        }
        return points.last?.display ?? target
    }
}

// Scenes (`GlowScene`, `SceneResult`) live in `Scenes/`.
