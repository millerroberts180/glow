import Testing
@testable import GlowApp

/// MacBook Pro (built-in, native), Dell U2723QE (hardware), LG UltraFine 27 (software).
private let desk = DemoData.displays(generation: 1)
private let mac = desk[0].id
private let dell = desk[1].id
private let lg = desk[2].id

/// Stands in for macOS's Accessibility grant.
@MainActor
private final class FakeAccess {
    var granted: Bool
    var bundled: Bool
    private(set) var requests = 0

    init(granted: Bool = false, bundled: Bool = true) {
        self.granted = granted
        self.bundled = bundled
    }

    var permission: KeyPermission {
        KeyPermission(isGranted: { self.granted }, request: { self.requests += 1 }, isBundledApp: { self.bundled })
    }
}

/// Stands in for macOS's Login Items, and records each change setup asks for.
@MainActor
private final class FakeLogin {
    let canRegister: Bool
    var on: Bool
    private(set) var sets: [Bool] = []

    init(canRegister: Bool = true, on: Bool = false) {
        self.canRegister = canRegister
        self.on = on
    }

    var login: SetupLogin {
        SetupLogin(canRegister: canRegister, isOn: { self.on }, detail: { "Login Items" }, set: { self.sets.append($0); self.on = $0 })
    }
}

/// The demo desk's displays named, at the levels given; records every brightness write.
@MainActor
private final class FakeAdapter: DisplayAdapter {
    let name = "Test adapter"
    var connected: [PersistentDisplayIdentity]
    private(set) var levels: [PersistentDisplayIdentity: Double]
    private(set) var writes: [(PersistentDisplayIdentity, Double)] = []

    init(_ connected: [PersistentDisplayIdentity] = [mac, dell], levels: [PersistentDisplayIdentity: Double] = [mac: 50, dell: 40, lg: 80]) {
        self.connected = connected
        self.levels = levels
    }

    func discover(generation: UInt64) async -> [DisplaySnapshot] {
        DemoData.displays(generation: generation).filter { connected.contains($0.id) }.map { display in
            var display = display
            if let level = levels[display.id], let index = display.capabilities.firstIndex(where: { $0.id == .brightness }) {
                display.capabilities[index].currentValue = .number(level)
                display.capabilities[index].lastConfirmedValue = .number(level)
            }
            return display
        }
    }

    func write(_ value: CapabilityValue, capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws {
        guard capability == .brightness, case let .number(level) = value else { throw ControlError.invalidValue }
        writes.append((display, level))
        levels[display] = level
    }

    func read(capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws -> CapabilityValue {
        guard capability == .brightness, let level = levels[display] else { throw ControlError.notWritable }
        return .number(level)
    }
}

/// The grey patches as if on the screens, remembered instead of shown.
@MainActor
private final class RecordingPatches: MatchPatchPresenting {
    var showsOnScreens: Bool { true }
    private(set) var shown: [MatchPatch] = []
    private(set) var shows = 0
    func show(_ patches: [MatchPatch]) { shown = patches; shows += 1 }
    func hide() { shown = [] }
}

@MainActor
private func makeModel(_ store: GlowStore, tutorialOnly: Bool = false, access: FakeAccess = FakeAccess(),
                       login: FakeLogin = FakeLogin(canRegister: false), patches: RecordingPatches = RecordingPatches()) -> SetupModel {
    SetupModel(store: store, login: login.login, tutorialOnly: tutorialOnly, permission: access.permission, patches: { _ in patches })
}

@MainActor
private func brightness(_ store: GlowStore, _ id: PersistentDisplayIdentity) -> Double? {
    store.displays.first { $0.id == id }?.brightnessSetting?.matchNumber
}

// MARK: Completion

@Test func settingsWithoutSetupCompletionHaveNotSeenSetup() throws {
    #expect(try SettingsFixture.decode("{}").hasCompletedSetup == false)
}

@Test func setupCompletionDecodesWithoutResettingTheRest() throws {
    let settings = try SettingsFixture.decode(#"{"hasCompletedSetup": true}"#)
    var expected = GlowSettings()
    expected.hasCompletedSetup = true
    #expect(settings == expected)
}

@Test func setupCompletionRoundTripsThroughJSON() throws {
    var settings = GlowSettings()
    settings.hasCompletedSetup = true
    settings.controlTarget = .underCursor
    #expect(try SettingsFixture.roundTrip(settings) == settings)
}

@MainActor @Test func setupCompletionIsSavedAndReadBack() {
    SettingsFixture.withSuite { defaults in
        let store = GlowSettingsStore(defaults: defaults)
        store.value.hasCompletedSetup = true
        store.flush()
        #expect(GlowSettingsStore(defaults: defaults).value.hasCompletedSetup)
    }
}

// MARK: Steps

@Test func firstRunWalksThroughMatchingToTheFinishAndTheTutorialSkipsTheEnds() {
    #expect(SetupModel.steps(tutorialOnly: false) == [.welcome, .displays, .match, .finish])
    #expect(SetupModel.steps(tutorialOnly: true) == [.displays, .match])
}

@MainActor @Test func finishingFirstRunRecordsCompletionOnce() {
    SetupFixture.withStore { store, saved in
        let model = makeModel(store)
        var finished = 0
        model.onFinish = { finished += 1 }
        #expect(model.step == .welcome && model.isFirst && model.stepNumber == 1)
        for _ in model.steps { model.next() }
        #expect(finished == 1)
        #expect(model.step == .finish)
        #expect(!model.isWatchingAccess)
        #expect(saved().hasCompletedSetup)
    }
}

@MainActor @Test func backStopsAtTheFirstStep() {
    SetupFixture.withStore { store, _ in
        let model = makeModel(store)
        model.next()
        model.back()
        model.back()
        #expect(model.step == .welcome)
    }
}

@MainActor @Test func tutorialShowsTheDisplaysAndTheMatchThenDone() {
    SetupFixture.withStore { store, saved in
        let login = FakeLogin(on: false)
        let model = makeModel(store, tutorialOnly: true, login: login)
        var finished = 0
        model.onFinish = { finished += 1 }
        #expect(model.step == .displays && model.isFirst)
        #expect(model.primaryTitle == "Continue")
        model.next()
        #expect(model.step == .match && model.isLast)
        #expect(model.primaryTitle == "Done")
        model.primary()
        #expect(finished == 1)
        // It has no finish step, so it changes neither open at login nor completion.
        #expect(login.sets.isEmpty)
        #expect(!saved().hasCompletedSetup)
        #expect(!store.settings.value.hasCompletedSetup)
    }
}

@MainActor @Test func closingMidwayCountsAsSeenAndStopsWatching() {
    SetupFixture.withStore { store, saved in
        let model = makeModel(store)
        model.step = .finish
        #expect(model.isWatchingAccess)
        model.close()
        #expect(!model.isWatchingAccess)
        #expect(saved().hasCompletedSetup)
    }
}

@MainActor @Test func closingTheTutorialLeavesCompletionAlone() {
    SetupFixture.withStore { store, saved in
        let model = makeModel(store, tutorialOnly: true)
        model.next()
        model.close()
        #expect(!saved().hasCompletedSetup)
    }
}

@MainActor @Test func primaryButtonSaysWhatItDoes() async {
    await SetupFixture.withStore(adapter: FakeAdapter()) { store, _ in
        await store.refresh()
        let model = makeModel(store)
        #expect(model.primaryTitle == "Get Started")
        model.next()
        #expect(model.primaryTitle == "Continue")
        model.next()
        #expect(model.primaryTitle == "Start Matching")
        model.primary()
        #expect(model.matchStage == .adjust)
        #expect(model.primaryTitle == "Save Match")
        model.primary()
        await model.work?.value
        #expect(model.matchStage == .matched)
        #expect(model.primaryTitle == "Continue")
        model.next()
        #expect(model.primaryTitle == "Start Using Glow")
    }
}

// MARK: Matching

@MainActor @Test func oneDisplaySetsItsBrightnessInsteadOfMatching() async {
    let adapter = FakeAdapter([mac])
    await SetupFixture.withStore(adapter: adapter) { store, _ in
        await store.refresh()
        let patches = RecordingPatches()
        let model = makeModel(store, patches: patches)
        model.step = .match
        #expect(model.matchStage == .single)
        #expect(!model.showsNotNow && !model.isMatching && model.canGoOn)
        #expect(model.primaryTitle == "Continue")
        model.primary()
        #expect(model.step == .finish)
        #expect(patches.shows == 0)
        #expect(adapter.writes.isEmpty)
        #expect(store.brightnessMatch.calibrations.isEmpty)
    }
}

@MainActor @Test func twoDisplaysOfferAQuickMatchThatNotNowSkips() async {
    let adapter = FakeAdapter()
    await SetupFixture.withStore(adapter: adapter) { store, _ in
        await store.refresh()
        // Demo displays have no screens, so their patches stay in the window.
        #expect(!SetupModel.livePatches(store).showsOnScreens)
        let patches = RecordingPatches()
        let model = makeModel(store, patches: patches)
        model.step = .match
        #expect(model.matchStage == .pick)
        #expect(model.match?.method == .quick)
        #expect(model.match?.referenceID == mac)
        #expect(model.showsNotNow && model.canGoOn)
        // Not Now goes on and changes nothing.
        model.next()
        await model.work?.value
        #expect(model.step == .finish)
        #expect(patches.shows == 0)
        #expect(adapter.writes.isEmpty)
        #expect(store.brightnessMatch.calibrations.isEmpty)
        #expect(!store.moveMatchedTogether)
    }
}

@MainActor @Test func safeModeSaysMatchingCantStart() async throws {
    try await SetupFixture.withStore(adapter: FakeAdapter(), safeMode: true) { store, _ in
        await store.refresh()
        let model = makeModel(store)
        model.step = .match
        let reason = try #require(model.match?.unavailableReason)
        #expect(reason.contains("safe mode"))
        #expect(model.matchStage == .unavailable(reason))
        #expect(!model.showsNotNow && model.canGoOn)
        #expect(model.primaryTitle == "Continue")
    }
}

@MainActor @Test func savingKeepsTheMatchAsSettingsDoesAndMovesThemTogether() async throws {
    let adapter = FakeAdapter()
    try await SetupFixture.withStore(adapter: adapter) { store, _ in
        await store.refresh()
        let patches = RecordingPatches()
        let model = makeModel(store, patches: patches)
        var raised: [Bool] = []
        model.onPatchesChange = { raised.append($0) }
        model.step = .match
        model.primary()
        #expect(model.matchStage == .adjust && model.isMatching)
        #expect(!model.showsNotNow)
        #expect(patches.shown.map(\.isReference) == [true, false])
        #expect(raised == [true])
        // Quick Match changes nothing until the person does.
        #expect(adapter.writes.isEmpty)
        model.match?.set(dell, to: 30)
        model.primary()
        await model.work?.value
        #expect(model.matchStage == .matched && !model.isMatching)
        #expect(patches.shown.isEmpty)
        #expect(raised.last == false)
        let saved = try #require(store.brightnessMatch.calibration(for: dell))
        #expect(saved.method == .quick)
        #expect(abs(saved.curve.value(for: 1) - 0.6) < 1e-9)
        #expect(adapter.levels[mac] == 50)
        #expect(adapter.levels[dell] == 30)
        #expect(store.displays.map(\.isAppearanceMatched) == [true, true])
        // They move together from the reference's slider, as in the popover.
        #expect(store.moveMatchedTogether)
        store.update(displayID: mac, capabilityID: .brightness, proposed: .number(75))
        #expect(brightness(store, dell) == 45)
    }
}

@MainActor @Test func aSaveWithNothingToKeepGoesBackToComparing() async {
    let adapter = FakeAdapter()
    await SetupFixture.withStore(adapter: adapter) { store, _ in
        await store.refresh()
        let model = makeModel(store)
        model.step = .match
        model.startMatch()
        // The Dell goes away part way.
        adapter.connected = [mac]
        await store.refresh()
        await model.saveMatch()
        #expect(model.saveProblem?.contains("Nothing to save") == true)
        #expect(model.matchStage == .adjust)
        #expect(!store.moveMatchedTogether)
        #expect(store.brightnessMatch.calibrations.isEmpty)
        model.cancel()
        await model.work?.value
        #expect(model.saveProblem == nil)
    }
}

@MainActor @Test func cancelPutsEveryDisplayBackAndOffersTheMatchAgain() async {
    let adapter = FakeAdapter()
    await SetupFixture.withStore(adapter: adapter) { store, _ in
        await store.refresh()
        let patches = RecordingPatches()
        let model = makeModel(store, patches: patches)
        model.step = .match
        model.primary()
        model.match?.set(dell, to: 30)
        let first = model.match
        model.cancel()
        await model.work?.value
        #expect(!adapter.writes.isEmpty)
        #expect(adapter.levels == [mac: 50, dell: 40, lg: 80])
        #expect(brightness(store, dell) == 40)
        #expect(patches.shown.isEmpty)
        #expect(store.brightnessMatch.calibrations.isEmpty)
        #expect(model.step == .match)
        #expect(model.matchStage == .pick)
        #expect(model.match !== first)
    }
}

@MainActor @Test func backWhileMatchingPutsEveryDisplayBack() async {
    let adapter = FakeAdapter()
    await SetupFixture.withStore(adapter: adapter) { store, _ in
        await store.refresh()
        let patches = RecordingPatches()
        let model = makeModel(store, patches: patches)
        model.step = .match
        model.primary()
        model.match?.set(dell, to: 30)
        model.back()
        #expect(model.step == .displays)
        await model.work?.value
        #expect(adapter.levels[dell] == 40)
        #expect(brightness(store, dell) == 40)
        #expect(patches.shown.isEmpty)
        #expect(store.brightnessMatch.calibrations.isEmpty)
        // Coming back starts over.
        model.next()
        #expect(model.matchStage == .pick)
    }
}

@MainActor @Test func closingWhileMatchingPutsEveryDisplayBack() async {
    let adapter = FakeAdapter()
    await SetupFixture.withStore(adapter: adapter) { store, saved in
        await store.refresh()
        let patches = RecordingPatches()
        let model = makeModel(store, patches: patches)
        model.step = .match
        model.primary()
        model.match?.set(dell, to: 25)
        model.close()
        await model.work?.value
        #expect(adapter.levels[dell] == 40)
        #expect(patches.shown.isEmpty)
        #expect(store.brightnessMatch.calibrations.isEmpty)
        #expect(saved().hasCompletedSetup)
    }
}

@MainActor @Test func aSavedMatchStaysDoneUntilMatchedAgain() async {
    let adapter = FakeAdapter()
    await SetupFixture.withStore(adapter: adapter) { store, _ in
        await store.refresh()
        let model = makeModel(store)
        model.step = .match
        model.primary()
        model.primary()
        await model.work?.value
        #expect(model.matchStage == .matched)
        let writes = adapter.writes.count
        // Leaving and coming back keeps it, and writes nothing.
        model.back()
        model.next()
        await model.work?.value
        #expect(model.matchStage == .matched)
        #expect(adapter.writes.count == writes)
        // Match Again offers the choice of reference; the saved match stays until replaced.
        model.startOver()
        #expect(model.matchStage == .pick)
        #expect(store.brightnessMatch.calibration(for: dell) != nil)
    }
}

@MainActor @Test func arrowKeysSetTheHighlightedDisplayWhileComparing() async {
    await SetupFixture.withStore(adapter: FakeAdapter()) { store, _ in
        await store.refresh()
        let model = makeModel(store)
        model.step = .match
        let match = model.match
        // Before comparing they're left to the window.
        #expect(match?.handleArrowKey(124, shift: false) == false)
        model.startMatch()
        #expect(match?.handleArrowKey(124, shift: false) == true)
        #expect(match?.value(of: dell) == 41)
        #expect(match?.handleArrowKey(123, shift: true) == true)
        #expect(match?.value(of: dell) == 36)
        // Return and the rest stay the footer's.
        #expect(match?.handleArrowKey(36, shift: false) == false)
        model.cancel()
        await model.work?.value
    }
}

@MainActor @Test func theWindowRisesOnlyAbovePatchesOnTheScreens() {
    var changes: [Bool] = []
    let onScreens = SetupPatches(RecordingPatches()) { changes.append($0) }
    #expect(onScreens.showsOnScreens)
    onScreens.show([])
    onScreens.hide()
    #expect(changes == [true, false])
    changes = []
    let inWindow = SetupPatches(WindowOnlyPatches()) { changes.append($0) }
    #expect(!inWindow.showsOnScreens)
    inWindow.show([])
    #expect(changes.isEmpty)
}

// MARK: Permission

@MainActor @Test func grantIsWatchedOnlyOnTheFinish() {
    SetupFixture.withStore { store, _ in
        let model = makeModel(store)
        #expect(!model.isWatchingAccess)
        model.next()
        #expect(model.step == .displays && !model.isWatchingAccess)
        model.next()
        #expect(model.step == .match && !model.isWatchingAccess)
        model.next()
        #expect(model.step == .finish && model.isWatchingAccess)
        model.back()
        #expect(!model.isWatchingAccess)
        model.close()
    }
}

@MainActor @Test func nothingToWatchOnceAccessIsOn() {
    SetupFixture.withStore { store, _ in
        let model = makeModel(store, access: FakeAccess(granted: true))
        model.step = .finish
        #expect(model.accessGranted)
        #expect(!model.isWatchingAccess)
    }
}

@MainActor @Test func allowOpensMacOSsPromptAndWatches() {
    SetupFixture.withStore { store, _ in
        let access = FakeAccess()
        let model = makeModel(store, access: access)
        model.step = .finish
        #expect(!model.askedForAccess)
        model.requestAccess()
        #expect(access.requests == 1)
        #expect(model.askedForAccess)
        #expect(model.isWatchingAccess)
        #expect(!model.accessGranted)
        model.close()
    }
}

@MainActor @Test func grantIsNoticedWithinASecond() {
    SetupFixture.withStore { store, _ in
        let access = FakeAccess()
        let model = makeModel(store, access: access)
        model.step = .finish
        access.granted = true
        #expect(!model.accessGranted)
        SetupFixture.spin(seconds: 1.3)
        #expect(model.accessGranted)
        #expect(!model.isWatchingAccess)
    }
}

@MainActor @Test func grantGivenOnAnotherStepStillCounts() {
    SetupFixture.withStore { store, _ in
        let access = FakeAccess()
        let model = makeModel(store, access: access)
        model.step = .match
        #expect(!model.accessGranted)
        access.granted = true
        model.back()
        #expect(model.accessGranted)
    }
}

// MARK: Open at login

@MainActor @Test func openAtLoginIsOffWhereMacOSCantAddGlow() {
    SetupFixture.withStore { store, _ in
        let loginItem = LoginItem()
        // Tests run from a bare executable, as `swift run` does.
        #expect(!loginItem.canRegister)
        let model = SetupModel(store: store, login: .live(loginItem), tutorialOnly: false, permission: FakeAccess().permission)
        #expect(!model.openAtLogin)
    }
}

@MainActor @Test func openAtLoginIsOfferedTheFirstTimeAndSetOnFinish() {
    SetupFixture.withStore { store, _ in
        let login = FakeLogin(on: false)
        let model = makeModel(store, login: login)
        #expect(model.openAtLogin)
        model.step = .finish
        // Nothing changes until Start Using Glow.
        #expect(login.sets.isEmpty)
        model.primary()
        #expect(login.sets == [true])
    }
}

@MainActor @Test func openAtLoginIsSetOnlyWhenItDiffers() {
    SetupFixture.withStore { store, _ in
        // Already on, and left on.
        let kept = FakeLogin(on: true)
        makeModel(store, login: kept).finish()
        #expect(kept.sets.isEmpty)
        // On, and turned off.
        let turnedOff = FakeLogin(on: true)
        let model = makeModel(store, login: turnedOff)
        model.openAtLogin = false
        model.finish()
        #expect(turnedOff.sets == [false])
        // Off after setup was seen: it stays off unless chosen.
        store.settings.value.hasCompletedSetup = true
        let off = FakeLogin(on: false)
        let again = makeModel(store, login: off)
        #expect(!again.openAtLogin)
        again.finish()
        #expect(off.sets.isEmpty)
    }
}

// MARK: Your displays

@Test func yourDeskSaysWhatItCanShow() {
    let demo = DemoData.displays(generation: 0)
    #expect(YourDesk(displays: [], isReading: true).state == .reading)
    #expect(YourDesk(displays: []).state == .none)
    #expect(YourDesk(displays: demo, isDemo: true).state == .demo)
    #expect(YourDesk(displays: [demo[0]]).state == .builtInOnly)
    #expect(YourDesk(displays: demo).state == .ready)
    // Displays found while discovery is still going are shown.
    #expect(YourDesk(displays: [demo[0]], isReading: true).state == .builtInOnly)
}

@MainActor @Test func eachDisplaySaysHowGlowSetsItInPlainWords() {
    let states: [ControlStatus.State] = ControlRoute.allCases.map { .route($0) } + [.untested, .contradicted, .failed, .paused]
    let lines = states.map(SetupDisplayRow.howGlowSetsIt)
    #expect(Set(lines).count == states.count)
    for line in lines {
        #expect(!line.isEmpty)
        #expect(!line.contains("DDC") && !line.contains("VCP") && !line.contains("0x"))
    }
}
