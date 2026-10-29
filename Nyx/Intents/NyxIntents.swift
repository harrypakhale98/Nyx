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
    static let description=IntentDescription("Find the on-device darkness score for a park or dark-sky place. Returns the score, 0 to 100.")
    @Parameter(title:"Park") var park:ParkEntity
    static var parameterSummary:some ParameterSummary { Summary("Darkness at \(\.$park) tonight") }
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog & ShowsSnippetView {
        let sky=try await IntentSky.load([park.id])
        guard let selected=sky.parks.first else { throw NyxIntentError.parkNotFound }
        var voiceOnly=false
        if #available(iOS 27.0,*) { voiceOnly=systemContext.isVoiceOnly }
        // The park's closure from the app's last park update, said before the score.
        let answer=DarknessAnswer(park:selected,forecast:sky.planner.forecasts[selected.id],detail:sky.planner.details[selected.id],closure:sky.closures[selected.id],
                                  inputs:sky.inputs(selected),forecastsOn:NetworkService.forecasts.isOn(),now:.now,voiceOnly:voiceOnly)
        return .result(value:answer.night.score.value,dialog:IntentDialog(stringLiteral:answer.dialog),view:DarknessSnippetView(night:answer.night,closure:answer.closure))
    }
}
/// What Siri's answers about places read, once, and never a request: the copy shared with the
/// widgets, the places asked about, a planner with their newest forecasts (`BestNightSearch`), the
/// last park alerts on this device and each place's closure (`IntentClosure`). Tonight's darkness
/// score, Find the best night and its card all start here, so they name the same night.
nonisolated struct IntentSky {
    let shared: SavedSkySnapshot?
    let parks: [Park]
    let planner: NightPlanner
    /// The app's last park alerts on disk, read only while park alerts are on in Your privacy.
    let alerts: ParkAlertsCache?
    /// Each place's closure, by id.
    let closures: [String: String]
    /// `ids`: the places asked about, nil for the saved parks. A place the library lacks (a world
    /// catalogue place found by search, not followed) resolves by its id; one that resolves to nothing is left out.
    static func load(_ ids: [String]?) async throws -> IntentSky {
        // Saved parks share their forecast with the widget; the app's own cache may be newer. Read once.
        let shared=await SharedSettings.load()
        guard let ids else { return IntentSky(shared:shared,parks:shared?.parks ?? []) }
        let library=try ParkLibrary.places(snapshot:shared)
        return IntentSky(shared:shared,parks:ids.compactMap { id in library.first { $0.id==id } ?? ParkLibrary.place(id,snapshot:shared) })
    }
    init(shared: SavedSkySnapshot?, parks: [Park]) {
        self.shared=shared; self.parks=parks
        planner=NightPlanner(forecasts:BestNightSearch.forecasts(for:parks,shared:shared),details:BestNightSearch.details(for:parks,shared:shared))
        let enabled=NetworkService.alerts.isOn(), alerts=enabled ? ParkStore.stored(parks) : nil
        self.alerts=alerts
        closures=IntentClosure.closures(parks,shared:shared,enabled:enabled,cached:{ _ in alerts })
    }
    /// What a score here counts and leaves out, as the app's switches and caches say (`ScoreInputs`).
    func inputs(_ park: Park) -> ScoreInputs {
        ScoreInputs(smokeOn:NetworkService.smoke.isOn(),smokeKnown:planner.details[park.id]?.air == nil ? [] : [park.id],alertsOn:NetworkService.alerts.isOn(),alerts:alerts)
    }
}
/// A place's closure for a spoken answer or a followed night, from whichever is newer: the copy
/// shared with the widgets, or the app's own last park alerts on disk (while park alerts are on in
/// Your privacy). Never a request. A closure the newer alerts cleared is never said.
nonisolated enum IntentClosure {
    static func closure(_ park:Park,shared:SavedSkySnapshot?,enabled:Bool=NetworkService.alerts.isOn(),cached:(Park)->ParkAlertsCache?={ ParkStore.stored([$0]) })->String? {
        let saved=shared?.closures[park.id]
        guard enabled, let code=park.nps, let cache=cached(park) else { return saved }
        // The shared copy stands when it was made from these alerts or newer ones, and for a park the
        // alerts on disk do not cover (each fetch lists every park asked for, with or without alerts).
        if let stamp=shared?.closuresUpdated, stamp>=cache.updated { return saved }
        guard cache.alerts[code] != nil else { return saved }
        return cache.closure(for:park)
    }
    /// Every closure among these places, by park id. `cached`: the alerts on disk, read once by the caller.
    static func closures(_ parks:[Park],shared:SavedSkySnapshot?,enabled:Bool,cached:(Park)->ParkAlertsCache?)->[String:String] {
        Dictionary(parks.compactMap { park in closure(park,shared:shared,enabled:enabled,cached:cached).map { (park.id,$0) } },uniquingKeysWith:{ first,_ in first })
    }
}
/// The darkness answer apart from the intent, so its words and value can be tested. The words are
/// every device's (`TonightAnswer`).
nonisolated struct DarknessAnswer:Sendable {
    let night:Night
    let dialog:String
    /// The closure the dialog leads with, for the card beside it.
    let closure:String?
    /// `closure` is the park's closure as Nyx words it beside the score; `inputs`, what the score counts
    /// and leaves out (smoke, whether closures were checked; the detail's smoke is counted in); `voiceOnly`
    /// (iOS 27, no screen in view) keeps the closure, the score and the one caveat that matters.
    init(park:Park,forecast:Forecast?,detail:ForecastDetail?,closure:String?=nil,inputs:ScoreInputs?=nil,forecastsOn:Bool=true,now:Date,voiceOnly:Bool=false) {
        let sky=AstronomyEngine().conditions(for:park,on:park.currentNight(at:now))
        night=NightPlanner.night(park:park,sky:sky,forecast:forecast,detail:detail,now:now)
        self.closure=closure
        var inputs=inputs
        if detail?.air != nil { inputs?.smokeKnown.insert(park.id) }
        dialog=Self.dialog(night,closure:closure,inputs:inputs,forecastsOn:forecastsOn,voiceOnly:voiceOnly)
    }
    /// Without `inputs`, the answer says nothing of smoke left out or closures unchecked.
    static func dialog(_ night:Night,closure:String?,inputs:ScoreInputs?=nil,forecastsOn:Bool=true,voiceOnly:Bool)->String {
        (inputs?.answer(night,closure:closure,forecastsOn:forecastsOn) ?? TonightAnswer(night:night,closure:closure,forecastsOn:forecastsOn)).dialog(voiceOnly:voiceOnly)
    }
}
/// Siri's card for tonight's score: the score on a still dial (Siri shows a snapshot, so nothing
/// counts up), the Moon as it is tonight, what the clouds rest on, and the closure the answer led with.
struct DarknessSnippetView:View {
    let night:Night
    /// The park's closure, as the spoken answer says it first and the best-night card shows it.
    var closure:String?=nil
    @Environment(\.colorSchemeContrast) private var contrast
    /// The app's night look, so a night-vision evening is not lit up by a white card.
    private var palette:NyxPalette { NightLook(contrast:contrast).palette }
    var body:some View {
        HStack(alignment:.center,spacing:18) {
            StaticScoreDial(score:night.score.value,hasForecast:night.score.hasForecast,palette:palette).frame(width:118,height:118)
            VStack(alignment:.leading,spacing:6) {
                Text("Tonight").textCase(Lettering.spaced ? .uppercase : nil).font(.caption2.weight(.medium)).tracking(Lettering.spaced ? 1.4 : 0).foregroundStyle(palette.muted)
                Text(night.park.shortName).font(.system(.title3,design:.serif)).fixedSize(horizontal:false,vertical:true)
                Text(night.score.band.label).bandWord(.headline,ink:palette.ink)
                // The one line that must never be lost: beside the score, as on the park's page.
                if let closure { Label(closure,systemImage:"exclamationmark.triangle").font(.caption).labelStyle(.caution).fixedSize(horizontal:false,vertical:true) }
                HStack(spacing:8) {
                    MoonDisc(illumination:night.sky.moon.illumination,waxing:night.sky.moon.waxing,southern:night.park.latitude<0)
                        .frame(width:22,height:22).accessibilityIgnoresInvertColors()
                    Text("\(night.sky.moon.name), \(night.sky.moon.litText)").font(.caption).foregroundStyle(palette.muted)
                }
                Text(night.basisLabel ?? String(localized:"Cloud forecast included")).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                // A place the Park Service does not run: Nyx cannot see its closures, and says so.
                if let unknown=ClosureLine.unknown(night.park) { Text(unknown).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
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
        .accessibilityLabel(Self.spoken(night,closure:closure))
    }
    /// What VoiceOver reads for the card: the closure first, as the dialog says it.
    static func spoken(_ night:Night,closure:String?)->String {
        ClosureLine.around(night.spokenSummary(.snippet),park:night.park,closure:closure)
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
            // The dial's track without a fill, as in the app: the score is the numeral's alone.
            Circle().trim(from:0.125,to:0.875).rotation(.degrees(90))
                .stroke(palette.ink.opacity(0.18),style:StrokeStyle(lineWidth:7,lineCap:.round,dash:hasForecast ? [] : [6,5]))
            VStack(spacing:0) {
                Text("\(score)").scoreNumeral(size:44,accent:palette.accent)
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
        AppShortcut(intent:DarkTonightIntent(),phrases:["When is it dark tonight in \(.applicationName)","When is it dark at \(\.$park) in \(.applicationName)","When does true darkness start at \(\.$park) in \(.applicationName)"],shortTitle:"True darkness",systemImageName:"moon.haze")
        AppShortcut(intent:WhatsUpTonightIntent(),phrases:["What's up tonight in \(.applicationName)","What's up tonight at \(\.$park) in \(.applicationName)","What can I see tonight at \(\.$park) with \(.applicationName)"],shortTitle:"What's up",systemImageName:"sparkles")
        // A park is optional: without one, field mode opens at the last park used in the field, else the starting park.
        AppShortcut(intent:StartFieldModeIntent(),phrases:["Start field mode at \(\.$park) in \(.applicationName)","I'm stargazing at \(\.$park) with \(.applicationName)","Start field mode in \(.applicationName)","I'm stargazing with \(.applicationName)"],shortTitle:"Field mode",systemImageName:"scope")
        AppShortcut(intent:FollowNightIntent(),phrases:["Follow tonight in \(.applicationName)","Follow tonight at \(\.$park) in \(.applicationName)","Put tonight on my Lock Screen with \(.applicationName)"],shortTitle:"Follow tonight",systemImageName:"lock.rectangle")
        AppShortcut(intent:UnfollowNightIntent(),phrases:["Stop following the night in \(.applicationName)","Stop following \(\.$park) in \(.applicationName)"],shortTitle:"Stop following",systemImageName:"moon.stars")
        AppShortcut(intent:NightVisionOnIntent(),phrases:["Turn on night vision in \(.applicationName)","Turn on \(.applicationName) night vision"],shortTitle:"Night vision",systemImageName:"flashlight.on.circle.fill")
        AppShortcut(intent:AddJournalEntryIntent(),phrases:["Add to my \(.applicationName) journal","Record a night in \(.applicationName)"],shortTitle:"Record a night",systemImageName:"book.closed")
    }
}
