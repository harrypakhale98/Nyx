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
            .buttonStyle(.plain).foregroundStyle(palette.accent)
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

/// Follows (or stops following) a night from Siri's best-night card. A Live Activity intent, so it
/// may start or schedule the activity while Nyx stays in the background.
struct FollowNightIntent: LiveActivityIntent {
    static let title: LocalizedStringResource="Follow a night"
    static let description=IntentDescription("Puts a night's countdown at a national park on your Lock Screen. It starts by itself before sunset; Nyx does not need to be open.")
    static let isDiscoverable=false
    @Parameter(title:"Park") var park: ParkEntity
    @Parameter(title:"Night") var night: Date
    init() {}
    init(park: ParkEntity, night: Date) { self.park=park; self.night=night }
    func perform() async throws -> some IntentResult {
        guard let chosen=try ParkData.load().first(where:{ $0.id==park.id }) else { return .result() }
        let shared=SharedSettings.read()
        let planner=NightPlanner(forecasts:BestNightSearch.forecasts(for:[chosen],shared:shared),details:BestNightSearch.details(for:[chosen],shared:shared))
        let found=planner.night(chosen,on:chosen.evening(night),now:.now)
        if FieldActivities.isFollowing(park:chosen,night:found.id) { await FieldActivities.unfollow(park:chosen,night:found.id) }
        else { await FieldActivities.follow(night:found,closure:shared?.closures[chosen.id],nightVision:SharedSettings.defaults.bool(forKey:"nightVision")) }
        BestNightSnippetIntent.reload()
        return .result()
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
                    Image(systemName:status.symbol).foregroundStyle(palette.accent).accessibilityHidden(true)
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
