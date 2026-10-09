import SwiftUI
import WidgetKit

/// The Live Activity's faces, shared by the widget extension and the app's DEBUG review screen.
/// Black, quiet, one figure: the countdown to the next milestone. Under it the night as a line
/// from dusk to dawn that fills by itself, so the activity stays true between updates. When its
/// countdown has run out with no update (stale), Nyx cannot know which moment is next while the
/// phone sleeps: the faces then list the night's remaining times, which stay true, and name none
/// of them next.
struct FieldActivityColors {
    let nightVision: Bool
    var ink: Color { nightVision ? Color(red:1,green:0.27,blue:0.23) : Color(red:0.961,green:0.945,blue:0.902) }
    var accent: Color { nightVision ? Color(red:1,green:0.27,blue:0.23) : Color(red:1,green:0.706,blue:0.329) }
    /// Night vision keeps full red for secondary text: red is already dim, and any less fails contrast at caption sizes.
    var muted: Color { nightVision ? ink : ink.opacity(0.7) }
    var track: Color { ink.opacity(0.22) }
}

struct FieldActivityLockView: View {
    let attributes: FieldActivityAttributes
    let state: FieldActivityAttributes.ContentState
    let isStale: Bool
    private var colors: FieldActivityColors { FieldActivityColors(nightVision:state.nightVision) }
    /// "Heading out": followed ahead, before true darkness. Sunset, true darkness and the closure.
    private var heading: Bool { state.heading == true && !isStale && !state.finished }
    var body: some View {
        let mark=attributes.shown(state,isStale:isStale)
        VStack(alignment:.leading,spacing:heading ? 8 : 10) {
            HStack(spacing:6) {
                Image(systemName:"moon.stars").accessibilityHidden(true)
                Text(heading ? String(localized:"Tonight at \(attributes.parkName)") : attributes.parkName).lineLimit(1).minimumScaleFactor(0.75).layoutPriority(1)
                Spacer(minLength:8)
                // The night's latest score; its day when it is old, so the face is never surer than Nyx.
                Text(attributes.scoreLine(state)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityLabel(attributes.spokenScore(state))
            }.font(.caption.weight(.medium)).foregroundStyle(colors.muted)
            if state.finished {
                Text("The night is over. Rest your eyes.").font(.system(.title3,design:.serif)).foregroundStyle(colors.ink)
            } else if isStale {
                FieldActivitySchedule(attributes:attributes,state:state,colors:colors)
            } else if let mark {
                HStack(alignment:.firstTextBaseline) {
                    Label { Text(mark.title).lineLimit(1).minimumScaleFactor(0.75) } icon:{ Image(systemName:mark.symbol).accessibilityHidden(true) }
                        .font(.system(.headline,design:.serif)).foregroundStyle(colors.ink)
                    Spacer(minLength:8)
                    FieldActivityTimer(target:mark.date).font(.system(.title2,design:.serif)).monospacedDigit()
                        .foregroundStyle(colors.accent).multilineTextAlignment(.trailing).frame(maxWidth:130,alignment:.trailing)
                }
            } else {
                // Past the last mark: only sunrise is left to say.
                Text("Sunrise at \(Text(attributes.dawn,style:.time))").font(.system(.headline,design:.serif)).foregroundStyle(colors.ink)
            }
            if heading {
                // Before arrival: the two times that decide when to be there, and the one line that decides whether to go.
                HStack(spacing:12) {
                    timeMark(String(localized:"Sunset"),attributes.dusk)
                    if let dark=attributes.darkStart { timeMark(String(localized:"True darkness"),dark) }
                }.font(.caption).foregroundStyle(colors.muted).lineLimit(1).minimumScaleFactor(0.8)
                if let closure=attributes.closure(state) {
                    Label { Text(closure).lineLimit(2) } icon:{ Image(systemName:"exclamationmark.triangle").accessibilityHidden(true) }
                        .font(.caption.weight(.medium)).foregroundStyle(colors.accent)
                }
            } else if !state.finished {
                FieldNightLine(attributes:attributes,colors:colors).frame(height:isStale ? 10 : 16)
                if isStale {
                    FieldActivityUpdated(attributes:attributes,state:state).font(.caption2).foregroundStyle(colors.muted)
                } else {
                    let later=Array((mark.map { attributes.after($0) } ?? []).prefix(2))
                    if !later.isEmpty {
                        // Two marks when both fit whole, else one: never a truncated name.
                        ViewThatFits(in:.horizontal) {
                            HStack(spacing:12) { ForEach(later,id:\.date) { laterMark($0) } }
                            laterMark(later[0])
                        }.font(.caption2).foregroundStyle(colors.muted)
                    }
                }
            }
        }
        .padding(16)
        .accessibilityElement(children:.combine)
        .environment(\.timeZone,attributes.timeZone)
    }
    private func laterMark(_ item:FieldActivityAttributes.Milestone)->some View {
        HStack(spacing:4) { Text(item.title); Text(item.date,style:.time).monospacedDigit() }.fixedSize()
    }
    private func timeMark(_ title:String,_ date:Date)->some View {
        HStack(spacing:4) { Text(title); Text(date,style:.time).monospacedDigit().foregroundStyle(colors.ink) }
    }
}

/// The stale face's body: the night's remaining times as clock times, two to a row, and sunrise
/// last. Times stay true however long the phone sleeps; none is called next.
struct FieldActivitySchedule: View {
    let attributes: FieldActivityAttributes
    let state: FieldActivityAttributes.ContentState
    let colors: FieldActivityColors
    /// At most three marks and sunrise, so the face keeps the Lock Screen's height.
    static let shown=3
    var body: some View {
        let items=Array(attributes.schedule(state).prefix(Self.shown)).map { ($0.title,$0.date) }+[(String(localized:"Sunrise"),attributes.dawn)]
        let rows=stride(from:0,to:items.count,by:2).map { Array(items[$0..<min($0+2,items.count)]) }
        Grid(alignment:.leading,horizontalSpacing:14,verticalSpacing:4) {
            ForEach(Array(rows.enumerated()),id:\.offset) { _,row in
                GridRow {
                    ForEach(Array(row.enumerated()),id:\.offset) { _,item in
                        HStack(spacing:5) {
                            Text(item.0).foregroundStyle(colors.muted).lineLimit(1).minimumScaleFactor(0.8)
                            Text(item.1,style:.time).monospacedDigit().foregroundStyle(colors.ink).fixedSize()
                        }
                    }
                }
            }
        }.font(.system(.subheadline,design:.serif))
    }
}
/// "Updated 7:44 PM. Open Nyx to refresh." A night planned on another day names that day.
struct FieldActivityUpdated: View {
    let attributes: FieldActivityAttributes
    let state: FieldActivityAttributes.ContentState
    var body: some View {
        if let updated=state.updated {
            Text("Updated \(Text(updated,format:Self.format(updated,dusk:attributes.dusk,zone:attributes.timeZone))). Open Nyx to refresh.")
        } else { Text("Open Nyx to refresh.") }
    }
    /// The time alone on the night's own day, else the weekday too ("Wed 3:12 PM"), in park time.
    static func format(_ updated:Date,dusk:Date,zone:TimeZone)->Date.FormatStyle {
        var style=dusk.timeIntervalSince(updated)<18*3600 ? Date.FormatStyle.dateTime.hour().minute() : Date.FormatStyle.dateTime.weekday(.abbreviated).hour().minute()
        style.timeZone=zone
        return style
    }
}

/// Apple Watch's Smart Stack and CarPlay (the small activity family): the milestone's symbol, one
/// large countdown, the park's short name. Nothing else, and red in night vision. Stale, it names
/// sunrise and its time, which stay true.
struct FieldActivitySmallView: View {
    let attributes: FieldActivityAttributes
    let state: FieldActivityAttributes.ContentState
    let isStale: Bool
    var body: some View {
        let colors=FieldActivityColors(nightVision:state.nightVision)
        let mark=FieldActivityMark(attributes:attributes,state:state,isStale:isStale)
        VStack(alignment:.leading,spacing:2) {
            Label { Text(mark.title).lineLimit(1).minimumScaleFactor(0.7) } icon:{ Image(systemName:mark.symbol).accessibilityHidden(true) }
                .font(.caption.weight(.semibold)).foregroundStyle(colors.ink)
            Group {
                if let milestone=mark.milestone { FieldActivityTimer(target:milestone.date) }
                else if state.finished { Text("Dawn") }
                else { Text(attributes.dawn,style:.time) }
            }
            .font(.system(.title2,design:.serif).weight(.medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            .foregroundStyle(colors.accent)
            Text(attributes.parkName).font(.caption2).foregroundStyle(colors.muted).lineLimit(1)
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .padding(.horizontal,10).padding(.vertical,8)
        .accessibilityElement(children:.combine)
        .environment(\.timeZone,attributes.timeZone)
    }
}

/// Dusk to dawn as a line. The fill is a system timer, so it advances without updates; marks sit
/// at each milestone, and true darkness is the brighter stretch.
struct FieldNightLine: View {
    let attributes: FieldActivityAttributes
    let colors: FieldActivityColors
    var body: some View {
        GeometryReader { proxy in
            let w=proxy.size.width
            ZStack(alignment:.leading) {
                if let start=attributes.darkStart, let end=attributes.darkEnd {
                    let a=attributes.fraction(start), b=attributes.fraction(end)
                    Capsule().fill(colors.track).frame(width:max(2,(b-a)*w),height:6).offset(x:a*w)
                }
                ProgressView(timerInterval:attributes.dusk...max(attributes.dusk,attributes.dawn),countsDown:false) { EmptyView() } currentValueLabel:{ EmptyView() }
                    .progressViewStyle(.linear).tint(colors.accent).frame(height:3)
                ForEach(attributes.milestones,id:\.date) { item in
                    Capsule().fill(colors.ink.opacity(0.8)).frame(width:1.5,height:12).offset(x:attributes.fraction(item.date)*w-0.75)
                }
            }.frame(maxHeight:.infinity)
        }.accessibilityHidden(true)
    }
}

/// What the Dynamic Island and the small family name: the milestone counted down to, sunrise when
/// only that is left or when the activity has gone stale, dawn once over.
struct FieldActivityMark {
    let milestone: FieldActivityAttributes.Milestone?
    let finished: Bool
    init(attributes:FieldActivityAttributes,state:FieldActivityAttributes.ContentState,isStale:Bool) {
        milestone=attributes.shown(state,isStale:isStale); finished=state.finished
    }
    var title: String { finished ? String(localized:"Dawn") : milestone?.title ?? String(localized:"Sunrise") }
    var symbol: String { milestone?.symbol ?? "sunrise" }
}
/// The Dynamic Island's compact and minimal faces, spoken as the moment they stand for.
struct FieldActivitySymbol: View {
    let mark: FieldActivityMark
    let nightVision: Bool
    init(attributes:FieldActivityAttributes,state:FieldActivityAttributes.ContentState,isStale:Bool) {
        mark=FieldActivityMark(attributes:attributes,state:state,isStale:isStale); nightVision=state.nightVision
    }
    var body: some View {
        Image(systemName:mark.symbol)
            .foregroundStyle(FieldActivityColors(nightVision:nightVision).accent)
            .accessibilityLabel(mark.title)
    }
}
/// The countdown to the shown milestone; sunrise's clock time when only that is left or once
/// stale. In the compact island on iOS 27 it follows the system's width: hours and minutes when
/// there is room, minutes alone ("91m") when the island is narrowed. iOS 26 caps the width.
struct FieldActivityCountdown: View {
    let attributes: FieldActivityAttributes
    let state: FieldActivityAttributes.ContentState
    let isStale: Bool
    /// Compact by default; the expanded island passes a larger face and a wider cap.
    var font: Font = .caption.weight(.semibold)
    var maxWidth: CGFloat = 56
    /// The compact island, which follows `isDynamicIslandLimitedInWidth` on iOS 27.
    var compact = true
    var body: some View {
        let colors=FieldActivityColors(nightVision:state.nightVision)
        Group {
            if compact, #available(iOS 27.0, *) {
                FieldActivityAdaptiveCountdown(attributes:attributes,state:state,isStale:isStale)
            } else {
                face(.abbreviated).frame(maxWidth:maxWidth,alignment:.trailing)
            }
        }
        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8).multilineTextAlignment(.trailing)
        .font(font).foregroundStyle(colors.accent)
        .environment(\.timeZone,attributes.timeZone)
    }
    @ViewBuilder fileprivate func face(_ style:FieldActivityTimer.Style)->some View {
        if let mark=attributes.shown(state,isStale:isStale) { FieldActivityTimer(target:mark.date,style:style) }
        else if !state.finished { Text(attributes.dawn,style:.time) }
        else { Text("Dawn") }
    }
}
@available(iOS 27.0, *)
private struct FieldActivityAdaptiveCountdown: View {
    @Environment(\.isDynamicIslandLimitedInWidth) private var limited
    let attributes: FieldActivityAttributes
    let state: FieldActivityAttributes.ContentState
    let isStale: Bool
    var body: some View {
        FieldActivityCountdown(attributes:attributes,state:state,isStale:isStale).face(limited ? .minutes : .narrow)
    }
}

/// The countdown on the Lock Screen and in the Dynamic Island: hours and minutes, rounded up
/// ("23 min", "1 hr, 31 min"), updated by the system from a time source, so it keeps counting
/// between the app's updates and never reads as a clock time. No seconds: a widget cannot switch
/// to them in the last two minutes without an update, so it keeps minute precision to the end.
struct FieldActivityTimer: View {
    enum Style { case abbreviated, narrow, minutes }
    let target: Date
    var style: Style = .abbreviated
    var body: some View {
        // From now to the target, counted in whole minutes; the 59 s rounds a part minute up ("22:39" reads "23 min").
        let range=TimeDataSource<Range<Date>>.dateRange(endingAt:target.addingTimeInterval(59))
        switch style {
        case .abbreviated: Text(range,format:.components(style:.abbreviated,fields:[.hour,.minute]))
        case .narrow: Text(range,format:.components(style:.narrow,fields:[.hour,.minute]))
        case .minutes: Text(range,format:.components(style:.narrow,fields:[.minute]))
        }
    }
}
#if DEBUG
extension FieldActivityAttributes {
    /// The same night moved in time, so a review screen's system timers count against a real clock.
    /// Its clock times stay the park's own: the zone is moved back by the same amount (to the
    /// minute), so a capture taken at any hour reads "Sunset 5:47 PM", never the capture's hour.
    func shifted(by seconds:TimeInterval)->FieldActivityAttributes {
        let day=86400, half=43200
        let offset=timeZone.secondsFromGMT(for:dusk)-Int((seconds/60).rounded())*60
        let wrapped=((offset+half)%day+day)%day-half
        let zone=String(format:"GMT%@%02d%02d",wrapped<0 ? "-" : "+",abs(wrapped)/3600,abs(wrapped)%3600/60)
        return FieldActivityAttributes(parkID:parkID,parkName:parkName,score:score,band:band,dusk:dusk+seconds,dawn:dawn+seconds,darkStart:darkStart.map { $0+seconds },darkEnd:darkEnd.map { $0+seconds },
            milestones:milestones.map { Milestone(title:$0.title,date:$0.date+seconds,symbol:$0.symbol) },timeZoneID:zone,nightID:nightID,closure:closure)
    }
    /// A state carrying a later score, band and closure, for previews and the review screen.
    static func rescored(_ state:ContentState,score:Int,band:String,closure:String?,at:Date)->ContentState {
        var state=state
        state.scored=Scored(score:score,band:band,closure:closure,at:at)
        return state
    }
    /// A real-looking night for previews: dusk at 6:20 PM, darkness 7:45 PM to 5:30 AM.
    static var preview: FieldActivityAttributes {
        let dusk=Date(timeIntervalSince1970:1_797_210_000)
        func at(_ minutes:Double)->Date { dusk.addingTimeInterval(minutes*60) }
        return FieldActivityAttributes(parkID:"jotr",parkName:"Joshua Tree",score:94,band:"Pristine",dusk:dusk,dawn:at(760),darkStart:at(85),darkEnd:at(670),
            milestones:[.init(title:"True darkness",date:at(85),symbol:"moon.stars"),.init(title:"Moonset",date:at(170),symbol:"moonset"),
                        .init(title:"Geminids at their best",date:at(420),symbol:"sparkles"),.init(title:"Dawn twilight",date:at(670),symbol:"sun.horizon")],
            timeZoneID:"America/Los_Angeles",closure:"Keys View Road closed at night")
    }
}
#Preview("Lock Screen states") {
    let a=FieldActivityAttributes.preview
    ScrollView { VStack(spacing:12) {
        FieldActivityLockView(attributes:a,state:a.state(at:a.dusk.addingTimeInterval(-1200),nightVision:false,heading:true),isStale:false)
        FieldActivityLockView(attributes:a,state:FieldActivityAttributes.rescored(a.state(at:a.dusk.addingTimeInterval(-1200),nightVision:false,heading:true),
            score:71,band:"Good",closure:nil,at:a.dusk.addingTimeInterval(-3*24*3600)),isStale:false)
        FieldActivityLockView(attributes:a,state:a.state(at:a.dusk.addingTimeInterval(3000),nightVision:false),isStale:false)
        FieldActivityLockView(attributes:a,state:a.state(at:a.dusk.addingTimeInterval(3000),nightVision:true),isStale:false)
        FieldActivityLockView(attributes:a,state:a.state(at:a.dusk.addingTimeInterval(3000),nightVision:false),isStale:true)
        FieldActivityLockView(attributes:a,state:a.state(at:a.dawn,nightVision:false),isStale:false)
        HStack { FieldActivitySmallView(attributes:a,state:a.state(at:a.dusk,nightVision:false),isStale:false); FieldActivitySmallView(attributes:a,state:a.state(at:a.dusk,nightVision:true),isStale:true) }.frame(height:84)
    }.background(Color.black).padding() }
}
#endif
