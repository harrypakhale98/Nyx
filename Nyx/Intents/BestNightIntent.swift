import AppIntents
import SwiftUI

/// "Find the best night at Joshua Tree" from Siri, Shortcuts or Spotlight: the darkest night in a
/// range of up to 30 nights, at one park or across the saved parks, from the on-device score.
/// Answers with a short dialog and an interactive snippet (iOS 26).
struct FindBestNightIntent: AppIntent {
    static let title: LocalizedStringResource="Find the best night"
    static let description=IntentDescription("Finds the darkest night ahead at a national park, or across your saved parks, using Nyx's on-device darkness score. Clouds count only where a cached forecast reaches.")
    @Parameter(title:"Park",description:"Leave empty to compare your saved parks.") var park: ParkEntity?
    @Parameter(title:"Nights",description:"How many nights ahead to look, up to 30.",default:14,inclusiveRange:(1,30)) var nights: Int
    @Parameter(title:"Starting",description:"The first night to consider. Tonight if empty.") var start: Date?
    static var parameterSummary: some ParameterSummary {
        Summary("Find the best night at \(\.$park) in the next \(\.$nights) nights") { \.$start }
    }
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetIntent {
        let library=try ParkData.load()
        let saved=SharedSettings.read()
        let parks=park.map { chosen in library.filter { $0.id==chosen.id } } ?? (saved?.parks ?? [])
        guard !parks.isEmpty else {
            return .result(dialog:"Choose a park, or save parks in Nyx to compare them.",snippetIntent:EmptySnippetIntent())
        }
        let now=Date.now, day=start.map { TripDay($0) }
        let planner=NightPlanner(forecasts:BestNightSearch.forecasts(for:parks,shared:saved),details:BestNightSearch.details(for:parks,shared:saved))
        guard let answer=BestNightSearch.answer(parks:parks,planner:planner,day:day,nights:nights,now:now) else {
            return .result(dialog:"Nyx could not find those nights.",snippetIntent:EmptySnippetIntent())
        }
        BestNightBrowse.reset()
        var voiceOnly=false
        if #available(iOS 27.0,*) { voiceOnly=systemContext.isVoiceOnly }
        return .result(dialog:IntentDialog(stringLiteral:BestNightSearch.dialog(answer,voiceOnly:voiceOnly)),
                       snippetIntent:BestNightSnippetIntent(parkIDs:parks.map(\.id),start:start,nights:answer.count))
    }
}

/// The search and its words, apart from the intent so they can be tested.
nonisolated enum BestNightSearch {
    struct Answer: Sendable {
        /// Best first, at most five, so the snippet can step through the runners-up.
        let ranked: [Night]
        let count: Int
        var best: Night { ranked[0] }
    }
    static func answer(parks: [Park], planner: NightPlanner, from start: Date, nights: Int, now: Date) -> Answer? {
        let count=min(30,max(1,nights))
        let ranked=planner.bestNights(parks,from:start,count:count,now:now,limit:5)
        return ranked.isEmpty ? nil : Answer(ranked:ranked,count:count)
    }
    /// From the night of a picked day (the day as the person's calendar shows it, so a date
    /// picked at midnight or before a western park's sunrise never starts the night before),
    /// or from tonight when no day was picked.
    static func answer(parks: [Park], planner: NightPlanner, day: TripDay?, nights: Int, now: Date) -> Answer? {
        guard let day else { return answer(parks:parks,planner:planner,from:now,nights:nights,now:now) }
        let count=min(30,max(1,nights))
        let ranked=planner.bestNights(parks,day:DateComponents(year:day.year,month:day.month,day:day.day),count:count,now:now,limit:5)
        return ranked.isEmpty ? nil : Answer(ranked:ranked,count:count)
    }
    /// Each park's newest forecast: the one the widget shares, or the app's own cache.
    /// Smoke and cloud layers: the app's own cache, else what the widget was handed.
    static func details(for parks: [Park], shared: SavedSkySnapshot?) -> [String: ForecastDetail] {
        var result: [String: ForecastDetail]=[:]
        for park in parks { result[park.id]=CacheDirectory.read(ForecastDetail.self,name:"detail-\(park.id)") ?? shared?.details?[park.id] }
        return result
    }
    static func forecasts(for parks: [Park], shared: SavedSkySnapshot?) -> [String: Forecast] {
        var result: [String: Forecast]=[:]
        for park in parks {
            let candidates=[shared?.forecasts[park.id],CacheDirectory.read(Forecast.self,name:"weather-\(park.id)")].compactMap { $0 }
            result[park.id]=candidates.max { $0.updated<$1.updated }
        }
        return result
    }
    /// The full answer names the night, the score and what it rests on. Voice-only (iOS 27, no
    /// screen in view) keeps the night, the score and the one caveat that matters.
    static func dialog(_ answer: Answer, voiceOnly: Bool) -> String {
        let night=answer.best, park=night.park
        let day=park.programDate(park.isoDay(night.id))
        if voiceOnly {
            let basis=night.score.hasForecast ? "" : " "+(night.basis.isEarlyLook ? String(localized:"An early look at the clouds.") : night.withTypicalClouds(String(localized:"Clouds aren't forecast yet.")))
            return String(localized:"\(day) at \(park.shortName): \(night.score.value), \(night.score.band.label).")+basis
        }
        if night.sky.darkHours==0 {
            return String(localized:"No true darkness at \(park.shortName) in the next \(answer.count) nights. The best is \(day), \(night.score.value) out of 100.")
        }
        let basis=night.basisCaption(typical:true) ?? String(localized:"Includes a cached cloud forecast.")
        return String(localized:"The best of the next \(answer.count) nights: \(day) at \(park.shortName), \(night.score.value) out of 100, \(night.score.band.label). \(basis) Confirm park access before you go.")
    }
}

/// Which of the ranked nights the snippet shows; "Next best" steps through them. Kept in the
/// app's defaults because the snippet is rebuilt from its intent after every button.
nonisolated enum BestNightBrowse {
    static let key="bestNightSnippetRank"
    static func reset(_ defaults: UserDefaults = .standard) { defaults.set(0,forKey:key) }
    static func rank(_ defaults: UserDefaults = .standard) -> Int { defaults.integer(forKey:key) }
    static func advance(count: Int, _ defaults: UserDefaults = .standard) { defaults.set(count>0 ? (rank(defaults)+1)%count : 0,forKey:key) }
}

/// The interactive result card: the night, its score and Moon, with "Next best" and "Open in Nyx".
struct BestNightSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource="Best night"
    static let isDiscoverable=false
    @Parameter(title:"Parks") var parkIDs: [String]
    @Parameter(title:"Starting") var start: Date?
    @Parameter(title:"Nights") var nights: Int
    init() {}
    init(parkIDs: [String], start: Date?, nights: Int) { self.parkIDs=parkIDs; self.start=start; self.nights=nights }
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let parks=try ParkData.load().filter { parkIDs.contains($0.id) }
        let now=Date.now
        let shared=SharedSettings.read()
        let planner=NightPlanner(forecasts:BestNightSearch.forecasts(for:parks,shared:shared),details:BestNightSearch.details(for:parks,shared:shared))
        guard let answer=BestNightSearch.answer(parks:parks,planner:planner,day:start.map { TripDay($0) },nights:nights,now:now) else { return .result(view:EmptyView()) }
        let rank=min(BestNightBrowse.rank(),answer.ranked.count-1)
        return .result(view:BestNightSnippetView(night:answer.ranked[rank],rank:rank,total:answer.ranked.count,nights:answer.count))
    }
}
/// "Next best": steps the snippet to the next of the ranked nights, then back to the best.
struct NextBestNightIntent: AppIntent {
    static let title: LocalizedStringResource="Show the next best night"
    static let isDiscoverable=false
    @Parameter(title:"Count") var count: Int
    init() {}
    init(count: Int) { self.count=count }
    func perform() async throws -> some IntentResult {
        BestNightBrowse.advance(count:count)
        BestNightSnippetIntent.reload()
        return .result()
    }
}

struct BestNightSnippetView: View {
    let night: Night
    let rank: Int
    let total: Int
    let nights: Int
    private let palette=NyxPalette(nightVision:false,highContrast:false)
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:3) {
                    Text(rank==0 ? "BEST OF THE NEXT \(nights) NIGHTS" : "NUMBER \(rank+1) OF THE NEXT \(nights) NIGHTS")
                        .font(.caption2.weight(.medium)).tracking(1.4).foregroundStyle(palette.muted)
                    Text(night.park.shortName).font(.system(.title3,design:.serif))
                    Text(night.park.programDate(night.park.isoDay(night.id))).font(.subheadline).foregroundStyle(palette.muted)
                }
                Spacer(minLength:8)
                MoonDisc(illumination:night.sky.moon.illumination,waxing:night.sky.moon.waxing,southern:night.park.latitude<0)
                    .frame(width:44,height:44).accessibilityIgnoresInvertColors()
            }
            HStack(alignment:.firstTextBaseline,spacing:10) {
                Text("\(night.score.value)").font(.system(size:56,weight:.light,design:.serif)).foregroundStyle(palette.accent)
                VStack(alignment:.leading,spacing:2) {
                    Text(night.score.band.label).font(.system(.headline,design:.serif))
                    Text(night.basisLabel ?? String(localized:"Cached forecast included")).font(.caption).foregroundStyle(palette.muted)
                }
            }
            .accessibilityElement(children:.combine)
            if let typical=night.typicalClouds { Text(typical).font(.caption).foregroundStyle(palette.muted) }
            Text("\(night.sky.moon.name), \(Int((night.sky.moon.illumination*100).rounded()))% lit. Confirm park access before you go.").font(.caption).foregroundStyle(palette.muted)
            HStack(spacing:10) {
                if total>1 {
                    Button(intent:NextBestNightIntent(count:total)) { Label("Next best",systemImage:"arrow.forward") }
                        .accessibilityInputLabels([Text("Next best"),Text("Next")])
                }
                Button(intent:OpenParkIntent(target:ParkEntity(night.park))) { Label("Open in Nyx",systemImage:"arrow.up.forward.app") }
            }
            .buttonStyle(.bordered).tint(palette.accent).font(.subheadline)
        }
        .foregroundStyle(palette.ink)
        .padding(18)
        .background(LinearGradient(colors:[.black,Color(red:0.043,green:0.063,blue:0.149)],startPoint:.top,endPoint:.bottom),in:RoundedRectangle(cornerRadius:22))
        .environment(\.colorScheme,.dark)
    }
}
