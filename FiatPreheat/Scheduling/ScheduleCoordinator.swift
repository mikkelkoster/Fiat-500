import BackgroundTasks
import Foundation
import UserNotifications

/// Turns schedules into something iOS will actually wake the app for.
///
/// iOS does not let apps run code at an exact time, so each schedule is covered two ways:
/// 1. A repeating local notification at the start time. Delivered in the foreground it
///    preheats straight away; otherwise its "Preheat now" action runs in the background
///    without opening the app.
/// 2. A background refresh request just before the start time. iOS decides when (or
///    whether) to grant it; when it does and a start is due, the app preheats on its own.
///
/// For a fully hands-off schedule, a Shortcuts personal automation that runs the
/// "Preheat" App Intent is the one mechanism iOS guarantees (see README).
final class ScheduleCoordinator: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = ScheduleCoordinator()

    static let backgroundTaskID = "dk.koster.varme.schedule"
    private static let categoryID = "PREHEAT"
    private static let startActionID = "PREHEAT_NOW"
    private static let requestPrefix = "preheat-"
    private static let firedKey = "lastScheduledPreheat"

    /// A background wake-up within this window of a start time counts as on time.
    private static let earlyWindow: TimeInterval = 10 * 60
    private static let lateWindow: TimeInterval = 5 * 60

    private let center = UNUserNotificationCenter.current()

    func configure() {
        center.delegate = self
        let start = UNNotificationAction(identifier: Self.startActionID, title: "Heat now", options: [])
        let lock = UNNotificationAction(identifier: CarAlerts.lockActionID, title: "Lock", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: [start], intentIdentifiers: []),
            UNNotificationCategory(identifier: CarAlerts.lockCategoryID, actions: [lock], intentIdentifiers: []),
        ])
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundTaskID, using: nil) { task in
            self.handleBackgroundRefresh(task as! BGAppRefreshTask)
        }
    }

    func requestPermission() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    // MARK: Scheduling

    func reschedule(_ schedules: [PreheatSchedule]) {
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.requestPrefix) }
            self.center.removePendingNotificationRequests(withIdentifiers: ours)

            for schedule in schedules where schedule.isEnabled {
                for weekday in schedule.weekdays {
                    let content = UNMutableNotificationContent()
                    content.title = "Warm by \(schedule.readyTimeText)"
                    content.body = "Long-press and choose Heat now. Skipped if it already started."
                    content.sound = .default
                    content.categoryIdentifier = Self.categoryID
                    content.userInfo = ["scheduleID": schedule.id.uuidString]

                    let trigger = UNCalendarNotificationTrigger(
                        dateMatching: DateComponents(
                            hour: schedule.start.hour,
                            minute: schedule.start.minute,
                            weekday: schedule.startWeekday(forReadyWeekday: weekday)
                        ),
                        repeats: true
                    )
                    let id = "\(Self.requestPrefix)\(schedule.id.uuidString)-\(weekday)"
                    self.center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                }
            }
        }
        submitBackgroundRefresh(for: schedules)
    }

    /// One request: just before the next schedule, or in half an hour when alerts need a look at
    /// the car, whichever is sooner.
    private func submitBackgroundRefresh(for schedules: [PreheatSchedule]) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskID)
        let nextSchedule = schedules.flatMap { $0.upcomingStarts(after: Date()) }.min()?.addingTimeInterval(-Self.earlyWindow)
        let alertsCheck = Self.alertsOn() ? Date().addingTimeInterval(30 * 60) : nil
        guard let when = [nextSchedule, alertsCheck].compactMap({ $0 }).min() else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskID)
        request.earliestBeginDate = when
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func alertsOn() -> Bool {
        CarAlerts.Kind.allCases.contains { UserDefaults.standard.bool(forKey: "alert.\($0.rawValue)") }
    }

    // MARK: Firing

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        let work = Task { @MainActor in
            let model = CarModel.shared
            if let due = Self.due(in: model.schedules, now: Date()), !Self.alreadyFired(due.start) {
                Self.markFired(due.start)
                await model.scheduledPreheat(scheduleID: due.schedule.id)
            } else if CarAlerts.anyOn {
                // Reading the status runs the alert checks.
                await model.refreshStatus()
            }
            self.submitBackgroundRefresh(for: model.schedules)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// The start time a wake-up at `now` should act on, if any.
    static func dueStart(in schedules: [PreheatSchedule], now: Date) -> Date? {
        due(in: schedules, now: now)?.start
    }

    /// The same, with the schedule it belongs to.
    static func due(in schedules: [PreheatSchedule], now: Date) -> (start: Date, schedule: PreheatSchedule)? {
        schedules
            .flatMap { s in s.upcomingStarts(after: now.addingTimeInterval(-lateWindow)).map { (start: $0, schedule: s) } }
            .filter { $0.start.timeIntervalSince(now) <= earlyWindow }
            .min { $0.start < $1.start }
    }

    private static func alreadyFired(_ start: Date) -> Bool {
        guard let last = UserDefaults.standard.object(forKey: firedKey) as? Date else { return false }
        return abs(last.timeIntervalSince(start)) < earlyWindow + lateWindow
    }

    private static func markFired(_ start: Date) {
        UserDefaults.standard.set(start, forKey: firedKey)
    }

    private func preheatFromNotification(_ notification: UNNotification) async {
        guard notification.request.identifier.hasPrefix(Self.requestPrefix) else { return }
        let start = Calendar.current.dateInterval(of: .minute, for: notification.date)?.start ?? notification.date
        guard !Self.alreadyFired(start) else { return }
        Self.markFired(start)
        let id = (notification.request.content.userInfo["scheduleID"] as? String).flatMap(UUID.init(uuidString:))
        await Self.startPreheat(scheduleID: id)
    }

    @MainActor
    private static func lock() async {
        await CarModel.shared.perform(.lock, waitForCar: false)
    }

    @MainActor
    private static func startPreheat(scheduleID: UUID?) async {
        await CarModel.shared.scheduledPreheat(scheduleID: scheduleID)
    }

    // MARK: UNUserNotificationCenterDelegate

    /// App is open when the schedule fires: just do it.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await preheatFromNotification(notification)
        return [.banner, .sound]
    }

    /// "Preheat now" action or a tap on the notification.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
        if response.actionIdentifier == CarAlerts.lockActionID {
            await Self.lock()
            return
        }
        await preheatFromNotification(response.notification)
    }
}
