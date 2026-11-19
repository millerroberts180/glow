import SwiftUI

/// A row's title with a quieter second line saying what it does or why it's dimmed.
struct DetailLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: GlowTokens.Space.s0_5) {
            Text(title)
            Text(detail)
                .font(GlowTokens.Typography.caption)
                .foregroundStyle(GlowTokens.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A switch with a second, quieter line saying what it does.
struct DetailToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            DetailLabel(title: title, detail: detail)
        }
    }
}

/// A grouped-form footer that reads as a note: left-aligned, caption, secondary.
struct FooterNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(GlowTokens.Typography.caption)
            .foregroundStyle(GlowTokens.Text.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row of illustrated tiles for choosing one of a few settings, in place of a segmented
/// control. Each tile draws what its choice does, and the chosen one glows. `onPick` runs
/// after a choice, to demonstrate it.
struct VisualChoice<Value: Hashable, Art: View>: View {
    struct Option: Identifiable {
        var value: Value
        var title: String
        var id: Value { value }
    }

    var options: [Option]
    @Binding var selection: Value
    var artHeight = GlowTokens.Size.choiceArtHeight
    var onPick: (Value) -> Void = { _ in }
    /// The tile's drawing for a value; the Bool is whether it's chosen.
    @ViewBuilder var art: (Value, Bool) -> Art

    var body: some View {
        HStack(spacing: GlowTokens.Space.s2) {
            ForEach(options) { option in
                tile(option)
            }
        }
    }

    private func tile(_ option: Option) -> some View {
        let selected = option.value == selection
        let shape = RoundedRectangle(cornerRadius: GlowTokens.Radius.tile, style: .continuous)
        return Button {
            selection = option.value
            onPick(option.value)
        } label: {
            VStack(spacing: GlowTokens.Space.s1_5) {
                art(option.value, selected)
                    .frame(maxWidth: .infinity)
                    .frame(height: artHeight)
                    .background(shape.fill(selected ? GlowTokens.Surface.tileChosen : GlowTokens.Surface.tile))
                    .overlay(shape.strokeBorder(selected ? GlowTokens.Accent.primary : GlowTokens.Border.tile, lineWidth: selected ? 2 : 1))
                    .shadow(color: selected ? GlowTokens.Accent.glow : .clear, radius: 5)
                Text(option.title)
                    .font(selected ? GlowTokens.Typography.tileTitleChosen : GlowTokens.Typography.tileTitle)
                    .foregroundStyle(selected ? GlowTokens.Text.primary : GlowTokens.Text.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Settings' action buttons in the same family as the choice tiles: a soft tile with an
/// accent icon that lights on hover and glows as it's pressed. Selected, it wears the chosen
/// tile's accent edge, for buttons that pick or switch something. Rounded, it has the
/// popover's softer corners.
struct ActionButtonStyle: ButtonStyle {
    var compact = false
    var isSelected = false
    var rounded = false

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, compact: compact, isSelected: isSelected, rounded: rounded)
    }

    // Not named `Button`: it would shadow SwiftUI's inside this style.
    private struct StyledButton: View {
        let configuration: Configuration
        let compact: Bool
        let isSelected: Bool
        let rounded: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            if rounded {
                styled(PopoverButtonShape())
            } else {
                styled(RoundedRectangle(cornerRadius: compact ? GlowTokens.Radius.control : GlowTokens.Radius.action, style: .continuous))
            }
        }

        private func styled<S: InsettableShape>(_ shape: S) -> some View {
            let pressed = configuration.isPressed
            let fill = pressed ? GlowTokens.Accent.pressed
                : isSelected ? GlowTokens.Surface.tileChosen
                : hovering ? GlowTokens.Surface.tileHover : GlowTokens.Surface.tile
            let edge = pressed || isSelected ? GlowTokens.Accent.primary : (hovering ? GlowTokens.Accent.glow : GlowTokens.Border.tile)
            return configuration.label
                .font(compact ? GlowTokens.Typography.actionLabelCompact : GlowTokens.Typography.actionLabel)
                .padding(.horizontal, compact ? 9 : GlowTokens.Space.s3)
                .padding(.vertical, compact ? GlowTokens.Space.s1 : GlowTokens.Space.s1_5)
                .background(shape.fill(fill))
                .overlay(shape.strokeBorder(edge, lineWidth: pressed || isSelected ? 1.5 : 1))
                .shadow(color: pressed ? GlowTokens.Accent.glow : .clear, radius: 5)
                .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
                // Disabled reads as quieter text and a fainter tile, not opacity alone.
                .foregroundStyle(isEnabled ? GlowTokens.Text.primary : GlowTokens.Text.tertiary)
                .opacity(isEnabled ? 1 : 0.6)
                .animation(GlowTokens.Motion.press, value: pressed)
                .animation(GlowTokens.Motion.press, value: hovering)
                .contentShape(Rectangle())
                .onHover { hovering = $0 && isEnabled }
        }
    }
}

/// A popover button's outline: corners as round as `Radius.popoverAction`, held to what a
/// continuous curve draws cleanly at the button's height. A one-line button comes out nearly
/// a capsule, and a taller one, such as a brightness-key button, a soft square.
private struct PopoverButtonShape: InsettableShape {
    /// Past this share of the height a continuous corner runs out of room, and the edge
    /// shows a notch on either side.
    private static let roundest: CGFloat = 0.4
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        let radius = min(GlowTokens.Radius.popoverAction - inset, rect.height * Self.roundest)
        return RoundedRectangle(cornerRadius: max(0, radius), style: .continuous).path(in: rect)
    }

    func inset(by amount: CGFloat) -> PopoverButtonShape {
        var shape = self
        shape.inset += amount
        return shape
    }
}

/// An action button's label: an accent-coloured icon, then the title.
struct ActionLabel: View {
    let title: String
    let symbol: String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: GlowTokens.Space.s1_5) {
            Image(systemName: symbol)
                .font(GlowTokens.Typography.actionSymbol)
                .foregroundStyle(isEnabled ? GlowTokens.Accent.primary : GlowTokens.Text.tertiary)
            Text(title)
        }
    }
}

/// A checkbox as a Settings button: selected, with a checkmark, while it's on. Without its
/// title showing it's a small square for the start of a row, still named by `title` for
/// VoiceOver and its tooltip. VoiceOver reads it as the checkbox it stands for.
struct CheckButton: View {
    let title: String
    var showsTitle = true
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: GlowTokens.Space.s1_5) {
                Image(systemName: "checkmark")
                    .font(GlowTokens.Typography.actionSymbol)
                    .foregroundStyle(isEnabled ? GlowTokens.Accent.primary : GlowTokens.Text.tertiary)
                    // Kept in place while off, so the button doesn't change width.
                    .opacity(isOn ? 1 : 0)
                if showsTitle { Text(title) }
            }
        }
        .buttonStyle(ActionButtonStyle(compact: true, isSelected: isOn))
        .help(title)
        .accessibilityRepresentation {
            Toggle(title, isOn: $isOn)
        }
    }
}

/// A few fixed choices as a row of buttons, the chosen one selected, in place of a pop-up
/// menu. A long list, or one that comes from a display, is a `MenuPicker` instead.
struct ChoiceButtons<Value: Hashable>: View {
    struct Option: Identifiable {
        var value: Value
        var title: String
        var id: Value { value }
    }

    /// What's being chosen, for VoiceOver.
    let label: String
    var options: [Option]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: GlowTokens.Space.s1) {
            ForEach(options) { option in
                let selected = option.value == selection
                Button(option.title) { selection = option.value }
                    .buttonStyle(ActionButtonStyle(compact: true, isSelected: selected))
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// A native menu behind a trigger in the action buttons' compact style: the label, then a
/// small chevron saying a menu opens.
struct SettingsMenu<Content: View, Label: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var label: () -> Label

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: GlowTokens.Space.s1) {
                label()
                Image(systemName: "chevron.down")
                    .font(GlowTokens.Typography.menuChevron)
                    .foregroundStyle(GlowTokens.Text.secondary)
            }
        }
        // `.button` is the menu style that draws its label with the button style.
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(ActionButtonStyle(compact: true))
        .fixedSize()
    }
}

/// One choice from a list that can be long or comes from a display or the system, such as a
/// display's inputs: a menu whose trigger shows the current choice, and `placeholder` when
/// there's none. A few fixed choices are `ChoiceButtons` instead.
struct MenuPicker<Value: Hashable>: View {
    struct Option: Identifiable {
        var value: Value
        var title: String
        var id: Value { value }
    }

    /// What's being chosen, for VoiceOver.
    let label: String
    var options: [Option]
    @Binding var selection: Value?
    var placeholder = "None"

    var body: some View {
        let current = options.first { $0.value == selection }?.title ?? placeholder
        SettingsMenu {
            // A toggle in a menu is an item with a checkmark when it's on.
            ForEach(options) { option in
                Toggle(option.title, isOn: Binding(
                    get: { selection == option.value },
                    set: { if $0 { selection = option.value } }
                ))
            }
        } label: {
            Text(current)
        }
        .accessibilityLabel(label)
        .accessibilityValue(current)
    }
}
