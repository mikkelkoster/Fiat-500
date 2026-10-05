import SwiftUI
import UIKit

// Design tokens, ported from Torque (torque-ios: Torque/Design/Tokens.swift and
// design/design-system.md) so both apps share one design system. Keep the two in step: change a
// token there first, then copy it here. Every color, type step and spacing in the app comes from
// here; nothing is hard-coded in views.
//
// Each color carries a light and a dark value (stone greys since 2026-10-01, warmer than the zinc before, the same data hues lifted a step
// for contrast on black). Views never branch on the color scheme; the tokens do.

enum Ink {
    static let foreground = Color(light: 0x0C0A09, dark: 0xE7E5E4)   // titles, values
    static let muted = Color(light: 0x78716C, dark: 0x78716C)        // labels, captions, units
    static let secondary = Color(light: 0x57534E, dark: 0xA8A29E)    // body copy, legend
    static let subtle = Color(light: 0xA8A29E, dark: 0x78716C)       // eyebrow, secondary chart line
    static let primary = Color(light: 0x1C1917, dark: 0xFAFAF9)      // buttons, chart ink, fills
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0x0C0A09)    // text on a primary fill
    /// Hairlines. In dark, white at 10% rather than neutral 800: a solid grey matched the dark
    /// glass cards and every line inside them disappeared (Mikkel, 2026-09-30). A tint stays a step
    /// lighter than whatever it lies on, glass, card or page.
    static let border = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.10) : UIColor(hex: 0xE7E5E4) })
    /// A step brighter: the edge of something that is meant to stand out from its neighbours,
    /// like the work line's badges against the recovery line's.
    static let border2 = Color(light: 0xD6D3D1, dark: 0x44403C)
    static let track = border2        // inactive bars
    /// A ride's map before its tiles are in: the map's own average tone, so the head of the page is
    /// map-grey from the first frame rather than the page's white (Mikkel, 2026-09-29).
    static let mapGround = Color(light: 0xD6D3D1, dark: 0x292524)
    // A control that can't be used right now: one look everywhere, never opacity on the enabled one
    // (which fades the label and the fill by different amounts and read as two different states).
    static let disabledFill = Color(light: 0xE7E5E4, dark: 0x44403C)
    static let disabledText = subtle
    /// Tab group, progress track, chips, skeletons. Dark is white at 8% rather than a solid grey: the
    /// solid (#18181B) sat one shade off the card surface, so every track, chip and segmented control
    /// on a card disappeared. A tint lifts by the same step whatever it lies on (2026-09-25).
    // Neutral 200 since 2026-10-05: stone 100 was the card's own grey, so skeletons and fills vanished on cards.
    static let mutedBg = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.08) : UIColor(hex: 0xE5E5E5) })
    /// A segmented control's track: zinc 200 in light, where the muted grey left the white segment
    /// on white (Mikkel, 2026-09-29: "too light compared to dark mode"); the muted tint in dark.
    static let segmentTrack = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.08) : UIColor(hex: 0xE7E5E4) })
    /// The same, sitting on the page's ground rather than a card: neutral 900 in dark, where a
    /// tint of white on the black ground all but vanished.
    static let segmentTrackOnGround = Color(light: 0xE7E5E4, dark: 0x1C1917)
    static let selected = Color(light: 0xEFF6FF, dark: 0x1E293B)
    /// What the light greys (a neutral badge, a meter's empty steps, a bar's track, a skeleton)
    /// become on a selected row: grey on the light blue all but vanished (2026-09-28). Dark is
    /// slate-700, a step up from the selected slate-800, as white would glare.
    static let onSelected = Color(light: 0xFFFFFF, dark: 0x334155)
    /// A week's summary at the head of its card on Plan and History: in light the segmented
    /// control's grey, so the two are one (Mikkel, 2026-09-29); zinc 300 since the glass rows under
    /// it came out greyer than white and 200 lost its contrast (2026-09-30),
    /// and neutral 800 in dark, a step up from the card's 900.
    /// Sets it apart from the white day rows; the light blue it was read as a highlight rather than
    /// a heading (2026-09-26).
    // Dark: neutral 700, two steps over the neutral 900 cards, as zinc 300 sits over light's white
    // rows; at 800 it matched the dark glass and the summary vanished (Mikkel, 2026-09-30).
    // Airy, after Pluto (2026-10-05): a whisper of grey on the grey card, not a heavy band.
    static let summary = Color(light: 0xFAFAFA, dark: 0x44403C)
    /// Today inside an already tinted row (the calendar's this week): blue 100 on blue 50.
    static let today = Color(light: 0xDBEAFE, dark: 0x334155)     // tapped row, today's row, "you": a light blue, as blue means today
    static let background = Color(light: 0xFFFFFF, dark: 0x0A0A0A)   // the base everything sits on: white, under flat grey cards (2026-10-05)
    /// One step up from the base: stat tiles, list rows, cards, chips. Dark mirrors what light has
    /// always had — white panels on an off-white page — instead of everything floating on flat black.
    static let surface = Color(light: 0xFFFFFF, dark: 0x1C1917)
    /// A card: soft grey on the white page, no border, no glass (Mikkel, 2026-10-05, after Pluto).
    static let card = Color(light: 0xF5F5F5, dark: 0x171717)
    /// A secondary button: grey on the page, white on a card, so it always stands off what's under it.
    static let control = Color(light: 0xF5F5F5, dark: 0x262626)
    static let controlOnCard = Color(light: 0xFFFFFF, dark: 0x262626)

    // Every colour is a Tailwind v3 shade (Mikkel, 2026-09-24: "only use tailwind colors").
    // v3 hues — data only, never decoration.
    static let blue = Color(light: 0x2563EB, dark: 0x60A5FA)
    /// The interface's one accent: ink, the primary buttons' black (white in dark). Selection,
    /// today, the tab bar and links take it; blue is kept for power and data (Mikkel, 2026-10-05:
    /// blue and black read as two primaries).
    static let accent = primary
    /// Training zones, for workout blocks: Tailwind 400s, the same in light and dark.
    static let zoneRecovery = Color(hex: 0xA3A3A3)   // neutral 400
    static let zoneEndurance = Color(hex: 0x38BDF8)  // sky 400
    static let zoneTempo = Color(hex: 0x34D399)      // emerald 400
    static let zoneThreshold = Color(hex: 0xFBBF24)  // amber 400
    static let zoneVO2 = Color(hex: 0xFB923C)        // orange 400
    static let zoneAnaerobic = Color(hex: 0xF87171)  // red 400         // power, primary data line
    static let red = Color(light: 0xDC2626, dark: 0xF87171)          // heart rate
    static let orange = Color(light: 0xEA580C, dark: 0xFB923C)       // orange 600 / 400
    static let fatigue = primary      // recent load on the fitness chart: the ink, stone 900 / 50; its hot gap takes the badge's yellow or red (2026-10-01)
    /// Figure glyphs, one step softer than the chart lines they echo (blue 400, red 400).
    static let powerGlyph = Color(light: 0x60A5FA, dark: 0x60A5FA)
    static let heartGlyph = Color(light: 0xF87171, dark: 0xF87171)
    /// Glyph families: time and distance violet 400, speed and cadence teal 400, elevation and temperature amber 400.
    static let spanGlyph = Color(light: 0xA78BFA, dark: 0xA78BFA)
    static let paceGlyph = Color(light: 0x2DD4BF, dark: 0x2DD4BF)
    static let terrainGlyph = Color(light: 0xFBBF24, dark: 0xFBBF24)
    static let purple = Color(light: 0x7C3AED, dark: 0xA78BFA)       // speed, time glyph (violet 600/400)
    /// The top of the rider profile's scale (Excellent and up), apart from Good's green (2026-10-01):
    /// violet 100 / 950 with 700 / 300 text, as the other badge tints are built.
    static let violetBg = Color(light: 0xEDE9FE, dark: 0x2E1065)
    static let violetText = Color(light: 0x6D28D9, dark: 0xC4B5FD)
    /// The very top (Elite, World class): fuchsia, the same build (2026-10-01: violet carried four words).
    static let fuchsia = Color(light: 0xC026D3, dark: 0xE879F9)
    static let fuchsiaBg = Color(light: 0xFAE8FF, dark: 0x4A044E)
    static let fuchsiaText = Color(light: 0xA21CAF, dark: 0xF0ABFC)
    static let teal = Color(light: 0x0D9488, dark: 0x2DD4BF)         // cadence
    static let green = Color(light: 0x059669, dark: 0x34D399)
    // Status pairs keep one shape in both themes: a faint tint of the colour behind a strong mark.
    // Dark mode used to swap them (a strong disc behind a pale mark), which read as a different badge.
    static let greenBg = Color(light: 0xD1FAE5, dark: 0x022C22)
    static let greenText = Color(light: 0x065F46, dark: 0x34D399)   // 8.0:1 on its dark tint
    static let redText = Color(light: 0xB91C1C, dark: 0xF87171)     // 5.9:1 on its dark tint
    static let redBg = Color(light: 0xFEE2E2, dark: 0x450A0A)
    // Yellow days: close to fatigue that makes hard training unproductive.
    static let yellow = Color(light: 0xCA8A04, dark: 0xFACC15)
    /// Today's mark on the Progress tiles and sheets: the badge's hue at 400 in both themes, lighter
    /// than the badge's own ink (Mikkel, 2026-10-03: the 600-700 bars read heavy).
    static let chartGood = Color(light: 0x34D399, dark: 0x34D399)     // emerald 400
    static let chartCaution = Color(light: 0xFACC15, dark: 0xFACC15)  // yellow 400
    static let chartBad = heartGlyph      // red 400
    static let yellowText = Color(light: 0x854D0E, dark: 0xFDE68A)
    static let yellowBg = Color(light: 0xFEF9C3, dark: 0x422006)       // yellow 100: a badge fill that shows on the grey card too (2026-10-05)

    // Intensity tints (calendar circles, session bars): four steps of blue, never a ramp. Each is
    // the brand blue (`blue`) over the page, precomputed opaque, so both modes show the same hue
    // and a harder effort always stands out more: 25/50/72/100% in light, 50/65/76/100% in dark
    // (the dark page swallows a faint blue, so the steps start brighter there). They used to be
    // four separate blues that swapped order in dark mode.
    static let tintS = Color(light: 0xBFDBFE, dark: 0x1E3A8A)
    static let tintM = Color(light: 0x93C5FD, dark: 0x1E40AF)
    static let tintL = Color(light: 0x60A5FA, dark: 0x1D4ED8)
    static let tintXL = blue
    /// The bar under the finger. A selected bar used to be merely un-dimmed, which on a chart of
    /// blues is not a signal; this is a step brighter than the brightest tint, so it reads as lit.
    static let tintLit = Color(light: 0x3B82F6, dark: 0x93C5FD)
    /// Label on the three lighter steps (4.6:1 or better on each, both modes).
    static let tintLabelDark = Color(light: 0x172554, dark: 0xDBEAFE)
    /// Label on the strongest step: white on light, near-black on dark (5.2:1 / 5.4:1).
    static let tintLabelLight = onPrimary
}

// Geist is bundled (Torque/Resources/Fonts), cut from the variable original at 400 regular, 500
// medium and 600 semibold, and sets everything: words and figures. Figures use tabular digits so
// they line up in columns. Geist Mono was used for figures until 2026-09-23; Mikkel found the mix
// read as generated design, so the `mono` steps now resolve to Geist and only keep their names.
extension Ink {
    /// Text and marks on the blue fill (a primary button, a picked day, a calendar end).
    static let onAccent = Color.white
    /// A divider between two picked days.
    static let onAccentDivider = Color.white.opacity(0.35)
    /// Behind a panel that covers the page.
    static let scrim = Color.black.opacity(0.25)
    /// Glass's inner edge before iOS 26.
    static let glassEdge = Color.black.opacity(0.06)
    /// Keep it easy and Rest today: their fill and edge, light and dark.
    static let cautionFill = Color(light: 0xFEFCE8, dark: 0xFACC15, darkOpacity: 0.08)
    static let cautionEdge = Color(light: 0xFEF08A, dark: 0xFACC15, darkOpacity: 0.25)
    static let criticalFill = Color(light: 0xFEF2F2, dark: 0x450A0A)
    static let criticalEdge = Color(light: 0xFECACA, dark: 0x7F1D1D)
    /// A new best's confetti: the data colours.
    static let celebration: [Color] = [
        Color(hex: 0x3B82F6), Color(hex: 0x22C55E), Color(hex: 0xFBBF24), Color(hex: 0xF472B6),
        Color(hex: 0xA78BFA), Color(hex: 0x2DD4BF), Color(hex: 0xF87171),
    ]
}

enum Type {
    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name = switch weight {
        case .semibold, .bold, .heavy, .black: "Geist-SemiBold"
        case .medium: "Geist-Medium"
        default: "Geist-Regular"
        }
        return .custom(name, size: size)
    }

    /// Figures, units and metric lines: Geist with tabular digits. Two weights only.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        inter(size, weight == .regular ? .regular : .medium).monospacedDigit()
    }

    // MARK: The type scale (2026-09-24)
    // Nine styles, each with one job. Every text in the app uses one of them and nothing sits
    // between the steps. Figures take the same step as the words beside them, with tabular digits.
    //
    //   Display   64 medium    the one key number on a card
    //   Page      32 bold      a tab's name at the top of its page
    //   Title     26 semibold  a sheet's title, a ride or session name heading its page
    //   Number    28 semibold  tile and strip figures
    //   Heading   18 semibold  every card and section title
    //   Emphasis  17 medium    row names, figures in rows, the sentence under a key number
    //   Body      16           text, bullets, buttons, menus (medium for buttons)
    //   Footnote  13           sub-lines, units, chips, axis, legends
    //   Label     12 semibold  caps labels over a figure, badges, eyebrows
    static let displayNumber = mono(64, .medium)
    /// Ride now's figures, read at a glance mid-effort: between Number and Display.
    static let liveFigure = inter(38, .semibold).monospacedDigit()
    static let page = inter(28, .bold)
    static let title = inter(26, .semibold)
    static let number = inter(30, .semibold).monospacedDigit()
    static let heading = inter(18, .semibold)
    static let emphasis = inter(17, .medium)
    static let body = inter(16)
    static let bodyMedium = inter(16, .medium)
    static let footnote = inter(13)
    static let footnoteMedium = inter(13, .medium)
    static let label = inter(14, .semibold)   // 14 since 2026-10-01: in sentence case 12 read too small

    // The names screens already use, each pointing at its step, so no screen can fall between them.
    // Figures beside words take the same step with tabular digits (never a separate mono face).
    static let monoFootnote = mono(13)
    static let monoFootnoteMedium = mono(13, .medium)
    static let monoBody = mono(16)
    static let monoBodyMedium = mono(16, .medium)
    static let monoEmphasis = mono(17, .medium)
    /// Long text read top to bottom (the ride analysis headline): the Body step.
    /// Reading text in the coach's analyses: a step over body, in the ink (2026-10-01).
    static let reading = inter(17)
    static let readingLineSpacing: CGFloat = 16 * 0.4
    static let pageTitleTracking: CGFloat = -0.6
}

/// Corner radii, by what they round. Every rounded shape in the app takes one of these, so a new
/// look (sharper, softer) is a change here (2026-10-04).
enum Radius {
    // Five steps, 6 pt apart above the smallest (Mikkel, 2026-10-04: 13 sizes became 5).
    /// Marks in charts: bars, legend swatches, the setup step bar.
    static let mark: CGFloat = 3
    /// Small shapes: a checkbox, a tiny fill.
    static let small: CGFloat = 6
    /// Controls: fields, notices, segmented controls, the app mark, a note.
    static let control: CGFloat = 12
    /// Panels inside a card or sheet, and the smaller cards.
    static let panel: CGFloat = 18
    /// Cards, banners, toasts.
    static let card: CGFloat = 24
}

/// Shadows, by what casts them. Flat by default: only things that float over the page have one.
struct Elevation {
    let opacity: Double, radius: CGFloat, y: CGFloat
    var color: Color = .black

    /// A chart's scrub readout.
    static let scrub = Elevation(opacity: 0.1, radius: 7, y: 4)
    /// The floating tab bar's buttons.
    static let floating = Elevation(opacity: 0.06, radius: 12, y: 4)
    /// A card that has been answered and is leaving.
    static let notice = Elevation(opacity: 0.06, radius: 7, y: 4)
    /// An in-app notification.
    static let banner = Elevation(opacity: 0.12, radius: 16, y: 6)
    /// A drawer or panel rising from the bottom edge.
    static let drawer = Elevation(opacity: 0.10, radius: 12, y: -2)
    static let bottomSheet = Elevation(opacity: 0.12, radius: 20, y: -2)
    /// Every button: a soft lift, so a white one stands off a grey card (Mikkel, 2026-10-05).
    static let button = Elevation(opacity: 0.05, radius: 6, y: 2)
    /// Glass before iOS 26, and its blue variant.
    static let glass = Elevation(opacity: 0.08, radius: 6, y: 2)
    static let glassProminent = Elevation(opacity: 0.25, radius: 6, y: 2, color: Ink.blue)
}

extension View {
    func elevation(_ e: Elevation) -> some View { shadow(color: e.color.opacity(e.opacity), radius: e.radius, y: e.y) }
}

/// SF Symbol sizes. Icons take a step and a weight (Icon.s.weight(.semibold)), never a size inline.
enum Icon {
    // Five sizes, 2 pt apart (Mikkel, 2026-10-04: 9 to 18 in single points became 5).
    static let xs = Font.system(size: 10)
    static let s = Font.system(size: 12)
    static let m = Font.system(size: 14)
    static let l = Font.system(size: 16)
    static let xl = Font.system(size: 18)
}

enum Space {
    /// The page's side margin (Mikkel, 2026-09-30; was 24). Kept at 20 when the cards spread out.
    static let gutter: CGFloat = 20
    /// Sideways, a chart alone on the screen: the safe area already keeps it off the Dynamic
    /// Island, so the page gutter on top of that only cost width.
    static let sideGutter: CGFloat = 12
    /// Between one card and the next in a stack: always this, whatever the cards hold. 28 since
    /// 2026-10-05 (airier, after Pluto; 20 before).
    static let cardGap: CGFloat = 28
    /// Inside every card, from its edge to its content: one value on every screen. 20 since
    /// 2026-10-05 (was 16).
    static let cardPadding: CGFloat = 20
    /// From a tab's title to its first card: the same on Progress, Plan and History, so switching
    /// tabs doesn't move the first card (2026-09-24).
    static let firstCard: CGFloat = 24
    /// Between one field of a form and the next: plan setup, events, time off, Custom workout.
    /// 32 since 2026-09-23 (24 read cramped on the device).
    /// One value, so changing it changes every form.
    static let formField: CGFloat = 32
    /// A Toast's distance above the bottom safe area, on every screen and sheet. The safe area
    /// already clears the floating tab bar; this is only the breath between the two.
    static let toastBottom: CGFloat = 12
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// A color that follows the interface style.
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { trait in
            UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// The same, with the dark shade laid over the page at an opacity (Tailwind's yellow-400/10):
    /// a tint rather than a deep shade, which reads brown for yellow.
    init(light: UInt32, dark: UInt32, darkOpacity: Double) {
        self.init(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark).withAlphaComponent(darkOpacity) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension View {
    /// Tabular numerals on every numeral, per the design system.
    func tabular() -> some View { monospacedDigit() }

    /// Eyebrow: 600 11px, .18em tracking, uppercase, subtle.
    func eyebrowStyle() -> some View {
        // Sentence case since 2026-10-01: caps read as a dashboard, not a person.
        font(Type.label).foregroundStyle(Ink.muted)
    }

    /// Section title: 600 16px, slight negative tracking.
    func sectionTitleStyle() -> some View {
        font(Type.emphasis).tracking(-14 * 0.01).foregroundStyle(Ink.foreground)
    }

    /// Caps label for key-number strips: 600 10px, .14em, uppercase, muted.
    func capsLabelStyle() -> some View {
        font(Type.label).foregroundStyle(Ink.muted)
    }

    func hairline(_ edges: Edge.Set = .top) -> some View {
        overlay(alignment: edges.contains(.top) && !edges.contains(.bottom) ? .top : .bottom) {
            Rectangle().fill(Ink.border).frame(height: 1)
        }
    }

    /// Standard sheet chrome: the app ground, the system grabber, and the given heights. Every
    /// sheet uses it, or KeyboardSheet where the sheet rides the keyboard (2026-09-30).
    /// Two thirds of the screen by default, expanding to full height when there is more to read.
    func torqueSheet(_ detents: Set<PresentationDetent> = [.fraction(0.66), .large]) -> some View {
        background(Ink.background)
            // The sheet's own surface too, or the strip under the content (the home indicator area)
            // shows the system sheet colour.
            .presentationBackground(Ink.background)
            .presentationDetents(detents)
            .presentationDragIndicator(.visible)
    }
}
