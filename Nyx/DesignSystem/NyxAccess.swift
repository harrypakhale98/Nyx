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
/// A park pushed from a page that shows it in more than one place (Tonight's pill, the pill's list
/// and the rows below it): each place is its own zoom source, so the page grows out of the one tapped.
nonisolated struct ZoomRoute: Hashable, Sendable {
    let park: Park
    /// The transition source's id, unique on the page.
    let source: String
    static func pill(_ park: Park) -> ZoomRoute { ZoomRoute(park: park, source: "pill.\(park.id)") }
    static func pillList(_ park: Park) -> ZoomRoute { ZoomRoute(park: park, source: "pill-list.\(park.id)") }
    static func row(_ park: Park) -> ZoomRoute { ZoomRoute(park: park, source: "row.\(park.id)") }
}
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
    static func phoneticAnnotations(in text:String)->[(range:Range<String.Index>,ipa:String)] { ranges(of:phonetic,in:text) }
    /// Word → SSML fragment. "Bortle" is said BOR-tl, not "bottle"; the Milky Way's centre is
    /// "Sagittarius A star", as astronomers say it.
    static let pronunciations:[(word:String,ssml:String)]=[
        ("Bortle","<phoneme alphabet=\"ipa\" ph=\"\(bortleIPA)\">Bortle</phoneme>"),
        ("Sagittarius A*","Sagittarius A <sub alias=\"star\">*</sub>"),
        ("Gemínidas","<lang xml:lang=\"es-US\">Gemínidas</lang>")
    ]
    /// Every range of `text` that has a pronunciation, with its fragment. Pure, for tests.
    static func annotations(in text:String)->[(range:Range<String.Index>,ssml:String)] { ranges(of:pronunciations,in:text) }
    /// Every range of `text` where one of the table's words appears, with that word's spelling, in reading order.
    private static func ranges(of table:[(String,String)],in text:String)->[(Range<String.Index>,String)] {
        var found:[(Range<String.Index>,String)]=[]
        for (word,spelling) in table {
            var start=text.startIndex
            while let range=text.range(of:word,range:start..<text.endIndex) { found.append((range,spelling)); start=range.upperBound }
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

/// For actions that are only words (starlight text, a small capsule): pressed, they dim like a plain
/// button; with Show Borders (Button Shapes) on, a hairline capsule says "this is a button" without
/// colour. Rows and cards that draw their own outline keep `.plain`.
struct NyxActionStyle: ButtonStyle {
    func makeBody(configuration:Configuration)->some View { NyxActionLabel(configuration:configuration) }
}
private struct NyxActionLabel: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.nyxAccess) private var access
    @Environment(\.nyx) private var palette
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        configuration.label
            .padding(.horizontal,access.showBorders ? 12 : 0)
            .overlay { if access.showBorders { Capsule().strokeBorder(palette.line,lineWidth:1) } }
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : enabled ? 1 : 0.45)
    }
}
extension ButtonStyle where Self == NyxActionStyle {
    /// A text-only action that gains an outline under Show Borders.
    static var nyxAction: NyxActionStyle { NyxActionStyle() }
}
/// An action that leads somewhere from an answer (a darker night ahead, a wider radius, field mode,
/// Listen): starlight words in a faintly filled hairline capsule, at least 44 pt tall (amber stays with the score). Pressed it dims;
/// under a pointer (iPad) the capsule lifts. The capsule already outlines it, so Show Borders adds nothing.
struct CapsuleActionStyle: ButtonStyle {
    /// The rounded rectangle at every size, for a label broken onto two lines.
    var rounded=false
    func makeBody(configuration:Configuration)->some View { CapsuleActionLabel(configuration:configuration,rounded:rounded) }
}
private struct CapsuleActionLabel: View {
    let configuration: ButtonStyleConfiguration
    let rounded: Bool
    @Environment(\.nyx) private var palette
    @Environment(\.isEnabled) private var enabled
    @Environment(\.dynamicTypeSize) private var typeSize
    /// A rounded rectangle at accessibility sizes: a capsule around several wrapped lines has so large
    /// a radius that its rim cuts through the first and last.
    private var shape: AnyShape { rounded || typeSize.isAccessibilitySize ? AnyShape(RoundedRectangle(cornerRadius:22,style:.continuous)) : AnyShape(Capsule()) }
    var body: some View {
        configuration.label
            .font(.subheadline).foregroundStyle(palette.ink).padding(.vertical,10).padding(.horizontal,16).frame(minHeight:44)
            .background(shape.fill(palette.ink.opacity(palette.nightVision ? 0 : 0.06)))
            .overlay(shape.stroke(palette.line,lineWidth:0.5*palette.stroke))
            .contentShape(.hoverEffect,shape).hoverEffect(.highlight)
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.55 : enabled ? 1 : 0.45)
    }
}
extension ButtonStyle where Self == CapsuleActionStyle {
    /// The hairline capsule that leads from an answer to the next step.
    static var capsuleAction: CapsuleActionStyle { CapsuleActionStyle() }
}

/// A secondary action ("Tell someone", "Near me", "Add all to Calendar"): clear glass with a starlight
/// label, so amber stays with the score and light and no action reads as a tinted web button. Bordered
/// in starlight where glass would not read: night vision, Reduce Transparency, Increase Contrast. One look
/// for every such button, "I'm here tonight" and "Keep this night" too.
struct SecondaryAction: ViewModifier {
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var typeSize
    /// A rounded rectangle at accessibility sizes, where a wrapped label would meet a capsule's rim.
    private var shape: ButtonBorderShape { typeSize.isAccessibilitySize ? .roundedRectangle(radius:22) : .capsule }
    /// Bordered always: a quieter action beside a glass one ("Keep this night" under another answer).
    var bordered=false
    @ViewBuilder func body(content:Content)->some View {
        if bordered || NyxGlass<Capsule>.solid(palette,reduceTransparency:reduceTransparency) { content.buttonStyle(.bordered).buttonBorderShape(shape).tint(palette.ink) }
        else { content.buttonStyle(.glass).buttonBorderShape(shape).tint(palette.ink) }
    }
}
extension View {
    func secondaryAction(bordered:Bool=false)->some View { modifier(SecondaryAction(bordered:bordered)) }
}

/// The three action looks side by side: a text action, a capsule, and a secondary action on glass.
private struct ActionStylesPreview: View {
    var body: some View {
        VStack(spacing:18) {
            Button("Open this night") {}.buttonStyle(.nyxAction)
            Button { } label:{ Label { Text(verbatim:"Darker on Fri, Oct 30 · Joshua Tree, 82") } icon:{ Image(systemName:"moon.stars") } }.buttonStyle(.capsuleAction)
            Button { } label:{ Label("Add to Calendar",systemImage:"calendar.badge.plus") }.secondaryAction()
        }.padding().background(.black)
    }
}
#Preview("Action styles") { ActionStylesPreview() }
#Preview("Action styles • AX5, wrapped") { ActionStylesPreview().dynamicTypeSize(.accessibility5) }
#Preview("Action styles • Increase Contrast") { ActionStylesPreview().environment(\.nyx,NyxPalette(nightVision:false,highContrast:true)) }
#Preview("Action styles • night vision") { ActionStylesPreview().environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)) }
