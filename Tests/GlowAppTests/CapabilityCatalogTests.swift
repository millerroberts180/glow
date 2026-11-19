import Testing
@testable import GlowApp

// MARK: - Capability string parsing

@Test func parsesAWellFormedCapabilityString() throws {
    let parsed = try #require(MCCSCapabilities.parse(DemoData.dellCapabilityString))
    #expect(parsed.model == "U2723QE")
    #expect(parsed.mccsVersion == "2.1")
    #expect(parsed.values(for: 0x60) == [0x0F, 0x11, 0x12, 0x1B])
    #expect(parsed.values(for: 0x10) == [])
    #expect(parsed.codes.first?.code == 0x02)
}

@Test func parsesSloppyFirmwareFormatting() throws {
    // No outer wrapper, no spaces, lowercase hex, a nested group and a repeated code.
    let parsed = try #require(MCCSCapabilities.parse("type(lcd)vcp(1012 14(0508)60(0f11) dc(00(01 02) 03) 10)"))
    #expect(parsed.codes.map(\.code) == [0x10, 0x12, 0x14, 0x60, 0xDC])
    #expect(parsed.values(for: 0x14) == [0x05, 0x08])
    #expect(parsed.values(for: 0x60) == [0x0F, 0x11])
    #expect(parsed.values(for: 0xDC) == [0x00, 0x03])
}

@Test func missingVCPListMeansNothingReported() {
    #expect(MCCSCapabilities.parse("(prot(monitor)type(lcd))") == nil)
    #expect(MCCSCapabilities.parse("") == nil)
    #expect(MCCSCapabilities.parse(String(repeating: "vcp(10)", count: 2000)) == nil)
}

// MARK: - Catalog and evidence

@Test func reportedCodesAreNotEditableUntilProbed() throws {
    let parsed = try #require(MCCSCapabilities.parse("vcp(10 60(0F 11))"))
    let descriptors = CapabilityCatalog.descriptors(from: parsed, transport: "DisplayPort")
    #expect(descriptors.map(\.id) == [.brightness, .input])
    #expect(descriptors.allSatisfy { $0.evidence == .reportedOnly && !$0.isSafelyEditable })
    #expect(descriptors.allSatisfy { CapabilityRenderer.style(for: $0) == .readOnly })
    #expect(descriptors.allSatisfy { $0.currentValue == nil })
}

@Test func unknownAndMaintenanceCodesStayInConnectionDetails() throws {
    let parsed = try #require(MCCSCapabilities.parse("vcp(02 04 10 52 C9 E2(00 1D))"))
    let descriptors = CapabilityCatalog.descriptors(from: parsed, transport: "DisplayPort")
    // Housekeeping codes (0x02, 0x52, 0xC9) mean nothing to people and are dropped.
    #expect(descriptors.map(\.rawCode) == ["VCP 0x04", "VCP 0x10", "VCP 0xE2"])
    let reset = try #require(descriptors.first(where: { $0.rawCode == "VCP 0x04" }))
    let vendor = try #require(descriptors.first(where: { $0.rawCode == "VCP 0xE2" }))
    #expect(reset.presentation == .connectionDetailsOnly && !reset.isSafelyEditable)
    #expect(vendor.presentation == .connectionDetailsOnly && vendor.evidence == .reportedUninterpreted)
    #expect(CapabilityRenderer.style(for: vendor) == .unavailable)
    // Even a successful read never makes a withheld or uninterpreted code editable.
    #expect(!vendor.recordingProbe(.read(current: 1, maximum: 1)).isSafelyEditable)
}

@Test func successfulProbeMakesSettingEditableWithReportedRange() throws {
    let parsed = try #require(MCCSCapabilities.parse("vcp(10)"))
    let brightness = try #require(CapabilityCatalog.descriptors(from: parsed, transport: "USB-C").first)
    let probed = brightness.recordingProbe(.read(current: 40, maximum: 80))
    #expect(probed.evidence == .safelyProbed)
    #expect(probed.isSafelyEditable)
    #expect(probed.currentValue == .number(40))
    #expect(probed.kind == .range(minimum: 0, maximum: 80, step: 1))
    #expect(CapabilityRenderer.style(for: probed) == .slider)
}

@Test func refusedOrSilentProbesStaySafe() throws {
    let parsed = try #require(MCCSCapabilities.parse("vcp(D6(01 04))"))
    let power = try #require(CapabilityCatalog.descriptors(from: parsed, transport: "HDMI").first)
    let refused = power.recordingProbe(.unsupported)
    let silent = power.recordingProbe(.noResponse)
    #expect(refused.evidence == .contradictory && !refused.isSafelyEditable)
    #expect(silent.evidence == .reportedOnly && !silent.isSafelyEditable)
    #expect(silent.currentValue == nil)
    #expect(power.requiresConfirmation)
}

@Test func optionNamesNeverExposeRawCodes() throws {
    let parsed = try #require(MCCSCapabilities.parse("vcp(60(0F 11 1B 1C))"))
    let plain = try #require(CapabilityCatalog.descriptors(from: parsed, transport: "USB-C").first)
    #expect(plain.kind == .options(["DisplayPort 1", "HDMI 1", "Other input 1", "Other input 2"]))
    let named = try #require(CapabilityCatalog.descriptors(from: parsed, transport: "USB-C", manufacturerNames: [0x60: [0x1B: "USB-C"]]).first)
    #expect(named.kind == .options(["DisplayPort 1", "HDMI 1", "USB-C", "Other input 1"]))
    #expect(named.requiresConfirmation)
}

@Test func encodeAndDecodeRoundTripThroughTheCatalog() throws {
    let parsed = try #require(MCCSCapabilities.parse("vcp(60(0F 11) 8D(01 02) 10)"))
    let descriptors = CapabilityCatalog.descriptors(from: parsed, transport: "DisplayPort")
    let input = try #require(descriptors.first(where: { $0.id == .input }))
    let mute = try #require(descriptors.first(where: { $0.id == .mute }))
    let brightness = try #require(descriptors.first(where: { $0.id == .brightness }))
    #expect(CapabilityCatalog.encode(.text("HDMI 1"), for: input) == 0x11)
    #expect(CapabilityCatalog.encode(.text("VGA 1"), for: input) == nil)
    #expect(CapabilityCatalog.decode(0x010F, for: input) == .text("DisplayPort 1"))
    #expect(CapabilityCatalog.encode(.boolean(true), for: mute) == 1)
    #expect(CapabilityCatalog.encode(.boolean(false), for: mute) == 2)
    #expect(CapabilityCatalog.decode(7, for: mute) == nil)
    #expect(CapabilityCatalog.encode(.number(.nan), for: brightness) == nil)
}

@Test func probeOfAnUnlistedCurrentOptionOffersItNeutrally() throws {
    let parsed = try #require(MCCSCapabilities.parse("vcp(60(0F 11))"))
    let input = try #require(CapabilityCatalog.descriptors(from: parsed, transport: "USB-C").first)
    let probed = input.recordingProbe(.read(current: 0x1B, maximum: 0))
    #expect(probed.currentValue == .text("Other input 1"))
    #expect(probed.kind == .options(["DisplayPort 1", "HDMI 1", "Other input 1"]))
    #expect(CapabilityCatalog.encode(.text("Other input 1"), for: probed) == 0x1B)
}

// MARK: - The demo OSD is generated, not hand-built

@Test func demoOSDComesFromTheCapabilityReport() throws {
    let dell = DemoData.displays(generation: 1)[1]
    let sections = dell.osdSections
    #expect(sections.map(\.category) == [.essentials, .display, .connectivity])
    #expect(sections[0].capabilities.map(\.id) == [.brightness, .contrast, .volume, .mute])
    let display = sections[1].capabilities
    let input = try #require(display.first(where: { $0.id == .input }))
    #expect(input.currentValue == .text("USB-C"))
    #expect(input.isSafelyEditable && input.requiresConfirmation)
    let power = try #require(display.first(where: { $0.id == .power }))
    #expect(power.evidence == .contradictory)
    #expect(CapabilityRenderer.style(for: power) == .readOnly)
    #expect(sections.allSatisfy { $0.capabilities.allSatisfy { $0.presentation == .osd } })
    #expect(dell.capabilities.contains { $0.presentation == .connectionDetailsOnly && $0.rawCode == "VCP 0xE2" })
}

@Test func softwareDimmingIsLabelledAndNeverHardware() throws {
    let lg = DemoData.displays(generation: 1)[2]
    let brightness = try #require(lg.capabilities.first(where: { $0.id == .brightness }))
    let volume = try #require(lg.capabilities.first(where: { $0.id == .volume }))
    #expect(lg.primaryRoute == .software)
    #expect(brightness.isSafelyEditable)
    #expect(ControlStatus.State.route(brightness.route).label == "Software dimming")
    #expect(CapabilityRenderer.style(for: volume) == .unavailable)
}

// MARK: - Transport channel

private actor FakeLink: DDCTransport {
    var reads: [UInt8] = []
    var writes: [(UInt8, UInt16)] = []
    let report: String
    let answers: [UInt8: ProbeResult]
    init(report: String, answers: [UInt8: ProbeResult]) { self.report = report; self.answers = answers }
    func capabilityString() async throws -> String { report }
    func read(code: UInt8) async throws -> ProbeResult { reads.append(code); return answers[code] ?? .noResponse }
    func write(code: UInt8, value: UInt16) async throws { writes.append((code, value)) }
}

@Test func discoveryOnlyReadsSettingsAndNeverTouchesMaintenanceCodes() async {
    let link = FakeLink(report: "vcp(04 05 10 60(0F 11) E2)", answers: [0x10: .read(current: 50, maximum: 100), 0x60: .read(current: 0x11, maximum: 0)])
    let profile = await CapabilityDiscovery.profile(using: link, transport: "DisplayPort")
    #expect(await link.reads == [0x10, 0x60])
    #expect(await link.writes.isEmpty)
    #expect(profile.filter(\.isSafelyEditable).map(\.id) == [.brightness, .input])
}

@Test func channelSendsCatalogCodesAndTreatsSilenceAsTransient() async throws {
    let link = FakeLink(report: "vcp(60(0F 11))", answers: [:])
    let parsed = try #require(MCCSCapabilities.parse("vcp(60(0F 11))"))
    let input = try #require(CapabilityCatalog.descriptors(from: parsed, transport: "USB-C").first)
    let channel = DDCControlChannel(link: link)
    try await channel.write(.text("HDMI 1"), descriptor: input)
    let writes = await link.writes
    #expect(writes.count == 1 && writes[0].0 == 0x60 && writes[0].1 == 0x11)
    await #expect(throws: ControlError.timedOut) { _ = try await channel.read(input) }
    await #expect(throws: ControlError.notWritable) { try await channel.write(.text("VGA 1"), descriptor: input) }
}

// MARK: - Write safety

@Test @MainActor func suspendedPipelineRejectsWritesWithoutTouchingTheDisplay() async throws {
    let adapter = CountingAdapter()
    let pipeline = DisplayWritePipeline()
    let display = DemoData.displays(generation: 3)[1]
    await pipeline.setTopologyGeneration(3)
    await pipeline.setSuspended(true)
    let descriptor = try #require(display.capabilities.first(where: { $0.id == .brightness }))
    await #expect(throws: ControlError.suspended) { _ = try await pipeline.write(descriptor: descriptor, value: .number(40), display: display, adapter: adapter) }
    #expect(adapter.writeCount == 0)
    await pipeline.setSuspended(false)
    _ = try await pipeline.write(descriptor: descriptor, value: .number(40), display: display, adapter: adapter)
    #expect(adapter.writeCount == 1)
}

@Test @MainActor func sleepPausesWritesVisibly() async {
    // Demo displays, so the test never reaches this Mac's real hardware.
    let store = GlowStore(demoDisplays: true)
    await store.start()
    store.handle(.sleep)
    #expect(store.pauseReason == "Displays are asleep")
}

@MainActor private final class CountingAdapter: DisplayAdapter {
    let name = "Counting"
    var writeCount = 0
    private var stored: CapabilityValue = .number(0)
    func discover(generation: UInt64) async -> [DisplaySnapshot] { [] }
    func write(_ value: CapabilityValue, capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws { writeCount += 1; stored = value }
    func read(capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws -> CapabilityValue { stored }
}

// MARK: - What the catalog covers

@Test func catalogCoversEveryStandardOSDSetting() {
    // Each is one catalog entry; none needs its own UI code.
    let expected: [CapabilityIdentifier: UInt8] = [
        .brightness: 0x10, .contrast: 0x12, .volume: 0x62, .mute: 0x8D, .input: 0x60, .preset: 0x14,
        .redGain: 0x16, .greenGain: 0x18, .blueGain: 0x1A,
        .redBlackLevel: 0x6C, .greenBlackLevel: 0x6E, .blueBlackLevel: 0x70,
        .sharpness: 0x87, .gamma: 0x72, .osdLanguage: 0xCC, .power: 0xD6, .usageTime: 0xC0
    ]
    for (id, code) in expected {
        #expect(CapabilityCatalog.entry(for: id)?.code == code, "\(id.rawValue)")
    }
    let entries = CapabilityCatalog.entries
    #expect(Set(entries.map(\.code)).count == entries.count)
    #expect(Set(entries.map(\.id)).count == entries.count)
}

@Test func blackLevelsAreSlidersOnceRead() throws {
    let parsed = try #require(MCCSCapabilities.parse("vcp(6C 6E 70)"))
    let descriptors = CapabilityCatalog.descriptors(from: parsed, transport: "DisplayPort")
    #expect(descriptors.map(\.id) == [.redBlackLevel, .greenBlackLevel, .blueBlackLevel])
    for descriptor in descriptors {
        let probed = descriptor.recordingProbe(.read(current: 50, maximum: 100))
        #expect(probed.isSafelyEditable && CapabilityRenderer.style(for: probed) == .slider)
    }
}

@Test func gammaLanguageAndHoursAreShownButNeverChanged() throws {
    let parsed = try #require(MCCSCapabilities.parse("vcp(72 CC C0)"))
    let descriptors = CapabilityCatalog.descriptors(from: parsed, transport: "DisplayPort")
    let readings: [CapabilityIdentifier: (ProbeResult, CapabilityValue)] = [
        .gamma: (.read(current: 0x78, maximum: 0), .text("2.2")),
        .osdLanguage: (.read(current: 0x02, maximum: 0), .text("English")),
        .usageTime: (.read(current: 240, maximum: 0), .text("240 hours"))
    ]
    #expect(Set(descriptors.map(\.id)) == Set(readings.keys))
    for descriptor in descriptors {
        let (reading, value) = try #require(readings[descriptor.id])
        let probed = descriptor.recordingProbe(reading)
        #expect(probed.access == .readOnly && probed.evidence == .safelyProbed)
        #expect(probed.currentValue == value)
        #expect(!probed.isSafelyEditable && CapabilityRenderer.style(for: probed) == .readOnly)
        #expect(CapabilityCatalog.encode(value, for: probed) == nil)
    }
    #expect(CapabilityCatalog.gamma(current: 0x78) == 2.2)
    #expect(CapabilityCatalog.gamma(current: 0x50) == 1.8)
    // Hours: the maximum's low byte is the high byte of a 24-bit count.
    #expect(CapabilityCatalog.usageHours(current: 0x1234, maximum: 0x01) == 0x01_1234)
    #expect(CapabilityCatalog.usageText(current: 1, maximum: 0) == "1 hour")
}
