import Testing
@testable import GlowApp

private let demo = DemoData.displays(generation: 1)
private let mac = demo[0]
private let dell = demo[1]
private let lg = demo[2]

/// Demo displays from a store that isn't in demo mode, so its scenes are the person's own;
/// writes to `refusing` fail, and every other write reads back as sent.
@MainActor private final class SceneAdapter: DisplayAdapter {
    let name = "Scene test"
    var displays: [DisplaySnapshot]
    var refusing: Set<CapabilityIdentifier>
    private(set) var written: [CapabilityIdentifier: CapabilityValue] = [:]
    init(displays: [DisplaySnapshot] = DemoData.displays(generation: 0), refusing: Set<CapabilityIdentifier> = []) {
        self.displays = displays
        self.refusing = refusing
    }
    func discover(generation: UInt64) async -> [DisplaySnapshot] {
        displays.map { display in
            var display = display
            display.connection = .init(displayID: display.connection.displayID, transport: display.connection.transport, generation: generation)
            return display
        }
    }
    func write(_ value: CapabilityValue, capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws {
        guard !refusing.contains(capability) else { throw ControlError.adapter("Refused") }
        written[capability] = value
    }
    func read(capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws -> CapabilityValue {
        guard let value = written[capability] else { throw ControlError.notWritable }
        return value
    }
}

private func value(_ id: CapabilityIdentifier, on display: DisplaySnapshot?) -> CapabilityValue? {
    display?.capabilities.first(where: { $0.id == id })?.currentValue
}

// MARK: - Capture

@Test func newSceneCapturesEverydayConfirmedValuesOnly() throws {
    var displays = demo
    // A value whose last read failed, and one still on its way, are never captured.
    let contrast = try #require(displays[1].capabilities.firstIndex(where: { $0.id == .contrast }))
    displays[1].capabilities[contrast].freshness = .stale
    let volume = try #require(displays[1].capabilities.firstIndex(where: { $0.id == .volume }))
    displays[1].capabilities[volume].pendingValue = .number(50)
    displays[1].capabilities[volume].lastConfirmedValue = nil

    let scene = GlowScene.capturing(displays, name: "Desk")
    let dellPart = try #require(scene.part(for: dell.id))
    #expect(dellPart.setting(.brightness)?.value == .number(68))
    #expect(dellPart.setting(.preset)?.value == .text("sRGB"))
    #expect(dellPart.setting(.contrast) == nil)
    #expect(dellPart.setting(.volume) == nil)
    // Input asks first and power is destructive: both stay out of a new scene.
    #expect(dellPart.setting(.input) == nil)
    #expect(dellPart.setting(.power) == nil)
    // Read-only settings aren't values a scene can set.
    let macPart = try #require(scene.part(for: mac.id))
    #expect(macPart.settings.map(\.capability) == [.brightness])
    #expect(macPart.name == "MacBook Pro")
    // Software dimming is a setting Glow can change, so it's captured; LG volume isn't.
    let lgPart = try #require(scene.part(for: lg.id))
    #expect(lgPart.settings.map(\.capability) == [.brightness])
    #expect(scene.isCurrent(on: displays))
}

@Test func captureLeavesOutDisconnectedDisplays() {
    var displays = demo
    displays[2].isConnected = false
    #expect(GlowScene.capturing(displays, name: "Desk").part(for: lg.id) == nil)
}

// MARK: - Apply

@MainActor @Test func applyReportsPartialFailureExactly() async {
    let scene = GlowScene(id: "s", name: "S", symbol: "sun.max", values: [dell.id: [.brightness: .number(40), .contrast: .number(60), .volume: .number(20)]], on: demo)
    let plan = scene.plan(on: demo)
    #expect(plan.writes.map(\.capability) == [.brightness, .contrast, .volume])
    let result = await SceneApplier.apply(plan, includingAsksFirst: false) { write in
        if write.capability == .volume { throw ControlError.readBackMismatch }
    }
    #expect(result == SceneResult(succeeded: 2, failed: 1))
    #expect(result.summary == "Applied 2; 1 couldn’t be updated")
    #expect(result.tone == .warning)
}

@MainActor @Test func storeAppliesThroughThePipelineAndRollsBackWhatFails() async {
    await SceneFixture.withSuite { defaults in
        let adapter = SceneAdapter(refusing: [.volume])
        let store = GlowStore(settings: GlowSettingsStore(defaults: defaults), demoDisplays: false, adapter: adapter)
        await store.refresh()
        let scene = GlowScene(id: "s", name: "S", symbol: "sun.max", values: [dell.id: [.brightness: .number(40), .volume: .number(20)]], on: store.displays)
        let result = await store.applyScene(scene)
        #expect(result.summary == "Applied 1; 1 couldn’t be updated")
        #expect(store.sceneState.results["s"] == result)
        #expect(store.lastMessage == result.summary)
        let live = store.displays.first(where: { $0.id == dell.id })
        #expect(value(.brightness, on: live) == .number(40))
        // The refused write is never shown as if it took.
        #expect(value(.volume, on: live) == .number(35))
        #expect(adapter.written[.volume] == nil)
    }
}

@Test func settingsADisplayDoesNotSupportAreSkipped() {
    // LG volume is unavailable on its connection, the MacBook has no contrast, and the
    // Dell's power is destructive (and refused in testing): none is ever sent.
    let scene = GlowScene(id: "x", name: "X", symbol: "sparkles", values: [
        lg.id: [.volume: .number(30)], mac.id: [.contrast: .number(50)], dell.id: [.power: .text("Off")]
    ], on: demo)
    let plan = scene.plan(on: demo)
    #expect(plan.writes.isEmpty)
    #expect(plan.skipped == 3)
    let result = SceneResult(succeeded: 0, failed: 0, skipped: plan.skipped)
    #expect(result.summary == "Nothing to change on the displays connected now")
    #expect(result.detail == "3 skipped: not on this connection")
}

@Test func outOfRangeValuesAreSnappedNotGuessed() {
    let scene = GlowScene(id: "x", name: "X", symbol: "sparkles", values: [dell.id: [.brightness: .number(140), .preset: .text("Vivid 9000")]], on: demo)
    let plan = scene.plan(on: demo)
    #expect(plan.writes.map(\.value) == [.number(100)])
    #expect(plan.skipped == 1)
}

@MainActor @Test func aSceneWhoseDisplaysAreAllAwaySaysSo() async {
    let away = PersistentDisplayIdentity(vendorID: 1, productID: 2, serialNumber: 3)
    let scene = GlowScene(id: "a", name: "Away", symbol: "moon", displays: [
        SceneDisplay(identity: away, name: "Studio Display", settings: [SceneSetting(.brightness, .number(50), describedBy: nil)])
    ])
    let result = await SceneApplier.apply(scene.plan(on: demo), includingAsksFirst: false) { _ in Issue.record("Nothing should be written") }
    #expect(result.summary == "None of this scene’s displays are connected")
    #expect(result.detail == nil)
    #expect(!scene.isCurrent(on: demo))

    let mixed = GlowScene(id: "m", name: "Mixed", symbol: "moon", displays: scene.displays + [
        SceneDisplay(identity: dell.id, name: dell.name, settings: [SceneSetting(.brightness, .number(50), describedBy: nil)])
    ])
    let partly = await SceneApplier.apply(mixed.plan(on: demo), includingAsksFirst: false) { _ in }
    #expect(partly.summary == "Applied to 1 setting")
    #expect(partly.detail == "1 display isn’t connected")
}

@MainActor @Test func inputAsksFirstGoesLastAndCanBeLeftAsItIs() async {
    let scene = GlowScene(id: "p", name: "Present", symbol: "play.rectangle", values: [dell.id: [.input: .text("HDMI 1"), .brightness: .number(85)]], on: demo)
    let plan = scene.plan(on: demo)
    #expect(plan.writes.map(\.capability) == [.brightness, .input])
    #expect(plan.confirmations.map(\.descriptor.id) == [.input])
    let confirmation = SceneConfirmation(scene: scene, changes: plan.confirmations)
    #expect(confirmation.title == "Switch your Dell U2723QE to HDMI 1?")
    #expect(confirmation.confirmTitle == "Switch to HDMI 1")
    #expect(confirmation.declineTitle == "Leave Input As It Is")

    var sent: [CapabilityIdentifier] = []
    let declined = await SceneApplier.apply(plan, includingAsksFirst: false) { sent.append($0.capability) }
    #expect(sent == [.brightness])
    #expect(declined.heldBack == 1)
    #expect(declined.detail == "1 left as it was")
    let accepted = await SceneApplier.apply(plan, includingAsksFirst: true) { sent.append($0.capability) }
    #expect(sent == [.brightness, .brightness, .input])
    #expect(accepted.summary == "Applied to 2 settings")
}

@Test func anInputAlreadySetNeedsNoQuestion() {
    let scene = GlowScene(id: "u", name: "Same", symbol: "circle", values: [dell.id: [.input: .text("USB-C"), .brightness: .number(40)]], on: demo)
    let plan = scene.plan(on: demo)
    #expect(plan.confirmations.isEmpty)
    #expect(plan.alreadySet == 1)
}

// MARK: - Saving

@Test func settingsWithoutScenesDecodeToAnEmptyLibrary() throws {
    let settings = try SettingsFixture.decode(#"{"fineAdjustment": false}"#)
    #expect(settings.sceneLibrary == SceneLibrary())
    #expect(settings.reapplyAfterWake == false)
}

@Test func aDamagedSceneOrSettingCostsOnlyItself() throws {
    let json = #"""
    {"showOverlayOnChange": false, "reapplyAfterWake": true, "scenes": {"version": 1, "scenes": [
      {"id": "a", "displays": [{"identity": {"vendorID": 4268, "productID": 41200, "serialNumber": 783245},
        "settings": [{"capability": "brightness", "value": {"number": {"_0": 40}}}, {"capability": "contrast"}, 7]}]},
      {"name": "No ID"},
      {"id": "b", "name": "Night", "symbol": "moon", "displays": "lots"}
    ]}}
    """#
    let settings = try SettingsFixture.decode(json)
    #expect(settings.showOverlayOnChange == false)
    #expect(settings.reapplyAfterWake == true)
    let scenes = settings.sceneLibrary.scenes
    #expect(scenes.map(\.id) == ["a", "b"])
    #expect(scenes[0].name == "Scene")
    #expect(scenes[0].symbol == SceneSymbol.fallback)
    #expect(scenes[0].displays.first?.name == "A display")
    #expect(scenes[0].displays.first?.settings.map(\.capability) == [.brightness])
    #expect(scenes[0].displays.first?.settings.first?.label == "Brightness")
    #expect(scenes[1].displays.isEmpty)
}

@Test func anUnreadableLibraryLeavesTheOtherSettings() throws {
    let settings = try SettingsFixture.decode(#"{"scenes": 7, "fineAdjustment": false}"#)
    #expect(settings.sceneLibrary.scenes.isEmpty)
    #expect(settings.fineAdjustment == false)
}

@Test func aLibraryFromANewerGlowIsReadAndSavedAsThisVersion() throws {
    let settings = try SettingsFixture.decode(#"{"scenes": {"version": 9, "future": true, "scenes": [{"id": "z", "name": "Z", "symbol": "film", "displays": [], "lighting": "warm"}]}}"#)
    #expect(settings.sceneLibrary.version == 9)
    #expect(settings.sceneLibrary.scenes.map(\.name) == ["Z"])
    let saved = try SettingsFixture.roundTrip(settings)
    #expect(saved.sceneLibrary.version == SceneLibrary.currentVersion)
    #expect(saved.sceneLibrary.scenes == settings.sceneLibrary.scenes)
}

@Test func scenesRoundTripThroughSettings() throws {
    var settings = GlowSettings()
    settings.sceneLibrary.scenes = [GlowScene.capturing(demo, name: "Desk")]
    settings.reapplyAfterWake = true
    #expect(try SettingsFixture.roundTrip(settings) == settings)
}

// MARK: - Demo and real

@MainActor @Test func demoExamplesNeverMixWithRealScenes() async throws {
    try await SceneFixture.withSuite { defaults in
        let settings = GlowSettingsStore(defaults: defaults)
        let real = GlowStore(settings: settings, demoDisplays: false, adapter: SceneAdapter())
        #expect(real.scenes.isEmpty)
        await real.refresh()
        let captured = real.newSceneFromCurrentSettings()
        #expect(captured.name == "New Scene")
        real.saveScene(captured)
        #expect(real.newSceneFromCurrentSettings().name == "New Scene 2")
        let saved = try SceneFixture.savedLibrary(settings)
        #expect(saved.scenes.map(\.id) == [captured.id])

        let demoStore = GlowStore(settings: settings, demoDisplays: true)
        #expect(demoStore.scenes.map(\.id) == ["demo-work", "demo-night", "demo-presentation"])
        demoStore.saveScene(GlowScene(id: "demo-extra", name: "Extra", symbol: "film", displays: []))
        demoStore.deleteScene(id: captured.id)
        // Editing demo examples stays in memory; the person's library is untouched.
        let after = try SceneFixture.savedLibrary(settings)
        #expect(after.scenes.map(\.id) == [captured.id])
        #expect(!demoStore.scenes.contains(where: { $0.id == captured.id }))
    }
}

@Test func demoExamplesMatchTheDemoDisplays() {
    for scene in DemoScenes.examples {
        #expect(scene.plan(on: demo).skipped == 0, "\(scene.name) has a setting the demo can’t apply")
    }
}

@MainActor @Test func scenesReorderAndDelete() async {
    await SceneFixture.withSuite { defaults in
        let store = GlowStore(settings: GlowSettingsStore(defaults: defaults), demoDisplays: false, adapter: SceneAdapter())
        for name in ["A", "B", "C"] { store.saveScene(GlowScene(id: name, name: " \(name) ", symbol: "film", displays: [])) }
        #expect(store.scenes.map(\.name) == ["A", "B", "C"])
        store.moveScene(id: "C", by: -1)
        store.moveScene(id: "A", by: -1)
        #expect(store.scenes.map(\.id) == ["A", "C", "B"])
        store.deleteScene(id: "C")
        #expect(store.scenes.map(\.id) == ["A", "B"])
    }
}

// MARK: - Active, restore and wake

@MainActor @Test func theActiveSceneIsWhatTheDisplaysShow() async throws {
    let store = GlowStore(demoDisplays: true)
    await store.refresh()
    #expect(store.activeScene?.id == "demo-work")
    let night = try #require(store.scenes.first(where: { $0.id == "demo-night" }))
    let result = await store.applyScene(night)
    #expect(result.summary == "Applied to 3 settings")
    #expect(store.activeScene?.id == "demo-night")
}

@MainActor @Test func restoreStartingValuesPutsBackWhatWasReadAtLaunch() async throws {
    let store = GlowStore(demoDisplays: true)
    await store.refresh()
    let dellNow = try #require(store.displays.first(where: { $0.id == dell.id }))
    #expect(store.startingScene(for: dellNow).settingCount == 0)
    #expect(store.startingValues(for: dell.id)[.power] == nil)
    #expect(store.startingValues(for: dell.id)[.brightness] == .number(68))

    let night = try #require(store.scenes.first(where: { $0.id == "demo-night" }))
    await store.applyScene(night)
    let changed = try #require(store.displays.first(where: { $0.id == dell.id }))
    #expect(store.startingScene(for: changed).settingCount == 3)
    let result = await store.restoreStartingValues(of: changed)
    #expect(result.summary(done: "Restored") == "Restored 3 settings")
    #expect(store.sceneState.restoreResults[dell.id] == result)
    let restored = store.displays.first(where: { $0.id == dell.id })
    #expect(value(.brightness, on: restored) == .number(68))
    #expect(value(.volume, on: restored) == .number(35))
    #expect(value(.preset, on: restored) == .text("sRGB"))
}

@MainActor @Test func restoreComparesWithTheDisplayAsItIsNow() async throws {
    let store = GlowStore(demoDisplays: true)
    await store.refresh()
    // A snapshot from before the change, as a button drawn earlier would hold.
    let before = try #require(store.displays.first(where: { $0.id == dell.id }))
    let night = try #require(store.scenes.first(where: { $0.id == "demo-night" }))
    await store.applyScene(night)
    let result = await store.restoreStartingValues(of: before)
    #expect(result.summary(done: "Restored") == "Restored 3 settings")
    #expect(value(.brightness, on: store.displays.first(where: { $0.id == dell.id })) == .number(68))
}

@MainActor @Test func reapplyAfterWakeIsOptInAndPutsBackWhatAScreenForgot() async {
    await SceneFixture.withSuite { defaults in
        let store = GlowStore(settings: GlowSettingsStore(defaults: defaults), demoDisplays: true)
        await store.refresh()
        guard let night = store.scenes.first(where: { $0.id == "demo-night" }) else {
            Issue.record("No Night example")
            return
        }
        await store.applyScene(night)
        // The demo adapter reads its starting values again on every discovery, as a
        // display that forgot over sleep would.
        await store.refresh()
        #expect(value(.brightness, on: store.displays.first(where: { $0.id == dell.id })) == .number(68))
        #expect(await store.reapplyAfterWakeIfChosen() == nil)

        store.reapplyAfterWake = true
        let result = await store.reapplyAfterWakeIfChosen()
        #expect(result?.succeeded == 3)
        #expect(store.lastMessage == "After wake: Reapplied 3 settings")
        let dellNow = store.displays.first(where: { $0.id == dell.id })
        #expect(value(.brightness, on: dellNow) == .number(28))
        #expect(value(.preset, on: dellNow) == .text("5000 K"))
        // Nothing left to put back the second time.
        #expect(await store.reapplyAfterWakeIfChosen() == nil)
    }
}

@MainActor @Test func reapplyAfterWakeNeverSwitchesAnInput() async {
    await SceneFixture.withSuite { defaults in
        let store = GlowStore(settings: GlowSettingsStore(defaults: defaults), demoDisplays: true)
        store.reapplyAfterWake = true
        await store.refresh()
        guard let presentation = store.scenes.first(where: { $0.id == "demo-presentation" }) else {
            Issue.record("No Presentation example")
            return
        }
        await store.applyScene(presentation, includingAsksFirst: true)
        #expect(value(.input, on: store.displays.first(where: { $0.id == dell.id })) == .text("HDMI 1"))
        await store.refresh()
        let result = await store.reapplyAfterWakeIfChosen()
        #expect(result?.succeeded == 1)
        #expect(value(.input, on: store.displays.first(where: { $0.id == dell.id })) == .text("USB-C"))
    }
}

// MARK: - Naming

@Test func aNewSceneTakesItsNameFromTheSymbol() {
    var scene = GlowScene.capturing(demo, name: "New Scene 2")
    let defaultName = GlowScene.defaultName(startingFrom: scene.name, isNew: true)
    scene.wear("moon", defaultName: defaultName)
    #expect(scene.name == "Night")
    scene.wear("briefcase", defaultName: defaultName)
    #expect(scene.name == "Work")
    // Other names nothing, so the scene goes back to the name Glow gave it.
    scene.wear(SceneSymbol.fallback, defaultName: defaultName)
    #expect(scene.name == "New Scene 2")
    #expect(scene.symbol == SceneSymbol.fallback)
}

@Test func aTypedNameStaysAndAClearedOneFollowsAgain() {
    var scene = GlowScene.capturing(demo, name: "New Scene")
    let defaultName = GlowScene.defaultName(startingFrom: scene.name, isNew: true)
    scene.name = "Desk"
    scene.wear("moon", defaultName: defaultName)
    #expect(scene.name == "Desk")
    #expect(scene.symbol == "moon")
    scene.name = " "
    scene.wear("book", defaultName: defaultName)
    #expect(scene.name == "Read")
}

@Test func aSavedSceneFollowsOnlyWhileItsNameIsItsSymbols() {
    var night = GlowScene(name: "Night", symbol: "moon", displays: [])
    let nightDefault = GlowScene.defaultName(startingFrom: night.name, isNew: false)
    night.wear("briefcase", defaultName: nightDefault)
    #expect(night.name == "Work")
    night.wear(SceneSymbol.fallback, defaultName: nightDefault)
    #expect(night.name == "New Scene")

    var talk = GlowScene(name: "Presentation", symbol: "play.rectangle", displays: [])
    talk.wear("film", defaultName: GlowScene.defaultName(startingFrom: talk.name, isNew: false))
    #expect(talk.name == "Presentation")
    #expect(talk.symbol == "film")
}

@Test func onlyGlowsOwnNewSceneNamesCountAsDefaults() {
    #expect(GlowScene.isNewSceneName("New Scene"))
    #expect(GlowScene.isNewSceneName("New Scene 3"))
    #expect(!GlowScene.isNewSceneName("New Scene 100"))
    #expect(!GlowScene.isNewSceneName("New Scenery"))
    #expect(GlowScene.defaultName(startingFrom: "New Scene 4", isNew: false) == "New Scene 4")
}
