import Foundation

/// How one connection's DDC/CI link behaves (ADR 0001, decision 7). The defaults are the
/// standard; anything else is a fact about that connection and shows in Connection details.
/// Timing comes from MonitorControl's measured defaults (`Arm64DDC.swift:92-117`).
struct DDCTransportProfile: Hashable, Sendable {
    /// The host address in each request: 0x51, or 0x50 for the alternate address some
    /// monitors answer on.
    var sourceAddress: UInt8 = 0x51
    /// How many times each request is sent.
    var sendCount = 1
    /// Pause before each send.
    var writeWait: Duration = .milliseconds(10)
    /// Pause between a request and reading its reply.
    var readWait: Duration = .milliseconds(50)
    /// DDC/CI asks hosts to leave 50 ms after Set VCP before the next message.
    var settleAfterSet: Duration = .milliseconds(50)
    /// Extra attempts after a failed exchange.
    var retries = 4
    var retryWait: Duration = .milliseconds(20)
    /// Retries stop once one exchange has taken this long. A bus that blocks for seconds
    /// before refusing a read won't answer a retry either.
    var retryWindow: Duration = .seconds(1)
    var ignoresReadChecksum = false
    /// Send Save Current Settings after each write. Off: most monitors keep values anyway,
    /// and it wears their memory.
    var savesAfterWrite = false

    static let standard = DDCTransportProfile()
    /// For monitors and adapters that answer late: each request sent twice, longer waits,
    /// more tries.
    static let slow = DDCTransportProfile(
        sendCount: 2, writeWait: .milliseconds(20), readWait: .milliseconds(200),
        retries: 6, retryWait: .milliseconds(100), retryWindow: .seconds(3)
    )
    /// Some monitors answer only when the host uses source address 0x50 (ADR 0001, decision 8).
    static let alternate = DDCTransportProfile(sourceAddress: 0x50)
    /// What discovery tries, in order, until a display answers.
    static let ladder: [DDCTransportProfile] = [.standard, .slow, .alternate]

    /// The profile's name in Connection details.
    var name: String {
        switch self {
        case .standard: "Standard"
        case .slow: "Slower timing"
        case .alternate: "Alternate address"
        default: "Custom"
        }
    }

    /// Each setting that differs from the standard, in words, for Connection details.
    var differencesFromStandard: [String] {
        let standard = Self.standard
        var notes: [String] = []
        if sourceAddress != standard.sourceAddress { notes.append("Uses the alternate address (source 0x\(DDCPacket.hex(sourceAddress)))") }
        if sendCount != standard.sendCount { notes.append("Sends each request \(sendCount) times") }
        if writeWait != standard.writeWait { notes.append("Waits \(writeWait.milliseconds) ms before sending") }
        if readWait != standard.readWait { notes.append("Waits \(readWait.milliseconds) ms for a reply") }
        if settleAfterSet != standard.settleAfterSet { notes.append("Waits \(settleAfterSet.milliseconds) ms after a change") }
        if retries != standard.retries { notes.append("Tries \(retries + 1) times") }
        if retryWait != standard.retryWait { notes.append("Waits \(retryWait.milliseconds) ms between tries") }
        if retryWindow != standard.retryWindow { notes.append("Keeps trying for up to \(retryWindow.milliseconds) ms") }
        if ignoresReadChecksum { notes.append("Accepts replies with a bad checksum") }
        if savesAfterWrite { notes.append("Saves settings on the display after each change") }
        return notes
    }

    var summary: String {
        let differences = differencesFromStandard
        return differences.isEmpty
            ? "Standard DDC/CI (source 0x51, one send, checksums checked)"
            : differences.joined(separator: "; ")
    }
}

extension Duration {
    var milliseconds: Int64 { components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000 }
    var microseconds: UInt32 { UInt32(clamping: components.seconds * 1_000_000 + components.attoseconds / 1_000_000_000_000) }
}

/// Why a DDC exchange failed, in words people can act on.
enum DDCError: Error, Equatable, LocalizedError, Sendable {
    /// macOS doesn't offer the private I2C calls Glow needs.
    case interfaceMissing(String)
    case sendFailed(Int32)
    /// The connection gave up waiting for a reply.
    case readFailed(Int32)
    case badChecksum
    case unexpectedReply(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .interfaceMissing(let name): "This Mac doesn't offer \(name), so Glow can't talk to the display directly."
        case .sendFailed(let code): "The display connection refused the request (IOReturn 0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case .readFailed(let code): "The display didn't reply; the connection gave up waiting (IOReturn 0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case .badChecksum: "The display's reply was garbled."
        case .unexpectedReply(let detail): "The display gave an unexpected reply: \(detail)."
        case .timedOut: "The display took too long to answer."
        }
    }
}

/// Builds DDC/CI requests and checks replies. Pure byte work, so every rule here is tested
/// without a monitor. Requests go to I2C address 0x37; the first byte on the wire after the
/// address is the source byte, which IOAVService takes as its data-address argument.
enum DDCPacket {
    static let chipAddress: UInt8 = 0x37
    /// The display's own address, which every checksum starts from.
    static let displayAddress: UInt8 = 0x6E
    /// The address replies are checksummed against.
    static let replyChecksumSeed: UInt8 = 0x50

    static let getVCPOpcode: UInt8 = 0x01
    static let getVCPReplyOpcode: UInt8 = 0x02
    static let setVCPOpcode: UInt8 = 0x03
    static let saveSettingsOpcode: UInt8 = 0x0C
    static let capabilitiesOpcode: UInt8 = 0xF3
    static let capabilitiesReplyOpcode: UInt8 = 0xE3

    /// A Get VCP reply: address, length, opcode, result, code, type, max (2), current (2), checksum.
    static let getVCPReplyLength = 11
    /// A capabilities reply carries at most 32 data bytes after its 5-byte header.
    static let capabilitiesReplyLength = 38

    static func hex(_ byte: UInt8) -> String { String(format: "%02X", byte) }

    /// XOR of the seed and every byte.
    static func checksum(_ bytes: some Sequence<UInt8>, seed: UInt8) -> UInt8 {
        bytes.reduce(seed, ^)
    }

    /// Length byte, payload, checksum. The checksum covers the display address, the source
    /// byte and the payload, as the DDC/CI standard specifies.
    static func request(_ payload: [UInt8], source: UInt8 = 0x51) -> [UInt8] {
        let body = [0x80 | UInt8(payload.count)] + payload
        return body + [checksum(body, seed: displayAddress ^ source)]
    }

    static func getVCP(_ code: UInt8, source: UInt8 = 0x51) -> [UInt8] {
        request([getVCPOpcode, code], source: source)
    }

    static func setVCP(_ code: UInt8, value: UInt16, source: UInt8 = 0x51) -> [UInt8] {
        request([setVCPOpcode, code, UInt8(value >> 8), UInt8(value & 0xFF)], source: source)
    }

    static func capabilities(offset: UInt16, source: UInt8 = 0x51) -> [UInt8] {
        request([capabilitiesOpcode, UInt8(offset >> 8), UInt8(offset & 0xFF)], source: source)
    }

    static func saveSettings(source: UInt8 = 0x51) -> [UInt8] {
        request([saveSettingsOpcode], source: source)
    }

    /// What one read of a reply buffer means.
    enum Reading: Equatable, Sendable {
        case value(ProbeResult)
        /// Nothing came back (an all-zero buffer): the display stayed silent.
        case silent
        /// Something came back but can't be trusted; worth another try.
        case invalid(DDCError)
    }

    /// Checks a Get VCP reply against the code that was asked for.
    static func parseGetVCPReply(_ reply: [UInt8], code: UInt8, ignoresChecksum: Bool = false) -> Reading {
        guard reply.count >= getVCPReplyLength else { return .invalid(.unexpectedReply("too short")) }
        let reply = Array(reply.prefix(getVCPReplyLength))
        if reply.allSatisfy({ $0 == 0 }) { return .silent }
        if !ignoresChecksum, checksum(reply.dropLast(), seed: replyChecksumSeed) != reply[getVCPReplyLength - 1] {
            return .invalid(.badChecksum)
        }
        guard reply[1] & 0x80 != 0, reply[2] == getVCPReplyOpcode else {
            return .invalid(.unexpectedReply("opcode 0x\(hex(reply[2]))"))
        }
        // A reply for another code is left over from an earlier request.
        guard reply[4] == code else { return .invalid(.unexpectedReply("answered for VCP 0x\(hex(reply[4]))")) }
        switch reply[3] {
        case 0x00:
            let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
            let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
            return .value(.read(current: current, maximum: maximum))
        case 0x01:
            return .value(.unsupported)
        default:
            return .invalid(.unexpectedReply("result code 0x\(hex(reply[3]))"))
        }
    }

    /// One fragment of the capability report.
    enum Fragment: Equatable, Sendable {
        case data([UInt8])
        /// A zero-length fragment: the report is complete.
        case end
        case silent
        case invalid(DDCError)
    }

    static func parseCapabilitiesReply(_ reply: [UInt8], offset: UInt16, ignoresChecksum: Bool = false) -> Fragment {
        guard reply.count >= 6 else { return .invalid(.unexpectedReply("too short")) }
        if reply.allSatisfy({ $0 == 0 }) { return .silent }
        let length = Int(reply[1] & 0x7F)
        // The length counts the opcode and the two offset bytes, then the data.
        guard reply[1] & 0x80 != 0, length >= 3, length <= 35, reply.count >= length + 3 else {
            return .invalid(.unexpectedReply("length byte 0x\(hex(reply[1]))"))
        }
        let checked = reply.prefix(length + 2)
        if !ignoresChecksum, checksum(checked, seed: replyChecksumSeed) != reply[length + 2] {
            return .invalid(.badChecksum)
        }
        guard reply[2] == capabilitiesReplyOpcode else { return .invalid(.unexpectedReply("opcode 0x\(hex(reply[2]))")) }
        let echoed = UInt16(reply[3]) << 8 | UInt16(reply[4])
        guard echoed == offset else { return .invalid(.unexpectedReply("fragment for offset \(echoed), wanted \(offset)")) }
        guard length > 3 else { return .end }
        return .data(Array(reply[5..<(length + 2)]))
    }
}

/// Puts the capability report back together from its fragments, which arrive in order,
/// each naming the offset it starts at.
struct CapabilityAssembler: Sendable {
    /// Real reports are well under 1 KB; past this the display is repeating itself.
    static let limit = 4096

    private(set) var bytes: [UInt8] = []
    private(set) var isComplete = false
    var nextOffset: UInt16 { UInt16(clamping: bytes.count) }

    enum Step: Equatable { case more, done, overflow }

    mutating func accept(_ fragment: [UInt8]) -> Step {
        bytes += fragment
        if bytes.count > Self.limit { return .overflow }
        // A NUL ends the text on displays that pad their last fragment instead of
        // sending an empty one.
        if fragment.contains(0) { isComplete = true; return .done }
        return .more
    }

    mutating func finish() { isComplete = true }

    /// The report as text, without padding.
    var text: String {
        let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
        return String(decoding: bytes[..<end], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
