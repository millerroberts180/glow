#if DEBUG
import CoreGraphics
import Foundation

/// `swift run Glow --scene-selftest` (debug builds): scenes, Restore Starting Values and
/// Reapply after wake against the real displays, through the real store and pipeline, with
/// a throwaway defaults suite. Only brightness and contrast on a hardware or native route
/// are touched, each moved by 5 and put back, and every value is read back afterwards.
/// Software dimming is left alone, so no gamma table is written. Exits non-zero on a failure.
@MainActor
enum SceneSelfTest {
    static func requested(in arguments: [String]) -> Bool { arguments.contains("--scene-selftest") }

    private static let allowed: Set<CapabilityIdentifier> = [.brightness, .contrast]

    static func run() async -> Int32 {
        let suite = "app.glow.scene-selftest"
        guard let defaults = UserDefaults(suiteName: suite) else { return 1 }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GlowStore(settings: GlowSettingsStore(defaults: defaults), demoDisplays: false)
        await store.refresh()
        var failures = 0
        func check(_ passed: Bool, _ text: String) {
            print("\(passed ? "PASS" : "FAIL")  \(text)")
            if !passed { failures += 1 }
        }

        // The exact native levels, so the end puts back 0.3125 and not 31 %.
        let nativeLevels = Dictionary(uniqueKeysWithValues: store.displays.compactMap { display -> (CGDirectDisplayID, Float)? in
            guard display.capabilities.contains(where: { $0.id == .brightness && $0.route == .native }),
                  let level = NativeBrightness.shared?.brightness(display.connection.displayID) else { return nil }
            return (display.connection.displayID, level)
        })
        let original = testable(GlowScene.capturing(store.displays, name: "Original"), on: store.displays)
        print("Displays: \(store.displays.map { "\($0.name) (\($0.primaryRoute.userLabel))" }.joined(separator: ", "))")
        for part in original.displays {
            print("  \(part.name): \(part.settings.map { $0.text(on: nil) }.joined(separator: " · "))")
        }
        guard original.settingCount > 0 else {
            print("Nothing on a hardware or native route to test with.")
            return 0
        }
        let shifted = moved(original, on: store.displays)

        // 1. A new scene applies, every write confirmed, and becomes the active scene.
        store.saveScene(original)
        store.saveScene(shifted)
        let applied = await store.applyScene(shifted)
        print("Apply: \(applied.summary)\(applied.detail.map { " (\($0))" } ?? "")")
        check(applied.failed == 0 && applied.succeeded == shifted.settingCount, "scene applied: \(applied.summary)")
        check(await matches(shifted, store), "every shifted value reads back from the display")
        check(store.activeScene?.id == shifted.id, "the shifted scene is active")

        // 2. The captured scene puts the original values back.
        let back = await store.applyScene(original)
        check(back.failed == 0, "original scene applied: \(back.summary)")
        check(await matches(original, store), "every original value reads back")

        // 3. Reapply after wake: shift, then the display "forgets" behind Glow's back.
        await store.applyScene(shifted)
        for part in original.displays {
            for setting in part.settings {
                try? await store.hardwareAdapter.write(setting.value, capability: setting.capability, display: part.identity)
            }
        }
        await store.refresh()
        check(await matches(original, store), "the forgotten values read as the originals")
        check(await store.reapplyAfterWakeIfChosen() == nil, "nothing is reapplied while the option is off")
        store.reapplyAfterWake = true
        let reapplied = await store.reapplyAfterWakeIfChosen()
        print("After wake: \(reapplied?.summary(done: "Reapplied") ?? "nothing")")
        check(reapplied?.failed == 0 && reapplied?.succeeded == shifted.settingCount, "after wake, Glow put back what it set")
        check(await matches(shifted, store), "every reapplied value reads back")

        // 4. Restore Starting Values, where the starting values hold only what was moved.
        for display in store.displays {
            let starting = store.startingScene(for: display)
            guard starting.settingCount > 0 else { continue }
            guard starting.displays.allSatisfy({ $0.settings.allSatisfy { allowed.contains($0.capability) } }) else {
                print("SKIP  \(display.name): its starting values differ in more than brightness and contrast")
                continue
            }
            let restored = await store.restoreStartingValues(of: display)
            print("Restore on \(display.name): \(restored.summary(done: "Restored"))")
            check(restored.failed == 0, "\(display.name) restored to its starting values")
        }
        check(await matches(original, store), "every value is back to where Glow found it")

        // 5. A scene whose only display isn't here sends nothing and says so.
        let away = GlowScene(name: "Away", symbol: "moon", displays: [SceneDisplay(
            identity: PersistentDisplayIdentity(vendorID: 1, productID: 2, serialNumber: 3), name: "Studio Display",
            settings: [SceneSetting(.brightness, .number(50), describedBy: nil)]
        )])
        let missing = await store.applyScene(away)
        check(missing.summary == "None of this scene’s displays are connected", "a disconnected scene says so: \(missing.summary)")

        // Leave the built-in exactly as it was found, then read everything once more.
        for (id, level) in nativeLevels { _ = NativeBrightness.shared?.setBrightness(level, on: id) }
        for (id, level) in nativeLevels {
            let now = NativeBrightness.shared?.brightness(id)
            check(now.map { abs($0 - level) < 0.002 } ?? false, "native level \(level) restored exactly (reads \(now.map { String($0) } ?? "nothing"))")
        }
        check(await matches(original, store), "final read: everything as found")
        print(failures == 0 ? "All scene checks passed." : "\(failures) scene check(s) failed.")
        return failures == 0 ? 0 : 1
    }

    /// Only brightness and contrast that Glow controls directly: hardware or native, never
    /// software dimming.
    private static func testable(_ scene: GlowScene, on displays: [DisplaySnapshot]) -> GlowScene {
        var scene = scene
        scene.displays = scene.displays.compactMap { part in
            let display = displays.first(where: { $0.id == part.identity })
            var part = part
            part.settings = part.settings.filter { setting in
                allowed.contains(setting.capability)
                    && [.hardware, .native].contains(display?.capabilities.first(where: { $0.id == setting.capability })?.route)
            }
            return part.settings.isEmpty ? nil : part
        }
        return scene
    }

    /// Each value moved by 5, down unless that would leave the range.
    private static func moved(_ scene: GlowScene, on displays: [DisplaySnapshot]) -> GlowScene {
        var moved = scene
        moved.id = UUID().uuidString
        moved.name = "Shifted"
        for index in moved.displays.indices {
            let display = displays.first(where: { $0.id == moved.displays[index].identity })
            for settingIndex in moved.displays[index].settings.indices {
                let setting = moved.displays[index].settings[settingIndex]
                guard case let .number(value) = setting.value,
                      case let .range(minimum, _, _)? = display?.capabilities.first(where: { $0.id == setting.capability })?.kind else { continue }
                moved.displays[index].settings[settingIndex].value = .number(value - 5 >= minimum ? value - 5 : value + 5)
            }
        }
        return moved
    }

    /// Reads every value in the scene straight from the display, past the store.
    private static func matches(_ scene: GlowScene, _ store: GlowStore) async -> Bool {
        var all = true
        for part in scene.displays {
            for setting in part.settings {
                let read = try? await store.hardwareAdapter.read(capability: setting.capability, display: part.identity)
                if read != setting.value {
                    print("      \(part.name) \(setting.label): expected \(setting.value), read \(read?.description ?? "nothing")")
                    all = false
                }
            }
        }
        return all
    }
}
#endif
