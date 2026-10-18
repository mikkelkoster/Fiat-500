import SwiftUI

/// The car's name, plate and colour, units, the owner's name, and the account.
struct SettingsSheet: View {
    @Environment(CarModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false
    @State private var showTrips = false
    @State private var alerts: [CarAlerts.Kind: Bool] = Dictionary(uniqueKeysWithValues: CarAlerts.Kind.allCases.map { ($0, CarAlerts.isOn($0)) })

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            VSheetHeader(eyebrow: "Settings", title: model.carName) { dismiss() }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        field("Vehicle name", text: $model.carName)
                        Divider().overlay(V.outline).padding(.leading, 18)
                        field("Plate", text: $model.plate, caps: true)
                    }
                    .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.raised))

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Colour").font(V.label).foregroundStyle(V.textMuted)
                            Spacer()
                            if !model.paints.isEmpty {
                                Text(CarPaint.fiat500e(matching: model.carColorHex).name).font(V.label).foregroundStyle(V.text)
                            }
                        }
                        CarColorPicker(hex: $model.carColorHex, paints: model.paints)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.raised))

                    VMenuRow(title: "Distance", options: [(false, "Kilometres"), (true, "Miles")], selection: $model.useMiles)
                        .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.raised))

                    Button { showTrips = true } label: {
                        HStack {
                            Text("Trips").font(V.body).foregroundStyle(V.text)
                            Spacer()
                            PhIcon(name: "caret-right", size: 12).foregroundStyle(V.textMuted)
                        }
                        .padding(.horizontal, 18).frame(height: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.raised))

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Alerts").font(V.label).foregroundStyle(V.textMuted)
                            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 4)
                        ForEach(CarAlerts.Kind.allCases) { kind in
                            if kind != CarAlerts.Kind.allCases.first { Divider().overlay(V.outline).padding(.leading, 18) }
                            HStack {
                                Text(kind.title).font(V.body).foregroundStyle(V.text)
                                Spacer()
                                VSwitch(isOn: alertBinding(kind))
                            }
                            .padding(.leading, 18).padding(.trailing, 12).frame(height: 56)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.raised))

                    if model.vehicles.count > 1 {
                        VStack(spacing: 0) {
                            ForEach(model.vehicles) { vehicle in
                                Button {
                                    Task { await model.switchCar(to: vehicle.vin) }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(vehicle.vin == model.selectedVIN ? model.carName : (model.savedName(for: vehicle) ?? vehicle.nickname ?? vehicle.model ?? "Car"))
                                                .font(V.body).foregroundStyle(V.text)
                                            Text(vehicle.vin).font(V.label).foregroundStyle(V.textFaint)
                                        }
                                        Spacer()
                                        if vehicle.vin == model.selectedVIN { PhIcon(name: "check", size: 16).foregroundStyle(V.positive) }
                                    }
                                    .padding(.horizontal, 18).frame(minHeight: 56)
                                }
                                .buttonStyle(.plain)
                                if vehicle.vin != model.vehicles.last?.vin { Divider().overlay(V.outline).padding(.leading, 18) }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.raised))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Account").font(V.label).foregroundStyle(V.textMuted)
                        Text("\(model.account?.brand.name ?? "") · \(model.account?.email ?? "")").font(V.body).foregroundStyle(V.text)
                        if let vin = model.selectedVIN { Text(vin).font(V.label).foregroundStyle(V.textFaint).textSelection(.enabled) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.raised))

                    Button { confirmSignOut = true } label: {
                        Text(Demo.isSample ? "Leave sample car" : "Sign out").font(V.label).foregroundStyle(V.danger).frame(height: 44)
                    }
                    Text("Varme is an independent app, not affiliated with Stellantis or its brands.")
                        .font(V.label).foregroundStyle(V.textFaint).multilineTextAlignment(.center)
                }
                .padding(.horizontal, V.gutter)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
        }
        .background(V.surface.ignoresSafeArea())
        .varmeSheet()
        .sheet(isPresented: $showTrips) { TripsSheet() }
        .confirmationDialog(Demo.isSample ? "Leave the sample car?" : "Sign out of \(model.account?.brand.name ?? "the account")?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(Demo.isSample ? "Leave" : "Sign out", role: .destructive) { Task { await model.signOut() }; dismiss() }
        }
    }

    private func alertBinding(_ kind: CarAlerts.Kind) -> Binding<Bool> {
        Binding(get: { alerts[kind] ?? false }, set: { on in
            alerts[kind] = on
            CarAlerts.set(kind, on)
            ScheduleCoordinator.shared.reschedule(model.schedules)
            if on {
                Task {
                    await ScheduleCoordinator.shared.requestPermission()
                    await CarAlerts.confirm(kind)
                }
            }
        })
    }

    private func field(_ title: String, text: Binding<String>, caps: Bool = false) -> some View {
        VTextRow(title: title, text: text, caps: caps)
    }
}

/// Twelve swatches and a free colour. The choice tints the light around the car.
struct CarColorPicker: View {
    @Binding var hex: String
    /// The car's factory paints, when we have pictures of them; the picture follows the choice.
    var paints: [CarPaint] = []

    static let swatches: [(String, String)] = [
        ("Black", "#18181b"), ("White", "#f4f4f5"), ("Grey", "#71717a"), ("Silver", "#d4d4d8"), ("Red", "#dc2626"), ("Orange", "#f97316"),
        ("Yellow", "#facc15"), ("Green", "#15803d"), ("Teal", "#0d9488"), ("Light blue", "#7dd3fc"), ("Blue", "#1d4ed8"), ("Rose", "#fda4af"),
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
            ForEach(paints.isEmpty ? Self.swatches : paints.map { ($0.name, $0.hex) }, id: \.1) { name, value in
                Button {
                    Haptics.select()
                    hex = value
                } label: {
                    Circle().fill(Color(hexString: value))
                        .overlay(Circle().strokeBorder(V.outline, lineWidth: 1))
                        .frame(width: 32, height: 32)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().strokeBorder(hex.lowercased() == value ? V.text : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
            }
            if paints.isEmpty {
                ColorPicker("", selection: Binding(get: { Color(hexString: hex) }, set: { hex = $0.hexString }), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Any colour")
            }
        }
    }
}
