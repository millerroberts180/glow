import Foundation
import Observation

/// Puts the grey comparison patch on each display while matching, and takes it down.
@MainActor
protocol MatchPatchPresenting: AnyObject {
    /// False when there are no real screens to show patches on, as with demo displays;
    /// the window draws stand-ins then.
    var showsOnScreens: Bool { get }
    func show(_ patches: [MatchPatch])
    func hide()
}

/// One display's patch: the same grey on every display, with a small caption.
struct MatchPatch: Equatable, Sendable {
    let screen: UInt32
    let name: String
    let isReference: Bool
}

/// Demo displays have no screens to put patches on.
@MainActor
final class WindowOnlyPatches: MatchPatchPresenting {
    var showsOnScreens: Bool { false }
    func show(_ patches: [MatchPatch]) {}
    func hide() {}
}

/// One run of Brightness Match, from choosing the reference until it's saved or
/// cancelled. Every change goes through the store's confirmed write, nothing is kept
/// until Save, and Cancel puts every display it changed back where it was.
@MainActor @Observable
final class MatchSession {
    enum Step: Equatable {
        case intro
        /// Comparing at `levels[index]`.
        case compare(Int)
        case review
        /// Putting displays back, or setting them on their new curves.
        case settling
        /// Saved, cancelled or closed. The window stays open only if something went wrong.
        case finished
    }

    let store: GlowStore
    var method: MatchMethod
    var referenceID: PersistentDisplayIdentity?
    /// The display ←/→ adjust.
    var adjustingID: PersistentDisplayIdentity?
    private(set) var step: Step = .intro
    /// What went wrong last, shown until the next change goes through.
    private(set) var problem: String?
    /// Comparison levels as fractions of the reference's range, fixed once matching starts.
    private(set) var levels: [Double] = []
    /// The displays being matched, reference first, fixed once matching starts.
    private(set) var members: [PersistentDisplayIdentity] = []
    /// Each display's brightness before matching began, put back on Cancel.
    private(set) var originals: [PersistentDisplayIdentity: Double] = [:]
    /// What each display was set to at each comparison point.
    private(set) var chosen: [[PersistentDisplayIdentity: Double]] = []
    private var touched: Set<PersistentDisplayIdentity> = []
    @ObservationIgnored private var writers: [PersistentDisplayIdentity: Task<Void, Never>] = [:]
    @ObservationIgnored private var queued: [PersistentDisplayIdentity: Double] = [:]
    let patches: any MatchPatchPresenting
    private let fixedCandidates: [DisplaySnapshot]?
    @ObservationIgnored var onFinish: (() -> Void)?

    /// `candidates` stands in for the store's displays, for snapshots of a desk with one.
    init(store: GlowStore, patches: any MatchPatchPresenting, candidates: [DisplaySnapshot]? = nil) {
        self.store = store
        self.patches = patches
        fixedCandidates = candidates
        method = store.matchMethod
        let candidates = candidates ?? store.matchCandidates
        referenceID = (candidates.first(where: \.isBuiltIn) ?? candidates.first)?.id
    }

    var candidates: [DisplaySnapshot] { fixedCandidates ?? store.matchCandidates }
    var reference: DisplaySnapshot? { referenceID.flatMap(display) }
    /// The displays being set to look like the reference.
    var adjustable: [DisplaySnapshot] { members.dropFirst().compactMap(display) }

    func display(_ id: PersistentDisplayIdentity) -> DisplaySnapshot? {
        store.displays.first { $0.id == id } ?? fixedCandidates?.first { $0.id == id }
    }

    /// Why matching can't start at all, in words.
    var unavailableReason: String? { Self.unavailableReason(store: store, candidates: candidates) }

    static func unavailableReason(store: GlowStore, candidates: [DisplaySnapshot]) -> String? {
        if store.safeMode && !store.demoMode {
            return "Glow opened in safe mode, so it changes nothing. Quit and reopen Glow to match displays."
        }
        if let pause = store.pauseReason { return "\(pause). Matching can start once they settle." }
        switch candidates.count {
        case 0: return "Matching needs two displays whose brightness Glow can set, and it can’t set any now."
        case 1: return "Matching needs two displays whose brightness Glow can set. Only \(candidates[0].name) can be set now."
        default: return nil
        }
    }

    /// Why the choices made so far can't start, when matching is otherwise possible.
    var startProblem: String? {
        guard method == .quick, let setting = reference?.matchableBrightness,
              let current = setting.matchNumber, setting.matchLevel(of: current) == 0 else { return nil }
        return "\(reference?.name ?? "The reference") is at its lowest. Turn it up a little first, so there’s a brightness to match."
    }

    var canStart: Bool {
        step == .intro && unavailableReason == nil && startProblem == nil && candidates.contains { $0.id == referenceID }
    }

    // MARK: Comparing

    func begin() {
        guard canStart, let reference = candidates.first(where: { $0.id == referenceID }),
              let setting = reference.matchableBrightness, let current = setting.matchNumber else { return }
        let others = candidates.filter { $0.id != reference.id }
        members = [reference.id] + others.map(\.id)
        originals = Dictionary(uniqueKeysWithValues: candidates.compactMap { display in
            display.matchableBrightness?.matchNumber.map { (display.id, $0) }
        })
        levels = method == .quick ? [setting.matchLevel(of: current) ?? 1] : MatchCurve.guidedLevels
        chosen = []
        touched = []
        adjustingID = others.first?.id
        patches.show(candidates.map { MatchPatch(screen: $0.connection.displayID, name: $0.name, isReference: $0.id == reference.id) })
        go(to: 0)
    }

    var pointIndex: Int? {
        if case let .compare(index) = step { index } else { nil }
    }

    /// The reference's level at this point, in its own units.
    func referenceValue(at index: Int) -> Double? {
        referenceID.flatMap { chosen.indices.contains(index) ? chosen[index][$0] : nil }
    }

    /// What a display is set to at the point on show.
    func value(of id: PersistentDisplayIdentity) -> Double? {
        guard let index = pointIndex ?? (step == .review ? levels.count - 1 : nil), chosen.indices.contains(index) else { return nil }
        return chosen[index][id]
    }

    /// Where a display's slider can go at the point on show. In Guided Match it can't go
    /// below where it was at the point before, so the curve never turns back.
    func bounds(of id: PersistentDisplayIdentity) -> ClosedRange<Double>? {
        guard let index = pointIndex, let range = display(id)?.brightnessSetting?.matchRange else { return nil }
        let floor = min(range.maximum, self.floor(of: id, at: index))
        return floor...range.maximum
    }

    func set(_ id: PersistentDisplayIdentity, to proposed: Double) {
        guard let index = pointIndex, id != referenceID, let setting = display(id)?.brightnessSetting,
              let bounds = bounds(of: id), let snapped = setting.matchValue(at: setting.matchLevel(of: proposed) ?? 0) else { return }
        let value = min(bounds.upperBound, max(bounds.lowerBound, snapped))
        adjustingID = id
        guard chosen[index][id] != value else { return }
        chosen[index][id] = value
        send(id, value)
    }

    /// ← and →: one step of the adjusted display's range, or 1 % of it if its steps are finer.
    func nudge(_ steps: Int) {
        guard let id = adjustingID, let range = display(id)?.brightnessSetting?.matchRange, let current = value(of: id) else { return }
        let unit = max(range.step, (range.maximum - range.minimum) / 100)
        set(id, to: current + Double(steps) * unit)
    }

    /// ↑ and ↓: the next display to adjust.
    func selectAdjacent(_ offset: Int) {
        let ids = adjustable.map(\.id)
        guard !ids.isEmpty else { return }
        let current = adjustingID.flatMap { ids.firstIndex(of: $0) } ?? 0
        adjustingID = ids[(current + offset + ids.count) % ids.count]
    }

    func next() {
        switch step {
        case .intro: begin()
        case .compare(let index): index + 1 < levels.count ? go(to: index + 1) : (step = .review)
        default: break
        }
    }

    func back() {
        switch step {
        case .compare(let index) where index > 0: go(to: index - 1)
        case .review: go(to: levels.count - 1)
        default: break
        }
    }

    private func go(to index: Int) {
        problem = nil
        if chosen.count <= index { chosen.append(firstGuess(at: index)) }
        // A change at an earlier point can raise this one's floor.
        for id in members.dropFirst() {
            if let value = chosen[index][id] { chosen[index][id] = max(value, floor(of: id, at: index)) }
        }
        step = .compare(index)
        for id in members {
            guard let value = chosen[index][id], value != display(id)?.brightnessSetting?.matchNumber else { continue }
            send(id, value)
        }
    }

    private func floor(of id: PersistentDisplayIdentity, at index: Int) -> Double {
        let minimum = display(id)?.brightnessSetting?.matchRange?.minimum ?? 0
        guard method == .guided, index > 0, chosen.indices.contains(index - 1) else { return minimum }
        return chosen[index - 1][id] ?? minimum
    }

    /// Where each display starts at a point. Quick Match leaves everything where it is.
    /// Guided Match starts from a display's current match, then from the ratio it took at
    /// the point before, then from the same share of its range as the reference.
    private func firstGuess(at index: Int) -> [PersistentDisplayIdentity: Double] {
        guard let referenceID, let referenceSetting = display(referenceID)?.brightnessSetting else { return [:] }
        if method == .quick { return originals.filter { members.contains($0.key) } }
        let level = levels[index]
        var values: [PersistentDisplayIdentity: Double] = [:]
        values[referenceID] = referenceSetting.matchValue(at: level)
        for id in members.dropFirst() {
            guard let display = display(id), let setting = display.brightnessSetting else { continue }
            var guess = setting.matchValue(at: level)
            if case let .matched(calibration) = store.matchState(of: display), calibration.pair.reference == referenceID {
                guess = setting.matchValue(at: calibration.curve.value(for: level))
            } else if index > 0, let previous = chosen[index - 1][id], let previousLevel = setting.matchLevel(of: previous), levels[index - 1] > 0 {
                guess = setting.matchValue(at: previousLevel / levels[index - 1] * level)
            }
            values[id] = guess.map { max($0, floor(of: id, at: index)) }
        }
        return values
    }

    // MARK: Writing

    /// Sends the latest value for a display, one write at a time: a dragged slider skips
    /// the values in between instead of queueing them.
    private func send(_ id: PersistentDisplayIdentity, _ value: Double) {
        touched.insert(id)
        queued[id] = value
        guard writers[id] == nil else { return }
        writers[id] = Task { [weak self] in await self?.drain(id) }
    }

    private func drain(_ id: PersistentDisplayIdentity) async {
        while !Task.isCancelled, let value = queued.removeValue(forKey: id) {
            do {
                _ = try await store.confirmWrite(displayID: id, capabilityID: .brightness, value: .number(value))
                problem = nil
            } catch let error as ControlError where error == .suspended || error == .staleTopology {
                // Paused for sleep or a display change: try again once displays are back.
                if queued[id] == nil { queued[id] = value }
                try? await Task.sleep(for: .milliseconds(250))
            } catch is CancellationError {
                break
            } catch {
                problem = "\(display(id)?.name ?? "A display") didn’t take that change. \(error.localizedDescription)"
            }
        }
        writers[id] = nil
    }

    private func stopWriters() async {
        queued.removeAll()
        let running = Array(writers.values)
        running.forEach { $0.cancel() }
        for task in running { await task.value }
        writers.removeAll()
    }

    /// Writes each value and waits for the display to confirm it, waiting out a pause for
    /// sleep or a display change for up to 10 seconds. Returns the displays that didn't.
    private func settle(_ targets: [(PersistentDisplayIdentity, Double)]) async -> [String] {
        var failed: [String] = []
        for (id, value) in targets {
            var attempts = 0
            while true {
                do {
                    _ = try await store.confirmWrite(displayID: id, capabilityID: .brightness, value: .number(value))
                    break
                } catch let error as ControlError where attempts < 40 && (store.pauseReason != nil || error == .suspended || error == .staleTopology) {
                    attempts += 1
                    try? await Task.sleep(for: .milliseconds(250))
                } catch {
                    failed.append(display(id)?.name ?? "A display")
                    break
                }
            }
        }
        return failed
    }

    // MARK: Finishing

    /// The curves this run would save: one for each display matched to the reference.
    var calibrations: [MatchCalibration] {
        guard let referenceID, let reference = display(referenceID) else { return [] }
        return adjustable.compactMap { display in
            guard let setting = display.brightnessSetting else { return nil }
            let points = levels.indices.compactMap { index -> CalibrationPoint? in
                guard chosen.indices.contains(index), let value = chosen[index][display.id], let level = setting.matchLevel(of: value) else { return nil }
                return CalibrationPoint(reference: levels[index], display: level)
            }
            let curve = method == .quick
                ? points.first.flatMap { MatchCurve.quick(reference: $0.reference, display: $0.display) }
                : MatchCurve.guided(points)
            return curve.map {
                MatchCalibration(pair: MatchPair(reference: referenceID, display: display.id), curve: $0, method: method,
                                 referenceRoute: reference.brightnessRoute, displayRoute: display.brightnessRoute)
            }
        }
    }

    /// Keeps the match, puts the reference back where it was and each matched display on
    /// its new curve there.
    func save() async {
        guard step == .review else { return }
        let new = calibrations
        guard !new.isEmpty, let referenceID, let original = originals[referenceID] else {
            problem = "Nothing to save: the displays being matched aren’t connected."
            return
        }
        store.brightnessMatch.save(new)
        store.matchMethod = method
        step = .settling
        patches.hide()
        await stopWriters()
        var targets = [(referenceID, original)]
        if let level = display(referenceID)?.brightnessSetting?.matchLevel(of: original) {
            for calibration in new {
                guard let value = display(calibration.pair.display)?.brightnessSetting?.matchValue(at: calibration.curve.value(for: level)) else { continue }
                targets.append((calibration.pair.display, value))
            }
        }
        let failed = await settle(targets)
        finish(problem: failed.isEmpty ? nil : "Match saved, but \(Self.list(failed)) didn’t take the new brightness. Try the brightness keys once displays settle.")
    }

    /// Puts every display matching changed back to its brightness from before, and keeps
    /// nothing. The patches come down first.
    func cancel() async {
        switch step {
        case .intro: finish(problem: nil)
        case .settling, .finished: return
        case .compare, .review:
            step = .settling
            patches.hide()
            await stopWriters()
            let targets = members.filter(touched.contains).compactMap { id in originals[id].map { (id, $0) } }
            let failed = await settle(targets)
            finish(problem: failed.isEmpty ? nil : "\(Self.list(failed)) didn’t go back to its brightness from before. Set it in Settings › Displays.")
        }
    }

    /// Closes after a problem was shown.
    func close() {
        guard step == .finished else { return }
        onFinish?()
    }

    private func finish(problem: String?) {
        patches.hide()
        self.problem = problem
        step = .finished
        if problem == nil { onFinish?() }
    }

    private static func list(_ names: [String]) -> String {
        ListFormatter.localizedString(byJoining: names)
    }
}
