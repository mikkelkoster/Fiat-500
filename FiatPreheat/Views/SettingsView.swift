import SwiftUI

struct SettingsView: View {
    @Environment(CarModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var pin = ""
    @State private var isSigningIn = false
    @State private var signInError: String?

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            SheetHeader(
                title: model.hasAccount ? "Settings" : "Connect your 500e",
                subtitle: model.hasAccount ? "" : "Use the same login and PIN as the Fiat app."
            ) { dismiss() }

            ScrollView {
                CardStack {
                    CardSection(title: "Fiat account", help: "Stored only in this iPhone's Keychain") {
                        VStack(spacing: 10) {
                            FormTextField(placeholder: "Email", text: $email)
                                .textContentType(.username)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            FormTextField(placeholder: "Password", text: $password, secure: true)
                                .textContentType(.password)
                            FormTextField(placeholder: "Uconnect PIN", text: $pin, secure: true)
                                .keyboardType(.numberPad)
                            if let signInError {
                                Text(signInError).font(Type.footnote).foregroundStyle(Ink.redText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            PrimaryButton(title: isSigningIn ? "Connecting…" : model.hasAccount ? "Reconnect" : "Connect") {
                                Task { await signIn() }
                            }
                            .disabled(isSigningIn || email.isEmpty || password.isEmpty || pin.count < 4)
                            .padding(.top, 6)
                        }
                    }

                    if model.hasAccount {
                        CardSection(title: "Car") {
                            VStack(spacing: 0) {
                                row("Plate") {
                                    TextField("Plate", text: $model.plate)
                                        .font(Type.bodyMedium).foregroundStyle(Ink.foreground)
                                        .multilineTextAlignment(.trailing)
                                        .textInputAutocapitalization(.characters)
                                }
                                .rowRule(true)
                                if model.vehicles.count > 1 {
                                    row("Vehicle") {
                                        Menu {
                                            Picker("Vehicle", selection: $model.selectedVIN) {
                                                ForEach(model.vehicles) { vehicle in
                                                    Text(vehicle.nickname ?? vehicle.model ?? vehicle.vin).tag(Optional(vehicle.vin))
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 8) {
                                                Text(selectedName).font(Type.bodyMedium).foregroundStyle(Ink.foreground)
                                                Image(systemName: "chevron.down").font(Icon.xs.weight(.medium)).foregroundStyle(Ink.muted)
                                            }
                                        }
                                    }
                                    .rowRule(true)
                                }
                                row("VIN") {
                                    Text(model.selectedVIN ?? "–").font(Type.monoFootnote).foregroundStyle(Ink.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .cardSurface()
                        }

                        CardSection(title: "Fully automatic schedules", help: "The one way iOS runs something exactly on time") {
                            Card {
                                VStack(alignment: .leading, spacing: 14) {
                                    step(1, "Open Shortcuts, then Automation, then New, then Time of Day.")
                                    step(2, "Pick the time and days, and choose Run Immediately.")
                                    step(3, "Add the action Preheat Car from this app.")
                                    Text("In-app schedules send a notification you can answer from the lock screen, and preheat on their own when iOS lets the app run.")
                                        .font(Type.footnote).foregroundStyle(Ink.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }

                        PrimaryButton(title: "Sign out", outline: true, tint: Ink.redText) {
                            Task { await model.signOut() }
                        }
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, 32)
            }
        }
        .torqueSheet([.large])
        .interactiveDismissDisabled(!model.hasAccount)
        .onChange(of: model.selectedVIN) {
            Task { await model.refreshStatus() }
        }
        .onAppear {
            if let account = model.account {
                email = account.email
                password = account.password
                pin = account.pin
            }
        }
    }

    private var selectedName: String {
        let vehicle = model.vehicles.first { $0.vin == model.selectedVIN }
        return vehicle?.nickname ?? vehicle?.model ?? "Choose"
    }

    private func row<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: 12) {
            Text(title).font(Type.emphasis).foregroundStyle(Ink.foreground)
            Spacer()
            value()
        }
        .padding(.horizontal, Space.cardPadding)
        .frame(minHeight: 56)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)").font(Type.monoFootnoteMedium).foregroundStyle(Ink.onPrimary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Ink.primary))
            Text(text).font(Type.body).foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func signIn() async {
        isSigningIn = true
        signInError = nil
        defer { isSigningIn = false }
        do {
            try await model.signIn(UconnectAccount(email: email.trimmingCharacters(in: .whitespaces), password: password, pin: pin))
            Haptics.notify(.success)
            dismiss()
        } catch {
            Haptics.notify(.error)
            signInError = error.localizedDescription
        }
    }
}
