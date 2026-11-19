import AppKit
import CoreGraphics

/// Watches for the brightness keys with a CGEventTap on the main run loop. It runs only
/// while `KeyAccess.isGranted`; until then it checks once a second and arms itself the
/// moment the grant arrives. Each key-down, repeat and key-up goes to `handler`
/// (`BrightnessKeyHold`); an event it takes is swallowed, and any other goes on to macOS
/// unchanged.
@MainActor
final class BrightnessKeyTap {
    typealias Handler = @MainActor (BrightnessKeyEvent) -> Bool

    /// `NX_SYSDEFINED`, its media-key subtype, and the brightness key codes from IOKit's
    /// `ev_keymap.h`.
    nonisolated static let systemDefinedType = CGEventType(rawValue: 14)!
    nonisolated static let auxControlSubtype: Int16 = 8
    nonisolated static let brightnessUp = 2
    nonisolated static let brightnessDown = 3

    private let handler: Handler
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var poll: Timer?

    var isArmed: Bool { tap != nil }

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func start() {
        armIfAllowed()
        guard poll == nil else { return }
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.armIfAllowed() }
        }
    }

    func stop() {
        poll?.invalidate()
        poll = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        // A key-up can't arrive now, so a held key stops here.
        _ = handler(.lost)
    }

    private func armIfAllowed() {
        guard KeyAccess.isGranted else { return }
        if let tap {
            // macOS turns a tap off if it once ran slowly; turn it back on.
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << Self.systemDefinedType.rawValue,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<BrightnessKeyTap>.fromOpaque(context).takeUnretainedValue()
                let signal = BrightnessKeyTap.signal(type, event)
                let swallow = MainActor.assumeIsolated { tap.handle(signal) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    /// What the tap saw, read out of the event before it reaches the main actor.
    enum Signal: Sendable {
        case tapDisabled
        case brightness(code: Int, isDown: Bool, isRepeat: Bool, option: Bool, shift: Bool, commandOrControl: Bool)
        case other
    }

    nonisolated static func signal(_ type: CGEventType, _ event: CGEvent) -> Signal {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { return .tapDisabled }
        guard type == systemDefinedType, let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == auxControlSubtype, let key = brightnessKey(data1: nsEvent.data1) else { return .other }
        let flags = event.flags
        return .brightness(
            code: key.code, isDown: key.isDown, isRepeat: key.isRepeat,
            option: flags.contains(.maskAlternate), shift: flags.contains(.maskShift),
            commandOrControl: flags.contains(.maskCommand) || flags.contains(.maskControl)
        )
    }

    /// True swallows the event.
    private func handle(_ signal: Signal) -> Bool {
        switch signal {
        case .other:
            return false
        case .tapDisabled:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // Events went by unseen, maybe a key-up among them.
            _ = handler(.lost)
            return false
        case let .brightness(code, isDown, isRepeat, option, shift, commandOrControl):
            let direction: BrightnessKeyPress.Direction = code == Self.brightnessUp ? .up : .down
            guard isDown else { return handler(.up(direction)) }
            // Option alone opens Displays settings, and Command or Control mean something
            // else to macOS: those go through untouched. A repeat goes wherever its press went.
            if !isRepeat, commandOrControl || (option && !shift) { return false }
            return handler(.down(BrightnessKeyPress(direction: direction, quarterStep: option && shift), isRepeat: isRepeat))
        }
    }

    /// `data1` packs the key code in its upper 16 bits, the state (0xA down, 0xB up) in
    /// bits 8–15, and sets bit 0 on the keyboard's auto-repeat.
    nonisolated static func brightnessKey(data1: Int) -> (code: Int, isDown: Bool, isRepeat: Bool)? {
        let code = (data1 & 0xFFFF_0000) >> 16
        let state = (data1 & 0xFF00) >> 8
        guard code == brightnessUp || code == brightnessDown, state == 0xA || state == 0xB else { return nil }
        return (code, state == 0xA, data1 & 0x1 != 0)
    }

    /// The display under the pointer, for the Under cursor target.
    static func pointerDisplay() -> CGDirectDisplayID? {
        let location = CGEvent(source: nil)?.location ?? .zero
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(location, 1, &display, &count) == .success, count > 0 else { return nil }
        return display
    }
}
