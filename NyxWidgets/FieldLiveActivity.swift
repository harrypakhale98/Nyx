import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

/// The night in the field, on the Lock Screen, in the Dynamic Island and in StandBy (whose night
/// mode already turns it red).
struct FieldLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for:FieldActivityAttributes.self) { context in
            FieldActivityLockView(attributes:context.attributes,state:context.state,isStale:context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.88))
                .activitySystemActionForegroundColor(FieldActivityColors(nightVision:context.state.nightVision).ink)
                .widgetURL(URL(string:"nyx://field/\(context.attributes.parkID)"))
        } dynamicIsland: { context in
            let colors=FieldActivityColors(nightVision:context.state.nightVision)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label { Text(context.state.finished ? String(localized:"Dawn") : context.state.next?.title ?? String(localized:"Later tonight")).lineLimit(1) } icon:{ FieldActivitySymbol(state:context.state) }
                        .font(.system(.subheadline,design:.serif)).foregroundStyle(colors.ink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FieldActivityCountdown(attributes:context.attributes,state:context.state,isStale:context.isStale).font(.system(.title3,design:.serif))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment:.leading,spacing:6) {
                        FieldNightLine(attributes:context.attributes,colors:colors).frame(height:14)
                        Text("\(context.attributes.parkName) · \(context.attributes.score) \(context.attributes.band)").font(.caption2).foregroundStyle(colors.muted)
                    }
                }
            } compactLeading: {
                FieldActivitySymbol(state:context.state)
            } compactTrailing: {
                FieldActivityCountdown(attributes:context.attributes,state:context.state,isStale:context.isStale)
            } minimal: {
                FieldActivitySymbol(state:context.state)
            }
            .keylineTint(colors.accent)
            .widgetURL(URL(string:"nyx://field/\(context.attributes.parkID)"))
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
                DynamicIslandExpandedRegion(.leading) { Text(context.attributes.presentation.alert.title).font(.subheadline).lineLimit(2) }
                DynamicIslandExpandedRegion(.trailing) { countdown(context.state).monospacedDigit() }
            } compactLeading: { Image(systemName:"alarm").foregroundStyle(context.attributes.tintColor) }
              compactTrailing: { countdown(context.state).monospacedDigit().frame(maxWidth:52).foregroundStyle(context.attributes.tintColor) }
              minimal: { Image(systemName:"alarm").foregroundStyle(context.attributes.tintColor) }
        }
    }
    @ViewBuilder private func countdown(_ state:AlarmPresentationState)->some View {
        if case .countdown(let countdown)=state.mode { Text(timerInterval:Date.now...max(Date.now,countdown.fireDate),countsDown:true) }
        else { Image(systemName:"alarm") }
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
