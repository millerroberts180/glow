import Testing
@testable import GlowApp

// Discovery that shows its work: every display appears at once, an external one as being
// checked, and each takes its place as its own probe finishes, so a slow or silent monitor
// holds up no other display.

/// Shows the demo displays at once with the external ones still being checked, then waits
/// for the test to let those checks finish. Each discovery waits on its own.
@MainActor private final class SteppedAdapter: DisplayAdapter {
    let name = "Stepped discovery"
    private var checks: [CheckedContinuation<Void, Never>] = []
    var waiting: Int { checks.count }

    func discover(generation: UInt64) async -> [DisplaySnapshot] {
        await discover(generation: generation) { _ in }
    }

    func discover(generation: UInt64, progress: @escaping @MainActor @Sendable ([DisplaySnapshot]) -> Void) async -> [DisplaySnapshot] {
        let finished = DemoData.displays(generation: generation)
        progress(finished.map { display in
            guard !display.isBuiltIn else { return display }
            var checking = display
            checking.capabilities = []
            checking.isChecking = true
            return checking
        })
        await withCheckedContinuation { checks.append($0) }
        progress(finished)
        return finished
    }

    /// Lets the oldest discovery that's waiting finish.
    func finishOldest() {
        guard !checks.isEmpty else { return }
        checks.removeFirst().resume()
    }

    func write(_ value: CapabilityValue, capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws {}
    func read(capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws -> CapabilityValue { .number(50) }
}

@MainActor private func until(_ condition: () -> Bool) async {
    while !condition() { await Task.yield() }
}

@MainActor @Test func everyDisplayShowsWhileTheMonitorsAreStillBeingChecked() async {
    let adapter = SteppedAdapter()
    await MatchFixture.withStore(adapter: adapter) { store in
        let refresh = Task { await store.refresh() }
        await until { adapter.waiting == 1 }
        #expect(store.isDiscovering)
        #expect(store.displays.map(\.name) == DemoData.displays(generation: 1).map(\.name))
        let builtIn = store.displays.first(where: \.isBuiltIn)
        #expect(builtIn?.isChecking == false && builtIn?.brightnessSetting != nil)
        let monitors = store.displays.filter { !$0.isBuiltIn }
        #expect(!monitors.isEmpty && monitors.allSatisfy { $0.isChecking && $0.capabilities.isEmpty })
        #expect(monitors.allSatisfy { $0.summaryStatus(isPaused: false) == .checking })
        #expect(monitors.allSatisfy { $0.summaryStatus(isPaused: true) == .paused })
        // The saved choices already find their displays.
        #expect(store.focusedDisplayID == monitors.first?.id)
        #expect(store.selectedDisplayID == store.displays.first?.id)

        adapter.finishOldest()
        await refresh.value
        #expect(!store.isDiscovering)
        #expect(store.displays.allSatisfy { !$0.isChecking })
        #expect(store.displays.filter { !$0.isBuiltIn }.allSatisfy { !$0.capabilities.isEmpty })
    }
}

@MainActor @Test func aRefreshKeepsShowingAMonitorUntilItsOwnCheckFinishes() async {
    let adapter = SteppedAdapter()
    await MatchFixture.withStore(adapter: adapter) { store in
        let first = Task { await store.refresh() }
        await until { adapter.waiting == 1 }
        adapter.finishOldest()
        await first.value
        let before = store.displays

        let second = Task { await store.refresh() }
        await until { adapter.waiting == 1 }
        // The built-in comes from the new discovery; each monitor keeps what it showed.
        #expect(store.displays.first(where: \.isBuiltIn)?.connection.generation == store.generation)
        #expect(store.displays.filter { !$0.isBuiltIn } == before.filter { !$0.isBuiltIn })
        adapter.finishOldest()
        await second.value
        #expect(store.displays.allSatisfy { $0.connection.generation == store.generation && !$0.isChecking })
    }
}

@MainActor @Test func anOlderDiscoveryNeverShowsOverANewerOne() async {
    let adapter = SteppedAdapter()
    await MatchFixture.withStore(adapter: adapter) { store in
        let older = Task { await store.refresh() }
        await until { adapter.waiting == 1 }
        let newer = Task { await store.refresh() }
        await until { adapter.waiting == 2 }
        let newest = store.generation
        // The older one finishes first; what it found is dropped.
        adapter.finishOldest()
        await older.value
        #expect(store.isDiscovering)
        #expect(store.displays.allSatisfy { $0.connection.generation == newest })
        #expect(store.displays.contains { $0.isChecking })
        adapter.finishOldest()
        await newer.value
        #expect(!store.isDiscovering)
        #expect(store.displays.allSatisfy { $0.connection.generation == newest && !$0.isChecking })
    }
}
