import SwiftUI

/// What applying a scene would do on the displays connected now: the writes in order, the
/// changes that ask first, and what's skipped and why. Built fresh on every apply, so a
/// scene saved against yesterday's desk is checked against today's.
struct ScenePlan: Sendable {
    struct Write: Hashable, Sendable {
        let display: PersistentDisplayIdentity
        let capability: CapabilityIdentifier
        let value: CapabilityValue
        /// Can blank the display, such as a new input; made only after a yes.
        let asksFirst: Bool
    }

    var writes: [Write] = []
    var skipped = 0
    /// Asks-first settings already at the scene's value, so nothing needs sending.
    var alreadySet = 0
    var missingDisplays = 0
    /// What to ask about before applying: one per change that asks first.
    var confirmations: [PendingChange] = []
}

extension GlowScene {
    func plan(on connected: [DisplaySnapshot]) -> ScenePlan {
        var plan = ScenePlan()
        var asking: [ScenePlan.Write] = []
        for part in displays {
            guard let display = connected.first(where: { $0.id == part.identity && $0.isConnected }) else {
                plan.missingDisplays += 1
                continue
            }
            for setting in part.settings.sorted(by: { $0.order(on: display) < $1.order(on: display) }) {
                // A setting this connection can't change is skipped, never guessed at, and a
                // destructive one (display power) is never applied by a scene.
                guard let descriptor = display.capabilities.first(where: { $0.id == setting.capability }),
                      descriptor.canBeInScene, let value = try? descriptor.validated(setting.value) else {
                    plan.skipped += 1
                    continue
                }
                guard descriptor.requiresConfirmation else {
                    plan.writes.append(.init(display: display.id, capability: descriptor.id, value: value, asksFirst: false))
                    continue
                }
                if descriptor.currentValue == value {
                    plan.alreadySet += 1
                } else {
                    asking.append(.init(display: display.id, capability: descriptor.id, value: value, asksFirst: true))
                    plan.confirmations.append(PendingChange(display: display, descriptor: descriptor, value: value))
                }
            }
        }
        // A new input can take a display away and pause writes while it reconnects, so the
        // changes that ask first go after everything else.
        plan.writes += asking
        return plan
    }

    /// A new scene holding the confirmed value of every everyday setting on these displays.
    /// Changes that ask first (input) and destructive ones (power) stay out; the editor lets
    /// someone add an asks-first one.
    static func capturing(_ displays: [DisplaySnapshot], name: String) -> GlowScene {
        let parts = displays.filter(\.isConnected).compactMap { display -> SceneDisplay? in
            let settings = display.capabilities
                .filter { $0.canBeInScene && !$0.requiresConfirmation }
                .compactMap { descriptor in descriptor.confirmedValue.map { SceneSetting(descriptor.id, $0, describedBy: descriptor) } }
                .sorted { $0.order(on: display) < $1.order(on: display) }
            return settings.isEmpty ? nil : SceneDisplay(identity: display.id, name: display.name, settings: settings)
        }
        return GlowScene(name: name, symbol: SceneSymbol.fallback, displays: parts)
    }
}

extension CapabilityDescriptor {
    /// Can be part of a scene: changeable on this connection, a value rather than an action,
    /// and never destructive.
    var canBeInScene: Bool {
        guard isSafelyEditable, risk != .destructive else { return false }
        return switch kind {
        case .range, .options, .toggle: true
        case .action, .text: false
        }
    }

    /// The value Glow last read or confirmed. Nil while the last change failed, and never
    /// the hopeful value of a change still on its way.
    var confirmedValue: CapabilityValue? {
        guard freshness == .confirmed else { return nil }
        return lastConfirmedValue ?? (pendingValue == nil ? currentValue : nil)
    }
}

@MainActor
enum SceneApplier {
    /// Runs the plan's writes one at a time and counts what took. `write` goes through the
    /// store to the pipeline, which validates each value and confirms it by reading back.
    /// Without `includingAsksFirst`, the changes that ask first are left as they are.
    static func apply(_ plan: ScenePlan, includingAsksFirst: Bool, write: (ScenePlan.Write) async throws -> Void) async -> SceneResult {
        var result = SceneResult(succeeded: plan.alreadySet, failed: 0, skipped: plan.skipped, missingDisplays: plan.missingDisplays)
        for item in plan.writes {
            guard includingAsksFirst || !item.asksFirst else {
                result.heldBack += 1
                continue
            }
            do {
                try await write(item)
                result.succeeded += 1
            } catch {
                result.failed += 1
            }
        }
        return result
    }
}

/// A scene, or a restore, waiting for a yes because some of its changes can blank a display.
/// Names each display and what it may do; Cancel changes nothing at all.
struct SceneConfirmation: Identifiable {
    let id = UUID()
    let scene: GlowScene
    let changes: [PendingChange]

    var title: String {
        changes.count == 1 ? changes[0].title : "Make \(changes.count) changes that can blank a display?"
    }

    var message: String { changes.map(\.message).joined(separator: "\n\n") }

    var confirmTitle: String { changes.count == 1 ? changes[0].confirmTitle : "Make All Changes" }

    /// "Leave Input As It Is": apply the rest of the scene without these changes.
    var declineTitle: String {
        let labels = Set(changes.map(\.descriptor.label))
        return labels.count == 1 ? "Leave \(labels.first ?? "It") As It Is" : "Apply the Rest Only"
    }
}

extension View {
    /// Asks before a scene makes changes that can blank a display. `apply` is told whether
    /// the person said yes to those changes; Cancel applies nothing.
    func confirmingScene(_ pending: Binding<SceneConfirmation?>, apply: @escaping (GlowScene, Bool) -> Void) -> some View {
        confirmationDialog(
            pending.wrappedValue?.title ?? "",
            isPresented: Binding(get: { pending.wrappedValue != nil }, set: { if !$0 { pending.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: pending.wrappedValue
        ) { confirmation in
            Button(confirmation.confirmTitle) { apply(confirmation.scene, true) }
            Button(confirmation.declineTitle) { apply(confirmation.scene, false) }
            Button("Cancel", role: .cancel) {}
        } message: { confirmation in
            Text(confirmation.message)
        }
    }
}
