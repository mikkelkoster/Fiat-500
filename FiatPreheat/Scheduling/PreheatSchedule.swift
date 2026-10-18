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

    var daysText: String {
        switch weekdays {
        case [2, 3, 4, 5, 6]: return "Mon – Fri"
        case [1, 7]: return "Weekends"
        case Set(1...7): return "Every day"
        default:
            // Runs of three or more days read as a range: "Mon – Sat", "Mon – Wed, Fri".
            let symbols = Calendar.current.shortWeekdaySymbols
            var runs: [[Int]] = []
            for day in Self.weekOrder where weekdays.contains(day) {
                if let last = runs.last?.last, Self.weekOrder.firstIndex(of: last)! + 1 == Self.weekOrder.firstIndex(of: day)! {
                    runs[runs.count - 1].append(day)
                } else {
                    runs.append([day])
                }
            }
            return runs.map { run in
                run.count >= 3 ? "\(symbols[run.first! - 1]) – \(symbols[run.last! - 1])" : run.map { symbols[$0 - 1] }.joined(separator: ", ")
            }.joined(separator: ", ")
        }
    }

    /// Monday-first display order.
    static let weekOrder = [2, 3, 4, 5, 6, 7, 1]
}
