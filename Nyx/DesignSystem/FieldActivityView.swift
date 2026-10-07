import SwiftUI

/// The Live Activity's faces, shared by the widget extension and the app's DEBUG review screen.
/// Black, quiet, one figure: the countdown to the next milestone. Under it the night as a line
/// from dusk to dawn that fills by itself, so the activity stays true between updates even when
/// its countdown has run out (the state is then stale and shows absolute times instead).
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
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:6) {
                Image(systemName:"moon.stars").accessibilityHidden(true)
                Text(attributes.parkName).lineLimit(1).minimumScaleFactor(0.75).layoutPriority(1)
                Spacer(minLength:8)
                Text("\(attributes.score) · \(attributes.band)").monospacedDigit()
            }.font(.caption.weight(.medium)).foregroundStyle(colors.muted)
            if state.finished {
                Text("The night is over. Rest your eyes.").font(.system(.title3,design:.serif)).foregroundStyle(colors.ink)
            } else if let next=state.next, !isStale {
                HStack(alignment:.firstTextBaseline) {
                    Label { Text(next.title).lineLimit(1).minimumScaleFactor(0.75) } icon:{ Image(systemName:next.symbol).accessibilityHidden(true) }
                        .font(.system(.headline,design:.serif)).foregroundStyle(colors.ink)
                    Spacer(minLength:8)
                    Text(timerInterval:Date.now...max(Date.now,next.date),countsDown:true).font(.system(.title2,design:.serif)).monospacedDigit()
                        .foregroundStyle(colors.accent).multilineTextAlignment(.trailing).frame(maxWidth:110,alignment:.trailing)
                }
            } else if attributes.after(state.next).isEmpty {
                // Past the last mark with no update since: only sunrise is left to say.
                HStack(spacing:6) { Text("Sunrise at"); Text(attributes.dawn,style:.time) }.font(.system(.headline,design:.serif)).foregroundStyle(colors.ink)
            } else {
                Text("Later tonight").font(.system(.headline,design:.serif)).foregroundStyle(colors.ink)
            }
            if !state.finished {
                FieldNightLine(attributes:attributes,colors:colors).frame(height:16)
                let later=Array(attributes.after(state.next).prefix(2))
                if !later.isEmpty {
                    // Two marks when both fit whole, else one: never a truncated name.
                    ViewThatFits(in:.horizontal) {
                        HStack(spacing:12) { ForEach(later,id:\.date) { laterMark($0) } }
                        laterMark(later[0])
                    }.font(.caption2).foregroundStyle(colors.muted)
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

/// The Dynamic Island's compact and minimal faces.
struct FieldActivitySymbol: View {
    let state: FieldActivityAttributes.ContentState
    var body: some View {
        Image(systemName:state.finished ? "sunrise" : state.next?.symbol ?? "moon.stars")
            .foregroundStyle(FieldActivityColors(nightVision:state.nightVision).accent)
            .accessibilityLabel(state.finished ? Text("Dawn") : Text(state.next?.title ?? String(localized:"Later tonight")))
    }
}
struct FieldActivityCountdown: View {
    let attributes: FieldActivityAttributes
    let state: FieldActivityAttributes.ContentState
    let isStale: Bool
    var body: some View {
        let colors=FieldActivityColors(nightVision:state.nightVision)
        Group {
            if let next=state.next, !isStale, !state.finished {
                Text(timerInterval:Date.now...max(Date.now,next.date),countsDown:true).monospacedDigit().frame(maxWidth:56)
            } else if let later=attributes.after(state.next).first, !state.finished {
                Text(later.date,style:.time).monospacedDigit()
            } else { Text("Dawn") }
        }.font(.caption.weight(.semibold)).foregroundStyle(colors.accent)
        .environment(\.timeZone,attributes.timeZone)
    }
}

#if DEBUG
extension FieldActivityAttributes {
    /// The same night moved in time, so a review screen's system timers count against a real clock.
    func shifted(by seconds:TimeInterval)->FieldActivityAttributes {
        FieldActivityAttributes(parkID:parkID,parkName:parkName,score:score,band:band,dusk:dusk+seconds,dawn:dawn+seconds,darkStart:darkStart.map { $0+seconds },darkEnd:darkEnd.map { $0+seconds },
            milestones:milestones.map { Milestone(title:$0.title,date:$0.date+seconds,symbol:$0.symbol) },timeZoneID:timeZoneID)
    }
    /// A real-looking night for previews: dusk at 6:20 PM, darkness 7:45 PM to 5:30 AM.
    static var preview: FieldActivityAttributes {
        let dusk=Date(timeIntervalSince1970:1_797_210_000)
        func at(_ minutes:Double)->Date { dusk.addingTimeInterval(minutes*60) }
        return FieldActivityAttributes(parkID:"jotr",parkName:"Joshua Tree",score:94,band:"Pristine",dusk:dusk,dawn:at(760),darkStart:at(85),darkEnd:at(670),
            milestones:[.init(title:"True darkness",date:at(85),symbol:"moon.stars"),.init(title:"Moonset",date:at(170),symbol:"moonset"),
                        .init(title:"Geminids at their best",date:at(420),symbol:"sparkles"),.init(title:"Dawn twilight",date:at(670),symbol:"sun.horizon")])
    }
}
#endif
