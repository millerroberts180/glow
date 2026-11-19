import Foundation
import Observation

/// Settings › Reading: rereading displays, Read Again, launch restore, Patience and Hide
/// (ADR 0002). Reads never cause writes. The one write here is launch restore, which only
/// runs when someone chose it.
extension GlowStore {
    var readingFreshness: ReadingFreshness {
        get { settings.value.reading.freshness }
        set { settings.value.reading.freshness = newValue }
    }

    var launchReading: LaunchReading {
        get { settings.value.reading.atLaunch }
        set { settings.value.reading.atLaunch = newValue }
    }

    var readingPatience: ReadingPatience {
        get { settings.value.reading.patience }
        set {
            settings.value.reading.patience = newValue
            hardwareAdapter.patience = newValue
        }
    }

    // MARK: - The reread loop

    /// Called from `start()` after the first discovery, and again whenever demo mode
    /// restarts the store: the loop is replaced, never doubled.
    func startReading() async {
        hardwareAdapter.patience = readingPatience
        if !reading.tracksLastSet {
            reading.tracksLastSet = true
            trackLastSet()
        }
        if !reading.launchActionDone {
            reading.launchActionDone = true
            if launchReading == .restore { await putBackLastSet() }
        }
        reading.loop?.cancel()
        reading.loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let pause = await self?.readingStep() else { return }
                try? await Task.sleep(for: pause)
            }
        }
    }

    /// One turn of the loop, and how long to wait before the next: a second while Glow is
    /// open, five while it's closed.
    private func readingStep() async -> Duration {
        await readingTick(now: reading.now())
        return reading.isGlowOpen() ? .seconds(1) : .seconds(5)
    }

    /// Clears marks older than a minute, then rereads whatever is due on each display at
    /// `now`, all displays at once. Nothing is read while writes are paused or discovery runs.
    func readingTick(now: Date) async {
        clearChangeMarks(now: now)
        guard pauseReason == nil, !isDiscovering else { return }
        let intervals = ReadingSchedule.intervals(readingFreshness, isOpen: reading.isGlowOpen())
        let due = displays.compactMap { display -> (PersistentDisplayIdentity, ReadingScope)? in
            guard !reading.passes.contains(display.id),
                  let scope = ReadingSchedule.due(reading.clocks[display.id] ?? DisplayReadingClock(), intervals: intervals, now: now) else { return nil }
            return (display.id, scope)
        }
        // Each pass awaits its own reads, so the displays are read side by side.
        let passes = due.map { id, scope in Task { await readPass(id, scope: scope, now: now) } }
        for pass in passes { _ = await pass.value }
    }

    /// Rereads one display, one setting at a time, with Get VCP or macOS's own query. A
    /// setting someone is changing, or a display Glow wrote to a moment ago, is skipped, and
    /// each read is checked again when it returns, so a reading never lands on top of a change.
    @discardableResult
    func readPass(_ id: PersistentDisplayIdentity, scope: ReadingScope, now: Date) async -> [ReadingOutcome] {
        guard !reading.passes.contains(id), let display = displays.first(where: { $0.id == id }) else { return [] }
        reading.passes.insert(id)
        defer { reading.passes.remove(id) }
        let generation = display.connection.generation
        let adapter = adapter
        var outcomes: [ReadingOutcome] = []
        var asked = 0
        var unanswered = 0

        for descriptor in display.rereadable(scope) {
            var outcome = ReadingOutcome(display: id, capability: descriptor.id, label: descriptor.label, result: .unchanged)
            if let reason = readingSkip(descriptor.id, on: id, generation: generation) {
                outcome.result = .skipped(reason)
                outcomes.append(outcome)
                continue
            }
            let started = ContinuousClock.now
            do {
                let value = try await adapter.read(capability: descriptor.id, display: id)
                outcome.milliseconds = Self.milliseconds(since: started)
                if descriptor.route == .hardware { asked += 1 }
                if let reason = readingSkip(descriptor.id, on: id, generation: generation) {
                    outcome.result = .skipped("\(reason), so the reading was dropped")
                    outcomes.append(outcome)
                    continue
                }
                outcome.value = value
                // A reading Glow can't trust is never shown and never confirms the last one.
                if let reason = descriptor.distrust(value) {
                    outcome.result = .skipped("\(reason), so Glow kept the last reading")
                    outcomes.append(outcome)
                    continue
                }
                let shown = displays.first(where: { $0.id == id })?.capabilities.first(where: { $0.id == descriptor.id })?.currentValue
                outcome.result = shown == value || shown == nil ? .unchanged : .changed(from: shown)
                reviseSetting(descriptor.id, on: id, generation: generation) { setting in
                    setting.lastConfirmedValue = value
                    setting.freshness = .confirmed
                    if let shown = setting.currentValue, shown != value { setting.changedOnDisplayAt = now }
                    setting.currentValue = value
                }
            } catch {
                outcome.milliseconds = Self.milliseconds(since: started)
                if descriptor.route == .hardware {
                    asked += 1
                    if Self.isSilence(error) { unanswered += 1 }
                }
                outcome.result = .failed(error.localizedDescription)
            }
            outcomes.append(outcome)
        }

        if case .everything = scope {
            for descriptor in display.reportedUncatalogued {
                guard let code = descriptor.reportedCode, readingSkip(descriptor.id, on: id, generation: generation) == nil else { continue }
                let started = ContinuousClock.now
                let result: ProbeResult
                do {
                    result = try await adapter.readReported(code: code, display: id)
                } catch ControlError.notWritable {
                    continue
                } catch {
                    result = .noResponse
                }
                asked += 1
                if result == .noResponse { unanswered += 1 }
                guard readingSkip(descriptor.id, on: id, generation: generation) == nil else { continue }
                reviseSetting(descriptor.id, on: id, generation: generation) { $0 = $0.recordingRawReading(result) }
                outcomes.append(ReadingOutcome(
                    display: id, capability: descriptor.id, label: descriptor.label,
                    result: result == .noResponse ? .failed("No reply") : .unchanged,
                    value: .text(DDCProbe.describe(result)), milliseconds: Self.milliseconds(since: started)
                ))
            }
        }

        var clock = reading.clocks[id] ?? DisplayReadingClock()
        clock.lastFrequent = now
        if scope != .frequent { clock.lastRare = now }
        // Every DDC/CI read went unanswered: leave the display alone for a while. One answer
        // is enough to start again.
        if asked > 0, unanswered == asked {
            clock.silentPasses += 1
            clock.backoffUntil = now.addingTimeInterval(ReadingSchedule.backoff(afterSilentPasses: clock.silentPasses))
        } else if asked > unanswered {
            clock.silentPasses = 0
            clock.backoffUntil = nil
        }
        reading.clocks[id] = clock
        // A display with nothing to reread, like one Glow dims itself, is as read as it gets.
        if scope != .frequent, outcomes.isEmpty || outcomes.contains(where: \.wasRead) { reading.lastRead[id] = now }
        reading.note(outcomes)
        return outcomes
    }

    /// Why a setting can't be read, or a reading can't be used, right now; nil when it can.
    private func readingSkip(_ capability: CapabilityIdentifier, on id: PersistentDisplayIdentity, generation: UInt64) -> String? {
        if pauseReason != nil { return "Writes are paused" }
        if isDiscovering { return "Glow is looking for displays" }
        guard let display = displays.first(where: { $0.id == id && $0.connection.generation == generation }),
              let setting = display.capabilities.first(where: { $0.id == capability }) else { return "The display reconnected" }
        if setting.pendingValue != nil { return "A change is on its way" }
        if let last = adapter.lastWrite(to: id), ContinuousClock.now - last < reading.writeQuiet { return "Glow changed this display a moment ago" }
        return nil
    }

    /// A read that got no answer, as opposed to one the display refused or answered oddly.
    private static func isSilence(_ error: Error) -> Bool {
        guard let error = error as? ControlError else { return true }
        return error == .timedOut
    }

    private static func milliseconds(since started: ContinuousClock.Instant) -> Int {
        Int((ContinuousClock.now - started).milliseconds)
    }

    /// Takes "Changed on the display" off settings marked more than a minute before `now`.
    func clearChangeMarks(now: Date) {
        for display in displays {
            for setting in display.capabilities {
                guard let marked = setting.changedOnDisplayAt, now.timeIntervalSince(marked) >= ReadingSchedule.markDuration else { continue }
                reviseSetting(setting.id, on: display.id, generation: display.connection.generation) { $0.changedOnDisplayAt = nil }
            }
        }
    }

    // MARK: - Read Again

    /// Read Again: every setting the display reports, hidden ones too, and once more each
    /// reported code the catalog doesn't know. It ignores Keep readings fresh and the
    /// back-off, because someone asked, and it doesn't rediscover.
    @discardableResult
    func readAgain(_ id: PersistentDisplayIdentity) async -> [ReadingOutcome] {
        guard pauseReason == nil, !isDiscovering, !reading.readingNow.contains(id) else { return [] }
        reading.readingNow.insert(id)
        defer { reading.readingNow.remove(id) }
        // A scheduled pass on this display finishes first.
        while reading.passes.contains(id), !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return await readPass(id, scope: .everything, now: reading.now())
    }

    /// Read All: Read Again on every display at once.
    func readAll() async {
        let reads = displays.map { display in Task { await readAgain(display.id) } }
        for read in reads { _ = await read.value }
    }

    /// "Read just now", "Read 3 min ago".
    func readingAge(for id: PersistentDisplayIdentity, now: Date) -> String {
        ReadingAge.text(since: reading.lastRead[id], now: now)
    }

    /// The oldest full reading of any display, for Read All.
    func oldestReadingAge(now: Date) -> String {
        let reads = displays.map { reading.lastRead[$0.id] }
        if reads.contains(where: { $0 == nil }) { return ReadingAge.text(since: nil, now: now) }
        return ReadingAge.text(since: reads.compactMap { $0 }.min(), now: now)
    }

    // MARK: - Discovery's results

    /// Discovery's result with reading's state laid over it: each display counts as just
    /// read, and what someone hid on a real display stays hidden. `rediscover()` calls it.
    func applyingCorrections(to discovered: [DisplaySnapshot]) -> [DisplaySnapshot] {
        let now = reading.now()
        return discovered.map { display in
            reading.lastRead[display.id] = now
            reading.clocks[display.id] = DisplayReadingClock(lastFrequent: now, lastRare: now)
            let hidden = display.isDemo ? [] : settings.value.corrections.hidden(on: display.id)
            guard !hidden.isEmpty else { return display }
            var corrected = display
            for index in corrected.capabilities.indices
            where hidden.contains(corrected.capabilities[index].id) && corrected.capabilities[index].canBeHidden {
                corrected.capabilities[index].presentation = .hiddenByYou
            }
            return corrected
        }
    }

    // MARK: - Hide and Show

    /// Hides a setting a real display reports but that does nothing there. It leaves the OSD,
    /// Glow Desk and scenes, and Connection details lists it as "Hidden by you".
    func hide(_ capability: CapabilityIdentifier, on id: PersistentDisplayIdentity) {
        guard let display = displays.first(where: { $0.id == id }), !display.isDemo,
              display.capabilities.first(where: { $0.id == capability })?.canBeHidden == true else { return }
        settings.value.corrections.hide(capability, on: id)
        reviseSetting(capability, on: id, generation: display.connection.generation) { $0.presentation = .hiddenByYou }
    }

    func show(_ capability: CapabilityIdentifier, on id: PersistentDisplayIdentity) {
        settings.value.corrections.show(capability, on: id)
        guard let display = displays.first(where: { $0.id == id }) else { return }
        reviseSetting(capability, on: id, generation: display.connection.generation) { setting in
            if setting.presentation == .hiddenByYou { setting.presentation = .osd }
        }
    }

    /// What's hidden on a display, by name, including settings it didn't report this time.
    func hiddenSettings(on id: PersistentDisplayIdentity) -> [(id: CapabilityIdentifier, label: String)] {
        let display = displays.first(where: { $0.id == id })
        return settings.value.corrections.hidden(on: id)
            .map { capability in
                let label = display?.capabilities.first(where: { $0.id == capability })?.label
                    ?? CapabilityCatalog.entry(for: capability)?.label ?? capability.rawValue
                return (capability, label)
            }
            .sorted { first, second in
                let order = { (id: CapabilityIdentifier) in display?.capabilities.first(where: { $0.id == id })?.sortOrder ?? Int.max }
                return (order(first.id), first.label) < (order(second.id), second.label)
            }
    }

    // MARK: - At launch

    /// Keeps what Glow last set on each real display, across launches, for "Put back what
    /// Glow last set". Follows `setByGlow` without touching how it's written.
    private func trackLastSet() {
        withObservationTracking {
            _ = setByGlow
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.recordLastSet()
                self?.trackLastSet()
            }
        }
    }

    func recordLastSet() {
        var lastSet = settings.value.lastSet
        for (id, values) in setByGlow {
            guard let display = displays.first(where: { $0.id == id }), !display.isDemo else { continue }
            lastSet.record(values, on: id)
        }
        if lastSet != settings.value.lastSet { settings.value.lastSet = lastSet }
    }

    /// At launch › Put back what Glow last set: Reapply after wake's rules and write path,
    /// for the values kept from the last launch. Real displays only, never input or power,
    /// never in safe mode and never while writes are paused.
    @discardableResult
    func putBackLastSet() async -> SceneResult? {
        guard !safeMode, !demoMode, pauseReason == nil else { return nil }
        let scene = LaunchRestore.scene(from: settings.value.lastSet, on: displays)
        guard !scene.displays.isEmpty else { return nil }
        let result = await SceneApplier.apply(scene.plan(on: displays), includingAsksFirst: false) { write in
            guard !LaunchRestore.neverWritten.contains(write.capability) else { throw ControlError.notWritable }
            _ = try await confirmWrite(displayID: write.display, capabilityID: write.capability, value: write.value)
        }
        reading.launchResult = result
        showMessage("At launch: \(result.summary(done: "Put back"))")
        return result
    }
}
