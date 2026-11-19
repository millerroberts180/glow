#if DEBUG
import Foundation

/// A monitor's DDC/CI firmware played in software: an `I2CBus` that checks each request the
/// way a monitor does and answers in real reply bytes. Debug builds can show these in place
/// of this Mac's displays (`SimulatedDisplayAdapter`), and tests run Glow's whole DDC path
/// against them. Nothing here reaches IOKit or a real display.
///
/// What a model supports comes from a capability report a real monitor sent, quoted with
/// where it was published. Its quirks are assigned, not measured: each plays a kind of
/// monitor or connection one of Glow's transport profiles is for.
final class SimulatedMonitor: I2CBus, @unchecked Sendable {
    /// One request the firmware accepted: framed, checksummed and sent from an address it
    /// answers.
    enum Request: Hashable, Sendable, CustomStringConvertible {
        case getVCP(UInt8)
        case setVCP(UInt8, UInt16)
        case saveSettings
        case capabilities(offset: UInt16)

        var description: String {
            switch self {
            case let .getVCP(code): "Get VCP 0x\(DDCPacket.hex(code))"
            case let .setVCP(code, value): "Set VCP 0x\(DDCPacket.hex(code)) = \(value)"
            case .saveSettings: "Save Current Settings"
            case let .capabilities(offset): "Capabilities Request at \(offset)"
            }
        }
    }

    /// The requests the firmware didn't act on, and the replies it spoiled.
    struct Counters: Hashable, Sendable {
        /// Bad framing, a bad checksum or an opcode it doesn't know.
        var rejected = 0
        /// Sent from a source address it doesn't answer.
        var ignored = 0
        /// Arrived while it was still busy with a Set VCP; answered with the null message.
        var droppedWhileBusy = 0
        /// Reads that came before the reply was ready, and got nothing.
        var earlyReads = 0
        /// Replies sent with a bad checksum on purpose (`Quirks.garblesEvery`).
        var garbled = 0
    }

    /// One code in the report's vcp(…) list.
    struct Feature: Hashable, Sendable {
        /// The values listed for it; nil for a continuous setting.
        let values: [UInt8]?
    }

    let model: Model
    let clock: SimulatedClock
    /// The serial queue every link to this monitor shares (`DDCBus`).
    let busID: UInt64
    let features: [UInt8: Feature]

    private let lock = NSLock()
    private var values: [UInt8: UInt16]
    /// Set VCPs the firmware hasn't applied yet (`Quirks.readBackLag`).
    private var scheduled: [UInt8: (value: UInt16, at: ContinuousClock.Instant)] = [:]
    private var reply: (bytes: [UInt8], readyAt: ContinuousClock.Instant)?
    private var busyUntil: ContinuousClock.Instant?
    private var repliesSent = 0
    private var accepted: [Request] = []
    private var counts = Counters()

    init(_ model: Model, clock: SimulatedClock = .real) {
        self.model = model
        self.clock = clock
        busID = Self.nextBusID()
        features = Self.features(in: model.capabilityString)
        values = Self.startingValues(model, features: features)
    }

    /// Every request it accepted, oldest first.
    var log: [Request] { lock.withLock { accepted } }

    var counters: Counters { lock.withLock { counts } }

    /// Each Set VCP it accepted, in order.
    var writes: [(code: UInt8, value: UInt16)] {
        log.compactMap { request in
            guard case let .setVCP(code, value) = request else { return nil }
            return (code, value)
        }
    }

    /// What a Get VCP of `code` reports now; nil for a code it doesn't have.
    func value(of code: UInt8) -> UInt16? {
        let now = clock.now
        return lock.withLock {
            applyDue(at: now)
            return values[code]
        }
    }

    /// A change made with the monitor's own buttons, which the next read finds.
    func setOnDisplay(_ code: UInt8, to value: UInt16) {
        lock.withLock {
            guard features[code] != nil else { return }
            values[code] = value
            scheduled[code] = nil
        }
    }

    func clearLog() {
        lock.withLock {
            accepted = []
            counts = Counters()
        }
    }

    /// A DDC link to this monitor on `profile`, timed by its clock.
    func link(profile: DDCTransportProfile) -> DDCLink {
        DDCLink(session: session(profile: profile), busID: busID)
    }

    /// The exchanges themselves, for tests that drive the bus directly.
    func session(profile: DDCTransportProfile) -> DDCSession {
        DDCSession(bus: self, profile: profile, pause: { [clock] in clock.pause($0) }, now: { [clock] in clock.now })
    }

    // MARK: - I2CBus

    func write(_ packet: [UInt8], source: UInt8) -> Int32 {
        let now = clock.now
        lock.withLock { receive(packet, source: source, at: now) }
        // The bus takes any bytes; only the reply shows whether the monitor understood them.
        return 0
    }

    func read(count: Int) -> Result<[UInt8], DDCError> {
        let now = clock.now
        let nothing = [UInt8](repeating: 0, count: count)
        return lock.withLock {
            guard let pending = reply else { return .success(nothing) }
            guard now >= pending.readyAt else {
                counts.earlyReads += 1
                return .success(nothing)
            }
            reply = nil
            return .success(Array((pending.bytes + nothing).prefix(count)))
        }
    }

    // MARK: - Firmware

    /// Codes a monitor reports but won't let a host change.
    private static let readOnlyCodes: Set<UInt8> = [0xAC, 0xAE, 0xB2, 0xB6, 0xC0, 0xC6, 0xC8, 0xC9, 0xDF]
    /// The reset commands, and the codes each puts back to how the monitor started.
    private static let resets: [UInt8: Set<UInt8>?] = [
        0x04: nil,
        0x05: [0x10, 0x12],
        0x08: [0x14, 0x16, 0x18, 0x1A, 0x6C, 0x6E, 0x70]
    ]

    private func receive(_ packet: [UInt8], source: UInt8, at now: ContinuousClock.Instant) {
        guard model.quirks.sources.contains(source) else {
            counts.ignored += 1
            return
        }
        if let busyUntil, now < busyUntil {
            counts.droppedWhileBusy += 1
            stage(Self.reply([]), at: now)
            return
        }
        guard let request = Self.request(in: packet, source: source) else {
            counts.rejected += 1
            return
        }
        accepted.append(request)
        applyDue(at: now)
        switch request {
        case let .getVCP(code):
            stage(getVCPReply(code), at: now)
        case let .setVCP(code, value):
            // Set VCP has no reply.
            reply = nil
            set(code, value, at: now)
            if model.quirks.busyAfterSet > .zero { busyUntil = now + model.quirks.busyAfterSet }
        case .saveSettings:
            reply = nil
        case let .capabilities(offset):
            stage(capabilitiesReply(offset), at: now)
        }
    }

    private func set(_ code: UInt8, _ value: UInt16, at now: ContinuousClock.Instant) {
        if let codes = Self.resets[code] {
            for (reset, start) in Self.startingValues(model, features: features) where codes?.contains(reset) ?? true {
                values[reset] = start
                scheduled[reset] = nil
            }
            return
        }
        guard let feature = features[code], !Self.readOnlyCodes.contains(code) else { return }
        let applied: UInt16
        if let options = feature.values {
            // A value it didn't list is ignored, as monitors do.
            guard value >> 8 == 0, options.contains(UInt8(value)) else { return }
            applied = value
        } else {
            applied = min(value, maximum(of: code))
        }
        // Asking again for the change already on its way doesn't restart the wait.
        if scheduled[code]?.value == applied { return }
        if scheduled[code] == nil, values[code] == applied { return }
        if model.quirks.readBackLag > .zero {
            scheduled[code] = (applied, now + model.quirks.readBackLag)
        } else {
            values[code] = applied
        }
    }

    private func applyDue(at now: ContinuousClock.Instant) {
        for (code, change) in scheduled where change.at <= now {
            values[code] = change.value
            scheduled[code] = nil
        }
    }

    private func maximum(of code: UInt8) -> UInt16 {
        if let options = features[code]?.values { return UInt16(options.count) }
        // Hours used puts the top byte of its count in the maximum's low byte.
        return code == 0xC0 ? 0 : 100
    }

    private func getVCPReply(_ code: UInt8) -> [UInt8] {
        guard let current = values[code] else { return Self.reply([0x02, 0x01, code, 0x00, 0, 0, 0, 0]) }
        let maximum = maximum(of: code)
        return Self.reply([0x02, 0x00, code, 0x00, UInt8(maximum >> 8), UInt8(maximum & 0xFF), UInt8(current >> 8), UInt8(current & 0xFF)])
    }

    private func capabilitiesReply(_ offset: UInt16) -> [UInt8] {
        // A monitor with nothing to say sends the null message.
        guard model.quirks.sendsCapabilities else { return Self.reply([]) }
        let text = Array(model.capabilityString.utf8)
        let report = model.quirks.padsLastFragment ? text + [UInt8](repeating: 0, count: 32 - text.count % 32) : text
        let start = min(Int(offset), report.count)
        return Self.reply([0xE3, UInt8(offset >> 8), UInt8(offset & 0xFF)] + report[start..<min(start + 32, report.count)])
    }

    /// Holds a reply until `Quirks.replyDelay` has passed, spoiling one now and then if
    /// the model does.
    private func stage(_ bytes: [UInt8], at now: ContinuousClock.Instant) {
        var bytes = bytes
        repliesSent += 1
        if let every = model.quirks.garblesEvery, repliesSent % every == 0 {
            bytes[bytes.count - 1] ^= 0xFF
            counts.garbled += 1
        }
        reply = (bytes, now + model.quirks.replyDelay)
    }

    /// The request in `packet`, or nil when firmware would throw it away. Written apart
    /// from `DDCPacket`, so the tests check Glow's bytes against another reading of the
    /// standard rather than against themselves.
    private static func request(in packet: [UInt8], source: UInt8) -> Request? {
        guard let first = packet.first, first & 0x80 != 0 else { return nil }
        let length = Int(first & 0x7F)
        // The checksum covers the display's address 0x6E, the source byte and the body.
        guard length >= 1, packet.count == length + 2,
              packet.dropLast().reduce(0x6E ^ source, ^) == packet[length + 1] else { return nil }
        let payload = Array(packet[1...length])
        switch (payload[0], payload.count) {
        case (0x01, 2): return .getVCP(payload[1])
        case (0x03, 4): return .setVCP(payload[1], UInt16(payload[2]) << 8 | UInt16(payload[3]))
        case (0x0C, 1): return .saveSettings
        case (0xF3, 3): return .capabilities(offset: UInt16(payload[1]) << 8 | UInt16(payload[2]))
        default: return nil
        }
    }

    /// The display's address, length, payload and checksum, which starts from 0x50.
    private static func reply(_ payload: [UInt8]) -> [UInt8] {
        let body = [0x6E, 0x80 | UInt8(payload.count)] + payload
        return body + [body.reduce(0x50, ^)]
    }

    /// The codes in a report's vcp(…) list and the values listed for each. Like
    /// `request(in:source:)`, it's apart from Glow's own parser (`MCCSCapabilities`).
    static func features(in report: String) -> [UInt8: Feature] {
        let text = Array(report.lowercased().utf8)
        let key = Array("vcp(".utf8)
        guard let open = text.indices.first(where: { text[$0...].starts(with: key) }) else { return [:] }
        var features: [UInt8: Feature] = [:]
        var last: UInt8?
        var listed: [UInt8]?
        var digits: [UInt8] = []
        for byte in text[(open + key.count)...] {
            if let digit = hexDigit(byte) {
                digits.append(digit)
                guard digits.count == 2 else { continue }
                let code = digits[0] << 4 | digits[1]
                digits = []
                if listed != nil {
                    listed?.append(code)
                } else {
                    features[code] = Feature(values: nil)
                    last = code
                }
                continue
            }
            digits = []
            switch byte {
            case UInt8(ascii: "("):
                listed = []
            case UInt8(ascii: ")"):
                guard let values = listed else { return features }
                if let last { features[last] = Feature(values: values) }
                listed = nil
            default:
                break
            }
        }
        return features
    }

    private static func hexDigit(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        default: nil
        }
    }

    /// The model's values, then the first listed value of any other non-continuous code
    /// and 50 for any other continuous one.
    private static func startingValues(_ model: Model, features: [UInt8: Feature]) -> [UInt8: UInt16] {
        Dictionary(uniqueKeysWithValues: features.map { code, feature in
            (code, model.start[code] ?? feature.values.map { UInt16($0.first ?? 0) } ?? 50)
        })
    }

    private static let busLock = NSLock()
    nonisolated(unsafe) private static var lastBusID: UInt64 = 0x5100_0000_0000_0000

    /// Apart from every IORegistry ID, and new for each monitor.
    private static func nextBusID() -> UInt64 {
        busLock.withLock {
            lastBusID += 1
            return lastBusID
        }
    }
}

/// The time a simulated monitor keeps. In the app it's the real clock, and the host really
/// waits. In tests it's virtual: it moves only when the host waits or the test moves it, so a
/// three-second discovery takes no time and goes the same way every run.
final class SimulatedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var virtualNow: ContinuousClock.Instant?

    private init(virtualNow: ContinuousClock.Instant?) {
        self.virtualNow = virtualNow
    }

    static let real = SimulatedClock(virtualNow: nil)

    /// One for each monitor: a host waiting on one monitor's bus doesn't move another's time.
    static func virtual() -> SimulatedClock { SimulatedClock(virtualNow: .now) }

    var now: ContinuousClock.Instant { lock.withLock { virtualNow } ?? .now }

    /// The host's wait: a real sleep, or the virtual clock moving on.
    func pause(_ duration: Duration) {
        if !advance(by: duration) { usleep(duration.microseconds) }
    }

    /// Moves a virtual clock on; false for the real one, which moves by itself.
    @discardableResult
    func advance(by duration: Duration) -> Bool {
        lock.withLock {
            guard let now = virtualNow else { return false }
            virtualNow = now + duration
            return true
        }
    }
}

// MARK: - Models

extension SimulatedMonitor {
    /// One kind of monitor: a real capability report and the quirks it's given.
    struct Model: Hashable, Sendable, Identifiable {
        let id: String
        let name: String
        let vendorID: UInt32
        /// Made up, and apart from any real monitor's, so no saved setting is mistaken for
        /// one of a real display.
        let productID: UInt32
        let serialNumber: UInt32
        /// The report exactly as the real monitor sent it.
        let capabilityString: String
        /// Where that report was published.
        let source: String
        /// Values at power-on. A listed code not here starts at its first listed value, or 50.
        var start: [UInt8: UInt16] = [:]
        var quirks = Quirks()
        /// What the quirks stand for, for Connection details.
        let behaviour: String
    }

    struct Quirks: Hashable, Sendable {
        /// How long after its request a reply is ready. Standard timing reads at 50 ms.
        var replyDelay: Duration = .milliseconds(40)
        /// The source addresses it answers: 0x51 is the standard host address.
        var sources: Set<UInt8> = [0x51]
        /// False: it answers VCP 0xF3 with the null message, but still answers reads.
        var sendsCapabilities = true
        /// Ends the report with NULs in its last fragment instead of an empty fragment.
        var padsLastFragment = false
        /// A change shows in reads only this long after its Set VCP.
        var readBackLag: Duration = .zero
        /// After a Set VCP, every request this soon gets the null message.
        var busyAfterSet: Duration = .zero
        /// Every this-many replies, one goes out with a bad checksum.
        var garblesEvery: Int?
    }
}

extension SimulatedMonitor.Model {
    /// Dell UltraSharp U3011. Standard timing, but a change shows in reads 90 ms after it's
    /// set, later than Glow's first read-back at 60 ms.
    static let dellU3011 = Self(
        id: "dell-u3011", name: "Dell U3011", vendorID: 0x10AC, productID: 0xF301, serialNumber: 0x5130_0001,
        capabilityString: "(prot(monitor)type(lcd)model(U3011)cmds(01 02 03 07 0C E3 F3)vcp(02 04 05 06 08 10 12 14(01 05 08 0B 0C) 16 18 1A 52 60(01 03 04 0C 0F 11 12) AC AE B2 B6 C6 C8 C9 D6(01 04 05) DC(00 02 03 04 05) DF FD)mccs_ver(2.1)mswhql(1))",
        source: "https://www.ddcutil.com/cap_u3011_verbose_output/",
        start: [0x10: 75, 0x12: 75, 0x14: 0x05, 0x16: 50, 0x18: 50, 0x1A: 50, 0x60: 0x0F, 0xD6: 0x01, 0xDC: 0x00],
        quirks: .init(readBackLag: .milliseconds(90)),
        behaviour: "Standard timing; a change shows in reads 90 ms after it’s set"
    )

    /// AOC C24G2, the same G2 gaming line as the AOC 32G2WG3 used in testing, with its report
    /// in the compact form that has no spaces. It answers 120 ms after a request, after
    /// standard timing has already read, and ignores everything for 100 ms after a change.
    static let aocC24G2 = Self(
        id: "aoc-c24g2", name: "AOC C24G2", vendorID: 0x05E3, productID: 0xF302, serialNumber: 0x5130_0002,
        capabilityString: "(prot(monitor)type(lcd)model(C24G2)cmds(010203070C4EF3E3)vcp(020405080B0C101214(010506080B)16181A6C6E70ACAEB6C0C6C8C9CA60(010F1112)CC(0102030405060708090A0B0D1214161E)D6(0104)DFDC(000B0C0D0E0F10)86(0205)628D(0102)FF)mswhql(1)asset_eep(40)mccs_ver(2.2))",
        source: "https://github.com/rockowitz/ddcutil/issues/398",
        start: [0x10: 50, 0x12: 50, 0x14: 0x0B, 0x60: 0x11, 0x62: 30, 0x8D: 0x02, 0xC0: 2_917, 0xCC: 0x02, 0xD6: 0x01, 0xDC: 0x00],
        quirks: .init(replyDelay: .milliseconds(120), busyAfterSet: .milliseconds(100)),
        behaviour: "Answers 120 ms after a request, so only slower timing hears it; busy for 100 ms after a change"
    )

    /// LG 27MD5KL (UltraFine 5K), which names itself "RTK" in its report. It answers only
    /// the alternate source address 0x50, and pads the report's last fragment with NULs.
    static let lg27MD5KL = Self(
        id: "lg-27md5kl", name: "LG 27MD5KL", vendorID: 0x1E6D, productID: 0xF303, serialNumber: 0x5130_0003,
        capabilityString: "(prot(monitor)type(LCD)model(RTK)cmds(01 02 03 07 0C E3 F3)vcp(02 04 05 06 08 0B 0C 10 12 14(01 02 04 05 06 08 0B) 16 18 1A 52 60(01 03 04 0F 10 11 12) 87 AC AE B2 B6 C6 C8 CA CC(01 02 03 04 06 0A 0D) D6(01 04 05) DF FD FF)mswhql(1)asset_eep(40)mccs_ver(2.2))",
        source: "https://github.com/rockowitz/ddcutil/issues/213",
        start: [0x10: 60, 0x12: 70, 0x14: 0x05, 0x60: 0x0F, 0x87: 50, 0xCC: 0x02, 0xD6: 0x01],
        quirks: .init(sources: [0x50], padsLastFragment: true),
        behaviour: "Answers only the alternate address (source 0x50); pads the report’s last fragment with NULs"
    )

    /// LG 29UM69G. Its firmware here keeps the report to itself, answering VCP 0xF3 with the
    /// null message, but answers reads; every fifth reply has a bad checksum. The report
    /// still decides which codes it answers.
    static let lg29UM69G = Self(
        id: "lg-29um69g", name: "LG 29UM69G", vendorID: 0x1E6D, productID: 0xF304, serialNumber: 0x5130_0004,
        capabilityString: "(prot(monitor)type(lcd)UM69cmds(01 02 03 0C E3 F3)vcp(02 04 05 08 10 12 14(05 08 0B ) 16 18 1A 52 60( 11 0F 10) AC AE B2 B6 C0 C6 C8 C9 D6(01 04) DF 62 8D F4 F5(01 02 03 04) F6(00 01 02) 4D 4E 4F 15(01 06 11 13 14 15 18 19 20 22 23 24 28 29 32 48) F7(00 01 02 03) F8(00 01) F9 E4 E5 E6 E7 E8 E9 EA EB EF FA(00 01) FD(00 01) FE(00 01 02) FF)mccs_ver(2.1)mswhql(1))",
        source: "https://github.com/rockowitz/ddcutil/issues/100",
        start: [0x10: 40, 0x12: 60, 0x14: 0x05, 0x60: 0x11, 0x62: 20, 0x8D: 0x02, 0xC0: 812, 0xD6: 0x01],
        quirks: .init(sendsCapabilities: false, garblesEvery: 5),
        behaviour: "Sends no capability report but answers reads; every fifth reply is garbled"
    )

    static let all: [Self] = [.dellU3011, .aocC24G2, .lg27MD5KL, .lg29UM69G]

    static func named(_ id: String) -> Self? { all.first { $0.id == id } }
}
#endif
