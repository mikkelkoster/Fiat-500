import SwiftUI

/// The top of the home screen: the owner's car in a pool of light, the car's name over it with the plate and when it last reported, the status line at the foot.
struct CarHero: View {
    let carName: String
    let plate: String
    let carColor: Color
    let image: Image?
    let heating: Bool
    let lightsOn: Bool
    /// The picture is one of the 500e renders, whose lamp position is known.
    var lampsKnown = false
    let status: [StatusItem]
    var updated: String? = nil
    var height: CGFloat = 420
    var onSettings: (() -> Void)? = nil
    /// Other cars on the account (VIN, name); with more than one, the plate opens a switcher.
    var cars: [(vin: String, name: String)] = []
    var onSwitchCar: ((String) -> Void)? = nil
    /// Wakes the car for fresh numbers; shown on the "Updated" time.
    var onWake: (() -> Void)? = nil
    var waking = false
    /// Shown at the end of the status line when the car is plugged in and not charging.
    var onChargeNow: (() -> Void)? = nil
    var chargeBusy = false

    struct StatusItem: Identifiable, Equatable {
        let text: String
        var color: Color? = nil
        var id: String { text }
    }

    @State private var breathe = false
    @State private var shimmer = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let imageWidth = w * 620 / 390
            let imageHeight = imageWidth * 640 / 1200
            let imageTop = 118 * w / 390 + max(0, geo.size.height - 420) * 0.4
            ZStack(alignment: .topLeading) {
                spotlight
                if let image {
                    // A soft shadow of our own under the wheels; the picture has none.
                    Ellipse()
                        .fill(RadialGradient(colors: [.black.opacity(0.75), .black.opacity(0)], center: .center, startRadius: 0, endRadius: imageWidth * 0.26))
                        .frame(width: imageWidth * 0.56, height: imageHeight * 0.075)
                        .position(x: w / 2 - imageWidth / 2 + imageWidth * 0.5, y: imageTop + imageHeight * 0.755)
                    if heating {
                        // A blurred warm copy of the car itself breathes under it.
                        image.resizable().aspectRatio(contentMode: .fit)
                            .frame(width: imageWidth)
                            .colorMultiply(V.heat).brightness(0.2).blur(radius: 22)
                            .blendMode(.screen)
                            .scaleEffect(breathe ? 1.03 : 1, anchor: .center)
                            .opacity(breathe ? 1 : 0.55)
                            .position(x: w / 2, y: imageTop + imageHeight / 2)
                        warmEllipse(w: imageWidth * 0.44, h: imageHeight * 0.18)
                            .position(x: w / 2, y: imageTop + imageHeight * 0.9)
                    }
                    image.resizable().aspectRatio(contentMode: .fit)
                        .frame(width: imageWidth)
                        .position(x: w / 2, y: imageTop + imageHeight / 2)
                    if heating {
                        warmEllipse(w: imageWidth * 0.38, h: imageHeight * 0.25, bright: true)
                            .position(x: w / 2 - imageWidth * 0.02, y: imageTop + imageHeight * 0.36)
                        ForEach(0..<3, id: \.self) { i in
                            let x = w / 2 + CGFloat(i - 1) * imageWidth * 0.1
                            Ellipse().fill(RadialGradient(colors: [Color(hex: 0xfed7aa).opacity(0.55), V.heat.opacity(0)], center: .center, startRadius: 0, endRadius: 30))
                                .frame(width: 46, height: 74)
                                .blur(radius: 7)
                                .blendMode(.screen)
                                .offset(y: shimmer ? -46 : 26)
                                .opacity(shimmer ? 0 : 0.75)
                                .animation(.timingCurve(0.3, 0.1, 0.2, 1, duration: 3.6).repeatForever(autoreverses: false).delay(Double(i) * 1.2), value: shimmer)
                                .position(x: x, y: imageTop + imageHeight * 0.14)
                        }
                    }
                    if lightsOn, lampsKnown {
                        // Only where the lamp position is known for this render.
                        Ellipse().fill(RadialGradient(colors: [Color(hex: 0xfef3c7).opacity(0.6), Color(hex: 0xfef3c7).opacity(0)], center: .center, startRadius: 0, endRadius: 40))
                            .frame(width: imageWidth * 0.177, height: imageHeight * 0.18)
                            .blur(radius: 4)
                            .position(x: w / 2 - imageWidth / 2 + imageWidth * 0.485, y: imageTop + imageHeight * 0.41)
                    }
                } else {
                    CarSilhouette().fill(V.raised)
                        .frame(width: imageWidth * 0.7, height: imageWidth * 0.7 * 0.5)
                        .position(x: w / 2, y: imageTop + imageHeight * 0.55)
                }
                LinearGradient(colors: [V.ground.opacity(0), V.ground], startPoint: .top, endPoint: .bottom)
                    .frame(height: 120)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                VStack(alignment: .leading, spacing: 0) {
                    // Settings alone at the top right, clear of the Dynamic Island; the name below it.
                    HStack {
                        Spacer()
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
                    Text(carName).font(V.display).tracking(-3).foregroundStyle(V.text)
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .padding(.top, -8)
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
                            Button { onWake?() } label: {
                                HStack(spacing: 5) {
                                    Text(waking ? "Asking the car…" : updated).font(V.label).foregroundStyle(V.textMuted).lineLimit(1)
                                    if onWake != nil {
                                        PhIcon(name: "arrows-clockwise", size: 11).foregroundStyle(V.textMuted)
                                            .rotationEffect(.degrees(waking ? 360 : 0))
                                            .animation(waking ? .linear(duration: 1.2).repeatForever(autoreverses: false) : .default, value: waking)
                                    }
                                }
                                .frame(height: 24).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(onWake == nil || waking)
                            .accessibilityHint("Wakes the car for fresh numbers")
                        }
                    }
                    // The name's line box leaves room for descenders it rarely has; tuck the row up into it.
                    .padding(.top, -8)
                }
                .padding(.horizontal, V.gutter)
                .padding(.top, 54)

                HStack(spacing: 8) {
                    statusLine
                    if let onChargeNow {
                        Button(action: onChargeNow) {
                            HStack(spacing: 5) {
                                if chargeBusy { ProgressView().controlSize(.mini).tint(V.positive) }
                                else { PhIcon(name: "lightning", size: 12) }
                                Text(chargeBusy ? "Starting…" : "Charge now").font(V.label)
                            }
                            .foregroundStyle(V.positive)
                            .padding(.horizontal, 12).frame(height: 30)
                            .glassCapsule(tint: nil)
                        }
                        .buttonStyle(.plain)
                        .disabled(chargeBusy)
                    }
                }
                // Same height with or without Charge now, so the line doesn't jump.
                .frame(height: 30)
                .padding(.horizontal, V.gutter)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 2)
            }
        }
        .frame(height: height)
        .clipped()
        .onAppear { startAnimations() }
        .onChange(of: heating) { _, _ in startAnimations() }
    }

    private func startAnimations() {
        breathe = false; shimmer = false
        guard heating else { return }
        withAnimation(.timingCurve(0.45, 0, 0.55, 1, duration: 4.2).repeatForever(autoreverses: true)) { breathe = true }
        shimmer = true
    }

    private var spotlight: some View {
        let tint: Color = carColor.luminance < 0.15 ? V.outline : carColor.opacity(0.24)
        let centre = heating ? Color(hex: 0x431407) : tint
        let mid = heating ? Color(hex: 0x1c1917) : V.surface
        return RadialGradient(colors: [centre, mid, V.ground], center: UnitPoint(x: 0.5, y: 0.7), startRadius: 0, endRadius: 320)
            .animation(.easeInOut(duration: 1.2), value: heating)
    }

    private func warmEllipse(w: CGFloat, h: CGFloat, bright: Bool = false) -> some View {
        Ellipse()
            .fill(RadialGradient(colors: bright
                ? [Color(hex: 0xfed7aa).opacity(0.85), V.heat.opacity(0.5), V.heat.opacity(0)]
                : [V.heat.opacity(0.34), V.heat.opacity(0)], center: .center, startRadius: 0, endRadius: max(w, h) / 2))
            .frame(width: w, height: h)
            .blur(radius: 6)
            .blendMode(.screen)
            .opacity(breathe ? 0.95 : 0.45)
            .scaleEffect(x: breathe ? 1.06 : 1)
    }

    private var plateChipText: some View {
        Text(plate.isEmpty ? carName : plate).font(V.sora(12, .medium)).tracking(0.5).foregroundStyle(V.text).lineLimit(1)
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            ForEach(Array(status.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Text("·").font(V.label).foregroundStyle(V.textFaint) }
                HStack(spacing: 6) {
                    if let color = item.color { Circle().fill(color).frame(width: 8, height: 8) }
                    Text(item.text).font(V.label).foregroundStyle(item.color ?? V.textMuted).fixedSize()
                }
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

/// A plain side-view car, for a car we have no picture of.
struct CarSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        SVGPath.path("M4 70 L4 50 Q4 40 14 38 L24 36 L38 14 Q44 6 56 6 L92 6 Q104 6 110 14 L124 36 L134 38 Q140 40 140 50 L140 70 Z", in: rect, viewBox: CGSize(width: 144, height: 72))
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
