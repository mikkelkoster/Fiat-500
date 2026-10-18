import SwiftUI

/// A factory paint we have a picture of: Fiat's code (on the door sticker), a name, and the
/// colour of the swatch and of the light behind the car.
struct CarPaint: Identifiable, Hashable {
    let code: String
    let name: String
    let hex: String
    var id: String { code }

    /// The New 500 (500e), as Fiat's render service draws it. The pictures are cut out with
    /// Tools/car-renders and live in the asset catalog as car-fiat-500e-<code>.
    static let fiat500e: [CarPaint] = [
        CarPaint(code: "601", name: "Black", hex: "#18181b"),
        CarPaint(code: "815", name: "Grey", hex: "#3f3f46"),
        CarPaint(code: "268", name: "White", hex: "#f4f4f5"),
        CarPaint(code: "252", name: "Light blue", hex: "#cbd5e1"),
        CarPaint(code: "230", name: "Blue", hex: "#1e40af"),
        CarPaint(code: "237", name: "Rose gold", hex: "#fecdd3"),
        CarPaint(code: "111", name: "Red", hex: "#dc2626"),
        CarPaint(code: "554", name: "Yellow", hex: "#facc15"),
        CarPaint(code: "878", name: "Lime", hex: "#a3e635"),
    ]

    var imageName: String { "car-fiat-500e-\(code)" }

    /// The paint whose swatch is this colour, else black.
    static func fiat500e(matching hex: String) -> CarPaint {
        fiat500e.first { $0.hex.lowercased() == hex.lowercased() } ?? fiat500e[0]
    }
}
