import CoreGraphics
import Foundation
import IOKit

/// The private IOAVService I2C calls MonitorControl uses on Apple silicon.
/// They're looked up at run time; if macOS stops offering them, Glow says so and falls
/// back, rather than failing to launch.
struct IOAVServiceAPI: @unchecked Sendable {
    typealias Create = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias ReadI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    typealias WriteI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    let create: Create
    let readI2C: ReadI2C
    let writeI2C: WriteI2C

    /// The calls, or the name of the first one missing.
    static let shared: Result<IOAVServiceAPI, DDCError> = load()

    private static func load() -> Result<IOAVServiceAPI, DDCError> {
        let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        func symbol(_ name: String) -> UnsafeMutableRawPointer? { dlsym(handle ?? UnsafeMutableRawPointer(bitPattern: -2), name) }
        guard let create = symbol("IOAVServiceCreateWithService") else { return .failure(.interfaceMissing("IOAVServiceCreateWithService")) }
        guard let read = symbol("IOAVServiceReadI2C") else { return .failure(.interfaceMissing("IOAVServiceReadI2C")) }
        guard let write = symbol("IOAVServiceWriteI2C") else { return .failure(.interfaceMissing("IOAVServiceWriteI2C")) }
        return .success(IOAVServiceAPI(
            create: unsafeBitCast(create, to: Create.self),
            readI2C: unsafeBitCast(read, to: ReadI2C.self),
            writeI2C: unsafeBitCast(write, to: WriteI2C.self)
        ))
    }
}

/// One serial queue per IORegistry service (or simulated monitor), shared by every link to
/// it, so two discoveries or a discovery and a write never interleave bytes on one bus.
enum DDCBus {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var queues: [UInt64: DispatchQueue] = [:]

    static func queue(for registryID: UInt64) -> DispatchQueue {
        lock.withLock {
            if let queue = queues[registryID] { return queue }
            let queue = DispatchQueue(label: "app.glow.ddc.\(String(registryID, radix: 16))", qos: .userInitiated)
            queues[registryID] = queue
            return queue
        }
    }
}

/// The two I2C calls a DDC exchange needs. IOAVService in the app; a simulated monitor in
/// debug builds; scripted bytes in tests.
protocol I2CBus {
    /// Sends `packet` to chip 0x37 with `source` as the first byte on the wire.
    func write(_ packet: [UInt8], source: UInt8) -> IOReturn
    /// Reads `count` bytes from chip 0x37, or `.readFailed` with the bus's code when it refuses.
    func read(count: Int) -> Result<[UInt8], DDCError>
}

/// The DDC/CI exchanges over one bus: sends, waits, retries and checks replies. It blocks
/// the thread it runs on, so it only ever runs on a display's bus queue (or in a test).
struct DDCSession {
    let bus: any I2CBus
    let profile: DDCTransportProfile
    /// The whole capability read gives up after this, however many fragments are left.
    var capabilityTimeout: Duration = .seconds(8)
    var pause: (Duration) -> Void = { usleep($0.microseconds) }
    var now: () -> ContinuousClock.Instant = { .now }

    private func send(_ packet: [UInt8]) throws {
        var lastResult: IOReturn = kIOReturnSuccess
        var sent = false
        for _ in 0..<max(1, profile.sendCount) {
            pause(profile.writeWait)
            lastResult = bus.write(packet, source: profile.sourceAddress)
            if lastResult == kIOReturnSuccess { sent = true }
        }
        guard sent else { throw DDCError.sendFailed(lastResult) }
    }

    private func receive(count: Int) -> Result<[UInt8], DDCError> {
        pause(profile.readWait)
        return bus.read(count: count)
    }

    /// Another try is worth it only while the exchange is inside the profile's window.
    private func mayRetry(since started: ContinuousClock.Instant) -> Bool {
        now() - started < profile.retryWindow
    }

    /// Asks, then retries anything garbled or silent. A display that keeps saying nothing
    /// is `.noResponse`; one that keeps garbling is an error, and so is a bus that gave up
    /// on every read.
    func getVCP(_ code: UInt8) throws -> ProbeResult {
        let started = now()
        var garbled: DDCError?
        var refused: DDCError?
        var heard = false
        for attempt in 0...profile.retries {
            if attempt > 0 {
                guard mayRetry(since: started) else { break }
                pause(profile.retryWait)
            }
            guard (try? send(DDCPacket.getVCP(code, source: profile.sourceAddress))) != nil else { continue }
            switch receive(count: DDCPacket.getVCPReplyLength) {
            case .failure(let problem):
                refused = problem
                continue
            case .success(let reply):
                heard = true
                switch DDCPacket.parseGetVCPReply(reply, code: code, ignoresChecksum: profile.ignoresReadChecksum) {
                case .value(let result): return result
                case .silent: continue
                case .invalid(let problem): garbled = problem
                }
            }
        }
        if let garbled { throw garbled }
        if !heard, let refused { throw refused }
        // Silence, or a bus that refused every send, means the display isn't answering here.
        return .noResponse
    }

    /// Set VCP has no reply; the caller confirms it with a read.
    func setVCP(_ code: UInt8, value: UInt16) throws {
        let started = now()
        var lastProblem: DDCError = .timedOut
        for attempt in 0...profile.retries {
            if attempt > 0 {
                guard mayRetry(since: started) else { break }
                pause(profile.retryWait)
            }
            do {
                try send(DDCPacket.setVCP(code, value: value, source: profile.sourceAddress))
                pause(profile.settleAfterSet)
                if profile.savesAfterWrite {
                    try send(DDCPacket.saveSettings(source: profile.sourceAddress))
                    pause(profile.settleAfterSet)
                }
                return
            } catch let error as DDCError {
                lastProblem = error
            }
        }
        throw lastProblem
    }

    /// Requests fragments from offset 0 until the display sends an empty one.
    func readCapabilities() throws -> String {
        let deadline = now() + capabilityTimeout
        var assembler = CapabilityAssembler()
        var failures = 0
        var fragmentStarted = now()
        while !assembler.isComplete {
            guard now() < deadline else { throw DDCError.timedOut }
            let offset = assembler.nextOffset
            var fragment: DDCPacket.Fragment = .silent
            var refused: DDCError?
            do {
                try send(DDCPacket.capabilities(offset: offset, source: profile.sourceAddress))
                switch receive(count: DDCPacket.capabilitiesReplyLength) {
                case .success(let reply):
                    fragment = DDCPacket.parseCapabilitiesReply(reply, offset: offset, ignoresChecksum: profile.ignoresReadChecksum)
                case .failure(let problem):
                    refused = problem
                }
            } catch let error as DDCError {
                fragment = .invalid(error)
            }
            switch fragment {
            case .data(let bytes):
                failures = 0
                fragmentStarted = now()
                if assembler.accept(bytes) == .overflow { throw DDCError.unexpectedReply("the capability report never ended") }
            case .end:
                assembler.finish()
            case .silent, .invalid:
                failures += 1
                // A display that never answered the first fragment doesn't speak DDC here.
                if failures > profile.retries || !mayRetry(since: fragmentStarted) {
                    if case let .invalid(error) = fragment, offset > 0 { throw error }
                    if let refused { throw refused }
                    throw DDCError.timedOut
                }
                pause(profile.retryWait)
            }
        }
        return assembler.text
    }
}

/// One display's IOAVService, as an `I2CBus`.
private struct IOAVBus: I2CBus {
    let api: IOAVServiceAPI
    let service: CFTypeRef

    func write(_ packet: [UInt8], source: UInt8) -> IOReturn {
        var packet = packet
        return packet.withUnsafeMutableBytes { buffer in
            api.writeI2C(service, UInt32(DDCPacket.chipAddress), UInt32(source), buffer.baseAddress!, UInt32(buffer.count))
        }
    }

    func read(count: Int) -> Result<[UInt8], DDCError> {
        var reply = [UInt8](repeating: 0, count: count)
        let result = reply.withUnsafeMutableBytes { buffer in
            api.readI2C(service, UInt32(DDCPacket.chipAddress), 0, buffer.baseAddress!, UInt32(buffer.count))
        }
        return result == kIOReturnSuccess ? .success(reply) : .failure(.readFailed(result))
    }
}

/// DDC/CI to one display over one bus: IOAVService for a real external display, or a
/// simulated monitor in debug builds and tests. Every exchange runs on that bus's own serial
/// queue, off the main actor; waits block only that queue.
final class DDCLink: DDCTransport, @unchecked Sendable {
    let profile: DDCTransportProfile
    private let session: DDCSession
    private let queue: DispatchQueue

    /// `busID` picks the serial queue: every link with the same one takes turns.
    init(session: DDCSession, busID: UInt64) {
        profile = session.profile
        self.session = session
        queue = DDCBus.queue(for: busID)
    }

    /// Opens the display's AV service; nil when macOS won't hand one out.
    convenience init?(registryEntry: io_service_t, registryID: UInt64, profile: DDCTransportProfile = .standard) {
        guard case let .success(api) = IOAVServiceAPI.shared,
              let service = api.create(kCFAllocatorDefault, registryEntry)?.takeRetainedValue() else { return nil }
        self.init(session: DDCSession(bus: IOAVBus(api: api, service: service), profile: profile), busID: registryID)
    }

    func read(code: UInt8) async throws -> ProbeResult {
        try await run { try self.session.getVCP(code) }
    }

    func write(code: UInt8, value: UInt16) async throws {
        try await run { try self.session.setVCP(code, value: value) }
    }

    func capabilityString() async throws -> String {
        try await run { try self.session.readCapabilities() }
    }

    private func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }
}
