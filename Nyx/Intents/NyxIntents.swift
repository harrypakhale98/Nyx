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
        try await SpotlightIndexer.index(ParkData.load().filter { identifiers.contains($0.id) })
    }
    func reindexAllEntities(indexDescription:CSSearchableIndexDescription) async throws {
        try await SpotlightIndexer.index(ParkData.load())
    }
}
/// What Siri and Shortcuts say when an intent cannot answer, in the same calm words as the app.
enum NyxIntentError:Error,CustomLocalizedStringResourceConvertible {
    case parkNotFound, noParks, noNights, journalUnavailable
    var localizedStringResource:LocalizedStringResource {
        switch self {
        case .parkNotFound: "That park could not be found in the bundled library."
        case .noParks: "Choose a park, or save parks in Nyx to compare them."
        case .noNights: "Nyx could not find those nights."
        case .journalUnavailable: "Your journal could not be opened, so nothing was read or saved. The Journal tab in Nyx says more."
        }
    }
}
/// "What's the darkness score at Joshua Tree tonight?" Answers in words, with a card (the score
/// on a still dial, the Moon, what the clouds rest on), and returns the score so Shortcuts can use it.
struct DarknessIntent:AppIntent {
    static let title:LocalizedStringResource="Tonight's darkness score"
    static let description=IntentDescription("Find the on-device darkness estimate for a national park. Returns the score, 0 to 100.")
    @Parameter(title:"Park") var park:ParkEntity
    static var parameterSummary:some ParameterSummary { Summary("Darkness at \(\.$park) tonight") }
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog & ShowsSnippetView {
        guard let selected=try ParkData.load().first(where:{$0.id==park.id}) else { throw NyxIntentError.parkNotFound }
        // Saved parks share their forecast with the widget; the app's own cache may be newer.
        let shared=SharedSettings.read()
        var voiceOnly=false
        if #available(iOS 27.0,*) { voiceOnly=systemContext.isVoiceOnly }
        // The park's closure from the app's last park update, said before the score.
        let answer=DarknessAnswer(park:selected,forecast:BestNightSearch.forecasts(for:[selected],shared:shared)[selected.id],
                                  detail:BestNightSearch.details(for:[selected],shared:shared)[selected.id],closure:shared?.closures[selected.id],now:.now,voiceOnly:voiceOnly)
        return .result(value:answer.night.score.value,dialog:IntentDialog(stringLiteral:answer.dialog),view:DarknessSnippetView(night:answer.night))
    }
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
        let park=night.park, score=night.score
        let body:String
        if night.sky.darkHours==0 { body=String(localized:"No true darkness tonight at \(park.shortName). The darkness score is \(score.value) out of 100.") }
        else if voiceOnly {
            let basis=score.hasForecast ? "" : " "+(night.basis.isEarlyLook ? String(localized:"An early look at the clouds.") : night.withTypicalClouds(String(localized:"Clouds aren't forecast yet.")))
            let tonight=String(localized:"Tonight")
            body=String(localized:"\(tonight) at \(park.shortName): \(score.value), \(score.band.label).")+basis
        }
        else if let caption=night.basisCaption() { body=String(localized:"\(park.shortName): \(score.value) out of 100, \(score.band.label). \(caption) Confirm conditions and park access before traveling.") }
        else { body=String(localized:"\(park.shortName): \(score.value) out of 100, \(score.band.label). Includes a cached cloud forecast. Confirm conditions and park access before traveling.") }
        guard let closure=closure?.trimmingCharacters(in:.whitespacesAndNewlines), !closure.isEmpty else { return body }
        return sentence(String(localized:"Closure alert: \(closure)"))+" "+body
    }
    /// An NPS headline usually ends without a full stop; one is added so the score reads as its own sentence.
    static func sentence(_ text:String)->String { text.last.map { ".!?…".contains($0) } == true ? text : text+"." }
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
                Text("Tonight").textCase(.uppercase).font(.caption2.weight(.medium)).tracking(1.4).foregroundStyle(palette.muted)
                Text(night.park.shortName).font(.system(.title3,design:.serif)).fixedSize(horizontal:false,vertical:true)
                Text(night.score.band.label).font(.system(.headline,design:.serif)).foregroundStyle(palette.accent)
                HStack(spacing:8) {
                    MoonDisc(illumination:night.sky.moon.illumination,waxing:night.sky.moon.waxing,southern:night.park.latitude<0)
                        .frame(width:22,height:22).accessibilityIgnoresInvertColors()
                    Text("\(night.sky.moon.name), \(Int((night.sky.moon.illumination*100).rounded()))% lit").font(.caption).foregroundStyle(palette.muted)
                }
                Text(night.basisLabel ?? String(localized:"Cached forecast included")).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            }
            Spacer(minLength:0)
        }
        .foregroundStyle(palette.ink)
        .padding(18)
        .background(LinearGradient(colors:[.black,palette.panel],startPoint:.top,endPoint:.bottom),in:RoundedRectangle(cornerRadius:22))
        .environment(\.nyx,palette)
        .modifier(NightVisionFilter(enabled:palette.nightVision,red:palette.red))
        .environment(\.colorScheme,.dark)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(String(localized:"\(night.park.shortName) tonight: \(night.score.value) out of 100, \(night.score.band.label). \(night.sky.moon.name), \(Int((night.sky.moon.illumination*100).rounded())) percent lit."))
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
struct NyxShortcuts:AppShortcutsProvider {
    static var appShortcuts:[AppShortcut] {
        AppShortcut(intent:DarknessIntent(),phrases:["What is the darkness score at \(\.$park) in \(.applicationName)","Check tonight's sky at \(\.$park) with \(.applicationName)"],shortTitle:"Tonight's sky",systemImageName:"moon.stars")
        AppShortcut(intent:FindBestNightIntent(),phrases:["Find the best night at \(\.$park) with \(.applicationName)","When is the darkest night at \(\.$park) in \(.applicationName)","Find the best night for stars with \(.applicationName)"],shortTitle:"Best night",systemImageName:"calendar")
        AppShortcut(intent:StartFieldModeIntent(),phrases:["Start field mode at \(\.$park) in \(.applicationName)","I'm stargazing at \(\.$park) with \(.applicationName)"],shortTitle:"Field mode",systemImageName:"scope")
        AppShortcut(intent:AddJournalEntryIntent(),phrases:["Add to my \(.applicationName) journal","Record a night in \(.applicationName)"],shortTitle:"Record a night",systemImageName:"book.closed")
    }
}
