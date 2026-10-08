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
        let answer=DarknessAnswer(park:selected,forecast:BestNightSearch.forecasts(for:[selected],shared:shared)[selected.id],
                                  detail:BestNightSearch.details(for:[selected],shared:shared)[selected.id],now:.now)
        return .result(value:answer.night.score.value,dialog:IntentDialog(stringLiteral:answer.dialog),view:DarknessSnippetView(night:answer.night))
    }
}
/// The darkness answer apart from the intent, so its words and value can be tested.
nonisolated struct DarknessAnswer:Sendable {
    let night:Night
    let dialog:String
    init(park:Park,forecast:Forecast?,detail:ForecastDetail?,now:Date) {
        let sky=AstronomyEngine().conditions(for:park,on:park.currentNight(at:now))
        night=NightPlanner.night(park:park,sky:sky,forecast:forecast,detail:detail,now:now)
        let score=night.score
        if sky.darkHours==0 { dialog=String(localized:"No true darkness tonight at \(park.shortName). The darkness score is \(score.value) out of 100.") }
        else if let caption=night.basisCaption() { dialog=String(localized:"\(park.shortName): \(score.value) out of 100, \(score.band.label). \(caption) Confirm conditions and park access before traveling.") }
        else { dialog=String(localized:"\(park.shortName): \(score.value) out of 100, \(score.band.label). Includes a cached cloud forecast. Confirm conditions and park access before traveling.") }
    }
}
/// Siri's card for tonight's score: the score on a still dial (Siri shows a snapshot, so nothing
/// counts up), the Moon as it is tonight, and what the clouds rest on.
struct DarknessSnippetView:View {
    let night:Night
    private let palette=NyxPalette(nightVision:false,highContrast:false)
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
        .background(LinearGradient(colors:[.black,Color(red:0.043,green:0.063,blue:0.149)],startPoint:.top,endPoint:.bottom),in:RoundedRectangle(cornerRadius:22))
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
