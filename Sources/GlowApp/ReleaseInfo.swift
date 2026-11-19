import Foundation

/// Where Glow points people: read from the bundle's Info.plist, which scripts/bundle.sh stamps from
/// Resources/release.env. A link left unset there keeps a placeholder on glow.example, so a test build
/// still has somewhere to point. Glow never opens any of these on its own, only when someone clicks one.
enum ReleaseInfo {
    static var websiteURL: URL { url("GlowWebsiteURL", placeholder: "https://glow.example") }
    static var privacyPolicyURL: URL { url("GlowPrivacyPolicyURL", placeholder: "https://glow.example/privacy") }
    static var eulaURL: URL { url("GlowEULAURL", placeholder: "https://glow.example/eula") }
    /// A help page, such as the issue tracker. When there is one, About's Support link opens it.
    static var supportURL: URL? { string("GlowSupportURL").flatMap(URL.init(string:)) }
    /// The support address, if one is set.
    static var supportEmail: String? { string("GlowSupportEmail") }
    static var supportMailURL: URL { URL(string: "mailto:\(supportEmail ?? placeholderSupportEmail)") ?? websiteURL }
    /// What About's Support link says.
    static var supportTitle: String { supportTitle(email: supportEmail, url: supportURL) }

    /// The address when there is one, otherwise the help page's host, as the Website link shows its
    /// host. The placeholder address only when there is neither.
    static func supportTitle(email: String?, url: URL?) -> String {
        if let email { return email }
        if let url { return url.host() ?? url.absoluteString }
        return placeholderSupportEmail
    }

    private static let placeholderSupportEmail = "support@glow.example"

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
