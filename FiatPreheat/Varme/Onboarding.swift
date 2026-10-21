import SwiftUI

/// First run, in as few steps as it takes: welcome, the brand, sign in (the region is found by
/// trying), and into the app. Only an account without the remote package sees one more screen,
/// saying what it needs. The car's name and plate come from the brand and can be edited in Settings.
struct OnboardingFlow: View {
    @Environment(CarModel.self) private var model
    /// Opens on a later step in the demo, for screenshots: -onboardingStep 3
    @State private var step = Demo.isActive ? UserDefaults.standard.integer(forKey: "onboardingStep") : 0
    @State private var brand: Brand = .fiat
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
            default: packageStep
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // MARK: Welcome

    private var welcome: some View {
        // What it is, what it does, who it's for: the name and one line, the covered car small in
        // its own light, six things it does, two buttons, and the brands it works with.
        VStack(spacing: 0) {
            Text("Luft").eyebrowStyle().padding(.top, 28)
            Text("Your EV.\nIn your hands.").font(V.sora(34, .light)).tracking(-1).multilineTextAlignment(.center)
                .foregroundStyle(V.text).padding(.top, 14)
            Spacer(minLength: 8)
            Image("intro-covered").resizable().aspectRatio(contentMode: .fit)
                .frame(maxWidth: 250)
                // The photo's studio backdrop fades into the page, so no edge of it shows.
                .mask(RadialGradient(colors: [.black, .black, .clear], center: .center, startRadius: 0, endRadius: 125))
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            features
            Spacer(minLength: 20)
            VStack(spacing: 10) {
                VButton(title: "Get started") { step = 1 }
                // No car on hand (or App Review): the whole app on a made-up car.
                VButton(title: "Try with a sample car", prominent: false) { model.startSampleCar() }
            }
            VStack(spacing: 10) {
                Text("Works with").eyebrowStyle()
                VStack(spacing: 10) {
                    HStack(spacing: 16) { ForEach([Brand.fiat, .jeep, .alfaRomeo, .maserati]) { BrandMark(brand: $0, scale: 0.6) } }
                    HStack(spacing: 16) { ForEach([Brand.chrysler, .dodge, .ram]) { BrandMark(brand: $0, scale: 0.6) } }
                }
                .foregroundStyle(V.text)
                .opacity(0.6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Works with " + Brand.allCases.map(\.name).joined(separator: ", "))
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, V.gutter).padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(V.ground.ignoresSafeArea())
    }

    /// The six things the app does, an icon and two or three words each.
    private var features: some View {
        let items: [(icon: String, title: String)] = [
            ("battery", "Charge"), ("road", "Range"), ("wind", "Climate"),
            ("lock", "Lock & unlock"), ("map-pin", "Find on map"), ("sun", "Flash lights"),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 16) {
            ForEach(items, id: \.title) { item in
                VStack(spacing: 6) {
                    PhIcon(name: item.icon, size: 22).foregroundStyle(V.text)
                    Text(item.title).font(V.label).foregroundStyle(V.textMuted).lineLimit(1).minimumScaleFactor(0.85)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Brand

    private var brandStep: some View {
        StepPage(step: 1, eyebrow: "Step 1 of 2", title: "Which car do you drive?", body: "Luft signs in with the account you already use in your car brand's app.") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Brand.allCases) { b in
                    Button {
                        Haptics.select(); brand = b
                    } label: {
                        BrandMark(brand: b)
                            .foregroundStyle(V.text)
                            .frame(maxWidth: .infinity).frame(height: 84)
                            .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(brand == b ? V.raised : V.surface))
                            .overlay(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).strokeBorder(brand == b ? V.text : V.raised, lineWidth: brand == b ? 1.5 : 1))
                            .opacity(brand == b ? 1 : 0.75)
                    }
                    .buttonStyle(PressStyle())
                }
            }
        } footer: {
            VButton(title: "Continue") { step = 2 }
        }
    }

    // MARK: Sign in

    private var signInStep: some View {
        StepPage(step: 2, eyebrow: "Step 2 of 2", title: "Sign in to \(brand.name)", body: nil) {
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
            // Where the car was sold is worked out by trying the brand's regions, the phone's first.
            try await model.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password, pin: pin, brand: brand)
            Haptics.notify(.success)
            // Everything works: straight in. Something needs the remote package: say so first.
            if model.availability(of: .preconditionOn) == .needsSubscription { step = 3 } else { model.finishOnboarding() }
        } catch {
            Haptics.notify(.error)
            self.error = error.localizedDescription
        }
    }

    // MARK: Remote package

    private var packageStep: some View {
        let package = brand.remotePackageName
        return StepPage(step: 2, eyebrow: "One more thing", title: "One thing from \(brand.name)",
                        body: "Reading your battery is free. Doing things to the car from a distance is a \(brand.name) subscription called \(package). Luft can't work around it; nobody can.") {
            VStack(spacing: 0) {
                PackageRow(ok: true, title: "Battery, range, plugged in", detail: "Included with the car")
                PackageRow(ok: false, title: "Climate", detail: "Needs \(package)")
                PackageRow(ok: false, title: "Lock, unlock, lights, boot", detail: "Needs \(package)")
                PackageRow(ok: false, title: "Find the car, charge now", detail: "Needs \(package)", last: true)
            }
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.surface))
            .overlay(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).strokeBorder(V.raised, lineWidth: 1))
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(V.amber).frame(width: 8, height: 8).padding(.top, 6)
                Text("We checked your car: \(package) isn't active. It's bought in the \(brand.name) app, usually by the year. Luft itself is free.")
                    .font(V.body).foregroundStyle(V.text)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.activeFill(V.amber)))
            .overlay(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).strokeBorder(V.amber.opacity(0.35), lineWidth: 1))
        } footer: {
            VButton(title: "Continue with battery only") { model.finishOnboarding() }
            Text("Once you've bought \(package), pull down on the home screen and the buttons light up.")
                .font(V.label).foregroundStyle(V.textMuted).multilineTextAlignment(.center)
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
                ForEach(1...2, id: \.self) { i in Capsule().fill(i <= step ? V.text : V.raised).frame(height: 4) }
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
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
        }
        .focused($focused)
        .font(V.body).foregroundStyle(V.text)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .padding(.horizontal, 16).frame(height: 52)
        .background(Color.clear.contentShape(Rectangle()).onTapGesture { focused = true })
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
        .overlay(alignment: .bottom) { if !last { Divider().overlay(V.outline).padding(.leading, 18) } }
    }
}

/// A brand's mark in white: the logo where it's a simple shape, the name set in Sora where the
/// logo is a coloured badge (Alfa Romeo, Chrysler). Sized as on the brand step; `scale` shrinks it.
struct BrandMark: View {
    let brand: Brand
    var scale: CGFloat = 1

    var body: some View {
        Group {
            switch brand {
            case .fiat: logo("logo-fiat", 30)
            case .jeep: logo("logo-jeep", 18)
            case .maserati: logo("logo-maserati", 26)
            case .dodge: logo("logo-dodge", 13)
            case .ram: logo("logo-ram", 12)
            case .alfaRomeo, .chrysler:
                Text(brand.name.uppercased()).font(V.sora(13 * scale, .semibold)).tracking(2 * scale).lineLimit(1).fixedSize()
            }
        }
        .accessibilityLabel(brand.name)
    }

    private func logo(_ name: String, _ height: CGFloat) -> some View {
        Image(name).renderingMode(.template).resizable().aspectRatio(contentMode: .fit).frame(height: height * scale)
    }
}
