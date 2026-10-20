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

                    VMenuRow(title: "Distance", options: [(false, "Kilometres"), (true, "Miles")], selection: $model.useMiles)
                        .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.raised))

                    if let problem = model.pictureProblem, !Demo.isActive {
                        // The car shows under a cover: say why, and let the owner try again.
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Car picture").font(V.body).foregroundStyle(V.text)
                                Text(problem).font(V.label).foregroundStyle(V.textMuted).textSelection(.enabled)
                            }
                            Spacer(minLength: 8)
                            Button { Task { await model.retryPicture() } } label: {
                                if model.pictureLoading { ProgressView().tint(V.text) }
                                else { Text("Try again").font(V.label).foregroundStyle(V.text) }
                            }
                            .buttonStyle(.plain)
                            .disabled(model.pictureLoading)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: V.radiusCard, style: .continuous).fill(V.raised))
                    }

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

