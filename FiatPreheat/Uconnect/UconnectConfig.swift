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

/// Remote commands understood by the vehicle. The 500e uses the "precondition" pair for
/// cabin climate; it heats or cools to the temperature last set in the car.
enum RemoteCommand: String, Sendable {
    case preconditionOn = "ROPRECOND"
    case preconditionOff = "ROPRECOND_OFF"
}
