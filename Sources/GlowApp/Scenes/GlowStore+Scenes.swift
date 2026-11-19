import Foundation
import Observation

/// What the scenes UI shares between Glow Desk and Settings: the demo's examples, the last
/// result of each scene and of each restore, the scene applying now and the one being edited.
@MainActor @Observable
final class SceneState {
    /// Example scenes for the demo displays. Kept in memory only: never saved, and never
    /// shown beside the person's own.
    var demoScenes = DemoScenes.examples
    var results: [String: SceneResult] = [:]
    /// The scene applied most recently, for Glow Desk's one-line result.
    var lastApplied: String?
    var restoreResults: [PersistentDisplayIdentity: SceneResult] = [:]
    /// The scene, or the display's starting values, being written now.
    var applying: String?
    /// The scene open in the editor. Glow Desk sets it for "New Scene…", then opens Settings.
    var draft: SceneDraft?
}

/// A scene in the editor: a copy, saved only when the person chooses Save.
struct SceneDraft: Identifiable {
    var scene: GlowScene
    let isNew: Bool
    var id: String { scene.id }
}

extension GlowStore {
    /// The scenes on show: the person's own, or the demo's examples while demo displays are
    /// on. Never both, so a demo scene can't be saved over a real one.
    var scenes: [GlowScene] {
        get { demoMode ? sceneState.demoScenes : settings.value.sceneLibrary.scenes }
        set {
            if demoMode { sceneState.demoScenes = newValue } else { settings.value.sceneLibrary.scenes = newValue }
        }
    }

    /// The scene the displays match now, if any.
    var activeScene: GlowScene? { scenes.first { $0.isCurrent(on: displays) } }

    /// Whether Apply can do anything at all: not while writes are paused, and not in safe
    /// mode, where every write is refused.
    var canApplyScenes: Bool { pauseReason == nil && (demoMode || !safeMode) && sceneState.applying == nil }

    var reapplyAfterWake: Bool {
        get { settings.value.reapplyAfterWake }
        set { settings.value.reapplyAfterWake = newValue }
    }

    // MARK: - Managing

    /// A new, unsaved scene from what every display shows now, named so it doesn't clash.
    func newSceneFromCurrentSettings() -> GlowScene {
        let taken = Set(scenes.map(\.name))
        let name = (["New Scene"] + (2...99).map { "New Scene \($0)" }).first { !taken.contains($0) } ?? "New Scene"
        return GlowScene.capturing(displays, name: name)
    }

    /// Opens the editor on a new scene from current settings.
    func beginNewScene() {
        sceneState.draft = SceneDraft(scene: newSceneFromCurrentSettings(), isNew: true)
    }

    /// Adds the scene, or replaces the one with its ID. Displays left with nothing to set
    /// are dropped.
    func saveScene(_ scene: GlowScene) {
        var scene = scene
        scene.name = scene.name.trimmingCharacters(in: .whitespacesAndNewlines)
        scene.displays.removeAll { $0.settings.isEmpty }
        if let index = scenes.firstIndex(where: { $0.id == scene.id }) {
            scenes[index] = scene
        } else {
            scenes.append(scene)
        }
        sceneState.results[scene.id] = nil
    }

    func deleteScene(id: String) {
        scenes.removeAll { $0.id == id }
        sceneState.results[id] = nil
        if sceneState.lastApplied == id { sceneState.lastApplied = nil }
    }

    /// Moves a scene up (negative) or down (positive) the list, stopping at the ends.
    func moveScene(id: String, by offset: Int) {
        guard let index = scenes.firstIndex(where: { $0.id == id }) else { return }
        let target = min(scenes.count - 1, max(0, index + offset))
        guard target != index else { return }
        var reordered = scenes
        reordered.insert(reordered.remove(at: index), at: target)
        scenes = reordered
    }

    // MARK: - Applying

    /// Applies a scene through the write pipeline, one confirmed write at a time, and
    /// reports exactly how much took. Without `includingAsksFirst`, a change that would ask
    /// first (a new input) is left as it is; the caller asks before passing true.
    @discardableResult
    func applyScene(_ scene: GlowScene, includingAsksFirst: Bool = false) async -> SceneResult {
        sceneState.applying = scene.id
        defer { sceneState.applying = nil }
        let result = await write(scene, includingAsksFirst: includingAsksFirst)
        sceneState.results[scene.id] = result
        sceneState.lastApplied = scene.id
        showMessage(result.summary)
        return result
    }

    /// The confirmation a scene needs before it's applied, or nil when it can go straight on.
    func confirmation(for scene: GlowScene) -> SceneConfirmation? {
        let changes = scene.plan(on: displays).confirmations
        return changes.isEmpty ? nil : SceneConfirmation(scene: scene, changes: changes)
    }

    /// Every scene-shaped write, from a scene, a restore or after wake, goes this way: checked
    /// against the displays connected now, then written and read back one setting at a time.
    private func write(_ scene: GlowScene, includingAsksFirst: Bool) async -> SceneResult {
        await SceneApplier.apply(scene.plan(on: displays), includingAsksFirst: includingAsksFirst) { write in
            _ = try await confirmWrite(displayID: write.display, capabilityID: write.capability, value: write.value)
        }
    }

    // MARK: - Starting values (ADR 0001, decision 9)

    /// The values Glow read from a display when it first found it this launch, before it
    /// changed anything. Only settings it read and could change are kept.
    func startingValues(for identity: PersistentDisplayIdentity) -> [CapabilityIdentifier: CapabilityValue] {
        demoMode ? DemoScenes.startingValues[identity] ?? [:] : adapter.startingValues(for: identity)
    }

    /// The starting values that differ from what the display shows now, as a scene of its
    /// own, so restoring them goes through the same checks, confirmations and pipeline.
    func startingScene(for display: DisplaySnapshot) -> GlowScene {
        let settings = startingValues(for: display.id)
            .compactMap { id, value -> SceneSetting? in
                let descriptor = display.capabilities.first(where: { $0.id == id })
                guard descriptor?.currentValue != value else { return nil }
                return SceneSetting(id, value, describedBy: descriptor)
            }
            .sorted { $0.order(on: display) < $1.order(on: display) }
        return GlowScene(id: "starting-\(display.id.id)", name: "Starting values", symbol: "arrow.uturn.backward",
                         displays: settings.isEmpty ? [] : [SceneDisplay(identity: display.id, name: display.name, settings: settings)])
    }

    @discardableResult
    func restoreStartingValues(of display: DisplaySnapshot, includingAsksFirst: Bool = false) async -> SceneResult {
        // Compared with what the display shows now, not with a snapshot from when a button
        // or a confirmation was drawn.
        let scene = startingScene(for: displays.first(where: { $0.id == display.id }) ?? display)
        sceneState.applying = scene.id
        defer { sceneState.applying = nil }
        let result = await write(scene, includingAsksFirst: includingAsksFirst)
        sceneState.restoreResults[display.id] = result
        showMessage(result.summary(done: "Restored"))
        return result
    }

    // MARK: - After wake

    /// Opt-in. Some displays forget changes over sleep, so once the pipeline has resumed
    /// after a wake, Glow puts back what it last set and saw confirmed this launch, where the
    /// fresh reading differs. Nothing that asks first is ever reapplied, and safe mode
    /// reapplies nothing.
    @discardableResult
    func reapplyAfterWakeIfChosen() async -> SceneResult? {
        guard reapplyAfterWake, !safeMode || demoMode, pauseReason == nil else { return nil }
        let parts = displays.compactMap { display -> SceneDisplay? in
            let settings = (setByGlow[display.id] ?? [:]).compactMap { id, value -> SceneSetting? in
                guard let descriptor = display.capabilities.first(where: { $0.id == id }),
                      !descriptor.requiresConfirmation, descriptor.currentValue != value else { return nil }
                return SceneSetting(id, value, describedBy: descriptor)
            }
            return settings.isEmpty ? nil : SceneDisplay(identity: display.id, name: display.name, settings: settings)
        }
        guard !parts.isEmpty else { return nil }
        let scene = GlowScene(id: "after-wake", name: "After wake", symbol: "sun.max", displays: parts)
        let result = await write(scene, includingAsksFirst: false)
        showMessage("After wake: \(result.summary(done: "Reapplied"))")
        return result
    }
}

/// The demo's example scenes and starting values, made from the demo displays themselves.
enum DemoScenes {
    static var examples: [GlowScene] {
        let displays = DemoData.displays(generation: 0)
        guard let dell = displays.first(where: { $0.name.hasPrefix("Dell") }) else { return [] }
        return [
            GlowScene(id: "demo-work", name: "Work", symbol: "briefcase", values: [dell.id: [.brightness: .number(68), .volume: .number(35), .preset: .text("sRGB")]], on: displays),
            GlowScene(id: "demo-night", name: "Night", symbol: "moon", values: [dell.id: [.brightness: .number(28), .volume: .number(18), .preset: .text("5000 K")]], on: displays),
            GlowScene(id: "demo-presentation", name: "Presentation", symbol: "play.rectangle", values: [dell.id: [.brightness: .number(85), .input: .text("HDMI 1")]], on: displays)
        ]
    }

    /// What the demo displays start at, by the hardware adapter's rule: read successfully
    /// and changeable.
    static var startingValues: [PersistentDisplayIdentity: [CapabilityIdentifier: CapabilityValue]] {
        Dictionary(uniqueKeysWithValues: DemoData.displays(generation: 0).map { display in
            (display.id, Dictionary(uniqueKeysWithValues: display.capabilities.compactMap { descriptor in
                descriptor.evidence == .safelyProbed && descriptor.access.canWrite ? descriptor.currentValue.map { (descriptor.id, $0) } : nil
            }))
        })
    }
}
