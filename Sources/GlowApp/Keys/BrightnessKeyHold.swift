import AppKit

/// A brightness key as the event tap reports it: down (a fresh press, or the keyboard's
/// repeat while it's held), up, or the tap no longer seeing keys.
enum BrightnessKeyEvent: Equatable, Sendable {
    case down(BrightnessKeyPress, isRepeat: Bool)
    case up(BrightnessKeyPress.Direction)
    case lost
}

/// Why a held key stopped moving brightness.
enum KeyHoldStop: Equatable, Sendable {
    /// The key came up.
    case released
    /// The other brightness key went down.
    case otherKey
    /// The event tap was turned off or stopped, so a key-up could go unseen.
    case tapOff
    /// Every target is at the end of its range.
    case rangeEnd
    /// Writes are paused for sleep, wake or a display change.
    case paused
    /// The keys belong to macOS now (Mac only, demo displays or safe mode).
    case notGlows
    /// Neither a repeat nor a key-up came in time; the ramp waits for the next repeat.
    case silent
}

/// Runs the hold's steady tick. The app's is a run loop timer; tests drive their own.
@MainActor protocol KeyHoldTicker: AnyObject {
    func start(every interval: Double, _ tick: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor final class TimerTicker: KeyHoldTicker {
    private var timer: Timer?

    func start(every interval: Double, _ tick: @escaping @MainActor () -> Void) {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
        timer.tolerance = interval / 10
        // Common modes, so the ramp keeps going while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

/// Turns brightness key events into steps. A press moves one step at once, on key-down.
/// Held past the keyboard's repeat delay, brightness then ramps 1% per tick on every target
/// until the key comes up. Glow's own timer paces the ramp: the keyboard's repeats only
/// show the key is still down, are swallowed while Glow has the key, and never add a step.
///
/// A keyboard that sends no repeats still gets its first step and a short ramp: without a
/// repeat the hold is taken as released `firstRepeatWindow` after the press.
@MainActor
final class BrightnessKeyHold {
    struct Timing: Equatable {
        /// How long a key is down before the ramp starts.
        var rampDelay: Double
        /// One 1% step per tick: the full range in about two seconds.
        var tickInterval = 0.02
        /// How long the ramp runs past the last sign of the key, before the first repeat
        /// and after it.
        var firstRepeatWindow: Double
        var repeatWindow: Double

        /// From the keyboard's repeat settings, within limits that keep a hold feeling quick
        /// and a lost key-up short.
        init(repeatDelay: Double, repeatInterval: Double) {
            rampDelay = min(0.5, max(0.25, repeatDelay))
            repeatWindow = min(0.25, max(0.02, repeatInterval)) + 0.15
            firstRepeatWindow = min(1.0, max(rampDelay, repeatDelay)) + repeatWindow
        }

        static var system: Timing {
            Timing(repeatDelay: NSEvent.keyRepeatDelay, repeatInterval: NSEvent.keyRepeatInterval)
        }
    }

    typealias Press = @MainActor (BrightnessKeyPress) -> Bool
    typealias Tick = @MainActor (BrightnessKeyPress.Direction) -> KeyHoldStop?

    private struct Hold {
        var direction: BrightnessKeyPress.Direction
        var downAt: Double
        var lastSign: Double
        var sawRepeat = false
    }

    let timing: Timing
    private let press: Press
    private let tick: Tick
    private let ticker: any KeyHoldTicker
    private let clock: @MainActor () -> Double

    /// Keys whose key-down Glow took, so their repeats and key-up are swallowed too.
    private(set) var owned: Set<BrightnessKeyPress.Direction> = []
    private var hold: Hold?
    private var ticking = false
    private(set) var isRamping = false
    /// Why the most recent hold stopped.
    private(set) var lastStop: KeyHoldStop?

    /// `press` is one step, true when Glow took it; `tick` is one 1% ramp step, returning
    /// why to stop, or nil to go on.
    init(
        timing: Timing = .system,
        ticker: any KeyHoldTicker = TimerTicker(),
        clock: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime },
        press: @escaping Press,
        tick: @escaping Tick
    ) {
        self.timing = timing
        self.ticker = ticker
        self.clock = clock
        self.press = press
        self.tick = tick
    }

    /// True when the event is Glow's, so the tap swallows it.
    func handle(_ event: BrightnessKeyEvent) -> Bool {
        switch event {
        case .lost:
            end(.tapOff)
            return false
        case let .up(direction):
            if hold?.direction == direction { end(.released) }
            return owned.remove(direction) != nil
        case let .down(keyPress, isRepeat):
            if isRepeat {
                guard owned.contains(keyPress.direction) else { return false }
                stillHeld(keyPress.direction)
                return true
            }
            return pressed(keyPress)
        }
    }

    private func pressed(_ keyPress: BrightnessKeyPress) -> Bool {
        if let hold { end(hold.direction == keyPress.direction ? .released : .otherKey) }
        guard press(keyPress) else {
            owned.remove(keyPress.direction)
            return false
        }
        owned.insert(keyPress.direction)
        let now = clock()
        hold = Hold(direction: keyPress.direction, downAt: now, lastSign: now)
        startTicking()
        return true
    }

    /// A repeat: the key is still down. After a silent stop it picks the ramp up again.
    private func stillHeld(_ direction: BrightnessKeyPress.Direction) {
        guard hold?.direction == direction else { return }
        hold?.lastSign = clock()
        hold?.sawRepeat = true
        if lastStop == .silent {
            lastStop = nil
            startTicking()
        }
    }

    private func startTicking() {
        guard !ticking else { return }
        ticking = true
        ticker.start(every: timing.tickInterval) { [weak self] in self?.fire() }
    }

    private func fire() {
        guard let hold else { return end(.released) }
        let now = clock()
        let window = hold.sawRepeat ? timing.repeatWindow : timing.firstRepeatWindow
        guard now - hold.lastSign <= window else { return end(.silent) }
        guard now - hold.downAt >= timing.rampDelay else { return }
        isRamping = true
        if let stop = tick(hold.direction) { end(stop) }
    }

    /// Stops the ramp. A silent stop keeps the hold, so the next repeat can resume it.
    private func end(_ reason: KeyHoldStop) {
        if ticking {
            ticker.stop()
            ticking = false
        }
        isRamping = false
        guard hold != nil else { return }
        lastStop = reason
        if reason != .silent { hold = nil }
    }
}
