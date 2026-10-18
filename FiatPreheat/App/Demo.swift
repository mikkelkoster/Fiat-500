import Foundation

/// Sample data: the app on a made-up 500e, with no account and no network. Reached from
/// "Try with a sample car" on the welcome screen (for anyone without a car, App Review included),
/// or for simulator runs and screenshots:
///
///   -preheatDemo                  turn it on
///   -demoScreen home|preheating|charging|find|schedule|settings|onboarding   which screen to open on
///   -demoSoc 24  -demoName "…"     battery level and car name, for checking layouts
///   -demoUnlocked YES              the car reports unlocked
///   -demoLoading YES               no numbers yet: the gauge shows it's loading
enum Demo {
    static var isActive: Bool { launchedAsDemo || UserDefaults.standard.bool(forKey: sampleKey) }
    /// The sample car was chosen on the welcome screen; it lasts until "Leave sample car".
    static var isSample: Bool { !launchedAsDemo && UserDefaults.standard.bool(forKey: sampleKey) }
    static let sampleKey = "sampleCar"
    private static let launchedAsDemo = ProcessInfo.processInfo.arguments.contains("-preheatDemo")
    static let screen = UserDefaults.standard.string(forKey: "demoScreen") ?? "home"

    static let account = UconnectAccount(email: "driver@example.com", password: "password", pin: "1234")
    static let vehicle = Vehicle(vin: "ZFAEFAC39MX000000", nickname: "500e", model: "New 500", services: RemoteCommand.allCases.map(\.rawValue))
    /// A second car, to show switching.
    static let vehicles = [vehicle, Vehicle(vin: "ZARNAAG00R0000000", nickname: nil, model: "Alfa Romeo Junior Elettrica", services: RemoteCommand.allCases.map(\.rawValue))]
    /// The car's own timers, in the shape Fiat sends them.
    static let carTimers: [String: Any] = ["schedules": [
        ["scheduleType": "CHARGE", "startTime": "00:30", "endTime": "06:00", "enableScheduleType": true, "repeatSchedule": true,
         "scheduledDays": ["monday": true, "tuesday": true, "wednesday": true, "thursday": true, "friday": true, "saturday": false, "sunday": false]],
        ["scheduleType": "CLIMATE", "startTime": "07:10", "enableScheduleType": false, "repeatSchedule": true,
         "scheduledDays": ["monday": true, "tuesday": true, "wednesday": true, "thursday": true, "friday": true, "saturday": false, "sunday": false]],
    ]]
    static var trips: [Trip] {
        let day: TimeInterval = 86_400
        return [
            Trip(id: 0, start: Date().addingTimeInterval(-3 * 3600), distanceKm: 14.2, minutes: 24, consumption: 13.1, score: 82),
            Trip(id: 1, start: Date().addingTimeInterval(-day - 5 * 3600), distanceKm: 38.6, minutes: 41, consumption: 15.8, score: 74),
            Trip(id: 2, start: Date().addingTimeInterval(-day - 9 * 3600), distanceKm: 6.1, minutes: 13, consumption: 17.4, score: 69),
            Trip(id: 3, start: Date().addingTimeInterval(-3 * day), distanceKm: 92.3, minutes: 68, consumption: 16.2, score: 88),
        ]
    }
    static var status: VehicleStatus {
        let charging = screen == "charging"
        let soc = UserDefaults.standard.string(forKey: "demoSoc").flatMap(Double.init)
        return VehicleStatus(stateOfCharge: soc ?? (charging ? 76 : 100), range: soc.map { $0 * 2.6 } ?? (charging ? 198 : 260), rangeUnit: "km", isCharging: charging, isPluggedIn: true, updatedAt: Date(), isLocked: !UserDefaults.standard.bool(forKey: "demoUnlocked"))
    }
    /// Kongens Nytorv, Copenhagen.
    static var location: CarLocation {
        CarLocation(latitude: 55.6805, longitude: 12.5853, updatedAt: Date().addingTimeInterval(-12 * 60))
    }
    static let schedules = [
        PreheatSchedule(readyHour: 7, readyMinute: 30, leadMinutes: 20, weekdays: [2, 3, 4, 5, 6]),
        PreheatSchedule(readyHour: 9, readyMinute: 0, leadMinutes: 20, weekdays: [1, 7], onlyWhenPluggedIn: false),
    ]
}
