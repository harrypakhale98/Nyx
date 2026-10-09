import SwiftUI

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
    var ink: Color { nightVision ? .white : Color(red:0.961,green:0.945,blue:0.902) }
    var accent: Color { nightVision ? ink : Color(red:1,green:0.706,blue:0.329) }
    // Filled tracks must remain distinct from the white system thumb after the red filter.
    var controlTint:Color { nightVision ? Color(white:0.22) : Color(red:0.65,green:0.35,blue:0.10) }
    var muted: Color { ink.opacity(nightVision ? 0.96 : highContrast ? 0.9 : 0.72) }
    var panel: Color { nightVision ? Color(red:0.07,green:0.008,blue:0.005) : Color(red:0.043,green:0.063,blue:0.149) }
    /// Hairlines, tracks and outlines reach 3:1 against black and the panel (WCAG 1.4.11 for
    /// graphical objects): starlight at 40%, and at 70% through night vision's red, which dims it.
    var line: Color { ink.opacity(nightVision ? 0.7 : highContrast ? 0.6 : 0.4) }
}
private struct MotionOverrideKey: EnvironmentKey { static let defaultValue=false }
private struct PaletteKey: EnvironmentKey { static let defaultValue=NyxPalette(nightVision:false,highContrast:false) }
extension EnvironmentValues {
    var nyxReduceMotion: Bool { get { self[MotionOverrideKey.self] } set { self[MotionOverrideKey.self]=newValue } }
    var nyx: NyxPalette { get { self[PaletteKey.self] } set { self[PaletteKey.self]=newValue } }
}
/// The accessibility preferences Nyx adapts to beyond the basics (set by `nyxAccessibility()` in the app) each view reads itself (Reduce
/// Motion, Reduce Transparency, Increase Contrast, Dynamic Type). Read once near the root from the
/// system, newest settings behind availability, so every screen asks one question instead of four.
/// DEBUG launch flags force each one for screenshots: `-nyx-differentiate`, `-nyx-reduce-highlighting`,
/// `-nyx-crossfade`, `-nyx-reduced-resources`.
nonisolated struct NyxAccess: Equatable, Sendable {
    /// Differentiate Without Color: meaning carried by colour alone gains a shape or a word.
    var differentiate=false
    /// Reduce Highlighting Effects (iOS 26.4): glows, halos and the shooting star dim or go.
    var reduceHighlighting=false
    /// Prefer Cross-Fade Transitions (iOS 26.4): fades instead of the zoom and the month slide.
    var crossFade=false
    /// The system asks apps to use less (iOS 27): the sky holds still and draws fewer stars.
    var reducedResources=false
    /// Show Borders (Button Shapes): text-only actions gain a hairline outline (`NyxActionStyle`).
    var showBorders=false
    /// Controls that rely on a long, continuous drag (the time river) offer buttons too:
    /// "Prefers action slider alternative" (iOS 26.1) or Switch Control.
    var preferSteps=false
    /// How strong a decorative glow may be.
    var glow: Double { reduceHighlighting ? 0.35 : 1 }
}
private struct NyxAccessKey: EnvironmentKey { static let defaultValue=NyxAccess() }
extension EnvironmentValues {
    var nyxAccess: NyxAccess { get { self[NyxAccessKey.self] } set { self[NyxAccessKey.self]=newValue } }
}
enum NyxMotion {
    /// The shared spring's constants, for the few places that need the spring itself (a fling
    /// that coasts with the finger's velocity, or reading where a turn has got to).
    nonisolated static let response=0.65, dampingFraction=0.82
    nonisolated static let model=Spring(response:response,dampingRatio:dampingFraction)
    static let spring=Animation.spring(response:response,dampingFraction:dampingFraction)
}
/// A content card: solid deep indigo with a hairline, over the real sky. Liquid Glass is kept for
/// the controls that float above content (the park pill, the river's thumb, the field controls,
/// toolbars): on a dozen stacked cards it read as flat indigo anyway, cost compositing, and is the
/// content-layer use of glass the design language reserves for controls.
struct Panel<Content: View>: View {
    @Environment(\.nyx) private var palette
    @ViewBuilder var content: Content
    var body: some View {
        let shape=RoundedRectangle(cornerRadius:24)
        // One card however many views the content holds.
        VStack(alignment:.leading,spacing:0) { content }.padding(20).frame(maxWidth:.infinity,alignment:.leading)
            .background(shape.fill(palette.panel))
            .overlay(shape.stroke(palette.line,lineWidth:0.5))
    }
}
struct Eyebrow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.nyx) private var palette
    let text: LocalizedStringKey
    var body: some View { Text(text).font(.caption.weight(.medium)).kerning(typeSize.isAccessibilitySize ? 0 : 2.4).textCase(typeSize.isAccessibilitySize ? nil : .uppercase).fixedSize(horizontal:false,vertical:true).foregroundStyle(palette.muted).accessibilityAddTraits(.isHeader) }
}
struct NightBackground: View {
    @Environment(\.skyHome) private var home
    @Environment(\.nyx) private var palette
    var seed: String="nyx"
    /// The night's score, when the screen is about one night; stars twinkle harder as it rises.
    var score: Int?=nil
    /// The park and night whose real sky to show; otherwise the starting park tonight.
    var park: Park?=nil
    var night: Date?=nil
    /// Dims the sky behind long reading, where a star beside a word reads as stray punctuation.
    var veil: Double=0
    var body: some View {
        let twinkle=score.map { pow(Double($0)/100,2) } ?? 0.3
        // Increase Contrast: a calmer sky behind text, veiled by half and no more, so it is still a sky.
        let veil=palette.highContrast ? max(veil,0.5) : veil
        ZStack {
            Color.black
            // No light domes on the wallpaper: with no horizon drawn, a dome's clipped foot reads as a seam.
            if let place=park ?? home { RealSky(park:place,night:night ?? place.currentNight(at:.now),twinkle:twinkle,domes:false) }
            else { Starfield(seed:seed,twinkle:twinkle) }
            Color.black.opacity(veil)
        }.animation(.easeInOut(duration:0.6),value:palette.highContrast)
        .ignoresSafeArea().accessibilityHidden(true)
        // Nyx is dark by design and Smart Invert leaves it as it is: the system does not invert an
        // app that draws in the dark appearance (checked on iOS 27 with Smart Invert on: Tonight, a
        // park, Plan and a sheet). The opt-out stays on the sky itself, so a night sky can never turn
        // into a white page with black stars; Classic Invert remains for anyone who wants a light screen.
        .accessibilityIgnoresInvertColors()
    }
}
/// A hero object floats on its own plane: as the page scrolls, it lags slightly behind the
/// text around it, so it reads as nearer than the sky and farther than the page.
/// Off under Reduce Motion.
struct DepthParallax: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    let depth: Double
    func body(content:Content)->some View {
        if systemReduceMotion || forcedReduceMotion { content }
        else {
            content.visualEffect { [depth] view,proxy in
                view.offset(y:min(0,proxy.frame(in:.scrollView).minY)*(-depth))
            }
        }
    }
}
private struct SkyHomeKey: EnvironmentKey { static let defaultValue:Park?=nil }
extension EnvironmentValues {
    /// The starting park, whose sky stands behind screens that are not about one park.
    var skyHome: Park? { get { self[SkyHomeKey.self] } set { self[SkyHomeKey.self]=newValue } }
}
struct CalmState: View {
    @Environment(\.nyx) private var palette
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var body: some View {
        VStack(spacing:20) {
            Image(systemName:symbol).font(.system(size:36,weight:.ultraLight)).foregroundStyle(palette.accent).padding(26)
                .background(Circle().stroke(palette.line,lineWidth:0.5)).accessibilityHidden(true)
            Text(title).font(.system(.title2,design:.serif)).multilineTextAlignment(.center)
            Text(message).font(.body).foregroundStyle(palette.muted).multilineTextAlignment(.center)
        }.frame(maxWidth:.infinity).padding(.vertical,38).padding(.horizontal,24)
    }
}
#Preview("Empty") { CalmState(symbol:"sparkles",title:"A night to remember",message:"Your observations will live here.").background(.black).preferredColorScheme(.dark) }
#Preview("Error • AX5") { CalmState(symbol:"cloud",title:"The forecast is resting",message:"Moon and darkness calculations still work offline.").dynamicTypeSize(.accessibility5).background(.black).preferredColorScheme(.dark) }

struct NightVisionFilter: ViewModifier {
    let enabled:Bool
    var red:NightTint = .standard
    @ViewBuilder func body(content:Content)->some View {
        content.saturation(enabled ? 0 : 1).colorMultiply(enabled ? red.color : .white)
    }
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
/// How text contrast holds up for the commonest colour-vision deficiencies: Machado, Oliveira and
/// Fernandes (2009) full-severity matrices, applied in linear RGB, then WCAG 2 contrast. Mirrors
/// `Scripts/contrast.py`, so `Research/contrast.json` and the unit tests agree.
nonisolated enum ColorVision: String, Sendable, CaseIterable {
    case typical, protan, deutan
    private var matrix: [[Double]] {
        switch self {
        case .typical: [[1,0,0],[0,1,0],[0,0,1]]
        case .protan: [[0.152286,1.052583,-0.204868],[0.114503,0.786281,0.099216],[-0.003882,-0.048116,1.051998]]
        case .deutan: [[0.367322,0.860646,-0.227968],[0.280085,0.672501,0.047413],[-0.011820,0.042940,0.968881]]
        }
    }
    /// Relative luminance of a gamma-encoded sRGB colour as these eyes see it.
    func luminance(_ rgb: SIMD3<Double>) -> Double {
        func linear(_ v: Double) -> Double { v<=0.04045 ? v/12.92 : pow((v+0.055)/1.055,2.4) }
        let l=[linear(rgb.x),linear(rgb.y),linear(rgb.z)]
        let seen=matrix.map { row in min(1,max(0,zip(row,l).map(*).reduce(0,+))) }
        return 0.2126*seen[0]+0.7152*seen[1]+0.0722*seen[2]
    }
    /// WCAG contrast ratio between two colours, as these eyes see them.
    func contrast(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let x=luminance(a), y=luminance(b)
        return (max(x,y)+0.05)/(min(x,y)+0.05)
    }
}

private struct PresentationStyle:ViewModifier {
    @Environment(\.nyx) private var palette
    func body(content:Content)->some View {
        content.foregroundStyle(palette.ink).tint(palette.accent)
            .modifier(NightVisionFilter(enabled:palette.nightVision,red:palette.red)).preferredColorScheme(.dark)
    }
}
extension View {
    func nyxPresentation()->some View { modifier(PresentationStyle()) }
}
