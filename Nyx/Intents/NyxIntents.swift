import AppIntents
import CoreSpotlight
import SwiftUI

// `ParkEntity`, `ParkQuery`, `OpenParkIntent` and the widgets' settings live in ParkEntity.swift,
// shared with the widget extension.

/// iOS 27 asks the app to rebuild its Spotlight entries (after a restore, or when the index is lost).
/// Nyx keeps its parks in the default index, with no protection class: they are public facts.
@available(iOS 27.0,*)
extension ParkQuery:IndexedEntityQuery {
    func reindexEntities(for identifiers:[String],indexDescription:CSSearchableIndexDescription) async throws {
        try await SpotlightIndexer.reindex(identifiers)
    }
    /// The curated parks and the world catalogue places Nyx keeps in Spotlight (`SpotlightIndexer`).
    func reindexAllEntities(indexDescription:CSSearchableIndexDescription) async throws {
        try await SpotlightIndexer.reindexAll()
    }
}
/// What Siri and Shortcuts say when an intent cannot answer, in the same calm words as the app.
enum NyxIntentError:Error,CustomLocalizedStringResourceConvertible {
    case parkNotFound, noParks, noNights, journalUnavailable, journalLocked
    var localizedStringResource:LocalizedStringResource {
        switch self {
        case .parkNotFound: "That place could not be found in Nyx."
        case .noParks: "Choose a park, or save parks in Nyx to compare them."
        case .noNights: "Nyx could not find those nights."
        case .journalUnavailable: "Your journal could not be opened, so nothing was read or saved. The Journal tab in Nyx says more."
        case .journalLocked: "Your journal stays closed while this device is locked. Unlock it, then ask again."
        }
    }
}
/// "What's the darkness score at Joshua Tree tonight?" Answers in words, with a card (the score
/// on a still dial, the Moon, what the clouds rest on), and returns the score so Shortcuts can use it.
struct DarknessIntent:AppIntent {
    static let title:LocalizedStringResource="Tonight's darkness score"
    static let description=IntentDescription("Find the on-device darkness estimate for a park or dark-sky place. Returns the score, 0 to 100.")
    @Parameter(title:"Park") var park:ParkEntity
    static var parameterSummary:some ParameterSummary { Summary("Darkness at \(\.$park) tonight") }
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog & ShowsSnippetView {
        // A park or followed place, else any world catalogue place by its id (one found by search, not followed).
        guard let selected=try ParkLibrary.places().first(where:{$0.id==park.id}) ?? ParkLibrary.place(park.id) else { throw NyxIntentError.parkNotFound }
        // Saved parks share their forecast with the widget; the app's own cache may be newer.
        let shared=SharedSettings.read()
        var voiceOnly=false
        if #available(iOS 27.0,*) { voiceOnly=systemContext.isVoiceOnly }
        // The park's closure from the app's last park update, said before the score.
        let answer=DarknessAnswer(park:selected,forecast:BestNightSearch.forecasts(for:[selected],shared:shared)[selected.id],
                                  detail:BestNightSearch.details(for:[selected],shared:shared)[selected.id],closure:IntentClosure.closure(selected,shared:shared),now:.now,voiceOnly:voiceOnly)
        return .result(value:answer.night.score.value,dialog:IntentDialog(stringLiteral:answer.dialog),view:DarknessSnippetView(night:answer.night))
    }
}
/// A place's closure for a spoken answer: the copy shared with the widgets (saved parks), else the
/// app's own last park alerts on disk, never a request, while park alerts are on in Your privacy.
nonisolated enum IntentClosure {
    static func closure(_ park:Park,shared:SavedSkySnapshot?,enabled:Bool=alertsEnabled(),cached:(Park)->ParkAlertsCache?={ ParkStore.stored([$0]) })->String? {
        if let saved=shared?.closures[park.id] { return saved }
        guard enabled, let code=park.nps, let alerts=cached(park)?.alerts[code] else { return nil }
        return AlertRanking.closure(alerts)?.displayTitle(park:park)
    }
    /// The Your privacy switch for the Park Service (on unless turned off).
    static func alertsEnabled(_ defaults:UserDefaults = .standard)->Bool { defaults.object(forKey:"npsEnabled") as? Bool ?? true }
}
/// The darkness answer apart from the intent, so its words and value can be tested.
nonisolated struct DarknessAnswer:Sendable {
    let night:Night
    let dialog:String
    /// `closure` is the park's closure as Nyx words it beside the score; `voiceOnly` (iOS 27, no
    /// screen in view) keeps the closure, the score and the one caveat that matters.
    init(park:Park,forecast:Forecast?,detail:ForecastDetail?,closure:String?=nil,now:Date,voiceOnly:Bool=false) {
        let sky=AstronomyEngine().conditions(for:park,on:park.currentNight(at:now))
        night=NightPlanner.night(park:park,sky:sky,forecast:forecast,detail:detail,now:now)
        dialog=Self.dialog(night,closure:closure,voiceOnly:voiceOnly)
    }
    /// A closure comes first: a long drive to a closed road is the worst outcome Nyx can cause.
    static func dialog(_ night:Night,closure:String?,voiceOnly:Bool)->String {
        withClosures(night.spokenSummary(.siriTonight(voiceOnly:voiceOnly)),park:night.park,closure:closure)
    }
    /// Every spoken answer about a place, as to closures: a park's closure first (`closureFirst`); at a
    /// place the Park Service does not run, where Nyx has no closures to know, a last sentence that says
    /// so, so silence never reads as "nothing is closed".
    static func withClosures(_ body:String,park:Park,closure:String?)->String {
        let answer=closureFirst(body,closure:closure)
        return unknownClosures(park).map { Sentences.join([answer, $0]) } ?? answer
    }
    /// What the place's own page says where the Park Service has no alerts (`Place.unknownClosuresLine`):
    /// a place abroad points to its own site, a saved spot to local checks. Nil for a national park.
    static func unknownClosures(_ park:Park)->String? {
        guard park.nps == nil else { return nil }
        return park.isCatalogPlace ? String(localized:"Nyx can't check closures here. Check the park's own site before you go.")
            : String(localized:"Nyx has no alerts for this place. Check access, local rules and closures before you go.")
    }
    /// "Closure alert: …" before any answer about a park, when it has one. Shared by every spoken answer.
    static func closureFirst(_ body:String,closure:String?)->String {
        guard let closure=closure?.trimmingCharacters(in:.whitespacesAndNewlines), !closure.isEmpty else { return body }
        return Sentences.join([sentence(String(localized:"Closure alert: \(closure)")), body])
    }
    /// An NPS headline usually ends without a full stop; one is added so the score reads as its own sentence.
    static func sentence(_ text:String)->String { Sentences.end(text) }
}
/// Siri's card for tonight's score: the score on a still dial (Siri shows a snapshot, so nothing
/// counts up), the Moon as it is tonight, and what the clouds rest on.
struct DarknessSnippetView:View {
    let night:Night
    @Environment(\.colorSchemeContrast) private var contrast
    /// The app's night look, so a night-vision evening is not lit up by a white card.
    private var palette:NyxPalette { NightLook(contrast:contrast).palette }
    var body:some View {
        HStack(alignment:.center,spacing:18) {
            StaticScoreDial(score:night.score.value,hasForecast:night.score.hasForecast,palette:palette).frame(width:118,height:118)
            VStack(alignment:.leading,spacing:6) {
                Text("Tonight").textCase(Lettering.spaced ? .uppercase : nil).font(.caption2.weight(.medium)).tracking(Lettering.spaced ? 1.4 : 0).foregroundStyle(palette.muted)
                Text(night.park.shortName).font(.system(.title3,design:.serif)).fixedSize(horizontal:false,vertical:true)
                Text(night.score.band.label).font(.system(.headline,design:.serif)).foregroundStyle(palette.accent)
                HStack(spacing:8) {
                    MoonDisc(illumination:night.sky.moon.illumination,waxing:night.sky.moon.waxing,southern:night.park.latitude<0)
                        .frame(width:22,height:22).accessibilityIgnoresInvertColors()
                    Text("\(night.sky.moon.name), \(Percent.text(Int((night.sky.moon.illumination*100).rounded()))) lit").font(.caption).foregroundStyle(palette.muted)
                }
                Text(night.basisLabel ?? String(localized:"Cached forecast included")).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                // A place the Park Service does not run: Nyx cannot see its closures, and says so.
                if let unknown=DarknessAnswer.unknownClosures(night.park) { Text(unknown).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
            }
            Spacer(minLength:0)
        }
        .foregroundStyle(palette.ink)
        .padding(18)
        .background(palette.snippetBackground,in:RoundedRectangle(cornerRadius:22))
        .environment(\.nyx,palette)
        .modifier(NightVisionFilter(enabled:palette.nightVision,red:palette.red))
        .environment(\.colorScheme,.dark)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(DarknessAnswer.withClosures(night.spokenSummary(.snippet),park:night.park,closure:nil))
    }
}
/// The celestial gauge's arc and numeral, drawn once: for snapshots (Siri) where nothing animates.
/// A dashed arc when the score has no full cloud forecast, as in the app.
struct StaticScoreDial:View {
    let score:Int
    var hasForecast=true
    let palette:NyxPalette
    var body:some View {
        ZStack {
            Circle().trim(from:0.125,to:0.875).rotation(.degrees(90))
                .stroke(palette.ink.opacity(0.18),style:StrokeStyle(lineWidth:7,lineCap:.round))
            Circle().trim(from:0.125,to:0.125+0.75*Double(min(100,max(0,score)))/100).rotation(.degrees(90))
                .stroke(palette.accent,style:StrokeStyle(lineWidth:7,lineCap:.round,dash:hasForecast ? [] : [6,5]))
            VStack(spacing:0) {
                Text("\(score)").font(.system(size:44,weight:.light,design:.serif)).monospacedDigit().foregroundStyle(palette.accent)
                Text("of 100").font(.caption2).foregroundStyle(palette.muted)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityHidden(true)
    }
}
#Preview("Darkness snippet") {
    let model=PlanModel()
    if let park=model.home { DarknessSnippetView(night:model.night(park)).padding() }
}
/// Nine of the ten App Shortcuts an app may offer. Every phrase names Nyx; parks come from
/// `ParkQuery.suggestedEntities`, refreshed by `updateAppShortcutParameters()` at launch and when saved parks change.
struct NyxShortcuts:AppShortcutsProvider {
    static var appShortcuts:[AppShortcut] {
        AppShortcut(intent:DarknessIntent(),phrases:["What is the darkness score at \(\.$park) in \(.applicationName)","Check tonight's sky at \(\.$park) with \(.applicationName)"],shortTitle:"Tonight's sky",systemImageName:"moon.stars")
        AppShortcut(intent:FindBestNightIntent(),phrases:["Find the best night at \(\.$park) with \(.applicationName)","When is the darkest night at \(\.$park) in \(.applicationName)","Find the best night for stars with \(.applicationName)"],shortTitle:"Best night",systemImageName:"calendar")
        AppShortcut(intent:DarkTonightIntent(),phrases:["When is it dark tonight in \(.applicationName)","When is it dark at \(\.$park) in \(.applicationName)","When does true darkness start at \(\.$park) in \(.applicationName)"],shortTitle:"Dark hours",systemImageName:"moon.haze")
        AppShortcut(intent:WhatsUpTonightIntent(),phrases:["What's up tonight in \(.applicationName)","What's up tonight at \(\.$park) in \(.applicationName)","What can I see tonight at \(\.$park) with \(.applicationName)"],shortTitle:"What's up",systemImageName:"sparkles")
        // A park is optional: without one, field mode opens at the last park used in the field, else the starting park.
        AppShortcut(intent:StartFieldModeIntent(),phrases:["Start field mode at \(\.$park) in \(.applicationName)","I'm stargazing at \(\.$park) with \(.applicationName)","Start field mode in \(.applicationName)","I'm stargazing with \(.applicationName)"],shortTitle:"Field mode",systemImageName:"scope")
        AppShortcut(intent:FollowNightIntent(),phrases:["Follow tonight in \(.applicationName)","Follow tonight at \(\.$park) in \(.applicationName)","Put tonight on my Lock Screen with \(.applicationName)"],shortTitle:"Follow tonight",systemImageName:"lock.rectangle")
        AppShortcut(intent:UnfollowNightIntent(),phrases:["Stop following the night in \(.applicationName)","Stop following \(\.$park) in \(.applicationName)"],shortTitle:"Stop following",systemImageName:"moon.stars")
        AppShortcut(intent:NightVisionOnIntent(),phrases:["Turn on night vision in \(.applicationName)","Turn on \(.applicationName) night vision"],shortTitle:"Night vision",systemImageName:"flashlight.on.circle.fill")
        AppShortcut(intent:AddJournalEntryIntent(),phrases:["Add to my \(.applicationName) journal","Record a night in \(.applicationName)"],shortTitle:"Record a night",systemImageName:"book.closed")
    }
}
