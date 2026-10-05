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
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                    SecureField("Uconnect PIN", text: $pin)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Fiat account")
                } footer: {
                    Text("The same login and 4-digit PIN as the official Fiat app. Stored only in this iPhone's Keychain.")
                }

                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack {
                            Text(model.hasAccount ? "Update and Reconnect" : "Connect")
                            Spacer()
                            if isSigningIn { ProgressView() }
                        }
                    }
                    .disabled(isSigningIn || email.isEmpty || password.isEmpty || pin.count < 4)

                    if let signInError {
                        Text(signInError).font(.footnote).foregroundStyle(.red)
                    }
                }

                if model.hasAccount {
                    Section("Car") {
                        LabeledContent("Plate") {
                            TextField("Plate", text: $model.plate)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.characters)
                        }
                        if model.vehicles.count > 1 {
                            Picker("Vehicle", selection: $model.selectedVIN) {
                                ForEach(model.vehicles) { vehicle in
                                    Text(vehicle.nickname ?? vehicle.model ?? vehicle.vin).tag(Optional(vehicle.vin))
                                }
                            }
                        }
                        if let vin = model.selectedVIN {
                            LabeledContent("VIN", value: vin)
                                .font(.footnote.monospaced())
                        }
                    }

                    Section {
                        Label("Open the Shortcuts app › Automation › New › Time of Day", systemImage: "1.circle")
                        Label("Choose the time and days, and select Run Immediately", systemImage: "2.circle")
                        Label("Add the action \"Preheat Car\" from this app", systemImage: "3.circle")
                    } header: {
                        Text("Fully automatic schedules")
                    } footer: {
                        Text("In-app schedules send a notification you can act on from the lock screen and try to preheat in the background, but iOS decides when apps may run. A Shortcuts automation always runs on time.")
                    }

                    Section {
                        Button("Sign Out", role: .destructive) {
                            Task { await model.signOut() }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
        .interactiveDismissDisabled(!model.hasAccount)
    }

    private func signIn() async {
        isSigningIn = true
        signInError = nil
        defer { isSigningIn = false }
        do {
            try await model.signIn(UconnectAccount(email: email.trimmingCharacters(in: .whitespaces), password: password, pin: pin))
            dismiss()
        } catch {
            signInError = error.localizedDescription
        }
    }
}
