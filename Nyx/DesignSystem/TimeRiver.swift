import SwiftUI

/// Thirty nights as one flowing line. Drag across it (or swipe up/down with VoiceOver)
/// to scrub; the moon above the selected night morphs as you go. Nights beyond the cloud
/// forecast are dashed and hollow, and the best nights glow amber.
struct TimeRiver: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    let nights: [Night]
    @Binding var selected: Date
    @State private var scrubbing: Bool?
    private var index:Int { nights.firstIndex(where:{$0.park.calendar.isDate($0.id,inSameDayAs:selected)}) ?? 0 }
    private var current:Night? { nights.indices.contains(index) ? nights[index] : nil }
    /// The three highest-scoring nights, at least Good, receive the amber glow.
    private var peaks:Set<Int> {
        Set(nights.indices.filter { nights[$0].score.value>=60 }.sorted { nights[$0].score.value>nights[$1].score.value }.prefix(3))
    }
    private let inset=14.0, moonSize=30.0

    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Eyebrow(text:"Follow the darker nights")
            if nights.isEmpty {
                Text("No nights available").font(.subheadline).foregroundStyle(palette.muted)
            } else if typeSize.isAccessibilitySize {
                stepper
            } else {
                river
                summary
            }
            Text(legend).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }
        .sensoryFeedback(.selection,trigger:index)
    }

    private var river: some View {
        GeometryReader { proxy in
            let width=proxy.size.width
            ZStack(alignment:.topLeading) {
                Canvas { context,size in draw(in:&context,size:size) }
                    .accessibilityHidden(true)
                if let current {
                    MoonDisc(illumination:current.sky.moon.illumination,waxing:current.sky.moon.waxing,southern:current.park.latitude<0)
                        .frame(width:moonSize,height:moonSize)
                        .offset(x:x(index,width:width)-moonSize/2,y:0)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            // Scrub only on mostly-horizontal drags, so the page above still scrolls freely.
            .simultaneousGesture(DragGesture(minimumDistance:6).onChanged { drag in
                if scrubbing==nil { scrubbing=abs(drag.translation.width)>abs(drag.translation.height) }
                if scrubbing==true { choose(nearest(drag.location.x,width:width)) }
            }.onEnded { _ in scrubbing=nil })
            .onTapGesture { location in choose(nearest(location.x,width:width)) }
        }
        .frame(height:150)
        .accessibilityElement()
        .accessibilityLabel("Thirty-night darkness timeline")
        .accessibilityValue(spokenValue)
        .accessibilityHint("Swipe up or down to move one night at a time.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: choose(index+1)
            case .decrement: choose(index-1)
            @unknown default: break
            }
        }
    }

    private var summary: some View {
        HStack(alignment:.firstTextBaseline) {
            if let current {
                Text(current.park.dayLabel(current.id)).font(.subheadline)
                Spacer(minLength:8)
                Text("\(current.score.value)").font(.system(.title3,design:.serif)).foregroundStyle(palette.accent).contentTransition(.numericText(value:Double(current.score.value)))
                Text(current.score.hasForecast ? current.score.band.label : String(localized:"Estimate")).font(.caption).foregroundStyle(palette.muted)
            }
        }.accessibilityHidden(true)
    }

    /// At accessibility text sizes the drawn river gives way to a plain, large stepper.
    private var stepper: some View {
        Stepper(value:Binding(get:{index},set:choose),in:0...max(0,nights.count-1)) {
            Text(spokenValue).font(.subheadline).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
        }.tint(palette.controlTint).foregroundStyle(palette.ink,palette.muted,palette.muted)
            .accessibilityLabel("Selected night").accessibilityValue(spokenValue).accessibilityHint("Adjust to move one night at a time.")
    }

    private var spokenValue: String {
        guard let current else { return String(localized:"No nights available") }
        let clouds=current.score.hasForecast ? String(localized:"Forecast included") : String(localized:"Moon and darkness only. Clouds unknown.")
        return String(localized:"\(current.park.dayLabel(current.id)), \(current.score.value) out of 100, \(current.score.band.label). \(clouds)")
    }
    private var legend: String {
        typeSize.isAccessibilitySize ? String(localized:"Hollow nights have no cloud forecast yet.")
            : String(localized:"Drag along the river. Dashed, hollow nights are moon and darkness only.")
    }

    private func x(_ i:Int,width:Double)->Double {
        guard nights.count>1 else { return width/2 }
        return inset+Double(i)*(width-2*inset)/Double(nights.count-1)
    }
    private func nearest(_ location:Double,width:Double)->Int {
        guard nights.count>1 else { return 0 }
        return Int(((location-inset)/((width-2*inset)/Double(nights.count-1))).rounded())
    }
    private func choose(_ value:Int) {
        guard nights.indices.contains(value), value != index else { return }
        withAnimation(reduceMotion ? nil : NyxMotion.spring) { selected=nights[value].id }
    }

    private func draw(in context:inout GraphicsContext,size:CGSize) {
        let top=moonSize+12, bottom=size.height-22, span=bottom-top
        func point(_ i:Int)->CGPoint { CGPoint(x:x(i,width:size.width),y:bottom-span*Double(nights[i].score.value)/100) }
        let lastForecast=nights.lastIndex { $0.score.hasForecast }

        // Selected-night hairline, from the moon down to the date row.
        var hairline=Path(); hairline.move(to:CGPoint(x:x(index,width:size.width),y:moonSize+2)); hairline.addLine(to:CGPoint(x:x(index,width:size.width),y:bottom+4))
        context.stroke(hairline,with:.color(palette.line),lineWidth:0.6)

        // A smooth river through every night; the forecast-free stretch is dashed.
        func river(_ range:ClosedRange<Int>)->Path {
            var path=Path(); path.move(to:point(range.lowerBound))
            for i in range.dropFirst() {
                let a=point(i-1), b=point(i), mid=(a.x+b.x)/2
                path.addCurve(to:b,control1:CGPoint(x:mid,y:a.y),control2:CGPoint(x:mid,y:b.y))
            }
            return path
        }
        let all=river(0...(nights.count-1))
        var fill=all; fill.addLine(to:CGPoint(x:point(nights.count-1).x,y:bottom)); fill.addLine(to:CGPoint(x:point(0).x,y:bottom)); fill.closeSubpath()
        context.fill(fill,with:.linearGradient(Gradient(colors:[palette.accent.opacity(0.18),palette.accent.opacity(0)]),startPoint:CGPoint(x:0,y:top),endPoint:CGPoint(x:0,y:bottom)))
        if let lastForecast, lastForecast>0 { context.stroke(river(0...lastForecast),with:.color(palette.accent),style:StrokeStyle(lineWidth:1.6,lineCap:.round)) }
        let dashedStart=(lastForecast ?? -1)+1
        if dashedStart<nights.count {
            context.stroke(river(max(0,dashedStart-1)...(nights.count-1)),with:.color(palette.accent.opacity(0.55)),style:StrokeStyle(lineWidth:1.1,lineCap:.round,dash:[3,4]))
        }

        for i in nights.indices {
            let p=point(i), night=nights[i]
            if peaks.contains(i) {
                context.fill(Path(ellipseIn:CGRect(x:p.x-12,y:p.y-12,width:24,height:24)),with:.radialGradient(Gradient(colors:[palette.accent.opacity(0.45),palette.accent.opacity(0)]),center:p,startRadius:0,endRadius:12))
            }
            let r=i==index ? 5.0 : 2.4
            let dot=Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:2*r,height:2*r))
            if night.score.hasForecast { context.fill(dot,with:.color(palette.accent)) }
            else { context.fill(dot,with:.color(.black)); context.stroke(dot,with:.color(palette.accent),lineWidth:1.1) }
        }

        // Sparse date labels: tonight, the first night of each week, and the selected night.
        let labeled=nights.indices.filter { i in i==0 || i==index || (startsWeek(i) && abs(i-index)>2 && i>2) }
        for i in labeled {
            let label=i==0 ? String(localized:"Tonight") : "\(nights[i].park.calendar.component(.day,from:nights[i].id))"
            let text=context.resolve(Text(label).font(.caption2.weight(i==index ? .semibold : .regular)).foregroundStyle(i==index ? palette.ink : palette.muted))
            let measured=text.measure(in:size)
            let cx=min(max(x(i,width:size.width),measured.width/2),size.width-measured.width/2)
            context.draw(text,at:CGPoint(x:cx,y:size.height-measured.height/2))
        }
    }
    private func startsWeek(_ i:Int)->Bool {
        let park=nights[i].park
        return park.calendar.component(.weekday,from:nights[i].id)==park.calendar.firstWeekday
    }
}
#Preview("River") { if let p=try? ParkData.load().first(where:{$0.id=="jotr"}) { let m=PlanModel();TimeRiver(nights:m.nights(p,from:.now,count:30),selected:.constant(m.tonight(p))).padding().background(.black) } }
#Preview("River • AX5") { if let p=try? ParkData.load().first(where:{$0.id=="jotr"}) { let m=PlanModel();TimeRiver(nights:m.nights(p,from:.now,count:30),selected:.constant(m.tonight(p))).padding().dynamicTypeSize(.accessibility5).background(.black) } }
#Preview("Empty river") { TimeRiver(nights:[],selected:.constant(.now)).padding().background(.black) }
