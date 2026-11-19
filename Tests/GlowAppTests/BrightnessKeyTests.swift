import Testing
@testable import GlowApp

/// MacBook Pro (built-in, display 1), Dell U2723QE (2), LG UltraFine 27 (3).
private let desk = DemoData.displays(generation: 1)
private let mac = desk[0].id
private let dell = desk[1].id
private let lg = desk[2].id

private func route(_ target: ControlTarget, focused: PersistentDisplayIdentity? = nil, pointer: UInt32? = nil,
                   demo: Bool = false, safe: Bool = false, displays: [DisplaySnapshot] = desk) -> KeyRoute {
    BrightnessKeyRouting.route(target: target, displays: displays, focused: focused, pointerDisplay: pointer, demoMode: demo, safeMode: safe)
}

@Test func macOnlyLeavesTheKeysToMacOS() {
    #expect(route(.macOnly) == .macOS)
}

@Test func demoSafeModeAndAnEmptyDeskLeaveTheKeysToMacOS() {
    #expect(route(.all, demo: true) == .macOS)
    #expect(route(.all, safe: true) == .macOS)
    #expect(route(.all, displays: []) == .macOS)
}

@Test func allTakesEveryDisplayTheBuiltInIncluded() {
    // Glow changes the built-in itself, so macOS must not get the press too.
    #expect(route(.all) == .glow([mac, dell, lg]))
}

@Test func underCursorTakesOnlyThePointedDisplay() {
    #expect(route(.underCursor, pointer: 3) == .glow([lg]))
    #expect(route(.underCursor, pointer: 1) == .glow([mac]))
    // The press is still Glow's: handing it to macOS would change the built-in instead.
    #expect(route(.underCursor, pointer: 99) == .glow([]))
}

@Test func focusedUsesTheChoiceOrTheFirstExternalDisplay() {
    #expect(route(.focused, focused: lg) == .glow([lg]))
    #expect(route(.focused) == .glow([dell]))
    let away = PersistentDisplayIdentity(vendorID: 1, productID: 2, serialNumber: 3)
    #expect(route(.focused, focused: away) == .glow([dell]))
}

private let up = BrightnessKeyPress(direction: .up, quarterStep: false)
private let down = BrightnessKeyPress(direction: .down, quarterStep: false)
private let quarterUp = BrightnessKeyPress(direction: .up, quarterStep: true)

@Test func stepsAreSixteenthsAndQuarterStepsSixtyFourths() {
    #expect(BrightnessKeyRouting.next(from: 50, range: 0...100, press: up) == 56.25)
    #expect(BrightnessKeyRouting.next(from: 50, range: 0...100, press: down) == 43.75)
    #expect(BrightnessKeyRouting.next(from: 50, range: 0...100, press: quarterUp) == 51.5625)
    // Software dimming's range starts at its floor.
    #expect(BrightnessKeyRouting.next(from: 10, range: 10...100, press: up) == 15.625)
}

@Test func stepsStopAtTheEnds() {
    #expect(BrightnessKeyRouting.next(from: 100, range: 0...100, press: up) == 100)
    #expect(BrightnessKeyRouting.next(from: 0, range: 0...100, press: down) == 0)
    #expect(BrightnessKeyRouting.next(from: 98, range: 0...100, press: up) == 100)
}

@Test func aValueBetweenStepsMovesToTheNextGridLine() {
    #expect(BrightnessKeyRouting.next(from: 53, range: 0...100, press: up) == 56.25)
    #expect(BrightnessKeyRouting.next(from: 53, range: 0...100, press: down) == 50)
}

@Test func roundingToWholePercentsNeverHoldsAValueInPlace() {
    for press in [up, quarterUp] {
        var value = 0.0
        var presses = 0
        while value < 100, presses < 100 {
            let next = BrightnessKeyRouting.next(from: value, range: 0...100, press: press).rounded()
            #expect(next > value)
            value = next
            presses += 1
        }
        #expect(presses == (press.quarterStep ? 64 : 16))
    }
    var value = 100.0
    for _ in 0..<16 {
        let next = BrightnessKeyRouting.next(from: value, range: 0...100, press: down).rounded()
        #expect(next < value)
        value = next
    }
    #expect(value == 0)
}

@Test func onlyBrightnessKeysAreReadFromSystemEvents() {
    let upDown = BrightnessKeyTap.brightnessKey(data1: 2 << 16 | 0xA << 8)
    #expect(upDown?.code == 2 && upDown?.isDown == true)
    let downUp = BrightnessKeyTap.brightnessKey(data1: 3 << 16 | 0xB << 8)
    #expect(downUp?.code == 3 && downUp?.isDown == false)
    // Volume up (0) and play (16) belong to macOS.
    #expect(BrightnessKeyTap.brightnessKey(data1: 0 << 16 | 0xA << 8) == nil)
    #expect(BrightnessKeyTap.brightnessKey(data1: 16 << 16 | 0xA << 8) == nil)
}

@Test func theKeyboardsRepeatsAreToldFromFreshPresses() {
    #expect(BrightnessKeyTap.brightnessKey(data1: 2 << 16 | 0xA << 8)?.isRepeat == false)
    let held = BrightnessKeyTap.brightnessKey(data1: 2 << 16 | 0xA << 8 | 0x1)
    #expect(held?.code == 2 && held?.isDown == true && held?.isRepeat == true)
}

// MARK: Step size

private func press(_ direction: BrightnessKeyPress.Direction, _ step: KeyStep, fine: Bool = false) -> BrightnessKeyPress {
    BrightnessKeyPress(direction: direction, quarterStep: fine, step: step)
}

@Test func aTapMovesOneStepOfEachSize() {
    let expected: [(KeyStep, Double, Double)] = [(.likeMacOS, 56, 44), (.percent1, 51, 49), (.percent2, 52, 48), (.percent5, 55, 45), (.percent10, 60, 40)]
    for (step, upTo, downTo) in expected {
        #expect(BrightnessKeyRouting.next(from: 50, range: 0...100, press: press(.up, step)).rounded() == upTo)
        #expect(BrightnessKeyRouting.next(from: 50, range: 0...100, press: press(.down, step)).rounded() == downTo)
    }
}

@Test func everyStepSizeMovesToTheNextGridLine() {
    #expect(BrightnessKeyRouting.next(from: 47, range: 0...100, press: press(.up, .percent5)).rounded() == 50)
    #expect(BrightnessKeyRouting.next(from: 47, range: 0...100, press: press(.down, .percent5)).rounded() == 45)
    #expect(BrightnessKeyRouting.next(from: 47, range: 0...100, press: press(.up, .percent10)).rounded() == 50)
    #expect(BrightnessKeyRouting.next(from: 47, range: 0...100, press: press(.down, .percent10)).rounded() == 40)
    #expect(BrightnessKeyRouting.next(from: 99, range: 0...100, press: press(.up, .percent2)).rounded() == 100)
}

@Test func theFineStepIsAQuarterButNeverBelowOnePercent() {
    #expect(KeyStep.likeMacOS.fineFraction == 1.0 / 64)
    #expect(KeyStep.percent10.fineFraction == 0.025)
    #expect(KeyStep.percent5.fineFraction == 0.0125)
    #expect(KeyStep.percent2.fineFraction == 0.01)
    #expect(KeyStep.percent1.fineFraction == 0.01)
    #expect(BrightnessKeyRouting.next(from: 50, range: 0...100, press: press(.up, .percent10, fine: true)) == 52.5)
    #expect(BrightnessKeyRouting.next(from: 50, range: 0...100, press: press(.up, .percent2, fine: true)).rounded() == 51)
}

@Test func onePercentStepsNeverStallOnSoftwareDimmingsRange() {
    // 1% of 10…100 is 0.9; each step still lands a whole percent further.
    var value = 10.0
    for _ in 0..<90 {
        let next = BrightnessKeyRouting.next(from: value, range: 10...100, press: press(.up, .percent1), tolerance: 0.5).rounded()
        #expect(next == value + 1)
        value = next
    }
    #expect(value == 100)
}

@Test func theKeysFooterSaysWhatAPressDoes() {
    #expect(KeyStep.likeMacOS.footer.hasPrefix("Each press is one sixteenth of the range"))
    #expect(KeyStep.percent5.footer.hasPrefix("Each press moves 5% of the range."))
    #expect(KeyStep.allCases.allSatisfy { $0.footer.contains("1% at a time") })
}

@MainActor @Test func demoStoreHandsBrightnessKeysToMacOS() {
    SettingsFixture.withSuite { defaults in
        let store = GlowStore(settings: GlowSettingsStore(defaults: defaults), demoDisplays: true)
        #expect(!store.handleBrightnessKey(up, pointerDisplay: nil))
    }
}

// MARK: Brightness Match

/// The desk with brightness set: the MacBook Pro at 50, the Dell at 40, the LG at 80.
private func matchedDesk(_ values: [PersistentDisplayIdentity: Double] = [mac: 50, dell: 40, lg: 80],
                         without missing: PersistentDisplayIdentity? = nil) -> [DisplaySnapshot] {
    desk.filter { $0.id != missing }.map { display in
        var display = display
        if let value = values[display.id], let index = display.capabilities.firstIndex(where: { $0.id == .brightness }) {
            display.capabilities[index].currentValue = .number(value)
        }
        return display
    }
}

/// The Dell matched to the MacBook Pro by Quick Match: at half, it looked the same at 40 %.
private func dellFollowsMac(route: ControlRoute = .hardware) -> BrightnessMatchSettings {
    var match = BrightnessMatchSettings()
    match.save([MatchCalibration(pair: MatchPair(reference: mac, display: dell), curve: MatchCurve.quick(reference: 0.5, display: 0.4)!,
                                 method: .quick, referenceRoute: .native, displayRoute: route)])
    return match
}

private func plan(_ press: BrightnessKeyPress, _ targets: [PersistentDisplayIdentity] = [mac, dell, lg],
                  displays: [DisplaySnapshot] = matchedDesk(), match: BrightnessMatchSettings = dellFollowsMac()) -> [Double] {
    MatchFollow.keyPlan(press: press, targets: targets, displays: displays, match: match).map(\.1)
}

@Test func matchedDisplaysFollowTheirCurveFromTheReferencesNewLevel() {
    // The Mac takes its step; the Dell goes to its curve there, not a step of its own.
    #expect(plan(up) == [56.25, 45, 81.25])
    #expect(plan(down) == [43.75, 35, 75])
}

@Test func withoutAMatchEveryDisplayStepsOnItsOwn() {
    #expect(plan(up, match: BrightnessMatchSettings()) == [56.25, 43.75, 81.25])
}

@Test func aMatchedDisplayNeverMovesAgainstTheKey() {
    // Its own slider took the Dell above its curve: it waits there going up, and joins
    // the curve going down.
    let displays = matchedDesk([mac: 50, dell: 60, lg: 80])
    #expect(plan(up, displays: displays) == [56.25, 60, 81.25])
    #expect(plan(down, displays: displays) == [43.75, 35, 75])
}

@Test func withTheReferenceAwayTheGroupStepsOnTheReferencesScale() {
    // The Dell at 40 is where the Mac's half would put it, so it moves as the Mac's next step would.
    #expect(plan(up, [dell, lg], displays: matchedDesk(without: mac)) == [45, 81.25])
}

@Test func aMatchedDisplayTargetedAloneStepsOnItsOwn() {
    #expect(plan(up, [dell]) == [43.75])
}

@Test func anOutOfDateMatchIsNotFollowed() {
    #expect(plan(up, match: dellFollowsMac(route: .software)) == [56.25, 43.75, 81.25])
}

@Test func followersAtTheirEndsStayInTheirRange() {
    let displays = matchedDesk([mac: 100, dell: 80, lg: 100])
    #expect(plan(up, displays: displays) == [100, 80, 100])
    let low = matchedDesk([mac: 0, dell: 0, lg: 0])
    #expect(plan(down, displays: low) == [0, 0, 0])
    // From the bottom, the Dell climbs with the Mac.
    #expect(plan(up, displays: low) == [6.25, 5, 6.25])
}
