import Foundation

/// Sample data: the app on a made-up 500e, with no account and no network, for simulator runs and
/// screenshots.
///
///   -preheatDemo                  turn it on
///   -demoScreen home|preheating|charging|find|schedule|settings|onboarding   which screen to open on
enum Demo {
    static let isActive = ProcessInfo.processInfo.arguments.contains("-preheatDemo")
    static let screen = UserDefaults.standard.string(forKey: "demoScreen") ?? "home"

    static let account = UconnectAccount(email: "driver@example.com", password: "password", pin: "1234")
    static let vehicle = Vehicle(vin: "ZFAEFAC39MX000000", nickname: "500e", model: "New 500", services: RemoteCommand.allCases.map(\.rawValue))
    static var status: VehicleStatus {
        let charging = screen == "charging"
        return VehicleStatus(stateOfCharge: charging ? 76 : 100, range: charging ? 198 : 260, rangeUnit: "km", isCharging: charging, isPluggedIn: true, updatedAt: Date(), isLocked: true)
    }
    /// Kongens Nytorv, Copenhagen.
    static var location: CarLocation {
        CarLocation(latitude: 55.6805, longitude: 12.5853, updatedAt: Date().addingTimeInterval(-12 * 60))
    }
    static let schedules = [
        PreheatSchedule(readyHour: 7, readyMinute: 30, leadMinutes: 20, weekdays: [2, 3, 4, 5, 6]),
    ]
}
