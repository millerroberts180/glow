/// The person's own displays as setup and the popover show them, read from the store.
struct YourDesk: Equatable {
    enum State: Equatable {
        /// Discovery hasn't found anything yet.
        case reading
        /// Nothing Glow can see.
        case none
        /// Demo displays are on, so these aren't theirs.
        case demo
        /// The built-in display alone.
        case builtInOnly
        case ready
    }

    var displays: [DisplaySnapshot]
    var isReading = false
    var isPaused = false
    var isDemo = false

    @MainActor init(store: GlowStore) {
        self.init(displays: store.displays, isReading: store.isDiscovering, isPaused: store.pauseReason != nil,
                  isDemo: store.demoMode || store.isDemoData)
    }

    init(displays: [DisplaySnapshot], isReading: Bool = false, isPaused: Bool = false, isDemo: Bool = false) {
        self.displays = displays
        self.isReading = isReading
        self.isPaused = isPaused
        self.isDemo = isDemo
    }

    var state: State {
        if displays.isEmpty { return isReading ? .reading : .none }
        if isDemo { return .demo }
        return displays.contains { !$0.isBuiltIn } ? .ready : .builtInOnly
    }
}
