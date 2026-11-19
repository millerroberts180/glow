#if DEBUG
import AppKit
import CoreGraphics
import Foundation

/// Debug command-line tools that print and exit, so the hardware path can be checked
/// without opening Glow.
///
/// - `--probe-displays` reads every display the way discovery does and prints what it
///   found. It changes nothing: the adapter runs in safe mode.
/// - `--ddc-selftest` changes each display's brightness by a few percent, confirms it by
///   reading back, then restores it and confirms that too. It also dims the picture through
///   the gamma table and restores it. Only brightness is ever written.
/// - `--probe-readings` finds displays, then rereads them the way Settings › Reading does:
///   a frequent pass, then Read Again with Normal and with Patient, printing each read and
///   how long it took. It changes nothing: the store runs in safe mode on throwaway settings.
/// - `--brightness-pulse <level> [standard|slow|alternate]` is for a monitor that never
///   answers a read, such as one behind a hub that may pass commands but drop the replies.
///   Someone watching the monitor reads its brightness from the monitor's own menu, and the
///   pulse dims it by 10 from there twice, then puts it back. Brightness only.
/// - `--simulated-selftest [-GlowSimulatedMonitors <ids>]` runs discovery and the brightness
///   self-test against simulated DDC/CI monitors (`SimulatedMonitor`), printing what each
///   one was sent. No real display is read or changed.
@MainActor
enum DisplayProbe {
    static func command(in arguments: [String]) -> String? {
        ["--probe-displays", "--ddc-selftest", "--probe-readings", "--brightness-pulse", "--simulated-selftest"].first(where: arguments.contains)
    }

    static func run(_ command: String) -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        // The readings probe, the pulse and the simulated monitors never dim, so they leave
        // alone any dimming a running Glow set.
        let resetsGamma = !["--probe-readings", "--brightness-pulse", "--simulated-selftest"].contains(command)
        if resetsGamma { SoftwareDimmer.installExitRestore() }
        var status: Int32 = 0
        wait {
            status = switch command {
            case "--ddc-selftest": await selfTest()
            case "--probe-readings": await probeReadings()
            case "--brightness-pulse": await brightnessPulse(CommandLine.arguments)
            case "--simulated-selftest": await simulatedSelfTest()
            default: await probe()
            }
        }
        if resetsGamma { SoftwareDimmer.restoreAll() }
        return status
    }

    // MARK: - Probe

    private static func probe() async -> Int32 {
        let adapter = HardwareDisplayAdapter(safeMode: true)
        say("Glow display probe (read-only). DDC/CI interface: \(interfaceStatus)")
        let started = ContinuousClock.now
        let displays = await adapter.discover(generation: 1)
        say("Discovery took \(milliseconds(since: started)) ms and found \(displays.count) display(s).")
        for display in displays {
            say("")
            describe(display, adapter: adapter)
        }
        return 0
    }

    private static func describe(_ display: DisplaySnapshot, adapter: HardwareDisplayAdapter) {
        let state = adapter.connected[display.identity]
        say("== \(display.name) (display \(display.connection.displayID)\(display.isBuiltIn ? ", built-in" : ""))")
        say("   identity: vendor \(hex(display.identity.vendorID)), product \(hex(display.identity.productID)), serial \(display.identity.serialNumber == 0 ? "none" : "present")")
        say("   transport: \(display.connection.transport)")
        if let facts = state?.facts {
            say("   framebuffer: \(facts.location ?? "unknown")")
        }
        if display.isBuiltIn {
            say("   matched: not matched to a DDC service (built-in displays don't speak DDC)")
        } else if let match = state?.match {
            say("   matched: registry ID \(hex(match.candidate.registryID)), score \(match.score), by \(match.reasons.joined(separator: ", "))")
            say("   service: \(match.candidate.productName ?? "no product name"), link \(match.candidate.transport ?? "unnamed")")
        } else {
            say("   matched: no DDC service matched this display")
        }
        for note in display.connectionNotes { say("   note: \(note)") }
        if !display.isBuiltIn, let log = state?.log {
            for line in log.reportLines(for: display) { say("   \(line)") }
        }
        say("   settings:")
        for descriptor in display.capabilities {
            let value = descriptor.currentValue.map { "\($0)\(descriptor.unit ?? "")" } ?? "no reading"
            let code = descriptor.rawCode.map { " [\($0)]" } ?? ""
            say("   - \(descriptor.label)\(code): \(value); route \(descriptor.route.userLabel); evidence \(descriptor.evidence.rawValue); access \(descriptor.access.rawValue)\(descriptor.isSafelyEditable ? "; editable" : "")")
            say("     \(descriptor.reliability.provenance)\(descriptor.reliability.lastFailure.map { ". \($0)" } ?? "")")
        }
        if let baseline = adapter.baseline[display.identity], !baseline.isEmpty {
            let values = baseline.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue) \($0.value)" }
            say("   baseline (values read before any change): \(values.joined(separator: ", "))")
        }
    }

    // MARK: - Readings

    /// Settings › Reading against the real displays, read-only: safe mode refuses every
    /// write, and launch restore never runs because the store isn't started.
    private static func probeReadings() async -> Int32 {
        let suite = "app.glow.probe.readings"
        guard let defaults = UserDefaults(suiteName: suite) else { return 1 }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GlowStore(settings: GlowSettingsStore(defaults: defaults), demoDisplays: false, safeMode: true)
        say("Glow reading probe (read-only, safe mode). DDC/CI interface: \(interfaceStatus)")
        let started = ContinuousClock.now
        let timeline = watchDisplays(store, since: started)
        await store.refresh()
        timeline.cancel()
        await timeline.value
        say("Discovery took \(milliseconds(since: started)) ms and found \(store.displays.count) display(s).")
        for display in store.displays {
            say("")
            say("== \(display.name)\(display.isBuiltIn ? " (built-in)" : ""): \(display.primaryRoute.userLabel)")
            if let log = store.hardwareAdapter.discoveryLog(for: display.id) {
                for attempt in log.attempts { say("   tried: \(DDCDiscoveryLog.text(for: attempt))") }
                if let note = log.note { say("   note: \(note)") }
            }
            let often = display.rereadable(.frequent).map(\.label)
            let rest = display.rereadable(.allSettings).map(\.label).filter { !often.contains($0) }
            let raw = display.reportedUncatalogued.compactMap(\.rawCode)
            guard !often.isEmpty || !rest.isEmpty || !raw.isEmpty else {
                say("   nothing to reread: Glow sets this display without asking it, so it's never polled")
                continue
            }
            say("   reread every 5 s while open (45 s in the background with Always): \(list(often))")
            say("   reread every minute while open (10 min in the background): \(list(rest))")
            say("   read once more on Read Again only: \(list(raw))")
            await pass("Frequent pass", store: store, display: display) {
                await store.readPass(display.id, scope: .frequent, now: Date())
            }
            await pass("Read Again (Normal)", store: store, display: display) { await store.readAgain(display.id) }
            store.readingPatience = .patient
            await pass("Read Again (Patient)", store: store, display: display) { await store.readAgain(display.id) }
            store.readingPatience = .normal
            if let clock = store.reading.clocks[display.id], clock.silentPasses > 0 {
                say("   unanswered passes: \(clock.silentPasses); next scheduled reread waits until \(clock.backoffUntil.map { "\($0)" } ?? "the next interval")")
            }
            say("   age: \(store.readingAge(for: display.id, now: Date()))")
        }
        return 0
    }

    /// Says when each display first shows, as Glow Desk would see it, and when its check
    /// finishes.
    private static func watchDisplays(_ store: GlowStore, since started: ContinuousClock.Instant) -> Task<Void, Never> {
        Task {
            var shown = Set<PersistentDisplayIdentity>()
            var checked = Set<PersistentDisplayIdentity>()
            while true {
                for display in store.displays {
                    if shown.insert(display.id).inserted {
                        say("\(milliseconds(since: started)) ms: \(display.name) shows\(display.isChecking ? ", being checked" : "")")
                    }
                    if !display.isChecking, checked.insert(display.id).inserted {
                        say("\(milliseconds(since: started)) ms: \(display.name) is ready: \(display.primaryRoute.userLabel)")
                    }
                }
                // One last look once discovery is done, then stop.
                if Task.isCancelled { return }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    private static func pass(_ title: String, store: GlowStore, display: DisplaySnapshot, _ read: () async -> [ReadingOutcome]) async {
        let started = ContinuousClock.now
        let outcomes = await read()
        let answered = outcomes.filter(\.wasRead).count
        say("   \(title): \(answered) of \(outcomes.count) answered in \(milliseconds(since: started)) ms")
        for outcome in outcomes { say("   - \(describe(outcome))") }
    }

    private static func describe(_ outcome: ReadingOutcome) -> String {
        let value = outcome.value.map(\.description) ?? "no value"
        let result = switch outcome.result {
        case .unchanged: "unchanged, \(value)"
        case .changed(let from): "changed from \(from?.description ?? "no value") to \(value)"
        case .failed(let reason): "failed: \(reason)"
        case .skipped(let reason): "skipped: \(reason)"
        }
        let time = outcome.milliseconds.map { " · \($0) ms" } ?? ""
        return "\(outcome.label) [\(outcome.capability.rawValue)]: \(result)\(time)"
    }

    private static func list(_ items: [String]) -> String { items.isEmpty ? "none" : items.joined(separator: ", ") }

    // MARK: - Self-test

    /// Brightness only, by at most 10, through the same pipeline the app uses.
    private static func selfTest() async -> Int32 {
        let adapter = HardwareDisplayAdapter()
        let pipeline = DisplayWritePipeline()
        await pipeline.setTopologyGeneration(1)
        say("Glow brightness self-test. Each display: read, change by 5, confirm, restore, confirm.")
        let displays = await adapter.discover(generation: 1)
        var failures = 0
        for display in displays {
            say("")
            say("== \(display.name) (display \(display.connection.displayID))")
            guard let descriptor = display.capabilities.first(where: { $0.id == .brightness }) else {
                say("   no brightness setting; skipped")
                continue
            }
            say("   route: \(descriptor.route.userLabel); evidence: \(descriptor.evidence.rawValue)")
            guard descriptor.isSafelyEditable, case let .number(original)? = descriptor.currentValue,
                  case let .range(minimum, maximum, _) = descriptor.kind else {
                say("   not editable here (\(descriptor.reliability.provenance)); skipped")
                continue
            }
            // Glow works in whole percents; native brightness is finer, so keep the exact level.
            let id = display.connection.displayID
            let exact = descriptor.route == .native ? NativeBrightness.shared?.brightness(id) : nil
            if let exact { say("   exact level before: \(exact)") }
            let target = original + 5 <= maximum ? original + 5 : max(minimum, original - 5)
            failures += await step("write", from: original, to: target, descriptor: descriptor, display: display, adapter: adapter, pipeline: pipeline)
            failures += await step("restore", from: target, to: original, descriptor: descriptor, display: display, adapter: adapter, pipeline: pipeline)
            if let after = try? await adapter.read(capability: .brightness, display: display.identity) {
                say("   final read: \(after) (started at \(CapabilityValue.number(original)))")
                if after != .number(original) { failures += 1 }
            }
            if let exact, let native = NativeBrightness.shared {
                let set = native.setBrightness(exact, on: id)
                let back = native.brightness(id)
                say("   exact level restored: \(set ? "accepted" : "refused"), read back \(back.map { "\($0)" } ?? "unreadable")")
                if !set || back.map({ abs($0 - exact) > 0.0005 }) ?? true { failures += 1 }
            }
        }
        failures += gammaTest(displays)
        say("")
        say(failures == 0 ? "Self-test passed." : "Self-test finished with \(failures) failure(s).")
        return failures == 0 ? 0 : 1
    }

    private static func step(
        _ label: String, from: Double, to: Double, descriptor: CapabilityDescriptor, display: DisplaySnapshot,
        adapter: any DisplayAdapter, pipeline: DisplayWritePipeline
    ) async -> Int {
        let started = ContinuousClock.now
        do {
            let confirmed = try await pipeline.write(descriptor: descriptor, value: .number(to), display: display, adapter: adapter)
            say("   \(label): \(CapabilityValue.number(from)) → \(CapabilityValue.number(to)); read back \(confirmed) in \(milliseconds(since: started)) ms, confirmed")
            return 0
        } catch {
            say("   \(label): \(CapabilityValue.number(from)) → \(CapabilityValue.number(to)) failed after \(milliseconds(since: started)) ms: \(error.localizedDescription)")
            return 1
        }
    }

    /// Dims each display's picture to 80 % through its gamma table, reads the table back,
    /// then hands it back to ColorSync and checks it's full again.
    private static func gammaTest(_ displays: [DisplaySnapshot]) -> Int {
        let dimmer = SoftwareDimmer.shared
        var failures = 0
        for display in displays {
            let id = display.connection.displayID
            say("")
            say("== Software dimming on \(display.name)")
            guard let before = dimmer.level(of: id) else {
                say("   gamma table unreadable; skipped")
                continue
            }
            let dimmed = dimmer.setLevel(0.8, on: id)
            let during = dimmer.level(of: id)
            let restored = dimmer.setLevel(1, on: id)
            let after = dimmer.level(of: id)
            say("   before \(percent(before)); set 80 % \(dimmed ? "accepted" : "refused"), read back \(during.map(percent) ?? "unreadable")")
            say("   restore \(restored ? "accepted" : "refused"), read back \(after.map(percent) ?? "unreadable")")
            if !dimmed || during.map({ abs($0 - 0.8) > 0.01 }) ?? true { failures += 1 }
            if !restored || after != 1 { failures += 1 }
        }
        dimmer.restore()
        return failures
    }

    // MARK: - Brightness pulse

    /// Whether commands reach a monitor whose replies never come back. Glow can't read this
    /// monitor, so `level` is what its own menu shows, and the person watching is the read-back.
    /// It finds displays read-only, then sends Set VCP 0x10 (brightness) and nothing else, to
    /// the one external display that answered no read: 10 below `level` (10 above when `level`
    /// is under 10), `level`, the same again, and `level` once more in case the last was lost.
    /// Each dip lasts 3 s, so it is seen twice. Refuses unless exactly one external display is
    /// connected and it stayed silent; one that answers is for `--ddc-selftest`, which reads first.
    private static func brightnessPulse(_ arguments: [String]) async -> Int32 {
        let profiles: [String: DDCTransportProfile] = ["standard": .standard, "slow": .slow, "alternate": .alternate]
        guard let index = arguments.firstIndex(of: "--brightness-pulse"), arguments.indices.contains(index + 1),
              let level = Int(arguments[index + 1]), (0...100).contains(level),
              let profile = profiles[arguments.indices.contains(index + 2) ? arguments[index + 2] : "standard"] else {
            say("usage: Glow --brightness-pulse <brightness 0–100, from the monitor's own menu> [standard|slow|alternate]")
            return 64
        }
        say("Glow brightness pulse. Finding displays first, reading only…")
        let adapter = HardwareDisplayAdapter(safeMode: true)
        let external = await adapter.discover(generation: 1).filter { !$0.isBuiltIn }
        guard external.count == 1, let display = external.first else {
            say("Refused: this needs exactly one external display connected, and there \(external.count == 1 ? "is" : "are") \(external.count). Nothing was sent.")
            return 1
        }
        let state = adapter.connected[display.identity]
        guard let registryID = state?.match?.candidate.registryID else {
            say("Refused: \(display.name) has no DDC service matched to it. Nothing was sent.")
            return 1
        }
        guard state?.log?.workingProfile == nil else {
            say("Refused: \(display.name) answers DDC/CI reads, so use --ddc-selftest, which reads first. Nothing was sent.")
            return 1
        }
        guard let link = DisplayRegistry.link(registryID: registryID, profile: profile) else {
            say("Refused: macOS wouldn't open \(display.name)'s DDC service. Nothing was sent.")
            return 1
        }
        let dip = level >= 10 ? level - 10 : level + 10
        say("== \(display.name): vendor \(hex(display.identity.vendorID)), product \(hex(display.identity.productID)), service \(hex(registryID))")
        say("   profile: \(profile.name). Brightness \(level) → \(dip) → \(level) → \(dip) → \(level), starting in 3 s. Watch the monitor.")
        let started = ContinuousClock.now
        try? await Task.sleep(for: .seconds(3))
        var refused = 0
        for (value, hold) in [(dip, 3), (level, 3), (dip, 3), (level, 1), (level, 0)] {
            let sent = ContinuousClock.now
            do {
                try await link.write(code: 0x10, value: UInt16(value))
                say("   \(seconds(since: started)) s: sent brightness \(value); the connection took it in \(milliseconds(since: sent)) ms")
            } catch {
                refused += 1
                say("   \(seconds(since: started)) s: brightness \(value) refused: \(error.localizedDescription)")
            }
            try? await Task.sleep(for: .seconds(hold))
        }
        say("")
        say(refused == 0
            ? "Every command left the Mac. Did the monitor dim twice? Its menu should show \(level) again."
            : "\(refused) of 5 commands were refused before leaving the Mac. Check the monitor's menu shows \(level).")
        return refused == 0 ? 0 : 1
    }

    // MARK: - Simulated monitors

    /// The self-test's brightness steps against simulated monitors, through the same
    /// discovery, pipeline and DDC bytes as a real display, with every request each monitor
    /// accepted. Discovery must send no Set VCP, and the test only brightness.
    private static func simulatedSelfTest() async -> Int32 {
        let adapter = SimulatedDisplayAdapter.requested(in: CommandLine.arguments, safeMode: false)
            ?? SimulatedDisplayAdapter(monitors: SimulatedMonitor.Model.all.map { SimulatedMonitor($0) })
        let pipeline = DisplayWritePipeline()
        await pipeline.setTopologyGeneration(1)
        say("Glow simulated-monitor self-test. No real display is read or changed.")
        let started = ContinuousClock.now
        let displays = await adapter.discover(generation: 1)
        say("Discovery took \(milliseconds(since: started)) ms and found \(displays.count) simulated monitor(s).")
        var failures = 0
        for display in displays {
            guard let monitor = adapter.connected[display.identity]?.monitor else { continue }
            say("")
            say("== \(display.name)")
            for note in display.connectionNotes { say("   note: \(note)") }
            for line in adapter.discoveryLog(for: display.identity)?.reportLines(for: display) ?? [] { say("   \(line)") }
            let editable = display.capabilities.filter(\.isSafelyEditable).map { "\($0.label) \($0.currentValue.map { "\($0)" } ?? "unread")" }
            say("   editable: \(list(editable))")
            if !monitor.writes.isEmpty {
                say("   discovery sent Set VCP: \(list(monitor.writes.map { "0x\(DDCPacket.hex($0.code))" }))")
                failures += 1
            }
            guard let descriptor = display.capabilities.first(where: { $0.id == .brightness }), descriptor.isSafelyEditable,
                  case let .number(original)? = descriptor.currentValue, case let .range(minimum, maximum, _) = descriptor.kind else {
                say("   brightness isn't editable; failed")
                failures += 1
                continue
            }
            let target = original + 5 <= maximum ? original + 5 : max(minimum, original - 5)
            for (label, from, to) in [("write", original, target), ("restore", target, original)] {
                monitor.clearLog()
                failures += await step(label, from: from, to: to, descriptor: descriptor, display: display, adapter: adapter, pipeline: pipeline)
                say("     wire: \(list(monitor.log.map(\.description)))")
                let counters = monitor.counters
                say("     dropped while busy \(counters.droppedWhileBusy), read too early \(counters.earlyReads), garbled \(counters.garbled), ignored \(counters.ignored), rejected \(counters.rejected)")
                if counters.rejected > 0 || monitor.writes.contains(where: { $0.code != 0x10 }) { failures += 1 }
            }
            let after = monitor.value(of: 0x10)
            say("   monitor's brightness now: \(after.map(String.init) ?? "none") (started at \(Int(original)))")
            if after != UInt16(original) { failures += 1 }
        }
        say("")
        say(failures == 0 ? "Simulated self-test passed." : "Simulated self-test finished with \(failures) failure(s).")
        return failures == 0 ? 0 : 1
    }

    // MARK: - Helpers

    private static var interfaceStatus: String {
        switch IOAVServiceAPI.shared {
        case .success: "IOAVService calls found"
        case .failure(let error): error.localizedDescription
        }
    }

    private static func say(_ line: String) {
        print(line)
        fflush(stdout)
    }

    private static func hex(_ value: some BinaryInteger) -> String { "0x" + String(value, radix: 16, uppercase: true) }
    private static func percent(_ level: Double) -> String { "\(Int((level * 100).rounded())) %" }
    private static func milliseconds(since start: ContinuousClock.Instant) -> Int64 { (ContinuousClock.now - start).milliseconds }
    private static func seconds(since start: ContinuousClock.Instant) -> String {
        String(format: "%.1f", Double((ContinuousClock.now - start).milliseconds) / 1000)
    }

    private static func wait(_ work: @escaping @MainActor () async -> Void) {
        let task = Task { await work() }
        var finished = false
        Task {
            await task.value
            finished = true
        }
        while !finished {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }
}
#endif
