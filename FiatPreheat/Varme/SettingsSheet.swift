import SwiftUI

/// The car's name, plate and colour, units, the owner's name, and the account.
struct SettingsSheet: View {
    @Environment(CarModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            VSheetHeader(eyebrow: "Settings", title: model.carName) { dismiss() }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        field("Name", text: $model.carName)
                        Divider().overlay(V.raised)
                        field("Plate", text: $model.plate, caps: true)
                        Divider().overlay(V.raised)
                        field("Your name", text: Binding(get: { model.ownerName ?? "" }, set: { model.ownerName = $0.isEmpty ? nil : $0 }))
                    }
                    .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.raised))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Colour").font(V.label).foregroundStyle(V.textMuted)
                        CarColorPicker(hex: $model.carColorHex)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.raised))

                    VSwitchRow(title: "Miles instead of kilometres", isOn: $model.useMiles)

                    if model.vehicles.count > 1 {
                        VStack(spacing: 0) {
                            ForEach(model.vehicles) { vehicle in
                                Button {
                                    model.selectedVIN = vehicle.vin
                                    Task { await model.refreshStatus() }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(vehicle.nickname ?? vehicle.model ?? "Car").font(V.body).foregroundStyle(V.text)
                                            Text(vehicle.vin).font(V.label).foregroundStyle(V.textFaint)
                                        }
                                        Spacer()
                                        if vehicle.vin == model.selectedVIN { PhIcon(name: "check", size: 16).foregroundStyle(V.positive) }
                                    }
                                    .padding(.horizontal, 18).frame(minHeight: 56)
                                }
                                .buttonStyle(.plain)
                                if vehicle.vin != model.vehicles.last?.vin { Divider().overlay(V.raised) }
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
                        Text("Sign out").font(V.label).foregroundStyle(V.danger).frame(height: 44)
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
        .confirmationDialog("Sign out of \(model.account?.brand.name ?? "the account")?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await model.signOut() }; dismiss() }
        }
    }

    private func field(_ title: String, text: Binding<String>, caps: Bool = false) -> some View {
        HStack {
            Text(title).font(V.body).foregroundStyle(V.textMuted)
            Spacer()
            TextField(title, text: text)
                .font(V.body).foregroundStyle(V.text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(caps ? .characters : .words)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 18).frame(height: 56)
    }
}

/// Twelve swatches and a free colour. The choice tints the light around the car.
struct CarColorPicker: View {
    @Binding var hex: String

    static let swatches: [(String, String)] = [
        ("Black", "#18181b"), ("White", "#f4f4f5"), ("Grey", "#71717a"), ("Silver", "#d4d4d8"), ("Red", "#dc2626"), ("Orange", "#f97316"),
        ("Yellow", "#facc15"), ("Green", "#15803d"), ("Teal", "#0d9488"), ("Light blue", "#7dd3fc"), ("Blue", "#1d4ed8"), ("Rose", "#fda4af"),
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
            ForEach(Self.swatches, id: \.1) { name, value in
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
            ColorPicker("", selection: Binding(get: { Color(hexString: hex) }, set: { hex = $0.hexString }), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 44, height: 44)
                .accessibilityLabel("Any colour")
        }
    }
}
