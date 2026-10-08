import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

/// The night in the field, on the Lock Screen, in the Dynamic Island and in StandBy (whose night
/// mode already turns it red), and in its small family on Apple Watch's Smart Stack and CarPlay.
struct FieldLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for:FieldActivityAttributes.self) { context in
            FieldActivityFace(attributes:context.attributes,state:context.state,isStale:context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.88))
                .activitySystemActionForegroundColor(FieldActivityColors(nightVision:context.state.nightVision).ink)
                .widgetURL(URL(string:"nyx://field/\(context.attributes.parkID)"))
        } dynamicIsland: { context in
            let colors=FieldActivityColors(nightVision:context.state.nightVision)
            // One milestone for title, symbol and countdown, so a stale activity never names one moment and times another.
            let mark=FieldActivityMark(attributes:context.attributes,state:context.state,isStale:context.isStale)
            let zone=context.attributes.timeZone
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    // A long title drops below the camera rather than truncating beside it.
                    Label { Text(mark.title).lineLimit(2).minimumScaleFactor(0.75) } icon:{ FieldActivitySymbol(attributes:context.attributes,state:context.state,isStale:context.isStale).accessibilityHidden(true) }
                        .font(.system(.subheadline,design:.serif)).foregroundStyle(colors.ink)
                        .dynamicIsland(verticalPlacement:.belowIfTooWide)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FieldActivityCountdown(attributes:context.attributes,state:context.state,isStale:context.isStale,font:.system(.title3,design:.serif),maxWidth:110,compact:false)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment:.leading,spacing:6) {
                        FieldNightLine(attributes:context.attributes,colors:colors).frame(height:14)
                        if context.isStale && !context.state.finished {
                            FieldActivityUpdated(attributes:context.attributes,state:context.state).font(.caption2).foregroundStyle(colors.muted)
                        } else {
                            Text("\(context.attributes.parkName) · \(context.attributes.score) \(context.attributes.band)").font(.caption2).foregroundStyle(colors.muted)
                        }
                    }.environment(\.timeZone,zone)
                }
            } compactLeading: {
                FieldActivitySymbol(attributes:context.attributes,state:context.state,isStale:context.isStale)
            } compactTrailing: {
                FieldActivityCountdown(attributes:context.attributes,state:context.state,isStale:context.isStale)
            } minimal: {
                FieldActivitySymbol(attributes:context.attributes,state:context.state,isStale:context.isStale)
            }
            .keylineTint(colors.accent)
            .widgetURL(URL(string:"nyx://field/\(context.attributes.parkID)"))
        }
        // Apple Watch's Smart Stack and CarPlay draw the small family; without it they compose one from the island.
        .supplementalActivityFamilies([.small])
    }
}
/// The Lock Screen face, or the small one where the system asks for it.
struct FieldActivityFace: View {
    @Environment(\.activityFamily) private var family
    let attributes: FieldActivityAttributes
    let state: FieldActivityAttributes.ContentState
    let isStale: Bool
    var body: some View {
        switch family {
        case .small: FieldActivitySmallView(attributes:attributes,state:state,isStale:isStale)
        default: FieldActivityLockView(attributes:attributes,state:state,isStale:isStale)
        }
    }
}

/// A field-mode alarm's own Live Activity, shown while it is snoozed. Calm: a title and the time left.
struct FieldAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for:AlarmAttributes<FieldAlarmMetadata>.self) { context in
            HStack {
                VStack(alignment:.leading,spacing:4) {
                    Text(context.attributes.presentation.alert.title).font(.system(.headline,design:.serif))
                    if let park=context.attributes.metadata?.parkName { Text(park).font(.caption) }
                }
                Spacer()
                countdown(context.state).font(.system(.title2,design:.serif)).monospacedDigit()
            }
            .foregroundStyle(context.attributes.tintColor).padding(16).activityBackgroundTint(Color.black.opacity(0.88))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.presentation.alert.title).font(.subheadline).lineLimit(2).foregroundStyle(context.attributes.tintColor)
                        .dynamicIsland(verticalPlacement:.belowIfTooWide)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state).monospacedDigit().frame(maxWidth:90,alignment:.trailing).foregroundStyle(context.attributes.tintColor)
                }
            } compactLeading: { alarmSymbol.foregroundStyle(context.attributes.tintColor) }
              compactTrailing: { countdown(context.state).monospacedDigit().frame(maxWidth:52).foregroundStyle(context.attributes.tintColor) }
              minimal: { alarmSymbol.foregroundStyle(context.attributes.tintColor) }
              .keylineTint(context.attributes.tintColor)
        }
    }
    private var alarmSymbol: some View { Image(systemName:"alarm").accessibilityLabel("Alarm") }
    @ViewBuilder private func countdown(_ state:AlarmPresentationState)->some View {
        if case .countdown(let countdown)=state.mode { Text(timerInterval:Date.now...max(Date.now,countdown.fireDate),countsDown:true) }
        else { alarmSymbol }
    }
}

// The preview night is a DEBUG fixture, so the previews are too (Release archives must not reference it).
#if DEBUG
#Preview("Lock Screen",as:.content,using:FieldActivityAttributes.preview) { FieldLiveActivity() } contentStates:{
    FieldActivityAttributes.ContentState(next:FieldActivityAttributes.preview.milestones[1],nightVision:false)
    FieldActivityAttributes.ContentState(next:FieldActivityAttributes.preview.milestones[1],nightVision:true)
    FieldActivityAttributes.ContentState(next:nil,nightVision:false,finished:true)
}
#Preview("Island expanded",as:.dynamicIsland(.expanded),using:FieldActivityAttributes.preview) { FieldLiveActivity() } contentStates:{
    FieldActivityAttributes.ContentState(next:FieldActivityAttributes.preview.milestones[1],nightVision:false)
}
#Preview("Island compact",as:.dynamicIsland(.compact),using:FieldActivityAttributes.preview) { FieldLiveActivity() } contentStates:{
    FieldActivityAttributes.ContentState(next:FieldActivityAttributes.preview.milestones[1],nightVision:false)
    FieldActivityAttributes.ContentState(next:FieldActivityAttributes.preview.milestones[1],nightVision:true)
}
#Preview("Island minimal",as:.dynamicIsland(.minimal),using:FieldActivityAttributes.preview) { FieldLiveActivity() } contentStates:{
    FieldActivityAttributes.ContentState(next:FieldActivityAttributes.preview.milestones[1],nightVision:false)
}
#endif
