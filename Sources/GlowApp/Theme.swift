import AppKit
import SwiftUI

/// Glow's semantic design tokens. Components reference these, never
/// raw values. Where a brand colour matches a macOS semantic colour, the system colour is
/// used so Increase Contrast and the user's appearance keep working; the rest are defined
/// here for light and dark.
enum GlowTokens {
    /// Glow's own colour, Apricot Terracotta (design/logo). Identity only: the mark and the
    /// smallest brand moments, never a control, a selection or a state.
    enum Brand {
        static let glow = Color(nsColor: glowColor)
        /// The same colour for AppKit drawing, such as the mark's image.
        static let glowColor = NSColor(hex: 0xDE8B6D)
    }

    enum Surface {
        static let canvas = Color(nsColor: .windowBackgroundColor)
        static let window = Color(nsColor: .controlBackgroundColor)
        static let subtle = Color.primary.opacity(0.05)
        /// A chosen row or tile: a wash of the accent colour, so it follows the person's choice.
        static let selected = Color(nsColor: .controlAccentColor).opacity(0.16)
        /// A choice tile or action button at rest, under the pointer, and chosen.
        static let tile = Color.primary.opacity(0.05)
        static let tileHover = Color.primary.opacity(0.10)
        static let tileChosen = Color.primary.opacity(0.10)
        /// The overlay's level boxes: lit solid, unlit a quiet trace of the same ink.
        static let overlayBoxLit = Color.primary.opacity(0.88)
        static let overlayBoxUnlit = Color.primary.opacity(0.14)
        /// A wash under the overlay's material, so it reads over a busy desktop.
        static let overlayTint = Color(nsColor: .windowBackgroundColor).opacity(0.35)
    }

    enum Text {
        static let primary = Color(nsColor: .labelColor)
        static let secondary = Color(nsColor: .secondaryLabelColor)
        static let tertiary = Color(nsColor: .tertiaryLabelColor)
    }

    enum Border {
        static let subtle = Color(nsColor: .separatorColor)
        /// The outline of a choice tile or action button that isn't chosen.
        static let tile = Color.primary.opacity(0.10)
    }

    /// The person's macOS accent colour, blue unless they chose another: sliders, selection,
    /// focus and primary actions. An intentional, active choice; never decoration.
    enum Accent {
        static let primary = Color(nsColor: .controlAccentColor)
        /// The soft light around a chosen tile or a pressed action button.
        static let glow = Color(nsColor: .controlAccentColor).opacity(0.45)
        /// A pressed action button's fill.
        static let pressed = Color(nsColor: .controlAccentColor).opacity(0.20)
        /// A lit level box under the pointer: the accent, a little lighter.
        static let lifted = Color(nsColor: NSColor(name: nil) { _ in
            NSColor.controlAccentColor.usingColorSpace(.sRGB)?.blended(withFraction: 0.3, of: .white) ?? .controlAccentColor
        })
    }

    /// One tint per Settings pane, for its sidebar and header tile, like System Settings.
    /// Identity only: the tiles never carry state.
    enum PaneTint {
        static let general = Color.gray
        static let displays = Color.indigo
        static let match = Color.orange
        static let scenes = Color.purple
        static let controls = Color.teal
        static let connection = GlowTokens.dynamic(light: 0x6B7A8F, dark: 0x6B7A8F)
        /// The Glow pane's tile is the app icon, the mark in white on the brand colour.
        static let about = GlowTokens.Brand.glow
        static let reading = Color.blue
    }

    enum Status {
        /// Connected, matched, completed. Never a clickable button.
        static let success = Color(nsColor: .systemGreen)
        /// "Works differently", such as software dimming. Not failure.
        static let warning = Color(nsColor: .systemOrange)
        /// A real problem or destructive action.
        static let danger = Color(nsColor: .systemRed)
        /// The words of a status, a deeper shade of its symbol's hue in light mode, so
        /// caption text keeps 4.5:1 contrast on a white form row.
        static let successText = GlowTokens.dynamic(light: 0x1E7F34, dark: 0x30D158)
        static let warningText = GlowTokens.dynamic(light: 0xA05A00, dark: 0xFF9F0A)
        static let dangerText = GlowTokens.dynamic(light: 0xC4261D, dark: 0xFF453A)
    }

    enum Space {
        static let s0_5: CGFloat = 2
        static let s1: CGFloat = 4
        static let s1_5: CGFloat = 6
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s5: CGFloat = 20
        static let s6: CGFloat = 24
        static let s8: CGFloat = 32
        static let s10: CGFloat = 40
        /// Between the popover's level boxes.
        static let levelBoxGap: CGFloat = 2
    }

    enum Radius {
        static let control: CGFloat = 7
        static let card: CGFloat = 12
        static let window: CGFloat = 14
        /// Choice tiles and the art inside them.
        static let tile: CGFloat = 10
        static let action: CGFloat = 9
        /// The square brightness overlay, as round as macOS's own.
        static let overlayHUD: CGFloat = 18
        static let overlayBox: CGFloat = 1.5
        /// The popover's buttons, rounder and friendlier than Settings'. A one-line button is
        /// too short to take this cleanly, so it comes out nearly a capsule instead.
        static let popoverAction: CGFloat = 11
        /// A popover level box, and the ring around a row of them while it has keyboard focus.
        static let levelBox: CGFloat = 3.5
        static let levelBoxFocus: CGFloat = 7
    }

    enum Size {
        /// As narrow as four brightness-key buttons allow, side by side with room between.
        static let popoverWidth: CGFloat = 308
        /// The Glow mark beside "Glow" in the popover, and the leading symbol of a popover slider.
        static let popoverMark: CGFloat = 16
        static let sliderSymbol: CGFloat = 16
        /// A popover button's symbol, framed square so a row of them lines up.
        static let popoverSymbol: CGFloat = 14
        /// Room for "100%" in tabular figures.
        static let percentWidth: CGFloat = 36
        static let overlayWidth: CGFloat = 280
        static let rowMinHeight: CGFloat = 44
        static let controlHeight: CGFloat = 28
        static let primaryActionHeight: CGFloat = 32
        /// Settings: room for the Digital OSD's slider, value and status side by side.
        static let settingsWindow = CGSize(width: 760, height: 600)
        static let settingsSidebarWidth: CGFloat = 168
        /// Setup: room for a row of display tiles, and small enough that the grey patches show
        /// round it while matching.
        static let setupWindow = CGSize(width: 640, height: 600)
        static let paneHeaderHeight: CGFloat = 46
        static let sidebarTile: CGFloat = 19
        static let headerTile: CGFloat = 24
        static let choiceArtHeight: CGFloat = 40
        static let displayArtHeight: CGFloat = 56
        static let osdSliderWidth: CGFloat = 180
        static let valueWidth: CGFloat = 40
        /// The mark at the top of Settings › Glow.
        static let aboutMark: CGFloat = 64
        /// The slider overlay's height; it is `overlayWidth` wide.
        static let overlayHeight: CGFloat = 124
        /// The boxes overlay: a square, with a row of 16 boxes `overlayBoxHeight` tall.
        static let overlayHUD: CGFloat = 200
        static let overlayBoxHeight: CGFloat = 8
        static let overlayLevelBar: CGFloat = 4
        /// How far above the bottom of the screen each overlay sits.
        static let overlayInset: CGFloat = 44
        static let overlayHUDInset: CGFloat = 120
        /// A popover level box's height, about a small slider's, so rows keep their rhythm.
        static let levelBoxHeight: CGFloat = 14
        /// The mark on setup's welcome.
        static let setupMark: CGFloat = 88
    }

    enum Motion {
        static let press = Animation.easeOut(duration: 0.12)
        /// The popover's tiny outward settle as it opens, eased out with no bounce. Its
        /// content is fully shown from the first frame; only the scale moves.
        static let popoverOpen: TimeInterval = 0.09
        /// How far in the popover starts before it settles.
        static let popoverStartScale: CGFloat = 0.985
        static let expand = Animation.easeInOut(duration: 0.21)
        /// The overlay stays this long after the last change, then fades out this quickly.
        static let overlayLinger: TimeInterval = 1.5
        static let overlayFade: TimeInterval = 0.2
    }

    enum Typography {
        static let title1 = Font.system(size: 28, weight: .bold)
        static let title3 = Font.system(size: 17, weight: .semibold)
        static let headline = Font.system(size: 13, weight: .semibold)
        static let callout = Font.callout
        static let caption = Font.caption
        static let value = Font.system(size: 28, weight: .bold).monospacedDigit()
        static let diagnostic = Font.system(.caption, design: .monospaced)
        static let sectionLabel = Font.caption.weight(.medium)
        static let paneTitle = Font.system(size: 15, weight: .semibold)
        static let sidebarRow = Font.system(size: 12)
        static let body = Font.body
        static let tileTitle = Font.system(size: 11)
        static let tileTitleChosen = Font.system(size: 11, weight: .semibold)
        static let actionLabel = Font.system(size: 12, weight: .medium)
        static let actionLabelCompact = Font.system(size: 11, weight: .medium)
        static let actionSymbol = Font.system(size: 11, weight: .semibold)
        static let cardTitle = Font.system(size: 13, weight: .semibold)
        /// "Glow" in the popover header.
        static let popoverTitle = Font.system(size: 13, weight: .semibold)
        /// A display's name on its popover row.
        static let rowTitle = Font.system(size: 13, weight: .medium)
        /// Percentages, in tabular figures so a column of them lines up.
        static let percent = Font.callout.monospacedDigit()
        /// The small chevron on a Settings menu's trigger.
        static let menuChevron = Font.system(size: 8, weight: .bold)
        /// "Glow" under the mark in Settings › Glow.
        static let aboutTitle = Font.system(size: 20, weight: .semibold)
        /// The sun or speaker on the boxes overlay.
        static let overlaySymbol = Font.system(size: 64, weight: .regular)
        /// A setup step's title.
        static let setupTitle = Font.system(size: 22, weight: .semibold)
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
