import SwiftUI
import UIKit

// Design tokens, ported from Torque (torque-ios: Torque/Design/Tokens.swift and
// design/design-system.md) so both apps share one design system. Keep the two in step: change a
// token there first, then copy it here. Every color, type step and spacing in the app comes from
// here; nothing is hard-coded in views.
//
// Each color carries a light and a dark value: Tailwind neutral greys (since 2026-10-05; stone read
// reddish brown), the data hues lifted a step for contrast on black. Views never branch on the
// color scheme; the tokens do.

enum Ink {
    // Neutral greys throughout (Mikkel, 2026-10-05): the stone greys read reddish brown, in dark most.
    static let foreground = Color(light: 0x0A0A0A, dark: 0xE5E5E5)   // titles, values
    static let muted = Color(light: 0x737373, dark: 0x737373)        // labels, captions, units
    static let secondary = Color(light: 0x525252, dark: 0xA3A3A3)    // body copy, legend
    static let subtle = Color(light: 0xA3A3A3, dark: 0x737373)       // eyebrow, secondary chart line
    static let primary = Color(light: 0x171717, dark: 0xFAFAFA)      // buttons, chart ink, fills
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0x0A0A0A)    // text on a primary fill
    /// A switch's track when on: ink in light; in dark a light grey. White ink left the white knob
    /// on a white track, and neutral 500 read too close to the off track (Mikkel, 2026-10-05).
    /// Neutral 900 / 300.
    static let switchOn = Color(light: 0x171717, dark: 0xD4D4D4)
    /// The word inside a switch (On / Off) and the off track: on reads on the on-track, off on a soft
    /// grey (Mikkel, 2026-10-05, after a switch with its state written inside).
    static let switchOnText = Color(light: 0xFFFFFF, dark: 0x171717)
    static let switchOff = Color(light: 0xE5E5E5, dark: 0x404040)
    static let switchOffText = Color(light: 0x737373, dark: 0xA3A3A3)
    /// A switch's knob: white in both modes, as the system's.
    static let knob = Color(light: 0xFFFFFF, dark: 0xFFFFFF)
    /// A picked chip (a day in a day picker): a soft fill under ink words, neutral 200 / 600; an
    /// unpicked one is the control's white with its edge (Mikkel, 2026-10-05: the black day bars
    /// made Plan settings heavy).
    static let chipOn = Color(light: 0xE5E5E5, dark: 0x525252)
    /// Hairlines: neutral 200 / 800, solid. A see-through white drew crossings twice as dark (a stat
    /// grid's dividers, Mikkel 2026-10-05); the flat cards it once vanished on are gone.
    static let border = Color(light: 0xE5E5E5, dark: 0x262626)
    /// A step brighter: the edge of something that is meant to stand out from its neighbours,
    /// like the work line's badges against the recovery line's.
    static let border2 = Color(light: 0xD4D4D4, dark: 0x404040)
    static let track = border2        // inactive bars
    /// A ride's map before its tiles are in: the map's own average tone, so the head of the page is
    /// map-grey from the first frame rather than the page's white (Mikkel, 2026-09-29).
    static let mapGround = Color(light: 0xD4D4D4, dark: 0x262626)
    // A control that can't be used right now: one look everywhere, never opacity on the enabled one
    // (which fades the label and the fill by different amounts and read as two different states).
    // Disabled, a step stronger (Mikkel, 2026-10-05: it all but vanished on white): neutral 200
    // fill under neutral 500 words; dark neutral 800 under 400.
    static let disabledFill = Color(light: 0xE5E5E5, dark: 0x262626)
    static let disabledText = Color(light: 0x737373, dark: 0xA3A3A3)
    /// Tab group, progress track, chips, skeletons. Dark is white at 8% rather than a solid grey: the
    /// solid (#18181B) sat one shade off the card surface, so every track, chip and segmented control
    /// on a card disappeared. A tint lifts by the same step whatever it lies on (2026-09-25).
    // Neutral 200 since 2026-10-05: stone 100 was the card's own grey, so skeletons and fills vanished on cards.
    static let mutedBg = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.08) : UIColor(hex: 0xE5E5E5) })
    /// A segmented control's track: neutral 200 in light; the muted tint in dark.
    static let segmentTrack = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.08) : UIColor(hex: 0xE5E5E5) })
    /// The same, sitting on the page's ground rather than a card: neutral 900 in dark, where a
    /// tint of white on the black ground all but vanished.
    static let segmentTrackOnGround = Color(light: 0xE5E5E5, dark: 0x171717)
    // Pressed and selected: neutral 200 / 800, a step past the card, no colour (Mikkel,
    // 2026-10-05: light blue belonged to the old look).
    static let selected = Color(light: 0xE5E5E5, dark: 0x262626)
    /// What the light greys (a neutral badge, a meter's empty steps, a bar's track, a skeleton)
    /// become on a selected row: grey on grey vanishes, so white; dark is neutral 700, a step up
    /// from the selected neutral 800, as white would glare.
    static let onSelected = Color(light: 0xFFFFFF, dark: 0x404040)
    /// A week's summary at the head of its card on Plan and History: a whisper off the card, after
    /// Pluto (2026-10-05). One step either way: neutral 50 on light's 100 card, 800 on dark's 900
    /// (dark was 700, two steps, a heavy band next to light's whisper).
    static let summary = Color(light: 0xFAFAFA, dark: 0x262626)
    /// Today's mark inside a row.
    static let today = Color(light: 0xE5E5E5, dark: 0x262626)     // today's mark: neutral 200 / 800, no blue (2026-10-05)
    static let background = Color(light: 0xFFFFFF, dark: 0x0A0A0A)   // the base everything sits on: white, under flat grey cards (2026-10-05)
    /// One step up from the base: stat tiles, list rows, cards, chips. Dark mirrors what light has
    /// always had — white panels on an off-white page — instead of everything floating on flat black.
    static let surface = Color(light: 0xFFFFFF, dark: 0x262626)   // neutral 800 in dark: one step over the card, so it shows on it (was stone 900, which read brown and vanished, 2026-10-05)
    /// The ring that cuts a chart's dot out of its line: the card's ground in dark, white in light.
    static let dotRing = Color(light: 0xFFFFFF, dark: 0x171717)
    /// A card: soft grey on the white page, no border, no glass (Mikkel, 2026-10-05, after Pluto).
    static let card = Color(light: 0xF5F5F5, dark: 0x171717)
    /// A secondary button: grey on the page, white on a card, so it always stands off what's under it.
    static let control = Color(light: 0xF5F5F5, dark: 0x262626)
    static let controlOnCard = Color(light: 0xFFFFFF, dark: 0x262626)
    /// The secondary button's edge: white on the white page needs one, and on a grey card it
    /// keeps the two grounds' buttons the same (Mikkel, 2026-10-05). Neutral 200 / 700.
    static let controlBorder = Color(light: 0xE5E5E5, dark: 0x404040)
    /// A text or number field: white on the grey card in light; neutral 800 in dark. It was the
    /// surface, stone 900, which read brown and sunk on the neutral card (Mikkel, 2026-10-05).
    static let field = Color(light: 0xFFFFFF, dark: 0x262626)

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
    static let zoneThreshold = Color(hex: 0xFACC15)  // yellow 400: the Progress tiles' yellow, brighter than amber (2026-10-05)
    static let zoneVO2 = Color(hex: 0xFB923C)        // orange 400
    static let zoneAnaerobic = Color(hex: 0xF87171)  // red 400
    // A tapped block: its own colour two Tailwind steps deeper, 400 to 600 (one step read too faint) (Mikkel, 2026-10-05:
    // a blue Z2 bar turning black on tap read as a different thing).
    static let zoneRecoveryLit = Color(hex: 0x525252)   // neutral 600
    static let zoneEnduranceLit = Color(hex: 0x0284C7)  // sky 600
    static let zoneTempoLit = Color(hex: 0x059669)      // emerald 600
    static let zoneThresholdLit = Color(hex: 0xCA8A04)  // yellow 600
    static let zoneVO2Lit = Color(hex: 0xEA580C)        // orange 600
    static let zoneAnaerobicLit = Color(hex: 0xDC2626)  // red 600
    static let trackLit = Color(light: 0xA3A3A3, dark: 0x525252) // a tapped warm-up or rest: neutral 400 / 600, a step past track
    /// A zone's badge in its bar's hue (Mikkel, 2026-10-05): the 100 under 800 words, as every
    /// badge; dark is the 950 under 300. Z1 grey, Z2 sky, Z3 emerald, Z4 yellow, Z5 orange, Z6+ red.
    static let zoneBadge: [(fill: Color, ink: Color)] = [
        (Color(light: 0xE5E5E5, dark: 0x262626), Color(light: 0x404040, dark: 0xD4D4D4)),
        (Color(light: 0xE0F2FE, dark: 0x082F49), Color(light: 0x075985, dark: 0x7DD3FC)),
        (Color(light: 0xD1FAE5, dark: 0x022C22), Color(light: 0x065F46, dark: 0x6EE7B7)),
        (Color(light: 0xFEF9C3, dark: 0x422006), Color(light: 0x854D0E, dark: 0xFDE047)),
        (Color(light: 0xFFEDD5, dark: 0x431407), Color(light: 0x9A3412, dark: 0xFDBA74)),
        (Color(light: 0xFEE2E2, dark: 0x450A0A), Color(light: 0x991B1B, dark: 0xFCA5A5)),
    ]
    static let red = Color(light: 0xDC2626, dark: 0xF87171)          // heart rate
    static let orange = Color(light: 0xEA580C, dark: 0xFB923C)       // orange 600 / 400
    static let fatigue = primary      // recent load on the fitness chart: the ink, neutral 900 / 50; its hot gap takes the badge's yellow or red (2026-10-01)
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
    static let tintLabelDark = Color(light: 0x171717, dark: 0xE5E5E5) // ink on a light circle, no blue (2026-10-05)
    /// Label on the strongest step: white on light, near-black on dark (5.2:1 / 5.4:1).
    static let tintLabelLight = onPrimary
}

// Geist is bundled (Torque/Resources/Fonts), cut from the variable original at 400 regular, 500
// medium and 600 semibold, and sets everything: words and figures. Figures use tabular digits so
// they line up in columns. Geist Mono was used for figures until 2026-09-23; Mikkel found the mix
// read as generated design, so the `mono` steps now resolve to Geist and only keep their names.
extension Ink {
    /// Text and marks on a coloured fill: a red swipe box, Strava's orange.
    static let onAccent = Color.white
    /// A divider between two picked days, on the ink fill: the fill's own text colour, faded. It was
    /// white, which vanished on dark's white fill.
    static let onAccentDivider = onPrimary.opacity(0.35)
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
    //   Page      28 bold      a tab's name at the top of its page
    //   Title     26 semibold  a sheet's title, a ride or session name heading its page
    //   Number    30 semibold  tile and strip figures
    //   Readout   22 semibold  the figure in a scrub box
    //   Heading   18 semibold  every card and section title
    //   Emphasis  17 medium    row names, figures in rows, the sentence under a key number
    //   Body      16           text, bullets, buttons, menus (medium for buttons)
    //   Footnote  13           sub-lines, units, chips, axis, legends
    //   Label     14 semibold  labels over a figure, badges, eyebrows
    static let displayNumber = mono(64, .medium)
    /// Ride now's figures, read at a glance mid-effort: between Number and Display.
    static let liveFigure = inter(38, .semibold).monospacedDigit()
    static let page = inter(28, .bold)
    static let title = inter(26, .semibold)
    static let number = inter(30, .semibold).monospacedDigit()
    static let heading = inter(18, .semibold)
    /// The figure in a scrub box: a step over Heading, so it reads at a glance under the finger
    /// (Mikkel, 2026-10-05).
    static let readout = inter(22, .semibold)
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
    /// Reading text in the coach's analyses: a step over Body, in the ink (2026-10-01).
    static let reading = inter(17)
    static let readingLineSpacing: CGFloat = 16 * 0.4
    static let pageTitleTracking: CGFloat = -0.6
}

/// How thick a chart's line is drawn, one place for every line chart (Mikkel, 2026-10-05: thick
/// lines were hard to read; 3 pt went to 2, tiles 2 to 1.5).
enum Stroke {
    /// A chart's line on a card or sheet.
    static let line: CGFloat = 2
    /// A line in a small tile.
    static let lineCompact: CGFloat = 1.5
    /// A ride's own second-by-second streams (power, heart rate, cadence…): dense and jagged, so
    /// thinner than a trend's line, which read thick there (Mikkel, 2026-10-05).
    static let stream: CGFloat = 1.25
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
    /// A switch's knob, lifted off its track.
    static let knob = Elevation(opacity: 0.15, radius: 2, y: 1)
    /// Glass before iOS 26, and its prominent (ink) variant: a black shadow, not the blue of the
    /// old blue buttons.
    static let glass = Elevation(opacity: 0.08, radius: 6, y: 2)
    static let glassProminent = Elevation(opacity: 0.15, radius: 6, y: 2)
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
    /// Between one card and the next in a stack: always this, whatever the cards hold. 20 (28 was
    /// tried on 2026-10-05 and read too far apart).
    static let cardGap: CGFloat = 20
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
