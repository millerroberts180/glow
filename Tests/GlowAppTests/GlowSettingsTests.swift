import Testing
@testable import GlowApp

private func decode(_ json: String) throws -> GlowSettings {
    try SettingsFixture.decode(json)
}

@Test func oldPartialSettingsBlobKeepsEveryOtherDefault() throws {
    let settings = try decode(#"{"fineAdjustment": false}"#)
    var expected = GlowSettings()
    expected.fineAdjustment = false
    #expect(settings == expected)
}

@Test func emptySettingsBlobDecodesToDefaults() throws {
    #expect(try decode("{}") == GlowSettings())
}

@Test func unknownEnumValuesFallBackWithoutResettingTheRest() throws {
    let settings = try decode(#"{"controlTarget": "everywhere", "lastPane": "tutorial", "matchMethod": "lab", "showOverlayOnChange": false, "focusedDisplay": 7}"#)
    #expect(settings.controlTarget == .all)
    #expect(settings.lastPane == .displays)
    #expect(settings.matchMethod == .quick)
    #expect(settings.focusedDisplay == nil)
    #expect(settings.showOverlayOnChange == false)
}

@Test func settingsRoundTripThroughJSON() throws {
    var settings = GlowSettings()
    settings.useDemoDisplays = false
    settings.controlTarget = .focused
    settings.focusedDisplay = DemoData.displays(generation: 1)[1].id
    settings.matchMethod = .guided
    settings.lastPane = .connection
    #expect(try SettingsFixture.roundTrip(settings) == settings)
}

@MainActor @Test func settingsStoreSavesUnderVersionedKeyAndReadsBack() {
    SettingsFixture.withSuite { defaults in
        let store = GlowSettingsStore(defaults: defaults)
        store.value.controlTarget = .macOnly
        store.value.lastPane = .scenes
        store.flush()
        #expect(SettingsFixture.hasSavedSettings(defaults))
        let reopened = GlowSettingsStore(defaults: defaults)
        #expect(reopened.value.controlTarget == .macOnly)
        #expect(reopened.value.lastPane == .scenes)
    }
}

@MainActor @Test func unreadableSettingsFallBackToDefaults() {
    SettingsFixture.withSuite { defaults in
        SettingsFixture.saveUnreadableSettings(defaults)
        #expect(GlowSettingsStore(defaults: defaults).value == GlowSettings())
    }
}

@MainActor @Test func storeSettingsWiringReachesSavedSettings() {
    SettingsFixture.withSuite { defaults in
        let settings = GlowSettingsStore(defaults: defaults)
        let store = GlowStore(settings: settings)
        store.controlTarget = .underCursor
        store.showOverlayOnChange = false
        store.matchMethod = .guided
        store.selectedPane = .controls
        #expect(settings.value.controlTarget == .underCursor)
        #expect(settings.value.showOverlayOnChange == false)
        #expect(settings.value.matchMethod == .guided)
        #expect(settings.value.lastPane == .controls)
    }
}

@MainActor @Test func inputConfirmationNamesTheDisplayAndTheConsequence() throws {
    let dell = try #require(DemoData.displays(generation: 1).first(where: { $0.name == "Dell U2723QE" }))
    let input = try #require(dell.capabilities.first(where: { $0.id == .input }))
    #expect(input.requiresConfirmation)
    let change = PendingChange(display: dell, descriptor: input, value: .text("HDMI 1"))
    #expect(change.title == "Switch your Dell U2723QE to HDMI 1?")
    #expect(change.message.contains("Your Dell U2723QE may go blank until it finds a signal on HDMI 1"))
    #expect(change.confirmTitle == "Switch to HDMI 1")
}

@Test func sceneAsksFirstOnlyWhenItWouldChangeAnInput() throws {
    let displays = DemoData.displays(generation: 1)
    let dell = try #require(displays.first(where: { $0.name == "Dell U2723QE" }))
    let unchanged = GlowScene(id: "same", name: "Same", symbol: "circle", values: [dell.id: [.input: .text("USB-C"), .brightness: .number(40)]], on: displays)
    let switching = GlowScene(id: "switch", name: "Switch", symbol: "circle", values: [dell.id: [.input: .text("HDMI 1")]], on: displays)
    #expect(unchanged.plan(on: displays).confirmations.isEmpty)
    #expect(switching.plan(on: displays).confirmations.map(\.descriptor.id) == [.input])
}

@MainActor @Test func slidersLandOnTheSettingsSteps() {
    let descriptor = DemoData.descriptor(.brightness, "Brightness", .essentials, .range(minimum: 10, maximum: 90, step: 5), .number(50), .hardware)
    var proposed: [CapabilityValue] = []
    let binding = descriptor.sliderValue(minimum: 10, step: 5) { proposed.append($0) }
    binding.wrappedValue = 17.4
    binding.wrappedValue = 51
    #expect(proposed == [.number(15)])
}

@Test func freshInstallsUseRealDisplays() {
    #expect(GlowSettings().useDemoDisplays == false)
}

@Test func oldInstallsThatSavedDemoAsTheDefaultMoveToRealDisplaysOnce() throws {
    // Builds before real hardware saved `true` without anyone choosing it.
    let migrated = try decode(#"{"useDemoDisplays": true, "fineAdjustment": false}"#)
    #expect(migrated.useDemoDisplays == false)
    #expect(migrated.fineAdjustment == false)
    #expect(migrated.choseDemoDisplays == false)
}

@Test func aChosenDemoStaysChosen() throws {
    let chosen = try decode(#"{"useDemoDisplays": true, "choseDemoDisplays": true}"#)
    #expect(chosen.useDemoDisplays)
    var settings = GlowSettings()
    settings.useDemoDisplays = true
    settings.choseDemoDisplays = true
    #expect(try SettingsFixture.roundTrip(settings) == settings)
}

@MainActor @Test func turningOnDemoDisplaysRecordsTheChoice() {
    SettingsFixture.withSuite { defaults in
        let settings = GlowSettingsStore(defaults: defaults)
        let store = GlowStore(settings: settings, demoDisplays: true)
        store.setDemoMode(true)
        settings.flush()
        let reopened = GlowSettingsStore(defaults: defaults)
        #expect(reopened.value.useDemoDisplays)
        #expect(reopened.value.choseDemoDisplays)
    }
}

@Test func settingsLeftOnTheRemovedLicensePaneOpenOnDisplays() throws {
    let settings = try decode(#"{"lastPane": "license", "fineAdjustment": true}"#)
    #expect(settings.lastPane == .displays)
    #expect(settings.fineAdjustment)
}

@MainActor @Test func theTrialsLeftoversGoAndGlowsSettingsStay() {
    #expect(SettingsFixture.keysLeftAfterTrialCleanup() == [GlowSettingsStore.key])
}
