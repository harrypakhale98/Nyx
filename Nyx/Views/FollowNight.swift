import AppIntents
import SwiftUI

// MARK: Follow this night

/// "Follow this night": the night's Live Activity, scheduled to start on the Lock Screen by itself
/// half an hour before sunset (`FieldActivityAttributes.followStart`), with no need to open Nyx and
/// no push server. Offered on a park's chosen night, in the calendar's night menu and in Siri's
/// best-night card. Not offered once the night is over, where Live Activities are off, or on a Mac.
struct FollowNightButton: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @AppStorage("nightVision",store:SharedSettings.defaults) private var nightVision=false
    let night: Night
    private var following: Bool { NightFollowing.shared.isFollowing(park:night.park,night:night.id) }
    private var start: Date { FieldActivityAttributes.followStart(night.sky) }
    var body: some View {
        if FollowNight.offered(night) {
            Button { Task { await FollowNight.toggle(night,closure:model.closure(night.park),nightVision:nightVision) } } label:{
                HStack(alignment:.firstTextBaseline,spacing:8) {
                    Image(systemName:following ? "moon.stars.fill" : "moon.stars").accessibilityHidden(true)
                    VStack(alignment:.leading,spacing:2) {
                        Text(following ? "Following this night" : "Follow this night").font(.subheadline)
                        Text(FollowNight.caption(night,following:following)).font(.caption).foregroundStyle(palette.muted)
                            .fixedSize(horizontal:false,vertical:true)
                    }
                    Spacer(minLength:8)
                    if following { Text("Stop").font(.subheadline).accessibilityHidden(true) }
                }
                .frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(palette.ink)
            .accessibilityLabel(following ? String(localized:"Stop following \(night.park.shortName) on \(night.park.dayLabel(night.id))")
                                          : String(localized:"Follow \(night.park.shortName) on \(night.park.dayLabel(night.id))"))
            .accessibilityValue(FollowNight.caption(night,following:following))
            .accessibilityHint(following ? "Removes the night from your Lock Screen." : "Puts the night's countdown on your Lock Screen before sunset, without opening Nyx.")
            .accessibilityInputLabels(following ? [Text("Stop following"),Text("Unfollow")] : [Text("Follow this night"),Text("Follow")])
            .sensoryFeedback(.selection,trigger:following)
            .task { NightFollowing.shared.reload() }
        }
    }
}
/// The same action for a context menu (the calendar's long-press on a night).
struct FollowNightMenuItem: View {
    @Environment(PlanModel.self) private var model
    @AppStorage("nightVision",store:SharedSettings.defaults) private var nightVision=false
    let night: Night
    var body: some View {
        if FollowNight.offered(night) {
            let following=NightFollowing.shared.isFollowing(park:night.park,night:night.id)
            Button(following ? "Stop following" : "Follow this night",systemImage:following ? "moon.stars.fill" : "moon.stars") {
                Task { await FollowNight.toggle(night,closure:model.closure(night.park),nightVision:nightVision) }
            }
        }
    }
}
@MainActor enum FollowNight {
    static func offered(_ night: Night, now: Date = .now) -> Bool {
        FieldPresenter.supported && FieldActivities.enabled && !FieldNight.isOver(night.sky,at:DebugScenario.date ?? now)
    }
    static func toggle(_ night: Night, closure: String?, nightVision: Bool) async {
        if NightFollowing.shared.isFollowing(park:night.park,night:night.id) { await FieldActivities.unfollow(park:night.park,night:night.id) }
        else { await FieldActivities.follow(night:night,closure:closure,nightVision:nightVision) }
    }
    /// "On your Lock Screen from 5:50 PM" (park time), or what following will do.
    static func caption(_ night: Night, following: Bool, now: Date = .now) -> String {
        let start=FieldActivityAttributes.followStart(night.sky), park=night.park
        if following { return start>now ? String(localized:"On your Lock Screen from \(park.time(start))") : String(localized:"On your Lock Screen now") }
        return start>now ? String(localized:"On your Lock Screen from \(park.time(start)), without opening Nyx") : String(localized:"On your Lock Screen now, until dawn")
    }
}

/// "Follow tonight": puts a night's countdown on the Lock Screen, from Siri, Shortcuts or the
/// best-night card. Only ever follows; `UnfollowNightIntent` stops. A Live Activity intent, so it
/// may start or schedule the activity while Nyx stays in the background. Without a park, the night
/// under way or the starting park; without a night, tonight.
struct FollowNightIntent: LiveActivityIntent {
    static let title: LocalizedStringResource="Follow a night"
    static let description=IntentDescription("Puts a night's countdown at a park or dark-sky place on your Lock Screen. It starts by itself before sunset; Nyx does not need to be open.")
    @Parameter(title:"Park",description:"Leave empty for your starting park.") var park: ParkEntity?
    @Parameter(title:"Night",description:"Tonight if empty.") var night: Date?
    static var parameterSummary: some ParameterSummary { Summary("Follow \(\.$park) on \(\.$night)") }
    init() {}
    init(park: ParkEntity, night: Date) { self.park=park; self.night=night }
    // Live Activity intents run outside the main actor; following reads and changes the app's night list there.
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let shared=await SharedSettings.load()
        let chosen=try IntentPark.resolve(park,snapshot:shared)
        let now=Date.now
        let planner=NightPlanner(forecasts:BestNightSearch.forecasts(for:[chosen],shared:shared),details:BestNightSearch.details(for:[chosen],shared:shared))
        let found=planner.night(chosen,on:night.map { FollowNightWords.evening(of:$0,at:chosen) } ?? chosen.currentNight(at:now),now:now)
        let result=await FieldActivities.follow(night:found,closure:IntentClosure.closure(chosen,shared:shared),nightVision:SharedSettings.defaults.bool(forKey:"nightVision"),now:now)
        BestNightSnippetIntent.reload()
        return .result(dialog:IntentDialog(stringLiteral:FollowNightWords.followed(result,park:chosen,night:found.id)))
    }
}

/// "Stop following": ends a followed night, scheduled or running. Without a park or a night, the
/// soonest night followed; with a park alone, that park's soonest.
struct UnfollowNightIntent: LiveActivityIntent {
    static let title: LocalizedStringResource="Stop following a night"
    static let description=IntentDescription("Takes a followed night off your Lock Screen. Leave the park empty for the soonest night you follow.")
    @Parameter(title:"Park",description:"Leave empty for the soonest night you follow.") var park: ParkEntity?
    @Parameter(title:"Night",description:"Leave empty for the park's soonest followed night.") var night: Date?
    static var parameterSummary: some ParameterSummary { Summary("Stop following \(\.$park) on \(\.$night)") }
    init() {}
    init(park: ParkEntity, night: Date) { self.park=park; self.night=night }
    // Live Activity intents run outside the main actor; following reads and changes the app's night list there.
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        // Every place a night can be followed at, as Follow a night finds them: the parks, saved
        // spots and places abroad followed, then any catalogue place by id.
        let shared=await SharedSettings.load()
        let library=try ParkLibrary.places(snapshot:shared)
        let find:(String)->Park?={ id in library.first(where:{ $0.id==id }) ?? ParkLibrary.place(id,snapshot:shared) }
        var named: Park?
        if let park { guard let found=find(park.id) else { throw NyxIntentError.parkNotFound }; named=found }
        NightFollowing.shared.reload()
        let followed=FollowNightWords.followed(NightFollowing.shared.nights.map(\.attributes),named:night,now:.now,find:find)
        let target=FollowNightWords.target(followed,park:named,night:night)
        if let target { await FieldActivities.unfollow(park:target.park,night:target.night) }
        BestNightSnippetIntent.reload()
        return .result(dialog:IntentDialog(stringLiteral:FollowNightWords.unfollowed(target,park:named)))
    }
}

/// What following and unfollowing say, for every outcome, apart from the intents so it can be tested.
enum FollowNightWords {
    /// "Friday, October 16", the night's evening in the park's calendar.
    static func day(_ park: Park, _ night: Date) -> String { park.programDate(park.isoDay(night)) }
    /// The park's evening for a night given as a date: a night's own evening (the best-night card's
    /// button) as it is, any other date as the day the person's calendar shows it, as Find the best
    /// night reads a picked day, so a date picked at midnight never follows the night before.
    static func evening(of date: Date, at park: Park, calendar: Calendar = .current) -> Date {
        let exact=park.evening(date)
        if exact==date { return exact }
        let day=TripDay(date,calendar:calendar)
        return park.calendar.date(from:DateComponents(year:day.year,month:day.month,day:day.day,hour:12)) ?? exact
    }
    static func followed(_ result: FieldActivities.FollowResult, park: Park, night: Date) -> String {
        let name=park.shortName, day=Self.day(park,night)
        switch result {
        case .scheduled(let start):
            return Phrase.sentences([String(localized:"Following \(name) on \(day)."),Phrase.ended(String(localized:"On your Lock Screen from \(park.time(start)), without opening Nyx"))])
        case .started:
            return Phrase.sentences([String(localized:"Following \(name) on \(day)."),Phrase.ended(String(localized:"On your Lock Screen now, until dawn"))])
        case .alreadyFollowing:
            return String(localized:"You are already following \(name) on \(day).")
        case .over:
            return String(localized:"The night of \(day) at \(name) is over, so there is nothing to follow.")
        case .unavailable:
            return String(localized:"Nyx could not put this night on your Lock Screen. Live Activities may be off for Nyx in Settings.")
        }
    }
    /// The followed nights with their places, soonest first. Without a named night, one whose dawn
    /// has passed (a stale activity iOS has not ended yet) is left out: the night still ahead is the
    /// one to stop. A night whose place cannot be found any more is left out too.
    static func followed(_ nights: [FieldActivityAttributes], named night: Date?, now: Date, find: (String) -> Park?) -> [(park: Park, night: Date)] {
        nights.filter { night != nil || $0.dawn>now }.compactMap { item in
            guard let park=find(item.parkID) else { return nil }
            return (park,item.nightID ?? park.evening(item.dusk))
        }
    }
    /// The followed night to stop: the one named, else the park's soonest, else the soonest of all.
    /// `followed` is in the order ActivityKit's nights are kept (soonest sunset first).
    static func target(_ followed: [(park: Park, night: Date)], park: Park?, night: Date?, calendar: Calendar = .current) -> (park: Park, night: Date)? {
        followed.first { item in
            (park.map { $0.id==item.park.id } ?? true) && (night.map { evening(of:$0,at:item.park,calendar:calendar)==item.night } ?? true)
        }
    }
    static func unfollowed(_ target: (park: Park, night: Date)?, park: Park?) -> String {
        if let target { return String(localized:"Stopped following \(target.park.shortName) on \(day(target.park,target.night)). It is off your Lock Screen.") }
        if let park { return String(localized:"You are not following a night at \(park.shortName).") }
        return String(localized:"You are not following any nights.")
    }
}

// MARK: The night in progress

/// iOS 26.1's tab bar accessory while a followed night is under way (from three hours before
/// sunset until dawn): "Joshua Tree · True darkness in 14 min ›". A tap opens field mode for that
/// park. Nothing on iOS 26.0, where the accessory cannot be switched off once shown.
struct NightInProgressAccessory: ViewModifier {
    let open: (String) -> Void
    @State private var now=Date.now
    func body(content: Content) -> some View {
        let night=NightFollowing.shared.inProgress(at:now)
        Group {
            if #available(iOS 26.1, *) {
                content.tabViewBottomAccessory(isEnabled:night != nil) {
                    if let night { NightInProgressStrip(followed:night) { open(night.attributes.parkID) } }
                }
            } else { content }
        }
        .task {
            NightFollowing.shared.reload()
            while !Task.isCancelled { try? await Task.sleep(for:.seconds(60)); now = .now }
        }
    }
}
/// The strip itself: the park, then the next moment and how long until it, minute by minute.
/// Compact when the tab bar has shrunk beside it (`.inline`). Glass from the tab bar; a solid
/// black capsule in night vision and under Reduce Transparency, where glass costs contrast.
struct NightInProgressStrip: View {
    @Environment(\.nyx) private var palette
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let followed: NightFollowing.Followed
    let open: () -> Void
    var body: some View {
        TimelineView(.everyMinute) { context in
            let status=NightStatus(followed.attributes,at:context.date)
            Button(action:open) {
                HStack(spacing:8) {
                    Image(systemName:status.symbol).foregroundStyle(palette.ink).accessibilityHidden(true)
                    if placement == .inline {
                        Text(status.short).font(.subheadline.weight(.medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    } else {
                        Text("\(Text(followed.attributes.parkName).fontWeight(.semibold)) · \(status.line)").font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength:4)
                        Image(systemName:"chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(palette.muted).accessibilityHidden(true)
                    }
                }
                .foregroundStyle(palette.ink)
                .padding(.horizontal,placement == .inline ? 10 : 16).frame(maxWidth:.infinity,maxHeight:.infinity)
                .background { if palette.nightVision || reduceTransparency { Capsule().fill(Color.black).overlay(Capsule().stroke(palette.line,lineWidth:0.8)) } }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized:"\(followed.attributes.parkName) tonight. \(status.line)"))
            .accessibilityHint("Opens field mode.")
            .accessibilityInputLabels([Text("Field mode"),Text(followed.attributes.parkName)])
            .contextMenu {
                Button("Stop following",systemImage:"moon.stars") {
                    Task {
                        for activity in FieldActivities.Item.activities where activity.attributes.covers(parkID:followed.attributes.parkID,night:followed.attributes.nightID ?? followed.attributes.dusk) {
                            await activity.end(nil,dismissalPolicy:.immediate)
                        }
                        NightFollowing.shared.reload()
                    }
                }
            }
        }
    }
}
/// What the strip says at a moment of a followed night, worked out from the activity's own
/// milestones: sunset before it, then each milestone, then sunrise. Counted in whole minutes.
nonisolated struct NightStatus: Equatable, Sendable {
    let line: String
    let short: String
    let symbol: String
    init(_ attributes: FieldActivityAttributes, at now: Date) {
        func until(_ date: Date) -> String { NightStatus.duration(date.timeIntervalSince(now)) }
        if now<attributes.dusk {
            line=String(localized:"Sunset in \(until(attributes.dusk))"); short=until(attributes.dusk); symbol="sunset"
        } else if let next=attributes.milestones.first(where:{ $0.date>now }) {
            line=String(localized:"\(next.title) in \(until(next.date))"); short=until(next.date); symbol=next.symbol
        } else {
            var format=Date.FormatStyle.dateTime.hour().minute()
            format.timeZone=attributes.timeZone
            line=String(localized:"Sunrise at \(attributes.dawn.formatted(format))"); short=attributes.dawn.formatted(format); symbol="sunrise"
        }
    }
    /// "14 min", "1 hr, 20 min": rounded up to the minute, never seconds.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes=max(1,Int((seconds/60).rounded(.up)))
        return Duration.seconds(minutes*60).formatted(.units(allowed:[.hours,.minutes],width:.abbreviated))
    }
}

#if DEBUG
/// `-nyx-following`: tonight at the starting park as a followed night under way, so captures show
/// the tab bar accessory and the "Following this night" rows without a real Live Activity.
@MainActor enum DebugFollowing {
    static var fixture: NightFollowing.Followed?
    static func install(_ model: PlanModel) {
        guard DebugScenario.isEnabled("following"), let park=model.home else { return }
        let night=model.night(park)
        fixture=NightFollowing.Followed(attributes:FieldActivityAttributes(night:FieldNight(park:park,sky:night.sky),score:night.score.value,band:night.score.band.label,closure:model.closure(park)),started:true)
        NightFollowing.shared.reload()
    }
}
#Preview("Night in progress") {
    let attributes=FieldActivityAttributes.preview
    NightInProgressStrip(followed:NightFollowing.Followed(attributes:attributes,started:true)) {}
        .frame(height:48).padding().background(.black).preferredColorScheme(.dark)
}
#endif
