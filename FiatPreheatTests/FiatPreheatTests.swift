import XCTest
@testable import FiatPreheat

final class SigV4Tests: XCTestCase {
    /// AWS SigV4 test suite, "get-vanilla".
    func testMatchesAWSReferenceVector() {
        let header = SigV4.authorizationHeader(
            method: "GET",
            path: "/",
            query: "",
            headers: ["host": "example.amazonaws.com", "x-amz-date": "20150830T123600Z"],
            payloadHash: SigV4.sha256Hex(Data()),
            accessKeyId: "AKIDEXAMPLE",
            secretKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
            region: "us-east-1",
            service: "service",
            amzDate: "20150830T123600Z",
            dateStamp: "20150830"
        )
        XCTAssertEqual(
            header,
            "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, "
                + "SignedHeaders=host;x-amz-date, "
                + "Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31"
        )
    }

    func testSignKeepsTrailingSlashAndSignsSecurityToken() {
        var request = URLRequest(url: URL(string: "https://channels.sdpr-01.fcagcv.com/v3/accounts/abc/vehicles/VIN/status/")!)
        let credentials = AWSCredentials(accessKeyId: "AK", secretKey: "SK", sessionToken: "TOKEN", expiration: .distantFuture)
        SigV4.sign(&request, credentials: credentials, region: "eu-west-1")

        XCTAssertEqual(request.value(forHTTPHeaderField: "x-amz-security-token"), "TOKEN")
        let auth = try! XCTUnwrap(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(auth.contains("SignedHeaders=host;x-amz-content-sha256;x-amz-date;x-amz-security-token"))
        XCTAssertTrue(auth.contains("/eu-west-1/execute-api/aws4_request"))
    }
}

final class ScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Copenhagen")!
        return calendar
    }()

    func testStartIsLeadMinutesBeforeReadyTime() {
        let schedule = PreheatSchedule(readyHour: 7, readyMinute: 30, leadMinutes: 20)
        XCTAssertEqual(schedule.start.hour, 7)
        XCTAssertEqual(schedule.start.minute, 10)
    }

    func testStartCrossingMidnightMovesToPreviousDay() {
        let schedule = PreheatSchedule(readyHour: 0, readyMinute: 10, leadMinutes: 20, weekdays: [2])
        XCTAssertEqual(schedule.start.hour, 23)
        XCTAssertEqual(schedule.start.minute, 50)
        XCTAssertEqual(schedule.startWeekday(forReadyWeekday: 2), 1)
        XCTAssertEqual(schedule.startWeekday(forReadyWeekday: 1), 7)
    }

    func testUpcomingStartsSkipsUnselectedDays() {
        // Friday 3 Oct 2025, 12:00 Copenhagen.
        let friday = calendar.date(from: DateComponents(year: 2025, month: 10, day: 3, hour: 12))!
        let schedule = PreheatSchedule(readyHour: 7, readyMinute: 30, leadMinutes: 20, weekdays: [2, 3, 4, 5, 6])
        let next = schedule.upcomingStarts(after: friday, calendar: calendar).first!
        XCTAssertEqual(calendar.dateComponents([.weekday, .hour, .minute], from: next),
                       DateComponents(hour: 7, minute: 10, weekday: 2))
    }

    func testDisabledScheduleHasNoStarts() {
        let schedule = PreheatSchedule(isEnabled: false)
        XCTAssertTrue(schedule.upcomingStarts(after: .now).isEmpty)
    }

    func testOperationStatusParsing() {
        XCTAssertEqual(UconnectClient.parseResult("SUCCESS"), .succeeded)
        XCTAssertEqual(UconnectClient.parseResult("failure"), .failed)
        XCTAssertNil(UconnectClient.parseResult("pending"))
    }
}

final class RemoteTests: XCTestCase {
    func testCommandsGoWherePyUconnectSendsThem() {
        XCTAssertEqual(RemoteCommand.lock.endpoint, .init(command: "RDL", version: "v1", path: "remote"))
        XCTAssertEqual(RemoteCommand.trunkUnlock.endpoint, .init(command: "ROTRUNKUNLOCK", version: "v2", path: "remote"))
        XCTAssertEqual(RemoteCommand.trunkLock.endpoint, .init(command: "ROTRUNKLOCK", version: "v2", path: "remote"))
        XCTAssertEqual(RemoteCommand.liftgateUnlock.endpoint, .init(command: "ROLIFTGATEUNLOCK", version: "v2", path: "remote"))
        XCTAssertEqual(RemoteCommand.liftgateUnlock.fallback, .init(command: "ROLIFTGATEUNLOCK", version: "v1", path: "remote"))
        XCTAssertEqual(RemoteCommand.hornLights.endpoint, .init(command: "HBLF", version: "v1", path: "remote"))
        XCTAssertEqual(RemoteCommand.chargeNow.endpoint, .init(command: "CNOW", version: "v1", path: "ev/chargenow"))
        XCTAssertEqual(RemoteCommand.chargeNow.fallback, .init(command: "START_CHARGE", version: "v4", path: "ev/chargenow"))
        // Not py-uconnect's DEEPREFRESH2: the v2 endpoint answered 400 "must be DEEPREFRESH".
        XCTAssertEqual(RemoteCommand.deepRefresh.fallback, .init(command: "DEEPREFRESH", version: "v2", path: "ev"))
        XCTAssertEqual(RemoteCommand.locate.endpoint, .init(command: "VF", version: "v1", path: "location/"))
        XCTAssertNil(RemoteCommand.preconditionOn.fallback)
    }

    func testLocationParsesStringsAndMilliseconds() throws {
        let location = try XCTUnwrap(CarLocation(json: [
            "latitude": "55.6805", "longitude": 12.5853, "timeStamp": 1_760_000_000_000, "isLocationApprox": true,
        ]))
        XCTAssertEqual(location.latitude, 55.6805, accuracy: 0.0001)
        XCTAssertEqual(location.longitude, 12.5853, accuracy: 0.0001)
        XCTAssertEqual(location.updatedAt, Date(timeIntervalSince1970: 1_760_000_000))
        XCTAssertTrue(location.isApproximate)
        XCTAssertNil(CarLocation(json: ["latitude": 0, "longitude": 0]))
    }

    func testDoorsAreLockedOnlyWhenEveryDoorIs() {
        var status = VehicleStatus(updatedAt: .now)
        status.applyRemoteStatus(["doors": ["driver": ["status": "LOCKED"], "passenger": ["status": "LOCKED"]],
                                  "trunk": ["status": "UNLOCKED"]])
        XCTAssertEqual(status.isLocked, true)
        XCTAssertEqual(status.isTrunkLocked, false)
        status.applyRemoteStatus(["doors": ["driver": ["status": "LOCKED"], "passenger": ["status": "UNLOCKED"]]])
        XCTAssertEqual(status.isLocked, false)
    }

    func testMissingSubscriptionSaysSo() {
        let error = UconnectError.requestFailed(400, #"{"name":"SERVICE_NOT_SUPPORTED"}"#)
        XCTAssertTrue(error.localizedDescription.contains("My Remote"))
    }
}
