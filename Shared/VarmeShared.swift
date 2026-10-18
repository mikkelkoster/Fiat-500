#if canImport(ActivityKit)
import ActivityKit
#endif
import Foundation

// Shared between the app and the widget extension: what the widgets show, and the Live Activity.

enum VarmeGroup {
    #if os(watchOS)
    static let id = "group.dk.koster.varme.watch"
    #else
    static let id = "group.dk.koster.varme"
    #endif
    static let snapshotKey = "snapshot"
    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
}

/// Everything a widget needs, written by the app whenever the car's state changes.
struct CarSnapshot: Codable, Equatable {
    var carName: String
    var plate: String
    var stateOfCharge: Double?
    var rangeKm: Double?
    var useMiles: Bool
    var isCharging: Bool
    var isPluggedIn: Bool
    var isLocked: Bool?
    var preheatStartedAt: Date?
    var nextSchedule: String?
    var hasCarImage: Bool
    var updatedAt: Date
    /// Which picture of the car, in the asset catalog; follows the paint chosen in the app.
    var carImageName: String? = nil

    var carImage: String { carImageName ?? "car-fiat-500e-601" }

    /// Marks a picture made on the phone and left in the App Group, not one in the asset catalog.
    static let sharedPictureName = "group:car.png"
    static var sharedPictureURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: VarmeGroup.id)?.appending(path: "car.png")
    }

    static let placeholder = CarSnapshot(carName: "500e", plate: "ED 35079", stateOfCharge: 100, rangeKm: 260, useMiles: false,
                                         isCharging: false, isPluggedIn: true, isLocked: true, preheatStartedAt: nil,
                                         nextSchedule: "Mon 07:30", hasCarImage: true, updatedAt: Date())

    static func load() -> CarSnapshot? {
        guard let data = VarmeGroup.defaults.data(forKey: VarmeGroup.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(CarSnapshot.self, from: data)
    }

    func save() {
        VarmeGroup.defaults.set(try? JSONEncoder().encode(self), forKey: VarmeGroup.snapshotKey)
    }

    var isPreheating: Bool {
        guard let preheatStartedAt else { return false }
        return Date().timeIntervalSince(preheatStartedAt) < 30 * 60
    }

    var rangeText: String {
        guard let rangeKm else { return "–" }
        return useMiles ? "\(Int(rangeKm / 1.609)) mi" : "\(Int(rangeKm)) km"
    }
}

#if canImport(ActivityKit) && os(iOS)
/// The preheat Live Activity: fixed facts in the attributes, the end time in the state.
struct PreheatActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endDate: Date
        var warmBy: String?
        var stateOfCharge: Int?
        var rangeText: String?
    }
    var carName: String
    var plate: String
}
#endif

#if os(iOS)
import SwiftUI

extension CarSnapshot {
    /// The car's picture for a widget, from the asset catalog or the App Group.
    var carPicture: Image {
        if carImage == Self.sharedPictureName, let url = Self.sharedPictureURL, let image = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: image)
        }
        return Image(carImage == Self.sharedPictureName ? "car-fiat-500e-601" : carImage)
    }
}
#endif

/// Deep links the widgets open the app with; the app sends the command.
enum VarmeLink {
    static let preheat = URL(string: "varme://preheat")!
    static let stop = URL(string: "varme://stop")!
    static let lock = URL(string: "varme://lock")!
    static let unlock = URL(string: "varme://unlock")!
    static let find = URL(string: "varme://find")!
    static let open = URL(string: "varme://open")!
}
