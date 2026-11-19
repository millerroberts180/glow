import Testing
@testable import GlowApp

private let identity = GammaTable(red: [0, 0.5, 1], green: [0, 0.5, 1], blue: [0, 0.5, 1])
/// A calibrated table whose channels peak at different heights.
private let calibrated = GammaTable(red: [0, 0.45, 0.9], green: [0, 0.5, 1], blue: [0, 0.4, 0.8])

@Test func dimmingScalesEveryChannelByTheLevel() {
    #expect(identity.dimmed(to: 0.5) == GammaTable(red: [0, 0.25, 0.5], green: [0, 0.25, 0.5], blue: [0, 0.25, 0.5]))
}

@Test func theLevelReadsBackFromTheTable() throws {
    #expect(identity.dimmed(to: 0.5).level(relativeTo: identity) == 0.5)
    let level = try #require(calibrated.dimmed(to: 0.7).level(relativeTo: calibrated))
    #expect(abs(level - 0.7) < 0.0001)
    #expect(identity.level(relativeTo: identity) == 1)
}

@Test func dimmingNeverGoesBelowTheFloorOrAboveFull() throws {
    let floor = try #require(identity.dimmed(to: 0).level(relativeTo: identity))
    #expect(abs(floor - SoftwareDimmer.floor) < 0.0001)
    #expect(identity.dimmed(to: 3) == identity)
    #expect(SoftwareDimmer.clamped(.nan) == 1)
    #expect(SoftwareDimmer.clamped(-1) == SoftwareDimmer.floor)
}

@Test func aTableAnotherAppChangedHasNoLevel() {
    // Only red came down: not Glow's dimming, so Glow shows no value rather than a guess.
    let tinted = GammaTable(red: [0, 0.25, 0.5], green: [0, 0.5, 1], blue: [0, 0.5, 1])
    #expect(tinted.level(relativeTo: identity) == nil)
    #expect(GammaTable(red: [0, 1], green: [0, 1], blue: [0, 1]).level(relativeTo: identity) == nil)
}
