/// How far one press of a brightness key moves. Stored by its raw value, so the titles can
/// change without losing anyone's choice.
enum KeyStep: String, CaseIterable, Identifiable, Codable, Sendable {
    case likeMacOS, percent1, percent2, percent5, percent10
    var id: Self { self }

    var title: String {
        switch self {
        case .likeMacOS: "Like macOS"
        case .percent1: "1%"
        case .percent2: "2%"
        case .percent5: "5%"
        case .percent10: "10%"
        }
    }

    /// One press, as a share of the setting's range.
    var fraction: Double {
        switch self {
        case .likeMacOS: 1 / BrightnessKeyRouting.steps
        case .percent1: 0.01
        case .percent2: 0.02
        case .percent5: 0.05
        case .percent10: 0.10
        }
    }

    /// One press with Option and Shift: a quarter of a press, as on macOS, but never less
    /// than 1%.
    var fineFraction: Double {
        switch self {
        case .likeMacOS: 1 / BrightnessKeyRouting.quarterSteps
        default: max(fraction / 4, 0.01)
        }
    }

    /// The Controls pane's note on what a press does.
    var footer: String {
        switch self {
        case .likeMacOS: "Each press is one sixteenth of the range, as on a Mac without Glow. Hold a key and brightness moves 1% at a time until you let go."
        default: "Each press moves \(title) of the range. Hold a key and brightness moves 1% at a time until you let go."
        }
    }
}
