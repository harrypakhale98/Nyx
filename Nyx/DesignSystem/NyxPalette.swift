import SwiftUI

// Nyx's colours, its night-vision red and its one spring: plain values, with nothing from the
// app around them, so every target draws from this one copy (the iPhone and iPad app, the widgets,
// Apple Watch and Apple Vision Pro). Views, environment keys and the sky stay in NyxTheme.swift.

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
    /// Night vision's red is lifted under Increase Contrast or by choice, so it stays above 4.5:1
    /// for protan and deutan eyes too (`NightTint`).
    var red: NightTint { highContrast || brighterRed ? .brighter : .standard }
    /// Starlight and moon-amber, gamma-encoded sRGB: the one copy the app's palette and `NightLook`
    /// (widgets, the Live Activity, Siri's cards) both draw from.
    static let starlightRGB=SIMD3<Double>(0.961,0.945,0.902), amberRGB=SIMD3<Double>(1,0.706,0.329)
    static let starlight=Color(red:starlightRGB.x,green:starlightRGB.y,blue:starlightRGB.z), amber=Color(red:amberRGB.x,green:amberRGB.y,blue:amberRGB.z)
    /// Deep indigo (#0B1026, the panels) and nebula violet (#2A1B4E, the watch's dark toolbar
    /// buttons, the glow behind Vision Pro's Moon).
    static let indigo=Color(red:0.043,green:0.063,blue:0.149), nebula=Color(red:0.165,green:0.106,blue:0.306)
    var ink: Color { nightVision ? .white : Self.starlight }
    var accent: Color { nightVision ? ink : Self.amber }
    // Filled tracks must remain distinct from the white system thumb after the red filter.
    var controlTint:Color { nightVision ? Color(white:0.22) : Color(red:0.65,green:0.35,blue:0.10) }
    var muted: Color { ink.opacity(nightVision ? 0.96 : highContrast ? 0.9 : 0.72) }
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
    /// than a graphic may be (`Scripts/contrast.py`, "Night marks").
    func markOpacity(score:Int)->Double { max(nightVision ? 0.7 : 0.5,Self.markRamp(score:score)) }
}
/// Night vision's red: everything drawn in grey, then multiplied by one red. The standard red is
/// the deepest that keeps text at 6.2:1 on black for typical colour vision; the brighter one lets a
/// little more green and blue through, so protan eyes (which barely see long-wavelength red) still
/// get 5.1:1 and deutan eyes 8.1:1, while it still reads red. Chosen under Increase Contrast or by hand.
nonisolated enum NightTint: String, Sendable, CaseIterable {
    case standard, brighter
    /// The multiplier, gamma-encoded sRGB.
    var rgb: SIMD3<Double> { self == .standard ? SIMD3(1,0.27,0.23) : SIMD3(1,0.36,0.31) }
    var color: Color { Color(red:rgb.x,green:rgb.y,blue:rgb.z) }
    /// The setting's key in the shared defaults (the widgets and Control Center read the same suite).
    static let key="brighterRed"
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
    /// A line drawing itself or words arriving: critically damped, so a pen never overshoots its star.
    static let trace=Animation.spring(response:1.4,dampingFraction:1)
    static let arrival=Animation.spring(response:1.6,dampingFraction:1)
}
