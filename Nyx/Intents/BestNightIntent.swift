import AppIntents
import SwiftUI

/// "Find the best night at Joshua Tree" from Siri, Shortcuts or Spotlight: the darkest night in a
/// range of up to 30 nights, at one park or across the saved parks, from the on-device score.
/// Answers with a short dialog and an interactive snippet (iOS 26).
struct FindBestNightIntent: AppIntent {
    static let title: LocalizedStringResource="Find the best night"
    static let description=IntentDescription("Finds the darkest night ahead at a park or dark-sky place, or across your saved parks, using Nyx's on-device darkness score. Clouds count only where a cached forecast reaches.")
    @Parameter(title:"Park",description:"Leave empty to compare your saved parks.") var park: ParkEntity?
    @Parameter(title:"Nights",description:"How many nights ahead to look, up to 30.",default:14,inclusiveRange:(1,30)) var nights: Int
    @Parameter(title:"Starting",description:"The first night to consider. Tonight if empty.") var start: Date?
    static var parameterSummary: some ParameterSummary {
        Summary("Find the best night at \(\.$park) in the next \(\.$nights) nights") { \.$start }
    }
    init() {}
    /// Returns the moment the best night's true darkness begins (sunset where there is none), so a
    /// shortcut can put it in a calendar or a reminder.
    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog & ShowsSnippetIntent {
        let saved=SharedSettings.read()
        let library=try ParkLibrary.places(snapshot:saved)
        // A chosen place the library lacks (a world catalogue place found by search, not followed) resolves by its id.
        let parks=park.map { chosen in (library.first { $0.id==chosen.id } ?? ParkLibrary.place(chosen.id,snapshot:saved)).map { [$0] } ?? [] } ?? (saved?.parks ?? [])
        guard !parks.isEmpty else { throw park == nil ? NyxIntentError.noParks : NyxIntentError.parkNotFound }
        let now=Date.now, day=start.map { TripDay($0) }
        let planner=NightPlanner(forecasts:BestNightSearch.forecasts(for:parks,shared:saved),details:BestNightSearch.details(for:parks,shared:saved))
        guard let answer=BestNightSearch.answer(parks:parks,planner:planner,day:day,nights:nights,now:now) else { throw NyxIntentError.noNights }
        BestNightBrowse.reset()
        var voiceOnly=false
        if #available(iOS 27.0,*) { voiceOnly=systemContext.isVoiceOnly }
        return .result(value:BestNightSearch.value(answer),dialog:IntentDialog(stringLiteral:BestNightSearch.dialog(answer,voiceOnly:voiceOnly,closure:IntentClosure.closure(answer.best.park,shared:saved))),
                       snippetIntent:BestNightSnippetIntent(parkIDs:parks.map(\.id),start:start,nights:answer.count))
    }
}

/// The search and its words, apart from the intent so they can be tested.
nonisolated enum BestNightSearch {
    struct Answer: Sendable {
        /// Best first, at most five, so the snippet can step through the runners-up.
        let ranked: [Night]
        let count: Int
        /// No night searched has any true darkness (not only the best): only then does the answer say so.
        let noDarkness: Bool
        var best: Night { ranked[0] }
        /// `nights`: every night searched, best first; the answer keeps the first five.
        init(nights: [Night], count: Int) {
            ranked=Array(nights.prefix(5)); self.count=count
            noDarkness=nights.allSatisfy { $0.sky.darkHours==0 }
        }
    }
    static func answer(parks: [Park], planner: NightPlanner, from start: Date, nights: Int, now: Date) -> Answer? {
        let count=min(30,max(1,nights))
        let all=planner.bestNights(parks,from:start,count:count,now:now,limit:.max)
        return all.isEmpty ? nil : Answer(nights:all,count:count)
    }
    /// From the night of a picked day (the day as the person's calendar shows it, so a date
    /// picked at midnight or before a western park's sunrise never starts the night before),
    /// or from tonight when no day was picked.
    static func answer(parks: [Park], planner: NightPlanner, day: TripDay?, nights: Int, now: Date) -> Answer? {
        guard let day else { return answer(parks:parks,planner:planner,from:now,nights:nights,now:now) }
        let count=min(30,max(1,nights))
        let all=planner.bestNights(parks,day:DateComponents(year:day.year,month:day.month,day:day.day),count:count,now:now,limit:.max)
        return all.isEmpty ? nil : Answer(nights:all,count:count)
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
            // The name the forecast client writes: "weather-jotr" for a park, no colon for a place abroad or a spot.
            let candidates=[shared?.forecasts[park.id],CacheDirectory.read(Forecast.self,name:SpotForecast.cacheName(park.id))].compactMap { $0 }
            result[park.id]=candidates.max { $0.updated<$1.updated }
        }
        return result
    }
    /// The intent's value: when the best night's true darkness begins, or its sunset (or evening)
    /// where the Sun never goes far enough down.
    static func value(_ answer: Answer) -> Date {
        let sky=answer.best.sky
        return sky.darkStart ?? sky.sunset ?? sky.evening
    }
    /// The full answer names the night, the score and what it rests on. Voice-only (iOS 27, no
    /// screen in view) keeps the night, the score and the one caveat that matters. At a place the Park
    /// Service does not run, it ends by saying Nyx cannot check closures there. `closure`: the best
    /// night's park's closure, said first.
    static func dialog(_ answer: Answer, voiceOnly: Bool, closure: String? = nil) -> String {
        DarknessAnswer.withClosures(answer.best.spokenSummary(.siriBest(count:answer.count,voiceOnly:voiceOnly,noDarkness:answer.noDarkness)),park:answer.best.park,closure:closure)
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
        let shared=SharedSettings.read()
        let library=try ParkLibrary.places(snapshot:shared)
        let known=library.filter { parkIDs.contains($0.id) }
        // An unfollowed world catalogue place the answer was about resolves by its id, as it did for the answer.
        let parks=known+parkIDs.filter { id in !known.contains { $0.id==id } }.compactMap { ParkLibrary.place($0,snapshot:shared) }
        let now=Date.now
        let planner=NightPlanner(forecasts:BestNightSearch.forecasts(for:parks,shared:shared),details:BestNightSearch.details(for:parks,shared:shared))
        // Nothing left to show (the nights have passed since Siri first answered): a calm card that
        // says so and offers Nyx, never an empty one.
        guard let answer=BestNightSearch.answer(parks:parks,planner:planner,day:start.map { TripDay($0) },nights:nights,now:now) else {
            return .result(view:BestNightEmptySnippetView(parkID:parks.count==1 ? parks.first?.id : nil))
        }
        let rank=min(BestNightBrowse.rank(),answer.ranked.count-1)
        let night=answer.ranked[rank]
        // "Follow this night" where Live Activities are on and the night is still ahead.
        let follow: Bool?=FieldActivities.enabled && !FieldNight.isOver(night.sky,at:now) ? FieldActivities.isFollowing(park:night.park,night:night.id) : nil
        return .result(view:BestNightSnippetView(night:night,rank:rank,total:answer.ranked.count,nights:answer.count,following:follow))
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
    /// Whether this night is followed on the Lock Screen; nil where following is not offered.
    var following: Bool?=nil
    @Environment(\.colorSchemeContrast) private var contrast
    /// The hero numeral follows Dynamic Type, held to a size the card can carry.
    @ScaledMetric(relativeTo:.largeTitle) private var numeral=56.0
    /// The app's night look, so a night-vision evening is not lit up by a white card.
    private var palette: NyxPalette { NightLook(contrast:contrast).palette }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:3) {
                    Text(rank==0 ? "Best of the next \(nights) nights" : "Number \(rank+1) of the next \(nights) nights")
                        .textCase(Lettering.spaced ? .uppercase : nil).font(.caption2.weight(.medium)).tracking(Lettering.spaced ? 1.4 : 0).foregroundStyle(palette.muted)
                    Text(night.park.shortName).font(.system(.title3,design:.serif))
                    Text(night.park.programDate(night.park.isoDay(night.id))).font(.subheadline).foregroundStyle(palette.muted)
                }
                Spacer(minLength:8)
                MoonDisc(illumination:night.sky.moon.illumination,waxing:night.sky.moon.waxing,southern:night.park.latitude<0)
                    .frame(width:44,height:44).accessibilityIgnoresInvertColors()
            }
            HStack(alignment:.firstTextBaseline,spacing:10) {
                Text("\(night.score.value)").font(.system(size:min(numeral,76),weight:.light,design:.serif)).foregroundStyle(palette.accent)
                VStack(alignment:.leading,spacing:2) {
                    Text(night.score.band.label).font(.system(.headline,design:.serif))
                    Text(night.basisLabel ?? String(localized:"Cached forecast included")).font(.caption).foregroundStyle(palette.muted)
                }
            }
            .accessibilityElement(children:.combine)
            if let typical=night.typicalClouds { Text(typical).font(.caption).foregroundStyle(palette.muted) }
            // A place the Park Service does not run: Nyx cannot see its closures, and says so instead.
            if let unknown=DarknessAnswer.unknownClosures(night.park) {
                Text("\(night.sky.moon.name), \(Percent.text(Int((night.sky.moon.illumination*100).rounded()))) lit").font(.caption).foregroundStyle(palette.muted)
                Text(unknown).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            } else {
                Text("\(night.sky.moon.name), \(Percent.text(Int((night.sky.moon.illumination*100).rounded()))) lit. Confirm park access before you go.").font(.caption).foregroundStyle(palette.muted)
            }
            HStack(spacing:10) {
                if total>1 {
                    Button(intent:NextBestNightIntent(count:total)) { Label("Next best",systemImage:"arrow.forward") }
                        .accessibilityInputLabels([Text("Next best"),Text("Next")])
                }
                Button(intent:OpenParkIntent(target:ParkEntity(night.park))) { Label("Open in Nyx",systemImage:"arrow.up.forward.app") }
            }
            .buttonStyle(.bordered).tint(palette.accent).font(.subheadline)
            if let following {
                // Puts the night on the Lock Screen before its sunset, with no need to open Nyx; the
                // same place stops following. Two intents, so a repeated tap never undoes itself.
                Group {
                    if following {
                        Button(intent:UnfollowNightIntent(park:ParkEntity(night.park),night:night.id)) { Label("Following. Stop",systemImage:"moon.stars.fill") }
                            .accessibilityLabel("Stop following this night")
                            .accessibilityHint("Removes the night from your Lock Screen.")
                    } else {
                        Button(intent:FollowNightIntent(park:ParkEntity(night.park),night:night.id)) { Label("Follow this night",systemImage:"moon.stars") }
                            .accessibilityLabel("Follow this night")
                            .accessibilityHint("Puts the night's countdown on your Lock Screen before sunset.")
                    }
                }
                .buttonStyle(.bordered).tint(palette.accent).font(.subheadline)
            }
        }
        .foregroundStyle(palette.ink)
        .padding(18)
        .background(palette.snippetBackground,in:RoundedRectangle(cornerRadius:22))
        .environment(\.nyx,palette)
        .modifier(NightVisionFilter(enabled:palette.nightVision,red:palette.red))
        .environment(\.colorScheme,.dark)
    }
}

/// The best-night card when there is no night to show: what happened, in the app's words, and a
/// way into Nyx (the park, when there was one, else Tonight). Drawn in the app's night look.
struct BestNightEmptySnippetView: View {
    var parkID: String?=nil
    @Environment(\.colorSchemeContrast) private var contrast
    private var palette: NyxPalette { NightLook(contrast:contrast).palette }
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(alignment:.firstTextBaseline,spacing:8) {
                Image(systemName:"moon").foregroundStyle(palette.accent).accessibilityHidden(true)
                Text("No night to show").font(.system(.headline,design:.serif))
            }
            Text("Nyx could not find those nights. They may have passed; ask again for the nights ahead.")
                .font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            Button(intent:OpenTonightParkIntent(parkID:parkID)) { Label("Open in Nyx",systemImage:"arrow.up.forward.app") }
                .buttonStyle(.bordered).tint(palette.accent).font(.subheadline)
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .foregroundStyle(palette.ink)
        .padding(18)
        .background(palette.snippetBackground,in:RoundedRectangle(cornerRadius:22))
        .environment(\.nyx,palette)
        .modifier(NightVisionFilter(enabled:palette.nightVision,red:palette.red))
        .environment(\.colorScheme,.dark)
    }
}
#Preview("Best night, nothing to show") {
    BestNightEmptySnippetView().padding()
}
