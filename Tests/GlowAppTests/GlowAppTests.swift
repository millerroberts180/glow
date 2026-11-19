import Testing
@testable import GlowApp

@Test func rangeMapsToSliderWhenSafelyEditable() {
    let descriptor = DemoData.descriptor(.brightness, "Brightness", .essentials, .range(minimum: 0, maximum: 100, step: 1), .number(50), .hardware)
    #expect(CapabilityRenderer.style(for: descriptor) == .slider)
}

@Test func arbitraryNonBrightnessCapabilityMapsWithoutBespokeUI() {
    let descriptor = DemoData.descriptor("vendor-overdrive", "Pixel response", .display, .options(["Normal", "Fast"]), .text("Normal"), .hardware)
    #expect(CapabilityRenderer.style(for: descriptor) == .picker)
}

@Test func readOnlyContradictoryAndUnavailableCapabilitiesAreSafe() {
    let readOnly = DemoData.descriptor(.hdr, "HDR", .display, .toggle, .boolean(true), .native, access: .readOnly)
    let contradictory = DemoData.descriptor(.power, "Power", .display, .toggle, .boolean(true), .hardware, evidence: .contradictory)
    let unavailable = DemoData.descriptor(.power, "Power", .display, .toggle, nil, .unavailable, access: .unavailable, evidence: .unavailable)
    #expect(CapabilityRenderer.style(for: readOnly) == .readOnly)
    #expect(CapabilityRenderer.style(for: contradictory) == .readOnly)
    #expect(!contradictory.isSafelyEditable)
    #expect(CapabilityRenderer.style(for: unavailable) == .unavailable)
}

@Test func rangeValidationClampsAndSnaps() throws {
    let descriptor = DemoData.descriptor(.brightness, "Brightness", .essentials, .range(minimum: 10, maximum: 90, step: 5), .number(50), .hardware)
    #expect(try descriptor.validated(.number(93)) == .number(90))
    #expect(try descriptor.validated(.number(17)) == .number(15))
}

@Test func rangeValidationRejectsInvalidStepsAndNonFiniteValues() {
    let zeroStep = DemoData.descriptor(.brightness, "Brightness", .essentials, .range(minimum: 0, maximum: 100, step: 0), .number(50), .hardware)
    let nanValue = DemoData.descriptor(.brightness, "Brightness", .essentials, .range(minimum: 0, maximum: 100, step: 1), .number(50), .hardware)
    #expect(throws: ControlError.invalidValue) { try zeroStep.validated(.number(50)) }
    #expect(throws: ControlError.invalidValue) { try nanValue.validated(.number(.nan)) }
}

@Test func demoReliabilityStartsWithoutInventedWriteHistory() {
    let descriptor = DemoData.displays(generation: 1)[1].capabilities[0]
    #expect(descriptor.reliability.successfulWrites == 0)
    #expect(descriptor.reliability.failedWrites == 0)
    #expect(descriptor.reliability.summary == "Not yet tested")
    #expect(descriptor.reliability.provenance.contains("no physical connection test"))
}

@Test func enumValidationRejectsUnsupportedValue() {
    let descriptor = DemoData.descriptor(.input, "Input", .display, .options(["USB-C", "HDMI"]), .text("USB-C"), .hardware)
    #expect(throws: ControlError.invalidValue) { try descriptor.validated(.text("VGA")) }
}

@Test func missingCurrentValueRemainsRepresentable() {
    let descriptor = DemoData.descriptor("vendor-unknown", "Vendor feature", .connectivity, .text, nil, .native, access: .readOnly, evidence: .reportedOnly)
    #expect(descriptor.currentValue == nil)
    #expect(CapabilityRenderer.style(for: descriptor) == .readOnly)
}

@Test func calibrationCurveIsMonotonicAndBounded() {
    let curve = BrightnessCurve(points: [.init(reference: 0.8, display: 0.7), .init(reference: 0.2, display: 0.4), .init(reference: 0.5, display: 0.3), .init(reference: 1.2, display: 1.3)])
    #expect(curve.points.map(\.display) == [0.4, 0.4, 0.7, 1.0])
    #expect(curve.value(for: 0.7) >= curve.value(for: 0.3))
    #expect(curve.value(for: 2) <= 1)
}

@Test @MainActor func confirmedWriteReturnsReadBack() async throws {
    let adapter = PipelineAdapter(readBack: .number(65))
    let pipeline = DisplayWritePipeline()
    let display = DemoData.displays(generation: 4)[1]
    await pipeline.setTopologyGeneration(4)
    let descriptor = try #require(display.capabilities.first(where: { $0.id == .brightness }))
    let result = try await pipeline.write(descriptor: descriptor, value: .number(65), display: display, adapter: adapter)
    #expect(result == .number(65))
    #expect(adapter.writeCount == 1)
}

@Test @MainActor func readBackMismatchRetriesThenFails() async throws {
    let adapter = PipelineAdapter(readBack: .number(64))
    let pipeline = DisplayWritePipeline()
    let display = DemoData.displays(generation: 2)[1]
    await pipeline.setTopologyGeneration(2)
    let descriptor = try #require(display.capabilities.first(where: { $0.id == .brightness }))
    await #expect(throws: ControlError.readBackMismatch) { _ = try await pipeline.write(descriptor: descriptor, value: .number(65), display: display, adapter: adapter) }
    #expect(adapter.writeCount == 2)
}

@Test @MainActor func staleConnectionIsRejectedBeforeWrite() async throws {
    let adapter = PipelineAdapter(readBack: .number(65))
    let pipeline = DisplayWritePipeline()
    let display = DemoData.displays(generation: 1)[1]
    await pipeline.setTopologyGeneration(2)
    let descriptor = try #require(display.capabilities.first(where: { $0.id == .brightness }))
    await #expect(throws: ControlError.staleTopology) { _ = try await pipeline.write(descriptor: descriptor, value: .number(65), display: display, adapter: adapter) }
    #expect(adapter.writeCount == 0)
}

@Test @MainActor func diagnosticReportRedactsSerial() async {
    // Demo displays, so the test never reaches this Mac's real hardware.
    let store = GlowStore(demoDisplays: true)
    await store.start()
    let report = store.diagnosticReport()
    #expect(report.contains("serial [redacted]"))
    #expect(!report.contains("783245"))
}

@Test func partialSceneSummaryIsExplicit() {
    #expect(SceneResult(succeeded: 3, failed: 2).summary == "Applied 3; 2 couldn’t be updated")
    #expect(SceneResult(succeeded: 3, failed: 0).summary == "Applied to 3 settings")
}

@Test @MainActor func persistentAndActiveConnectionIdentitiesStaySeparate() {
    let display = DemoData.displays(generation: 1)[1]
    var reconnected = display
    reconnected.connection = .init(displayID: 9, transport: "HDMI", generation: 2)
    #expect(display.identity == reconnected.identity)
    #expect(display.connection != reconnected.connection)
}

@Test @MainActor func duplicatePersistentIdentityDoesNotConflateConnections() {
    let display = DemoData.displays(generation: 1)[1]
    var duplicateConnection = display
    duplicateConnection.connection = .init(displayID: 3, transport: "DisplayPort", generation: 1)
    #expect(Set([display.identity, duplicateConnection.identity]).count == 1)
    #expect(Set([display.connection, duplicateConnection.connection]).count == 2)
}

@Test func settingsPanesAreNamedPlainly() {
    #expect(GlowSettingsPane.connection.title == "Connection")
    #expect(GlowSettingsPane.about.title == "Glow")
    // Saved as the pane Settings reopens on, so the raw values never change.
    #expect(GlowSettingsPane(rawValue: "connection") == .connection)
}

@Test func theGlowPaneSaysWhichVersionThisIs() {
    #expect(AboutPane.version(from: nil) == "Development build")
    #expect(AboutPane.version(from: ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1"]) == "Version 0.1.0 (1)")
    #expect(AboutPane.version(from: ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "1.0"]) == "Version 1.0")
}

@Test func theSupportLinkNamesTheAddressThenThePageThenThePlaceholder() {
    let issues = "https://github.com/millerroberts180/glow/issues"
    #expect(ReleaseInfo.supportTitle(email: "help@example.com", url: .init(string: issues)) == "help@example.com")
    #expect(ReleaseInfo.supportTitle(email: nil, url: .init(string: issues)) == "github.com")
    #expect(ReleaseInfo.supportTitle(email: nil, url: nil) == "support@glow.example")
}

@MainActor private final class PipelineAdapter: DisplayAdapter {
    let name = "Pipeline test"
    var readBack: CapabilityValue
    var writeCount = 0
    init(readBack: CapabilityValue) { self.readBack = readBack }
    func discover(generation: UInt64) async -> [DisplaySnapshot] { DemoData.displays(generation: generation) }
    func write(_ value: CapabilityValue, capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws { writeCount += 1 }
    func read(capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws -> CapabilityValue { readBack }
}
