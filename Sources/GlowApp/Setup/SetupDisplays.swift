import SwiftUI

/// Your displays: Glow's mark and what Glow does, then the displays in Glow Desk's own
/// rows, as wide as Glow Desk, with where to find it in the menu bar.
struct DisplaysStep: View {
    let model: SetupModel

    var body: some View {
        let desk = model.deskOverride ?? YourDesk(store: model.store)
        let shape = RoundedRectangle(cornerRadius: GlowTokens.Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Image(nsImage: GlowLogo.markImage(side: GlowTokens.Size.setupMark))
                .padding(.bottom, GlowTokens.Space.s3)
                .accessibilityHidden(true)
            SetupTitle("Your displays", "Glow sets the brightness of every display from the menu bar.")
            HStack(alignment: .top, spacing: GlowTokens.Space.s6) {
                DeskDisplays(desk: desk, store: model.store)
                    .padding(GlowTokens.Space.s4)
                    .frame(width: GlowTokens.Size.popoverWidth)
                    .background(shape.fill(GlowTokens.Surface.tile))
                    .overlay(shape.strokeBorder(GlowTokens.Border.tile))
                VStack(alignment: .leading, spacing: GlowTokens.Space.s3) {
                    SetupTask(
                        // The mark is 18 points, as in the menu bar; lowered to sit on the line's middle.
                        Text("Click \(Text(Image(nsImage: GlowLogo.menuBarImage())).baselineOffset(-4)) in the menu bar to open Glow Desk."),
                        spoken: "Click Glow’s mark in the menu bar to open Glow Desk.",
                        done: model.openedGlowDesk
                    )
                    if !desk.displays.isEmpty {
                        Text("Native and Hardware control change a display’s own brightness; Software dimming dims its picture.")
                            .font(GlowTokens.Typography.caption)
                            .foregroundStyle(GlowTokens.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if desk.state == .demo {
                        SetupNote(symbol: "sparkles.rectangle.stack", text: "These are Glow’s demo displays. Turn off Use demo displays in Settings › General to see yours.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
