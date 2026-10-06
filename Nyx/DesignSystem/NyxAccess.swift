import SwiftUI
import Accessibility

extension View {
    /// Reads the system's accessibility preferences into `\.nyxAccess`. Applied at the root and on
    /// screens presented outside SwiftUI's hierarchy (field mode, a park opened from a reminder).
    func nyxAccessibility()->some View { modifier(NyxAccessReader()) }
}
private struct NyxAccessReader: ViewModifier {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    @ViewBuilder func body(content:Content)->some View {
        let base=NyxAccess(differentiate:differentiate || DebugScenario.isEnabled("differentiate"),
                           reduceHighlighting:DebugScenario.isEnabled("reduce-highlighting"),
                           crossFade:DebugScenario.isEnabled("crossfade"),
                           reducedResources:DebugScenario.isEnabled("reduced-resources"))
        if #available(iOS 26.4, *) { content.modifier(NyxAccessReader264(base:base)) }
        else { content.environment(\.nyxAccess,base) }
    }
}
@available(iOS 26.4, *)
private struct NyxAccessReader264: ViewModifier {
    @Environment(\.accessibilityReduceHighlightingEffects) private var reduceHighlighting
    @Environment(\.accessibilityPrefersCrossFadeTransitions) private var crossFade
    let base: NyxAccess
    @ViewBuilder func body(content:Content)->some View {
        let access=NyxAccess(differentiate:base.differentiate,reduceHighlighting:base.reduceHighlighting || reduceHighlighting,
                             crossFade:base.crossFade || crossFade,reducedResources:base.reducedResources)
        if #available(iOS 27.0, *) { content.modifier(NyxAccessReader27(base:access)) }
        else { content.environment(\.nyxAccess,access) }
    }
}
@available(iOS 27.0, *)
private struct NyxAccessReader27: ViewModifier {
    @Environment(\.systemPrefersReducedResourceUsage) private var reduced
    let base: NyxAccess
    func body(content:Content)->some View {
        var access=base
        access.reducedResources=base.reducedResources || reduced
        return content.environment(\.nyxAccess,access)
    }
}

// MARK: Navigation

/// A park opens with the zoom from its row, or a cross-fade when the person prefers one
/// (the system's own `.crossFade` on iOS 27; a plain push before it, which the system already
/// softens under Reduce Motion).
struct ParkTransition: ViewModifier {
    @Environment(\.nyxAccess) private var access
    let sourceID: String
    let namespace: Namespace.ID
    func body(content:Content)->some View {
        if !access.crossFade { content.navigationTransition(.zoom(sourceID:sourceID,in:namespace)) }
        else if #available(iOS 27.0, *) { content.navigationTransition(.crossFade) }
        else { content.navigationTransition(.automatic) }
    }
}

// MARK: Speech

/// How VoiceOver should say Nyx's few unusual words. On iOS 27 each is annotated with an SSML
/// fragment (`accessibilitySpeechSSML`); the text itself, and Braille, are unchanged. Before
/// iOS 27 the plain words are spoken as they are.
nonisolated enum NyxSpeech {
    /// Word → SSML fragment. "Bortle" is said BOR-tl, not "bottle"; the Milky Way's centre is
    /// "Sagittarius A star", as astronomers say it.
    static let pronunciations:[(word:String,ssml:String)]=[
        ("Bortle","<phoneme alphabet=\"ipa\" ph=\"ˈbɔɹtəl\">Bortle</phoneme>"),
        ("Sagittarius A*","Sagittarius A <sub alias=\"star\">*</sub>"),
        ("Gemínidas","<lang xml:lang=\"es-US\">Gemínidas</lang>")
    ]
    /// Every range of `text` that has a pronunciation, with its fragment. Pure, for tests.
    static func annotations(in text:String)->[(range:Range<String.Index>,ssml:String)] {
        var found:[(Range<String.Index>,String)]=[]
        for entry in pronunciations {
            var start=text.startIndex
            while let range=text.range(of:entry.word,range:start..<text.endIndex) { found.append((range,entry.ssml)); start=range.upperBound }
        }
        return found.sorted { $0.0.lowerBound<$1.0.lowerBound }
    }
}
extension View {
    /// An accessibility label that VoiceOver pronounces with Nyx's SSML on iOS 27.
    func speechLabel(_ text:String)->some View { accessibilityLabel(SpokenText.make(text)) }
}
enum SpokenText {
    static func make(_ text:String)->Text {
        guard #available(iOS 27.0, *), !NyxSpeech.annotations(in:text).isEmpty else { return Text(verbatim:text) }
        var attributed=AttributedString(text)
        for annotation in NyxSpeech.annotations(in:text) {
            guard let lower=AttributedString.Index(annotation.range.lowerBound,within:attributed),
                  let upper=AttributedString.Index(annotation.range.upperBound,within:attributed) else { continue }
            attributed[lower..<upper].accessibilitySpeechSSML=annotation.ssml
        }
        return Text(attributed)
    }
}

// MARK: Colour independence

/// The shape vocabulary that carries meaning colour also carries, so nothing depends on amber alone.
/// Used everywhere a night is a mark: the calendar, the river, the week strip.
nonisolated enum NightMark: Equatable, Sendable {
    /// Excellent or Pristine nights become four-pointed stars when Differentiate Without Color
    /// is on; every other night stays a dot. Hollow means no cloud forecast, in both shapes.
    case dot(filled:Bool)
    case star(filled:Bool)
    static func mark(score:Int,hasForecast:Bool,differentiate:Bool)->NightMark {
        differentiate && score>=75 ? .star(filled:hasForecast) : .dot(filled:hasForecast)
    }
    var filled: Bool { switch self { case .dot(let filled),.star(let filled): filled } }
    var isStar: Bool { if case .star=self { true } else { false } }
    /// The mark's outline, `radius` being the dot's own radius; a star reaches a little farther so
    /// it reads as the same size.
    func path(center:CGPoint,radius:Double)->Path {
        switch self {
        case .dot: return Path(ellipseIn:CGRect(x:center.x-radius,y:center.y-radius,width:2*radius,height:2*radius))
        case .star:
            let outer=max(3,radius*1.35), inner=outer*0.42
            var path=Path()
            for i in 0..<8 {
                let angle=Double(i)*Double.pi/4-Double.pi/2, r=i%2==0 ? outer : inner
                let point=CGPoint(x:center.x+r*cos(angle),y:center.y+r*sin(angle))
                if i==0 { path.move(to:point) } else { path.addLine(to:point) }
            }
            path.closeSubpath()
            return path
        }
    }
    /// One sentence for a legend, said only when the stars are drawn.
    static var legend: String { String(localized:"Star-shaped marks are Excellent or Pristine nights.") }
}
