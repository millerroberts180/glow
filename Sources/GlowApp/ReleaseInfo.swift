import Foundation

/// Where Glow points people: read from the bundle's Info.plist, which scripts/bundle.sh stamps from
/// Resources/release.env. A value left unset there keeps the source plist's placeholder on glow.example,
/// so a test build still has somewhere to point. Glow never opens any of these on its own, only when
/// someone clicks one.
enum ReleaseInfo {
    static var websiteURL: URL { url("GlowWebsiteURL", placeholder: "https://glow.example") }
    static var privacyPolicyURL: URL { url("GlowPrivacyPolicyURL", placeholder: "https://glow.example/privacy") }
    static var eulaURL: URL { url("GlowEULAURL", placeholder: "https://glow.example/eula") }
    /// A help page, if there is one; support is otherwise by email.
    static var supportURL: URL? { string("GlowSupportURL").flatMap(URL.init(string:)) }
    static var supportEmail: String { string("GlowSupportEmail") ?? "support@glow.example" }
    static var supportMailURL: URL { URL(string: "mailto:\(supportEmail)") ?? websiteURL }

    static var copyright: String { string("NSHumanReadableCopyright") ?? "" }

    static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.millerroberts.Glow" }

    private static func string(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func url(_ key: String, placeholder: String) -> URL {
        string(key).flatMap(URL.init(string:)) ?? URL(string: placeholder)!
    }
}
