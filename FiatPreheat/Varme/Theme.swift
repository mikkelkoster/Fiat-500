import SwiftUI

// The Varme design system, as tokens. The source of truth is the published system
// ("Varme design system" on claude.ai); keep this file in step with its tokens.json.
// Tailwind colours only, dark only. Colour means a state and each state has one colour.

enum V {
    // MARK: Colour

    static let ground = Color(hex: 0x09090b)       // zinc-950: the screen; ink on light fills
    static let surface = Color(hex: 0x18181b)      // zinc-900: cards, tiles, sheets
    static let raised = Color(hex: 0x27272a)       // zinc-800: controls on a surface, every border
    static let outline = Color(hex: 0x3f3f46)      // zinc-700: a line that must show on raised
    static let text = Color(hex: 0xf4f4f5)         // zinc-100: values, body; white fills
    static let textMuted = Color(hex: 0xa1a1aa)    // zinc-400: labels, status line, timestamps
    static let textFaint = Color(hex: 0x71717a)    // zinc-500: pending states only
    static let positive = Color(hex: 0x4ade80)     // green-400: battery ≥ 40 %, charging, locked, switch on
    static let heat = Color(hex: 0xfb923c)         // orange-400: heating
    static let cool = Color(hex: 0x38bdf8)         // sky-400: cooling, position, route
    static let amber = Color(hex: 0xfbbf24)        // amber-400: battery 15–39 %, unlocked, lights on
    static let danger = Color(hex: 0xf87171)       // red-400: battery < 15 %, failed, delete
    static let scrim = Color(hex: 0x09090b).opacity(0.55)
    static let tile = raised                         // zinc-800: tiles and buttons on the home screen
    static let readTile = raised.opacity(0.6)        // zinc-800 at 60 %: read-only tiles (battery, range)
    static let tileLine = outline.opacity(0.6)      // zinc-700: their edge

    /// An active fill: the state colour at 12 % behind a 1.5 pt border of the full colour.
    static func activeFill(_ state: Color) -> Color { state.opacity(0.12) }

    // MARK: Type (Sora, variable; bundled under Resources/Fonts)

    static func sora(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Sora", size: size).weight(weight)
    }
    static let display = sora(72, .ultraLight)     // the car's name, the schedule time
    static let number = sora(44, .ultraLight)      // battery %, range
    static let title = sora(26, .light)            // sheet and onboarding titles
    static let button = sora(17, .semibold)
    static let body = sora(15)
    static let label = sora(13)
    static let eyebrow = sora(12)                  // + 3 pt tracking, uppercase

    // MARK: Spacing and radii

    static let gutter: CGFloat = 20
    static let cardGap: CGFloat = 12
    static let tileHeight: CGFloat = 96
    static let buttonHeight: CGFloat = 60
    static let control: CGFloat = 44
    static let radiusCard: CGFloat = 24
    static let radiusSheet: CGFloat = 32

    // MARK: Battery bands

    static func batteryColor(_ soc: Double?) -> Color {
        guard let soc else { return textMuted }
        return soc >= 40 ? positive : soc >= 15 ? amber : danger
    }

    static func batteryWord(_ soc: Double?) -> String? {
        guard let soc else { return nil }
        return soc >= 40 ? nil : soc >= 15 ? "Low" : "Very low"
    }
}

extension Text {
    /// The greeting and section eyebrows: 12 pt, 3 pt tracking, uppercase, muted.
    func eyebrowStyle() -> some View {
        font(V.eyebrow).tracking(3).textCase(.uppercase).foregroundStyle(V.textMuted)
    }
}

/// A Phosphor icon from the asset catalog (regular weight, 16/256 stroke), tinted like text.
struct PhIcon: View {
    let name: String
    var size: CGFloat = 22

    var body: some View {
        Image("ph-\(name)")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

extension Color {
    /// `#rrggbb` as the design system writes it.
    init(hexString: String) {
        var h = hexString.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        let v = UInt32(h, radix: 16) ?? 0x18181b
        self.init(hex: v)
    }

    var hexString: String {
        let c = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    /// Relative luminance, to decide whether a car colour lights the spotlight.
    var luminance: Double {
        let c = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

/// Greeting by the hour: the one line of personality, the same for every brand.
enum Greeting {
    static func text(for date: Date = Date(), name: String?) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let part = hour < 5 ? "Good night" : hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : hour < 22 ? "Good evening" : "Good night"
        if let name, !name.isEmpty { return "\(part), \(name)" }
        return part
    }
}
