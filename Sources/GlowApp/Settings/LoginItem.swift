import AppKit
import Observation
import ServiceManagement

/// Open at login, through the system's own login-item list, which stays the source of
/// truth: every change is read back from it.
@MainActor @Observable
final class LoginItem {
    private(set) var status: SMAppService.Status
    /// Why the last change didn't take, in macOS's words.
    private(set) var failure: String?

    /// macOS registers only an app bundle. Under `swift run` Glow is a bare executable,
    /// so it can't be added and Settings says so instead of offering a switch that fails.
    let canRegister = Bundle.main.bundleURL.pathExtension == "app"

    init() {
        status = SMAppService.mainApp.status
    }

    var isEnabled: Bool { status == .enabled }

    /// Turned on, but still to be allowed in System Settings.
    var needsApproval: Bool { status == .requiresApproval }

    /// For the switch: on means registered or waiting for approval.
    var isOn: Bool {
        get { isEnabled || needsApproval }
        set { set(newValue) }
    }

    var detail: String {
        if !canRegister {
            return "Available once Glow is installed as an app. This copy runs from the command line, so macOS can’t add it to Login Items."
        }
        if let failure { return "macOS didn’t make the change: \(failure)" }
        if needsApproval { return "Allow Glow in System Settings › General › Login Items." }
        if status == .notFound, !isEnabled {
            return "Start Glow in the menu bar when you log in. If macOS can’t find this copy, open Glow from your Applications folder and try again."
        }
        return isEnabled ? "Glow starts in the menu bar when you log in." : "Start Glow in the menu bar when you log in."
    }

    func set(_ enabled: Bool) {
        guard canRegister else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
