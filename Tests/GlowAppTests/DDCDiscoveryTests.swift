import Testing
@testable import GlowApp

// Discovery across transport profiles, the fallback for displays that send no capability
// report, and what Connection details and Copy Report get to show.

/// Answers reads from a table and records each one. It never needs a monitor.
private actor ScriptedLink: DDCTransport {
    let report: String?
    let answers: [UInt8: ProbeResult]
    private(set) var reads: [UInt8] = []
    private(set) var writes = 0

    init(report: String? = nil, answers: [UInt8: ProbeResult] = [:]) {
        self.report = report
        self.answers = answers
    }

    func capabilityString() async throws -> String {
        guard let report else { throw DDCError.timedOut }
        return report
    }

    func read(code: UInt8) async throws -> ProbeResult {
        reads.append(code)
        return answers[code] ?? .noResponse
    }

    func write(code: UInt8, value: UInt16) async throws { writes += 1 }
}

// MARK: - Profiles

@Test func ladderTriesSlowerTimingThenTheAlternateAddress() async throws {
    let silent = ScriptedLink()
    let answering = ScriptedLink(report: "vcp(10)", answers: [0x10: .read(current: 30, maximum: 100)])
    var opened: [DDCTransportProfile] = []
    let probe = await DDCProbe.run(transport: "DisplayPort", profiles: DDCTransportProfile.ladder) { profile in
        opened.append(profile)
        return profile == .alternate ? answering : silent
    }
    #expect(opened == DDCTransportProfile.ladder)
    let attempts = probe.log.attempts
    // Standard asks for the report, then sends one Get VCP; later profiles start with the Get VCP.
    #expect(attempts.map(\.profile) == ["Standard", "Standard", "Slower timing", "Alternate address", "Alternate address"])
    #expect(attempts.map(\.request) == ["capability report", "Get VCP 0x10 (brightness)", "Get VCP 0x10 (brightness)", "Get VCP 0x10 (brightness)", "capability report"])
    #expect(attempts.map(\.answered) == [false, false, false, true, true])
    #expect(attempts.allSatisfy { $0.milliseconds != nil })
    #expect(probe.log.workingProfile == .alternate)
    #expect(probe.log.profileText == "Alternate address: Uses the alternate address (source 0x50)")
    #expect(probe.capabilityString == "vcp(10)")
    let brightness = try #require(probe.descriptors.first)
    #expect(brightness.evidence == .safelyProbed && brightness.isSafelyEditable)
    // The answer to the first Get VCP is reused, not asked for twice.
    #expect(await answering.reads == [0x10])
    #expect(await answering.writes == 0)
    #expect(await silent.writes == 0)
}

@Test func aConnectionThatWasSilentGetsOneQuickRequest() async {
    let link = ScriptedLink()
    let probe = await DDCProbe.run(transport: "HDMI", profiles: [.standard], quick: true) { _ in link }
    #expect(probe.log.attempts.map(\.request) == ["Get VCP 0x10 (brightness)"])
    #expect(probe.log.note?.contains("Refresh Displays") == true)
    #expect(probe.link == nil && probe.descriptors.isEmpty)
    #expect(probe.log.profileText == "None answered")
}

@Test func aQuickRecheckThatGetsAnAnswerReadsTheReport() async {
    let link = ScriptedLink(report: "vcp(10 12)", answers: [0x10: .read(current: 30, maximum: 100), 0x12: .read(current: 70, maximum: 100)])
    let probe = await DDCProbe.run(transport: "HDMI", profiles: [.standard], quick: true) { _ in link }
    #expect(probe.log.attempts.map(\.request) == ["Get VCP 0x10 (brightness)", "capability report"])
    #expect(probe.descriptors.filter(\.isSafelyEditable).map(\.id) == [.brightness, .contrast])
    #expect(probe.log.note == nil)
}

/// A connection that holds each request, then refuses it, as an Anker hub did with an AOC
/// 32G2WG3 (IOReturn 0xe0114103 after about 6 s).
private struct StallingLink: DDCTransport {
    let hold: Duration

    func capabilityString() async throws -> String { try await stall() }
    func read(code: UInt8) async throws -> ProbeResult { try await stall() }
    func write(code: UInt8, value: UInt16) async throws { throw DDCError.sendFailed(Self.refusal) }

    private static let refusal = Int32(bitPattern: 0xE011_4103)

    private func stall<T>() async throws -> T {
        try? await Task.sleep(for: hold)
        throw DDCError.readFailed(Self.refusal)
    }
}

@Test func aConnectionThatStallsThenRefusesEndsTheLadder() async {
    var opened: [DDCTransportProfile] = []
    let probe = await DDCProbe.run(transport: "DisplayPort", profiles: DDCTransportProfile.ladder, stallLimit: .milliseconds(20)) { profile in
        opened.append(profile)
        return StallingLink(hold: .milliseconds(40))
    }
    // One wait, not four: no other profile is opened.
    #expect(opened == [.standard])
    #expect(probe.log.attempts.map(\.request) == ["capability report"])
    #expect(probe.log.attempts.map(\.stalled) == [true])
    #expect(probe.log.stopped)
    #expect(probe.log.note?.contains("Some hubs and adapters don’t pass DDC/CI") == true)
    #expect(probe.link == nil && probe.descriptors.isEmpty)
}

@Test func aSilentConnectionThatStallsSaysWhyItStopped() async {
    let probe = await DDCProbe.run(transport: "HDMI", profiles: [.standard], quick: true, stallLimit: .milliseconds(20)) { _ in
        StallingLink(hold: .milliseconds(40))
    }
    #expect(probe.log.attempts.map(\.request) == ["Get VCP 0x10 (brightness)"])
    #expect(probe.log.note?.hasPrefix("Glow stopped there") == true)
}

@Test func aRefusalThatComesAtOnceStillClimbsTheLadder() async {
    // The connection didn't block, so another timing or address may still be heard.
    let probe = await DDCProbe.run(transport: "DisplayPort", profiles: DDCTransportProfile.ladder) { _ in
        StallingLink(hold: .zero)
    }
    #expect(probe.log.attempts.map(\.profile) == ["Standard", "Standard", "Slower timing", "Alternate address"])
    #expect(probe.log.attempts.allSatisfy { !$0.stalled })
    #expect(!probe.log.stopped)
}

@Test func aServiceThatWontOpenSaysSoAndSendsNothing() async {
    let probe = await DDCProbe.run(transport: "HDMI", profiles: DDCTransportProfile.ladder) { _ in nil }
    #expect(probe.log.attempts.isEmpty)
    #expect(probe.problem != nil)
}

private func aocFacts(location: String?) -> DisplayFacts {
    DisplayFacts(
        displayID: 3, vendorID: 0x05E3, productID: 0x3202, serialNumber: 0, name: "32G2WG3",
        isBuiltIn: false, location: location, weekOfManufacture: nil, yearOfManufacture: nil, imageSize: nil
    )
}

private func log(_ profile: DDCTransportProfile?) -> DDCDiscoveryLog {
    DDCDiscoveryLog(
        attempts: [.init(profile: (profile ?? .standard).name, request: "capability report", answered: profile != nil, detail: "")],
        workingProfile: profile
    )
}

@Test func eachConnectionKeepsTheProfileThatWorkedForIt() {
    var memory = DDCRouteMemory()
    let ladder = DDCTransportProfile.ladder
    let hub = DDCRouteKey(aocFacts(location: "IOService:/hub"), registryID: 1)
    let direct = DDCRouteKey(aocFacts(location: "IOService:/direct"), registryID: 2)
    #expect(memory.plan(for: hub, ladder: ladder).profiles == ladder)

    memory.record(log(.alternate), for: direct)
    #expect(memory.plan(for: direct, ladder: ladder).profiles == [.alternate, .standard, .slow])
    // The same monitor on another route starts from scratch.
    #expect(memory.plan(for: hub, ladder: ladder).profiles == ladder)

    // Silent: one quick request on automatic rediscovery, every profile after Refresh.
    memory.record(log(nil), for: hub)
    let recheck = memory.plan(for: hub, ladder: ladder)
    #expect(recheck.profiles == [.standard] && recheck.quick)
    memory.forgetSilence()
    let refreshed = memory.plan(for: hub, ladder: ladder)
    #expect(refreshed.profiles == ladder && !refreshed.quick)
    #expect(memory.plan(for: direct, ladder: ladder).profiles.first == .alternate)
}

@Test func aServiceThatWouldntOpenTeachesTheMemoryNothing() {
    var memory = DDCRouteMemory()
    let hub = DDCRouteKey(aocFacts(location: nil), registryID: 0x105502F64)
    memory.record(DDCDiscoveryLog(), for: hub)
    #expect(!memory.plan(for: hub, ladder: DDCTransportProfile.ladder).quick)
    #expect(hub.route == "service 105502f64")
}

// MARK: - No capability report

@Test func displayWithoutAReportIsReadSettingBySetting() async throws {
    let link = ScriptedLink(answers: [
        0x10: .read(current: 40, maximum: 100), 0x8D: .read(current: 2, maximum: 2),
        0x60: .read(current: 0x0F, maximum: 0), 0xD6: .read(current: 0x01, maximum: 0),
        0x14: .read(current: 0x05, maximum: 0), 0x12: .unsupported
    ])
    let probe = await DDCProbe.run(link, transport: "DisplayPort")
    #expect(probe.capabilityString == nil && probe.problem != nil)
    #expect(probe.log.workingProfile == .standard)
    // One read of every catalogued setting, brightness included only once, and no writes.
    #expect(await link.reads == CapabilityDiscovery.unlistedCodes)
    #expect(probe.readings.map(\.code) == CapabilityDiscovery.unlistedCodes)
    #expect(await link.writes == 0)

    let byID = Dictionary(uniqueKeysWithValues: probe.descriptors.map { ($0.id, $0) })
    #expect(Set(byID.keys) == [.brightness, .mute, .input, .power, .preset])
    #expect(byID.values.allSatisfy { $0.evidence == .answeredUnlisted && $0.route == .hardware })
    #expect(byID[.brightness]?.isSafelyEditable == true)
    #expect(byID[.brightness]?.currentValue == .number(40))
    #expect(byID[.mute]?.isSafelyEditable == true)
    // Nothing listed them, so input, power and presets are shown and never offered.
    #expect(byID[.input]?.currentValue == .text("DisplayPort 1"))
    #expect(byID[.input]?.isSafelyEditable == false)
    #expect(byID[.power]?.isSafelyEditable == false)
    #expect(byID[.preset]?.isSafelyEditable == false)
    // Refused or silent and not listed: nothing says the display has it.
    #expect(byID[.contrast] == nil && byID[.volume] == nil)
}

@Test @MainActor func withoutAReportOnlyLowRiskSlidersAndSwitchesBecomeEditable() throws {
    let answers = Dictionary(uniqueKeysWithValues: CapabilityDiscovery.unlistedCodes.map { ($0, ProbeResult.read(current: 1, maximum: 100)) })
    let profile = CapabilityDiscovery.unlistedProfile(transport: "DisplayPort") { answers[$0] ?? .noResponse }
    #expect(Set(profile.filter(\.isSafelyEditable).map(\.id)) == [
        .brightness, .contrast, .volume, .mute, .sharpness, .redGain, .greenGain, .blueGain,
        .redBlackLevel, .greenBlackLevel, .blueBlackLevel
    ])
    #expect(profile.allSatisfy { $0.evidence == .answeredUnlisted })
    #expect(profile.filter { $0.risk != .none }.allSatisfy { !$0.isSafelyEditable && $0.access == .readOnly })
    #expect(profile.allSatisfy { $0.reliability.provenance.contains("Not in a capability report") })
    let brightness = try #require(profile.first { $0.id == .brightness })
    #expect(ControlStatus(descriptor: brightness).state == .route(.hardware))
    #expect(SupportEvidence.answeredUnlisted.rawValue == "Answered, not listed by the display")
}

@Test func anUnlistedAnswerGlowCantNameIsLeftOut() {
    // Mute is 1 or 2; 7 means something Glow doesn't know. Nothing listed it, so "Reported,
    // but test failed" would be untrue. The raw reading stays in Connection details.
    let profile = CapabilityDiscovery.unlistedProfile(transport: "DisplayPort") { $0 == 0x8D ? .read(current: 7, maximum: 2) : .noResponse }
    #expect(profile.isEmpty)
}

@Test func theReportStillDecidesWhenThereIsOne() async throws {
    // A listed input that reads back can be offered (it asks first); unlisted, it can't.
    let link = ScriptedLink(report: "vcp(60(0F 11))", answers: [0x60: .read(current: 0x11, maximum: 0), 0x10: .read(current: 50, maximum: 100)])
    let probe = await DDCProbe.run(link, transport: "DisplayPort")
    let input = try #require(probe.descriptors.first { $0.id == .input })
    #expect(input.evidence == .safelyProbed && input.isSafelyEditable && input.requiresConfirmation)
    // Only listed codes are read.
    #expect(await link.reads == [0x60])
}

// MARK: - What people see

@Test func demoLogsShowEachDisplaysStory() throws {
    let dell = try #require(DemoData.discoveryLogs[DemoData.dellIdentity])
    #expect(dell.workingProfile == .standard && dell.capabilityString == DemoData.dellCapabilityString)
    let lg = try #require(DemoData.discoveryLogs[DemoData.lgIdentity])
    #expect(lg.workingProfile == nil && lg.attempts.allSatisfy { !$0.answered })
    #expect(Set(lg.attempts.map(\.profile)) == Set(DDCTransportProfile.ladder.map(\.name)))
    let unlisted = DemoData.unlistedDisplay(generation: 1)
    let brightness = try #require(unlisted.capabilities.first { $0.id == .brightness })
    #expect(brightness.evidence == .answeredUnlisted && brightness.isSafelyEditable)
    #expect(unlisted.capabilities.first { $0.id == .usageTime }?.access == .readOnly)
}

@Test func reportLinesNameEveryTryTheProfileTheReportAndEachReading() throws {
    let unlisted = DemoData.unlistedDisplay(generation: 1)
    let log = try #require(DemoData.discoveryLogs[DemoData.unlistedIdentity])
    let lines = log.reportLines(for: unlisted)
    #expect(lines.first == "DDC/CI tries:")
    #expect(lines.contains("- Standard, capability report: no reply · The display took too long to answer."))
    #expect(lines.contains("Working profile: \(DDCTransportProfile.standard.summary)"))
    #expect(lines.contains("Capability string: None (The display took too long to answer)"))
    #expect(lines.contains("- VCP 0x10 Brightness: current 60, maximum 100 · Answered, not listed by the display"))
    #expect(lines.contains("- VCP 0x16 Red level: no response"))
}

@Test @MainActor func copyReportIncludesDiscoveryAndStillRedactsSerials() async {
    let store = GlowStore(demoDisplays: true)
    await store.start()
    let report = store.diagnosticReport()
    #expect(report.contains("DDC/CI tries:"))
    #expect(report.contains("Working profile: \(DDCTransportProfile.standard.summary)"))
    #expect(report.contains("Capability string: \(DemoData.dellCapabilityString)"))
    #expect(report.contains("serial [redacted]"))
    #expect(!report.contains("783245") && !report.contains("1001"))
}
