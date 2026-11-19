import ApplicationServices
import AppKit

/// Whether macOS lets Glow see the brightness keys (Accessibility), and asking for it.
@MainActor enum KeyAccess {
    /// True once the grant is in place. Cheap enough to poll about once a second.
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Shows macOS's own prompt, then opens Privacy & Security › Accessibility.
    static func request() {
        // The literal is `kAXTrustedCheckOptionPrompt`; the global itself isn't
        // concurrency-safe under Swift 6.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// False under `swift run`: the grant then attaches to the terminal app, not Glow.
    static var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }
}
