import SwiftUI

/// True while a horizontal scrub is under way, so the page can hold still instead of drifting.
struct RiverScrubbingKey:PreferenceKey {
    static let defaultValue=false
    static func reduce(value:inout Bool,nextValue:()->Bool) { value = value || nextValue() }
}
/// Thirty nights as one flowing line. Drag across it (or swipe up/down with VoiceOver)
/// to scrub; the moon above the selected night morphs as you go. Nights beyond the cloud
/// forecast are dashed and hollow, and the best nights glow amber. Within the seven-day model
/// horizon a pale bar through each night spans the scores the clearest and cloudiest of three
/// forecast models would give, so uncertainty is something you can see, not a footnote.
struct TimeRiver: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    @Environment(\.nyxAccess) private var access
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    let nights: [Night]
    @Binding var selected: Date
    /// False when the river starts on a chosen night instead of tonight.
    var startsTonight=true
    /// Each night's forecast context, keyed by night; only `scoreRange` and `agreement` are drawn.
    var outlooks:[Date:NightOutlook]=[:]
    /// A visible eclipse or a notable shower's peak, drawn small above that night's point.
    var markers:[Date:WhatsUp.Events.Marker]=[:]
    /// Whether the current drag is a horizontal scrub; reset by the system even when a drag is cancelled.
    @GestureState private var scrubbing: Bool?=nil
    /// Haptic ticks follow a person's choice, never a data refresh.
    @State private var detents=0
    /// Counts a person's choices, so the Moon's texture follows a scrub once it settles.
    @State private var felt=0
    /// The selected night's position; nil when it is not on the river, which then marks no night
    /// rather than pretending the first one is chosen.
    private var index:Int? { nights.firstIndex(where:{$0.park.calendar.isDate($0.id,inSameDayAs:selected)}) }
    private var current:Night? { index.map { nights[$0] } }
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
                if let current, let marker=markers[current.id] {
                    Label { Text(marker.name) } icon:{ SkyGlyph(SkyGlyph.Kind(marker.glyph),color:palette.accent).frame(width:14,height:14) }
                        .font(.caption).foregroundStyle(palette.ink).accessibilityHidden(true)
                }
            }
            Text(legend).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }
        .sensoryFeedback(.selection,trigger:detents)
        .preference(key:RiverScrubbingKey.self,value:scrubbing==true)
        // Feel the Moon: once a scrub rests on a night, its Moon's phase as a short texture.
        .task(id:felt) {
            guard felt>0, MoonHaptics.enabled, let moon=current?.sky.moon else { return }
            try? await Task.sleep(for:.milliseconds(380))
            if !Task.isCancelled { MoonHaptics.shared.play(.moon(illumination:moon.illumination,waxing:moon.waxing,duration:0.6)) }
        }
    }

    private var river: some View {
        GeometryReader { proxy in
            let width=proxy.size.width
            ZStack(alignment:.topLeading) {
                Canvas { context,size in draw(in:&context,size:size) }
                    .accessibilityHidden(true)
                if let current,let index {
                    MoonView(geometry:AstronomyEngine().moon(for:current).geometry)
                        .frame(width:moonSize,height:moonSize)
                        .offset(x:x(index,width:width)-moonSize/2,y:0)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            // Scrub only on mostly-horizontal drags, so the page above still scrolls freely.
            .simultaneousGesture(DragGesture(minimumDistance:6).updating($scrubbing) { drag,state,_ in
                if state==nil { state=abs(drag.translation.width)>abs(drag.translation.height) }
            }.onChanged { drag in
                if scrubbing ?? (abs(drag.translation.width)>abs(drag.translation.height)) { choose(nearest(drag.location.x,width:width)) }
            })
            .onTapGesture { location in choose(nearest(location.x,width:width)) }
        }
        .frame(height:150)
        .accessibilityElement()
        .accessibilityLabel("Thirty-night darkness timeline")
        .accessibilityValue(spokenValue)
        .accessibilityHint("Swipe up or down to move one night at a time. An audio graph is available.")
        .accessibilityInputLabels([Text("River"),Text("Nights"),Text("Timeline")])
        .modifier(RiverAccessibility(nights:nights,outlooks:outlooks,markers:markers,peaks:peakOrder,current:index,choose:choose))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: choose(index.map { $0+1 } ?? 0)
            case .decrement: choose(index.map { $0-1 } ?? 0)
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
                // Where the models part, the range the score could fall in, beside the score itself.
                if let outlook=outlooks[current.id], outlook.agreement.map({ $0.band != .agree }) == true, let range=outlook.scoreRange, range.upperBound>range.lowerBound {
                    Text("· \(range.lowerBound)–\(range.upperBound)").font(.caption.monospacedDigit()).foregroundStyle(palette.muted)
                }
            }
        }.accessibilityHidden(true)
    }

    /// At accessibility text sizes the drawn river gives way to a plain, large stepper.
    private var stepper: some View {
        Stepper(value:Binding(get:{index ?? 0},set:choose),in:0...max(0,nights.count-1)) {
            Text(spokenValue).font(.subheadline).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
        }.tint(palette.controlTint).foregroundStyle(palette.ink,palette.muted,palette.muted)
            .accessibilityLabel("Selected night").accessibilityValue(spokenValue).accessibilityHint("Adjust to move one night at a time.")
            .accessibilityInputLabels([Text("Night"),Text("Selected night")])
            .modifier(RiverAccessibility(nights:nights,outlooks:outlooks,markers:markers,peaks:peakOrder,current:index,choose:choose))
    }

    private var spokenValue: String {
        guard let current else { return String(localized:"No nights available") }
        let clouds=current.score.hasForecast ? String(localized:"Forecast included") : String(localized:"Moon and darkness only. Clouds unknown.")
        return String(localized:"\(current.park.dayLabel(current.id)), \(current.score.value) out of 100, \(current.score.band.label). \(clouds)")+(agreementSpoken(current).map { ". "+$0 } ?? "")+(markers[current.id].map { ". "+$0.name } ?? "")
    }
    private func agreementSpoken(_ night:Night)->String? {
        guard let outlook=outlooks[night.id], let agreement=outlook.agreement else { return nil }
        guard agreement.band != .agree, let range=outlook.scoreRange, range.upperBound>range.lowerBound else { return String(localized:"Forecast models agree.") }
        return agreement.band == .roughly ? String(localized:"Forecast models roughly agree; the score could be \(range.lowerBound) to \(range.upperBound).")
            : String(localized:"Forecast models disagree; the score could be \(range.lowerBound) to \(range.upperBound).")
    }
    private var hasRanges:Bool { nights.contains { outlooks[$0.id]?.scoreRange != nil } }
    private var legend: String {
        if typeSize.isAccessibilitySize { return String(localized:"Hollow nights have no cloud forecast yet.") }
        var base=hasRanges ? String(localized:"Drag along the river. Pale bars span three forecast models; dashed, hollow nights are moon and darkness only.")
            : String(localized:"Drag along the river. Dashed, hollow nights are moon and darkness only.")
        if access.differentiate { base+=" "+NightMark.legend+" "+String(localized:"Small triangles beneath mark the three best nights.") }
        return markers.isEmpty ? base : base+" "+String(localized:"Small marks above a night are a meteor shower's peak or a lunar eclipse.")
    }
    /// The glowing nights, best first.
    private var peakOrder:[Int] { peaks.sorted { nights[$0].score.value>nights[$1].score.value || (nights[$0].score.value==nights[$1].score.value && $0<$1) } }

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
        // The detent sharpens with the night's score where Core Haptics can say so.
        if MoonHaptics.enabled { MoonHaptics.shared.detent(score:nights[value].score.value) } else { detents+=1 }
        felt+=1
    }

    private func draw(in context:inout GraphicsContext,size:CGSize) {
        let top=moonSize+12, bottom=size.height-22, span=bottom-top
        func point(_ i:Int)->CGPoint { CGPoint(x:x(i,width:size.width),y:bottom-span*Double(nights[i].score.value)/100) }
        let lastForecast=nights.lastIndex { $0.score.hasForecast }

        // Selected-night hairline, from the moon down to the date row.
        if let index {
            var hairline=Path(); hairline.move(to:CGPoint(x:x(index,width:size.width),y:moonSize+2)); hairline.addLine(to:CGPoint(x:x(index,width:size.width),y:bottom+4))
            context.stroke(hairline,with:.color(palette.line),lineWidth:0.6)
        }

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

        // Model spread: a soft starlight bar from the cloudiest model's score to the clearest's.
        for i in nights.indices {
            guard let range=outlooks[nights[i].id]?.scoreRange, range.upperBound>range.lowerBound else { continue }
            let cx=x(i,width:size.width)
            let upper=bottom-span*Double(range.upperBound)/100, lower=bottom-span*Double(range.lowerBound)/100
            let bar=Path(roundedRect:CGRect(x:cx-3.5,y:upper-3,width:7,height:lower-upper+6),cornerRadius:3.5)
            context.fill(bar,with:.color(palette.ink.opacity(palette.highContrast ? 0.3 : 0.16)))
            // A whisker with small caps, so the range still reads where the dot sits inside it.
            var line=Path(); line.move(to:CGPoint(x:cx,y:upper)); line.addLine(to:CGPoint(x:cx,y:lower))
            for y in [upper,lower] { line.move(to:CGPoint(x:cx-2.5,y:y)); line.addLine(to:CGPoint(x:cx+2.5,y:y)) }
            context.stroke(line,with:.color(palette.ink.opacity(palette.highContrast ? 0.8 : 0.55)),style:StrokeStyle(lineWidth:0.9,lineCap:.round))
        }

        for i in nights.indices {
            let p=point(i), night=nights[i]
            if peaks.contains(i) {
                context.fill(Path(ellipseIn:CGRect(x:p.x-12,y:p.y-12,width:24,height:24)),with:.radialGradient(Gradient(colors:[palette.accent.opacity(0.45*access.glow),palette.accent.opacity(0)]),center:p,startRadius:0,endRadius:12))
                // A glow is only light; a small caret beneath says "best" in shape as well (rings
                // would overlap on neighbouring nights).
                if access.differentiate {
                    var caret=Path(); caret.move(to:CGPoint(x:p.x,y:p.y+8)); caret.addLine(to:CGPoint(x:p.x-3.5,y:p.y+13)); caret.addLine(to:CGPoint(x:p.x+3.5,y:p.y+13)); caret.closeSubpath()
                    context.fill(caret,with:.color(palette.ink.opacity(0.85)))
                }
            }
            // The selected night's mark is named under the river instead, clear of its Moon.
            if let marker=markers[night.id], i != index {
                SkyGlyph.draw(SkyGlyph.Kind(marker.glyph),in:&context,rect:CGRect(x:p.x-5,y:p.y-21,width:10,height:10),color:palette.ink)
            }
            let r=i==index ? 5.0 : 2.4
            let mark=NightMark.mark(score:night.score.value,hasForecast:night.score.hasForecast,differentiate:access.differentiate)
            let dot=mark.path(center:p,radius:r)
            if mark.filled { context.fill(dot,with:.color(palette.accent)) }
            else { context.fill(dot,with:.color(.black)); context.stroke(dot,with:.color(palette.accent),lineWidth:1.1) }
        }

        // Sparse date labels: the selected night first, then the first night, then the first night
        // of each week. A label that would touch one already placed is left out.
        var placed:[CGRect]=[]
        for i in [index].compactMap({ $0 })+[0]+nights.indices.filter({ startsWeek($0) }) {
            let label=i==0 && startsTonight ? String(localized:"Tonight") : i==0 ? nights[i].park.dayLabel(nights[i].id) : "\(nights[i].park.calendar.component(.day,from:nights[i].id))"
            let text=context.resolve(Text(label).font(.caption2.weight(i==index ? .semibold : .regular)).foregroundStyle(i==index ? palette.ink : palette.muted))
            let measured=text.measure(in:size)
            let cx=min(max(x(i,width:size.width),measured.width/2),size.width-measured.width/2)
            let frame=CGRect(x:cx-measured.width/2-3,y:size.height-measured.height,width:measured.width+6,height:measured.height)
            guard !placed.contains(where:{ $0.intersects(frame) }) else { continue }
            placed.append(frame)
            context.draw(text,at:CGPoint(x:cx,y:size.height-measured.height/2))
        }
    }
    private func startsWeek(_ i:Int)->Bool {
        let park=nights[i].park
        return park.calendar.component(.weekday,from:nights[i].id)==park.calendar.firstWeekday
    }
}
/// The river's VoiceOver extras: its Audio Graph, jumps to the best nights (a rotor needs one
/// element per entry, and the river is one element, so these are actions), and Feel the Moon.
private struct RiverAccessibility: ViewModifier {
    let nights:[Night]
    let outlooks:[Date:NightOutlook]
    let markers:[Date:WhatsUp.Events.Marker]
    /// Best first.
    let peaks:[Int]
    let current:Int?
    let choose:(Int)->Void
    func body(content:Content)->some View {
        let nights=nights, outlooks=outlooks, events=markers.mapValues(\.name)
        let title=String(localized:"Darkness score, \(nights.count) nights")
        content
            .nightChart { NightChart.nights(nights,title:title,outlooks:outlooks,events:events) }
            .accessibilityActions {
                if let best=peaks.first { Button("Best night") { choose(best) } }
                if peaks.count>1 {
                    Button("Next of the best nights") {
                        // The best nights in date order, starting after the one shown.
                        let ordered=peaks.sorted()
                        if let next=ordered.first(where:{ $0>(current ?? -1) }) ?? ordered.first { choose(next) }
                    }
                }
                if MoonHaptics.enabled, let current, nights.indices.contains(current) {
                    Button("Feel the Moon") { let moon=nights[current].sky.moon; MoonHaptics.shared.play(.moon(illumination:moon.illumination,waxing:moon.waxing)) }
                }
            }
    }
}
#Preview("River") { if let p=try? ParkData.load().first(where:{$0.id=="jotr"}) { let m=PlanModel();TimeRiver(nights:m.nights(p,from:.now,count:30),selected:.constant(m.tonight(p))).padding().background(.black) } }
#Preview("River • AX5") { if let p=try? ParkData.load().first(where:{$0.id=="jotr"}) { let m=PlanModel();TimeRiver(nights:m.nights(p,from:.now,count:30),selected:.constant(m.tonight(p))).padding().dynamicTypeSize(.accessibility5).background(.black) } }
#Preview("Empty river") { TimeRiver(nights:[],selected:.constant(.now)).padding().background(.black) }
