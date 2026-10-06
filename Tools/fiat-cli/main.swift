import Foundation

// fiat-cli: sign in to Fiat (Uconnect) and talk to the car with the same code the app uses.
//
//   swift run fiat-cli vehicles        sign in and list the cars on the account
//   swift run fiat-cli status          battery, range, plug
//   swift run fiat-cli preheat         start climate and wait for the car to confirm
//   swift run fiat-cli stop            stop climate
//
// Credentials come from FIAT_EMAIL, FIAT_PASSWORD and FIAT_PIN, or are asked for (hidden).
// FIAT_VIN picks a car when the account has more than one. Nothing is stored.

func ask(_ prompt: String, secret: Bool = false) -> String {
    if secret {
        return String(cString: getpass(prompt))
    }
    print(prompt, terminator: "")
    return readLine() ?? ""
}

func env(_ key: String) -> String? {
    ProcessInfo.processInfo.environment[key].flatMap { $0.isEmpty ? nil : $0 }
}

let command = CommandLine.arguments.dropFirst().first ?? "vehicles"
guard ["vehicles", "status", "preheat", "stop"].contains(command) else {
    print("Usage: fiat-cli vehicles | status | preheat | stop")
    exit(2)
}

let account = UconnectAccount(
    email: env("FIAT_EMAIL") ?? ask("Fiat email: "),
    password: env("FIAT_PASSWORD") ?? ask("Password: ", secret: true),
    pin: env("FIAT_PIN") ?? ask("Uconnect PIN: ", secret: true)
)

let client = UconnectClient()
await client.setAccount(account)

func step(_ text: String) { print("▸ \(text)") }

do {
    step("Signing in and listing cars")
    let vehicles = try await client.vehicles()
    print("✓ Signed in. \(vehicles.count) car(s):")
    for v in vehicles {
        print("   \(v.vin)  \(v.model ?? "")  \(v.nickname.map { "“\($0)”" } ?? "")")
    }
    guard let vin = env("FIAT_VIN") ?? vehicles.first?.vin else {
        print("✗ No cars on this account.")
        exit(1)
    }
    if command == "vehicles" { exit(0) }

    step("Reading status for \(vin)")
    let status = try await client.status(vin: vin)
    print("✓ Battery \(status.stateOfCharge.map { "\(Int($0))%" } ?? "?"), range \(status.range.map { "\(Int($0)) \(status.rangeUnit ?? "")" } ?? "?"), plugged in: \(status.isPluggedIn.map { $0 ? "yes" : "no" } ?? "?"), charging: \(status.isCharging.map { $0 ? "yes" : "no" } ?? "?")")
    if command == "status" { exit(0) }

    let remote: RemoteCommand = command == "preheat" ? .preconditionOn : .preconditionOff
    step("Checking PIN and sending \(remote.rawValue)")
    let id = try await client.send(remote, vin: vin)
    print("✓ Queued (correlation id \(id)). Waiting up to 90 s for the car…")
    switch await client.waitForResult(vin: vin, correlationId: id) {
    case .succeeded: print("✓ The car confirmed. \(command == "preheat" ? "Climate is on." : "Climate is off.")")
    case .failed: print("✗ The car rejected the command.")
    case .unknown: print("… No answer from the car within 90 s. It may still act; check the Fiat app.")
    }
} catch {
    print("✗ \(error.localizedDescription)")
    exit(1)
}
