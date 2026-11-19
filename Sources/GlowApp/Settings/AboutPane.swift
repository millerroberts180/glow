import SwiftUI

/// Settings › Glow: the mark, what Glow is and which version this is, and where to find out more.
/// Quit Glow is at the end of Settings › General, and on a right-click of the menu-bar mark.
struct AboutPane: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: GlowTokens.Space.s2) {
                    Image(nsImage: GlowLogo.markImage(side: GlowTokens.Size.aboutMark))
                        .padding(.bottom, GlowTokens.Space.s1)
                    Text("Glow")
                        .font(GlowTokens.Typography.aboutTitle)
                    Text(Self.version(from: Bundle.main.infoDictionary))
                        .foregroundStyle(GlowTokens.Text.secondary)
                        .textSelection(.enabled)
                    VStack(spacing: GlowTokens.Space.s1) {
                        Text("Every display, in the same light.")
                        Text("Glow sets brightness, volume and each display’s own settings from the menu bar and the keys you already use, and shows plainly what each display can do.")
                            .foregroundStyle(GlowTokens.Text.secondary)
                    }
                    .font(GlowTokens.Typography.callout)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
                    .padding(.top, GlowTokens.Space.s2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, GlowTokens.Space.s4)
                .accessibilityElement(children: .combine)
            }

            Section {
                LabeledContent("Website") {
                    Link(ReleaseInfo.websiteURL.host() ?? ReleaseInfo.websiteURL.absoluteString, destination: ReleaseInfo.websiteURL)
                }
                LabeledContent("Support") {
                    Link(ReleaseInfo.supportTitle, destination: ReleaseInfo.supportURL ?? ReleaseInfo.supportMailURL)
                }
                LabeledContent("Privacy policy") {
                    Link("Read", destination: ReleaseInfo.privacyPolicyURL)
                }
                LabeledContent("License agreement") {
                    Link("Read", destination: ReleaseInfo.eulaURL)
                }
            } header: {
                Text("Links")
            } footer: {
                FooterNote("They open in \(ReleaseInfo.linksOpenIn). Glow itself never goes online.")
            }

            if !ReleaseInfo.copyright.isEmpty {
                Section {
                    Text(ReleaseInfo.copyright)
                        .font(GlowTokens.Typography.caption)
                        .foregroundStyle(GlowTokens.Text.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// "Version 0.1.0 (1)" from the app's Info.plist. Run with `swift run` there's none, so
    /// it says this is a development build.
    nonisolated static func version(from info: [String: Any]?) -> String {
        guard let short = info?["CFBundleShortVersionString"] as? String, !short.isEmpty else { return "Development build" }
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty, build != short else { return "Version \(short)" }
        return "Version \(short) (\(build))"
    }
}
