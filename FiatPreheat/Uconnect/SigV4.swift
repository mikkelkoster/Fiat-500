import CryptoKit
import Foundation

struct AWSCredentials: Sendable {
    let accessKeyId: String
    let secretKey: String
    let sessionToken: String
    let expiration: Date
}

/// AWS Signature Version 4 for API Gateway (`execute-api`). Signs `host` and every
/// `x-amz-*` header, matching what the Uconnect backend accepts from the official apps.
enum SigV4 {
    static func sign(
        _ request: inout URLRequest,
        credentials: AWSCredentials,
        region: String,
        service: String = "execute-api",
        date: Date = Date()
    ) {
        guard let url = request.url, let host = url.host else { return }
        let (amzDate, dateStamp) = timestamps(date)
        let payloadHash = sha256Hex(request.httpBody ?? Data())

        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(credentials.sessionToken, forHTTPHeaderField: "x-amz-security-token")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")

        var headers = ["host": host]
        for (name, value) in request.allHTTPHeaderFields ?? [:] where name.lowercased().hasPrefix("x-amz-") {
            headers[name.lowercased()] = value.trimmingCharacters(in: .whitespaces)
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components?.percentEncodedPath ?? "/"

        let authorization = authorizationHeader(
            method: request.httpMethod ?? "GET",
            path: path.isEmpty ? "/" : path,
            query: components?.percentEncodedQuery ?? "",
            headers: headers,
            payloadHash: payloadHash,
            accessKeyId: credentials.accessKeyId,
            secretKey: credentials.secretKey,
            region: region,
            service: service,
            amzDate: amzDate,
            dateStamp: dateStamp
        )
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }

    /// Pure signing step, separated out so it can be checked against AWS's published test vectors.
    static func authorizationHeader(
        method: String,
        path: String,
        query: String,
        headers: [String: String],
        payloadHash: String,
        accessKeyId: String,
        secretKey: String,
        region: String,
        service: String,
        amzDate: String,
        dateStamp: String
    ) -> String {
        let canonicalQuery = query
            .split(separator: "&", omittingEmptySubsequences: true)
            .map(String.init)
            .sorted()
            .joined(separator: "&")
        let signedHeaderNames = headers.keys.sorted()
        let canonicalHeaders = signedHeaderNames.map { "\($0):\(headers[$0]!)\n" }.joined()
        let signedHeaders = signedHeaderNames.joined(separator: ";")

        let canonicalRequest = [method, path, canonicalQuery, canonicalHeaders, signedHeaders, payloadHash]
            .joined(separator: "\n")
        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = ["AWS4-HMAC-SHA256", amzDate, scope, sha256Hex(Data(canonicalRequest.utf8))]
            .joined(separator: "\n")

        var key = SymmetricKey(data: Data("AWS4\(secretKey)".utf8))
        for part in [dateStamp, region, service, "aws4_request"] {
            key = SymmetricKey(data: hmac(key, part))
        }
        let signature = hmac(key, stringToSign).map { String(format: "%02x", $0) }.joined()

        return "AWS4-HMAC-SHA256 Credential=\(accessKeyId)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func hmac(_ key: SymmetricKey, _ message: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key))
    }

    private static func timestamps(_ date: Date) -> (amzDate: String, dateStamp: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = formatter.string(from: date)
        return (amzDate, String(amzDate.prefix(8)))
    }
}
