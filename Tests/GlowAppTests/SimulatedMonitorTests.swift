import Testing
@testable import GlowApp

// The simulated DDC/CI monitors (`SimulatedMonitor`, `SimulatedDisplayAdapter`): firmware
// that checks Glow's bytes and answers in reply bytes, with each model's quirks, driven
// through discovery, `DDCControlChannel` and the store. Every monitor runs on its own
// virtual clock, so a three-second discovery takes no time.

private func monitor(_ model: SimulatedMonitor.Model) -> SimulatedMonitor {
    SimulatedMonitor(model, clock: .virtual())
}

private func model(_ id: String) -> SimulatedMonitor.Model { SimulatedMonitor.Model.named(id)! }

private func identity(_ model: SimulatedMonitor.Model) -> PersistentDisplayIdentity {
    PersistentDisplayIdentity(vendorID: model.vendorID, productID: model.productID, serialNumber: model.serialNumber)
}

private func discover(_ monitor: SimulatedMonitor) async -> DDCProbe {
    await DDCProbe.run(transport: SimulatedDisplayAdapter.transport, profiles: DDCTransportProfile.ladder) { monitor.link(profile: $0) }
}

/// One request as a host sends it, and the reply once the monitor has had time to answer.
private func exchange(_ monitor: SimulatedMonitor, _ packet: [UInt8], source: UInt8 = 0x51, count: Int = DDCPacket.getVCPReplyLength) -> [UInt8] {
    _ = monitor.write(packet, source: source)
    monitor.clock.advance(by: monitor.model.quirks.replyDelay)
    return (try? monitor.read(count: count).get()) ?? []
}

// MARK: - Firmware

@Test func getVCPIsAnsweredInTheBytesAMonitorSends() {
    let dell = monitor(.dellU3011)
    // Brightness 75 of 100, checksummed from 0x50.
    #expect(exchange(dell, DDCPacket.getVCP(0x10)) == [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x4B, 0x8B])
    #expect(dell.log == [.getVCP(0x10)])
    // A code it didn't report: "unsupported".
    #expect(DDCPacket.parseGetVCPReply(exchange(dell, DDCPacket.getVCP(0x62)), code: 0x62) == .value(.unsupported))
}

@Test func everyRequestGlowBuildsIsOneTheFirmwareAccepts() {
    let dell = monitor(.dellU3011)
    for packet in [DDCPacket.getVCP(0x12), DDCPacket.setVCP(0x12, value: 70), DDCPacket.saveSettings(), DDCPacket.capabilities(offset: 64)] {
        _ = dell.write(packet, source: 0x51)
    }
    #expect(dell.log == [.getVCP(0x12), .setVCP(0x12, 70), .saveSettings, .capabilities(offset: 64)])
    #expect(dell.counters == .init())
    // On the alternate address, the checksum starts from 0x50 instead.
    let lg = monitor(.lg27MD5KL)
    _ = lg.write(DDCPacket.getVCP(0x10, source: 0x50), source: 0x50)
    #expect(lg.log == [.getVCP(0x10)])
}

@Test func badFramingAndChecksumsAreThrownAway() {
    let dell = monitor(.dellU3011)
    var garbled = DDCPacket.getVCP(0x10)
    garbled[garbled.count - 1] ^= 0x01
    var short = DDCPacket.getVCP(0x10)
    short[0] = 0x83
    // Each is dropped without a reply, as firmware does.
    for packet in [garbled, short, DDCPacket.request([0x07]), [], DDCPacket.getVCP(0x10, source: 0x50)] {
        #expect(exchange(dell, packet).allSatisfy { $0 == 0 })
    }
    #expect(dell.counters.rejected == 5)
    // The right bytes from an address it doesn't answer are ignored, not rejected.
    #expect(exchange(dell, DDCPacket.getVCP(0x10, source: 0x50), source: 0x50).allSatisfy { $0 == 0 })
    #expect(dell.counters.ignored == 1)
    #expect(dell.log.isEmpty)
}

@Test func aReadBeforeTheReplyIsReadyGetsNothing() throws {
    let aoc = monitor(.aocC24G2)
    _ = aoc.write(DDCPacket.getVCP(0x10), source: 0x51)
    aoc.clock.advance(by: .milliseconds(50))
    #expect(try aoc.read(count: 11).get().allSatisfy { $0 == 0 })
    #expect(aoc.counters.earlyReads == 1)
    aoc.clock.advance(by: .milliseconds(70))
    #expect(DDCPacket.parseGetVCPReply(try aoc.read(count: 11).get(), code: 0x10) == .value(.read(current: 50, maximum: 100)))
}

@Test func setVCPKeepsToWhatTheMonitorAllows() {
    let lg = monitor(.lg29UM69G)
    for (code, value) in [(0x12, 250), (0x60, 0x05), (0x60, 0x0F), (0xC0, 0), (0x87, 10)] as [(UInt8, UInt16)] {
        _ = lg.write(DDCPacket.setVCP(code, value: value), source: 0x51)
    }
    // Continuous settings stop at their maximum; a value it didn't list, a read-only code
    // and a code it doesn't have change nothing.
    #expect(lg.value(of: 0x12) == 100)
    #expect(lg.value(of: 0x60) == 0x0F)
    #expect(lg.value(of: 0xC0) == 812)
    #expect(lg.value(of: 0x87) == nil)
}

@Test func theResetCommandsPutSettingsBack() {
    let dell = monitor(.dellU3011)
    for (code, value) in [(0x10, 20), (0x12, 20), (0x16, 20), (0x05, 1)] as [(UInt8, UInt16)] {
        _ = dell.write(DDCPacket.setVCP(code, value: value), source: 0x51)
    }
    dell.clock.advance(by: .milliseconds(100))
    // 0x05 restores brightness and contrast only.
    #expect([dell.value(of: 0x10), dell.value(of: 0x12), dell.value(of: 0x16)] == [75, 75, 20])
}

@Test func capabilityFragmentsEchoTheirOffset() {
    let dell = monitor(.dellU3011)
    let text = Array(dell.model.capabilityString.utf8)
    let fragment = exchange(dell, DDCPacket.capabilities(offset: 32), count: DDCPacket.capabilitiesReplyLength)
    #expect(Array(fragment.prefix(5)) == [0x6E, 0xA3, 0xE3, 0x00, 0x20])
    #expect(DDCPacket.parseCapabilitiesReply(fragment, offset: 32) == .data(Array(text[32..<64])))
    let end = exchange(dell, DDCPacket.capabilities(offset: UInt16(text.count)), count: DDCPacket.capabilitiesReplyLength)
    #expect(DDCPacket.parseCapabilitiesReply(end, offset: UInt16(text.count)) == .end)
}

@Test func eachReportReassemblesExactly() throws {
    // The Dell's report is exactly seven fragments long, so an empty eighth ends it.
    let dell = monitor(.dellU3011)
    #expect(try dell.session(profile: .standard).readCapabilities() == dell.model.capabilityString)
    #expect(dell.log == stride(from: 0, through: 224, by: 32).map { .capabilities(offset: UInt16($0)) })
    // The LG pads its last fragment with NULs, which end the report without an empty one.
    let lg = monitor(.lg27MD5KL)
    #expect(try lg.session(profile: .alternate).readCapabilities() == lg.model.capabilityString)
    #expect(lg.log == stride(from: 0, through: 256, by: 32).map { .capabilities(offset: UInt16($0)) })
    // The AOC's compact report arrives only on slower timing, every request sent twice.
    let aoc = monitor(.aocC24G2)
    #expect(try aoc.session(profile: .slow).readCapabilities() == aoc.model.capabilityString)
    // The LG 29UM69G answers with the null message until Glow gives up.
    let quiet = monitor(.lg29UM69G)
    #expect(throws: DDCError.timedOut) { try quiet.session(profile: .standard).readCapabilities() }
}

@Test(arguments: SimulatedMonitor.Model.all.map(\.id))
func theFirmwareAndGlowReadAReportTheSameWay(_ id: String) throws {
    let model = model(id)
    let glows = try #require(MCCSCapabilities.parse(model.capabilityString))
    let firmware = SimulatedMonitor.features(in: model.capabilityString)
    #expect(Set(glows.codes.map(\.code)) == Set(firmware.keys))
    for (code, values) in glows.codes {
        #expect(firmware[code]?.values ?? [] == values, "VCP 0x\(DDCPacket.hex(code))")
    }
}

// MARK: - Quirks

@Test func aHostThatSkipsTheSettleReadsTheOldValue() throws {
    let dell = monitor(.dellU3011)
    var hasty = DDCTransportProfile.standard
    hasty.settleAfterSet = .zero
    let session = dell.session(profile: hasty)
    try session.setVCP(0x10, value: 80)
    #expect(try session.getVCP(0x10) == .read(current: 75, maximum: 100))
    dell.clock.advance(by: .milliseconds(90))
    #expect(try session.getVCP(0x10) == .read(current: 80, maximum: 100))
}

@Test func aRequestTooSoonAfterAChangeGetsTheNullMessage() throws {
    let aoc = monitor(.aocC24G2)
    _ = aoc.write(DDCPacket.setVCP(0x10, value: 55), source: 0x51)
    let reply = exchange(aoc, DDCPacket.getVCP(0x10))
    #expect(Array(reply.prefix(3)) == [0x6E, 0x80, 0xBE])
    #expect(DDCPacket.parseGetVCPReply(reply, code: 0x10) == .invalid(.unexpectedReply("opcode 0xBE")))
    #expect(aoc.counters.droppedWhileBusy == 1)
    // Slower timing sends everything twice: the second Set and the first Get land in the
    // busy window, and the second Get is answered.
    let session = aoc.session(profile: .slow)
    try session.setVCP(0x10, value: 60)
    #expect(try session.getVCP(0x10) == .read(current: 60, maximum: 100))
    #expect(aoc.counters.droppedWhileBusy == 3)
}

@Test func aGarbledReplyIsAskedAgain() throws {
    let lg = monitor(.lg29UM69G)
    let replies = (0..<5).map { _ in DDCPacket.parseGetVCPReply(exchange(lg, DDCPacket.getVCP(0x10)), code: 0x10) }
    #expect(replies.last == .invalid(.badChecksum))
    #expect(replies.dropLast().allSatisfy { $0 == .value(.read(current: 40, maximum: 100)) })
    // Glow's session retries the next one it spoils.
    let session = lg.session(profile: .standard)
    for _ in 0..<5 { #expect(try session.getVCP(0x12) == .read(current: 60, maximum: 100)) }
    #expect(lg.counters.garbled == 2)
}

// MARK: - Discovery

private let expectedProfile: [String: DDCTransportProfile] = [
    "dell-u3011": .standard, "aoc-c24g2": .slow, "lg-27md5kl": .alternate, "lg-29um69g": .standard
]

private let colorLevels: Set<CapabilityIdentifier> = [.redGain, .greenGain, .blueGain]

private let expectedEditable: [String: Set<CapabilityIdentifier>] = [
    "dell-u3011": colorLevels.union([.brightness, .contrast, .input, .preset, .pictureMode, .power]),
    "aoc-c24g2": colorLevels.union([.brightness, .contrast, .volume, .mute, .input, .preset, .pictureMode, .power,
                                    .redBlackLevel, .greenBlackLevel, .blueBlackLevel]),
    "lg-27md5kl": colorLevels.union([.brightness, .contrast, .input, .preset, .sharpness, .power]),
    // No report: only low-risk sliders and switches it answered.
    "lg-29um69g": colorLevels.union([.brightness, .contrast, .volume, .mute])
]

@Test(arguments: SimulatedMonitor.Model.all.map(\.id))
func discoveryFindsEachModelsProfileAndSettings(_ id: String) async throws {
    let model = model(id)
    let monitor = monitor(model)
    let probe = await discover(monitor)
    #expect(probe.log.workingProfile == expectedProfile[id])
    #expect(probe.capabilityString == (model.quirks.sendsCapabilities ? model.capabilityString : nil))
    #expect(Set(probe.descriptors.filter(\.isSafelyEditable).map(\.id)) == expectedEditable[id])

    let brightness = try #require(probe.descriptors.first { $0.id == .brightness })
    #expect(brightness.evidence == (model.quirks.sendsCapabilities ? .safelyProbed : .answeredUnlisted))
    #expect(brightness.currentValue == .number(Double(model.start[0x10]!)))
    #expect(probe.descriptors.first { $0.id == .contrast }?.currentValue == .number(Double(model.start[0x12]!)))
    if !model.quirks.sendsCapabilities {
        // Nothing listed the input, so it stays read-only.
        #expect(probe.descriptors.first { $0.id == .input }?.access == .readOnly)
        #expect(monitor.counters.garbled > 0)
    }

    // Discovery only reads, in bytes the firmware accepts.
    #expect(monitor.writes.isEmpty)
    #expect(monitor.counters.rejected == 0)
    if model.quirks.sources == [0x50] {
        // The standard and slower profiles asked at 0x51, which it doesn't answer.
        #expect(monitor.counters.ignored > 0)
    } else {
        #expect(monitor.counters.ignored == 0)
    }
}

// MARK: - DDCControlChannel

@Test(arguments: SimulatedMonitor.Model.all.map(\.id))
func theControlChannelWritesReadsBackAndRestores(_ id: String) async throws {
    let model = model(id)
    let monitor = monitor(model)
    let probe = await discover(monitor)
    let channel = DDCControlChannel(link: try #require(probe.link))
    monitor.clearLog()
    var tried: [UInt8] = []
    for (id, code) in [(CapabilityIdentifier.brightness, UInt8(0x10)), (.contrast, 0x12), (.volume, 0x62)] {
        guard let descriptor = probe.descriptors.first(where: { $0.id == id }), descriptor.isSafelyEditable,
              case let .number(original)? = descriptor.currentValue else { continue }
        tried.append(code)
        try await channel.write(.number(original + 5), descriptor: descriptor)
        monitor.clock.advance(by: model.quirks.readBackLag)
        #expect(try await channel.read(descriptor) == .number(original + 5))
        try await channel.write(.number(original), descriptor: descriptor)
        monitor.clock.advance(by: model.quirks.readBackLag)
        #expect(try await channel.read(descriptor) == .number(original))
        #expect(monitor.value(of: code) == UInt16(original))
    }
    #expect(tried.count >= 2)
    // Exactly the codes asked for went out, and nothing else.
    #expect(monitor.writes.map(\.code) == tried.flatMap { [$0, $0] })
    #expect(monitor.counters.rejected == 0)
}

// MARK: - Adapter

@Test func theLaunchArgumentNamesModels() {
    #expect(SimulatedDisplayAdapter.models(in: ["Glow"]) == nil)
    #expect(SimulatedDisplayAdapter.models(in: ["Glow", "-GlowSimulatedMonitors", "all"])?.models == SimulatedMonitor.Model.all)
    #expect(SimulatedDisplayAdapter.models(in: ["Glow", "-GlowSimulatedMonitors"])?.models == SimulatedMonitor.Model.all)
    let some = SimulatedDisplayAdapter.models(in: ["Glow", "-GlowSimulatedMonitors", "aoc-c24g2,LG-29UM69G,benq"])
    #expect(some?.models.map(\.id) == ["aoc-c24g2", "lg-29um69g"])
    #expect(some?.unknown == ["benq"])
}

@MainActor private func simulatedAdapter(safeMode: Bool = false) -> SimulatedDisplayAdapter {
    SimulatedDisplayAdapter(monitors: SimulatedMonitor.Model.all.map(monitor), safeMode: safeMode)
}

@MainActor @Test func theAdapterShowsEachMonitorAsAnExternalDisplay() async throws {
    let adapter = simulatedAdapter()
    let displays = await adapter.discover(generation: 1)
    #expect(displays.map(\.name) == SimulatedMonitor.Model.all.map { "\($0.name) (simulated)" })
    #expect(displays.map(\.id) == SimulatedMonitor.Model.all.map(identity))
    #expect(displays.allSatisfy { !$0.isBuiltIn && !$0.isDemo && $0.connection.transport == SimulatedDisplayAdapter.transport })
    #expect(displays.map(\.connection.displayID) == [0x5100_0001, 0x5100_0002, 0x5100_0003, 0x5100_0004])
    let aoc = try #require(displays.first { $0.id == identity(.aocC24G2) })
    #expect(aoc.connectionNotes.contains { $0.contains(SimulatedMonitor.Model.aocC24G2.source) })
    #expect(aoc.connectionNotes.contains("DDC/CI profile: \(DDCTransportProfile.slow.name): \(DDCTransportProfile.slow.summary)"))
    #expect(adapter.discoveryLog(for: aoc.id)?.workingProfile == .slow)
    #expect(aoc.capabilities.allSatisfy { $0.route == .hardware })
}

@MainActor private final class Published {
    var lists: [[DisplaySnapshot]] = []
}

@MainActor @Test func theAdapterShowsEveryMonitorBeingCheckedThenEachAsItFinishes() async {
    let adapter = simulatedAdapter()
    let published = Published()
    let displays = await adapter.discover(generation: 1) { published.lists.append($0) }
    let count = SimulatedMonitor.Model.all.count
    #expect(published.lists.count == count + 1)
    let first = published.lists.first ?? []
    #expect(first.map(\.id) == displays.map(\.id))
    #expect(first.allSatisfy { $0.isChecking && $0.capabilities.isEmpty && $0.summaryStatus(isPaused: false) == .checking })
    // One fewer is being checked each time, until none is.
    #expect(published.lists.map { $0.filter(\.isChecking).count } == Array((0...count).reversed()))
    #expect(published.lists.last == displays)
}

@MainActor @Test func theAdapterReadsAChangeMadeOnTheMonitor() async throws {
    let adapter = simulatedAdapter()
    let displays = await adapter.discover(generation: 1)
    let lg = try #require(displays.first { $0.id == identity(.lg27MD5KL) })
    adapter.connected[lg.id]?.monitor.setOnDisplay(0x10, to: 33)
    #expect(try await adapter.read(capability: .brightness, display: lg.id) == .number(33))
    #expect(try await adapter.readReported(code: 0xFD, display: lg.id) == .read(current: 50, maximum: 100))
}

@MainActor @Test func safeModeReadsButNeverSetsAnything() async throws {
    let adapter = simulatedAdapter(safeMode: true)
    let displays = await adapter.discover(generation: 1)
    let dell = try #require(displays.first)
    #expect(dell.connectionNotes.contains { $0.hasPrefix("Safe mode") })
    await #expect(throws: ControlError.adapter(HardwareDisplayAdapter.safeModeMessage)) {
        try await adapter.write(.number(50), capability: .brightness, display: dell.id)
    }
    #expect(adapter.monitors.allSatisfy { $0.writes.isEmpty })
}

// MARK: - Through the store

@MainActor private func setting(_ id: CapabilityIdentifier, on display: PersistentDisplayIdentity, in store: GlowStore) -> CapabilityDescriptor? {
    store.displays.first { $0.id == display }?.capabilities.first { $0.id == id }
}

/// Waits for a run of writes to be confirmed.
@MainActor private func settle(_ store: GlowStore, _ id: CapabilityIdentifier, on display: PersistentDisplayIdentity) async throws {
    for _ in 0..<100 {
        guard setting(id, on: display, in: store)?.pendingValue != nil else { return }
        try await Task.sleep(for: .milliseconds(20))
    }
}

@MainActor @Test func confirmedWritesReachEachMonitorAndComeBack() async throws {
    let adapter = simulatedAdapter()
    try await MatchFixture.withStore(adapter: adapter) { store in
        await store.refresh()
        #expect(store.displays.count == 4)
        for monitor in adapter.monitors {
            let id = identity(monitor.model)
            let original = Double(monitor.model.start[0x10]!)
            monitor.clearLog()
            let raised = try await store.confirmWrite(displayID: id, capabilityID: .brightness, value: .number(original + 5))
            #expect(raised == .number(original + 5))
            #expect(monitor.value(of: 0x10) == UInt16(original + 5))
            if monitor.model == .dellU3011 {
                // Its change shows late, so the first read-back still has 75 and the
                // pipeline's second try confirms it.
                #expect(monitor.log == [.setVCP(0x10, 80), .getVCP(0x10), .setVCP(0x10, 80), .getVCP(0x10)])
            }
            let restored = try await store.confirmWrite(displayID: id, capabilityID: .brightness, value: .number(original))
            #expect(restored == .number(original))
            #expect(monitor.value(of: 0x10) == UInt16(original))
            #expect(setting(.brightness, on: id, in: store)?.lastConfirmedValue == .number(original))
            #expect(monitor.writes.allSatisfy { $0.code == 0x10 })
            // Restore starting values reads what discovery found, before any change.
            #expect(store.startingValues(for: id)[.brightness] == .number(original))
        }
    }
}

@MainActor @Test func aHeldKeyRampsTheFocusedMonitorAndConfirmsTheLastStep() async throws {
    let adapter = simulatedAdapter()
    try await MatchFixture.withStore(adapter: adapter) { store in
        await store.refresh()
        for monitor in adapter.monitors {
            let id = identity(monitor.model)
            let original = Double(monitor.model.start[0x10]!)
            monitor.clearLog()
            store.controlTarget = .focused
            store.focusedDisplayID = id
            for _ in 0..<5 { #expect(store.rampBrightness(.up, pointerDisplay: nil) == nil) }
            try await settle(store, .brightness, on: id)
            #expect(setting(.brightness, on: id, in: store)?.lastConfirmedValue == .number(original + 5))
            #expect(monitor.value(of: 0x10) == UInt16(original + 5))
            // Only brightness went out, climbing, and the last one is where the key stopped.
            let sent = monitor.writes.map(\.value)
            #expect(monitor.writes.allSatisfy { $0.code == 0x10 })
            #expect(sent.last == UInt16(original + 5))
            #expect(sent == sent.sorted())
        }
    }
}

@MainActor @Test func aSceneAppliesOnlyWhatItMayAndSaysSo() async {
    let adapter = simulatedAdapter()
    let dell = identity(.dellU3011), aoc = identity(.aocC24G2), lg = identity(.lg29UM69G)
    await MatchFixture.withStore(adapter: adapter) { store in
        await store.refresh()
        let monitors = Dictionary(uniqueKeysWithValues: adapter.monitors.map { (identity($0.model), $0) })
        monitors.values.forEach { $0.clearLog() }
        let scene = GlowScene(id: "night", name: "Night", symbol: "moon", values: [
            dell: [.brightness: .number(30), .contrast: .number(60), .input: .text("HDMI 1")],
            aoc: [.brightness: .number(20), .volume: .number(10), .power: .text("Off")],
            lg: [.brightness: .number(25), .mute: .boolean(true)]
        ], on: store.displays)
        let result = await store.applyScene(scene)
        #expect(result.succeeded == 6)
        #expect(result.failed == 0)
        // The new input asks first, and power is never part of a scene.
        #expect(result.heldBack == 1)
        #expect(result.skipped == 1)
        #expect([monitors[dell]?.value(of: 0x10), monitors[dell]?.value(of: 0x12), monitors[dell]?.value(of: 0x60)] == [30, 60, 0x0F])
        #expect([monitors[aoc]?.value(of: 0x10), monitors[aoc]?.value(of: 0x62), monitors[aoc]?.value(of: 0xD6)] == [20, 10, 0x01])
        #expect([monitors[lg]?.value(of: 0x10), monitors[lg]?.value(of: 0x8D)] == [25, 0x01])

        // Asked and agreed, the input goes too.
        let asked = await store.applyScene(scene, includingAsksFirst: true)
        #expect(asked.heldBack == 0)
        #expect(monitors[dell]?.value(of: 0x60) == 0x11)
        // Every Set VCP on the wire was a setting the scene named.
        let written = Set(monitors.values.flatMap { $0.writes.map(\.code) })
        #expect(written == [0x10, 0x12, 0x60, 0x62, 0x8D])
        #expect(monitors.values.allSatisfy { $0.counters.rejected == 0 })
    }
}
