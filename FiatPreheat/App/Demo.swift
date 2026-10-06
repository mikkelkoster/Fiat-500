import Foundation

/// Sample data: the app on a made-up 500e, with no account and no network, for simulator runs and
/// screenshots. Same pattern as Torque's `-torqueDemo`.
///
///   -preheatDemo                  turn it on
///   -demoScreen home|preheating|schedule|settings   which screen to open on (default home)
enum Demo {
    static let isActive = ProcessInfo.processInfo.arguments.contains("-preheatDemo")
    static let screen = UserDefaults.standard.string(forKey: "demoScreen") ?? "home"

    static let account = UconnectAccount(email: "driver@example.com", password: "password", pin: "1234")
    static let vehicle = Vehicle(vin: "ZFAEFAC39MX000000", nickname: "500e", model: "Fiat 500e")
    static var status: VehicleStatus {
        VehicleStatus(stateOfCharge: 82, range: 214, rangeUnit: "km", isCharging: false, isPluggedIn: true, updatedAt: Date())
    }
    static let schedules = [
        PreheatSchedule(readyHour: 7, readyMinute: 30, leadMinutes: 20, weekdays: [2, 3, 4, 5, 6]),
        PreheatSchedule(readyHour: 9, readyMinute: 0, leadMinutes: 15, weekdays: [1, 7], isEnabled: false),
    ]
}
