import SwiftUI

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
/// The page's measures, one copy: a content card's corner and inner padding, and a page's margin.
enum NyxMetrics {
    static let cardRadius=24.0
    static let cardPadding=20.0
    static let pagePadding=24.0
}
/// A content card: solid deep indigo with a hairline, over the real sky. Liquid Glass is kept for
/// the controls that float above content (the park pill, the river's thumb, the field controls,
/// toolbars): on a dozen stacked cards it read as flat indigo anyway, cost compositing, and is the
/// content-layer use of glass the design language reserves for controls.
struct Panel<Content: View>: View {
    @Environment(\.nyx) private var palette
    @ViewBuilder var content: Content
    var body: some View {
        let shape=RoundedRectangle(cornerRadius:NyxMetrics.cardRadius)
        // One card however many views the content holds.
        VStack(alignment:.leading,spacing:0) { content }.padding(NyxMetrics.cardPadding).frame(maxWidth:.infinity,alignment:.leading)
            .background(shape.fill(palette.panel))
            .overlay(shape.stroke(palette.line,lineWidth:0.5*palette.stroke))
    }
}
/// Letter-spaced capitals are a Latin-script convention: Japanese kana and kanji spread apart read
/// as broken words, so spaced labels set solid when the app speaks Japanese.
nonisolated enum Lettering {
    static let spaced = !(Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("ja")
}
struct Eyebrow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.nyx) private var palette
    let text: LocalizedStringKey
    var body: some View { Text(text).font(.caption.weight(.medium)).kerning(typeSize.isAccessibilitySize || !Lettering.spaced ? 0 : 2.4).textCase(typeSize.isAccessibilitySize || !Lettering.spaced ? nil : .uppercase).fixedSize(horizontal:false,vertical:true).foregroundStyle(palette.muted).accessibilityAddTraits(.isHeader) }
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
            // Keyed by the park and night, so a night chosen with an animation (the river's shared
            // spring) cross-fades its sky in rather than cutting; without one it simply changes.
            if let place=park ?? home {
                let shown=night ?? place.currentNight(at:.now)
                RealSky(park:place,night:shown,twinkle:twinkle,domes:false).id(SkyProjection.key(park:place,night:shown)).transition(.opacity)
            }
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
/// One night look for what Nyx draws outside its own windows: the widgets, the Live Activity, the
/// alarm and Siri's cards. Night vision and the brighter-red choice come from the shared suite,
/// where the app, Control Center and field mode write them; Increase Contrast comes from the view
/// that draws, since an extension has no app root to read it once. Where nothing filters the
/// surface red (a widget, the Live Activity), `ink` and `accent` are the red itself; where Nyx
/// draws a whole card (Siri), `palette` with `NightVisionFilter` reddens it as the app does.
nonisolated struct NightLook: Equatable, Sendable {
    let nightVision: Bool
    let brighterRed: Bool
    let highContrast: Bool
    /// The night-vision switch's key in the shared defaults.
    static let nightVisionKey="nightVision"
    /// Starlight and moon-amber, gamma-encoded sRGB, from `NyxPalette`.
    static let starlight=NyxPalette.starlightRGB, amber=NyxPalette.amberRGB
    init(nightVision: Bool, brighterRed: Bool=false, highContrast: Bool=false) {
        self.nightVision=nightVision; self.brighterRed=brighterRed; self.highContrast=highContrast
    }
    /// From the shared settings. `nightVision` stands in for the stored switch on a surface that
    /// carries its own (a widget's entry, a Live Activity's state).
    init(defaults: UserDefaults=SharedSettings.defaults, contrast: ColorSchemeContrast = .standard, nightVision: Bool?=nil) {
        self.init(nightVision:nightVision ?? defaults.bool(forKey:Self.nightVisionKey),brighterRed:defaults.bool(forKey:NightTint.key),highContrast:contrast == .increased)
    }
    var palette: NyxPalette { NyxPalette(nightVision:nightVision,highContrast:highContrast,brighterRed:brighterRed) }
    /// The brighter red by choice or under Increase Contrast, as in the app.
    var red: NightTint { palette.red }
    var inkRGB: SIMD3<Double> { nightVision ? red.rgb : Self.starlight }
    var accentRGB: SIMD3<Double> { nightVision ? red.rgb : Self.amber }
    var ink: Color { Color(red:inkRGB.x,green:inkRGB.y,blue:inkRGB.z) }
    var accent: Color { Color(red:accentRGB.x,green:accentRGB.y,blue:accentRGB.z) }
    /// Secondary text. Night vision's red is already dim, so it stays near full, and full under
    /// Increase Contrast; starlight is held at 90% there, as in the app.
    var mutedOpacity: Double { nightVision ? (highContrast ? 1 : 0.9) : highContrast ? 0.9 : 0.7 }
    var muted: Color { ink.opacity(mutedOpacity) }
}
/// How text contrast holds up for the commonest colour-vision deficiencies: Machado, Oliveira and
/// Fernandes (2009) full-severity matrices, applied in linear RGB, then WCAG 2 contrast.
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
