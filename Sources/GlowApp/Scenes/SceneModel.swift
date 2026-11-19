import Foundation

/// A saved set of display settings that Glow puts back in one click. Values are kept per
/// display, by its persistent identity so a scene outlives reconnecting, and per setting.
struct GlowScene: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var name: String
    var symbol: String
    var displays: [SceneDisplay]

    init(id: String = UUID().uuidString, name: String, symbol: String, displays: [SceneDisplay]) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.displays = displays
    }

    /// A scene from plain values, labelled from the displays given; for examples and tests.
    init(id: String, name: String, symbol: String, values: [PersistentDisplayIdentity: [CapabilityIdentifier: CapabilityValue]], on known: [DisplaySnapshot]) {
        let parts = values.map { identity, settings in
            let display = known.first(where: { $0.id == identity })
            return SceneDisplay(
                identity: identity,
                name: display?.name ?? "A display",
                settings: settings.map { id, value in SceneSetting(id, value, describedBy: display?.capabilities.first(where: { $0.id == id })) }
                    .sorted { $0.order(on: display) < $1.order(on: display) }
            )
        }
        self.init(id: id, name: name, symbol: symbol, displays: parts.sorted { first, second in
            (known.firstIndex(where: { $0.id == first.identity }) ?? .max) < (known.firstIndex(where: { $0.id == second.identity }) ?? .max)
        })
    }

    private enum CodingKeys: String, CodingKey { case id, name, symbol, displays }

    /// Each display and setting on its own: a damaged one, or one a newer Glow wrote, is left
    /// out without costing the rest.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Scene"
        symbol = (try? c.decodeIfPresent(String.self, forKey: .symbol)) ?? SceneSymbol.fallback
        displays = ((try? c.decodeIfPresent([Lossy<SceneDisplay>].self, forKey: .displays)) ?? []).compactMap(\.value)
    }

    var settingCount: Int { displays.reduce(0) { $0 + $1.settings.count } }

    func part(for identity: PersistentDisplayIdentity) -> SceneDisplay? {
        displays.first(where: { $0.identity == identity })
    }

    /// True while every setting the scene has on a connected display is at the scene's
    /// value, and at least one such display is connected. Derived, never stored, so it stops
    /// being true the moment someone moves a slider.
    func isCurrent(on connected: [DisplaySnapshot]) -> Bool {
        var compared = 0
        for part in displays {
            guard let display = connected.first(where: { $0.id == part.identity && $0.isConnected }) else { continue }
            for setting in part.settings {
                guard let descriptor = display.capabilities.first(where: { $0.id == setting.capability }),
                      descriptor.isSafelyEditable, descriptor.risk != .destructive else { continue }
                guard descriptor.currentValue == setting.value else { return false }
                compared += 1
            }
        }
        return compared > 0
    }
}

/// One display's part of a scene. Its name is remembered so the scene can say which
/// display it's waiting for while that one is away.
struct SceneDisplay: Hashable, Codable, Sendable {
    var identity: PersistentDisplayIdentity
    var name: String
    var settings: [SceneSetting]

    private enum CodingKeys: String, CodingKey { case identity, name, settings }

    init(identity: PersistentDisplayIdentity, name: String, settings: [SceneSetting]) {
        self.identity = identity
        self.name = name
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identity = try c.decode(PersistentDisplayIdentity.self, forKey: .identity)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "A display"
        settings = ((try? c.decodeIfPresent([Lossy<SceneSetting>].self, forKey: .settings)) ?? []).compactMap(\.value)
    }

    func setting(_ id: CapabilityIdentifier) -> SceneSetting? { settings.first(where: { $0.capability == id }) }
}

/// One setting's value in a scene. The label and unit are remembered for when the display
/// isn't connected; while it is, the display's own descriptor speaks for it.
struct SceneSetting: Hashable, Codable, Sendable {
    var capability: CapabilityIdentifier
    var value: CapabilityValue
    var label: String
    var unit: String?

    init(capability: CapabilityIdentifier, value: CapabilityValue, label: String, unit: String?) {
        self.capability = capability
        self.value = value
        self.label = label
        self.unit = unit
    }

    init(_ capability: CapabilityIdentifier, _ value: CapabilityValue, describedBy descriptor: CapabilityDescriptor?) {
        self.init(capability: capability, value: value,
                  label: descriptor?.label ?? CapabilityCatalog.entry(for: capability)?.label ?? capability.rawValue,
                  unit: descriptor?.unit)
    }

    private enum CodingKeys: String, CodingKey { case capability, value, label, unit }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        capability = try c.decode(CapabilityIdentifier.self, forKey: .capability)
        value = try c.decode(CapabilityValue.self, forKey: .value)
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? CapabilityCatalog.entry(for: capability)?.label ?? capability.rawValue
        unit = try? c.decodeIfPresent(String.self, forKey: .unit)
    }

    /// "Brightness 68%", in the display's words when it's connected.
    func text(on display: DisplaySnapshot?) -> String {
        let descriptor = display?.capabilities.first(where: { $0.id == capability })
        return "\(descriptor?.label ?? label) \(value.description)\(descriptor?.unit ?? unit ?? "")"
    }

    /// Where the setting sits in the display's OSD, section first, so a scene reads in the
    /// same order.
    func order(on display: DisplaySnapshot?) -> Int {
        let descriptor = display?.capabilities.first(where: { $0.id == capability })
        let entry = CapabilityCatalog.entry(for: capability)
        guard let category = descriptor?.category ?? entry?.category,
              let position = descriptor?.sortOrder ?? entry?.order else { return .max }
        return (CapabilityCategory.allCases.firstIndex(of: category) ?? 0) * 10_000 + position
    }

    /// Whether a change to this setting asks first, by the connected display's word or,
    /// while it's away, the catalog's.
    func asksFirst(on display: DisplaySnapshot?) -> Bool {
        let risk = display?.capabilities.first(where: { $0.id == capability })?.risk ?? CapabilityCatalog.entry(for: capability)?.risk ?? .none
        return risk != .none
    }
}

/// The person's own scenes, as saved in `GlowSettings`. Versioned on its own, so the scene
/// format can grow without touching the other settings.
struct SceneLibrary: Hashable, Codable, Sendable {
    static let currentVersion = 1
    var version = SceneLibrary.currentVersion
    var scenes: [GlowScene] = []

    init(scenes: [GlowScene] = []) { self.scenes = scenes }

    private enum CodingKeys: String, CodingKey { case version, scenes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? Self.currentVersion
        scenes = ((try? c.decodeIfPresent([Lossy<GlowScene>].self, forKey: .scenes)) ?? []).compactMap(\.value)
    }

    /// Glow writes what it knows, so a library read from a newer version is saved back as this one.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        try c.encode(scenes, forKey: .scenes)
    }
}

/// Decodes one element, or nothing when it can't, so an array keeps its readable members.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

/// The symbols a scene can wear, each with a name for VoiceOver and the picker.
enum SceneSymbol {
    static let fallback = "sparkles"
    static let all: [(symbol: String, name: String)] = [
        ("briefcase", "Work"), ("moon", "Night"), ("sun.max", "Day"), ("play.rectangle", "Present"),
        ("film", "Film"), ("gamecontroller", "Game"), ("book", "Read"), ("paintpalette", "Color"), ("sparkles", "Other")
    ]

    static func name(of symbol: String) -> String? { all.first { $0.symbol == symbol }?.name }

    /// The name a scene takes from its symbol while its name is automatic: "Night" for the
    /// moon. Other gives none, and the scene keeps its default name: "Other" is the picker's
    /// word for "none of these", and says nothing about a scene.
    static func sceneName(for symbol: String) -> String? {
        symbol == fallback ? nil : name(of: symbol)
    }
}

extension GlowScene {
    /// "New Scene", or "New Scene 2" to "New Scene 99", as Glow names a new scene.
    static func isNewSceneName(_ name: String) -> Bool {
        let base = "New Scene"
        guard name.hasPrefix(base) else { return false }
        let rest = name.dropFirst(base.count)
        guard !rest.isEmpty else { return true }
        guard rest.first == " ", let number = Int(rest.dropFirst()) else { return false }
        return (2...99).contains(number)
    }

    /// The name the editor goes back to when a symbol gives none: a new scene's starting
    /// name, or "New Scene" for a saved one unless its name is already like that.
    static func defaultName(startingFrom name: String, isNew: Bool) -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return isNew || isNewSceneName(name) ? name : "New Scene"
    }

    /// Whether the name is still Glow's own rather than one the person typed: empty, a new
    /// scene's default, or the current symbol's name. Read from the name itself, so a saved
    /// scene behaves the same with no flag stored.
    func hasAutomaticName(defaultName: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name == defaultName || Self.isNewSceneName(name) || name == SceneSymbol.name(of: symbol)
    }

    /// Wears a symbol. An automatic name follows it; a name the person typed stays.
    mutating func wear(_ symbol: String, defaultName: String) {
        if hasAutomaticName(defaultName: defaultName) {
            name = SceneSymbol.sceneName(for: symbol) ?? defaultName
        }
        self.symbol = symbol
    }
}

/// How much of a scene took: written and confirmed, refused, and what was never tried and why.
struct SceneResult: Equatable, Sendable {
    var succeeded: Int
    var failed: Int
    /// Settings a connected display doesn't offer, or can't change on this connection, and
    /// destructive ones (display power), which a scene never applies.
    var skipped = 0
    /// Changes that ask first, such as a new input, that the person chose not to make.
    var heldBack = 0
    /// Displays in the scene that aren't connected; nothing was sent to them.
    var missingDisplays = 0

    var summary: String { summary(done: "Applied") }

    /// "Applied 2; 1 couldn’t be updated", or with another verb such as "Restored".
    func summary(done verb: String) -> String {
        guard succeeded + failed > 0 else {
            if missingDisplays > 0, skipped == 0, heldBack == 0 { return "None of this scene’s displays are connected" }
            return heldBack > 0 && skipped == 0 ? "Nothing changed" : "Nothing to change on the displays connected now"
        }
        if failed == 0 {
            if verb == "Applied" { return succeeded == 1 ? "Applied to 1 setting" : "Applied to \(succeeded) settings" }
            return succeeded == 1 ? "\(verb) 1 setting" : "\(verb) \(succeeded) settings"
        }
        return "\(verb) \(succeeded); \(failed) couldn’t be updated"
    }

    /// What wasn't tried, when anything wasn't: "1 skipped: not on this connection · 1 display
    /// isn’t connected". Nil when everything was tried.
    var detail: String? {
        var parts: [String] = []
        if skipped > 0 { parts.append("\(skipped) skipped: not on this connection") }
        if heldBack > 0 { parts.append("\(heldBack) left as it was") }
        if missingDisplays > 0, succeeded + failed + skipped + heldBack > 0 {
            parts.append(missingDisplays == 1 ? "1 display isn’t connected" : "\(missingDisplays) displays aren’t connected")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var tone: StatusTone {
        if failed > 0 { return succeeded == 0 ? .danger : .warning }
        return succeeded > 0 ? .success : .neutral
    }
}
