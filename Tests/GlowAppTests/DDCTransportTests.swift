import Testing
@testable import GlowApp

// Every byte below was worked out by hand from the DDC/CI rules (checksum = XOR of the
// seed and each byte; requests seed with 0x6E ^ source, replies with 0x50), not with the
// code under test.

// MARK: - Requests

@Test func getVCPRequestMatchesTheDDCCILayout() {
    #expect(DDCPacket.getVCP(0x10) == [0x82, 0x01, 0x10, 0xAC])
    #expect(DDCPacket.getVCP(0x10, source: 0x50) == [0x82, 0x01, 0x10, 0xAD])
}

@Test func setVCPCapabilityAndSaveRequestsCarryTheirChecksums() {
    #expect(DDCPacket.setVCP(0x10, value: 50) == [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
    #expect(DDCPacket.capabilities(offset: 0) == [0x83, 0xF3, 0x00, 0x00, 0x4F])
    #expect(DDCPacket.capabilities(offset: 32) == [0x83, 0xF3, 0x00, 0x20, 0x6F])
    #expect(DDCPacket.saveSettings() == [0x81, 0x0C, 0xB2])
}

// MARK: - Get VCP replies

/// Brightness 50 of 100.
private let brightnessReply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0xF2]
private let unsupportedReply: [UInt8] = [0x6E, 0x88, 0x02, 0x01, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0xA5]
private let silence = [UInt8](repeating: 0, count: 38)

private func isInvalid(_ reading: DDCPacket.Reading) -> Bool {
    if case .invalid = reading { return true }
    return false
}

private func isInvalid(_ fragment: DDCPacket.Fragment) -> Bool {
    if case .invalid = fragment { return true }
    return false
}

@Test func goodReplyGivesCurrentAndMaximum() {
    #expect(DDCPacket.parseGetVCPReply(brightnessReply, code: 0x10) == .value(.read(current: 50, maximum: 100)))
}

@Test func badChecksumIsRejectedUnlessTheProfileAcceptsIt() {
    var garbled = brightnessReply
    garbled[10] ^= 0x01
    #expect(DDCPacket.parseGetVCPReply(garbled, code: 0x10) == .invalid(.badChecksum))
    #expect(DDCPacket.parseGetVCPReply(garbled, code: 0x10, ignoresChecksum: true) == .value(.read(current: 50, maximum: 100)))
}

@Test func unsupportedResultCodeIsUnsupported() {
    #expect(DDCPacket.parseGetVCPReply(unsupportedReply, code: 0x10) == .value(.unsupported))
}

@Test func allZeroReplyIsSilence() {
    #expect(DDCPacket.parseGetVCPReply(Array(silence.prefix(11)), code: 0x10) == .silent)
}

@Test func replyForAnotherCodeShortOrWrongOpcodeIsInvalid() {
    #expect(isInvalid(DDCPacket.parseGetVCPReply(brightnessReply, code: 0x12)))
    #expect(isInvalid(DDCPacket.parseGetVCPReply(Array(brightnessReply.prefix(6)), code: 0x10)))
    // A capabilities reply where a Get VCP reply belongs.
    #expect(isInvalid(DDCPacket.parseGetVCPReply(capabilityStart, code: 0x10, ignoresChecksum: true)))
}

// MARK: - Capability fragments

private func padded(_ bytes: [UInt8]) -> [UInt8] { bytes + [UInt8](repeating: 0, count: 38 - bytes.count) }
/// "(prot(monitor)" at offset 0.
private let capabilityStart = padded([0x6E, 0x91, 0xE3, 0x00, 0x00, 0x28, 0x70, 0x72, 0x6F, 0x74, 0x28, 0x6D, 0x6F, 0x6E, 0x69, 0x74, 0x6F, 0x72, 0x29, 0x10])
/// "vcp(10 12))" at offset 14.
private let capabilityRest = padded([0x6E, 0x8E, 0xE3, 0x00, 0x0E, 0x76, 0x63, 0x70, 0x28, 0x31, 0x30, 0x20, 0x31, 0x32, 0x29, 0x29, 0x32])
/// The empty fragment at offset 25 that ends the report.
private let capabilityEnd = padded([0x6E, 0x83, 0xE3, 0x00, 0x19, 0x47])

@Test func capabilityFragmentsParseByOffset() {
    #expect(DDCPacket.parseCapabilitiesReply(capabilityStart, offset: 0) == .data(Array("(prot(monitor)".utf8)))
    #expect(DDCPacket.parseCapabilitiesReply(capabilityRest, offset: 14) == .data(Array("vcp(10 12))".utf8)))
    #expect(DDCPacket.parseCapabilitiesReply(capabilityEnd, offset: 25) == .end)
    #expect(DDCPacket.parseCapabilitiesReply(silence, offset: 0) == .silent)
    // A fragment for the wrong offset is left over from an earlier request.
    #expect(isInvalid(DDCPacket.parseCapabilitiesReply(capabilityRest, offset: 0)))
    var garbled = capabilityRest
    garbled[16] ^= 0xFF
    #expect(DDCPacket.parseCapabilitiesReply(garbled, offset: 14) == .invalid(.badChecksum))
}

@Test func assemblerStopsAtANulAndRefusesEndlessReports() {
    var padded = CapabilityAssembler()
    #expect(padded.accept(Array("(vcp(10))".utf8) + [0, 0]) == .done)
    #expect(padded.isComplete && padded.text == "(vcp(10))")

    var endless = CapabilityAssembler()
    var step = CapabilityAssembler.Step.more
    while step == .more { step = endless.accept([UInt8](repeating: 0x20, count: 32)) }
    #expect(step == .overflow)
}

// MARK: - Exchanges over a scripted bus

/// The IOReturn the AOC's hub gave for every read: the connection gave up waiting.
private let gaveUp = Int32(bitPattern: 0xE011_4103)

/// A clock that moves only when told, so waits cost no real time.
private final class TestClock {
    var now = ContinuousClock.now
}

/// Plays back replies in order (silence once they run out; nil is a refused read) and
/// records every request.
private final class ScriptedBus: I2CBus {
    var replies: [[UInt8]?]
    private(set) var sent: [[UInt8]] = []
    var refusesWrites = false
    var refusesReads = false
    /// How long each read takes on `clock`, to play a bus that blocks before giving up.
    var readCost: Duration = .zero
    let clock: TestClock

    init(_ replies: [[UInt8]?] = [], clock: TestClock = TestClock()) {
        self.replies = replies
        self.clock = clock
    }

    func write(_ packet: [UInt8], source: UInt8) -> Int32 {
        sent.append(packet)
        return refusesWrites ? Int32(bitPattern: 0xE000_02BC) : 0
    }

    func read(count: Int) -> Result<[UInt8], DDCError> {
        clock.now += readCost
        if refusesReads { return .failure(.readFailed(gaveUp)) }
        guard !replies.isEmpty else { return .success([UInt8](repeating: 0, count: count)) }
        return replies.removeFirst().map { .success($0) } ?? .failure(.readFailed(gaveUp))
    }
}

private func session(_ bus: ScriptedBus, profile: DDCTransportProfile = .standard, timeout: Duration = .seconds(8)) -> DDCSession {
    DDCSession(bus: bus, profile: profile, capabilityTimeout: timeout, pause: { [clock = bus.clock] in clock.now += $0 }, now: { [clock = bus.clock] in clock.now })
}

@Test func capabilityReadAssemblesFragmentsUntilAnEmptyOne() throws {
    let bus = ScriptedBus([capabilityStart, capabilityRest, capabilityEnd])
    #expect(try session(bus).readCapabilities() == "(prot(monitor)vcp(10 12))")
    #expect(bus.sent == [DDCPacket.capabilities(offset: 0), DDCPacket.capabilities(offset: 14), DDCPacket.capabilities(offset: 25)])
}

@Test func capabilityReadAsksAgainForAGarbledFragment() throws {
    var garbled = capabilityRest
    garbled[16] ^= 0xFF
    let bus = ScriptedBus([capabilityStart, garbled, capabilityRest, capabilityEnd])
    #expect(try session(bus).readCapabilities() == "(prot(monitor)vcp(10 12))")
    #expect(bus.sent.filter { $0 == DDCPacket.capabilities(offset: 14) }.count == 2)
}

@Test func silentDisplayEndsTheCapabilityReadAfterItsRetries() {
    let bus = ScriptedBus()
    #expect(throws: DDCError.timedOut) { try session(bus).readCapabilities() }
    #expect(bus.sent.count == DDCTransportProfile.standard.retries + 1)
}

@Test func capabilityReadGivesUpAtItsOverallTimeout() {
    let bus = ScriptedBus([capabilityStart, capabilityRest, capabilityEnd])
    #expect(throws: DDCError.timedOut) { try session(bus, timeout: .zero).readCapabilities() }
    #expect(bus.sent.isEmpty)
}

@Test func getVCPRetriesSilenceThenReads() throws {
    let bus = ScriptedBus([Array(silence.prefix(11)), brightnessReply])
    #expect(try session(bus).getVCP(0x10) == .read(current: 50, maximum: 100))
    #expect(bus.sent == [DDCPacket.getVCP(0x10), DDCPacket.getVCP(0x10)])
}

@Test func getVCPIsNoResponseWhenEveryTryIsSilent() throws {
    let bus = ScriptedBus()
    #expect(try session(bus).getVCP(0x10) == .noResponse)
    #expect(bus.sent.count == DDCTransportProfile.standard.retries + 1)
}

@Test func getVCPThatKeepsGarblingThrowsRatherThanGuessing() {
    var garbled = brightnessReply
    garbled[10] ^= 0x01
    let bus = ScriptedBus(Array(repeating: garbled, count: 5))
    #expect(throws: DDCError.badChecksum) { try session(bus).getVCP(0x10) }
}

@Test func getVCPPassesUnsupportedThrough() throws {
    #expect(try session(ScriptedBus([unsupportedReply])).getVCP(0x10) == .unsupported)
}

@Test func setVCPSendsOnceAndNeverSavesByDefault() throws {
    let bus = ScriptedBus()
    try session(bus).setVCP(0x10, value: 50)
    #expect(bus.sent == [[0x84, 0x03, 0x10, 0x00, 0x32, 0x9A]])
}

@Test func refusedSendsFailTheWriteAfterItsRetries() {
    let bus = ScriptedBus()
    bus.refusesWrites = true
    #expect(throws: DDCError.sendFailed(Int32(bitPattern: 0xE000_02BC))) { try session(bus).setVCP(0x10, value: 50) }
    #expect(bus.sent.count == DDCTransportProfile.standard.retries + 1)
}

@Test func aBusThatRefusesEveryReadSaysWhyInsteadOfSilence() {
    let bus = ScriptedBus()
    bus.refusesReads = true
    #expect(throws: DDCError.readFailed(gaveUp)) { try session(bus).getVCP(0x10) }
    #expect(throws: DDCError.readFailed(gaveUp)) { try session(bus).readCapabilities() }
}

@Test func aRefusedReadThenAnAnswerStillReads() throws {
    let bus = ScriptedBus([nil, brightnessReply])
    #expect(try session(bus).getVCP(0x10) == .read(current: 50, maximum: 100))
    #expect(bus.sent.count == 2)
}

@Test func aBusThatBlocksForSecondsIsNotRetried() {
    // What the AOC behind its hub did: every read blocked about 6 s, then failed. Five
    // tries would hold discovery up for 30 s a code.
    let bus = ScriptedBus()
    bus.refusesReads = true
    bus.readCost = .seconds(6)
    #expect(throws: DDCError.readFailed(gaveUp)) { try session(bus).getVCP(0x10) }
    #expect(bus.sent.count == 1)
    #expect(throws: DDCError.readFailed(gaveUp)) { try session(bus).readCapabilities() }
    #expect(bus.sent.count == 2)
}

@Test func theSlowerProfileWaitsLongerAndSendsTwice() throws {
    let bus = ScriptedBus([brightnessReply])
    let started = bus.clock.now
    #expect(try session(bus, profile: .slow).getVCP(0x10) == .read(current: 50, maximum: 100))
    #expect(bus.sent == [DDCPacket.getVCP(0x10), DDCPacket.getVCP(0x10)])
    #expect(bus.clock.now - started == .milliseconds(20 + 20 + 200))
}

@Test func theAlternateProfileUsesSource0x50() throws {
    let bus = ScriptedBus([brightnessReply])
    _ = try session(bus, profile: .alternate).getVCP(0x10)
    #expect(bus.sent == [DDCPacket.getVCP(0x10, source: 0x50)])
}

@Test func theLadderIsStandardThenSlowerThenAlternate() {
    #expect(DDCTransportProfile.ladder == [.standard, .slow, .alternate])
    #expect(DDCTransportProfile.ladder.map(\.name) == ["Standard", "Slower timing", "Alternate address"])
    #expect(DDCTransportProfile.alternate.differencesFromStandard == ["Uses the alternate address (source 0x50)"])
    #expect(DDCTransportProfile.slow.differencesFromStandard == [
        "Sends each request 2 times", "Waits 20 ms before sending", "Waits 200 ms for a reply",
        "Tries 7 times", "Waits 100 ms between tries", "Keeps trying for up to 3000 ms"
    ])
}

@Test func standardProfileShowsNoDifferencesAndOthersSayWhat() {
    #expect(DDCTransportProfile.standard.differencesFromStandard.isEmpty)
    var alternate = DDCTransportProfile.standard
    alternate.sourceAddress = 0x50
    alternate.ignoresReadChecksum = true
    #expect(alternate.differencesFromStandard == ["Uses the alternate address (source 0x50)", "Accepts replies with a bad checksum"])
}

// MARK: - Discovery through a link

private actor FakeLink: DDCTransport {
    var writes = 0
    let report: String?
    let answers: [UInt8: ProbeResult]

    init(report: String?, answers: [UInt8: ProbeResult] = [0x10: .read(current: 40, maximum: 100)]) {
        self.report = report
        self.answers = answers
    }

    func capabilityString() async throws -> String {
        guard let report else { throw DDCError.timedOut }
        return report
    }

    func read(code: UInt8) async throws -> ProbeResult { answers[code] ?? .noResponse }

    func write(code: UInt8, value: UInt16) async throws { writes += 1 }
}

@Test func discoveryReadsEachListedSettingOnceAndNeverWrites() async throws {
    let link = FakeLink(report: "(prot(monitor)type(lcd)vcp(10 12)mccs_ver(2.2))")
    let probe = await DDCProbe.run(link, transport: "DisplayPort")
    #expect(probe.capabilityString == "(prot(monitor)type(lcd)vcp(10 12)mccs_ver(2.2))")
    #expect(probe.readings.map(\.code) == [0x10, 0x12])
    #expect(await link.writes == 0)
    let brightness = try #require(probe.descriptors.first { $0.id == .brightness })
    #expect(brightness.isSafelyEditable)
    #expect(brightness.currentValue == .number(40))
    // Listed but silent: shown, never editable, never given a guessed value.
    let contrast = try #require(probe.descriptors.first { $0.id == .contrast })
    #expect(!contrast.isSafelyEditable)
    #expect(contrast.currentValue == nil)
}

@Test func displayThatDoesntAnswerGivesNoSettingsAndAReason() async {
    let probe = await DDCProbe.run(FakeLink(report: nil, answers: [:]), transport: "HDMI")
    #expect(probe.capabilityString == nil)
    #expect(probe.problem != nil)
    #expect(probe.descriptors.isEmpty)
    #expect(probe.readings.isEmpty)
    #expect(probe.link == nil && probe.log.workingProfile == nil)
}

// MARK: - Matching displays to services

private func aoc(_ id: UInt32, location: String? = nil, serial: UInt32 = 0) -> DisplayFacts {
    DisplayFacts(
        displayID: id, vendorID: 0x05E3, productID: 0x3220, serialNumber: serial, name: "32G2WG3",
        isBuiltIn: false, location: location, weekOfManufacture: 31, yearOfManufacture: 2023,
        imageSize: (width: 698, height: 393)
    )
}

private func service(_ index: Int, id: UInt64, location: String) -> DDCServiceCandidate {
    DDCServiceCandidate(
        index: index, registryID: id, location: location,
        edidUUID: "05E32032-0000-0000-1F21-0104B5462778",
        productName: "32G2WG3", serialNumber: nil, vendorID: 0x05E3, productID: 0x3220, transport: "DP"
    )
}

@Test func everyEDIDFieldAndTheLocationCount() {
    let (score, reasons) = DDCServiceMatcher.score(aoc(2, location: "IOService:/fb0"), service(1, id: 100, location: "IOService:/fb0"))
    #expect(reasons == ["framebuffer location", "EDID vendor", "EDID product", "EDID manufacture date", "EDID image size", "vendor", "product", "product name"])
    #expect(score == DDCServiceMatcher.locationWeight + 7)
}

@Test func identicalMonitorsEachGetTheirOwnServiceByLocation() throws {
    let displays = [aoc(2, location: "IOService:/fb1"), aoc(3, location: "IOService:/fb2")]
    // Registry order is the reverse of display order.
    let services = [service(1, id: 200, location: "IOService:/fb2"), service(2, id: 100, location: "IOService:/fb1")]
    let matches = DDCServiceMatcher.assign(displays, to: services)
    #expect(try #require(matches[2]).candidate.registryID == 100)
    #expect(try #require(matches[3]).candidate.registryID == 200)
}

@Test func oneServiceIsNeverUsedForTwoDisplays() {
    let matches = DDCServiceMatcher.assign([aoc(2), aoc(3)], to: [service(1, id: 100, location: "IOService:/fb1")])
    #expect(matches.count == 1)
    #expect(matches.values.map(\.candidate.registryID) == [100])
}

@Test func builtInAndUnrelatedServicesNeverMatch() {
    var builtIn = aoc(1)
    builtIn.isBuiltIn = true
    let stranger = DDCServiceCandidate(index: 1, registryID: 300, location: "IOService:/other", edidUUID: "10AC0000-0000-0000-0000-000000000000",
                                       productName: "DELL U2723QE", serialNumber: 99, vendorID: 0x10AC, productID: 0x4242, transport: "HDMI")
    #expect(DDCServiceMatcher.assign([builtIn], to: [service(1, id: 100, location: "IOService:/fb1")]).isEmpty)
    #expect(DDCServiceMatcher.assign([aoc(2)], to: [stranger]).isEmpty)
}

@Test func theBuiltInDisplayIsNamedAfterTheMac() {
    func named(_ product: String?) -> String { DisplayRegistry.macName(productName: product) }
    #expect(named("MacBook Air (15-inch, M4, 2025)") == "MacBook Air")
    #expect(named("iMac (24-inch, 2024)") == "iMac")
    #expect(named("MacBook Pro") == "MacBook Pro")
    #expect(named("") == "This Mac")
    #expect(named(nil) == "This Mac")
}
