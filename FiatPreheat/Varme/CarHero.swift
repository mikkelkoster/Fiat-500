import SwiftUI

/// The top of the home screen: the plate and when the car last reported, settings, and the
/// car's name, on a soft pool of light. No picture of the car: the gauge below is the hero.
struct CarHero: View {
    let carName: String
    let plate: String
    var updated: String? = nil
    var height: CGFloat = 196
    var onSettings: (() -> Void)? = nil
    /// Other cars on the account (VIN, name); with more than one, the plate opens a switcher.
    var cars: [(vin: String, name: String)] = []
    var onSwitchCar: ((String) -> Void)? = nil


    var body: some View {
        ZStack(alignment: .topLeading) {
            spotlight
            // The light fades into the page instead of ending in a line.
            LinearGradient(colors: [V.ground.opacity(0), V.ground], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .frame(maxHeight: .infinity, alignment: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                // Plate and update time on the left, settings on the right, clear of the Dynamic Island.
                HStack(alignment: .center, spacing: 10) {
                    HStack(spacing: 10) {
                        if cars.count > 1, let onSwitchCar {
                            Menu {
                                ForEach(cars, id: \.vin) { car in
                                    Button(car.name) { onSwitchCar(car.vin) }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    plateChipText
                                    PhIcon(name: "caret-down", size: 10)
                                }
                                .foregroundStyle(V.text)
                                .padding(.horizontal, 10).frame(height: 24)
                                .background(Capsule().fill(V.scrim))
                                .overlay(Capsule().strokeBorder(V.outline, lineWidth: 1))
                            }
                            .accessibilityLabel("Switch car")
                        } else if !plate.isEmpty {
                            plateChipText
                                .padding(.horizontal, 10).frame(height: 24)
                                .background(Capsule().fill(V.scrim))
                                .overlay(Capsule().strokeBorder(V.outline, lineWidth: 1))
                        }
                        if let updated {
                            // Pulling the page down refreshes; this only says when.
                            Text(updated).font(V.label).foregroundStyle(V.textMuted).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    if let onSettings {
                        Button(action: onSettings) {
                            PhIcon(name: "gear", size: 20).foregroundStyle(V.text)
                                .frame(width: 44, height: 44)
                                .glassCircle()
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, -4)
                        .accessibilityLabel("Settings")
                    }
                }
                .frame(height: 44)
                // A long name shrinks to fit one line rather than running under the car.
                Text(carName).font(V.sora(42, .ultraLight)).tracking(-1.2).foregroundStyle(V.text)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .padding(.top, 2)

            }
            .padding(.horizontal, V.gutter)
            .padding(.top, 54)

        }
        .frame(height: height)
        .clipped()
    }

    /// A soft pool of light behind the name.
    private var spotlight: some View {
        RadialGradient(colors: [V.outline, V.surface, V.ground], center: UnitPoint(x: 0.5, y: 0.7), startRadius: 0, endRadius: 320)
    }

    private var plateChipText: some View {
        Text(plate.isEmpty ? carName : plate).font(V.sora(12, .medium)).tracking(0.5).foregroundStyle(V.text).lineLimit(1)
    }
}

/// Just enough of SVG path syntax (M L H V Q C Z, absolute) to carry the design's shapes into Swift.
enum SVGPath {
    static func path(_ d: String, in rect: CGRect, viewBox: CGSize) -> Path {
        var path = Path()
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let ox = rect.midX - viewBox.width * scale / 2, oy = rect.midY - viewBox.height * scale / 2
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * scale, y: oy + y * scale) }
        let tokens = d.replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "([MLHVQCZmlhvqcz])", with: " $1 ", options: .regularExpression)
            .split(separator: " ").map(String.init)
        var i = 0, cmd = "M", current = CGPoint.zero
        func num() -> Double { defer { i += 1 }; return Double(tokens[i]) ?? 0 }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter { cmd = tokens[i]; i += 1; if cmd == "Z" { path.closeSubpath(); continue } }
            switch cmd {
            case "M": current = pt(num(), num()); path.move(to: current); cmd = "L"
            case "L": current = pt(num(), num()); path.addLine(to: current)
            case "H": current = CGPoint(x: pt(num(), 0).x, y: current.y); path.addLine(to: current)
            case "V": current = CGPoint(x: current.x, y: pt(0, num()).y); path.addLine(to: current)
            case "Q": let c = pt(num(), num()); current = pt(num(), num()); path.addQuadCurve(to: current, control: c)
            case "C": let c1 = pt(num(), num()), c2 = pt(num(), num()); current = pt(num(), num()); path.addCurve(to: current, control1: c1, control2: c2)
            default: i += 1
            }
        }
        return path
    }
}
