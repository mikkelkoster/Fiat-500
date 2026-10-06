import Foundation

struct UconnectAccount: Sendable, Equatable {
    var email: String
    var password: String
    var pin: String
}

struct Vehicle: Sendable, Identifiable, Hashable {
    let vin: String
    let nickname: String?
    let model: String?
    var id: String { vin }
}

struct VehicleStatus: Sendable, Equatable {
    var stateOfCharge: Double?
    var range: Double?
    var rangeUnit: String?
    var isCharging: Bool?
    var isPluggedIn: Bool?
    var updatedAt: Date
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
        case .requestFailed(let code, let body): "Server returned \(code). \(body.prefix(200))"
        case .commandRejected(let reason): "The car rejected the command: \(reason)"
        case .unexpectedResponse(let detail): "Unexpected response: \(detail.prefix(200))"
        }
    }
}

/// Talks to Stellantis' Uconnect backend the same way the Fiat app does:
/// Gigya login → Cognito identity → AWS SigV4-signed REST calls → PIN-authorised commands.
actor UconnectClient {
    private let config: UconnectConfig
    private var session: URLSession
    private var account: UconnectAccount?
    private var uid: String?
    private var aws: AWSCredentials?

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
        uid = nil
        aws = nil
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
            return Vehicle(
                vin: vin,
                nickname: item["nickname"] as? String,
                model: (item["modelDescription"] as? String) ?? (item["make"] as? String)
            )
        }
    }

    func status(vin: String) async throws -> VehicleStatus {
        let uid = try await authenticatedUID()
        let json = try await signedRequest("GET", "/v3/accounts/\(uid)/vehicles/\(vin)/status/")
        let battery = (json["evInfo"] as? [String: Any])?["battery"] as? [String: Any]
        let range = battery?["distanceToEmpty"] as? [String: Any]
        return VehicleStatus(
            stateOfCharge: number(battery?["stateOfCharge"]),
            range: number(range?["value"]),
            rangeUnit: range?["unit"] as? String,
            isCharging: (battery?["chargingStatus"] as? String).map { $0 == "CHARGING" },
            isPluggedIn: battery?["plugInStatus"] as? Bool,
            updatedAt: Date()
        )
    }

    // MARK: Commands

    /// Queues a command and returns its correlation id. The car is reached over the
    /// cellular network, so the command is only *queued* when this returns.
    func send(_ command: RemoteCommand, vin: String) async throws -> String {
        let uid = try await authenticatedUID()
        let pinToken = try await pinAuthToken(uid: uid)
        let json = try await signedRequest(
            "POST", "/v1/accounts/\(uid)/vehicles/\(vin)/remote",
            body: ["command": command.rawValue, "pinAuth": pinToken]
        )
        guard json["responseStatus"] as? String == "pending",
              let correlationId = json["correlationId"] as? String else {
            throw UconnectError.commandRejected((json["debugMsg"] as? String) ?? "\(json)")
        }
        return correlationId
    }

    /// Polls until the car confirms or rejects the command, or the timeout passes.
    func waitForResult(vin: String, correlationId: String, timeout: Duration = .seconds(90)) async -> OperationResult {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .seconds(3))
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

    private func authenticatedUID() async throws -> String {
        if let uid, let aws, aws.expiration.timeIntervalSinceNow > 5 * 60 {
            return uid
        }
        try await login()
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
