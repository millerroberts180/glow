import Testing
@testable import GlowApp

/// MacBook Pro (built-in, native), Dell U2723QE (hardware), LG UltraFine 27 (software).
private let desk = DemoData.displays(generation: 1)
private let mac = desk[0].id
private let dell = desk[1].id
private let lg = desk[2].id

private func samples(_ curve: BrightnessCurve) -> [Double] {
    (0...20).map { curve.value(for: Double($0) / 20) }
}

private func isMonotoneAndInRange(_ curve: BrightnessCurve) -> Bool {
    let values = samples(curve)
    return zip(values, values.dropFirst()).allSatisfy { $0 <= $1 } && values.allSatisfy { (0...1).contains($0) }
}

private func calibration(_ display: PersistentDisplayIdentity, follows reference: PersistentDisplayIdentity = mac,
                         method: MatchMethod = .quick, referenceRoute: ControlRoute = .native, displayRoute: ControlRoute) -> MatchCalibration {
    MatchCalibration(pair: MatchPair(reference: reference, display: display), curve: MatchCurve.quick(reference: 0.5, display: 0.4)!,
                     method: method, referenceRoute: referenceRoute, displayRoute: displayRoute)
}

// MARK: Curves

@Test func quickMatchIsARatioFromBothDisplaysDarkest() throws {
    let curve = try #require(MatchCurve.quick(reference: 0.5, display: 0.4))
    #expect(curve.value(for: 0) == 0)
    #expect(curve.value(for: 0.25) == 0.2)
    #expect(curve.value(for: 0.5) == 0.4)
    #expect(curve.value(for: 1) == 0.8)
}

@Test func quickMatchBrighterThanTheReferenceReachesFullAndStays() throws {
    let curve = try #require(MatchCurve.quick(reference: 0.5, display: 0.8))
    #expect(curve.value(for: 0.5) == 0.8)
    #expect(curve.value(for: 0.625) == 1)
    #expect(curve.value(for: 0.9) == 1)
    #expect(isMonotoneAndInRange(curve))
}

@Test func quickMatchNeedsALitReference() {
    #expect(MatchCurve.quick(reference: 0, display: 0.3) == nil)
    #expect(MatchCurve.quick(reference: .nan, display: 0.3) == nil)
}

@Test func guidedMatchTakesThreeToFivePoints() {
    let points = MatchCurve.guidedLevels.map { CalibrationPoint(reference: $0, display: $0 * 0.9) }
    #expect(MatchCurve.guided(Array(points.prefix(2))) == nil)
    #expect(MatchCurve.guided(Array(points.prefix(3))) != nil)
    #expect(MatchCurve.guided(points) != nil)
    #expect(MatchCurve.guided(points + [CalibrationPoint(reference: 0.9, display: 0.8)]) == nil)
}

@Test func guidedCurvesPassThroughEachPoint() throws {
    let points = [(0.2, 0.3), (0.4, 0.5), (0.6, 0.6), (0.8, 0.75), (1.0, 0.9)].map { CalibrationPoint(reference: $0.0, display: $0.1) }
    let curve = try #require(MatchCurve.guided(points))
    for point in points { #expect(abs(curve.value(for: point.reference) - point.display) < 1e-9) }
    // Below the first point it falls straight to both displays' darkest.
    #expect(curve.value(for: 0) == 0)
    #expect(abs(curve.value(for: 0.1) - 0.15) < 1e-9)
}

@Test func guidedCurvesNeverTurnBackOrLeaveTheRange() throws {
    let points = [(0.2, 0.4), (0.4, 0.3), (0.6, 1.4), (0.8, -0.2), (1.2, 0.9)].map { CalibrationPoint(reference: $0.0, display: $0.1) }
    let curve = try #require(MatchCurve.guided(points))
    #expect(isMonotoneAndInRange(curve))
    #expect(curve.value(for: 1) == 1)
}

@Test func theInverseFindsTheLowestReferenceLevel() throws {
    let curve = try #require(MatchCurve.quick(reference: 0.5, display: 0.4))
    #expect(curve.referenceLevel(for: 0) == 0)
    #expect(curve.referenceLevel(for: 0.4) == 0.5)
    // Out of reach: the reference's top is as near as it gets.
    #expect(curve.referenceLevel(for: 1) == 1)
    let flat = try #require(MatchCurve.quick(reference: 0.5, display: 0.8))
    #expect(flat.referenceLevel(for: 1) == 0.625)
    for level in stride(from: 0.0, through: 1, by: 0.05) {
        #expect(abs(curve.value(for: curve.referenceLevel(for: curve.value(for: level))) - curve.value(for: level)) < 1e-9)
    }
}

@Test func levelsBeyondTheEndsHoldAtTheEnds() throws {
    let curve = try #require(MatchCurve.quick(reference: 0.5, display: 0.4))
    #expect(curve.value(for: -1) == 0)
    #expect(curve.value(for: 2) == 0.8)
    #expect(curve.referenceLevel(for: -1) == 0)
}

@Test func levelsMapOntoEachDisplaysOwnRangeAndSteps() throws {
    var dimmed = try #require(desk[2].brightnessSetting)
    dimmed.kind = .range(minimum: 10, maximum: 100, step: 1)
    #expect(dimmed.matchValue(at: 0) == 10)
    #expect(dimmed.matchValue(at: 0.5) == 55)
    #expect(dimmed.matchValue(at: 1.5) == 100)
    #expect(dimmed.matchValue(at: 0.333) == 40)
    #expect(dimmed.matchLevel(of: 5) == 0)
    #expect(dimmed.matchLevel(of: 100) == 1)
}

// MARK: Saved matches

@Test func settingsFromBeforeBrightnessMatchDecodeWithNoMatches() throws {
    let settings = try SettingsFixture.decode(#"{"choseDemoDisplays":true,"useDemoDisplays":true,"matchMethod":"guided","controlTarget":"focused"}"#)
    #expect(settings.brightnessMatch == BrightnessMatchSettings())
    #expect(settings.matchMethod == .guided)
    #expect(settings.controlTarget == .focused)
}

@Test func anUnreadableMatchKeepsTheRestOfSettings() throws {
    let settings = try SettingsFixture.decode(#"{"matchMethod":"guided","brightnessMatch":"nonsense","fineAdjustment":false}"#)
    #expect(settings.brightnessMatch == BrightnessMatchSettings())
    #expect(settings.matchMethod == .guided)
    #expect(!settings.fineAdjustment)
}

@Test func matchesRoundTripWithTheirVersion() throws {
    var match = BrightnessMatchSettings()
    match.moveTogether = true
    match.save([calibration(dell, method: .guided, displayRoute: .hardware), calibration(lg, displayRoute: .software)])
    var settings = GlowSettings()
    settings.brightnessMatch = match
    let back = try SettingsFixture.roundTrip(settings)
    #expect(back.brightnessMatch == match)
    #expect(back.brightnessMatch.version == BrightnessMatchSettings.currentVersion)
    #expect(back.brightnessMatch.calibration(for: dell)?.method == .guided)
}

@Test func oneUnreadableCalibrationLeavesTheOthers() throws {
    var match = BrightnessMatchSettings()
    match.save([calibration(dell, displayRoute: .hardware), calibration(lg, displayRoute: .software)])
    // A route from a newer Glow.
    let json = try MatchFixture.json(match).replacing(#""displayRoute":"software""#, with: #""displayRoute":"laser""#)
    let back = try MatchFixture.decode(json)
    #expect(back.calibrations.map(\.pair.display) == [dell])
    #expect(try MatchFixture.decode(#"{"version":7,"moveTogether":true}"#).moveTogether)
}

@Test func aSavedCurveThatTurnsBackIsStraightenedAsItLoads() throws {
    let json = try MatchFixture.calibrationJSON(calibration(dell, displayRoute: .hardware), points: [(0, 0), (0.5, 0.6), (1, 0.4)])
    let back = try MatchFixture.decode(#"{"calibrations":["# + json + "]}")
    let curve = try #require(back.calibration(for: dell)?.curve)
    #expect(isMonotoneAndInRange(curve))
    #expect(curve.value(for: 1) == 0.6)
}

@Test func savingAMatchReplacesOldOnesSoReferencesNeverChain() {
    var match = BrightnessMatchSettings()
    match.save([calibration(dell, displayRoute: .hardware)])
    // Now the Mac follows the LG: the Dell's match to the Mac goes.
    match.save([calibration(mac, follows: lg, referenceRoute: .software, displayRoute: .native)])
    #expect(match.calibrations.map(\.pair) == [MatchPair(reference: lg, display: mac)])
    match.forget([lg])
    #expect(match.calibrations.isEmpty)
}

// MARK: Status

@Test func appearanceMatchedComesFromSavedMatches() {
    var match = BrightnessMatchSettings()
    match.save([calibration(dell, displayRoute: .hardware)])
    let annotated = match.annotated(desk)
    #expect(annotated.map(\.isAppearanceMatched) == [true, true, false])
    #expect(match.state(of: desk[0], among: desk) == .reference(followers: ["Dell U2723QE"]))
    #expect(match.state(of: desk[2], among: desk) == .notMatched)
}

@Test func aChangedRouteMakesAMatchOutOfDate() {
    var match = BrightnessMatchSettings()
    let old = calibration(dell, displayRoute: .software)
    match.save([old])
    #expect(match.state(of: desk[1], among: desk) == .outOfDate(old, was: .software, now: .hardware))
    #expect(match.annotated(desk).map(\.isAppearanceMatched) == [false, false, false])
    #expect(match.active(among: desk).isEmpty)
}

@Test func aReferenceWithItsMatchedDisplaysAwayIsNotMatched() {
    var match = BrightnessMatchSettings()
    match.save([calibration(dell, displayRoute: .hardware)])
    let alone = desk.filter { $0.id != dell }
    #expect(match.state(of: alone[0], among: alone) == .reference(followers: []))
    #expect(match.annotated(alone).map(\.isAppearanceMatched) == [false, false])
    // A matched display keeps its match while the reference is away.
    #expect(match.annotated(desk.filter { $0.id != mac }).map(\.isAppearanceMatched) == [true, false])
}

// MARK: The store and a calibration run

/// Displays from the demo desk at the levels given; records every brightness write.
@MainActor
private final class FakeAdapter: DisplayAdapter {
    let name = "Test adapter"
    private(set) var levels: [PersistentDisplayIdentity: Double]
    private(set) var writes: [(PersistentDisplayIdentity, Double)] = []
    var refusing: Set<PersistentDisplayIdentity> = []

    init(_ levels: [PersistentDisplayIdentity: Double] = [mac: 50, dell: 40, lg: 80]) {
        self.levels = levels
    }

    func discover(generation: UInt64) async -> [DisplaySnapshot] {
        DemoData.displays(generation: generation).map { display in
            var display = display
            if let level = levels[display.id], let index = display.capabilities.firstIndex(where: { $0.id == .brightness }) {
                display.capabilities[index].currentValue = .number(level)
                display.capabilities[index].lastConfirmedValue = .number(level)
            }
            return display
        }
    }

    func write(_ value: CapabilityValue, capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws {
        guard !refusing.contains(display) else { throw ControlError.notWritable }
        guard capability == .brightness, case let .number(level) = value else { throw ControlError.invalidValue }
        writes.append((display, level))
        levels[display] = level
    }

    func read(capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws -> CapabilityValue {
        guard capability == .brightness, let level = levels[display] else { throw ControlError.notWritable }
        return .number(level)
    }
}

@MainActor
private final class RecordingPatches: MatchPatchPresenting {
    var showsOnScreens: Bool { true }
    private(set) var shown: [MatchPatch] = []
    func show(_ patches: [MatchPatch]) { shown = patches }
    func hide() { shown = [] }
}

@MainActor
private func brightness(_ store: GlowStore, _ id: PersistentDisplayIdentity) -> Double? {
    store.displays.first { $0.id == id }?.brightnessSetting?.matchNumber
}

@MainActor @Test func theStoreMarksMatchedDisplaysAfterDiscovery() async {
    await MatchFixture.withStore(adapter: FakeAdapter()) { store in
        store.settings.value.brightnessMatch.save([calibration(dell, displayRoute: .hardware)])
        await store.refresh()
        #expect(store.displays.map(\.isAppearanceMatched) == [true, true, false])
        #expect(store.hasMatchToForget)
        store.forgetMatch()
        #expect(store.displays.map(\.isAppearanceMatched) == [false, false, false])
        #expect(!store.hasMatchToForget)
    }
}

@MainActor @Test func everyDisplayKeysMoveMatchedDisplaysAlongTheirCurves() async {
    await MatchFixture.withStore(adapter: FakeAdapter()) { store in
        await store.refresh()
        store.brightnessMatch.save([calibration(dell, displayRoute: .hardware)])
        store.controlTarget = .all
        #expect(store.handleBrightnessKey(BrightnessKeyPress(direction: .up, quarterStep: false), pointerDisplay: nil))
        // Each lands on its own whole-percent steps.
        #expect([mac, dell, lg].map { brightness(store, $0) } == [56, 45, 81])
        // Focused on the Dell: it steps alone, from where it is.
        store.controlTarget = .focused
        store.focusedDisplayID = dell
        _ = store.handleBrightnessKey(BrightnessKeyPress(direction: .up, quarterStep: false), pointerDisplay: nil)
        #expect([mac, dell, lg].map { brightness(store, $0) } == [56, 50, 81])
    }
}

@MainActor @Test func aReferencesSliderMovesMatchedDisplaysOnlyWhenAskedTo() async {
    await MatchFixture.withStore(adapter: FakeAdapter()) { store in
        await store.refresh()
        store.brightnessMatch.save([calibration(dell, displayRoute: .hardware)])
        store.update(displayID: mac, capabilityID: .brightness, proposed: .number(25))
        #expect(brightness(store, dell) == 40)
        store.moveMatchedTogether = true
        store.update(displayID: mac, capabilityID: .brightness, proposed: .number(75))
        #expect(brightness(store, dell) == 60)
        // A matched display's own slider sets it alone.
        store.update(displayID: dell, capabilityID: .brightness, proposed: .number(30))
        #expect(brightness(store, mac) == 75)
    }
}

@MainActor @Test func cancelPutsEveryChangedDisplayBackAndKeepsNothing() async {
    let adapter = FakeAdapter()
    await MatchFixture.withStore(adapter: adapter) { store in
        await store.refresh()
        let patches = RecordingPatches()
        let session = MatchSession(store: store, patches: patches)
        var closed = false
        session.onFinish = { closed = true }
        session.method = .guided
        #expect(session.referenceID == mac)
        session.begin()
        #expect(patches.shown.map(\.isReference) == [true, false, false])
        session.set(dell, to: 30)
        session.next()
        session.set(lg, to: 20)
        await session.cancel()
        #expect(patches.shown.isEmpty)
        #expect(closed)
        #expect(adapter.levels == [mac: 50, dell: 40, lg: 80])
        #expect([mac, dell, lg].map { brightness(store, $0) } == [50, 40, 80])
        #expect(!adapter.writes.isEmpty)
        #expect(store.brightnessMatch.calibrations.isEmpty)
    }
}

@MainActor @Test func cancelBeforeStartingWritesNothing() async {
    let adapter = FakeAdapter()
    await MatchFixture.withStore(adapter: adapter) { store in
        await store.refresh()
        let session = MatchSession(store: store, patches: RecordingPatches())
        var closed = false
        session.onFinish = { closed = true }
        await session.cancel()
        #expect(closed)
        #expect(adapter.writes.isEmpty)
    }
}

@MainActor @Test func aRestoreThatFailsKeepsTheWindowOpenAndSaysWhich() async {
    let adapter = FakeAdapter()
    await MatchFixture.withStore(adapter: adapter) { store in
        await store.refresh()
        let session = MatchSession(store: store, patches: RecordingPatches())
        var closed = false
        session.onFinish = { closed = true }
        session.begin()
        session.set(dell, to: 30)
        session.set(lg, to: 60)
        adapter.refusing = [lg]
        await session.cancel()
        #expect(adapter.levels[dell] == 40)
        #expect(session.step == .finished)
        #expect(session.problem?.contains("LG UltraFine 27") == true)
        #expect(!closed)
        session.close()
        #expect(closed)
    }
}

@MainActor @Test func quickMatchSavesARatioAndPutsTheReferenceBack() async throws {
    let adapter = FakeAdapter()
    try await MatchFixture.withStore(adapter: adapter) { store in
        await store.refresh()
        let session = MatchSession(store: store, patches: RecordingPatches())
        session.method = .quick
        session.begin()
        // Quick Match changes nothing until the person does.
        #expect(adapter.writes.isEmpty)
        session.set(dell, to: 30)
        session.next()
        #expect(session.step == .review)
        await session.save()
        #expect(session.step == .finished)
        let saved = try #require(store.brightnessMatch.calibration(for: dell))
        #expect(saved.method == .quick)
        #expect(abs(saved.curve.value(for: 1) - 0.6) < 1e-9)
        #expect(store.brightnessMatch.calibration(for: lg) != nil)
        #expect(adapter.levels[mac] == 50)
        #expect(adapter.levels[dell] == 30)
        #expect(store.displays.map(\.isAppearanceMatched) == [true, true, true])
    }
}

@MainActor @Test func guidedSlidersCantGoBelowThePointBefore() async {
    await MatchFixture.withStore(adapter: FakeAdapter()) { store in
        await store.refresh()
        let session = MatchSession(store: store, patches: RecordingPatches())
        session.method = .guided
        session.begin()
        #expect(session.levels == MatchCurve.guidedLevels)
        #expect(session.referenceValue(at: 0) == 20)
        session.set(dell, to: 50)
        session.next()
        #expect(session.bounds(of: dell)?.lowerBound == 50)
        session.set(dell, to: 10)
        #expect(session.value(of: dell) == 50)
        // The reference's own level isn't the person's to set.
        session.set(mac, to: 90)
        #expect(session.value(of: mac) == 40)
        await session.cancel()
    }
}

@MainActor @Test func arrowKeysNudgeTheChosenDisplayAndMoveBetweenThem() async {
    await MatchFixture.withStore(adapter: FakeAdapter()) { store in
        await store.refresh()
        let session = MatchSession(store: store, patches: RecordingPatches())
        session.begin()
        #expect(session.adjustingID == dell)
        session.nudge(1)
        #expect(session.value(of: dell) == 41)
        session.nudge(-5)
        #expect(session.value(of: dell) == 36)
        session.selectAdjacent(1)
        #expect(session.adjustingID == lg)
        session.selectAdjacent(1)
        #expect(session.adjustingID == dell)
        await session.cancel()
    }
}

@MainActor @Test func matchingSaysWhyItCantStart() async {
    await MatchFixture.withStore(adapter: FakeAdapter([mac: 0, dell: 40, lg: 80])) { store in
        await store.refresh()
        let alone = MatchSession(store: store, patches: RecordingPatches(), candidates: store.displays.filter(\.isBuiltIn))
        #expect(alone.unavailableReason?.contains("two displays") == true)
        #expect(!alone.canStart)
        let dark = MatchSession(store: store, patches: RecordingPatches())
        dark.method = .quick
        #expect(dark.startProblem?.contains("at its lowest") == true)
        #expect(!dark.canStart)
        dark.method = .guided
        #expect(dark.canStart)
    }
}
