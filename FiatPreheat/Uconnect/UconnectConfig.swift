import Foundation

/// Endpoints and public client keys used by the official Fiat (Uconnect) app in Europe.
///
/// There is no public API for Stellantis connected services. These values come from the
/// open-source py-uconnect project (https://github.com/hass-uconnect/py-uconnect), which
/// mirrors what the Fiat web/mobile apps send. Stellantis can change them at any time.
struct UconnectConfig: Sendable {
    let region: String
    let gigyaURL: URL
    let gigyaAPIKey: String
    let tokenURL: URL
    let apiURL: URL
    let apiKey: String
    let authURL: URL
    let authKey: String
    let locale: String
    let brandCode: String

    var cognitoURL: URL { URL(string: "https://cognito-identity.\(region).amazonaws.com/")! }

    static let fiatEU = UconnectConfig(
        region: "eu-west-1",
        gigyaURL: URL(string: "https://loginmyuconnect.fiat.com")!,
        gigyaAPIKey: "3_mOx_J2dRgjXYCdyhchv3b5lhi54eBcdCTX4BI8MORqmZCoQWhA0mV2PTlptLGUQI",
        tokenURL: URL(string: "https://authz.sdpr-01.fcagcv.com/v2/cognito/identity/token")!,
        apiURL: URL(string: "https://channels.sdpr-01.fcagcv.com")!,
        apiKey: "2wGyL6PHec9o1UeLPYpoYa1SkEWqeBur9bLsi24i",
        authURL: URL(string: "https://mfa.fcl-01.fcagcv.com")!,
        authKey: "JWRYW7IYhW9v0RqDghQSx4UcRYRILNmc8zAuh5ys",
        locale: "de_de",
        brandCode: "FIAT"
    )
}

/// Remote commands understood by the vehicle, as listed by py-uconnect. Each is POSTed with a PIN
/// token to `/{version}/accounts/{uid}/vehicles/{vin}/{path}`. The raw value is also the service
/// code in the car's `services` list: the car refuses a command whose service isn't enabled, and on
/// the 500e everything here except climate comes with Fiat's paid "My Remote" package.
enum RemoteCommand: String, Sendable, CaseIterable {
    /// Cabin climate. The 500e heats or cools to the temperature last set in the car.
    case preconditionOn = "ROPRECOND"
    case preconditionOff = "ROPRECOND_OFF"
    case lock = "RDL"
    case unlock = "RDU"
    case lights = "ROLIGHTS"
    case trunkUnlock = "ROTRUNKUNLOCK"
    case chargeNow = "CNOW"
    /// Wakes the car so it reports fresh battery and charging data.
    case deepRefresh = "DEEPREFRESH"
    /// Asks the car for its position; read it afterwards from `location/lastknown`.
    case locate = "VF"

    struct Endpoint: Equatable, Sendable {
        let command: String
        let version: String
        let path: String
    }

    var endpoint: Endpoint {
        switch self {
        case .trunkUnlock: Endpoint(command: rawValue, version: "v2", path: "remote")
        case .chargeNow: Endpoint(command: rawValue, version: "v1", path: "ev/chargenow")
        case .deepRefresh: Endpoint(command: rawValue, version: "v1", path: "ev")
        case .locate: Endpoint(command: rawValue, version: "v1", path: "location/")
        default: Endpoint(command: rawValue, version: "v1", path: "remote")
        }
    }

    /// Newer cars answer 403 to the first form of some commands; py-uconnect then retries this one.
    var fallback: Endpoint? {
        switch self {
        case .chargeNow: Endpoint(command: "START_CHARGE", version: "v4", path: "ev/chargenow")
        case .deepRefresh: Endpoint(command: "DEEPREFRESH2", version: "v2", path: "ev")
        default: nil
        }
    }
}
