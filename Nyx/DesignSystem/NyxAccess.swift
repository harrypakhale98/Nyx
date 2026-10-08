import SwiftUI
import Accessibility

extension View {
    /// Reads the system's accessibility preferences into `\.nyxAccess`. Applied at the root and on
    /// screens presented outside SwiftUI's hierarchy (field mode, a park opened from a reminder).
    func nyxAccessibility()->some View { modifier(NyxAccessReader()) }
}
private struct NyxAccessReader: ViewModifier {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    @Environment(\.accessibilityShowBorders) private var showBorders
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    /// iOS 26.1's "prefers action slider alternative", read at appear and whenever it changes.
    @State private var actionSliderAlternative=ActionSliderPreference.current
    @ViewBuilder func body(content:Content)->some View {
        let base=NyxAccess(differentiate:differentiate || DebugScenario.isEnabled("differentiate"),
                           reduceHighlighting:DebugScenario.isEnabled("reduce-highlighting"),
                           crossFade:DebugScenario.isEnabled("crossfade"),
                           reducedResources:DebugScenario.isEnabled("reduced-resources"),
                           showBorders:showBorders || DebugScenario.isEnabled("borders"),
                           preferSteps:actionSliderAlternative || switchControl || DebugScenario.isEnabled("steps"))
        Group {
            if #available(iOS 26.4, *) { content.modifier(NyxAccessReader264(base:base)) }
            else { content.environment(\.nyxAccess,base) }
        }
        .onReceive(NotificationCenter.default.publisher(for:ActionSliderPreference.changed)) { _ in actionSliderAlternative=ActionSliderPreference.current }
    }
}
/// "Prefers action slider alternative" (Settings › Accessibility › Touch, iOS 26.1): items that rely
/// on a prolonged, continuous swipe should offer something needing less dexterity. Before 26.1 the
/// setting does not exist; Switch Control and accessibility text sizes bring the same buttons.
enum ActionSliderPreference {
    static var current: Bool {
        if #available(iOS 26.1, *) { return AccessibilitySettings.prefersActionSliderAlternative }
        return false
    }
    /// The change notification; before iOS 26.1, a name nothing posts.
    static var changed: Notification.Name {
        if #available(iOS 26.1, *) { return AccessibilitySettings.prefersActionSliderAlternativeDidChangeNotification }
        return Notification.Name("com.harrypakhale.nyx.actionSliderUnavailable")
    }
}
@available(iOS 26.4, *)
private struct NyxAccessReader264: ViewModifier {
    @Environment(\.accessibilityReduceHighlightingEffects) private var reduceHighlighting
    @Environment(\.accessibilityPrefersCrossFadeTransitions) private var crossFade
    let base: NyxAccess
    private var access: NyxAccess {
        var access=base
        access.reduceHighlighting=base.reduceHighlighting || reduceHighlighting
        access.crossFade=base.crossFade || crossFade
        return access
    }
    @ViewBuilder func body(content:Content)->some View {
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
/// fragment (`accessibilitySpeechSSML`); before it, words with an IPA spelling get the iOS 15
/// phonetic notation instead, so "Bortle" is never "bottle" on iOS 26 either. The text itself, and
/// Braille, are unchanged.
nonisolated enum NyxSpeech {
    static let bortleIPA="ˈbɔɹtəl"
    /// Word → IPA, for iOS 26's `accessibilitySpeechPhoneticNotation` (words SSML only substitutes
    /// or switches language for are left as they are).
    static let phonetic:[(word:String,ipa:String)]=[("Bortle",bortleIPA)]
    /// Every range of `text` that has an IPA spelling, with it. Pure, for tests.
    static func phoneticAnnotations(in text:String)->[(range:Range<String.Index>,ipa:String)] {
        var found:[(Range<String.Index>,String)]=[]
        for entry in phonetic {
            var start=text.startIndex
            while let range=text.range(of:entry.word,range:start..<text.endIndex) { found.append((range,entry.ipa)); start=range.upperBound }
        }
        return found.sorted { $0.0.lowerBound<$1.0.lowerBound }
    }
    /// Word → SSML fragment. "Bortle" is said BOR-tl, not "bottle"; the Milky Way's centre is
    /// "Sagittarius A star", as astronomers say it.
    static let pronunciations:[(word:String,ssml:String)]=[
        ("Bortle","<phoneme alphabet=\"ipa\" ph=\"\(bortleIPA)\">Bortle</phoneme>"),
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
        if #available(iOS 27.0, *) {
            return NyxSpeech.annotations(in:text).isEmpty ? Text(verbatim:text) : Text(ssml(text))
        }
        return NyxSpeech.phoneticAnnotations(in:text).isEmpty ? Text(verbatim:text) : Text(phonetic(text))
    }
    /// iOS 27: each word with a pronunciation carries its SSML fragment.
    @available(iOS 27.0, *)
    static func ssml(_ text:String)->AttributedString {
        var attributed=AttributedString(text)
        for annotation in NyxSpeech.annotations(in:text) {
            guard let lower=AttributedString.Index(annotation.range.lowerBound,within:attributed),
                  let upper=AttributedString.Index(annotation.range.upperBound,within:attributed) else { continue }
            attributed[lower..<upper].accessibilitySpeechSSML=annotation.ssml
        }
        return attributed
    }
    /// Before iOS 27: each word with an IPA spelling carries it as phonetic notation (iOS 15+).
    static func phonetic(_ text:String)->AttributedString {
        var attributed=AttributedString(text)
        for annotation in NyxSpeech.phoneticAnnotations(in:text) {
            guard let lower=AttributedString.Index(annotation.range.lowerBound,within:attributed),
                  let upper=AttributedString.Index(annotation.range.upperBound,within:attributed) else { continue }
            attributed[lower..<upper].accessibilitySpeechPhoneticNotation=annotation.ipa
        }
        return attributed
    }
}

// MARK: Actions

/// For actions that are only words (amber text, a small capsule): pressed, they dim like a plain
/// button; with Show Borders (Button Shapes) on, a hairline capsule, or an underline for a link in
/// running text, says "this is a button" without colour. Rows and cards that draw their own
/// outline keep `.plain`.
struct NyxActionStyle: ButtonStyle {
    enum Border { case capsule, underline }
    var border: Border = .capsule
    func makeBody(configuration:Configuration)->some View { NyxActionLabel(configuration:configuration,border:border) }
}
private struct NyxActionLabel: View {
    let configuration: ButtonStyleConfiguration
    let border: NyxActionStyle.Border
    @Environment(\.nyxAccess) private var access
    @Environment(\.nyx) private var palette
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        configuration.label
            .padding(.horizontal,access.showBorders && border == .capsule ? 12 : 0)
            .overlay {
                if access.showBorders {
                    switch border {
                    case .capsule: Capsule().strokeBorder(palette.line,lineWidth:1)
                    case .underline: Rectangle().fill(palette.line).frame(height:1).frame(maxHeight:.infinity,alignment:.bottom).padding(.bottom,6)
                    }
                }
            }
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : enabled ? 1 : 0.45)
    }
}
extension ButtonStyle where Self == NyxActionStyle {
    /// A text-only action that gains an outline under Show Borders.
    static var nyxAction: NyxActionStyle { NyxActionStyle() }
}

// MARK: Colour independence

/// The shape vocabulary that carries meaning colour also carries, so nothing depends on amber alone.
/// Used everywhere a night is a mark: the calendar, the river, the week strip.
nonisolated enum NightMark: Equatable, Sendable {
    /// Excellent or Pristine nights become four-pointed stars when Differentiate Without Color
    /// is on; every other night stays a dot. Hollow means no cloud forecast yet and half-filled an
    /// early look (a forecast eased toward the usual clouds), in both shapes.
    case dot(filled:Bool)
    case star(filled:Bool)
    static func mark(score:Int,hasForecast:Bool,differentiate:Bool)->NightMark {
        differentiate && score>=75 ? .star(filled:hasForecast) : .dot(filled:hasForecast)
    }
    /// A night's mark; an early look is drawn hollow with its lower half filled (`draw`).
    static func mark(_ night:Night,differentiate:Bool)->NightMark { mark(score:night.score.value,hasForecast:night.basis.fill == .full,differentiate:differentiate) }
    /// Draws a mark: filled, hollow, or hollow with its lower half filled for an early look.
    func draw(in context:inout GraphicsContext,center:CGPoint,radius:Double,fill:NightFill,color:Color,fillOpacity:Double,lineWidth:Double=1.1,hollowBackground:Color?=nil) {
        let shape=path(center:center,radius:radius)
        switch fill {
        case .full: context.fill(shape,with:.color(color.opacity(fillOpacity)))
        case .half, .hollow:
            if let hollowBackground { context.fill(shape,with:.color(hollowBackground)) }
            if fill == .half {
                var lower=context
                let reach=radius*1.5+2
                lower.clip(to:Path(CGRect(x:center.x-reach,y:center.y,width:2*reach,height:reach)))
                lower.fill(shape,with:.color(color.opacity(fillOpacity)))
            }
            context.stroke(shape,with:.color(color),lineWidth:lineWidth)
        }
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
