import CoreGraphics
import Foundation

/// A display's gamma transfer table: one curve per channel.
struct GammaTable: Equatable, Sendable {
    var red: [CGGammaValue]
    var green: [CGGammaValue]
    var blue: [CGGammaValue]

    /// The same curves scaled down to `level` of their light. Scaling every entry keeps the
    /// display's calibration; only the top end comes down.
    func dimmed(to level: Double) -> GammaTable {
        let factor = CGGammaValue(SoftwareDimmer.clamped(level))
        return GammaTable(red: red.map { $0 * factor }, green: green.map { $0 * factor }, blue: blue.map { $0 * factor })
    }

    /// How far `self` is dimmed from `original`, from the brightest entry of each, or nil
    /// when the tables don't line up (another app changed them).
    func level(relativeTo original: GammaTable) -> Double? {
        guard red.count == original.red.count, green.count == original.green.count, blue.count == original.blue.count,
              let peak = original.red.max(), peak > 0, let current = red.max() else { return nil }
        let level = Double(current / peak)
        // The other channels must be scaled by the same factor, or this isn't Glow's dimming.
        for (now, before) in [(green, original.green), (blue, original.blue)] {
            guard let channelPeak = before.max(), channelPeak > 0, let channelNow = now.max(),
                  abs(Double(channelNow / channelPeak) - level) < 0.01 else { return nil }
        }
        return min(1, level)
    }
}

/// Software dimming: darkens a display's picture through its gamma table, for displays whose
/// hardware brightness doesn't answer. It never changes the backlight and is always labelled
/// "Software dimming". Every exit path restores the ColorSync tables.
@MainActor
final class SoftwareDimmer {
    /// The darkest Glow goes, so the screen can never go black.
    nonisolated static let floor = 0.1

    nonisolated static func clamped(_ level: Double) -> Double {
        guard level.isFinite else { return 1 }
        return min(1, max(floor, level))
    }

    /// Each display's table before Glow touched it.
    private var originals: [CGDirectDisplayID: GammaTable] = [:]
    /// The level Glow set on each display it dims now.
    private var levels: [CGDirectDisplayID: Double] = [:]

    static let shared = SoftwareDimmer()

    /// The level the display shows now, read from its live table: 1 when Glow hasn't
    /// dimmed it or macOS has reset it since.
    func level(of display: CGDirectDisplayID) -> Double? {
        guard let current = Self.table(of: display) else { return nil }
        guard let original = originals[display] else {
            originals[display] = current
            return 1
        }
        if current == original { return 1 }
        return current.level(relativeTo: original)
    }

    func setLevel(_ level: Double, on display: CGDirectDisplayID) -> Bool {
        let level = Self.clamped(level)
        if originals[display] == nil { originals[display] = Self.table(of: display) }
        guard let original = originals[display] else { return false }
        guard level < 1 else {
            // Back to full: hand the display back to ColorSync. That resets every display, so
            // put back any other display Glow still dims.
            levels[display] = nil
            CGDisplayRestoreColorSyncSettings()
            for (other, otherLevel) in levels { _ = apply(otherLevel, on: other) }
            return true
        }
        levels[display] = level
        return apply(level, on: display, original: original)
    }

    private func apply(_ level: Double, on display: CGDirectDisplayID, original: GammaTable? = nil) -> Bool {
        guard let table = (original ?? originals[display])?.dimmed(to: level) else { return false }
        return CGSetDisplayTransferByTable(display, UInt32(table.red.count), table.red, table.green, table.blue) == .success
    }

    /// Forgets displays that are gone, so a reconnected one starts from its new table.
    func keepOnly(_ displays: Set<CGDirectDisplayID>) {
        originals = originals.filter { displays.contains($0.key) }
        levels = levels.filter { displays.contains($0.key) }
    }

    var isDimmingAnything: Bool { !levels.isEmpty }

    /// Puts every display's ColorSync table back. Safe to call from any thread and more
    /// than once; quitting, signals and `atexit` all end here.
    nonisolated static func restoreAll() {
        CGDisplayRestoreColorSyncSettings()
    }

    func restore() {
        levels.removeAll()
        Self.restoreAll()
    }

    private static func table(of display: CGDirectDisplayID) -> GammaTable? {
        let capacity = CGDisplayGammaTableCapacity(display)
        guard capacity > 0 else { return nil }
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = red
        var blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &count) == .success, count > 0 else { return nil }
        return GammaTable(red: Array(red.prefix(Int(count))), green: Array(green.prefix(Int(count))), blue: Array(blue.prefix(Int(count))))
    }

    /// Restores gamma if Glow exits by `exit()`, SIGINT, SIGTERM or SIGHUP rather than
    /// quitting normally. (macOS also resets tables when a process ends; this doesn't rely on it.)
    static func installExitRestore() {
        atexit { SoftwareDimmer.restoreAll() }
        for signal in [SIGINT, SIGTERM, SIGHUP] {
            Foundation.signal(signal, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signal, queue: .main)
            source.setEventHandler {
                SoftwareDimmer.restoreAll()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private static var signalSources: [DispatchSourceSignal] = []
}
