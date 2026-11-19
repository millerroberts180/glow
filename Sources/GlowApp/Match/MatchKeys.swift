extension MatchSession {
    /// The calibration's arrow keys while comparing: ← and → change the highlighted
    /// display, five steps at a time with Shift, and ↑ and ↓ choose another. Returns
    /// whether the key was one of them, so the window that has the keyboard can keep it.
    /// The calibration window and setup both use it.
    func handleArrowKey(_ keyCode: UInt16, shift: Bool) -> Bool {
        guard pointIndex != nil else { return false }
        let steps = shift ? 5 : 1
        switch keyCode {
        case 123: nudge(-steps)
        case 124: nudge(steps)
        case 125: selectAdjacent(1)
        case 126: selectAdjacent(-1)
        default: return false
        }
        return true
    }
}
