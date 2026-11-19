import Foundation

/// A parsed MCCS capabilities string (the reply to VCP 0xF3), e.g.
/// `(prot(monitor)type(lcd)model(U2723QE)cmds(01 02 03 07 0C F3)vcp(10 12 14(05 08 0B) 60(0F 11 1B))mccs_ver(2.1))`.
/// Monitors format these loosely, so the parser accepts missing spaces, lowercase hex,
/// a missing outer wrapper and nested value lists, and ignores fields it doesn't need.
struct MCCSCapabilities: Equatable, Sendable {
    /// Reported VCP codes in the order the monitor listed them, each with its allowed
    /// values. An empty list means the code is continuous or its values weren't listed.
    var codes: [(code: UInt8, values: [UInt8])]
    var fields: [String: String]

    var model: String? { fields["model"] }
    var displayType: String? { fields["type"] }
    var mccsVersion: String? { fields["mccs_ver"] }
    func values(for code: UInt8) -> [UInt8]? { codes.first(where: { $0.code == code })?.values }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.fields == rhs.fields && lhs.codes.map(\.code) == rhs.codes.map(\.code) && lhs.codes.map(\.values) == rhs.codes.map(\.values)
    }

    /// Returns nil when the text has no `vcp(...)` list; that is "nothing reported", not "nothing supported".
    static func parse(_ raw: String) -> MCCSCapabilities? {
        // Real strings are well under 1 KB; anything far larger is noise from a bad read.
        guard raw.utf8.count <= 8192 else { return nil }
        var text = Substring(raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)))
        if text.first == "(", let close = matchingParen(in: text, openingAt: text.startIndex), text.index(after: close) == text.endIndex {
            text = text[text.index(after: text.startIndex)..<close]
        }
        let fields = topLevelFields(text)
        guard let vcp = fields["vcp"] else { return nil }
        return MCCSCapabilities(codes: parseVCPList(Substring(vcp)), fields: fields)
    }

    private static func topLevelFields(_ text: Substring) -> [String: String] {
        var fields: [String: String] = [:]
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index].isLetter || text[index] == "_" else { index = text.index(after: index); continue }
            let nameStart = index
            while index < text.endIndex, text[index].isLetter || text[index].isNumber || text[index] == "_" { index = text.index(after: index) }
            let name = text[nameStart..<index].lowercased()
            guard index < text.endIndex, text[index] == "(", let close = matchingParen(in: text, openingAt: index) else { continue }
            // Keep the first occurrence; some firmware repeats fields with junk.
            if fields[name] == nil { fields[name] = String(text[text.index(after: index)..<close]) }
            index = text.index(after: close)
        }
        return fields
    }

    private static func parseVCPList(_ text: Substring) -> [(code: UInt8, values: [UInt8])] {
        var result: [(code: UInt8, values: [UInt8])] = []
        var seen = Set<UInt8>()
        var index = text.startIndex
        while index < text.endIndex {
            if let (code, next) = hexByte(in: text, at: index) {
                index = next
                while index < text.endIndex, text[index] == " " { index = text.index(after: index) }
                var values: [UInt8] = []
                if index < text.endIndex, text[index] == "(", let close = matchingParen(in: text, openingAt: index) {
                    values = flatHexBytes(text[text.index(after: index)..<close])
                    index = text.index(after: close)
                }
                if seen.insert(code).inserted { result.append((code, values)) }
            } else {
                index = text.index(after: index)
            }
        }
        return result
    }

    /// Top-level values only; a nested group such as `DC(00(01 02) 03)` contributes 00 and 03.
    private static func flatHexBytes(_ text: Substring) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "(", let close = matchingParen(in: text, openingAt: index) {
                index = text.index(after: close)
            } else if let (byte, next) = hexByte(in: text, at: index) {
                if !bytes.contains(byte) { bytes.append(byte) }
                index = next
            } else {
                index = text.index(after: index)
            }
        }
        return bytes
    }

    private static func hexByte(in text: Substring, at index: Substring.Index) -> (UInt8, Substring.Index)? {
        guard text[index].isHexDigit else { return nil }
        let second = text.index(after: index)
        guard second < text.endIndex, text[second].isHexDigit,
              let byte = UInt8(String(text[index...second]), radix: 16) else { return nil }
        return (byte, text.index(after: second))
    }

    private static func matchingParen(in text: Substring, openingAt open: Substring.Index) -> Substring.Index? {
        var depth = 0
        var index = open
        while index < text.endIndex {
            if text[index] == "(" { depth += 1 }
            if text[index] == ")" { depth -= 1; if depth == 0 { return index } }
            index = text.index(after: index)
        }
        return nil
    }
}

/// How a reported code appears to people.
enum CapabilityPresentation: String, Codable, Sendable {
    /// A setting in the Digital OSD.
    case osd
    /// Listed only in Connection details: protocol plumbing, codes Glow can't interpret,
    /// and maintenance commands Glow deliberately doesn't offer.
    case connectionDetailsOnly
    /// Hidden on this display by the person, because it does nothing there. Like
    /// `connectionDetailsOnly` it leaves the OSD, the popover and scenes; Connection details
    /// labels it "Hidden by you" (ADR 0002, decision 8).
    case hiddenByYou
}

/// What a harmless read (Get VCP Feature) returned for one reported code.
enum ProbeResult: Equatable, Sendable {
    case read(current: UInt16, maximum: UInt16)
    /// The monitor answered that it doesn't support this code, contradicting its capability string.
    case unsupported
    case noResponse
}

/// Turns reported VCP codes into capability descriptors. Adding a monitor feature means
/// adding an entry here; the Digital OSD renders it with the shared controls.
enum CapabilityCatalog {
    enum Encoding: Sendable {
        case continuous(unit: String?)
        case options([UInt8: String])
        /// MCCS toggles use two non-zero codes (0x8D mute: 1 = muted, 2 = not muted).
        case toggle(on: UInt8, off: UInt8)
        case action
        /// A reading shown as text, such as gamma or hours used. Never written.
        case formatted(@Sendable (_ current: UInt16, _ maximum: UInt16) -> String)
    }

    struct Entry: Sendable {
        let code: UInt8
        let id: CapabilityIdentifier
        let label: String
        let category: CapabilityCategory
        let order: Int
        let encoding: Encoding
        let risk: DestructiveRisk
        let presentation: CapabilityPresentation
        /// Shown, never written, even when the display lists it.
        var isReadOnly = false

        /// Whether a read alone, with no capability report, is enough to offer the setting:
        /// only low-risk sliders and switches.
        var allowsUnlistedWrites: Bool {
            guard risk == .none, !isReadOnly, presentation == .osd else { return false }
            switch encoding {
            case .continuous, .toggle: return true
            case .options, .action, .formatted: return false
            }
        }
    }

    static let inputNames: [UInt8: String] = [
        0x01: "VGA 1", 0x02: "VGA 2", 0x03: "DVI 1", 0x04: "DVI 2",
        0x05: "Composite 1", 0x06: "Composite 2", 0x07: "S-Video 1", 0x08: "S-Video 2",
        0x09: "Tuner 1", 0x0A: "Tuner 2", 0x0B: "Tuner 3",
        0x0C: "Component 1", 0x0D: "Component 2", 0x0E: "Component 3",
        0x0F: "DisplayPort 1", 0x10: "DisplayPort 2", 0x11: "HDMI 1", 0x12: "HDMI 2"
    ]

    static let colorPresetNames: [UInt8: String] = [
        0x01: "sRGB", 0x02: "Native", 0x03: "4000 K", 0x04: "5000 K", 0x05: "6500 K",
        0x06: "7500 K", 0x07: "8200 K", 0x08: "9300 K", 0x09: "10000 K", 0x0A: "11500 K",
        0x0B: "Custom 1", 0x0C: "Custom 2", 0x0D: "Custom 3"
    ]

    static let pictureModeNames: [UInt8: String] = [
        0x00: "Standard", 0x01: "Productivity", 0x02: "Mixed", 0x03: "Movie", 0x04: "Custom",
        0x05: "Games", 0x06: "Sports", 0x07: "Professional", 0x08: "Standard, lower power",
        0x09: "Standard, low power", 0x0A: "Demonstration", 0xF0: "Dynamic contrast"
    ]

    static let powerNames: [UInt8: String] = [0x01: "On", 0x02: "Standby", 0x03: "Suspend", 0x04: "Off", 0x05: "Off (power switch)"]

    /// MCCS OSD language codes (VCP 0xCC).
    static let languageNames: [UInt8: String] = [
        0x01: "Chinese (traditional)", 0x02: "English", 0x03: "French", 0x04: "German", 0x05: "Italian",
        0x06: "Japanese", 0x07: "Korean", 0x08: "Portuguese (Portugal)", 0x09: "Russian", 0x0A: "Spanish",
        0x0B: "Swedish", 0x0C: "Turkish", 0x0D: "Chinese (simplified)", 0x0E: "Portuguese (Brazil)",
        0x0F: "Arabic", 0x10: "Bulgarian", 0x11: "Croatian", 0x12: "Czech", 0x13: "Danish", 0x14: "Dutch",
        0x15: "Estonian", 0x16: "Finnish", 0x17: "Greek", 0x18: "Hebrew", 0x19: "Hindi", 0x1A: "Hungarian",
        0x1B: "Latvian", 0x1C: "Lithuanian", 0x1D: "Norwegian", 0x1E: "Polish", 0x1F: "Romanian",
        0x20: "Serbian", 0x21: "Slovak", 0x22: "Slovenian", 0x23: "Thai", 0x24: "Ukrainian", 0x25: "Vietnamese"
    ]

    /// VCP 0x72: the low byte is the gamma, as (value + 100) / 100, so 0x78 is 2.2.
    static func gamma(current: UInt16) -> Double { (Double(current & 0xFF) + 100) / 100 }

    static func gammaText(current: UInt16, maximum: UInt16) -> String {
        gamma(current: current).formatted(.number.precision(.fractionLength(1...2)))
    }

    /// VCP 0xC0: hours powered on. Displays put the top byte of a three-byte count in the
    /// maximum's low byte.
    static func usageHours(current: UInt16, maximum: UInt16) -> Int { Int(maximum & 0xFF) << 16 | Int(current) }

    static func usageText(current: UInt16, maximum: UInt16) -> String {
        let hours = usageHours(current: current, maximum: maximum)
        return "\(hours.formatted()) \(hours == 1 ? "hour" : "hours")"
    }

    static let entries: [Entry] = [
        Entry(code: 0x10, id: .brightness, label: "Brightness", category: .essentials, order: 0, encoding: .continuous(unit: "%"), risk: .none, presentation: .osd),
        Entry(code: 0x12, id: .contrast, label: "Contrast", category: .essentials, order: 1, encoding: .continuous(unit: "%"), risk: .none, presentation: .osd),
        Entry(code: 0x62, id: .volume, label: "Speaker volume", category: .essentials, order: 2, encoding: .continuous(unit: "%"), risk: .none, presentation: .osd),
        Entry(code: 0x8D, id: .mute, label: "Mute speakers", category: .essentials, order: 3, encoding: .toggle(on: 0x01, off: 0x02), risk: .none, presentation: .osd),
        Entry(code: 0x60, id: .input, label: "Input", category: .display, order: 10, encoding: .options(inputNames), risk: .disruptive, presentation: .osd),
        Entry(code: 0x14, id: .preset, label: "Color preset", category: .display, order: 11, encoding: .options(colorPresetNames), risk: .none, presentation: .osd),
        Entry(code: 0xDC, id: .pictureMode, label: "Picture mode", category: .display, order: 12, encoding: .options(pictureModeNames), risk: .none, presentation: .osd),
        Entry(code: 0x87, id: .sharpness, label: "Sharpness", category: .display, order: 13, encoding: .continuous(unit: nil), risk: .none, presentation: .osd),
        Entry(code: 0x16, id: .redGain, label: "Red level", category: .display, order: 14, encoding: .continuous(unit: nil), risk: .none, presentation: .osd),
        Entry(code: 0x18, id: .greenGain, label: "Green level", category: .display, order: 15, encoding: .continuous(unit: nil), risk: .none, presentation: .osd),
        Entry(code: 0x1A, id: .blueGain, label: "Blue level", category: .display, order: 16, encoding: .continuous(unit: nil), risk: .none, presentation: .osd),
        Entry(code: 0x6C, id: .redBlackLevel, label: "Red black level", category: .display, order: 17, encoding: .continuous(unit: nil), risk: .none, presentation: .osd),
        Entry(code: 0x6E, id: .greenBlackLevel, label: "Green black level", category: .display, order: 18, encoding: .continuous(unit: nil), risk: .none, presentation: .osd),
        Entry(code: 0x70, id: .blueBlackLevel, label: "Blue black level", category: .display, order: 19, encoding: .continuous(unit: nil), risk: .none, presentation: .osd),
        // Makers encode gamma differently, so Glow shows it and leaves it alone.
        Entry(code: 0x72, id: .gamma, label: "Gamma", category: .display, order: 20, encoding: .formatted(gammaText), risk: .none, presentation: .osd, isReadOnly: true),
        Entry(code: 0xCC, id: .osdLanguage, label: "Menu language", category: .display, order: 25, encoding: .options(languageNames), risk: .none, presentation: .osd, isReadOnly: true),
        Entry(code: 0xD6, id: .power, label: "Display power", category: .display, order: 30, encoding: .options(powerNames), risk: .destructive, presentation: .osd),
        Entry(code: 0xC0, id: .usageTime, label: "Hours used", category: .display, order: 45, encoding: .formatted(usageText), risk: .none, presentation: .osd, isReadOnly: true),
        // Maintenance commands: real features, but one click can undo a person's monitor setup.
        Entry(code: 0x04, id: "factory-reset", label: "Restore factory settings", category: .display, order: 90, encoding: .action, risk: .destructive, presentation: .connectionDetailsOnly),
        Entry(code: 0x05, id: "reset-brightness-contrast", label: "Restore brightness and contrast", category: .display, order: 91, encoding: .action, risk: .destructive, presentation: .connectionDetailsOnly),
        Entry(code: 0x08, id: "reset-color", label: "Restore color settings", category: .display, order: 92, encoding: .action, risk: .destructive, presentation: .connectionDetailsOnly)
    ]

    /// Protocol housekeeping codes. They're reported constantly and mean nothing to people.
    static let housekeepingCodes: Set<UInt8> = [0x02, 0x52, 0xAC, 0xAE, 0xB2, 0xB6, 0xC6, 0xC8, 0xC9, 0xDF]

    /// MCCS's write-only commands: a Get VCP of one means nothing, so Glow never sends one.
    static let commandCodes: Set<UInt8> = [0x01, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0xB0]

    /// A reported code the catalog doesn't know, which Glow reads once with Get VCP and never
    /// writes (ADR 0002, decision 7). Housekeeping and commands are left alone.
    static func readsOnce(_ code: UInt8) -> Bool {
        entry(for: code) == nil && !housekeepingCodes.contains(code) && !commandCodes.contains(code)
    }

    /// The identifier of a reported code the catalog doesn't know: "vcp-e2".
    static func uncataloguedID(_ code: UInt8) -> CapabilityIdentifier {
        CapabilityIdentifier(rawValue: "vcp-" + String(format: "%02x", code))
    }

    /// The code behind an identifier from `uncataloguedID`, or nil for any other.
    static func uncataloguedCode(of id: CapabilityIdentifier) -> UInt8? {
        guard id.rawValue.hasPrefix("vcp-"), id.rawValue.count == 6 else { return nil }
        return UInt8(id.rawValue.dropFirst(4), radix: 16)
    }

    static func entry(for code: UInt8) -> Entry? { entries.first(where: { $0.code == code }) }
    static func entry(for id: CapabilityIdentifier) -> Entry? { entries.first(where: { $0.id == id }) }

    static func rawCodeLabel(_ code: UInt8) -> String { "VCP 0x" + String(format: "%02X", code) }

    /// Builds one descriptor per reported code. None are editable yet: evidence starts at
    /// "Reported, not tested" until `recordingProbe` sees a successful read.
    /// `manufacturerNames` names vendor-specific option codes (keyed by VCP code), for
    /// example a monitor that uses input 0x1B for USB-C; it comes from a manufacturer profile.
    static func descriptors(
        from capabilities: MCCSCapabilities,
        transport: String,
        manufacturerNames: [UInt8: [UInt8: String]] = [:]
    ) -> [CapabilityDescriptor] {
        let reliability = ReliabilityState(successfulWrites: 0, failedWrites: 0, lastSuccess: nil, lastFailure: nil, provenance: "Listed in the display's capability report")
        return capabilities.codes.compactMap { code, values in
            guard let entry = entry(for: code) else {
                guard !housekeepingCodes.contains(code) else { return nil }
                return CapabilityDescriptor(
                    id: uncataloguedID(code),
                    label: code >= 0xE0 ? "Manufacturer setting" : "Unrecognized setting",
                    category: .connectivity, kind: .text, access: .unavailable, unit: nil,
                    evidence: .reportedUninterpreted, currentValue: nil, freshness: .unknown,
                    route: .hardware, transport: transport, reliability: reliability, risk: .none,
                    rawCode: rawCodeLabel(code), pendingValue: nil, lastConfirmedValue: nil,
                    sortOrder: 1000 + Int(code), presentation: .connectionDetailsOnly
                )
            }
            return descriptor(for: entry, reportedValues: values, transport: transport, manufacturerNames: manufacturerNames[code] ?? [:], provenance: reliability.provenance)
        }
    }

    /// One catalog setting before any read: "Reported, not tested", with no value.
    static func descriptor(
        for entry: Entry, reportedValues: [UInt8], transport: String,
        manufacturerNames: [UInt8: String] = [:], provenance: String
    ) -> CapabilityDescriptor {
        let options = rawOptions(for: entry, reportedValues: reportedValues, manufacturerNames: manufacturerNames)
        return CapabilityDescriptor(
            id: entry.id, label: entry.label, category: entry.category,
            kind: kind(for: entry, options: options),
            access: entry.presentation != .osd ? .unavailable : entry.isReadOnly ? .readOnly : .readWrite,
            unit: unit(for: entry),
            evidence: .reportedOnly, currentValue: nil, freshness: .unknown,
            route: .hardware, transport: transport,
            reliability: ReliabilityState(successfulWrites: 0, failedWrites: 0, lastSuccess: nil, lastFailure: nil, provenance: provenance),
            risk: entry.risk, rawCode: rawCodeLabel(entry.code), pendingValue: nil, lastConfirmedValue: nil,
            sortOrder: entry.order, presentation: entry.presentation, rawOptions: options
        )
    }

    /// Option names for the values a monitor reported, falling back to the full standard
    /// list when it reported none. Codes nobody has named become "Other input 1", "Other
    /// input 2"…, so raw numbers stay in Connection details.
    static func rawOptions(for entry: Entry, reportedValues: [UInt8], manufacturerNames: [UInt8: String] = [:]) -> [RawOption] {
        guard case let .options(standardNames) = entry.encoding else { return [] }
        let names = standardNames.merging(manufacturerNames) { _, manufacturer in manufacturer }
        let codes = reportedValues.isEmpty ? standardNames.keys.sorted() : reportedValues
        var unnamed = 0
        return codes.map { code in
            if let name = names[code] { return RawOption(code: UInt16(code), name: name) }
            unnamed += 1
            return RawOption(code: UInt16(code), name: "\(otherPrefix(for: entry)) \(unnamed)")
        }
    }

    static func otherPrefix(for entry: Entry) -> String {
        entry.id == .input ? "Other input" : "Other \(entry.label.lowercased())"
    }

    private static func unit(for entry: Entry) -> String? {
        if case let .continuous(unit) = entry.encoding { return unit }
        return nil
    }

    private static func kind(for entry: Entry, options: [RawOption]) -> CapabilityKind {
        switch entry.encoding {
        case .continuous: .range(minimum: 0, maximum: 100, step: 1)
        case .options: .options(options.map(\.name))
        case .toggle: .toggle
        case .action: .action
        case .formatted: .text
        }
    }

    /// The raw value to send for a validated value, or nil if it can't be expressed.
    static func encode(_ value: CapabilityValue, for descriptor: CapabilityDescriptor) -> UInt16? {
        guard let entry = entry(for: descriptor.id), !entry.isReadOnly else { return nil }
        switch (entry.encoding, value) {
        case let (.continuous, .number(number)):
            guard number.isFinite, number >= 0, number <= Double(UInt16.max) else { return nil }
            return UInt16(number.rounded())
        case let (.options, .text(name)):
            return descriptor.rawOptions.first(where: { $0.name == name })?.code
        case let (.toggle(on, off), .boolean(isOn)):
            return UInt16(isOn ? on : off)
        default:
            return nil
        }
    }

    /// The value a raw reading represents, or nil when it isn't one the descriptor can name.
    static func decode(_ raw: UInt16, maximum: UInt16 = 0, for descriptor: CapabilityDescriptor) -> CapabilityValue? {
        guard let entry = entry(for: descriptor.id) else { return nil }
        switch entry.encoding {
        case .continuous:
            return .number(Double(raw))
        case .options:
            // Option codes live in the low byte; some monitors set the high byte.
            let code = raw & 0xFF
            return descriptor.rawOptions.first(where: { $0.code == code }).map { .text($0.name) }
        case let .toggle(on, off):
            let code = UInt8(raw & 0xFF)
            return code == on ? .boolean(true) : code == off ? .boolean(false) : nil
        case .action:
            return nil
        case let .formatted(format):
            return .text(format(raw, maximum))
        }
    }
}

extension CapabilityIdentifier {
    static let redBlackLevel: Self = "red-black-level"
    static let greenBlackLevel: Self = "green-black-level"
    static let blueBlackLevel: Self = "blue-black-level"
    static let gamma: Self = "gamma"
    static let osdLanguage: Self = "osd-language"
    static let usageTime: Self = "usage-time"
}

extension CapabilityDescriptor {
    /// Records what a harmless read showed. A successful read is the only thing that makes a
    /// reported setting editable; a refusal marks the report as contradicted.
    func recordingProbe(_ result: ProbeResult) -> CapabilityDescriptor {
        var updated = self
        switch result {
        case let .read(current, maximum):
            if case let .range(minimum, _, step) = kind, maximum > 0 {
                updated.kind = .range(minimum: minimum, maximum: Double(maximum), step: step)
            }
            if case .options = kind, CapabilityCatalog.decode(current, maximum: maximum, for: self) == nil,
               let entry = CapabilityCatalog.entry(for: id) {
                // The display is using an option it didn't list. It came from the display, so
                // offering it back is safe; give it a neutral name like any other unnamed code.
                let unnamed = rawOptions.filter { $0.name.hasPrefix(CapabilityCatalog.otherPrefix(for: entry)) }.count
                updated.rawOptions.append(RawOption(code: current & 0xFF, name: "\(CapabilityCatalog.otherPrefix(for: entry)) \(unnamed + 1)"))
                updated.kind = .options(updated.rawOptions.map(\.name))
            }
            guard let value = CapabilityCatalog.decode(current, maximum: maximum, for: updated) else {
                // It answered, but with a value Glow can't name; changing it could pick the wrong mode.
                updated.evidence = .contradictory
                updated.reliability.lastFailure = "The display reported a value Glow doesn't recognize."
                return updated
            }
            updated.evidence = .safelyProbed
            updated.currentValue = value
            updated.lastConfirmedValue = value
            updated.freshness = .confirmed
            updated.reliability.provenance = "Listed in the display's capability report and read successfully"
        case .unsupported:
            updated.evidence = .contradictory
            updated.freshness = .unknown
            updated.reliability.lastFailure = "Listed, but the display said it doesn't support it."
        case .noResponse:
            updated.freshness = .unknown
            updated.reliability.lastFailure = "The display didn't answer a read."
        }
        return updated
    }

    var requiresConfirmation: Bool { risk != .none }

    /// The code behind a setting the display reported, from its raw-code label.
    var reportedCode: UInt8? {
        guard let rawCode, rawCode.hasPrefix("VCP 0x") else { return nil }
        return UInt8(rawCode.dropFirst(6), radix: 16)
    }

    /// Records one Get VCP of a reported code the catalog doesn't know: the raw current and
    /// maximum, as text, for Connection details. Evidence and access don't change, so the
    /// setting stays uninterpreted and unwritable whatever comes back (ADR 0002, decision 7).
    /// nil means the read never happened.
    func recordingRawReading(_ result: ProbeResult?) -> CapabilityDescriptor {
        var updated = self
        switch result {
        case let .read(current, maximum)?:
            updated.currentValue = .text(DDCProbe.describe(.read(current: current, maximum: maximum)))
            updated.lastConfirmedValue = updated.currentValue
            updated.freshness = .confirmed
            updated.reliability.lastFailure = nil
        case .unsupported?:
            updated.currentValue = nil
            updated.freshness = .unknown
            updated.reliability.lastFailure = "Listed, but the display said it doesn’t support it."
        case .noResponse?:
            updated.currentValue = nil
            updated.freshness = .unknown
            updated.reliability.lastFailure = "The display didn’t answer a read."
        case nil:
            updated.freshness = updated.currentValue == nil ? .unknown : .stale
            updated.reliability.lastFailure = updated.currentValue == nil ? "Not read: discovery ran out of time." : nil
        }
        return updated
    }
}
