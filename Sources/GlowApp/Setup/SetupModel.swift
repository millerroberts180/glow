import Foundation
import Observation

/// The first-run setup, in order: your displays as Glow Desk shows them, matching their
/// brightness with Quick Match, the brightness keys and their permission, then open at
/// login. Reopened from Settings › General it runs as a tutorial: the same steps, without
/// the permission or open at login.
@MainActor @Observable
final class SetupModel {
    enum Step: String, CaseIterable {
        /// The connected displays, in Glow Desk's own rows, and where Glow Desk is.
        case displays
        /// Quick Match, when two or more displays can be set.
        case match
        /// The brightness keys: the permission, then a press that Glow handles.
        case keys
        /// Open at login.
        case finish
    }

    /// Where the match step is.
    enum MatchStage: Hashable {
        /// Matching can't start now, as while displays sleep.
        case unavailable(String)
        /// Choosing the reference.
        case pick
        /// Comparing, with the grey patches up.
        case adjust
        /// Saving, or putting displays back.
        case settling
        /// Saved: the displays look alike and move together.
        case matched
        /// A display didn't go back to its brightness from before.
        case problem(String)
    }

    let tutorialOnly: Bool
    var step: Step {
        didSet { stepChanged(from: oldValue) }
    }
    /// Applied on finish, and only if it differs from what macOS already has.
    var openAtLogin: Bool
    /// Whether macOS lets Glow see the brightness keys. Rechecked once a second while the
    /// keys step shows, and on every step change.
    private(set) var accessGranted: Bool

    let store: GlowStore
    let login: SetupLogin
    let permission: KeyPermission
    /// This visit's Quick Match, made fresh each time the match step starts over. It's the
    /// same session the calibration window runs, so it saves exactly as Settings does.
    private(set) var match: MatchSession?
    /// Set once this setup saves a match, so the step shows it done until it's run again.
    private(set) var matched = false
    /// Why the last Save didn't go through, shown until the next change.
    private(set) var saveProblem: String?
    /// For snapshots: what the displays step shows instead of the store's displays.
    var deskOverride: YourDesk?
    @ObservationIgnored var onFinish: (() -> Void)?
    /// Called with true when the grey patches go up and false when they come down, so the
    /// window can rise above them.
    @ObservationIgnored var onPatchesChange: ((Bool) -> Void)?
    /// The last save, cancel or restore setup started, so tests can wait for it.
    @ObservationIgnored private(set) var work: Task<Void, Never>?
    @ObservationIgnored private let makePatches: @MainActor (GlowStore) -> any MatchPatchPresenting
    @ObservationIgnored private var accessTimer: Timer?
    /// Glow Desk's openings and the key presses Glow took before this setup opened, so
    /// only what happens while it's open ticks a step off.
    private let deskOpensBefore: Int
    private let keyPressesBefore: Int

    /// `patches` puts up the grey patches for a match: on each screen, or for demo
    /// displays nowhere, as the calibration window does.
    init(store: GlowStore, login: SetupLogin, tutorialOnly: Bool, permission: KeyPermission = .live,
         patches: @escaping @MainActor (GlowStore) -> any MatchPatchPresenting = SetupModel.livePatches) {
        self.store = store
        self.login = login
        self.tutorialOnly = tutorialOnly
        self.permission = permission
        makePatches = patches
        accessGranted = permission.isGranted()
        step = .displays
        deskOpensBefore = store.glowDeskOpens
        keyPressesBefore = store.keyPressesMoved
        // On by default the first time, where macOS allows it; afterwards, what macOS says.
        openAtLogin = login.isOn() || (login.canRegister && !store.settings.value.hasCompletedSetup)
    }

    /// The steps this run shows. Matching needs two displays Glow can set; the tutorial
    /// shows the keys only when Glow takes them, since it never asks for the permission.
    nonisolated static func steps(tutorialOnly: Bool, canMatch: Bool, keysReachGlow: Bool) -> [Step] {
        var steps: [Step] = [.displays]
        if canMatch { steps.append(.match) }
        if !tutorialOnly {
            steps += [.keys, .finish]
        } else if keysReachGlow {
            steps.append(.keys)
        }
        return steps
    }

    /// The steps for the desk as it is now. The step on show stays listed, so Back and the
    /// dots still make sense if a display leaves while it's open.
    var steps: [Step] {
        let wanted = Self.steps(tutorialOnly: tutorialOnly, canMatch: store.matchCandidates.count > 1 || matched, keysReachGlow: keysReachGlow)
        return Step.allCases.filter { wanted.contains($0) || $0 == step }
    }

    static func livePatches(_ store: GlowStore) -> any MatchPatchPresenting {
        // Demo displays aren't real screens, so the window draws their patches instead.
        store.isDemoData ? WindowOnlyPatches() : ScreenPatches()
    }

    var isFirst: Bool { step == steps.first }
    var isLast: Bool { step == steps.last }
    var stepNumber: Int { (steps.firstIndex(of: step) ?? 0) + 1 }

    // MARK: Moving between steps

    /// The footer's main button.
    var primaryTitle: String {
        switch step {
        case .match where matchStage == .pick: return "Start Matching"
        case .match where matchStage == .adjust || matchStage == .settling: return "Save Match"
        default: return isLast ? (tutorialOnly ? "Done" : "Start Using Glow") : "Continue"
        }
    }

    var canGoOn: Bool {
        guard step == .match else { return true }
        switch matchStage {
        case .pick: return match?.canStart ?? false
        case .settling: return false
        default: return true
        }
    }

    /// The footer's main button: start or save the match on the match step, otherwise on.
    func primary() {
        guard step == .match else { return next() }
        switch matchStage {
        case .pick: startMatch()
        case .adjust: work = Task { await saveMatch() }
        case .settling: break
        default: next()
        }
    }

    func next() {
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return finish() }
        step = steps[index + 1]
    }

    /// Back a step. Leaving a match part way puts every display back first.
    func back() {
        guard let index = steps.firstIndex(of: step), index > 0 else { return }
        step = steps[index - 1]
    }

    func finish() {
        stopWatchingAccess()
        leaveMatch()
        if !tutorialOnly, login.canRegister, openAtLogin != login.isOn() {
            login.set(openAtLogin)
        }
        markSeen()
        onFinish?()
    }

    /// The window closed, on whatever step: a match part way is put back, as Cancel does.
    func close() {
        stopWatchingAccess()
        leaveMatch()
        markSeen()
    }

    /// Closing counts as seen too: setup opens by itself once, and the tutorial stays in
    /// Settings › General.
    func markSeen() {
        guard !tutorialOnly, !store.settings.value.hasCompletedSetup else { return }
        store.settings.value.hasCompletedSetup = true
        store.settings.flush()
    }

    private func stepChanged(from old: Step) {
        // Granted in System Settings while on another step still counts.
        accessGranted = permission.isGranted()
        if step == .keys { watchAccess() } else { stopWatchingAccess() }
        guard step != old else { return }
        if old == .match { leaveMatch() }
        if step == .match, !matched { startOver() }
    }

    // MARK: Matching

    var matchStage: MatchStage {
        if matched { return .matched }
        guard let match else { return .pick }
        switch match.step {
        case .intro:
            if let reason = match.unavailableReason { return .unavailable(reason) }
            return .pick
        case .compare, .review: return .adjust
        case .settling: return .settling
        case .finished: return match.problem.map(MatchStage.problem) ?? .pick
        }
    }

    /// Whether the grey patches are up and displays are being changed.
    var isMatching: Bool { step == .match && (matchStage == .adjust || matchStage == .settling) }

    /// Not Now, beside Start Matching: on without matching.
    var showsNotNow: Bool { step == .match && matchStage == .pick }

    /// Puts up the patches and starts comparing, at the reference's brightness now.
    func startMatch() {
        guard let match, match.canStart else { return }
        saveProblem = nil
        match.begin()
    }

    /// Keeps the match, as Settings › Brightness Match saves it, and moves the matched
    /// displays together from the reference's slider too. Settings › Brightness Match can
    /// turn that off.
    func saveMatch() async {
        guard let match, isMatching, match.step != .settling else { return }
        if match.pointIndex != nil { match.next() }
        await match.save()
        switch match.step {
        case .settling, .finished:
            store.moveMatchedTogether = true
            matched = true
        default:
            // Nothing could be saved: back to comparing, with why.
            saveProblem = match.problem
            match.back()
        }
    }

    /// Takes the patches down and puts every display back where it was, then offers the
    /// choice of reference again.
    func cancelMatch() async {
        guard let match else { return }
        saveProblem = nil
        await match.cancel()
        if match.problem == nil { startOver() }
    }

    /// Cancel, from the footer or Esc.
    func cancel() {
        work = Task { await cancelMatch() }
    }

    /// A fresh Quick Match, for the first visit, after Cancel, or to match again.
    func startOver() {
        saveProblem = nil
        matched = false
        let session = MatchSession(store: store, patches: SetupPatches(makePatches(store)) { [weak self] in self?.onPatchesChange?($0) })
        session.method = .quick
        match = session
    }

    /// Leaving the step, or the window: a match part way is cancelled, putting every
    /// display back.
    private func leaveMatch() {
        guard let match, match.step != .intro, match.step != .finished, match.step != .settling else { return }
        saveProblem = nil
        work = Task { await match.cancel() }
    }

    // MARK: Glow Desk and the keys

    /// Glow Desk opened from the menu bar while setup is open.
    var openedGlowDesk: Bool { store.glowDeskOpens > deskOpensBefore }

    /// A brightness key changed a display while setup is open.
    var pressedKey: Bool { store.keyPressesMoved > keyPressesBefore }

    /// Why a brightness key goes to macOS rather than Glow now, in Glow Desk's words, or
    /// nil when Glow takes it. The same cases as `BrightnessKeyRouting`.
    var keysLeftToMacOS: String? {
        if store.demoMode { return "With demo displays on, the keys work as they do without Glow." }
        if store.safeMode { return "In safe mode, the keys work as they do without Glow." }
        if store.controlTarget == .macOnly { return "With Mac chosen for the brightness keys in Glow Desk, the keys work as they do without Glow." }
        if store.displays.isEmpty { return "Once Glow finds your displays, the keys change them." }
        return nil
    }

    /// Glow can see the keys and takes them.
    var keysReachGlow: Bool { accessGranted && keysLeftToMacOS == nil }

    /// What a brightness key changes now, as Glow Desk's Brightness keys choose.
    var keysChange: String {
        switch store.controlTarget {
        case .all: return "every display"
        case .underCursor: return "the display under the pointer"
        case .macOnly: return "the Mac’s own display"
        case .focused:
            // As the keys pick it: the chosen display, or else the first external one.
            let focused = store.displays.first { $0.id == store.focusedDisplayID } ?? store.displays.first { !$0.isBuiltIn }
            return focused?.name ?? "the focused display"
        }
    }

    // MARK: Permission

    /// Set once Allow… is clicked, so the step can say where to turn it on.
    private(set) var askedForAccess = false

    /// macOS's prompt, then System Settings. The step notices the grant by itself.
    func requestAccess() {
        askedForAccess = true
        permission.request()
        watchAccess()
    }

    var isWatchingAccess: Bool { accessTimer != nil }

    /// One look at the grant: what the timer runs once a second.
    func checkAccess() {
        accessGranted = permission.isGranted()
        if accessGranted { stopWatchingAccess() }
    }

    /// System Settings doesn't say when access is granted: look once a second. In the
    /// common modes, so it keeps going while a menu is open.
    private func watchAccess() {
        checkAccess()
        guard accessTimer == nil, !accessGranted else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAccess() }
        }
        RunLoop.main.add(timer, forMode: .common)
        accessTimer = timer
    }

    private func stopWatchingAccess() {
        accessTimer?.invalidate()
        accessTimer = nil
    }
}

/// How setup checks and asks for Accessibility, through `KeyAccess`, so tests and
/// snapshots can stand in for macOS.
struct KeyPermission {
    var isGranted: @MainActor () -> Bool
    var request: @MainActor () -> Void
    /// False under `swift run`, where the grant goes to the terminal app instead.
    var isBundledApp: @MainActor () -> Bool

    static var live: KeyPermission {
        KeyPermission(isGranted: { KeyAccess.isGranted }, request: { KeyAccess.request() }, isBundledApp: { KeyAccess.isBundledApp })
    }
}

/// Open at login as setup sees it, through `LoginItem`, so tests can stand in for macOS.
struct SetupLogin {
    /// False under `swift run`, where macOS can't add Glow to Login Items.
    var canRegister: Bool
    var isOn: @MainActor () -> Bool
    /// What Settings › General says about it, for when it can't be changed.
    var detail: @MainActor () -> String
    var set: @MainActor (Bool) -> Void

    @MainActor static func live(_ item: LoginItem) -> SetupLogin {
        SetupLogin(canRegister: item.canRegister, isOn: { item.isOn }, detail: { item.detail }, set: { item.set($0) })
    }
}

/// The match's patches, passed on to the real ones, telling setup when they go up on the
/// screens and when they come down.
@MainActor
final class SetupPatches: MatchPatchPresenting {
    private let inner: any MatchPatchPresenting
    private let onChange: (Bool) -> Void

    init(_ inner: any MatchPatchPresenting, onChange: @escaping (Bool) -> Void) {
        self.inner = inner
        self.onChange = onChange
    }

    var showsOnScreens: Bool { inner.showsOnScreens }

    func show(_ patches: [MatchPatch]) {
        inner.show(patches)
        if inner.showsOnScreens { onChange(true) }
    }

    func hide() {
        inner.hide()
        onChange(false)
    }
}
