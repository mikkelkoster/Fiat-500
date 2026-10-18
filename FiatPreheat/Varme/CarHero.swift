import SwiftUI

/// The top of the home screen: the plate and when the car last reported, settings, the car's name,
/// and the car itself in a pool of light, large enough that the battery gauge below overlaps it.
struct CarHero: View {
    let carName: String
    let plate: String
    let carColor: Color
    let image: Image?
    let heating: Bool
    let lightsOn: Bool
    /// The picture is one of the 500e renders, whose lamp and tyre positions are known.
    var lampsKnown = false
    /// Where any other picture meets the ground, worked out from its silhouette.
    var ground: GroundShape? = nil
    var updated: String? = nil
    /// The picture is on its way: the wheel turns where the car will be.
    var loading = false
    var height: CGFloat = 420
    var onSettings: (() -> Void)? = nil
    /// Other cars on the account (VIN, name); with more than one, the plate opens a switcher.
    var cars: [(vin: String, name: String)] = []
    var onSwitchCar: ((String) -> Void)? = nil

    @State private var breathe = false
    @State private var shimmer = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // A little narrower than the screen leaves air either side; the top moves down so the
            // wheels stay where the gauge overlaps them.
            let imageWidth = w * 620 / 390 * 1.08
            let imageHeight = imageWidth * 640 / 1200
            let imageTop = 88 * w / 390 + max(0, geo.size.height - 420) * 0.3
            ZStack(alignment: .topLeading) {
                spotlight
                if let image {
                    // The picture has no ground of its own: a lit floor and shadows put the car on it.
                    CarGround(knownWheels: lampsKnown, shape: ground)
                        .frame(width: imageWidth, height: imageHeight)
                        .position(x: w / 2, y: imageTop + imageHeight / 2)
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
                } else if loading {
                    TimelineView(.animation) { context in
                        PhIcon(name: "wheel", size: 30).foregroundStyle(V.textMuted)
                            .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360))
                    }
                    .position(x: w / 2, y: imageTop + imageHeight * 0.55)
                    .accessibilityLabel("Loading the car's picture")
                } else {
                    CarSilhouette().fill(V.raised)
                        .frame(width: imageWidth * 0.7, height: imageWidth * 0.7 * 0.5)
                        .position(x: w / 2, y: imageTop + imageHeight * 0.55)
                }
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
                    Text(carName).font(V.sora(48, .ultraLight)).tracking(-1.5).foregroundStyle(V.text)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .padding(.top, 2)

                }
                .padding(.horizontal, V.gutter)
                .padding(.top, 54)

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

/// Where a car picture meets the ground, on the 1200×640 picture canvas: the line through its
/// lowest points (in perspective, the far wheels sit higher) and the tyres along it.
struct GroundShape: Equatable {
    var hull: [CGPoint]
    var tyres: [CGRect]
}

/// The floor under the car, drawn on the same 1200×640 canvas as the car pictures: a faint pool of
/// light on the floor, a soft shadow along where the car meets it, and dark spots under the tyres.
struct CarGround: View {
    /// The 500e pictures, whose tyre positions were measured.
    let knownWheels: Bool
    /// For any other picture: worked out from its silhouette.
    var shape: GroundShape? = nil

    /// Where the tyres touch down in the 500e pictures: rear, front, far front (x, y, width).
    private static let tyres: [(CGFloat, CGFloat, CGFloat)] = [(348, 466, 84), (600, 486, 116), (830, 479, 82)]

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 1200
            func oval(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: (cx - w / 2) * s, y: (cy - h / 2) * s, width: w * s, height: h * s))
            }
            if let shape, !knownWheels, let first = shape.hull.first, let last = shape.hull.last {
                let cy = shape.hull.map(\.y).reduce(0, +) / CGFloat(shape.hull.count)
                ctx.drawLayer { floor in
                    floor.addFilter(.blur(radius: 34 * s))
                    floor.fill(oval((first.x + last.x) / 2, cy, 920, 120), with: .color(.white.opacity(0.08)))
                }
                // A band from the ground line up into the car, then a darker line right at it.
                ctx.drawLayer { band in
                    band.addFilter(.blur(radius: 9 * s))
                    var p = Path()
                    p.addLines(shape.hull.map { CGPoint(x: $0.x * s, y: ($0.y + 4) * s) } + shape.hull.reversed().map { CGPoint(x: $0.x * s, y: ($0.y - 26) * s) })
                    p.closeSubpath()
                    band.fill(p, with: .color(.black.opacity(0.6)))
                    for t in shape.tyres { band.fill(oval(t.midX, t.midY, t.width, t.height), with: .color(.black)) }
                }
                ctx.drawLayer { core in
                    core.addFilter(.blur(radius: 3 * s))
                    var p = Path()
                    p.addLines(shape.hull.map { CGPoint(x: $0.x * s, y: ($0.y + 1) * s) })
                    core.stroke(p, with: .color(.black.opacity(0.9)), lineWidth: 10 * s)
                }
                return
            }
            ctx.drawLayer { floor in
                floor.addFilter(.blur(radius: 30 * s))
                floor.fill(oval(600, 482, 860, 110), with: .color(.white.opacity(0.08)))
            }
            ctx.drawLayer { body in
                body.addFilter(.blur(radius: 14 * s))
                body.fill(oval(592, 474, knownWheels ? 600 : 560, 44), with: .color(.black.opacity(0.85)))
            }
            ctx.drawLayer { contact in
                contact.addFilter(.blur(radius: 5 * s))
                if knownWheels {
                    for (x, y, w) in Self.tyres { contact.fill(oval(x, y, w, 16), with: .color(.black)) }
                } else {
                    contact.fill(oval(599, 488, 520, 18), with: .color(.black.opacity(0.9)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
