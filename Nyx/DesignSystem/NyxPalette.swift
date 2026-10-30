import SwiftUI

// Nyx's colours, its night-vision red, its lettering rule, the sRGB curve and its one spring: plain
// values, with nothing from the app around them, so every target draws from this one copy (the
// iPhone and iPad app, the widgets, Apple Watch and Apple Vision Pro). Views, environment keys and
// the sky stay in NyxTheme.swift; night vision outside the app's windows is in NightLook.swift.

nonisolated struct NyxPalette: Equatable, Sendable {
    let nightVision: Bool
    let highContrast: Bool
    /// The person chose the brighter red (Settings › In the dark, or field mode's options).
    var brighterRed=false
    /// Bold Text is on (`legibilityWeight == .bold`). Defaults to off so the widget, watch and
    /// preview call sites keep building unchanged.
    var boldText=false
    /// How heavy drawn outlines and hairlines are: the honesty marks' rings, the week strip's and
    /// the calendar's outlines, the river's and the sky arc's hairlines, the gauge's track and ticks.
    /// 1.6× under Increase Contrast or Bold Text, as text grows heavier; 1 otherwise, so the default
    /// drawing is unchanged.
    var stroke: Double { highContrast || boldText ? 1.6 : 1.0 }
    /// Night vision's red is lifted further under Increase Contrast or by choice (`NightTint`).
    var red: NightTint { highContrast || brighterRed ? .brighter : .standard }
    /// Starlight and moon-amber, gamma-encoded sRGB: the one copy the app's palette and `NightLook`
    /// (widgets, the Live Activity, Siri's cards) both draw from.
    static let starlightRGB=SIMD3<Double>(0.961,0.945,0.902), amberRGB=SIMD3<Double>(1,0.706,0.329)
    static let starlight=Color(red:starlightRGB.x,green:starlightRGB.y,blue:starlightRGB.z), amber=Color(red:amberRGB.x,green:amberRGB.y,blue:amberRGB.z)
    /// Deep indigo (#0B1026, the panels) and nebula violet (#2A1B4E, the watch's dark toolbar
    /// buttons, the glow behind Vision Pro's Moon).
    static let indigo=Color(red:0.043,green:0.063,blue:0.149), nebula=Color(red:0.165,green:0.106,blue:0.306)
    /// The warning glyph's warm red (`caution`): 8:1 on the panel, apart from amber, so amber keeps
    /// one job (the score and light) and a closure never reads as a link.
    static let cautionColor=Color(red:1,green:0.48,blue:0.38)
    /// Each planet's own tint for `PlanetGlyph`, as it looks in a small telescope.
    static let venus=Color(red:0.98,green:0.95,blue:0.86), jupiter=Color(red:0.93,green:0.84,blue:0.7), saturn=Color(red:0.92,green:0.82,blue:0.58)
    static let mars=Color(red:0.9,green:0.47,blue:0.32), mercury=Color(red:0.76,green:0.74,blue:0.71), jupiterBelt=Color(red:0.62,green:0.44,blue:0.32)
    var ink: Color { nightVision ? .white : Self.starlight }
    var accent: Color { nightVision ? ink : Self.amber }
    /// A switch that is on, a confirm button: nebula violet lifted until it reads as "on" against the
    /// off track and stays distinct from the white thumb (about 4:1), so amber keeps to the score and
    /// light. Through night vision a dark grey, which the red filter keeps apart from the thumb.
    var controlTint:Color { nightVision ? Color(white:0.22) : Color(red:0.42,green:0.36,blue:0.66) }
    /// The iPad sidebar's selected row: "now" is amber, as the selected tab is on iPhone, deepened so
    /// its starlight label keeps its contrast on the fill. Through night vision a dark grey.
    var selectionTint:Color { nightVision ? Color(white:0.22) : Color(red:0.65,green:0.35,blue:0.10) }
    /// Secondary text's opacity over its ink, the one rule for every surface (the app, `NightLook`'s
    /// widgets, Live Activity and Siri cards): starlight at 72%, 90% under Increase Contrast; night
    /// vision's red, already dim, at 96% (4.5:1 for protan eyes too, `Scripts/contrast.py`) and in full
    /// under Increase Contrast.
    static func mutedOpacity(nightVision: Bool, highContrast: Bool) -> Double {
        nightVision ? (highContrast ? 1 : 0.96) : highContrast ? 0.9 : 0.72
    }
    /// A quieter level than muted, for starlight only (a footnote under a line, a passed moment): in
    /// red, or under Increase Contrast, it is muted, since nothing dimmer would still read.
    static func faintOpacity(nightVision: Bool, highContrast: Bool) -> Double {
        nightVision || highContrast ? mutedOpacity(nightVision: nightVision, highContrast: highContrast) : 0.62
    }
    var muted: Color { ink.opacity(Self.mutedOpacity(nightVision: nightVision, highContrast: highContrast)) }
    var panel: Color { nightVision ? Color(red:0.07,green:0.008,blue:0.005) : Self.indigo }
    /// Hairlines, tracks and outlines reach 3:1 against black and the panel (WCAG 1.4.11 for
    /// graphical objects): starlight at 40%, and at 70% through night vision's red, which dims it.
    var line: Color { ink.opacity(nightVision ? 0.7 : highContrast ? 0.6 : 0.4) }
    /// Siri's cards: black at the top to the panel, under every snippet Nyx draws.
    var snippetGradient: Gradient { Gradient(colors:[.black,panel]) }
    var snippetBackground: LinearGradient { LinearGradient(gradient:snippetGradient,startPoint:.top,endPoint:.bottom) }
    /// A night's filled mark grows fuller with its score (45% at 0 to 95% at 100); its size says the score too.
    static func markRamp(score:Int)->Double { 0.45+Double(min(100,max(0,score)))/200 }
    /// The ramp held at 3:1 against black and the panel (WCAG 1.4.11), as `line` is: amber from 50%, and
    /// from 70% through night vision's red, which dims it. A poor night's mark stays smaller, never fainter
    /// than a graphic may be.
    func markOpacity(score:Int)->Double { max(nightVision ? 0.7 : 0.5,Self.markRamp(score:score)) }
}
/// Night vision's red: everything drawn in grey, then multiplied by one red. Protan eyes barely see
/// long-wavelength red, so the red carries enough green for them to read it, and blue in step so it
/// stays red rather than orange (hue about 8°): the standard red keeps every word at 4.5:1 or better
/// for typical, protan and deutan eyes (6.9, 5.1 and 8.0:1 on black). The brighter one (6.1:1 for
/// protan eyes) is chosen under Increase Contrast or by hand.
nonisolated enum NightTint: String, Sendable, CaseIterable {
    case standard, brighter
    /// The multiplier, gamma-encoded sRGB (`Scripts/contrast.py` measures both). The default must pass
    /// for everyone: Vision Pro has no setting of its own.
    var rgb: SIMD3<Double> { self == .standard ? SIMD3(1,0.36,0.25) : SIMD3(1,0.45,0.32) }
    var color: Color { Color(red:rgb.x,green:rgb.y,blue:rgb.z) }
    /// What `NightVisionFilter` does to a colour (`saturation(0)` then `colorMultiply(color)`): its
    /// Rec. 709 luminance times the multiplier. For the places no view filter reaches, such as
    /// Vision Pro's immersive sky, so they leak exactly as little green and blue as the iPhone.
    func filtered(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let luminance = 0.2126*rgb.x + 0.7152*rgb.y + 0.0722*rgb.z
        return luminance*self.rgb
    }
    /// The setting's key in the shared defaults (the widgets and Control Center read the same suite).
    static let key="brighterRed"
}
/// Night vision on a view: everything drawn in grey, then multiplied by one red (`NightTint`). The
/// one filter on every device, the iPhone's windows and Siri's cards, and Vision Pro's window and sheets.
struct NightVisionFilter: ViewModifier {
    let enabled:Bool
    var red:NightTint = .standard
    @ViewBuilder func body(content:Content)->some View {
        content.saturation(enabled ? 0 : 1).colorMultiply(enabled ? red.color : .white)
    }
}
/// Letter-spaced capitals are a Latin-script convention: Japanese kana and kanji spread apart read
/// as broken words, so spaced labels set solid when Nyx speaks Japanese.
nonisolated enum Lettering {
    static let spaced = !(Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("ja")
}
/// The Darkness Score's numeral, set one way on every surface (the dial, the river, widgets,
/// complications, the watch and Vision Pro): New York at one weight, tracked by a share of its size
/// so a 40-point widget and the dial read as one face, with tabular digits so a count-up or a column
/// of scores never shifts sideways. Each surface keeps its own size.
nonisolated enum ScoreNumeral {
    /// Light, the iPhone dial's weight. Bold Text draws the next weight up on its own.
    static let weight=Font.Weight.light
    /// 2% tight, the iPhone dial's proportion.
    static let tracking = -0.02
    /// A text style's size at the default Dynamic Type size (iOS's; the watch's differ by a point
    /// or two, a few hundredths of a point of tracking), which `ScaledMetric` then scales.
    static func nominalSize(_ style:Font.TextStyle)->CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline,.body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }
}
extension View {
    /// The score's numeral at a fixed size (the dials, the widgets' heroes), in the surface's accent:
    /// the palette's amber, or ink where night vision or a tinted face turns the accent to ink.
    func scoreNumeral(size:CGFloat,accent:Color)->some View {
        font(.system(size:size,weight:ScoreNumeral.weight,design:.serif)).tracking(size*ScoreNumeral.tracking).monospacedDigit().foregroundStyle(accent)
    }
    /// The score's numeral at a text style, so it grows with Dynamic Type and its tracking with it.
    func scoreNumeral(_ style:Font.TextStyle,accent:Color)->some View { modifier(ScoreNumeralStyle(style:style,accent:accent)) }
    /// The band word beside or under a score ("Excellent"): serif, in ink, a step quieter than the
    /// numeral, as on the iPhone dial. What the score rests on ("Early look") goes on a line of its own.
    func bandWord(_ style:Font.TextStyle,ink:Color)->some View { font(.system(style,design:.serif)).foregroundStyle(ink) }
}
private struct ScoreNumeralStyle: ViewModifier {
    let style:Font.TextStyle
    let accent:Color
    @ScaledMetric private var size:CGFloat
    init(style:Font.TextStyle,accent:Color) {
        self.style=style; self.accent=accent
        _size=ScaledMetric(wrappedValue:ScoreNumeral.nominalSize(style),relativeTo:style)
    }
    func body(content:Content)->some View {
        content.font(.system(style,design:.serif).weight(ScoreNumeral.weight)).tracking(size*ScoreNumeral.tracking).monospacedDigit().foregroundStyle(accent)
    }
}
/// The sRGB transfer function, one copy: gamma-encoded display values to linear light and back.
nonisolated enum SRGB {
    static func linear(_ encoded: Double) -> Double { encoded <= 0.04045 ? encoded/12.92 : pow((encoded+0.055)/1.055, 2.4) }
    /// Clamped to 0…1 first.
    static func encoded(_ linear: Double) -> Double {
        let c = min(1, max(0, linear))
        return c <= 0.0031308 ? 12.92*c : 1.055*pow(c, 1/2.4)-0.055
    }
}
enum NyxMotion {
    /// The shared spring's constants, for the few places that need the spring itself (a fling
    /// that coasts with the finger's velocity, or reading where a turn has got to).
    nonisolated static let response=0.65, dampingFraction=0.82
    nonisolated static let model=Spring(response:response,dampingRatio:dampingFraction)
    static let spring=Animation.spring(response:response,dampingFraction:dampingFraction)
    /// Under a finger: the same kind of spring, quick enough that what a scrub moves (the river's
    /// loupe, its hairline and Moon) stays under the finger rather than trailing it. Released, the
    /// shared spring takes over.
    nonisolated static let trackingResponse=0.15, trackingDamping=0.86
    static let tracking=Animation.spring(response:trackingResponse,dampingFraction:trackingDamping)
    /// A short settle, for an answer already seen (the dial's 0.35 s landing, its band word).
    nonisolated static let settleDuration=0.35
    static let settle=Animation.spring(duration:settleDuration)
    /// The cold launch: the app settling in over the launch screen's stars, slower and calmer than a change on a screen.
    static let launch=Animation.spring(response:0.9,dampingFraction:0.9)
    /// When the launch spring is about nine tenths of the way in (0.55 s): the moment the held
    /// score is let go, so its count overlaps the arrival instead of waiting out the spring's tail.
    nonisolated static let launchSettle=0.55
    /// A line drawing itself or words arriving: critically damped, so a pen never overshoots its star.
    static let trace=Animation.spring(response:1.4,dampingFraction:1)
    static let arrival=Animation.spring(response:1.6,dampingFraction:1)
    /// Reduce Motion's change: nothing travels or scales, the new state cross-fades in. Apple's
    /// guidance is to replace motion with a dissolve, not to remove it, so a page never just cuts.
    static let fade=Animation.easeInOut(duration:0.25)
    /// A layer of the sky leaving or returning (Increase Contrast's faint stars, the high-contrast
    /// palette): slower than a change on the page, and only ever opacity, so Reduce Motion keeps it.
    static let dissolve=Animation.easeInOut(duration:0.6)
    /// The shared spring, or the cross-fade under Reduce Motion. Only for changes whose Reduce
    /// Motion form is already opacity (an `.opacity` transition, a numeral's `.contentTransition`).
    static func spring(reduced:Bool)->Animation { reduced ? fade : spring }
}
