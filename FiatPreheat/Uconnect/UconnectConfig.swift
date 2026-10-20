import Foundation

/// Endpoints and public client keys used by the official brand apps.
///
/// There is no public API for Stellantis connected services. These values come from the
/// open-source py-uconnect project (https://github.com/hass-uconnect/py-uconnect), which
/// mirrors what the brand web/mobile apps send. Stellantis can change them at any time.
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

    static let fiatEU = Brand.fiat.config(in: .europe)
}

/// The car brands Varme signs in to. Each brand has its own login service; the car data behind
/// it is Stellantis' shared Uconnect platform, one for Europe and Asia, one for the Americas.
enum Brand: String, CaseIterable, Codable, Sendable, Identifiable {
    case fiat, jeep, alfaRomeo, maserati, chrysler, dodge, ram

    var id: String { rawValue }

    var name: String {
        switch self {
        case .fiat: "Fiat"
        case .jeep: "Jeep"
        case .alfaRomeo: "Alfa Romeo"
        case .maserati: "Maserati"
        case .chrysler: "Chrysler"
        case .dodge: "Dodge"
        case .ram: "Ram"
        }
    }

    /// What the brand calls the paid package that unlocks remote commands.
    var remotePackageName: String {
        switch self {
        case .fiat, .alfaRomeo, .jeep, .maserati: "My Remote"
        case .chrysler, .dodge, .ram: "Uconnect Services"
        }
    }

    /// Where the brand sells cars with Uconnect Services, as py-uconnect lists it.
    var regions: [Region] {
        switch self {
        case .fiat: [.europe, .northAmerica, .asia]
        case .jeep: [.europe, .northAmerica, .asia]
        case .alfaRomeo: [.europe, .northAmerica, .asia]
        case .maserati: [.europe, .northAmerica, .asia]
        case .chrysler, .dodge, .ram: [.northAmerica]
        }
    }

    enum Region: String, CaseIterable, Codable, Sendable, Identifiable {
        case europe, northAmerica, asia
        var id: String { rawValue }
        var name: String {
            switch self {
            case .europe: "Europe"
            case .northAmerica: "US and Canada"
            case .asia: "Asia and Pacific"
            }
        }
    }

    func config(in region: Region) -> UconnectConfig {
        let (loginURL, loginKey) = login(in: region)
        let americas = region == .northAmerica
        return UconnectConfig(
            region: americas ? "us-east-1" : "eu-west-1",
            gigyaURL: URL(string: loginURL)!,
            gigyaAPIKey: loginKey,
            tokenURL: URL(string: americas ? "https://authz.sdpr-02.fcagcv.com/v2/cognito/identity/token" : "https://authz.sdpr-01.fcagcv.com/v2/cognito/identity/token")!,
            apiURL: URL(string: americas ? "https://channels.sdpr-02.fcagcv.com" : "https://channels.sdpr-01.fcagcv.com")!,
            apiKey: americas ? "OgNqp2eAv84oZvMrXPIzP8mR8a6d9bVm1aaH9LqU" : "2wGyL6PHec9o1UeLPYpoYa1SkEWqeBur9bLsi24i",
            authURL: URL(string: americas ? "https://mfa.fcl-02.fcagcv.com" : "https://mfa.fcl-01.fcagcv.com")!,
            authKey: americas ? "fNQO6NjR1N6W0E5A6sTzR3YY4JGbuPv48Nj9aZci" : "JWRYW7IYhW9v0RqDghQSx4UcRYRILNmc8zAuh5ys",
            locale: americas ? "en_us" : "de_de",
            brandCode: brandCode(in: region)
        )
    }

    private func login(in region: Region) -> (String, String) {
        switch (self, region) {
        case (.fiat, .europe): ("https://loginmyuconnect.fiat.com", "3_mOx_J2dRgjXYCdyhchv3b5lhi54eBcdCTX4BI8MORqmZCoQWhA0mV2PTlptLGUQI")
        case (.fiat, .northAmerica): ("https://login-us.fiat.com", "3_WfFvlZJwcSdOD0LFQCngUV3W390R4Yshpuq3RsZvnV4VG0c9Q6R0RtDwcXc8dTrI")
        case (.fiat, .asia): ("https://login-iap.fiat.com", "4_YAQNaPqdPEUbbzhvhunKAA")
        case (.jeep, .europe): ("https://login.jeep.com", "3_ZvJpoiZQ4jT5ACwouBG5D1seGEntHGhlL0JYlZNtj95yERzqpH4fFyIewVMmmK7j")
        case (.jeep, .northAmerica): ("https://login-us.jeep.com", "3_5qxvrevRPG7--nEXe6huWdVvF5kV7bmmJcyLdaTJ8A45XUYpaR398QNeHkd7EB1X")
        case (.jeep, .asia): ("https://login-iap.jeep.com", "4_zqGYHC7rM8RCHHl4YFDebA")
        case (.alfaRomeo, .europe): ("https://login.alfaromeo.com", "3_h8sj2VQI-KYXiunPq9a1QuAA4yWkY0r5AD1u8A8B1RPn_Cvl54xcoc2-InH5onJ1")
        case (.alfaRomeo, .northAmerica): ("https://login-us.alfaromeo.com", "3_FSxGyaktviayTDRcgp9r9o2KjuFSrHT13wWNN9zPrvAGUCoXPDqoIPOwlBUhck4A")
        case (.alfaRomeo, .asia): ("https://login-iap.alfaromeo.com", "4_PSQeADnQ4p5XOaDgT0B5pA")
        case (.maserati, .europe): ("https://login.maserati.com", "3_rNbVuhn2gIt3BnLjlGsJcMo26Lft3avDne_FLRT34Dy_9OxHtCVOnplwY436lGZa")
        case (.maserati, .northAmerica): ("https://login-us.maserati.com", "3_nShL4-O7IL0OGqroO8AzwiRU0-ZHcBZ4TLBrh5MORusMo5XYxhCLXPYfjI4OOLOy")
        case (.maserati, .asia): ("https://accounts.au1.gigya.com", "4_uwF-in6KF-aMbEkPAb-fOg")
        case (.chrysler, _): ("https://login-us.chrysler.com", "3_cv4AzHkJh48-cqwaf_Ahcg1HnsmQqz1lm0sOdVdHW5FjT3m6SyywywOBaskBQqwn")
        case (.dodge, _): ("https://login-us.dodge.com", "4_dSRvo6ZIpp8_St7BF9VHGA")
        case (.ram, _): ("https://login-us.ramtrucks.com", "3_7YjzjoSb7dYtCP5-D6FhPsCciggJFvM14hNPvXN9OsIiV1ujDqa4fNltDJYnHawO")
        }
    }

    /// The `brand` filter the vehicle list takes. The Americas platform answers to ALL.
    private func brandCode(in region: Region) -> String {
        if region == .northAmerica { return "ALL" }
        switch self {
        case .fiat: return "FIAT"
        case .jeep: return "REST"
        case .alfaRomeo: return "ALFAROMEO"
        case .maserati: return "MASERATI"
        case .chrysler, .dodge, .ram: return "ALL"
        }
    }
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
    /// Not every car offers it; where it isn't listed, locking the car locks the boot too.
    case trunkLock = "ROTRUNKLOCK"
    /// Cars with a liftgate (most Jeeps) list these instead of the boot ones.
    case liftgateUnlock = "ROLIFTGATEUNLOCK"
    case liftgateLock = "ROLIFTGATELOCK"
    /// Horn and lights together: what many North American cars offer to find them.
    case hornLights = "HBLF"
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
        case .trunkUnlock, .trunkLock, .liftgateUnlock, .liftgateLock: Endpoint(command: rawValue, version: "v2", path: "remote")
        case .chargeNow: Endpoint(command: rawValue, version: "v1", path: "ev/chargenow")
        case .deepRefresh: Endpoint(command: rawValue, version: "v1", path: "ev")
        case .locate: Endpoint(command: rawValue, version: "v1", path: "location/")
        default: Endpoint(command: rawValue, version: "v1", path: "remote")
        }
    }

    /// Newer cars answer 403 to the first form of some commands; py-uconnect then retries this one.
    var fallback: Endpoint? {
        switch self {
        // Untested on a liftgate car: if v2 refuses, try the plain remote path.
        case .liftgateUnlock, .liftgateLock: Endpoint(command: rawValue, version: "v1", path: "remote")
        case .chargeNow: Endpoint(command: "START_CHARGE", version: "v4", path: "ev/chargenow")
        // The v2 endpoint names it DEEPREFRESH too: Fiat answers 400 "must be DEEPREFRESH" to
        // the DEEPREFRESH2 py-uconnect sends (seen on a 2022 500e, 2026-10-18).
        case .deepRefresh: Endpoint(command: "DEEPREFRESH", version: "v2", path: "ev")
        default: nil
        }
    }
}
