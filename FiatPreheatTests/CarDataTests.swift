import XCTest
@testable import FiatPreheat

final class CarTimersTests: XCTestCase {
    private let reply: [String: Any] = ["vin": "X", "schedules": [
        ["scheduleType": "CHARGE", "startTime": "00:30:00", "endTime": "06:00:00", "enableScheduleType": true,
         "repeatSchedule": true, "cabinPriority": false,
         "scheduledDays": ["monday": true, "tuesday": true, "wednesday": true, "thursday": true, "friday": true, "saturday": false, "sunday": false]],
        ["scheduleType": "CLIMATE", "startTime": "07:10", "enableScheduleType": false,
         "scheduledDays": ["saturday": true, "sunday": true]],
    ]]

    func testReadsTimers() throws {
        let timers = try XCTUnwrap(CarTimers(reply: reply)).timers
        XCTAssertEqual(timers.count, 2)
        XCTAssertEqual(timers[0].kind, .charge)
        XCTAssertEqual(timers[0].timeText, "00:30 – 06:00")
        XCTAssertEqual(timers[0].weekdays, [2, 3, 4, 5, 6])
        XCTAssertTrue(timers[0].isOn)
        XCTAssertEqual(timers[1].kind, .climate)
        XCTAssertEqual(timers[1].daysText, "Weekends")
        XCTAssertFalse(timers[1].isOn)
    }

    func testWritesBackOnlyWhatChanged() throws {
        var timers = try XCTUnwrap(CarTimers(reply: reply))
        var first = timers.timers[0]
        first.startHour = 1; first.startMinute = 15; first.isOn = false; first.weekdays = [2]
        timers.update(first)
        let list = try XCTUnwrap(timers.body["schedules"] as? [[String: Any]])
        XCTAssertEqual(list[0]["startTime"] as? String, "01:15:00", "keeps the car's seconds format")
        XCTAssertEqual(list[0]["endTime"] as? String, "06:00:00")
        XCTAssertEqual(list[0]["enableScheduleType"] as? Bool, false)
        XCTAssertEqual(list[0]["cabinPriority"] as? Bool, false, "fields the app doesn't know survive")
        XCTAssertEqual((list[0]["scheduledDays"] as? [String: Bool])?["monday"], true)
        XCTAssertEqual((list[0]["scheduledDays"] as? [String: Bool])?["tuesday"], false)
        XCTAssertEqual(list[1]["startTime"] as? String, "07:10", "untouched timer keeps its format")
        XCTAssertEqual(timers.body["vin"] as? String, "X")
    }

    func testNoTimersIsNil() {
        XCTAssertNil(CarTimers(reply: ["schedules": []]))
        XCTAssertNil(CarTimers(reply: ["something": "else"]))
    }
}

final class TripTests: XCTestCase {
    func testReadsNestedTripList() {
        let reply: [String: Any] = ["data": ["trips": [
            ["startTime": 1_760_000_000_000, "distance": ["value": 12.5, "unit": "km"], "duration": 1500, "consumption": 14.2, "ecoScore": 81],
            ["startTime": 1_760_100_000_000, "distance": ["value": 3, "unit": "mi"], "duration": 10],
        ]]]
        let trips = Trip.list(from: reply)
        XCTAssertEqual(trips.count, 2)
        // Newest first.
        XCTAssertEqual(trips[0].distanceKm ?? 0, 4.827, accuracy: 0.01)
        XCTAssertEqual(trips[0].minutes, 10)
        XCTAssertEqual(trips[1].distanceKm, 12.5)
        XCTAssertEqual(trips[1].minutes, 25, "seconds read as minutes")
        XCTAssertEqual(trips[1].consumption, 14.2)
        XCTAssertEqual(trips[1].score, 81)
        XCTAssertEqual(trips[1].start, Date(timeIntervalSince1970: 1_760_000_000))
    }

    func testSingleLastTrip() {
        let trips = Trip.list(from: ["trip": ["startTime": 1_760_000_000_000, "distance": 7.5, "duration": 900]])
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips[0].distanceKm, 7.5)
        XCTAssertEqual(trips[0].minutes, 15)
    }

    func testNothingUnderstood() {
        XCTAssertTrue(Trip.list(from: ["trips": [["foo": 1]]]).isEmpty)
    }
}

@MainActor
final class CarAlertsTests: XCTestCase {
    override func setUp() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("alert") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func status(soc: Double, charging: Bool, locked: Bool?) -> VehicleStatus {
        VehicleStatus(stateOfCharge: soc, range: soc * 2.6, rangeUnit: "km", isCharging: charging, isPluggedIn: true, updatedAt: Date(), isLocked: locked)
    }

    func testUnlockedWarnsOnlyAfterTheGraceTime() {
        let start = Date()
        CarAlerts.evaluate(status(soc: 80, charging: false, locked: false), carName: "500e", rangeText: "208 km", now: start)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "alertState.unlockedSent"))
        CarAlerts.evaluate(status(soc: 80, charging: false, locked: false), carName: "500e", rangeText: "208 km", now: start.addingTimeInterval(11 * 60))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "alertState.unlockedSent"))
        CarAlerts.evaluate(status(soc: 80, charging: false, locked: true), carName: "500e", rangeText: "208 km", now: start.addingTimeInterval(12 * 60))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "alertState.unlockedSent"), "locking resets it")
    }

    func testLowWarnsOncePerDip() {
        CarAlerts.evaluate(status(soc: 30, charging: false, locked: true), carName: "500e", rangeText: "", now: Date())
        CarAlerts.evaluate(status(soc: 18, charging: false, locked: true), carName: "500e", rangeText: "", now: Date())
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "alertState.lowSent"))
        CarAlerts.evaluate(status(soc: 22, charging: false, locked: true), carName: "500e", rangeText: "", now: Date())
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "alertState.lowSent"), "22 % isn't back over the reset line")
        CarAlerts.evaluate(status(soc: 40, charging: false, locked: true), carName: "500e", rangeText: "", now: Date())
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "alertState.lowSent"))
    }

    func testWeekdayText() {
        XCTAssertEqual(Weekdays.text([2, 3, 4, 5, 6, 7]), "Mon – Sat")
        XCTAssertEqual(Weekdays.text([2, 3, 4, 6]), "Mon – Wed, Fri")
    }
}
