import SwiftUI
import UIKit

// The building blocks this app uses from Torque's design system, ported from torque-ios
// (Views/Components/Primitives.swift, Notice.swift, Motion.swift, Plan/SessionSheets.swift,
// AppShell.swift). Same names, sizes and tokens, so a screen here reads like a Torque screen.
// Keep them dumb: layout and tokens only.

// MARK: - Motion & haptics

enum Motion {
    /// Taps, toggles, small state changes.
    static let fast: Double = 0.15
    /// Rows expanding, toasts, numbers changing.
    static let normal: Double = 0.25
    /// A value the user changed: figures count and rows slide on this one curve.
    static let change: Animation = .easeInOut(duration: 0.4)
}

enum Haptics {
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) { UIImpactFeedbackGenerator(style: style).impactOccurred() }
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) { UINotificationFeedbackGenerator().notificationOccurred(type) }
}

// MARK: - Surfaces

extension View {
    /// A control's ground: primary black, secondary grey on the page and white on a card.
    func glass<S: Shape>(_ shape: S, prominent: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, prominent: prominent))
    }

    /// A card: flat grey on the white page, no border, no shadow.
    func cardSurface(corner: CGFloat = Radius.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return environment(\.onCard, true).clipShape(shape).background(shape.fill(Ink.card))
    }

    /// A line under a row in a card; the last row goes without.
    func rowRule(_ shown: Bool) -> some View {
        overlay(alignment: .bottom) {
            if shown { Rectangle().fill(Ink.border).frame(height: 1) }
        }
    }
}

private struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let prominent: Bool
    @Environment(\.onCard) private var onCard

    func body(content: Content) -> some View {
        content.background(shape.fill(prominent ? Ink.primary : onCard ? Ink.controlOnCard : Ink.control).elevation(.button))
    }
}

private struct OnCardKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Set by `cardSurface()` for the controls drawn on a card.
    var onCard: Bool {
        get { self[OnCardKey.self] }
        set { self[OnCardKey.self] = newValue }
    }
}

/// Apple's control heights: regular 34 pt inside content, 44 pt in the top bar. Every button's
/// tap area stays at least 44 pt whatever it draws.
enum ControlSize {
    static let small: CGFloat = 28
    static let regular: CGFloat = 34
    static let bar: CGFloat = 44
}

/// The NoticeCard box without the dot: content that belongs together as one object.
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(Space.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }
}

struct CardStack<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.cardGap) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A heading over a card, with an optional line of help and an action on the right
/// (design-system.md: "Section header with an action").
struct CardSection<Content: View, Action: View>: View {
    let title: String
    var help: String? = nil
    @ViewBuilder let action: Action
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Type.heading).tracking(-0.3).foregroundStyle(Ink.foreground)
                    if let help { Text(help).font(Type.footnote).foregroundStyle(Ink.muted) }
                }
                Spacer(minLength: 8)
                action
            }
            content
        }
    }
}

extension CardSection where Action == EmptyView {
    init(title: String, help: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, help: help, action: { EmptyView() }, content: content)
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Ink.border).frame(height: 1) }
}

struct RowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(Icon.s.weight(.semibold)).foregroundStyle(Ink.muted)
            .accessibilityHidden(true)
    }
}

// MARK: - Buttons

/// 44 pt primary / outline buttons. Disabled draws the one disabled look: a flat grey fill with grey text.
struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var outline = false
    var height: CGFloat = 44
    /// Text color for the outline variant (red for a destructive action).
    var tint: Color = Ink.foreground
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PrimaryButtonLabel(title: title, icon: icon, outline: outline, height: height, tint: tint)
        }
        .buttonStyle(PressableStyle())
    }
}

struct PrimaryButtonLabel: View {
    let title: String
    var icon: String? = nil
    var outline = false
    var height: CGFloat = 44
    var tint: Color = Ink.foreground
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 8) {
            if let icon { Image(systemName: icon).font(Icon.m.weight(.medium)) }
            Text(title).font(Type.bodyMedium)
        }
        .foregroundStyle(!isEnabled ? Ink.disabledText : outline ? tint : Ink.onPrimary)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .modifier(ButtonSurface(outline: outline, enabled: isEnabled))
        .contentShape(Capsule())
    }
}

struct ButtonSurface: ViewModifier {
    let outline: Bool
    let enabled: Bool

    func body(content: Content) -> some View {
        if !enabled {
            content.background(Capsule().fill(Ink.disabledFill))
        } else {
            content.glass(Capsule(), prominent: !outline)
        }
    }
}

/// Buttons give slightly under the finger, so a tap visibly registers before anything loads.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: Motion.fast), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { Haptics.tap() } }
    }
}

struct SmallButtonLabel: View {
    let title: String
    var icon: String? = nil
    var color: Color = Ink.foreground
    var primary = false
    var height: CGFloat = ControlSize.regular

    var body: some View {
        let small = height < ControlSize.regular
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(Icon.s.weight(.semibold)) }
            Text(title).font(small ? Type.footnoteMedium : Type.bodyMedium).lineLimit(1).fixedSize()
        }
        .foregroundStyle(primary ? Ink.onPrimary : color)
        .padding(.horizontal, icon != nil || small ? 12 : 14)
        .frame(height: height)
        .glass(Capsule(), prominent: primary)
        .contentShape(Rectangle())
    }
}

/// Small 34 pt button with a 44 pt hit area ("Add", "Settings").
struct SmallButton: View {
    let title: String
    var icon: String? = nil
    var color: Color = Ink.foreground
    var primary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SmallButtonLabel(title: title, icon: icon, color: color, primary: primary)
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: .close, action: action) {
                Image(systemName: "xmark").font(Icon.l.weight(.medium))
                    .foregroundStyle(Ink.foreground)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Close")
        } else {
            Button(action: action) {
                Image(systemName: "xmark").font(Icon.s.weight(.medium)).foregroundStyle(Ink.foreground)
                    .frame(width: 32, height: 32).background(Circle().fill(Ink.mutedBg))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }
}

// MARK: - Controls

/// The app's switch: the system's own, in the accent ink, with any label after it and a 44 pt row.
struct WeeklySwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Ink.accent)
                .fixedSize()
            configuration.label
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

/// − value +: the value between two 44 pt glass buttons.
struct NumberStepper: View {
    let value: String
    var unit: String? = nil
    let canDecrease: Bool
    let canIncrease: Bool
    let decrease: () -> Void
    let increase: () -> Void
    var valueWidth: CGFloat = 64

    var body: some View {
        HStack(spacing: 2) {
            button("minus", enabled: canDecrease, action: decrease)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(Type.monoEmphasis).foregroundStyle(Ink.foreground).tabular()
                    .contentTransition(.numericText())
                    .animation(Motion.change, value: value)
                if let unit { Text(unit).font(Type.monoFootnote).foregroundStyle(Ink.muted) }
            }
            .frame(minWidth: valueWidth)
            button("plus", enabled: canIncrease, action: increase)
        }
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(unit.map { "\(value) \($0)" } ?? value)
        .accessibilityAdjustableAction { d in d == .increment ? (canIncrease ? increase() : ()) : (canDecrease ? decrease() : ()) }
    }

    private func button(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap(.light)
            withAnimation(Motion.change) { action() }
        } label: {
            Image(systemName: icon).font(Icon.l.weight(.semibold))
                .foregroundStyle(enabled ? Ink.foreground : Ink.disabledText)
                .frame(width: ControlSize.bar, height: ControlSize.bar)
                .glass(Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Days of the week as one segmented strip. `days` are Calendar weekdays (1 = Sunday … 7 = Saturday).
struct DayPicker: View {
    let days: [Int]
    let selected: Set<Int>
    let toggle: (Int) -> Void

    var body: some View {
        let short = Calendar.current.shortWeekdaySymbols
        let long = Calendar.current.weekdaySymbols
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element) { i, d in
                let on = selected.contains(d)
                Button {
                    Haptics.select()
                    withAnimation(.easeOut(duration: Motion.fast)) { toggle(d) }
                } label: {
                    Text(short[d - 1]).font(Type.footnoteMedium)
                        .foregroundStyle(on ? Ink.onPrimary : Ink.secondary)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(on ? Ink.accent : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // A short line between two days of the same state, so a run of picked days still reads as days.
                .overlay(alignment: .leading) {
                    if i > 0, on == selected.contains(days[i - 1]) {
                        Rectangle().fill(on ? Ink.onAccentDivider : Ink.border).frame(width: 1).padding(.vertical, 12)
                    }
                }
                .accessibilityLabel(long[d - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .background(Ink.mutedBg)
        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
    }
}

/// A text field on a form: 44 tall, surface fill, hairline edge.
struct FormTextField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .font(Type.body).foregroundStyle(Ink.foreground)
        .padding(.horizontal, 12).frame(height: 44)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: Radius.control))
        .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Ink.border, lineWidth: 1))
    }
}

// MARK: - Tags, headers, toasts

/// A state in words on a light pill: neutral grey; good, caution and bad tinted.
struct DayTag: View {
    enum Tone { case neutral, good, caution, bad }
    let text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text).font(Type.label)
            .lineLimit(1).fixedSize()
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .frame(minHeight: 20)
            .background(Capsule().fill(fill))
    }

    private var ink: Color {
        switch tone {
        case .good: Ink.greenText
        case .caution: Ink.yellowText
        case .bad: Ink.redText
        case .neutral: Ink.secondary
        }
    }

    private var fill: Color {
        switch tone {
        case .good: Ink.greenBg
        case .caution: Ink.yellowBg
        case .bad: Ink.redBg
        case .neutral: Ink.mutedBg
        }
    }
}

/// A sheet's title with the close button centred on the title line, and an optional subtitle.
struct SheetHeader: View {
    let title: String
    var subtitle: String = ""
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 12) {
                Text(title).font(Type.title).tracking(-24 * 0.025).foregroundStyle(Ink.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                CloseButton(action: onClose)
            }
            if !subtitle.isEmpty {
                Text(subtitle).font(Type.body).foregroundStyle(Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Space.gutter).padding(.top, 22).padding(.bottom, 28)
    }
}

/// A word from the app at the foot of the screen, on `primary`: what just happened, and when there
/// is something to say back, the answer as an underlined link.
struct Toast: View {
    struct Action {
        let title: String
        let run: () -> Void
    }

    let title: String
    var detail: String? = nil
    var leading: AnyView? = nil
    var action: Action? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 10) {
                if let leading { leading }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Type.bodyMedium).foregroundStyle(Ink.onPrimary)
                        .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail).font(Type.body).foregroundStyle(Ink.onPrimary.opacity(0.75))
                            .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let action {
                Button(action.title, action: action.run)
                    .font(Type.bodyMedium).foregroundStyle(Ink.onPrimary).underline()
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
        }
        .padding(.leading, 16).padding(.trailing, action == nil ? 16 : 8)
        .padding(.vertical, detail == nil ? 10 : 8).frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(Ink.primary))
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Where a Toast sits: centred at the foot of the screen, inside the gutters, sliding up.
    func toastPlacement() -> some View {
        padding(.horizontal, Space.gutter)
            .padding(.bottom, Space.toastBottom)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
