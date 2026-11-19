import Testing
@testable import GlowApp

@MainActor @Test func rightClickMenuHasRefreshSettingsAndQuit() {
    #expect(StatusMenuFixture.items(isDiscovering: false) == [
        .init(title: "Refresh Displays"),
        .init(title: "Settings…", shortcut: "⌘,"),
        .init(title: "—", acts: false),
        .init(title: "Quit Glow", shortcut: "⌘Q")
    ])
}

@MainActor @Test func refreshWaitsWhileDisplaysAreBeingRead() {
    let items = StatusMenuFixture.items(isDiscovering: true)
    #expect(items.first == .init(title: "Refresh Displays", isEnabled: false))
    #expect(items.dropFirst().allSatisfy { $0.isEnabled })
}

@Test func onlyARightClickOrControlClickOpensTheMenu() {
    // A plain left click is the popover's; the menu takes the press, never the release.
    #expect(StatusMenuFixture.clicksThatOpenMenu == ["right", "control-left"])
}
