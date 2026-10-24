import Foundation
import UserNotifications

/// Notifications about the car, worked out by comparing each status read with the last one.
/// There is no server, so they arrive when the app reads the car: when it's open, and on the
/// background refreshes iOS grants (roughly every half hour to few hours, at iOS's discretion).
@MainActor
enum CarAlerts {
    enum Kind: String, CaseIterable, Identifiable {
        case charged, low, unlocked, service, lowVoltage
        var id: String { rawValue }
        var title: String {
            switch self {
            case .charged: "Charging finished"
            case .low: "Battery low"
            case .unlocked: "Left unlocked"
            case .service: "Service due"
            case .lowVoltage: "12 V battery low"
            }
        }
    }

    static let lockCategoryID = "UNLOCKED"
    static let lockActionID = "LOCK_NOW"
    /// Below this the battery counts as low; it has to climb back over `lowReset` to warn again.
    static let lowLevel = 20.0
    static let lowReset = 25.0
    /// How long the car has to sit unlocked before the warning.
    static let unlockedGrace: TimeInterval = 10 * 60
    /// A service counts as due this close to it, by days or distance.
    static let serviceSoonDays = 30.0
    static let serviceSoonKm = 1000.0
    /// The 12 V battery is low under this. Resting, a healthy one reads 12.4–12.7 V; while the car
    /// charges it, about 14.5 V. A flat one is a common reason a car stops answering.
    static let lowVolts = 12.0
    static let voltsReset = 12.4

    static func serviceSoon(_ status: VehicleStatus) -> Bool {
        (status.serviceDays.map { $0 <= serviceSoonDays } ?? false) || (status.serviceKm.map { $0 <= serviceSoonKm } ?? false)
    }

    private static let defaults = UserDefaults.standard

    static func isOn(_ kind: Kind) -> Bool { defaults.bool(forKey: "alert.\(kind.rawValue)") }
    static func set(_ kind: Kind, _ on: Bool) { defaults.set(on, forKey: "alert.\(kind.rawValue)") }

    /// Posted when an alert is switched on, once notifications are allowed: proof they get through.
    static func confirm(_ kind: Kind) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        post(id: "confirm-\(kind.rawValue)", title: "\(kind.title) alerts are on", body: "This is how they'll arrive.")
    }
    static var anyOn: Bool { Kind.allCases.contains(where: isOn) }

    private enum State {
        static let wasCharging = "alertState.wasCharging"
        static let lowSent = "alertState.lowSent"
        static let unlockedSince = "alertState.unlockedSince"
        static let unlockedSent = "alertState.unlockedSent"
        static let serviceSent = "alertState.serviceSent"
        static let lowVoltageSent = "alertState.lowVoltageSent"
    }

    /// Call with every fresh status; posts whatever changed into an alert.
    static func evaluate(_ status: VehicleStatus, carName: String, rangeText: String, now: Date = Date()) {
        // Charging finished: was charging last time, isn't now, cable still in.
        if let charging = status.isCharging {
            if defaults.bool(forKey: State.wasCharging), !charging, isOn(.charged) {
                let level = status.stateOfCharge.map { "\(Int($0)) %" } ?? "Charged"
                post(id: "charged", title: "\(carName) is charged", body: "\(level) · \(rangeText)")
            }
            defaults.set(charging, forKey: State.wasCharging)
        }

        // Low: once per dip under the line.
        if let soc = status.stateOfCharge {
            if soc < lowLevel, !defaults.bool(forKey: State.lowSent) {
                if isOn(.low), status.isCharging != true {
                    post(id: "low", title: "Battery low", body: "\(carName) is at \(Int(soc)) % · \(rangeText).")
                }
                defaults.set(true, forKey: State.lowSent)
            } else if soc >= lowReset {
                defaults.set(false, forKey: State.lowSent)
            }
        }

        // Service: once as it comes due, again after the next service resets the counters.
        if serviceSoon(status) {
            if !defaults.bool(forKey: State.serviceSent) {
                if isOn(.service) {
                    let when = [status.serviceDays.map { "\(Int($0)) days" }, status.serviceKm.map { "\(Int($0)) km" }]
                        .compactMap { $0 }.joined(separator: " or ")
                    post(id: "service", title: "\(carName) is due a service", body: "In \(when).")
                }
                defaults.set(true, forKey: State.serviceSent)
            }
        } else if (status.serviceDays ?? 0) > serviceSoonDays * 2 {
            defaults.set(false, forKey: State.serviceSent)
        }

        // 12 V battery: once per dip.
        if let volts = status.auxBatteryVolts {
            if volts < lowVolts, !defaults.bool(forKey: State.lowVoltageSent) {
                if isOn(.lowVoltage) {
                    post(id: "lowVoltage", title: "\(carName): 12 V battery low",
                         body: String(format: "It reads %.1f V. Driving or charging the car tops it up.", volts))
                }
                defaults.set(true, forKey: State.lowVoltageSent)
            } else if volts >= voltsReset {
                defaults.set(false, forKey: State.lowVoltageSent)
            }
        }

        // Unlocked: only after it has stayed that way a while, so unlocking to get in doesn't warn.
        switch status.isLocked {
        case false?:
            let since = defaults.object(forKey: State.unlockedSince) as? Date ?? (status.reportedAt ?? now)
            defaults.set(since, forKey: State.unlockedSince)
            if now.timeIntervalSince(since) >= unlockedGrace, !defaults.bool(forKey: State.unlockedSent) {
                if isOn(.unlocked) {
                    post(id: "unlocked", title: "\(carName) is unlocked",
                         body: "Since \(since.formatted(date: .omitted, time: .shortened)).", category: lockCategoryID)
                }
                defaults.set(true, forKey: State.unlockedSent)
            }
        case true?:
            defaults.removeObject(forKey: State.unlockedSince)
            defaults.set(false, forKey: State.unlockedSent)
        case nil:
            break
        }
    }

    private static func post(id: String, title: String, body: String, category: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category { content.categoryIdentifier = category }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "alert-\(id)", content: content, trigger: nil))
    }
}
