import SwiftUI
import UIKit

// The building blocks this app uses from Torque's design system, ported from torque-ios
// (Views/Components/Primitives.swift, Notice.swift, Motion.swift, Plan/SessionSheets.swift,
// AppShell.swift), last synced with torque-ios main at 9171fd2. Same names, sizes and tokens,
// so a screen here reads like a Torque screen.
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

/// Solid, no lens: primary black; secondary white with a neutral 200 edge on every ground, the
/// white page or a grey card.
private struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let prominent: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if prominent {
            content.background(shape.fill(Ink.primary).elevation(.button))
        } else {
            content.background(shape.fill(Ink.controlOnCard).overlay(shape.stroke(Ink.controlBorder, lineWidth: 1)).elevation(.button))
        }
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

/// The one round icon button: an SF Symbol on a circle in the secondary button's style, or black
/// when `prominent`. Every circle icon control draws this. Two sizes: `ControlSize.regular` (34) in
/// content, `ControlSize.bar` (44) in a sheet's header. The tap area is 44 pt either way.
struct IconButton: View {
    let systemImage: String
    let label: String
    var size: CGFloat = ControlSize.regular
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconButtonLabel(systemImage: systemImage, size: size, prominent: prominent)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// IconButton's look on its own, for a control that isn't a Button: a stepper's − and +.
struct IconButtonLabel: View {
    let systemImage: String
    var size: CGFloat = ControlSize.regular
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        // Medium at 44, a step smaller and semibold at 34, so the strokes read the same weight.
        Image(systemName: systemImage)
            .font(size >= ControlSize.bar ? Icon.l.weight(.medium) : Icon.m.weight(.semibold))
            .imageScale(.medium)
            .foregroundStyle(!isEnabled ? Ink.disabledText : prominent ? Ink.onPrimary : Ink.foreground)
            .frame(width: size, height: size)
            .glass(Circle(), prominent: prominent && isEnabled)
            .frame(width: max(44, size), height: max(44, size))
            .contentShape(Rectangle())
    }
}

struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        IconButton(systemImage: "xmark", label: "Close", size: ControlSize.bar, action: action)
    }
}

/// An answer as underlined words rather than a button: a toast's Undo. Body Medium in the ink;
/// `quiet` is Body in the subtle grey. The tap area is 44 pt.
struct TextLink: View {
    let title: String
    var quiet = false
    var color: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(quiet ? Type.body : Type.bodyMedium)
                .foregroundStyle(color ?? (quiet ? Ink.subtle : Ink.foreground)).underline()
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Controls

/// The app's switch, its state drawn inside: a check beside the knob on the ink track when on, a
/// cross on grey when off, so on and off read apart in dark too. Any label after it, a 44 pt row;
/// the whole row toggles. To VoiceOver and UI tests it is still a switch.
struct WeeklySwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            MarkSwitch(isOn: configuration.isOn)
            configuration.label
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.select()
            withAnimation(.snappy(duration: Motion.normal)) { configuration.isOn.toggle() }
        }
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// The capsule itself: 56 × 32, a 26 pt white knob that slides, and both marks always drawn, each
/// on its own side, crossfading as the knob passes, so nothing jumps.
struct MarkSwitch: View {
    let isOn: Bool
    @Environment(\.isEnabled) private var enabled
    static let width: CGFloat = 56, height: CGFloat = 32, inset: CGFloat = 3

    var body: some View {
        let knob = Self.height - Self.inset * 2
        let side = Self.width - knob - Self.inset * 2   // the room beside the knob
        ZStack(alignment: .leading) {
            Capsule().fill(isOn ? Ink.switchOn : Ink.switchOff)
            Image(systemName: "checkmark").font(Icon.s.weight(.bold))
                .foregroundStyle(Ink.switchOnText)
                .frame(width: side).offset(x: Self.inset)
                .opacity(isOn ? 1 : 0)
            Image(systemName: "xmark").font(Icon.xs.weight(.bold))
                .foregroundStyle(Ink.switchOffText)
                .frame(width: side).offset(x: Self.width - side - Self.inset)
                .opacity(isOn ? 0 : 1)
            Circle().fill(Ink.knob)
                .elevation(.knob)
                .frame(width: knob, height: knob)
                .offset(x: isOn ? Self.width - knob - Self.inset : Self.inset)
        }
        .frame(width: Self.width, height: Self.height)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityHidden(true)
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
            IconButtonLabel(systemImage: icon, size: ControlSize.bar)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Days of the week as chips: picked ones a soft grey under ink words, the rest white with an
/// edge. `days` are Calendar weekdays (1 = Sunday … 7 = Saturday).
struct DayPicker: View {
    let days: [Int]
    let selected: Set<Int>
    let toggle: (Int) -> Void

    var body: some View {
        let short = Calendar.current.shortWeekdaySymbols
        let long = Calendar.current.weekdaySymbols
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { d in
                let on = selected.contains(d)
                Button {
                    Haptics.select()
                    withAnimation(.easeOut(duration: Motion.fast)) { toggle(d) }
                } label: {
                    Text(short[d - 1]).font(Type.footnoteMedium)
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .foregroundStyle(on ? Ink.foreground : Ink.muted)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(Capsule().fill(on ? Ink.chipOn : Ink.controlOnCard))
                        .overlay(Capsule().strokeBorder(on ? Color.clear : Ink.controlBorder, lineWidth: 1))
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(long[d - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
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
        .background(Ink.field, in: RoundedRectangle(cornerRadius: Radius.control))
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
            // The close button is centred on the title's first line, so a title that wraps grows
            // downwards and keeps it where a one-line title has it.
            HStack(alignment: .sheetTitleLine, spacing: 12) {
                Text(title).font(Type.title).tracking(-24 * 0.025).foregroundStyle(Ink.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .alignmentGuide(.sheetTitleLine) { d in (d[.firstTextBaseline] + d.height - d[.lastTextBaseline]) / 2 }
                Spacer(minLength: 0)
                CloseButton(action: onClose)
            }
            if !subtitle.isEmpty {
                Text(subtitle).font(Type.body).foregroundStyle(Ink.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Space.gutter).padding(.top, 22).padding(.bottom, 18)
    }
}

extension VerticalAlignment {
    /// A sheet header's title line: the middle of a title's first line, the middle of the buttons.
    fileprivate enum SheetTitleLine: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] }
    }
    fileprivate static let sheetTitleLine = VerticalAlignment(SheetTitleLine.self)
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
                TextLink(title: action.title, color: Ink.onPrimary, action: action.run)
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
