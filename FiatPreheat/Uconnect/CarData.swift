import Foundation

// Fiat doesn't document these replies, so both readers look for the fields they need wherever
// they sit, and the timers are written back in exactly the shape they came in, with only the
// fields the app understands changed.

// MARK: - The car's own timers

/// One of the timers stored in the car (charging or climate). They run even with the phone off.
struct CarTimer: Identifiable, Equatable {
    enum Kind: Equatable { case charge, climate, other(String) }

    /// Stands in while no timer is being edited.
    static let placeholder = CarTimer(id: -1, kind: .charge, startHour: 0, startMinute: 0, endHour: nil, endMinute: nil, isOn: false, weekdays: [])

    let id: Int
    var kind: Kind
    var startHour: Int
    var startMinute: Int
    var endHour: Int?
    var endMinute: Int?
    var isOn: Bool
    /// Calendar weekday numbers: 1 = Sunday … 7 = Saturday.
    var weekdays: Set<Int>

    var title: String {
        switch kind {
        case .charge: "Charging"
        case .climate: "Climate"
        case .other(let name): name.capitalized
        }
    }

    var timeText: String {
        let start = String(format: "%02d:%02d", startHour, startMinute)
        guard let endHour, let endMinute else { return start }
        return start + " – " + String(format: "%02d:%02d", endHour, endMinute)
    }

    var daysText: String { Weekdays.text(weekdays) }
}

/// Calendar weekday numbers (1 = Sunday … 7 = Saturday) as short text.
enum Weekdays {
    /// Monday-first display order.
    static let order = [2, 3, 4, 5, 6, 7, 1]

    static func text(_ weekdays: Set<Int>) -> String {
        switch weekdays {
        case [2, 3, 4, 5, 6]: return "Mon – Fri"
        case [1, 7]: return "Weekends"
        case Set(1...7): return "Every day"
        default:
            // Runs of three or more days read as a range: "Mon – Sat", "Mon – Wed, Fri".
            let symbols = Calendar.current.shortWeekdaySymbols
            var runs: [[Int]] = []
            for day in order where weekdays.contains(day) {
                if let last = runs.last?.last, order.firstIndex(of: last)! + 1 == order.firstIndex(of: day)! {
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
}

/// The car's timers plus the reply they came from, so a change can be written back faithfully.
struct CarTimers {
    private(set) var timers: [CarTimer]
    private let reply: [String: Any]
    private let listKey: String?
    private let rawList: [[String: Any]]

    static let dayKeys: [(key: String, weekday: Int)] = [
        ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4), ("thursday", 5), ("friday", 6), ("saturday", 7),
    ]

    init?(reply: [String: Any]) {
        // Usually `schedules` at the top; otherwise the first list of things that have a start time.
        let found: (String?, [[String: Any]])?
        if let list = reply["schedules"] as? [[String: Any]] {
            found = ("schedules", list)
        } else {
            found = reply.lazy.compactMap { key, value -> (String?, [[String: Any]])? in
                guard let list = value as? [[String: Any]], list.contains(where: { $0["startTime"] != nil }) else { return nil }
                return (key, list)
            }.first
        }
        guard let (key, list) = found, !list.isEmpty else { return nil }
        self.reply = reply
        listKey = key
        rawList = list
        timers = list.enumerated().compactMap { index, item in Self.timer(index, item) }
        guard !timers.isEmpty else { return nil }
    }

    private static func timer(_ index: Int, _ item: [String: Any]) -> CarTimer? {
        guard let start = clock(item["startTime"]) else { return nil }
        let end = clock(item["endTime"])
        let type = (item["scheduleType"] as? String ?? "").uppercased()
        let kind: CarTimer.Kind = type.contains("CHARGE") ? .charge
            : (type.contains("CLIMATE") || type.contains("PRECOND") || type.contains("CABIN")) ? .climate
            : .other(type.isEmpty ? "Timer" : type.lowercased())
        let days = item["scheduledDays"] as? [String: Any] ?? [:]
        let weekdays = Set(dayKeys.filter { (days[$0.key] as? Bool) == true }.map(\.weekday))
        let on = (item["enableScheduleType"] as? Bool) ?? (item["enabled"] as? Bool) ?? (item["active"] as? Bool) ?? false
        return CarTimer(id: index, kind: kind, startHour: start.0, startMinute: start.1,
                        endHour: end?.0, endMinute: end?.1, isOn: on, weekdays: weekdays)
    }

    /// "07:30" or "07:30:00".
    static func clock(_ value: Any?) -> (Int, Int)? {
        guard let text = value as? String else { return nil }
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }

    mutating func update(_ timer: CarTimer) {
        guard let index = timers.firstIndex(where: { $0.id == timer.id }) else { return }
        timers[index] = timer
    }

    /// The reply with the changed timers written into it, ready to send back.
    var body: [String: Any] {
        var list = rawList
        for timer in timers {
            var item = list[timer.id]
            item["startTime"] = Self.format(timer.startHour, timer.startMinute, like: item["startTime"])
            if let h = timer.endHour, let m = timer.endMinute { item["endTime"] = Self.format(h, m, like: item["endTime"]) }
            if item["enableScheduleType"] != nil || (item["enabled"] == nil && item["active"] == nil) {
                item["enableScheduleType"] = timer.isOn
            } else if item["enabled"] != nil {
                item["enabled"] = timer.isOn
            } else {
                item["active"] = timer.isOn
            }
            var days = item["scheduledDays"] as? [String: Any] ?? [:]
            for (key, weekday) in Self.dayKeys { days[key] = timer.weekdays.contains(weekday) }
            item["scheduledDays"] = days
            list[timer.id] = item
        }
        var out = reply
        out[listKey ?? "schedules"] = list
        return out
    }

    private static func format(_ hour: Int, _ minute: Int, like original: Any?) -> String {
        let base = String(format: "%02d:%02d", hour, minute)
        return (original as? String)?.split(separator: ":").count == 3 ? base + ":00" : base
    }
}

// MARK: - Trips

/// One drive from the eco-coaching list. Every field is optional: the reply differs by car.
struct Trip: Identifiable, Equatable {
    let id: Int
    var start: Date?
    var distanceKm: Double?
    var minutes: Double?
    /// kWh per 100 km, when the car reports energy.
    var consumption: Double?
    /// Fiat's eco score, 0–100.
    var score: Double?

    /// Reads whichever list in the reply has distances in it.
    static func list(from reply: [String: Any]) -> [Trip] {
        // A single trip (the last-trip reply) counts as a list of one.
        guard let items = firstList(in: reply) ?? singleTrip(in: reply).map({ [$0] }) else { return [] }
        return items.enumerated().map { index, item in trip(index, flatten(item)) }
            .filter { $0.distanceKm != nil || $0.start != nil }
            .sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }
    }

    private static func isTripKey(_ key: String) -> Bool {
        key.contains("distance") || key.contains("mileage") || key.contains("odometer")
    }

    private static func singleTrip(in value: Any) -> [String: Any]? {
        guard let d = value as? [String: Any] else { return nil }
        if flatten(d).keys.contains(where: isTripKey) { return d }
        return d.values.lazy.compactMap { singleTrip(in: $0) }.first
    }

    private static func firstList(in value: Any) -> [[String: Any]]? {
        if let list = value as? [[String: Any]],
           list.contains(where: { flatten($0).keys.contains(where: isTripKey) }) {
            return list
        }
        if let d = value as? [String: Any] { return d.values.lazy.compactMap { firstList(in: $0) }.first }
        if let a = value as? [Any] { return a.lazy.compactMap { firstList(in: $0) }.first }
        return nil
    }

    /// Every level of nesting folded in, keys lower-cased:
    /// {"summary": {"distance": {"value": 12}}} → "summary.distance.value".
    private static func flatten(_ item: [String: Any], prefix: String = "") -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in item {
            let k = prefix + key.lowercased()
            if let inner = value as? [String: Any] {
                out.merge(flatten(inner, prefix: k + "."), uniquingKeysWith: { a, _ in a })
            } else {
                out[k] = value
            }
        }
        return out
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
    }

    private static func date(_ value: Any?) -> Date? {
        if let n = number(value) { return Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n) }
        guard let s = value as? String else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }

    private static func trip(_ index: Int, _ f: [String: Any]) -> Trip {
        func first(_ match: (String) -> Bool) -> (key: String, value: Any)? {
            f.filter { match($0.key) }.sorted { $0.key.count < $1.key.count }.first.map { ($0.key, $0.value) }
        }
        var trip = Trip(id: index)
        if let s = first({ ($0.contains("start") && ($0.contains("time") || $0.contains("date")) && !$0.contains("odometer")) || $0 == "timestamp" }) {
            trip.start = date(s.value)
        }
        func km(_ key: String, _ v: Double) -> Double {
            let unit = (f[key.replacingOccurrences(of: ".value", with: ".unit")] as? String ?? f["distanceunit"] as? String ?? "km").lowercased()
            return unit.hasPrefix("mi") ? v * 1.609 : unit == "m" ? v / 1000 : v
        }
        let distances = f.filter { ($0.key.contains("distance") || $0.key.contains("mileage")) && !$0.key.contains("unit") }
            .compactMap { k, v in number(v).map { (k, $0) } }.sorted { $0.0.count < $1.0.count }
        if let (k, v) = distances.first {
            trip.distanceKm = km(k, v)
        } else if let s = first({ $0.contains("odometer") && $0.contains("start") && !$0.contains("unit") }),
                  let e = first({ $0.contains("odometer") && $0.contains("end") && !$0.contains("unit") }),
                  let a = number(s.value), let b = number(e.value), b >= a {
            // Some replies give only the odometer at each end.
            trip.distanceKm = km(e.key, b - a)
        }
        if let d = first({ $0.contains("duration") && !$0.contains("unit") }), let v = number(d.value) {
            // Seconds unless it's clearly minutes.
            trip.minutes = v > 600 ? v / 60 : v
        } else if let start = trip.start,
                  let e = first({ $0.contains("end") && ($0.contains("time") || $0.contains("date")) }),
                  let end = date(e.value), end > start {
            trip.minutes = end.timeIntervalSince(start) / 60
        }
        if let c = first({ ($0.contains("consumption") || $0.contains("efficiency")) && !$0.contains("unit") }) {
            trip.consumption = number(c.value)
        }
        if let s = first({ $0.contains("score") }) { trip.score = number(s.value) }
        return trip
    }
}
