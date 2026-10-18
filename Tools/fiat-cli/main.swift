import Foundation

// fiat-cli: sign in to Fiat (Uconnect) and talk to the car with the same code the app uses.
//
//   swift run fiat-cli vehicles        sign in and list the cars on the account
//   swift run fiat-cli status          battery, range, plug
//   swift run fiat-cli preheat         start climate and wait for the car to confirm
//   swift run fiat-cli stop            stop climate
//   swift run fiat-cli where           last known position (no command sent)
//   swift run fiat-cli schedules       the car's own charge/departure schedules, raw (read-only)
//   swift run fiat-cli lock | unlock | lights | trunk | chargenow | refresh | locate
//                                      the My Remote commands; locate also prints the new position
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

let remoteCommands: [String: RemoteCommand] = [
    "preheat": .preconditionOn, "stop": .preconditionOff,
    "lock": .lock, "unlock": .unlock, "lights": .lights, "trunk": .trunkUnlock,
    "chargenow": .chargeNow, "refresh": .deepRefresh, "locate": .locate,
]
let command = CommandLine.arguments.dropFirst().first ?? "vehicles"
guard ["vehicles", "status", "where", "schedules", "trips", "image"].contains(command) || remoteCommands[command] != nil else {
    print("Usage: fiat-cli vehicles | status | where | schedules | trips | image | preheat | stop | lock | unlock | lights | trunk | chargenow | refresh | locate")
    exit(2)
}

func printLocation(_ client: UconnectClient, vin: String) async throws {
    let location = try await client.location(vin: vin)
    let when = location.updatedAt.map { " (\($0.formatted(date: .abbreviated, time: .shortened)))" } ?? ""
    print("✓ \(location.latitude), \(location.longitude)\(location.isApproximate ? " approx." : "")\(when)")
    print("   https://maps.apple.com/?q=\(location.latitude),\(location.longitude)")
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
        print("     services: \(v.services.isEmpty ? "none listed" : v.services.sorted().joined(separator: ", "))")
        if let image = v.imageURL { print("     picture: \(image)") }
        if !v.disabledServices.isEmpty {
            print("     capable but not enabled: \(v.disabledServices.sorted().joined(separator: ", "))")
        }
    }
    guard let vin = env("FIAT_VIN") ?? vehicles.first?.vin else {
        print("✗ No cars on this account.")
        exit(1)
    }
    if command == "vehicles" { exit(0) }

    if command == "schedules" {
        step("Reading the car's own schedules")
        let json = try await client.carSchedules(vin: vin)
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        if let timers = CarTimers(reply: json) {
            for t in timers.timers { print("✓ \(t.title) \(t.timeText) \(t.daysText) \(t.isOn ? "on" : "off")") }
        } else {
            print("! The app can't read timers from this reply yet.")
        }
        exit(0)
    }

    if command == "trips" {
        step("Reading trips")
        let json = try await client.trips(vin: vin)
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        let trips = Trip.list(from: json)
        print("✓ \(trips.count) trips understood")
        for t in trips.prefix(5) { print("  \(t.start.map { "\($0)" } ?? "?")  \(t.distanceKm.map { "\($0) km" } ?? "")  \(t.consumption.map { "\($0)" } ?? "")") }
        exit(0)
    }

    if command == "image" {
        step("Asking for the car's picture")
        print(try await client.imageURL(vin: vin).map { "✓ \($0)" } ?? "! No picture address in the reply")
        exit(0)
    }

    if command == "where" {
        step("Reading last known position")
        try await printLocation(client, vin: vin)
        exit(0)
    }

    step("Reading status for \(vin)")
    let status = try await client.status(vin: vin)
    let locked = status.isLocked.map { $0 ? "locked" : "unlocked" } ?? "?"
    print("✓ Battery \(status.stateOfCharge.map { "\(Int($0))%" } ?? "?"), range \(status.range.map { "\(Int($0)) \(status.rangeUnit ?? "")" } ?? "?"), plugged in: \(status.isPluggedIn.map { $0 ? "yes" : "no" } ?? "?"), charging: \(status.isCharging.map { $0 ? "yes" : "no" } ?? "?"), doors: \(locked)")
    if command == "status" { exit(0) }

    let remote = remoteCommands[command]!
    step("Checking PIN and sending \(remote.rawValue)")
    let id = try await client.send(remote, vin: vin)
    print("✓ Queued (correlation id \(id)). Waiting up to 90 s for the car…")
    switch await client.waitForResult(vin: vin, correlationId: id) {
    case .succeeded:
        print("✓ The car confirmed.")
        if remote == .locate { try await printLocation(client, vin: vin) }
    case .failed: print("✗ The car rejected the command.")
    case .unknown: print("… No answer from the car within 90 s. It may still act; check the Fiat app.")
    }
} catch {
    print("✗ \(error.localizedDescription)")
    exit(1)
}
