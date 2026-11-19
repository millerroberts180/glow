import AppKit
import Foundation
import Observation

/// Settings › Reading › Keep readings fresh: when Glow looks at each display again
/// (ADR 0002, decision 1).
enum ReadingFreshness: String, CaseIterable, Identifiable, Codable, Sendable {
    case off, whileOpen, always
    var id: Self { self }

    var title: String {
        switch self {
        case .off: "Off"
        case .whileOpen: "While Glow is open"
        case .always: "Always"
        }
    }

    var detail: String {
        switch self {
        case .off: "Glow reads each display when it starts and when you ask. A change made with a display’s own buttons shows up after Read Again."
        case .whileOpen: "While Glow Desk or Settings is open, Glow rereads brightness and volume every few seconds and everything else every minute. Closed, it asks displays nothing."
        case .always: "Every few seconds while Glow Desk or Settings is open. Closed, Glow still rereads brightness and volume every 45 seconds and everything else every 10 minutes."
        }
    }
}

/// Settings › Reading › At launch: what Glow does with each real display when it starts.
enum LaunchReading: String, CaseIterable, Identifiable, Codable, Sendable {
    case read, restore
    var id: Self { self }

    var title: String {
        switch self {
        case .read: "Read each display"
        case .restore: "Put back what Glow last set"
        }
    }

    var detail: String {
        switch self {
        case .read: "Glow reads what each display shows and leaves it as it is."
        case .restore: "Glow puts back the brightness and other settings it last set on each display, where a display shows something else. Input and power are never changed, and holding Shift as Glow opens skips it."
        }
    }
}

/// Settings › Reading › Patience: how long Glow waits for a display to answer, and how
/// many times it asks.
enum ReadingPatience: String, CaseIterable, Identifiable, Codable, Sendable {
    case normal, patient
    var id: Self { self }

    var title: String {
        switch self {
        case .normal: "Normal"
        case .patient: "Patient"
        }
    }

    var detail: String {
        switch self {
        case .normal: "Glow waits as long as each display needed when Glow found it."
        case .patient: "For displays that answer slowly or miss changes: Glow waits longer for each answer and asks up to 7 times. Changes take a moment longer."
        }
    }

    /// The profile reads and writes use on a connection whose discovery found `found`.
    func profile(from found: DDCTransportProfile) -> DDCTransportProfile {
        switch self {
        case .normal: found
        case .patient: found.patient
        }
    }
}

/// Settings › Reading, versioned on its own. Each field decodes alone, so a value from a
/// newer Glow falls back without resetting the others.
struct ReadingSettings: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var freshness: ReadingFreshness = .whileOpen
    var atLaunch: LaunchReading = .read
    var patience: ReadingPatience = .normal

    init() {}

    private enum CodingKeys: String, CodingKey { case version, freshness, atLaunch, patience }

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        freshness = (try? c.decodeIfPresent(ReadingFreshness.self, forKey: .freshness)) ?? freshness
        atLaunch = (try? c.decodeIfPresent(LaunchReading.self, forKey: .atLaunch)) ?? atLaunch
        patience = (try? c.decodeIfPresent(ReadingPatience.self, forKey: .patience)) ?? patience
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        try c.encode(freshness, forKey: .freshness)
        try c.encode(atLaunch, forKey: .atLaunch)
        try c.encode(patience, forKey: .patience)
    }
}

/// What Glow last set and saw confirmed on each real display, kept across launches for "Put
/// back what Glow last set" (ADR 0002, decision 5). Versioned on its own: a display or a
/// value that can't be read is dropped and the rest kept. Input and power are never kept.
struct LastSetValues: Codable, Equatable, Sendable {
    static let currentVersion = 1
    private(set) var displays: [PersistentDisplayIdentity: [CapabilityIdentifier: CapabilityValue]] = [:]

    init() {}

    func values(for identity: PersistentDisplayIdentity) -> [CapabilityIdentifier: CapabilityValue] {
        displays[identity] ?? [:]
    }

    mutating func record(_ values: [CapabilityIdentifier: CapabilityValue], on identity: PersistentDisplayIdentity) {
        let kept = values.filter { !LaunchRestore.neverWritten.contains($0.key) }
        guard !kept.isEmpty else { return }
        displays[identity, default: [:]].merge(kept) { _, new in new }
    }

    private struct Setting: Codable {
        let capability: CapabilityIdentifier
        let value: CapabilityValue
    }

    private struct Display: Codable {
        let identity: PersistentDisplayIdentity
        let settings: [LossyElement<Setting>]
    }

    private enum CodingKeys: String, CodingKey { case version, displays }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let stored = ((try? c.decodeIfPresent([LossyElement<Display>].self, forKey: .displays)) ?? []).compactMap(\.value)
        for display in stored {
            let values = display.settings.compactMap(\.value).map { ($0.capability, $0.value) }
            record(Dictionary(values) { _, last in last }, on: display.identity)
        }
    }

    /// Glow writes what it knows, sorted so the saved form doesn't churn.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        let stored = displays.sorted { $0.key.id < $1.key.id }.map { identity, values in
            Display(identity: identity, settings: values.sorted { $0.key.rawValue < $1.key.rawValue }.map { LossyElement(Setting(capability: $0.key, value: $0.value)) })
        }
        try c.encode(stored, forKey: .displays)
    }
}

/// Settings someone hid on a real display because they do nothing there, by display
/// identity: user-set evidence, shown as "Hidden by you" (ADR 0002, decision 8). Versioned
/// on its own.
struct DisplayCorrections: Codable, Equatable, Sendable {
    static let currentVersion = 1
    private(set) var hidden: [PersistentDisplayIdentity: Set<CapabilityIdentifier>] = [:]

    init() {}

    func hidden(on identity: PersistentDisplayIdentity) -> Set<CapabilityIdentifier> {
        hidden[identity] ?? []
    }

    mutating func hide(_ capability: CapabilityIdentifier, on identity: PersistentDisplayIdentity) {
        hidden[identity, default: []].insert(capability)
    }

    mutating func show(_ capability: CapabilityIdentifier, on identity: PersistentDisplayIdentity) {
        hidden[identity]?.remove(capability)
        if hidden[identity]?.isEmpty == true { hidden[identity] = nil }
    }

    private struct Display: Codable {
        let identity: PersistentDisplayIdentity
        let hidden: [CapabilityIdentifier]
    }

    private enum CodingKeys: String, CodingKey { case version, displays }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let stored = ((try? c.decodeIfPresent([LossyElement<Display>].self, forKey: .displays)) ?? []).compactMap(\.value)
        for display in stored {
            for capability in display.hidden { hide(capability, on: display.identity) }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        let stored = hidden.sorted { $0.key.id < $1.key.id }.map { Display(identity: $0.key, hidden: $0.value.sorted { $0.rawValue < $1.rawValue }) }
        try c.encode(stored, forKey: .displays)
    }
}

/// Decodes one element, or nothing when it can't, so an array keeps its readable members.
private struct LossyElement<Value: Codable>: Codable {
    let value: Value?
    init(_ value: Value) { self.value = value }
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

/// What a reread covers (ADR 0002, decision 1).
enum ReadingScope: Sendable {
    /// Brightness, volume and mute: what people change on the display itself.
    case frequent
    /// Every readable OSD setting.
    case allSettings
    /// Read Again: every setting, and once more each reported code the catalog doesn't know.
    case everything
}

/// When each display was last reread, and how long a silent one is left alone.
struct DisplayReadingClock: Equatable, Sendable {
    var lastFrequent: Date?
    var lastRare: Date?
    /// Passes in a row in which every DDC/CI read went unanswered.
    var silentPasses = 0
    var backoffUntil: Date?
}

/// The reread timetable (ADR 0002, decisions 1 and 3). Pure, so tests drive it with their
/// own clock.
enum ReadingSchedule {
    struct Intervals: Equatable, Sendable {
        let frequent: TimeInterval
        let rare: TimeInterval
    }

    static let open = Intervals(frequent: 5, rare: 60)
    static let background = Intervals(frequent: 45, rare: 600)
    /// The settings the frequent tier rereads.
    static let frequentSettings: Set<CapabilityIdentifier> = [.brightness, .volume, .mute]
    /// How long "Changed on the display" stays on a setting.
    static let markDuration: TimeInterval = 60
    /// Rereads keep this far from Glow's own writes to a display.
    static let writeQuiet: Duration = .seconds(2)

    static func intervals(_ freshness: ReadingFreshness, isOpen: Bool) -> Intervals? {
        switch freshness {
        case .off: nil
        case .whileOpen: isOpen ? open : nil
        case .always: isOpen ? open : background
        }
    }

    /// 30 s after the first silent pass, doubling to 15 min.
    static func backoff(afterSilentPasses passes: Int) -> TimeInterval {
        min(900, 30 * pow(2, Double(max(0, passes - 1))))
    }

    /// What's due on one display at `now`, or nil when nothing is.
    static func due(_ clock: DisplayReadingClock, intervals: Intervals?, now: Date) -> ReadingScope? {
        guard let intervals else { return nil }
        if let until = clock.backoffUntil, now < until { return nil }
        func elapsed(_ since: Date?, _ interval: TimeInterval) -> Bool {
            since.map { now.timeIntervalSince($0) >= interval } ?? true
        }
        if elapsed(clock.lastRare, intervals.rare) { return .allSettings }
        if elapsed(clock.lastFrequent, intervals.frequent) { return .frequent }
        return nil
    }
}

/// One setting's reread, for tests, `--probe-readings` and the reading journal.
struct ReadingOutcome: Equatable, Sendable {
    enum Result: Equatable, Sendable {
        case unchanged
        case changed(from: CapabilityValue?)
        case failed(String)
        case skipped(String)
    }

    let display: PersistentDisplayIdentity
    let capability: CapabilityIdentifier
    let label: String
    var result: Result
    var value: CapabilityValue?
    var milliseconds: Int?

    var wasRead: Bool {
        switch result {
        case .unchanged, .changed: true
        case .failed, .skipped: false
        }
    }
}

/// "Read just now", "Read 3 min ago": how old a display's last full reading is.
enum ReadingAge {
    static func text(since read: Date?, now: Date) -> String {
        guard let read else { return "Not read yet" }
        let seconds = max(0, now.timeIntervalSince(read))
        switch seconds {
        case ..<60: return "Read just now"
        case ..<3_600: return "Read \(Int(seconds / 60)) min ago"
        case ..<7_200: return "Read 1 hour ago"
        case ..<86_400: return "Read \(Int(seconds / 3_600)) hours ago"
        default: return "Read more than a day ago"
        }
    }
}

/// Glow's three launch writes are the only ones reading makes, and they follow Reapply after
/// wake's rules exactly (ADR 0002, decision 5).
enum LaunchRestore {
    /// Never written at launch, whatever was last set.
    static let neverWritten: Set<CapabilityIdentifier> = [.input, .power]

    /// The values to put back, as a scene: Reapply after wake's allowed set and rules, for
    /// the values kept from the last launch. A setting must still be on the display, must not
    /// ask first, and must differ from what the display shows. Demo displays are left out.
    static func scene(from lastSet: LastSetValues, on displays: [DisplaySnapshot]) -> GlowScene {
        let parts = displays.filter { !$0.isDemo }.compactMap { display -> SceneDisplay? in
            let settings = lastSet.values(for: display.id).compactMap { id, value -> SceneSetting? in
                guard !neverWritten.contains(id),
                      let descriptor = display.capabilities.first(where: { $0.id == id }),
                      !descriptor.requiresConfirmation, descriptor.currentValue != value else { return nil }
                return SceneSetting(id, value, describedBy: descriptor)
            }
            .sorted { $0.order(on: display) < $1.order(on: display) }
            return settings.isEmpty ? nil : SceneDisplay(identity: display.id, name: display.name, settings: settings)
        }
        return GlowScene(id: "at-launch", name: "At launch", symbol: "power", displays: parts)
    }
}

/// What reading shares between the store and its views: when each display was last read in
/// full, which are being read now, and the reread loop's state.
@MainActor @Observable
final class ReadingState {
    /// When every setting on each display was last read: discovery, a full pass or Read Again.
    var lastRead: [PersistentDisplayIdentity: Date] = [:]
    /// Displays a Read Again or Read All is reading now.
    var readingNow: Set<PersistentDisplayIdentity> = []
    /// What "Put back what Glow last set" did at launch, if it ran.
    var launchResult: SceneResult?

    @ObservationIgnored var clocks: [PersistentDisplayIdentity: DisplayReadingClock] = [:]
    /// Displays with a pass under way; a second pass for one waits for the next turn.
    @ObservationIgnored var passes: Set<PersistentDisplayIdentity> = []
    @ObservationIgnored var loop: Task<Void, Never>?
    @ObservationIgnored var launchActionDone = false
    @ObservationIgnored var tracksLastSet = false
    /// The clock schedules run on. Tests replace it.
    @ObservationIgnored var now: @MainActor () -> Date = { Date() }
    /// Whether Glow Desk or a Glow window is showing. Tests replace it.
    @ObservationIgnored var isGlowOpen: @MainActor () -> Bool = { GlowVisibility.isOpen() }
    /// How far rereads keep from Glow's own writes, on the real clock.
    @ObservationIgnored var writeQuiet = ReadingSchedule.writeQuiet
    /// The last rereads, newest last.
    @ObservationIgnored private(set) var journal: [ReadingOutcome] = []

    func note(_ outcomes: [ReadingOutcome]) {
        journal = Array((journal + outcomes).suffix(200))
    }
}

/// Whether any of Glow is on screen: Glow Desk, Settings, setup or a Brightness Match
/// window. The menu-bar mark and the overlay, which ignores the mouse, don't count.
@MainActor
enum GlowVisibility {
    static func isOpen() -> Bool {
        guard let app = NSApp else { return false }
        return app.windows.contains { window in
            window.isVisible && !window.ignoresMouseEvents && window.className != "NSStatusBarWindow"
        }
    }
}

extension DDCTransportProfile {
    /// Patience's version of a profile: the same address and sends, with waits and tries
    /// raised to at least Slower timing's (ADR 0002, decision 6).
    var patient: DDCTransportProfile {
        var profile = self
        profile.writeWait = max(writeWait, .milliseconds(20))
        profile.readWait = max(readWait, .milliseconds(120))
        profile.settleAfterSet = max(settleAfterSet, .milliseconds(100))
        profile.retries = max(retries, 6)
        profile.retryWait = max(retryWait, .milliseconds(100))
        profile.retryWindow = max(retryWindow, .seconds(3))
        return profile
    }
}

extension CapabilityDescriptor {
    /// A setting rereads look at: one that read successfully at discovery, over the display's
    /// own control or macOS's. Software dimming is Glow's own state, and text facts come back
    /// with rediscovery.
    var isRereadable: Bool {
        guard access.canRead, [.safelyProbed, .answeredUnlisted].contains(evidence) else { return false }
        switch route {
        case .hardware:
            if case .action = kind { return false }
            return presentation != .connectionDetailsOnly && CapabilityCatalog.entry(for: id) != nil
        case .native:
            return id == .brightness
        case .software, .unavailable:
            return false
        }
    }

    /// Why a reread's value can't be shown, or nil when Glow can trust it. It must fit the
    /// setting the way discovery's reading did. macOS's brightness of exactly 0 isn't believed
    /// either: DisplayServices has answered 0 for a lit built-in screen (QA_REPORT.md,
    /// "Built-in brightness reading"). Glow keeps the last reading instead.
    func distrust(_ value: CapabilityValue) -> String? {
        switch (kind, value) {
        case let (.range(minimum, maximum, _), .number(number)):
            guard number.isFinite, (minimum...maximum).contains(number) else { return "The reading was outside the setting’s range" }
            if route == .native, id == .brightness, number == 0 { return "macOS answered 0, which Glow doesn’t trust" }
            return nil
        case (.options, .text), (.toggle, .boolean), (.text, .text):
            return nil
        default:
            return "The reading didn’t fit the setting"
        }
    }

    /// A setting someone can hide on a real display: one the display itself reports, shown in
    /// the OSD.
    var canBeHidden: Bool { presentation == .osd && rawCode != nil }

    /// "Changed on the display", or for macOS's own control "Changed outside Glow".
    var changeMarkTitle: String { route == .native ? "Changed outside Glow" : "Changed on the display" }
}

extension DisplaySnapshot {
    /// What a pass of `scope` rereads, in OSD order. Hidden settings wait for Read Again.
    func rereadable(_ scope: ReadingScope) -> [CapabilityDescriptor] {
        capabilities
            .filter { descriptor in
                guard descriptor.isRereadable else { return false }
                switch scope {
                case .frequent: return descriptor.presentation == .osd && ReadingSchedule.frequentSettings.contains(descriptor.id)
                case .allSettings: return descriptor.presentation == .osd
                case .everything: return true
                }
            }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Reported codes the catalog doesn't know that Read Again reads once more.
    var reportedUncatalogued: [CapabilityDescriptor] {
        capabilities.filter { $0.reportedCode.map(CapabilityCatalog.readsOnce) ?? false }
    }
}
