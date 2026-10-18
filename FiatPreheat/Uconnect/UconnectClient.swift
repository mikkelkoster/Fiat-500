import Foundation

struct UconnectAccount: Sendable, Equatable {
    var email: String
    var password: String
    var pin: String
    var brand: Brand = .fiat
    var region: Brand.Region = .europe

    var config: UconnectConfig { brand.config(in: region) }
}

struct Vehicle: Sendable, Identifiable, Hashable, Codable {
    let vin: String
    let nickname: String?
    let model: String?
    /// Service codes the car is capable of and has enabled (e.g. "ROPRECOND", "RDL").
    /// Remote commands outside this list are refused with SERVICE_NOT_SUPPORTED.
    var services: [String] = []
    /// Service codes the car is capable of but which are not enabled on the account.
    var disabledServices: [String] = []
    /// Fiat's own picture of this car, when the vehicle list includes one.
    var imageURL: URL? = nil
    var id: String { vin }
}

struct VehicleStatus: Sendable, Equatable, Codable {
    var stateOfCharge: Double?
    var range: Double?
    var rangeUnit: String?
    var isCharging: Bool?
    var isPluggedIn: Bool?
    var updatedAt: Date
    /// All doors locked, from the car's last remote status report. Nil when it hasn't said.
    var isLocked: Bool? = nil
    var isTrunkLocked: Bool? = nil
    /// When the car itself last reported, which can be long before `updatedAt` while it sleeps.
    var reportedAt: Date? = nil
    /// Fiat's estimate while charging, in minutes, when it sends one.
    var minutesToFull: Double? = nil

    /// Reads the doors and boot out of `/remote/status`.
    mutating func applyRemoteStatus(_ json: [String: Any]) {
        if let doors = json["doors"] as? [String: Any] {
            let states = doors.values.compactMap { ($0 as? [String: Any])?["status"] as? String }
            isLocked = states.isEmpty ? nil : states.allSatisfy { $0 == "LOCKED" }
        }
        if let trunk = (json["trunk"] as? [String: Any])?["status"] as? String {
            isTrunkLocked = trunk == "LOCKED"
        }
    }
}

/// Where the car last reported itself.
struct CarLocation: Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    var updatedAt: Date?
    var isApproximate: Bool

    /// Parses `/location/lastknown`. Fiat sends numbers or numeric strings and a millisecond timestamp.
    init?(json: [String: Any]) {
        func number(_ value: Any?) -> Double? {
            (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
        }
        guard let latitude = number(json["latitude"]), let longitude = number(json["longitude"]),
              latitude != 0 || longitude != 0 else { return nil }
        self.latitude = latitude
        self.longitude = longitude
        updatedAt = number(json["timeStamp"]).map { Date(timeIntervalSince1970: $0 / 1000) }
        isApproximate = json["isLocationApprox"] as? Bool ?? false
    }

    init(latitude: Double, longitude: Double, updatedAt: Date?, isApproximate: Bool = false) {
        self.latitude = latitude
        self.longitude = longitude
        self.updatedAt = updatedAt
        self.isApproximate = isApproximate
    }
}

enum OperationResult: Sendable, Equatable {
    case succeeded
    case failed
    case unknown
}

enum UconnectError: LocalizedError {
    case missingAccount
    case loginFailed(String)
    case requestFailed(Int, String)
    case commandRejected(String)
    case unexpectedResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAccount: "Add your Fiat account in Settings first."
        case .loginFailed(let reason): "Login failed: \(reason)"
        case .requestFailed(_, let body) where body.contains("SERVICE_NOT_SUPPORTED"):
            "Fiat says this car's subscription doesn't include that. It needs the My Remote package."
        case .requestFailed(let code, let body): "Server returned \(code). \(body.prefix(200))"
        case .commandRejected(let reason): "The car rejected the command: \(reason)"
        case .unexpectedResponse(let detail): "Unexpected response: \(detail.prefix(200))"
        }
    }
}

/// Talks to Stellantis' Uconnect backend the same way the Fiat app does:
/// Gigya login → Cognito identity → AWS SigV4-signed REST calls → PIN-authorised commands.
actor UconnectClient {
    private var config: UconnectConfig
    private var session: URLSession
    private var account: UconnectAccount?
    private var uid: String?
    private var aws: AWSCredentials?
    /// The owner's first name from the brand account, once signed in.
    private(set) var ownerFirstName: String?

    init(config: UconnectConfig = .fiatEU) {
        self.config = config
        self.session = Self.makeSession()
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }

    func setAccount(_ account: UconnectAccount?) {
        guard account != self.account else { return }
        self.account = account
        if let account { config = account.config }
        uid = nil
        aws = nil
        ownerFirstName = nil
        signingIn?.cancel()
        signingIn = nil
        session = Self.makeSession()
    }

    // MARK: Vehicles

    func vehicles() async throws -> [Vehicle] {
        let uid = try await authenticatedUID()
        let json = try await signedRequest(
            "GET", "/v4/accounts/\(uid)/vehicles",
            query: ["stage": "ALL", "sdp": "ALL", "brand": config.brandCode]
        )
        guard let list = json["vehicles"] as? [[String: Any]] else {
            throw UconnectError.unexpectedResponse("\(json)")
        }
        return list.compactMap { item in
            guard let vin = item["vin"] as? String else { return nil }
            let capable = (item["services"] as? [[String: Any]] ?? [])
                .filter { $0["vehicleCapable"] as? Bool == true }
            return Vehicle(
                vin: vin,
                nickname: item["nickname"] as? String,
                model: (item["modelDescription"] as? String) ?? (item["make"] as? String),
                services: capable.filter { $0["serviceEnabled"] as? Bool == true }
                    .compactMap { $0["service"] as? String },
                disabledServices: capable.filter { $0["serviceEnabled"] as? Bool != true }
                    .compactMap { $0["service"] as? String },
                imageURL: (item["vehicleImageURL"] as? String).flatMap(URL.init(string:))
            )
        }
    }

    func status(vin: String) async throws -> VehicleStatus {
        let uid = try await authenticatedUID()
        let json = try await signedRequest("GET", "/v3/accounts/\(uid)/vehicles/\(vin)/status/")
        let battery = (json["evInfo"] as? [String: Any])?["battery"] as? [String: Any]
        let range = battery?["distanceToEmpty"] as? [String: Any]
        var status = VehicleStatus(
            stateOfCharge: number(battery?["stateOfCharge"]),
            range: number(range?["value"]),
            rangeUnit: range?["unit"] as? String,
            isCharging: (battery?["chargingStatus"] as? String).map { $0 == "CHARGING" },
            isPluggedIn: battery?["plugInStatus"] as? Bool,
            updatedAt: Date()
        )
        status.reportedAt = number(json["timestamp"]).map { Date(timeIntervalSince1970: $0 / 1000) }
        // Some cars send -1 for the levels they can't charge at.
        status.minutesToFull = ["timeToFullyChargeL2", "timeToFullyChargeL3", "timeToFullyChargeL1"]
            .compactMap { number(battery?[$0]) }.first { $0 > 0 }
        // Doors and boot come from a second endpoint; the battery is the part that matters, so
        // a failure here leaves the lock state unknown instead of failing the refresh.
        if let remote = try? await signedRequest("GET", "/v1/accounts/\(uid)/vehicles/\(vin)/remote/status") {
            status.applyRemoteStatus(remote)
        }
        return status
    }

    /// The car's own charging and climate timers, as Fiat sends them.
    func carSchedules(vin: String) async throws -> [String: Any] {
        let uid = try await authenticatedUID()
        return try await signedRequest("GET", "/v4/accounts/\(uid)/vehicles/\(vin)/ev/schedule/")
    }

    /// Writes the car's timers back (the same shape `carSchedules` returned) and returns the
    /// correlation id to wait on; the car confirms like a remote command.
    func setCarSchedules(vin: String, body: [String: Any]) async throws -> String {
        let uid = try await authenticatedUID()
        let pinToken = try await pinAuthToken(uid: uid)
        let json = try await signedRequest(
            "POST", "/v4/accounts/\(uid)/vehicles/\(vin)/ev/schedule/",
            body: body.merging(["pinAuth": pinToken]) { _, new in new }
        )
        guard let correlationId = json["correlationId"] as? String else {
            throw UconnectError.commandRejected((json["debugMsg"] as? String) ?? "\(json)")
        }
        return correlationId
    }

    /// The eco-coaching trip list, as Fiat sends it. The request isn't documented and Fiat has
    /// answered "parameter missing" to an empty one, so a few shapes are tried in turn, then the
    /// last trip on its own.
    func trips(vin: String) async throws -> [String: Any] {
        let uid = try await authenticatedUID()
        let path = "/v2/accounts/\(uid)/vehicles/\(vin)/ecocoaching/get-trips/"
        let now = Date()
        let from = now.addingTimeInterval(-30 * 86_400)
        let ms = { (d: Date) in Int64(d.timeIntervalSince1970 * 1000) }
        let iso = ISO8601DateFormatter()
        let bodies: [[String: Any]] = [
            [:],
            ["vin": vin],
            ["startTime": ms(from), "endTime": ms(now)],
            ["startDate": iso.string(from: from), "endDate": iso.string(from: now)],
            ["fromDate": iso.string(from: from), "toDate": iso.string(from: now)],
        ]
        var lastError: Error?
        for body in bodies {
            do { return try await signedRequest("POST", path, body: body) }
            catch UconnectError.requestFailed(400, let text) { lastError = UconnectError.requestFailed(400, text) }
        }
        do {
            return try await signedRequest("POST", "/v2/accounts/\(uid)/vehicles/\(vin)/ecocoaching/get-last-trip/", body: [:])
        } catch {
            throw lastError ?? error
        }
    }

    /// Fiat's own picture of the car, as a PNG address, for cars the app has no picture of.
    func imageURL(vin: String, width: Int = 1200, height: Int = 640) async throws -> URL? {
        let uid = try await authenticatedUID()
        let json = try await signedRequest(
            "POST", "/v4/accounts/\(uid)/vehicles/\(vin)/image/",
            body: ["imageURLs": [["id": vin, "width": width, "height": height, "resp": "png"]]]
        )
        return Self.firstURL(in: json)
    }

    /// The first web address anywhere in a response, for replies whose shape isn't documented.
    static func firstURL(in value: Any) -> URL? {
        switch value {
        case let s as String where s.hasPrefix("http"): return URL(string: s)
        case let d as [String: Any]: return d.values.lazy.compactMap { firstURL(in: $0) }.first
        case let a as [Any]: return a.lazy.compactMap { firstURL(in: $0) }.first
        default: return nil
        }
    }

    /// The car's last reported position. Send `.locate` first to ask it for a fresh one.
    func location(vin: String) async throws -> CarLocation {
        let uid = try await authenticatedUID()
        let json = try await signedRequest("GET", "/v1/accounts/\(uid)/vehicles/\(vin)/location/lastknown")
        guard let location = CarLocation(json: json) else {
            throw UconnectError.unexpectedResponse("no position in \(json)")
        }
        return location
    }

    // MARK: Commands

    /// Queues a command and returns its correlation id. The car is reached over the
    /// cellular network, so the command is only *queued* when this returns.
    func send(_ command: RemoteCommand, vin: String) async throws -> String {
        let uid = try await authenticatedUID()
        let pinToken = try await pinAuthToken(uid: uid)
        func post(_ endpoint: RemoteCommand.Endpoint) async throws -> [String: Any] {
            try await signedRequest(
                "POST", "/\(endpoint.version)/accounts/\(uid)/vehicles/\(vin)/\(endpoint.path)",
                body: ["command": endpoint.command, "pinAuth": pinToken]
            )
        }
        let json: [String: Any]
        do {
            json = try await post(command.endpoint)
        } catch UconnectError.requestFailed(403, _) where command.fallback != nil {
            // `perform` dropped the credentials on 403; sign in again before the retry.
            _ = try await authenticatedUID()
            json = try await post(command.fallback!)
        }
        guard json["responseStatus"] as? String == "pending",
              let correlationId = json["correlationId"] as? String else {
            throw UconnectError.commandRejected((json["debugMsg"] as? String) ?? "\(json)")
        }
        return correlationId
    }

    /// Polls until the car confirms or rejects the command, or the timeout passes.
    func waitForResult(vin: String, correlationId: String, timeout: Duration = .seconds(90)) async -> OperationResult {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            if Task.isCancelled { break }
            if let result = await operationResult(vin: vin, correlationId: correlationId) {
                return result
            }
        }
        return .unknown
    }

    private func operationResult(vin: String, correlationId: String) async -> OperationResult? {
        guard let uid = try? await authenticatedUID() else { return nil }

        if let json = try? await signedRequest("GET", "/v1/accounts/\(uid)/vehicles/\(vin)/remote/\(correlationId)/status/"),
           let result = Self.parseResult((json["status"] ?? json["responseStatus"]) as? String) {
            return result
        }

        // Some accounts get 404 from the status endpoint; the notification feed carries the same outcome.
        guard let json = try? await signedRequest("GET", "/v1/accounts/\(uid)/vehicles/\(vin)/notifications", query: ["limit": "30"]),
              let items = (json["notifications"] as? [String: Any])?["items"] as? [[String: Any]],
              let match = items.first(where: { $0["correlationId"] as? String == correlationId }) else {
            return nil
        }
        let status = ((match["notification"] as? [String: Any])?["data"] as? [String: Any])?["status"] as? String
        return Self.parseResult(status) ?? .failed
    }

    static func parseResult(_ status: String?) -> OperationResult? {
        switch status?.lowercased() {
        case "success", "succeeded", "completed", "complete": .succeeded
        case "failure", "failed", "error", "rejected": .failed
        default: nil
        }
    }

    // MARK: Authentication

    /// The sign-in under way, if any. The status, the location and the car's picture are all
    /// asked for at launch; without this each would sign in at once, tripping over the others'
    /// cookies. Now the first signs in and the rest wait for it.
    private var signingIn: Task<Void, Error>?

    private func authenticatedUID() async throws -> String {
        if let uid, let aws, aws.expiration.timeIntervalSinceNow > 5 * 60 {
            return uid
        }
        if let signingIn {
            try await signingIn.value
        } else {
            let task = Task { try await login() }
            signingIn = task
            defer { signingIn = nil }
            try await task.value
        }
        guard let uid else { throw UconnectError.loginFailed("no account id") }
        return uid
    }

    private func login() async throws {
        guard let account else { throw UconnectError.missingAccount }

        // 1. Gigya (SAP Customer Data Cloud) — sets session cookies.
        let bootstrap = try await gigya("accounts.webSdkBootstrap", method: "GET", params: ["apiKey": config.gigyaAPIKey])
        try checkGigya(bootstrap, step: "bootstrap")

        // 2. Email + password.
        let loginResponse = try await gigya("accounts.login", params: gigyaDefaults([
            "loginID": account.email,
            "password": account.password,
            "sessionExpiration": "300",
            "include": "profile,data,emails,subscriptions,preferences",
        ]))
        try checkGigya(loginResponse, step: "login")
        guard let uid = loginResponse["UID"] as? String,
              let loginToken = (loginResponse["sessionInfo"] as? [String: Any])?["login_token"] as? String else {
            throw UconnectError.loginFailed("missing session")
        }
        ownerFirstName = (loginResponse["profile"] as? [String: Any])?["firstName"] as? String

        // 3. Gigya JWT.
        let jwtResponse = try await gigya("accounts.getJWT", params: gigyaDefaults([
            "login_token": loginToken,
            "fields": "profile.firstName,profile.lastName,profile.email,country,locale,data.disclaimerCodeGSDP",
        ]))
        try checkGigya(jwtResponse, step: "JWT")
        guard let idToken = jwtResponse["id_token"] as? String else {
            throw UconnectError.loginFailed("missing JWT")
        }

        // 4. Exchange for a Cognito identity.
        var tokenRequest = URLRequest(url: config.tokenURL)
        tokenRequest.httpMethod = "POST"
        applyClientHeaders(&tokenRequest, apiKey: config.apiKey)
        tokenRequest.httpBody = try JSONSerialization.data(withJSONObject: ["gigya_token": idToken])
        let identity = try await perform(tokenRequest)
        guard let token = identity["Token"] as? String, let identityId = identity["IdentityId"] as? String else {
            throw UconnectError.loginFailed("no Cognito identity")
        }

        // 5. Temporary AWS credentials for signing API calls.
        var cognito = URLRequest(url: config.cognitoURL)
        cognito.httpMethod = "POST"
        cognito.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        cognito.setValue("AWSCognitoIdentityService.GetCredentialsForIdentity", forHTTPHeaderField: "X-Amz-Target")
        cognito.httpBody = try JSONSerialization.data(withJSONObject: [
            "IdentityId": identityId,
            "Logins": ["cognito-identity.amazonaws.com": token],
        ])
        let credentials = try await perform(cognito)["Credentials"] as? [String: Any]
        guard let accessKeyId = credentials?["AccessKeyId"] as? String,
              let secretKey = credentials?["SecretKey"] as? String,
              let sessionToken = credentials?["SessionToken"] as? String,
              let expiration = number(credentials?["Expiration"]) else {
            throw UconnectError.loginFailed("no AWS credentials")
        }

        self.uid = uid
        self.aws = AWSCredentials(
            accessKeyId: accessKeyId,
            secretKey: secretKey,
            sessionToken: sessionToken,
            expiration: Date(timeIntervalSince1970: expiration)
        )
    }

    private func pinAuthToken(uid: String) async throws -> String {
        guard let pin = account?.pin, !pin.isEmpty else { throw UconnectError.missingAccount }
        let json = try await signedRequest(
            "POST", "/v1/accounts/\(uid)/ignite/pin/authenticate",
            base: config.authURL, apiKey: config.authKey,
            body: ["pin": Data(pin.utf8).base64EncodedString()]
        )
        guard let token = json["token"] as? String else {
            throw UconnectError.commandRejected("PIN not accepted")
        }
        return token
    }

    // MARK: HTTP

    private func gigyaDefaults(_ params: [String: String]) -> [String: String] {
        params.merging([
            "targetEnv": "jssdk",
            "loginMode": "standard",
            "sdk": "js_latest",
            "authMode": "cookie",
            "sdkBuild": "12234",
            "format": "json",
            "APIKey": config.gigyaAPIKey,
        ]) { current, _ in current }
    }

    private func gigya(_ endpoint: String, method: String = "POST", params: [String: String]) async throws -> [String: Any] {
        var components = URLComponents(url: config.gigyaURL.appending(path: endpoint), resolvingAgainstBaseURL: false)!
        components.percentEncodedQueryItems = params.map {
            URLQueryItem(name: $0.key, value: $0.value.addingPercentEncoding(withAllowedCharacters: .rfc3986Unreserved))
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        return try await perform(request)
    }

    private func checkGigya(_ json: [String: Any], step: String) throws {
        guard number(json["statusCode"]) == 200 else {
            let reason = (json["errorDetails"] as? String) ?? (json["errorMessage"] as? String) ?? "status \(json["statusCode"] ?? "?")"
            throw UconnectError.loginFailed("\(step): \(reason)")
        }
    }

    private func signedRequest(
        _ method: String,
        _ path: String,
        base: URL? = nil,
        apiKey: String? = nil,
        query: [String: String] = [:],
        body: [String: Any]? = nil
    ) async throws -> [String: Any] {
        guard let aws else { throw UconnectError.loginFailed("not signed in") }
        var components = URLComponents(url: (base ?? config.apiURL).appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.percentEncodedQueryItems = query.sorted { $0.key < $1.key }.map {
                URLQueryItem(name: $0.key, value: $0.value.addingPercentEncoding(withAllowedCharacters: .rfc3986Unreserved))
            }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        applyClientHeaders(&request, apiKey: apiKey ?? config.apiKey)
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        SigV4.sign(&request, credentials: aws, region: config.region)
        return try await perform(request)
    }

    private func applyClientHeaders(_ request: inout URLRequest, apiKey: String) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CWP", forHTTPHeaderField: "x-clientapp-name")
        request.setValue("1.0", forHTTPHeaderField: "x-clientapp-version")
        request.setValue(String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)), forHTTPHeaderField: "clientrequestid")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(config.locale, forHTTPHeaderField: "locale")
        request.setValue("web", forHTTPHeaderField: "x-originator-type")
    }

    private func perform(_ request: URLRequest) async throws -> [String: Any] {
        var request = request
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(decoding: data, as: UTF8.self)
        guard (200..<300).contains(code) else {
            if code == 401 || code == 403 { aws = nil }
            throw UconnectError.requestFailed(code, text)
        }
        guard !data.isEmpty else { return [:] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UconnectError.unexpectedResponse(text)
        }
        return json
    }

    private func number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: n.doubleValue
        case let s as String: Double(s)
        default: nil
        }
    }
}

private extension CharacterSet {
    static let rfc3986Unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
