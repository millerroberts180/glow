#if DEBUG
import Foundation

/// `swift run Glow --hold-selftest` (debug builds): a held brightness key through the real
/// store, pipeline and hold timer, against the demo displays behind an adapter as slow as
/// DDC/CI (120 ms to write, as long again to read back). No real display is touched. It taps
/// up, holds up for two seconds while a simulated keyboard sends its repeats, then taps
/// down, and prints what the store showed on every tick and every write the display got.
/// Exits non-zero on a failure.
@MainActor
enum HoldSelfTest {
    static func requested(in arguments: [String]) -> Bool { arguments.contains("--hold-selftest") }

    static func run() async -> Int32 {
        let suite = "app.glow.hold-selftest"
        guard let defaults = UserDefaults(suiteName: suite) else { return 1 }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let start = ProcessInfo.processInfo.systemUptime
        let now = { ProcessInfo.processInfo.systemUptime - start }
        let adapter = SlowDemoAdapter(clock: now)
        let store = GlowStore(settings: GlowSettingsStore(defaults: defaults), demoDisplays: false, adapter: adapter)
        store.showOverlayOnChange = false
        await store.refresh()
        let dell = DemoData.dellIdentity
        store.controlTarget = .focused
        store.focusedDisplayID = dell
        let level = { store.displays.first(where: { $0.id == dell })?.brightnessSetting?.matchNumber ?? .nan }

        var ticks: [(time: Double, value: Double)] = []
        let hold = BrightnessKeyHold(
            press: { store.handleBrightnessKey($0, pointerDisplay: nil) },
            tick: { direction in
                let stop = store.rampBrightness(direction, pointerDisplay: nil)
                ticks.append((now(), level()))
                return stop
            }
        )
        let timing = hold.timing
        print("Hold timing: ramp after \(ms(timing.rampDelay)), a 1% step every \(ms(timing.tickInterval)), silent after \(ms(timing.repeatWindow)) without a repeat")
        print("Dell (hardware, demo) starts at \(format(level()))%, step \(store.keyStep.title); writes take 120 ms and read-backs 120 ms")

        var failures = 0
        func check(_ passed: Bool, _ text: String) {
            print("\(passed ? "PASS" : "FAIL")  \(text)")
            if !passed { failures += 1 }
        }
        let up = BrightnessKeyPress(direction: .up, quarterStep: false)
        let down = BrightnessKeyPress(direction: .down, quarterStep: false)

        // 1. A tap: one step, on key-down.
        let beforeTap = level()
        let expectedTap = BrightnessKeyRouting.next(from: beforeTap, range: 0...100, press: BrightnessKeyPress(direction: .up, quarterStep: false, step: store.keyStep)).rounded()
        print(String(format: "%7.3f  key down (tap up)", now()))
        _ = hold.handle(.down(up, isRepeat: false))
        let afterTap = level()
        try? await Task.sleep(for: .milliseconds(90))
        _ = hold.handle(.up(.up))
        print(String(format: "%7.3f  key up, store at %@%%", now(), format(level())))
        check(afterTap == expectedTap, "a tap moves one step at once: \(format(beforeTap)) → \(format(afterTap))")
        check(ticks.isEmpty, "a tap doesn't ramp")
        try? await Task.sleep(for: .milliseconds(400))

        // 2. A two-second hold, the keyboard repeating every 33 ms after its delay.
        let holdStart = now()
        print(String(format: "%7.3f  key down (hold up)", holdStart))
        _ = hold.handle(.down(up, isRepeat: false))
        let afterPress = level()
        var swallowed = true
        let repeats = Task {
            try? await Task.sleep(for: .seconds(timing.rampDelay))
            while now() - holdStart < 2.0, !Task.isCancelled {
                swallowed = swallowed && hold.handle(.down(up, isRepeat: true))
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
        try? await Task.sleep(for: .seconds(2.0))
        repeats.cancel()
        _ = hold.handle(.up(.up))
        let released = now()
        let atRelease = level()
        print(String(format: "%7.3f  key up, store at %@%%", released, format(atRelease)))
        check(hold.lastStop == .released, "the key-up stopped the ramp")
        check(swallowed, "every repeat was swallowed")

        try? await Task.sleep(for: .milliseconds(300))
        // 3. A tap the other way.
        print(String(format: "%7.3f  key down (tap down)", now()))
        _ = hold.handle(.down(down, isRepeat: false))
        try? await Task.sleep(for: .milliseconds(90))
        _ = hold.handle(.up(.down))
        let afterDown = level()

        // Let the last write and its read-back land.
        for _ in 0..<100 where store.displays.first(where: { $0.id == dell })?.brightnessSetting?.pendingValue != nil {
            try? await Task.sleep(for: .milliseconds(20))
        }

        // The timeline: what the store showed on each tick, and what the display was sent.
        print("\nTimeline (seconds from start):")
        var events: [(time: Double, line: String)] = ticks.map { ($0.time, "tick   store \(format($0.value))%") }
        for (index, call) in adapter.calls.enumerated() {
            let readBack = adapter.calls[(index + 1)...].first(where: { $0.kind == "read" })
            let confirmed = call.kind == "write" && readBack?.value == call.value
                && !adapter.calls[(index + 1)...].prefix(while: { $0.kind != "read" }).contains(where: { $0.kind == "write" })
            let label = call.kind == "write" ? "write  \(call.value.description)%\(confirmed ? "  (read back, confirmed)" : "  (no read-back)")" : "read   \(call.value.description)%"
            events.append((call.started, "       → \(label), done at \(String(format: "%.3f", call.finished))"))
        }
        for event in events.sorted(by: { $0.time < $1.time }) {
            print(String(format: "%7.3f  ", event.time) + event.line)
        }

        let rampTicks = ticks.filter { $0.time > holdStart && $0.time <= released }
        let gaps = zip(rampTicks.dropFirst(), rampTicks).map { $0.time - $1.time }
        let steps = zip(rampTicks.dropFirst(), rampTicks).map { $0.value - $1.value }
        let writes = adapter.calls.filter { $0.kind == "write" }
        let final = store.displays.first(where: { $0.id == dell })?.brightnessSetting
        print("\nRamp: \(rampTicks.count) ticks from \(format(afterPress))% to \(format(atRelease))%, largest gap between ticks \(ms(gaps.max() ?? 0))")
        print("Display: \(writes.count) writes, \(adapter.calls.count - writes.count) read-backs; at most \(adapter.maxInFlight) call in flight")
        print("Final: store \(format(level()))%, confirmed \(final?.lastConfirmedValue?.description ?? "nothing")%, display \(adapter.value(dell)?.description ?? "nothing")%")

        check(rampTicks.first.map { $0.time - holdStart >= timing.rampDelay - 0.005 } ?? false, "the ramp waits for the repeat delay")
        check(!steps.isEmpty && steps.allSatisfy { $0 == 1 }, "every tick moved exactly 1%")
        check((gaps.max() ?? 1) < 0.05, "no tick came more than 50 ms after the last")
        check(adapter.maxInFlight == 1, "one call at a time reached the display")
        check(writes.count < ticks.count, "values a newer one overtook were never sent")
        check(afterDown < atRelease, "the tap down moved down at once")
        check(final?.pendingValue == nil && final?.freshness == .confirmed, "the last value is confirmed")
        check(final?.lastConfirmedValue == .number(afterDown) && adapter.value(dell) == .number(afterDown), "the display ends on the store's last value, \(format(afterDown))%")
        print(failures == 0 ? "All hold checks passed." : "\(failures) hold check(s) failed.")
        return failures == 0 ? 0 : 1
    }

    private static func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
    private static func ms(_ seconds: Double) -> String { "\(Int((seconds * 1000).rounded())) ms" }
}

/// The demo displays, the Dell dimmed to 10%, behind DDC/CI's pace: every write and read
/// takes 120 ms. It keeps each call, with when it started and finished.
@MainActor
private final class SlowDemoAdapter: DisplayAdapter {
    struct Call {
        var kind: String
        var value: CapabilityValue
        var started: Double
        var finished: Double
    }

    let name = "Slow demo (hold self-test)"
    private let clock: () -> Double
    private var values: [PersistentDisplayIdentity: [CapabilityIdentifier: CapabilityValue]] = [:]
    private(set) var calls: [Call] = []
    private var inFlight = 0
    private(set) var maxInFlight = 0

    init(clock: @escaping () -> Double) {
        self.clock = clock
        values[DemoData.dellIdentity] = [.brightness: .number(10)]
    }

    func value(_ display: PersistentDisplayIdentity) -> CapabilityValue? { values[display]?[.brightness] }

    func discover(generation: UInt64) async -> [DisplaySnapshot] {
        DemoData.displays(generation: generation).map { display in
            var display = display
            for index in display.capabilities.indices {
                let id = display.capabilities[index].id
                if let value = values[display.id]?[id] {
                    display.capabilities[index].currentValue = value
                    display.capabilities[index].lastConfirmedValue = value
                } else if let value = display.capabilities[index].currentValue {
                    values[display.id, default: [:]][id] = value
                }
            }
            return display
        }
    }

    func write(_ value: CapabilityValue, capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws {
        let started = begin()
        try? await Task.sleep(for: .milliseconds(120))
        values[display, default: [:]][capability] = value
        end("write", value, started)
    }

    func read(capability: CapabilityIdentifier, display: PersistentDisplayIdentity) async throws -> CapabilityValue {
        let started = begin()
        try? await Task.sleep(for: .milliseconds(120))
        guard let value = values[display]?[capability] else { throw ControlError.timedOut }
        end("read", value, started)
        return value
    }

    private func begin() -> Double {
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        return clock()
    }

    private func end(_ kind: String, _ value: CapabilityValue, _ started: Double) {
        inFlight -= 1
        calls.append(Call(kind: kind, value: value, started: started, finished: clock()))
    }
}
#endif
