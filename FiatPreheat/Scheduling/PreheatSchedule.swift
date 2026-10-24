import Foundation

/// "Have the car warm by 07:30 on weekdays." The app starts preheating `leadMinutes` before.
struct PreheatSchedule: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var readyHour = 7
    var readyMinute = 30
    var leadMinutes = 20
    /// Calendar weekday numbers: 1 = Sunday … 7 = Saturday.
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var isEnabled = true
    /// Skip a run when the cable isn't in, so the heat comes from the wall, not the battery.
    var onlyWhenPluggedIn = true

    /// Hour/minute at which the preheat command is sent.
    var start: (hour: Int, minute: Int) {
        let total = (readyHour * 60 + readyMinute - leadMinutes + 24 * 60) % (24 * 60)
        return (total / 60, total % 60)
    }

    /// Weekday on which the command is sent; differs from the ready day when it crosses midnight.
    func startWeekday(forReadyWeekday weekday: Int) -> Int {
        readyHour * 60 + readyMinute >= leadMinutes ? weekday : (weekday + 5) % 7 + 1
    }

    /// Next moments the preheat command should be sent, soonest first.
    func upcomingStarts(after date: Date, calendar: Calendar = .current) -> [Date] {
        guard isEnabled else { return [] }
        return weekdays.compactMap { weekday in
            calendar.nextDate(
                after: date,
                matching: DateComponents(hour: start.hour, minute: start.minute, weekday: startWeekday(forReadyWeekday: weekday)),
                matchingPolicy: .nextTime
            )
        }.sorted()
    }

    var readyTimeText: String {
        String(format: "%02d:%02d", readyHour, readyMinute)
    }

    var daysText: String { Weekdays.text(weekdays) }

    /// Monday-first display order.
    static let weekOrder = Weekdays.order
}
