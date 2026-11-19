import Testing
@testable import GlowApp

// Settings › Reading (ADR 0002): rereads and their schedule, what they give way to, the
// "Changed on the display" mark, back-off, launch restore, Patience, the codes the catalog
// doesn't know, and Hide. Every test uses demo or mock adapters and its own clock.

private let dell = DemoData.dellIdentity
private let mac = DemoData.macIdentity
private let lg = DemoData.lgIdentity

@MainActor private func demoAdapter() -> MockDisplayAdapter {
    let adapter = MockDisplayAdapter()
    adapter.readDelay = .zero
    return adapter
}

@MainActor private func setting(_ id: CapabilityIdentifier, on display: PersistentDisplayIdentity, in store: GlowStore) -> CapabilityDescriptor? {
    store.displays.first(where: { $0.id == display })?.capabilities.first(where: { $0.id == id })
}

/// Lets an in-flight write finish: the mock takes about 150 ms with its read-back.
@MainActor private func settle(_ store: GlowStore, _ id: CapabilityIdentifier, on display: PersistentDisplayIdentity) async throws {
    for _ in 0..<100 where setting(id, on: display, in: store)?.pendingValue != nil {
        try await Task.sleep(for: .milliseconds(20))
    }
    try await Task.sleep(for: .milliseconds(20))
}

// MARK: - Schedule

@Test func freshnessChoosesTheIntervals() {
    #expect(ReadingSchedule.intervals(.off, isOpen: true) == nil)
    #expect(ReadingSchedule.intervals(.off, isOpen: false) == nil)
    #expect(ReadingSchedule.intervals(.whileOpen, isOpen: true) == ReadingSchedule.open)
    #expect(ReadingSchedule.intervals(.whileOpen, isOpen: false) == nil)
    #expect(ReadingSchedule.intervals(.always, isOpen: true) == ReadingSchedule.open)
    #expect(ReadingSchedule.intervals(.always, isOpen: false) == ReadingSchedule.background)
    #expect(ReadingSchedule.open == .init(frequent: 5, rare: 60))
    #expect(ReadingSchedule.background == .init(frequent: 45, rare: 600))
}

@Test func dueFollowsTheTwoTiersAndTheBackoff() {
    let read = DisplayReadingClock(lastFrequent: ReadingFixture.date(0), lastRare: ReadingFixture.date(0))
    let open = ReadingSchedule.open
    #expect(ReadingSchedule.due(read, intervals: open, now: ReadingFixture.date(4)) == nil)
    #expect(ReadingSchedule.due(read, intervals: open, now: ReadingFixture.date(5)) == .frequent)
    #expect(ReadingSchedule.due(read, intervals: open, now: ReadingFixture.date(60)) == .allSettings)
    #expect(ReadingSchedule.due(read, intervals: nil, now: ReadingFixture.date(600)) == nil)
    #expect(ReadingSchedule.due(DisplayReadingClock(), intervals: open, now: ReadingFixture.date(0)) == .allSettings)
    var silent = read
    silent.backoffUntil = ReadingFixture.date(100)
    #expect(ReadingSchedule.due(silent, intervals: open, now: ReadingFixture.date(99)) == nil)
    #expect(ReadingSchedule.due(silent, intervals: open, now: ReadingFixture.date(100)) == .allSettings)
}

@Test func backoffDoublesFromThirtySecondsToFifteenMinutes() {
    #expect((1...7).map(ReadingSchedule.backoff(afterSilentPasses:)) == [30, 60, 120, 240, 480, 900, 900])
}

@Test @MainActor func whileOpenRereadsOftenOnlyWhileGlowIsOpen() async {
    await ReadingFixture.withSuite { defaults in
        let adapter = demoAdapter()
        let clock = ReadingTestClock()
        let store = await ReadingFixture.store(defaults, adapter: adapter, clock: clock)
        let before = adapter.totalReads

        clock.seconds = 4
        await store.readingTick(now: clock.now)
        #expect(adapter.totalReads == before)

        // The frequent tier: brightness, volume and mute, on each display that has them.
        clock.seconds = 5
        await store.readingTick(now: clock.now)
        #expect(adapter.readCount(.brightness, on: dell) == 1)
        #expect(adapter.readCount(.volume, on: dell) == 1)
        #expect(adapter.readCount(.mute, on: dell) == 1)
        #expect(adapter.readCount(.contrast, on: dell) == 0)
        #expect(adapter.readCount(.brightness, on: mac) == 1)

        // The rare tier: every readable OSD setting.
        clock.seconds = 60
        await store.readingTick(now: clock.now)
        #expect(adapter.readCount(.contrast, on: dell) == 1)
        #expect(adapter.readCount(.sharpness, on: dell) == 1)
        #expect(adapter.readCount(.brightness, on: dell) == 2)

        // Closed: nothing at all.
        clock.isOpen = false
        let closed = adapter.totalReads
        for seconds in [65.0, 120, 700, 4_000] {
            clock.seconds = seconds
            await store.readingTick(now: clock.now)
        }
        #expect(adapter.totalReads == closed)
        // Software dimming is Glow's own state: the LG is never asked.
        #expect(adapter.readCount(.brightness, on: lg) == 0)
        #expect(adapter.totalWrites == 0)
    }
}

@Test @MainActor func alwaysRereadsSlowlyInTheBackground() async {
    await ReadingFixture.withSuite { defaults in
        let adapter = demoAdapter()
        let clock = ReadingTestClock()
        clock.isOpen = false
        let store = await ReadingFixture.store(defaults, adapter: adapter, clock: clock, freshness: .always)

        clock.seconds = 44
        await store.readingTick(now: clock.now)
        #expect(adapter.readCount(.brightness, on: dell) == 0)
        clock.seconds = 45
        await store.readingTick(now: clock.now)
        #expect(adapter.readCount(.brightness, on: dell) == 1)
        #expect(adapter.readCount(.contrast, on: dell) == 0)
        clock.seconds = 600
        await store.readingTick(now: clock.now)
        #expect(adapter.readCount(.contrast, on: dell) == 1)
        // Open again, it's back to every few seconds.
        clock.isOpen = true
        clock.seconds = 605
        await store.readingTick(now: clock.now)
        #expect(adapter.readCount(.brightness, on: dell) == 3)
    }
}

@Test @MainActor func offNeverRereadsButReadAgainStillReads() async {
    await ReadingFixture.withSuite { defaults in
        let adapter = demoAdapter()
        let clock = ReadingTestClock()
        let store = await ReadingFixture.store(defaults, adapter: adapter, clock: clock, freshness: .off)
        for seconds in [5.0, 60, 600, 6_000] {
            clock.seconds = seconds
            await store.readingTick(now: clock.now)
        }
        clock.isOpen = false
        clock.seconds = 7_000
        await store.readingTick(now: clock.now)
        #expect(adapter.totalReads == 0)
        await store.readAgain(dell)
        #expect(adapter.readCount(.brightness, on: dell) == 1)
        #expect(adapter.readCount(.contrast, on: dell) == 1)
    }
}

// MARK: - Giving way

@Test @MainActor func nothingIsReadWhileWritesArePaused() async {
    await ReadingFixture.withSuite { defaults in
        let adapter = demoAdapter()
        let clock = ReadingTestClock()
        let store = await ReadingFixture.store(defaults, adapter: adapter, clock: clock)
        store.handle(.sleep)
        #expect(store.pauseReason != nil)
        clock.seconds = 60
        await store.readingTick(now: clock.now)
        #expect(await store.readAgain(dell).isEmpty)
        #expect(adapter.totalReads == 0)
    }
}

@Test @MainActor func aSettingBeingChangedIsSkippedAndKeepsItsValue() async throws {
    try await ReadingFixture.withSuite { defaults in
        let adapter = demoAdapter()
        let clock = ReadingTestClock()
        let store = await ReadingFixture.store(defaults, adapter: adapter, clock: clock)
        store.update(displayID: dell, capabilityID: .brightness, proposed: .number(40))
        #expect(setting(.brightness, on: dell, in: store)?.pendingValue == .number(40))

        clock.seconds = 5
        let outcomes = await store.readPass(dell, scope: .frequent, now: clock.now)
        let brightness = try #require(outcomes.first { $0.capability == .brightness })
        #expect(brightness.result == .skipped("A change is on its way"))
        #expect(adapter.readCount(.brightness, on: dell) == 0)
        #expect(outcomes.first { $0.capability == .volume }?.wasRead == true)
        #expect(setting(.brightness, on: dell, in: store)?.currentValue == .number(40))

        // Once it lands, Glow keeps clear of the display for a moment, then reads it again.
        try await settle(store, .brightness, on: dell)
        #expect(setting(.brightness, on: dell, in: store)?.pendingValue == nil)
        let soon = await store.readPass(dell, scope: .frequent, now: clock.now)
        #expect(soon.allSatisfy { $0.result == .skipped("Glow changed this display a moment ago") })
        store.reading.writeQuiet = .zero
        let later = await store.readPass(dell, scope: .frequent, now: clock.now)
        #expect(later.first { $0.capability == .brightness }?.result == .unchanged)
        #expect(setting(.brightness, on: dell, in: store)?.currentValue == .number(40))
    }
}

@Test @MainActor func theFunnelMergesOneSettingAndLeavesAChangeInFlightAlone() async {
    await ReadingFixture.withSuite { defaults in
        let clock = ReadingTestClock()
        let store = await ReadingFixture.store(defaults, adapter: demoAdapter(), clock: clock)
        let generation = store.displays.first { $0.id == dell }?.connection.generation ?? 0
        store.update(displayID: dell, capabilityID: .brightness, proposed: .number(40))
        let before = setting(.brightness, on: dell, in: store)
        store.reviseSetting(.brightness, on: dell, generation: generation) { setting in
            setting.currentValue = .number(1)
            setting.freshness = .stale
            setting.pendingValue = nil
            setting.changedOnDisplayAt = clock.now
        }
        // Value, pending value and freshness untouched; only a presentation change gets through.
        #expect(setting(.brightness, on: dell, in: store) == before)
        store.reviseSetting(.brightness, on: dell, generation: generation) { $0.presentation = .hiddenByYou }
        #expect(setting(.brightness, on: dell, in: store)?.presentation == .hiddenByYou)
        #expect(setting(.brightness, on: dell, in: store)?.pendingValue == .number(40))
        // An old generation reaches nothing.
        store.reviseSetting(.volume, on: dell, generation: generation &+ 1) { $0.currentValue = .number(1) }
        #expect(setting(.volume, on: dell, in: store)?.currentValue == .number(35))
    }
}

// MARK: - Changes

@Test @MainActor func aReadingGlowCantTrustKeepsTheLastOne() async throws {
    try await ReadingFixture.withSuite { defaults in
        let adapter = ReadingFixture.realAdapter()
        let store = await ReadingFixture.store(defaults, adapter: adapter, clock: ReadingTestClock())
        let macBefore = try #require(setting(.brightness, on: mac, in: store))
        let dellBefore = try #require(setting(.brightness, on: dell, in: store))
        // macOS answering 0 for a lit screen, and a display answering past its own maximum.
        adapter.simulateChangeOnDisplay(.number(0), capability: .brightness, display: mac)
        adapter.simulateChangeOnDisplay(.number(250), capability: .brightness, display: dell)
        adapter.simulateChangeOnDisplay(.text("Loud"), capability: .volume, display: dell)

        let outcomes = await store.readAgain(mac) + store.readAgain(dell)
        for (capability, display, before) in [(CapabilityIdentifier.brightness, mac, macBefore), (.brightness, dell, dellBefore)] {
            let after = try #require(setting(capability, on: display, in: store))
            #expect(after.currentValue == before.currentValue && after.lastConfirmedValue == before.lastConfirmedValue)
            #expect(after.changedOnDisplayAt == nil)
        }
        #expect(setting(.volume, on: dell, in: store)?.currentValue != .text("Loud"))
        let distrusted = outcomes.filter { if case .skipped(let reason) = $0.result { reason.contains("kept the last reading") } else { false } }
        #expect(Set(distrusted.map(\.capability)) == [.brightness, .volume])
        #expect(distrusted.count == 3)
        #expect(adapter.totalWrites == 0)

        // A real 0 on the display's own control is believed; only macOS's is not.
        adapter.simulateChangeOnDisplay(.number(0), capability: .brightness, display: dell)
        _ = await store.readAgain(dell)
        #expect(setting(.brightness, on: dell, in: store)?.currentValue == .number(0))
    }
}

@Test @MainActor func aChangeOnTheDisplayIsShownAndMarkedForAMinuteAndNeverWritten() async throws {
    try await ReadingFixture.withSuite { defaults in
        let adapter = ReadingFixture.realAdapter()
        let clock = ReadingTestClock()
        let store = await ReadingFixture.store(defaults, adapter: adapter, clock: clock)
        adapter.simulateChangeOnDisplay(.number(30), capability: .brightness, display: dell)
        adapter.simulateChangeOnDisplay(.number(50), capability: .brightness, display: mac)

        clock.seconds = 5
        await store.readingTick(now: clock.now)
        let brightness = try #require(setting(.brightness, on: dell, in: store))
        #expect(brightness.currentValue == .number(30) && brightness.lastConfirmedValue == .number(30))
        #expect(brightness.freshness == .confirmed)
        #expect(ReadingFixture.seconds(brightness.changedOnDisplayAt) == 5)
        #expect(brightness.changeMarkTitle == "Changed on the display")
        #expect(setting(.brightness, on: mac, in: store)?.changeMarkTitle == "Changed outside Glow")
        #expect(setting(.volume, on: dell, in: store)?.changedOnDisplayAt == nil)
        #expect(store.reading.journal.contains { $0.capability == .brightness && $0.display == dell && $0.result == .changed(from: .number(68)) })

        // Reads never cause writes, and never count as set by Glow.
        #expect(adapter.totalWrites == 0)
        #expect(store.setByGlow.isEmpty)
        #expect(store.settings.value.lastSet == LastSetValues())

        clock.seconds = 64
        await store.readingTick(now: clock.now)
        #expect(setting(.brightness, on: dell, in: store)?.changedOnDisplayAt != nil)
        clock.seconds = 65
        await store.readingTick(now: clock.now)
        #expect(setting(.brightness, on: dell, in: store)?.changedOnDisplayAt == nil)
        #expect(setting(.brightness, on: dell, in: store)?.currentValue == .number(30))
    }
}

@Test func readingAgeIsSaidPlainly() {
    let now = ReadingFixture.date(100_000)
    func age(_ seconds: Double) -> String { ReadingAge.text(since: ReadingFixture.date(100_000 - seconds), now: now) }
    #expect(ReadingAge.text(since: nil, now: now) == "Not read yet")
    #expect(age(0) == "Read just now" && age(59) == "Read just now")
    #expect(age(60) == "Read 1 min ago" && age(180) == "Read 3 min ago")
    #expect(age(3_600) == "Read 1 hour ago" && age(7_200) == "Read 2 hours ago")
    #expect(age(90_000) == "Read more than a day ago")
}

@Test @MainActor func readAgainRereadsEverythingAndResetsTheAge() async {
    await ReadingFixture.withSuite { defaults in
        let adapter = demoAdapter()
        let clock = ReadingTestClock()
        let store = await ReadingFixture.store(defaults, adapter: adapter, clock: clock)
        #expect(store.readingAge(for: dell, now: clock.now) == "Read just now")
        clock.seconds = 180
        #expect(store.readingAge(for: dell, now: clock.now) == "Read 3 min ago")
        #expect(store.oldestReadingAge(now: clock.now) == "Read 3 min ago")
        let outcomes = await store.readAgain(dell)
        #expect(outcomes.contains { $0.capability == .input && $0.wasRead })
        #expect(adapter.readCount(.preset, on: dell) == 1)
        #expect(store.readingAge(for: dell, now: clock.now) == "Read just now")
        await store.readAll()
        #expect(adapter.readCount(.brightness, on: mac) == 1)
        #expect(store.oldestReadingAge(now: clock.now) == "Read just now")
        #expect(adapter.totalWrites == 0)
    }
}

// MARK: - Silent displays

@Test @MainActor func aDisplayThatStopsAnsweringIsLeftAloneLonger() async throws {
    try await ReadingFixture.withSuite { defaults in
        let adapter = demoAdapter()
        let clock = ReadingTestClock()
        let store = await ReadingFixture.store(defaults, adapter: adapter, clock: clock)
        adapter.silentDisplays = [dell]

        clock.seconds = 5
        await store.readingTick(now: clock.now)
        var dellClock = try #require(store.reading.clocks[dell])
        #expect(dellClock.silentPasses == 1 && ReadingFixture.seconds(dellClock.backoffUntil) == 35)
        let asked = adapter.readCount(.brightness, on: dell)

        for seconds in [10.0, 20, 30] {
            clock.seconds = seconds
            await store.readingTick(now: clock.now)
        }
        #expect(adapter.readCount(.brightness, on: dell) == asked)
        // The built-in display goes on being read; its brightness isn't DDC/CI.
        #expect(adapter.readCount(.brightness, on: mac) == 4)

        clock.seconds = 35
        await store.readingTick(now: clock.now)
        dellClock = try #require(store.reading.clocks[dell])
        #expect(dellClock.silentPasses == 2 && ReadingFixture.seconds(dellClock.backoffUntil) == 95)
        #expect(adapter.readCount(.brightness, on: dell) == asked + 1)

        // Read Again ignores the back-off; one answer ends it.
        adapter.silentDisplays = []
        clock.seconds = 40
        await store.readAgain(dell)
        dellClock = try #require(store.reading.clocks[dell])
        #expect(dellClock.silentPasses == 0 && dellClock.backoffUntil == nil)
        #expect(adapter.readCount(.brightness, on: lg) == 0)
    }
}

// MARK: - At launch

@Test func launchRestoreKeepsToReapplyAfterWakesRules() {
    var lastSet = LastSetValues()
    lastSet.record([.brightness: .number(40), .contrast: .number(78), .input: .text("HDMI 1"), .power: .text("Off"), .volume: .number(20)], on: dell)
    lastSet.record([.brightness: .number(10)], on: DemoData.unlistedIdentity)
    // Input and power are never even kept.
    #expect(Set(lastSet.values(for: dell).keys) == [.brightness, .contrast, .volume])

    let real = DemoData.displays(generation: 1).map { display -> DisplaySnapshot in
        var display = display
        display.isDemo = false
        return display
    }
    let scene = LaunchRestore.scene(from: lastSet, on: real)
    #expect(scene.displays.count == 1)
    let part = scene.displays.first
    #expect(part?.identity == dell)
    // Contrast already shows 78, so only what differs is put back.
    #expect(part?.settings.map(\.capability) == [.brightness, .volume])
    #expect(LaunchRestore.scene(from: lastSet, on: DemoData.displays(generation: 1)).displays.isEmpty)
    #expect(LaunchRestore.neverWritten == [.input, .power])
}

@Test @MainActor func putBackWhatGlowLastSetWritesOnlyTheAllowedSet() async {
    await ReadingFixture.withSuite { defaults in
        let adapter = ReadingFixture.realAdapter()
        let clock = ReadingTestClock()
        let store = await ReadingFixture.store(defaults, adapter: adapter, clock: clock) { settings in
            settings.value.reading.atLaunch = .restore
            settings.value.lastSet.record([.brightness: .number(40), .volume: .number(20), .input: .text("HDMI 1"), .contrast: .number(78)], on: dell)
        }
        #expect(adapter.writeCount(.brightness, on: dell) == 1)
        #expect(adapter.writeCount(.volume, on: dell) == 1)
        #expect(adapter.writeCount(.input, on: dell) == 0)
        #expect(adapter.writeCount(.power, on: dell) == 0)
        #expect(adapter.totalWrites == 2)
        #expect(store.reading.launchResult?.succeeded == 2)
        #expect(setting(.brightness, on: dell, in: store)?.currentValue == .number(40))
        // Now nothing differs, so there's nothing left to put back.
        #expect(await store.putBackLastSet() == nil)
    }
}

@Test @MainActor func launchRestoreNeverRunsInSafeModeForDemoDisplaysOrByDefault() async {
    let record: (GlowSettingsStore) -> Void = { settings in
        settings.value.lastSet.record([.brightness: .number(40)], on: dell)
    }
    await ReadingFixture.withSuite { defaults in
        let safe = ReadingFixture.realAdapter()
        _ = await ReadingFixture.store(defaults, adapter: safe, clock: ReadingTestClock(), safeMode: true) { settings in
            record(settings)
            settings.value.reading.atLaunch = .restore
        }
        #expect(safe.totalWrites == 0)
    }
    await ReadingFixture.withSuite { defaults in
        let byDefault = ReadingFixture.realAdapter()
        _ = await ReadingFixture.store(defaults, adapter: byDefault, clock: ReadingTestClock(), prepare: record)
        #expect(byDefault.totalWrites == 0)
    }
    await ReadingFixture.withSuite { defaults in
        let settings = GlowSettingsStore(defaults: defaults)
        record(settings)
        settings.value.reading.atLaunch = .restore
        let demo = GlowStore(settings: settings, demoDisplays: true)
        await demo.start()
        demo.reading.loop?.cancel()
        #expect(demo.reading.launchResult == nil)
        #expect(await demo.putBackLastSet() == nil)
    }
}

@Test @MainActor func whatGlowSetIsKeptForRealDisplaysOnly() async throws {
    try await ReadingFixture.withSuite { defaults in
        let store = await ReadingFixture.store(defaults, adapter: ReadingFixture.realAdapter(), clock: ReadingTestClock())
        store.update(displayID: dell, capabilityID: .brightness, proposed: .number(50))
        try await settle(store, .brightness, on: dell)
        #expect(store.settings.value.lastSet.values(for: dell)[.brightness] == .number(50))
        #expect(try ReadingFixture.saved(store.settings).lastSet.values(for: dell)[.brightness] == .number(50))

        let demo = GlowStore(settings: GlowSettingsStore(defaults: defaults), demoDisplays: false, adapter: demoAdapter())
        await demo.start()
        demo.reading.loop?.cancel()
        demo.update(displayID: dell, capabilityID: .volume, proposed: .number(10))
        try await settle(demo, .volume, on: dell)
        #expect(demo.setByGlow[dell]?[.volume] == .number(10))
        #expect(demo.settings.value.lastSet.values(for: dell)[.volume] == nil)
    }
}

// MARK: - Patience

@Test func patienceRaisesWaitsAndTriesButKeepsTheAddress() {
    #expect(ReadingPatience.normal.profile(from: .standard) == .standard)
    #expect(ReadingPatience.normal.profile(from: .slow) == .slow)
    let patient = ReadingPatience.patient.profile(from: .standard)
    #expect(patient.sourceAddress == 0x51 && patient.sendCount == 1)
    #expect(patient.readWait == .milliseconds(120) && patient.settleAfterSet == .milliseconds(100))
    #expect(patient.writeWait == .milliseconds(20) && patient.retryWait == .milliseconds(100))
    #expect(patient.retries == 6 && patient.retryWindow == .seconds(3))
    #expect(ReadingPatience.patient.profile(from: .alternate).sourceAddress == 0x50)
    let slow = ReadingPatience.patient.profile(from: .slow)
    #expect(slow.sendCount == 2 && slow.readWait == .milliseconds(200))
    #expect(patient.differencesFromStandard.contains("Tries 7 times"))
}

@Test @MainActor func patienceReachesTheHardwareAdapter() async {
    await ReadingFixture.withSuite { defaults in
        let store = await ReadingFixture.store(defaults, adapter: demoAdapter(), clock: ReadingTestClock()) { settings in
            settings.value.reading.patience = .patient
        }
        #expect(store.hardwareAdapter.patience == .patient)
        store.readingPatience = .normal
        #expect(store.hardwareAdapter.patience == .normal)
        #expect(store.settings.value.reading.patience == .normal)
    }
}

// MARK: - Codes the catalog doesn't know

/// Answers reads from a table and records each one.
private actor RawLink: DDCTransport {
    let report: String
    let answers: [UInt8: ProbeResult]
    private(set) var reads: [UInt8] = []
    private(set) var writes = 0
    init(report: String, answers: [UInt8: ProbeResult]) { self.report = report; self.answers = answers }
    func capabilityString() async throws -> String { report }
    func read(code: UInt8) async throws -> ProbeResult { reads.append(code); return answers[code] ?? .noResponse }
    func write(code: UInt8, value: UInt16) async throws { writes += 1 }
}

@Test func codesTheCatalogDoesntKnowAreReadOnceAndNeverWritable() async throws {
    let link = RawLink(report: "vcp(01 02 04 10 52 B0 C9 E2 F0)", answers: [
        0x10: .read(current: 50, maximum: 100), 0xE2: .read(current: 0x1D, maximum: 0), 0xF0: .unsupported
    ])
    let probe = await DDCProbe.run(link, transport: "DisplayPort")
    // Settings first, then each unknown code once; housekeeping and commands never.
    #expect(await link.reads == [0x10, 0xE2, 0xF0])
    #expect(probe.readings.map(\.code) == [0x10, 0xE2, 0xF0])
    #expect(await link.writes == 0)

    let vendor = try #require(probe.descriptors.first { $0.id == CapabilityCatalog.uncataloguedID(0xE2) })
    #expect(vendor.currentValue == .text("current 29, maximum 0"))
    #expect(vendor.evidence == .reportedUninterpreted && vendor.access == .unavailable)
    #expect(vendor.presentation == .connectionDetailsOnly && !vendor.isSafelyEditable && !vendor.canBeHidden)
    #expect(throws: ControlError.notWritable) { try vendor.validated(.text("current 0, maximum 0")) }
    await #expect(throws: ControlError.notWritable) {
        try await DDCControlChannel(link: link).write(.text("current 0, maximum 0"), descriptor: vendor)
    }
    #expect(await link.writes == 0)
    let refused = try #require(probe.descriptors.first { $0.id == CapabilityCatalog.uncataloguedID(0xF0) })
    #expect(refused.currentValue == nil && refused.reliability.lastFailure?.contains("doesn’t support") == true)
    let command = try #require(probe.descriptors.first { $0.rawCode == "VCP 0xB0" })
    #expect(command.currentValue == nil)

    #expect(CapabilityCatalog.readsOnce(0xE2) && CapabilityCatalog.readsOnce(0xF0))
    #expect(![0x01, 0x02, 0x04, 0x10, 0x52, 0xB0, 0xC9].contains(where: CapabilityCatalog.readsOnce))
    #expect(CapabilityCatalog.uncataloguedCode(of: "vcp-e2") == 0xE2)
    #expect(CapabilityCatalog.uncataloguedCode(of: .brightness) == nil)
}

@Test @MainActor func readAgainReadsUnknownCodesOnceMoreAndRereadsNeverDo() async throws {
    try await ReadingFixture.withSuite { defaults in
        let adapter = demoAdapter()
        let clock = ReadingTestClock()
        let store = await ReadingFixture.store(defaults, adapter: adapter, clock: clock)
        let e2 = CapabilityCatalog.uncataloguedID(0xE2)
        #expect(setting(e2, on: dell, in: store)?.currentValue == .text("current 29, maximum 0"))
        #expect(setting(CapabilityCatalog.uncataloguedID(0xF1), on: dell, in: store)?.currentValue == nil)

        clock.seconds = 60
        await store.readingTick(now: clock.now)
        #expect(adapter.readCount(e2, on: dell) == 0)

        adapter.reportedReadings[dell]?[0xE2] = .read(current: 0x02, maximum: 0)
        await store.readAgain(dell)
        #expect(adapter.readCount(e2, on: dell) == 1)
        let vendor = try #require(setting(e2, on: dell, in: store))
        #expect(vendor.currentValue == .text("current 2, maximum 0"))
        #expect(!vendor.isSafelyEditable && vendor.access == .unavailable)
        // Housekeeping (0xAC…) and commands (0x04…) are never asked for.
        #expect(adapter.readCount(CapabilityCatalog.uncataloguedID(0xAC), on: dell) == 0)
        #expect(adapter.totalWrites == 0)
    }
}

// MARK: - Hide

@Test @MainActor func hideAndShowPersistPerDisplayAndLeaveTheOSDAndScenes() async throws {
    try await ReadingFixture.withSuite { defaults in
        let clock = ReadingTestClock()
        let store = await ReadingFixture.store(defaults, adapter: ReadingFixture.realAdapter(), clock: clock)
        store.hide(.sharpness, on: dell)
        let hidden = try #require(setting(.sharpness, on: dell, in: store))
        #expect(hidden.presentation == .hiddenByYou && !hidden.isSafelyEditable && !hidden.canBeInScene)
        let display = try #require(store.displays.first { $0.id == dell })
        #expect(!display.osdSections.flatMap(\.capabilities).contains { $0.id == .sharpness })
        // Still listed for Connection details.
        #expect(display.capabilities.contains { $0.id == .sharpness })
        // Scenes: never captured, and skipped when an older scene asks for it.
        let captured = GlowScene.capturing(store.displays, name: "Now")
        #expect(captured.part(for: dell)?.setting(.sharpness) == nil)
        #expect(captured.part(for: dell)?.setting(.contrast) != nil)
        let old = GlowScene(name: "Old", symbol: SceneSymbol.fallback, displays: [
            SceneDisplay(identity: dell, name: "Dell", settings: [SceneSetting(.sharpness, .number(10), describedBy: hidden)])
        ])
        let plan = old.plan(on: store.displays)
        #expect(plan.writes.isEmpty && plan.skipped == 1)
        #expect(store.settings.value.corrections.hidden(on: dell) == [.sharpness])
        #expect(store.hiddenSettings(on: dell).map(\.label) == ["Sharpness"])

        // The next launch keeps it hidden on that display.
        _ = try ReadingFixture.saved(store.settings)
        let next = await ReadingFixture.store(defaults, adapter: ReadingFixture.realAdapter(), clock: clock)
        #expect(setting(.sharpness, on: dell, in: next)?.presentation == .hiddenByYou)
        #expect(next.settings.value.corrections.hidden(on: lg).isEmpty)

        next.show(.sharpness, on: dell)
        #expect(setting(.sharpness, on: dell, in: next)?.presentation == .osd)
        #expect(setting(.sharpness, on: dell, in: next)?.isSafelyEditable == true)
        #expect(next.settings.value.corrections.hidden(on: dell).isEmpty)
        #expect(next.hiddenSettings(on: dell).isEmpty)
    }
}

@Test @MainActor func onlySettingsARealDisplayReportsCanBeHidden() async {
    await ReadingFixture.withSuite { defaults in
        let clock = ReadingTestClock()
        let real = await ReadingFixture.store(defaults, adapter: ReadingFixture.realAdapter(), clock: clock)
        // The built-in display's brightness is macOS's, not reported by the display.
        real.hide(.brightness, on: mac)
        #expect(setting(.brightness, on: mac, in: real)?.presentation == .osd)
        real.hide(.resolution, on: dell)
        #expect(setting(.resolution, on: dell, in: real)?.presentation == .osd)
        #expect(real.settings.value.corrections == DisplayCorrections())

        let demo = await ReadingFixture.store(defaults, adapter: demoAdapter(), clock: clock)
        demo.hide(.sharpness, on: dell)
        #expect(setting(.sharpness, on: dell, in: demo)?.presentation == .osd)
        #expect(demo.settings.value.corrections == DisplayCorrections())
    }
}

@Test @MainActor func hiddenSettingsWaitForReadAgain() async {
    await ReadingFixture.withSuite { defaults in
        let adapter = ReadingFixture.realAdapter()
        let clock = ReadingTestClock()
        let store = await ReadingFixture.store(defaults, adapter: adapter, clock: clock)
        store.hide(.volume, on: dell)
        clock.seconds = 60
        await store.readingTick(now: clock.now)
        #expect(adapter.readCount(.volume, on: dell) == 0)
        #expect(adapter.readCount(.brightness, on: dell) == 1)
        await store.readAgain(dell)
        #expect(adapter.readCount(.volume, on: dell) == 1)
    }
}

@Test func correctionsAreKeptPerDisplayIdentity() throws {
    var corrections = DisplayCorrections()
    corrections.hide(.sharpness, on: dell)
    corrections.hide(.redGain, on: dell)
    corrections.hide(.volume, on: DemoData.unlistedIdentity)
    #expect(corrections.hidden(on: dell) == [.sharpness, .redGain])
    #expect(corrections.hidden(on: lg).isEmpty)
    corrections.show(.sharpness, on: dell)
    #expect(corrections.hidden(on: dell) == [.redGain])
    corrections.show(.redGain, on: dell)
    #expect(corrections.hidden.keys.sorted { $0.id < $1.id } == [DemoData.unlistedIdentity])
}

// MARK: - Saved settings

@Test func readingSettingsDecodeWhenMissingOrUnknown() throws {
    let empty = try SettingsFixture.decode("{}")
    #expect(empty.reading == ReadingSettings() && empty.lastSet == LastSetValues() && empty.corrections == DisplayCorrections())
    #expect(empty.reading.freshness == .whileOpen && empty.reading.atLaunch == .read && empty.reading.patience == .normal)

    // A newer Glow's values fall back one field at a time.
    let newer = try SettingsFixture.decode(#"{"reading": {"version": 9, "freshness": "sometimes", "atLaunch": "restore", "patience": "glacial"}, "fineAdjustment": false}"#)
    #expect(newer.reading.freshness == .whileOpen && newer.reading.atLaunch == .restore && newer.reading.patience == .normal)
    #expect(newer.fineAdjustment == false)

    // Unreadable blocks fall back whole, without resetting anything else.
    let broken = try SettingsFixture.decode(#"{"reading": 5, "lastSet": "x", "corrections": [1], "reapplyAfterWake": true}"#)
    #expect(broken.reading == ReadingSettings() && broken.lastSet == LastSetValues() && broken.corrections == DisplayCorrections())
    #expect(broken.reapplyAfterWake)
}

@Test func settingsReopenOnTheReadingPane() throws {
    #expect(try SettingsFixture.decode(#"{"lastPane": "reading"}"#).lastPane == .reading)
    #expect(GlowSettingsPane.reading.title == "Reading")
    // Wake moved here from General; its setting and its saved key are unchanged.
    #expect(try SettingsFixture.decode(#"{"lastPane": "general", "reapplyAfterWake": true}"#).reapplyAfterWake)
}

@Test func lastSetAndCorrectionsKeepWhatTheyCanRead() throws {
    let identity = #"{"vendorID": 4268, "productID": 41200, "serialNumber": 783245}"#
    let lastSet = try ReadingFixture.decode(LastSetValues.self, #"""
    {"version": 3, "displays": [
      {"identity": \#(identity), "settings": [
        {"capability": "brightness", "value": {"number": {"_0": 40}}},
        {"capability": "contrast", "value": "bogus"},
        {"capability": "input-source", "value": {"text": {"_0": "HDMI 1"}}}
      ]},
      {"identity": "not a display", "settings": []}
    ]}
    """#)
    #expect(lastSet.values(for: dell) == [.brightness: .number(40)])

    let corrections = try ReadingFixture.decode(DisplayCorrections.self, #"""
    {"version": 2, "displays": [{"identity": \#(identity), "hidden": ["sharpness"]}, {"identity": \#(identity)}]}
    """#)
    #expect(corrections.hidden(on: dell) == [.sharpness])
}

@Test func readingSettingsRoundTripAtTheCurrentVersion() throws {
    var settings = GlowSettings()
    settings.reading.freshness = .always
    settings.reading.atLaunch = .restore
    settings.reading.patience = .patient
    settings.lastSet.record([.brightness: .number(40), .preset: .text("sRGB")], on: dell)
    settings.corrections.hide(.sharpness, on: dell)
    #expect(try SettingsFixture.roundTrip(settings) == settings)
    #expect(try ReadingFixture.json(settings.reading).contains(#""version":1"#))
    #expect(try ReadingFixture.json(settings.lastSet).contains(#""version":1"#))
    #expect(try ReadingFixture.json(settings.corrections).contains(#""version":1"#))
}

@Test func readAgainSaysWhatItFoundPlainly() {
    let read = ReadingOutcome(display: dell, capability: .brightness, label: "Brightness", result: .unchanged, value: .number(40), milliseconds: 40)
    let changed = ReadingOutcome(display: dell, capability: .volume, label: "Volume", result: .changed(from: .number(20)), value: .number(30), milliseconds: 40)
    let failed = ReadingOutcome(display: dell, capability: .contrast, label: "Contrast", result: .failed("The display did not respond in time."), value: nil, milliseconds: 900)
    let skipped = ReadingOutcome(display: dell, capability: .contrast, label: "Contrast", result: .skipped("A change is on its way"), value: nil, milliseconds: 0)
    #expect(ReadAgainSection.summary(of: []) == nil)
    #expect(ReadAgainSection.summary(of: [read, failed]) == "Nothing had changed.")
    #expect(ReadAgainSection.summary(of: [read, changed]) == "1 setting had changed on the display.")
    #expect(ReadAgainSection.summary(of: [changed, changed]) == "2 settings had changed on the display.")
    #expect(ReadAgainSection.summary(of: [failed, failed])?.hasPrefix("The display didn’t answer") == true)
    #expect(ReadAgainSection.summary(of: [skipped]) == nil)
}
