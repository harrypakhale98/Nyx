import SwiftUI

struct NyxPalette {
    let nightVision: Bool
    let highContrast: Bool
    var ink: Color { nightVision ? .white : Color(red:0.961,green:0.945,blue:0.902) }
    var accent: Color { nightVision ? ink : Color(red:1,green:0.706,blue:0.329) }
    // Filled tracks must remain distinct from the white system thumb after the red filter.
    var controlTint:Color { nightVision ? Color(white:0.22) : Color(red:0.65,green:0.35,blue:0.10) }
    var muted: Color { ink.opacity(nightVision ? 0.96 : highContrast ? 0.9 : 0.72) }
    var panel: Color { nightVision ? Color(red:0.07,green:0.008,blue:0.005) : Color(red:0.043,green:0.063,blue:0.149) }
    var line: Color { ink.opacity(highContrast ? 0.6 : 0.22) }
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
    /// How strong a decorative glow may be.
    var glow: Double { reduceHighlighting ? 0.35 : 1 }
}
private struct NyxAccessKey: EnvironmentKey { static let defaultValue=NyxAccess() }
extension EnvironmentValues {
    var nyxAccess: NyxAccess { get { self[NyxAccessKey.self] } set { self[NyxAccessKey.self]=newValue } }
}
enum NyxMotion {
    static let spring=Animation.spring(response:0.65,dampingFraction:0.82)
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
        ZStack {
            Color.black
            if let place=park ?? home { RealSky(park:place,night:night ?? place.currentNight(at:.now),twinkle:twinkle) }
            else { Starfield(seed:seed,twinkle:twinkle) }
            if veil>0 { Color.black.opacity(veil) }
        }.ignoresSafeArea().accessibilityHidden(true)
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
    @ViewBuilder func body(content:Content)->some View {
        content.saturation(enabled ? 0 : 1).colorMultiply(enabled ? Color(red:1,green:0.27,blue:0.23) : .white)
    }
}

private struct PresentationStyle:ViewModifier {
    @Environment(\.nyx) private var palette
    func body(content:Content)->some View {
        content.foregroundStyle(palette.ink).tint(palette.accent)
            .modifier(NightVisionFilter(enabled:palette.nightVision)).preferredColorScheme(.dark)
    }
}
extension View {
    func nyxPresentation()->some View { modifier(PresentationStyle()) }
}
