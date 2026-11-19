import Testing
@testable import GlowApp

/// The hold's tick, run by hand.
@MainActor private final class ManualTicker: KeyHoldTicker {
    private(set) var tick: (@MainActor () -> Void)?
    private(set) var interval: Double?
    var isRunning: Bool { tick != nil }

    func start(every interval: Double, _ tick: @escaping @MainActor () -> Void) {
        self.interval = interval
        self.tick = tick
    }

    func stop() { tick = nil }
}

/// A hold on a pretend display, with a clock that only moves when the test says.
@MainActor private final class HoldRig {
    var now = 0.0
    var level = 50.0
    var presses: [BrightnessKeyPress] = []
    var ticks = 0
    /// What the next ramp tick says, nil to go on.
    var stopWith: KeyHoldStop?
    var takesPresses = true
    let ticker = ManualTicker()
    private(set) lazy var hold = BrightnessKeyHold(
        timing: BrightnessKeyHold.Timing(repeatDelay: 0.5, repeatInterval: 0.083),
        ticker: ticker,
        clock: { [unowned self] in now },
        press: { [unowned self] press in
            guard takesPresses else { return false }
            presses.append(press)
            level += press.direction == .up ? 6 : -6
            return true
        },
        tick: { [unowned self] direction in
            if let stopWith { return stopWith }
            ticks += 1
            level += direction == .up ? 1 : -1
            return nil
        }
    )

    /// Moves the clock on to `time`, one tick at a time, with the keyboard's repeats for
    /// `repeating` every `every` seconds once its delay has passed.
    func run(to time: Double, repeating direction: BrightnessKeyPress.Direction? = nil, every: Double = 0.033, from start: Double = 0.5) {
        var nextRepeat = start
        while now + 0.0201 <= time {
            now += 0.02
            if let direction, now >= nextRepeat {
                #expect(hold.handle(.down(BrightnessKeyPress(direction: direction, quarterStep: false), isRepeat: true)))
                nextRepeat += every
            }
            ticker.tick?()
        }
    }

    func down(_ direction: BrightnessKeyPress.Direction) -> Bool {
        hold.handle(.down(BrightnessKeyPress(direction: direction, quarterStep: false), isRepeat: false))
    }
}

@MainActor @Test func aTapIsOneStepOnKeyDownAndNoRamp() {
    let rig = HoldRig()
    #expect(rig.down(.up))
    #expect(rig.level == 56)
    rig.run(to: 0.1)
    #expect(rig.hold.handle(.up(.up)))
    #expect(rig.presses.count == 1)
    #expect(rig.ticks == 0)
    #expect(rig.hold.lastStop == .released)
    #expect(!rig.ticker.isRunning)
}

@MainActor @Test func aHeldKeyRampsOnePercentPerTickAfterTheDelay() {
    let rig = HoldRig()
    _ = rig.down(.up)
    rig.run(to: 0.49, repeating: .up)
    #expect(rig.ticks == 0)
    rig.run(to: 1.5, repeating: .up)
    #expect(rig.hold.isRamping)
    // A tick every 20 ms from half a second: 1% each, and the repeats add nothing.
    #expect((50...52).contains(rig.ticks))
    #expect(rig.level == 56 + Double(rig.ticks))
    #expect(rig.presses.count == 1)
    #expect(rig.ticker.interval == 0.02)
    #expect(rig.hold.handle(.up(.up)))
    #expect(rig.hold.lastStop == .released)
    #expect(!rig.hold.isRamping && !rig.ticker.isRunning)
}

@MainActor @Test func theRampKeepsItsOwnPaceWhateverTheKeyboardsRepeatRate() {
    let fast = HoldRig()
    _ = fast.down(.down)
    fast.run(to: 1.5, repeating: .down, every: 0.03)
    let slow = HoldRig()
    _ = slow.down(.down)
    slow.run(to: 1.5, repeating: .down, every: 0.2)
    #expect(fast.ticks == slow.ticks)
    #expect(fast.level == slow.level)
}

@MainActor @Test func theOtherKeyEndsTheHoldAndStartsItsOwn() {
    let rig = HoldRig()
    _ = rig.down(.up)
    rig.run(to: 0.8, repeating: .up)
    #expect(rig.down(.down))
    #expect(rig.hold.lastStop == .otherKey)
    #expect(rig.presses.map(\.direction) == [.up, .down])
    // The first key's key-up is still Glow's to swallow.
    #expect(rig.hold.handle(.up(.up)))
    #expect(rig.ticker.isRunning)
}

@MainActor @Test func theTapGoingOffStopsTheRamp() {
    let rig = HoldRig()
    _ = rig.down(.up)
    rig.run(to: 0.8, repeating: .up)
    #expect(!rig.hold.handle(.lost))
    #expect(rig.hold.lastStop == .tapOff)
    #expect(!rig.ticker.isRunning)
    let ticks = rig.ticks
    // Repeats after that are swallowed but never restart it.
    rig.run(to: 1.2, repeating: .up, from: 0.82)
    #expect(rig.ticks == ticks)
}

@MainActor @Test func theRangeEndAPauseAndMacOSTakingOverStopTheRamp() {
    for stop in [KeyHoldStop.rangeEnd, .paused, .notGlows] {
        let rig = HoldRig()
        _ = rig.down(.up)
        rig.run(to: 0.7, repeating: .up)
        rig.stopWith = stop
        rig.run(to: 0.8, repeating: .up, from: 0.72)
        #expect(rig.hold.lastStop == stop)
        #expect(!rig.ticker.isRunning)
        rig.stopWith = nil
        let level = rig.level
        rig.run(to: 1.2, repeating: .up, from: 0.82)
        #expect(rig.level == level)
        #expect(rig.hold.handle(.up(.up)))
    }
}

@MainActor @Test func withoutRepeatsAHoldGetsItsStepAndAShortRamp() {
    let rig = HoldRig()
    _ = rig.down(.up)
    rig.run(to: 2)
    // No repeat by 0.5 s + the window: the hold is taken as over, about a dozen ticks in.
    #expect(rig.hold.lastStop == .silent)
    #expect((10...13).contains(rig.ticks))
    #expect(!rig.ticker.isRunning)
    // A late repeat picks the ramp up again.
    #expect(rig.hold.handle(.down(BrightnessKeyPress(direction: .up, quarterStep: false), isRepeat: true)))
    #expect(rig.ticker.isRunning)
    let ticks = rig.ticks
    rig.ticker.tick?()
    #expect(rig.ticks == ticks + 1)
}

@MainActor @Test func aPressMacOSKeepsLeavesItsRepeatsAndKeyUpToMacOS() {
    let rig = HoldRig()
    rig.takesPresses = false
    #expect(!rig.down(.up))
    #expect(!rig.hold.handle(.down(BrightnessKeyPress(direction: .up, quarterStep: false), isRepeat: true)))
    #expect(!rig.hold.handle(.up(.up)))
    #expect(!rig.ticker.isRunning)
}

@Test func holdTimingFollowsTheKeyboardWithinLimits() {
    let usual = BrightnessKeyHold.Timing(repeatDelay: 0.5, repeatInterval: 0.083)
    #expect(usual.rampDelay == 0.5)
    #expect(abs(usual.repeatWindow - 0.233) < 0.0001)
    #expect(BrightnessKeyHold.Timing(repeatDelay: 0.1, repeatInterval: 0.03).rampDelay == 0.25)
    #expect(BrightnessKeyHold.Timing(repeatDelay: 2, repeatInterval: 2).rampDelay == 0.5)
    #expect(abs(BrightnessKeyHold.Timing(repeatDelay: 2, repeatInterval: 2).repeatWindow - 0.4) < 0.0001)
}

// MARK: The store's ramp

@MainActor private final class StoreAdapter: DisplayAdapter {
    let name = "Ramp test"
    private var written: [PersistentDisplayIdentity: CapabilityValue] = [:]
    func discover(generation: UInt64) async -> [DisplaySnapshot] { DemoData.displays(generation: generation) }
    func write(_ value: CapabilityValue, capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws { written[display] = value }
    func read(capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws -> CapabilityValue { written[display] ?? .number(0) }
}

@MainActor private func brightness(_ store: GlowStore, _ id: PersistentDisplayIdentity) -> Double? {
    store.displays.first(where: { $0.id == id })?.brightnessSetting?.matchNumber
}

@MainActor @Test func theStoresTickMovesEveryTargetOnePercent() async {
    await MatchFixture.withStore(adapter: StoreAdapter()) { store in
        await store.refresh()
        store.controlTarget = .all
        let before = store.displays.map { brightness(store, $0.id) ?? 0 }
        #expect(store.rampBrightness(.up, pointerDisplay: nil) == nil)
        #expect(store.displays.map { brightness(store, $0.id) ?? 0 } == before.map { $0 + 1 })
    }
}

@MainActor @Test func theStoresTickSaysWhyTheRampMustStop() async {
    await MatchFixture.withStore(adapter: StoreAdapter()) { store in
        await store.refresh()
        let dell = DemoData.dellIdentity
        store.controlTarget = .focused
        store.focusedDisplayID = dell
        store.update(displayID: dell, capabilityID: .brightness, proposed: .number(100))
        #expect(store.rampBrightness(.up, pointerDisplay: nil) == .rangeEnd)
        #expect(store.rampBrightness(.down, pointerDisplay: nil) == nil)
        #expect(brightness(store, dell) == 99)
        store.controlTarget = .macOnly
        #expect(store.rampBrightness(.down, pointerDisplay: nil) == .notGlows)
        store.controlTarget = .focused
        store.handle(.sleep)
        #expect(store.rampBrightness(.down, pointerDisplay: nil) == .paused)
        #expect(brightness(store, dell) == 99)
    }
}

@MainActor @Test func aKeyPressUsesTheChosenStep() async {
    await MatchFixture.withStore(adapter: StoreAdapter()) { store in
        await store.refresh()
        let dell = DemoData.dellIdentity
        store.controlTarget = .focused
        store.focusedDisplayID = dell
        store.update(displayID: dell, capabilityID: .brightness, proposed: .number(47))
        store.keyStep = .percent5
        #expect(store.handleBrightnessKey(BrightnessKeyPress(direction: .up, quarterStep: false), pointerDisplay: nil))
        #expect(brightness(store, dell) == 50)
        // Option and Shift: a quarter of 5%, rounded to the display's whole percents.
        #expect(store.handleBrightnessKey(BrightnessKeyPress(direction: .up, quarterStep: true), pointerDisplay: nil))
        #expect(brightness(store, dell) == 51)
    }
}
