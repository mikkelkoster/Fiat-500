import SwiftUI

// Varme's components. Each matches a card in the published design system.

// MARK: - Buttons

/// The white pill button, 60 pt (64 in the hero). `prominent: false` is the raised secondary.
struct VButton: View {
    let title: String
    var icon: String? = nil
    var prominent = true
    var height: CGFloat = V.buttonHeight
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon { PhIcon(name: icon, size: 20) }
                Text(title).font(prominent ? V.button : V.body)
            }
            .foregroundStyle(tint ?? (prominent ? V.ground : V.text))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Capsule().fill(prominent ? V.text : V.raised))
            .overlay(Capsule().strokeBorder(V.raised, lineWidth: prominent ? 0 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

/// Buttons give slightly under the finger.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { Haptics.tap() } }
    }
}

/// A 36 pt round close button for sheet headers.
struct VCloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            PhIcon(name: "x", size: 16)
                .foregroundStyle(V.text)
                .frame(width: 36, height: 36)
                .background(Circle().fill(V.raised))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Close")
    }
}

/// A round raised button holding one icon: the time stepper, the sheet actions.
struct VRoundButton: View {
    let icon: String
    let label: String
    var size: CGFloat = 56
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            PhIcon(name: icon, size: size * 0.4)
                .foregroundStyle(V.text)
                .frame(width: size, height: size)
                .background(Circle().fill(V.surface))
                .overlay(Circle().strokeBorder(V.raised, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - Sheet header

struct VSheetHeader: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(V.outline).frame(width: 40, height: 4).padding(.top, 10)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow).eyebrowStyle()
                    Text(title).font(V.title).foregroundStyle(V.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle { Text(subtitle).font(V.label).foregroundStyle(V.textMuted) }
                }
                Spacer(minLength: 8)
                VCloseButton(action: onClose)
            }
            .padding(.horizontal, V.gutter)
            .padding(.top, 14)
        }
    }
}

/// Sheet chrome: surface, 32 pt top corners, a hairline.
extension View {
    func varmeSheet(_ detents: Set<PresentationDetent> = [.large]) -> some View {
        presentationDetents(detents)
            .presentationBackground(V.surface)
            .presentationCornerRadius(V.radiusSheet)
            .presentationDragIndicator(.hidden)
    }
}

// MARK: - Switch

/// Torque's switch in Varme's colours: 56 × 32, a white knob, the state drawn inside the
/// track (a check on green when on, a cross on outline when off). The whole row toggles.
struct VSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let knob: CGFloat = 26, inset: CGFloat = 3, width: CGFloat = 56, height: CGFloat = 32
        Button {
            Haptics.select()
            withAnimation(.snappy(duration: 0.25)) { isOn.toggle() }
        } label: {
            ZStack(alignment: .leading) {
                Capsule().fill(isOn ? V.positive : V.outline)
                PhIcon(name: "check", size: 12).foregroundStyle(V.ground)
                    .frame(width: width - knob - inset * 2).offset(x: inset)
                    .opacity(isOn ? 1 : 0)
                PhIcon(name: "x", size: 10).foregroundStyle(V.textMuted)
                    .frame(width: width - knob - inset * 2).offset(x: knob + inset)
                    .opacity(isOn ? 0 : 1)
                Circle().fill(.white)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                    .frame(width: knob, height: knob)
                    .offset(x: isOn ? width - knob - inset : inset)
            }
            .frame(width: width, height: height)
            .opacity(enabled ? 1 : 0.5)
            .frame(minHeight: V.control)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle("", isOn: $isOn) }
    }
}

/// A 56 pt raised row with a label on the left and a switch on the right. No helper text.
struct VSwitchRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(V.body).foregroundStyle(V.text)
                if let detail { Text(detail).font(V.label).foregroundStyle(V.textMuted) }
            }
            Spacer()
            VSwitch(isOn: $isOn)
        }
        .padding(.leading, 18).padding(.trailing, 12)
        .frame(minHeight: 56)
        .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.raised))
        .contentShape(Rectangle())
        .onTapGesture { Haptics.select(); withAnimation(.snappy(duration: 0.25)) { isOn.toggle() } }
    }
}

// MARK: - Cards

struct VCard<Content: View>: View {
    var fill: Color = V.surface
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).strokeBorder(V.raised, lineWidth: 1))
    }
}

// MARK: - Toast

/// What the last command did, said once at the foot of the screen.
struct VToast: View {
    let title: String
    var detail: String? = nil
    var isError = false

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(isError ? V.danger : V.positive).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(V.body).foregroundStyle(V.text)
                if let detail { Text(detail).font(V.label).foregroundStyle(V.textMuted).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.raised))
        .overlay(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).strokeBorder(V.outline, lineWidth: 1))
        .padding(.horizontal, V.gutter)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Rolling digits

/// Text whose changed characters slide in: from below when the value went up, from above when down.
struct RollingText: View {
    let text: String
    let font: Font
    var up = true

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .font(font)
                    .transition(.asymmetric(
                        insertion: .move(edge: up ? .bottom : .top).combined(with: .opacity),
                        removal: .move(edge: up ? .top : .bottom).combined(with: .opacity)))
                    .id(ch)
            }
        }
        .clipped()
        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.42), value: text)
    }
}
