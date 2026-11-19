import Testing
@testable import GlowApp

// MARK: The write coalescer

/// Holds every caller until the test opens it.
@MainActor private final class Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async { await withCheckedContinuation { waiters.append($0) } }

    func open() {
        let waiting = waiters
        waiters = []
        waiting.forEach { $0.resume() }
    }
}

/// A coalescer whose sends and read-backs each wait at a gate, logging what reached the
/// pretend display.
@MainActor private final class CoalescerRig {
    let coalescer = WriteCoalescer<String, Int>()
    let sends = Gate()
    let confirms = Gate()
    var log: [String] = []
    var finished: [Int?] = []
    var refuse: Set<Int> = []

    func propose(_ value: Int, for key: String = "dell.brightness") {
        coalescer.propose(.init(
            send: { [unowned self] in
                log.append("send \(value)")
                await sends.wait()
                if refuse.contains(value) { throw ControlError.timedOut }
            },
            confirm: { [unowned self] in
                log.append("confirm \(value)")
                await confirms.wait()
                return value
            },
            finish: { [unowned self] in finished.append(try? $0.get()) }
        ), for: key)
    }

    /// Lets every task that can run, run.
    func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }
}

@MainActor @Test func theFirstValueIsSentAtOnceAndOnlyTheLastIsConfirmed() async {
    let rig = CoalescerRig()
    rig.propose(1)
    await rig.settle()
    #expect(rig.log == ["send 1"])
    #expect(rig.coalescer.isRunning("dell.brightness"))
    // While 1 is in flight, 2 and 3 are overtaken by 4 and never sent.
    rig.propose(2)
    rig.propose(3)
    rig.propose(4)
    await rig.settle()
    #expect(rig.log == ["send 1"])
    rig.sends.open()
    await rig.settle()
    // 1 had a newer value behind it, so it skipped its read-back.
    #expect(rig.log == ["send 1", "send 4"])
    rig.sends.open()
    await rig.settle()
    #expect(rig.log == ["send 1", "send 4", "confirm 4"])
    #expect(rig.finished.isEmpty)
    rig.confirms.open()
    await rig.settle()
    #expect(rig.finished == [4])
    #expect(!rig.coalescer.isRunning("dell.brightness"))
}

@MainActor @Test func aValueDuringTheReadBackIsStillSentAndReportedInstead() async {
    let rig = CoalescerRig()
    rig.propose(1)
    await rig.settle()
    rig.sends.open()
    await rig.settle()
    #expect(rig.log == ["send 1", "confirm 1"])
    rig.propose(2)
    rig.confirms.open()
    await rig.settle()
    #expect(rig.log == ["send 1", "confirm 1", "send 2"])
    #expect(rig.finished.isEmpty)
    rig.sends.open()
    await rig.settle()
    rig.confirms.open()
    await rig.settle()
    #expect(rig.log == ["send 1", "confirm 1", "send 2", "confirm 2"])
    #expect(rig.finished == [2])
}

@MainActor @Test func valuesProposedTogetherSendOnlyTheLast() async {
    let rig = CoalescerRig()
    rig.propose(1)
    rig.propose(2)
    await rig.settle()
    #expect(rig.log == ["send 2"])
}

@MainActor @Test func eachSettingHasItsOwnWriteInFlight() async {
    let rig = CoalescerRig()
    rig.propose(1, for: "dell.brightness")
    rig.propose(2, for: "lg.brightness")
    await rig.settle()
    #expect(rig.log == ["send 1", "send 2"])
}

@MainActor @Test func droppingARunForgetsWhatWaitsAndNeverReports() async {
    let rig = CoalescerRig()
    rig.propose(1)
    await rig.settle()
    rig.propose(2)
    rig.coalescer.drop("dell.brightness")
    #expect(!rig.coalescer.isRunning("dell.brightness"))
    // What comes next starts a run of its own at once.
    rig.propose(3)
    await rig.settle()
    #expect(rig.log == ["send 1", "send 3"])
    rig.sends.open()
    await rig.settle()
    rig.confirms.open()
    await rig.settle()
    #expect(rig.log == ["send 1", "send 3", "confirm 3"])
    #expect(rig.finished == [3])
}

@MainActor @Test func aRefusedWriteEndsTheRunWithItsFailure() async {
    let rig = CoalescerRig()
    rig.refuse = [1]
    rig.propose(1)
    await rig.settle()
    rig.propose(2)
    rig.sends.open()
    await rig.settle()
    #expect(rig.log == ["send 1"])
    #expect(rig.finished == [nil])
    #expect(!rig.coalescer.isRunning("dell.brightness"))
}

// MARK: The new settings

@Test func theStepAndLookFallBackWhenMissingOrUnknown() throws {
    let missing = try SettingsFixture.decode(#"{"fineAdjustment": false}"#)
    #expect(missing.keyStep == .likeMacOS)
    #expect(missing.levelStyle == .slider)
    let unknown = try SettingsFixture.decode(#"{"keyStep": "percent7", "levelStyle": "dots", "showOverlayOnChange": false}"#)
    #expect(unknown.keyStep == .likeMacOS)
    #expect(unknown.levelStyle == .slider)
    #expect(unknown.showOverlayOnChange == false)
    var chosen = GlowSettings()
    chosen.keyStep = .percent5
    chosen.levelStyle = .boxes
    #expect(try SettingsFixture.roundTrip(chosen) == chosen)
}

@MainActor @Test func theStoresStepAndLookReachSavedSettings() {
    SettingsFixture.withSuite { defaults in
        let settings = GlowSettingsStore(defaults: defaults)
        let store = GlowStore(settings: settings)
        store.keyStep = .percent10
        store.levelStyle = .boxes
        #expect(settings.value.keyStep == .percent10)
        #expect(settings.value.levelStyle == .boxes)
    }
}

// MARK: The overlay

@MainActor @Test func theOverlayChangesOneModelInPlace() {
    let overlays = OverlayCoordinator(presentsPanels: { false })
    let dell = DemoData.displays(generation: 1)[1]
    let brightness = dell.brightnessSetting!
    overlays.show(display: dell, capability: brightness, value: .number(47), failed: false, style: .boxes)
    let model = overlays.model(for: dell.connection.displayID)
    #expect(model?.level == 0.47)
    overlays.show(display: dell, capability: brightness, value: .number(48), failed: false, style: .boxes)
    #expect(overlays.model(for: dell.connection.displayID) === model)
    #expect(model?.level == 0.48)
    #expect(model?.valueText == "48%")
    #expect(model?.symbol == .brightness)
    #expect(model?.showsBoxes == true)
    #expect(model?.displayName == dell.name)
    // Nothing goes on screen without a running app.
    #expect(overlays.panelCount == 0)
    overlays.show(display: dell, capability: brightness, value: .number(48), failed: true, style: .slider)
    #expect(overlays.model(for: dell.connection.displayID) === model)
    #expect(model?.failed == true)
    #expect(model?.method == "Couldn’t update this display")
    #expect(model?.style == .slider)
}

@MainActor @Test func theOverlayKnowsSoftwareDimmingAndVolume() {
    let overlays = OverlayCoordinator(presentsPanels: { false })
    let displays = DemoData.displays(generation: 1)
    let lg = displays[2]
    overlays.show(display: lg, capability: lg.brightnessSetting!, value: .number(40), failed: false, style: .boxes)
    #expect(overlays.model(for: lg.connection.displayID)?.isSoftware == true)
    let volume = DemoData.descriptor(.volume, "Speaker volume", .essentials, .range(minimum: 0, maximum: 100, step: 1), .number(35), .hardware, unit: "%")
    overlays.show(display: displays[1], capability: volume, value: .number(35), failed: false, style: .boxes)
    #expect(overlays.model(for: displays[1].connection.displayID)?.symbol == .volume)
    #expect(overlays.model(for: displays[1].connection.displayID)?.isSoftware == false)
}

@MainActor @Test func theOverlayLevelIsWhereTheValueSitsInItsRange() {
    let range = CapabilityKind.range(minimum: 10, maximum: 100, step: 1)
    #expect(OverlayModel.level(of: .number(10), in: range) == 0)
    #expect(OverlayModel.level(of: .number(55), in: range) == 0.5)
    #expect(OverlayModel.level(of: .number(140), in: range) == 1)
    #expect(OverlayModel.level(of: .boolean(true), in: range) == nil)
}

@Test func boxesFillAsTheMacsOverlayDoes() {
    let fills = OverlayBoxes.fills(level: 0.47)
    #expect(fills.count == 16)
    #expect(fills.prefix(7).allSatisfy { $0 == 1 })
    #expect(abs(fills[7] - 0.52) < 0.0001)
    #expect(fills.dropFirst(8).allSatisfy { $0 == 0 })
    #expect(OverlayBoxes.fills(level: 0).allSatisfy { $0 == 0 })
    #expect(OverlayBoxes.fills(level: 1).allSatisfy { $0 == 1 })
    #expect(OverlayBoxes.fills(level: 1.3) == OverlayBoxes.fills(level: 1))
}
