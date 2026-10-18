import SwiftUI

/// First run: welcome, brand and region, sign in, the remote package, the car and its colour, done.
struct OnboardingFlow: View {
    @Environment(CarModel.self) private var model
    @State private var step = 0
    @State private var brand: Brand = .fiat
    @State private var region: Brand.Region = .europe
    @State private var email = ""
    @State private var password = ""
    @State private var pin = ""
    @State private var signingIn = false
    @State private var error: String?

    var body: some View {
        ZStack {
            V.ground.ignoresSafeArea()
            switch step {
            case 0: welcome
            case 1: brandStep
            case 2: signInStep
            case 3: packageStep
            case 4: carStep
            default: readyStep
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // MARK: Welcome

    private var welcome: some View {
        ZStack(alignment: .top) {
            RadialGradient(colors: [V.outline, V.surface, V.ground], center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 320).ignoresSafeArea()
            CarLineup().padding(.top, 150)
            LinearGradient(colors: [V.ground.opacity(0), V.ground], startPoint: .top, endPoint: .bottom).frame(height: 220).padding(.top, 330)
            VStack { Text("Varme").font(V.sora(56, .ultraLight)).tracking(-2).foregroundStyle(V.text).padding(.top, 76); Spacer() }
            VStack(spacing: 10) {
                Spacer()
                Text("A warm car\nwhen you leave.").font(V.sora(34, .light)).tracking(-1).multilineTextAlignment(.center).foregroundStyle(V.text)
                Text("Heat it, lock it, find it and charge it from your phone, by Siri and on a schedule.")
                    .font(V.body).foregroundStyle(V.textMuted).multilineTextAlignment(.center).padding(.bottom, 8)
                VButton(title: "Get started") { step = 1 }
                VStack(spacing: 10) {
                    Text("Works with").eyebrowStyle()
                    Text(Brand.allCases.map(\.name).joined(separator: "  ·  ")).font(V.label).foregroundStyle(V.textMuted).multilineTextAlignment(.center)
                    Text("Brand names belong to their owners. Varme is an independent app, not affiliated with Stellantis.")
                        .font(V.sora(11)).foregroundStyle(V.textFaint).multilineTextAlignment(.center)
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, V.gutter).padding(.bottom, 24)
        }
    }

    // MARK: Brand

    private var brandStep: some View {
        StepPage(step: 1, eyebrow: "Step 1 of 5", title: "Which car do you drive?", body: "Varme signs in with the account you already use in your car brand's app.") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Brand.allCases) { b in
                    Button {
                        Haptics.select(); brand = b
                        if !b.regions.contains(region) { region = b.regions[0] }
                    } label: {
                        Text(b.name.uppercased()).font(V.sora(14, .semibold)).tracking(2).foregroundStyle(V.text)
                            .frame(maxWidth: .infinity).frame(height: 72)
                            .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(brand == b ? V.raised : V.surface))
                            .overlay(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).strokeBorder(brand == b ? V.text : V.raised, lineWidth: brand == b ? 1.5 : 1))
                            .opacity(brand == b ? 1 : 0.75)
                    }
                    .buttonStyle(PressStyle())
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Where was it sold?").font(V.label).foregroundStyle(V.textMuted)
                HStack(spacing: 8) {
                    ForEach(brand.regions) { r in
                        Button { Haptics.select(); region = r } label: {
                            Text(r.name).font(V.label).foregroundStyle(region == r ? V.ground : V.text)
                                .padding(.horizontal, 14).frame(height: 40)
                                .background(Capsule().fill(region == r ? V.text : V.raised))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
            .padding(.top, 10)
        } footer: {
            VButton(title: "Continue") { step = 2 }
        }
    }

    // MARK: Sign in

    private var signInStep: some View {
        StepPage(step: 2, eyebrow: "Step 2 of 5", title: "Sign in to \(brand.name)", body: nil) {
            VStack(spacing: 10) {
                FormField(placeholder: "Email", text: $email).textContentType(.username).keyboardType(.emailAddress)
                FormField(placeholder: "Password", text: $password, secure: true).textContentType(.password)
                FormField(placeholder: "4-digit PIN", text: $pin, secure: true).keyboardType(.numberPad)
                if let error { Text(error).font(V.label).foregroundStyle(V.danger).frame(maxWidth: .infinity, alignment: .leading) }
            }
            VButton(title: signingIn ? "Signing in…" : "Sign in") { Task { await signIn() } }
                .disabled(signingIn || email.isEmpty || password.isEmpty || pin.count < 4)
                .padding(.top, 4)
            Text("Same login and PIN as the \(brand.name) app. They stay in this iPhone's keychain and go only to \(brand.name).")
                .font(V.label).foregroundStyle(V.textMuted).frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
        } footer: { EmptyView() }
    }

    private func signIn() async {
        signingIn = true; error = nil
        defer { signingIn = false }
        do {
            try await model.signIn(UconnectAccount(email: email.trimmingCharacters(in: .whitespaces), password: password, pin: pin, brand: brand, region: region))
            Haptics.notify(.success)
            step = 3
        } catch {
            Haptics.notify(.error)
            self.error = error.localizedDescription
        }
    }

    // MARK: Remote package

    private var packageStep: some View {
        let active = model.availability(of: .preconditionOn) == .available
        let package = brand.remotePackageName
        return StepPage(step: 3, eyebrow: "Step 3 of 5", title: active ? "You're all set with \(brand.name)" : "One thing from \(brand.name)",
                        body: active ? "Your account has \(package), so Varme can heat, lock and find the car." : "Reading your battery is free. Doing things to the car from a distance is a \(brand.name) subscription called \(package). Varme can't work around it; nobody can.") {
            VStack(spacing: 0) {
                PackageRow(ok: true, title: "Battery, range, plugged in", detail: "Included with the car")
                PackageRow(ok: active, title: "Preheat and cool", detail: active ? "Active" : "Needs \(package)")
                PackageRow(ok: active, title: "Lock, unlock, lights, boot", detail: active ? "Active" : "Needs \(package)")
                PackageRow(ok: active, title: "Find the car, charge now", detail: active ? "Active" : "Needs \(package)", last: true)
            }
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.surface))
            .overlay(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).strokeBorder(V.raised, lineWidth: 1))
            if !active {
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(V.amber).frame(width: 8, height: 8).padding(.top, 6)
                    Text("We checked your car: \(package) isn't active. It's bought in the \(brand.name) app, usually by the year. Varme itself is free.")
                        .font(V.body).foregroundStyle(V.text)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.activeFill(V.amber)))
                .overlay(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).strokeBorder(V.amber.opacity(0.35), lineWidth: 1))
            }
        } footer: {
            if active {
                VButton(title: "Continue") { step = 4 }
            } else {
                VButton(title: "Continue with battery only") { step = 4 }
                Text("Once you've bought \(package), pull down on the home screen and the buttons light up.")
                    .font(V.label).foregroundStyle(V.textMuted).multilineTextAlignment(.center)
            }
        }
    }

    // MARK: Car

    private var carStep: some View {
        @Bindable var model = model
        return StepPage(step: 4, eyebrow: "Step 4 of 5", title: "Your car", body: model.vehicles.count == 1 ? "We found one car on your account." : "We found \(model.vehicles.count) cars on your account.") {
            if model.vehicles.count > 1 {
                VStack(spacing: 0) {
                    ForEach(model.vehicles) { v in
                        Button { model.selectedVIN = v.vin } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(v.nickname ?? v.model ?? "Car").font(V.body).foregroundStyle(V.text)
                                    Text(v.vin).font(V.label).foregroundStyle(V.textFaint)
                                }
                                Spacer()
                                if v.vin == model.selectedVIN { PhIcon(name: "check", size: 16).foregroundStyle(V.positive) }
                            }
                            .padding(.horizontal, 18).frame(minHeight: 56)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.surface))
            } else if let v = model.vehicle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(brand.name).font(V.label).foregroundStyle(V.textMuted)
                    Text(v.model ?? v.nickname ?? "Car").font(V.title).foregroundStyle(V.text)
                    Text(v.vin).font(V.label).foregroundStyle(V.textFaint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.surface))
            }
            VStack(spacing: 0) {
                HStack { Text("Name").font(V.body).foregroundStyle(V.textMuted); Spacer(); TextField("Name", text: $model.carName).font(V.body).foregroundStyle(V.text).multilineTextAlignment(.trailing) }
                    .padding(.horizontal, 18).frame(height: 56)
                Divider().overlay(V.raised)
                HStack { Text("Plate").font(V.body).foregroundStyle(V.textMuted); Spacer(); TextField("Plate", text: $model.plate).font(V.body).foregroundStyle(V.text).multilineTextAlignment(.trailing).textInputAutocapitalization(.characters) }
                    .padding(.horizontal, 18).frame(height: 56)
            }
            .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.surface))
            VStack(alignment: .leading, spacing: 10) {
                Text("Colour").font(V.label).foregroundStyle(V.textMuted)
                CarColorPicker(hex: $model.carColorHex)
            }
        } footer: {
            VButton(title: "Continue") { step = 5 }
        }
    }

    // MARK: Ready

    private var readyStep: some View {
        StepPage(step: 5, eyebrow: "Step 5 of 5", title: "You're set", body: "Three things worth doing now. All optional.") {
            VStack(spacing: 0) {
                TipRow(icon: "clock", title: "Set a morning schedule", detail: "Warm by 07:30 on weekdays")
                TipRow(icon: "flame", title: "Allow Siri", detail: "\"Hey Siri, warm up my car with Varme\"")
                TipRow(icon: "car", title: "Add the widget", detail: "Battery and Preheat on your home screen", last: true)
            }
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.surface))
            .overlay(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).strokeBorder(V.raised, lineWidth: 1))
        } footer: {
            VButton(title: "Open Varme") { model.finishOnboarding() }
        }
    }
}

// MARK: - Pieces

private struct StepPage<Content: View, Footer: View>: View {
    let step: Int
    let eyebrow: String
    let title: String
    let body_: String?
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    init(step: Int, eyebrow: String, title: String, body: String?, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.step = step; self.eyebrow = eyebrow; self.title = title; self.body_ = body
        self.content = content(); self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { i in Capsule().fill(i <= step ? V.text : V.raised).frame(height: 4) }
            }
            .padding(.bottom, 22)
            Text(eyebrow).eyebrowStyle()
            Text(title).font(V.sora(32, .light)).tracking(-1).foregroundStyle(V.text).padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
            if let body_ { Text(body_).font(V.body).foregroundStyle(V.textMuted).padding(.top, 12).fixedSize(horizontal: false, vertical: true) }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) { content }.padding(.top, 20).padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 8) { footer }
        }
        .padding(.horizontal, V.gutter)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }
}

struct FormField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false

    var body: some View {
        Group {
            if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
        }
        .font(V.body).foregroundStyle(V.text)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .padding(.horizontal, 16).frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(V.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(V.raised, lineWidth: 1))
    }
}

private struct PackageRow: View {
    let ok: Bool
    let title: String
    let detail: String
    var last = false
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(V.raised).frame(width: 36, height: 36)
                .overlay(PhIcon(name: ok ? "check" : "lock", size: 18).foregroundStyle(ok ? V.positive : V.amber))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(V.body).foregroundStyle(V.text)
                Text(detail).font(V.label).foregroundStyle(V.textMuted)
            }
            Spacer()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { if !last { Divider().overlay(V.raised) } }
    }
}

private struct TipRow: View {
    let icon: String
    let title: String
    let detail: String
    var last = false
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(V.raised).frame(width: 36, height: 36).overlay(PhIcon(name: icon, size: 18).foregroundStyle(V.text))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(V.body).foregroundStyle(V.text)
                Text(detail).font(V.label).foregroundStyle(V.textMuted)
            }
            Spacer()
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { if !last { Divider().overlay(V.raised) } }
    }
}

/// Four side-view silhouettes, back to front, in zinc: our own artwork, so it suits every brand.
struct CarLineup: View {
    // Body path, its box, where it sits (at 390 wide), scale, fill, stroke, and the two wheel centres with their radius.
    private static let cars: [(String, CGSize, CGPoint, CGFloat, UInt32, UInt32, [CGPoint], CGFloat)] = [
        ("M4 82 L4 60 Q4 54 10 54 L52 54 L68 24 Q72 18 80 18 L116 18 Q124 18 126 26 L128 54 L172 54 Q178 54 178 60 L178 82 Z", CGSize(width: 182, height: 98), CGPoint(x: 205, y: 118), 1.02, 0x1f1f23, 0x3f3f46, [CGPoint(x: 40, y: 82), CGPoint(x: 144, y: 82)], 16),
        ("M4 80 L4 56 Q4 48 12 46 L34 42 L50 18 Q54 12 62 12 L124 12 Q132 12 136 18 L154 42 L174 46 Q182 48 182 56 L182 80 Z", CGSize(width: 186, height: 97), CGPoint(x: 20, y: 132), 1, 0x232327, 0x52525b, [CGPoint(x: 42, y: 80), CGPoint(x: 146, y: 80)], 17),
        ("M4 76 L4 58 Q4 50 14 48 L44 42 L72 18 Q78 14 86 14 L124 14 Q134 14 142 20 L172 40 L196 46 Q204 48 204 56 L204 76 Z", CGSize(width: 208, height: 92), CGPoint(x: 176, y: 150), 1, 0x27272a, 0x71717a, [CGPoint(x: 46, y: 76), CGPoint(x: 160, y: 76)], 16),
        ("M4 70 L4 50 Q4 40 14 38 L24 36 L38 14 Q44 6 56 6 L92 6 Q104 6 110 14 L124 36 L134 38 Q140 40 140 50 L140 70 Z", CGSize(width: 144, height: 85), CGPoint(x: 48, y: 158), 1, 0x2c2c30, 0xa1a1aa, [CGPoint(x: 34, y: 70), CGPoint(x: 110, y: 70)], 15),
    ]

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 390
            ctx.fill(Path(ellipseIn: CGRect(x: 25 * s, y: 228 * s, width: 340 * s, height: 16 * s)), with: .color(.black.opacity(0.5)))
            for (d, box, origin, scale, fill, stroke, wheels, r) in Self.cars {
                let k = s * scale
                let rect = CGRect(x: origin.x * s, y: origin.y * s, width: box.width * k, height: box.height * k)
                let path = SVGPath.path(d, in: rect, viewBox: box)
                ctx.fill(path, with: .color(Color(hex: fill)))
                ctx.stroke(path, with: .color(Color(hex: stroke)), lineWidth: 1.5)
                for w in wheels {
                    let c = CGPoint(x: rect.minX + w.x * k, y: rect.minY + w.y * k)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * k, y: c.y - r * k, width: 2 * r * k, height: 2 * r * k)), with: .color(Color(hex: 0x0c0c0e)))
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 7 * k, y: c.y - 7 * k, width: 14 * k, height: 14 * k)), with: .color(Color(hex: stroke)))
                }
            }
        }
        .frame(height: 300)
        .accessibilityLabel("A city car, a saloon, an SUV and a pickup, side by side")
    }
}
