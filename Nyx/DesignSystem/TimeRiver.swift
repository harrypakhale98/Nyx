import SwiftUI
import TipKit

/// True while a horizontal scrub is under way, so the page can hold still instead of drifting.
struct RiverScrubbingKey:PreferenceKey {
    static let defaultValue=false
    static func reduce(value:inout Bool,nextValue:()->Bool) { value = value || nextValue() }
}
/// Thirty nights as one flowing line. Drag across it (or swipe up/down with VoiceOver)
/// to scrub; the moon above the selected night morphs as you go. Nights without a full cloud
/// forecast are dashed (hollow beyond the forecast, half-filled for an early look), a small tick
/// marks where the forecast ends, and the best nights glow amber. Within the seven-day model
/// horizon a soft vertical glow behind each night spans the scores the clearest and cloudiest of
/// three forecast models would give, so uncertainty is something you can see, not a footnote.
/// The selected night's caption carries the meaning (date, score, what its clouds rest on); a
/// one-time tip explains the marks instead of a standing legend. The chosen night sits under a
/// small Liquid Glass lens that bends the river beneath it and answers the finger (solid in night
/// vision, under Reduce Transparency and Increase Contrast).
/// Without a long drag: VoiceOver and Voice Control adjust it a night at a time (activating it
/// says the night, never jumps to the middle one); with "prefers action slider alternative" or
/// Switch Control, previous and next night buttons sit under it; at accessibility sizes it becomes
/// a stepper.
struct TimeRiver: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
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
    /// Activating the river (VoiceOver double-tap, Voice Control "Tap River", Switch Control's
    /// select) opens the chosen night's breakdown when the page offers one; otherwise it is spoken.
    var open:((Night)->Void)?=nil
    /// Whether the current drag is a horizontal scrub; reset by the system even when a drag is cancelled.
    @GestureState private var scrubbing: Bool?=nil
    /// Haptic ticks follow a person's choice, never a data refresh.
    @State private var detents=0
    /// Counts a person's choices, so the Moon's texture follows a scrub once it settles.
    @State private var felt=0
    /// The night under an iPad's pointer, marked faintly before it is clicked.
    @State private var hovered: Int?
    /// The selected night's position; nil when it is not on the river, which then marks no night
    /// rather than pretending the first one is chosen.
    private var index:Int? { nights.firstIndex(where:{$0.park.calendar.isDate($0.id,inSameDayAs:selected)}) }
    private var current:Night? { index.map { nights[$0] } }
    /// The three best nights, at least Good, receive the amber glow: by score, which beyond the
    /// forecast already counts the park's usual clouds, never a clear sky.
    private var peaks:Set<Int> {
        let ranks=nights.map(\.rankScore)
        return Set(nights.indices.filter { ranks[$0]>=60 }.sorted { ranks[$0]>ranks[$1] || (ranks[$0]==ranks[$1] && $0<$1) }.prefix(3))
    }
    private let inset=14.0, moonSize=30.0, lensSize=30.0
    private let tip=RiverTip()

    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Eyebrow(text:startsTonight ? "The next 30 nights" : "30 nights from \(nights.first.map { $0.park.dayLabel($0.id) } ?? "")")
            if showsTip && !nights.isEmpty && !typeSize.isAccessibilitySize { TipView(tip,arrowEdge:.bottom).tipBackground(palette.panel).tint(palette.accent) }
            if nights.isEmpty {
                Text("No nights available").font(.subheadline).foregroundStyle(palette.muted)
            } else if typeSize.isAccessibilitySize {
                stepper
            } else {
                river
                summary
                if access.preferSteps { stepButtons }
            }
            #if DEBUG
            // UI tests: activates the river as VoiceOver would (`accessibilityActivate`), not as a touch.
            if DebugScenario.isEnabled("activate-river") { Button { _=DebugAccessibility.activate(label:String(localized:"Thirty-night darkness timeline")) } label:{ Text(verbatim:"Activate the river") } }
            #endif
            // Shapes stand in for colour under Differentiate Without Color; they need their key.
            if access.differentiate && !typeSize.isAccessibilitySize { Text(NightMark.legend+" "+String(localized:"Small triangles beneath mark the three best nights.")).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
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
                    lens.offset(x:x(index,width:width)-lensSize/2,y:y(current.score.value,height:proxy.size.height)-lensSize/2)
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
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): let i=nearest(location.x,width:width); hovered=nights.indices.contains(i) ? i : nil
                case .ended: hovered=nil
                }
            }
        }
        .frame(height:150)
        .accessibilityElement()
        .accessibilityLabel("Thirty-night darkness timeline")
        .accessibilityValue(spokenValue)
        .accessibilityHint("Moves one night at a time. An audio graph is available.")
        // An explicit activation, so a double-tap or "Tap River" says the night (or opens it) instead
        // of landing a tap on the middle of the river and choosing whichever night lies there.
        .accessibilityAction { activate() }
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

    /// The selected night in words: its date and score, then what the score rests on.
    private var summary: some View {
        VStack(alignment:.leading,spacing:4) {
            if let current {
                HStack(alignment:.firstTextBaseline) {
                    Text(current.park.dayLabel(current.id)).font(.subheadline)
                    Spacer(minLength:8)
                    Text("\(current.score.value)").font(.system(.title3,design:.serif)).foregroundStyle(palette.accent).contentTransition(.numericText(value:Double(current.score.value)))
                    Text(current.score.band.label).font(.caption).foregroundStyle(palette.muted)
                }
                HStack(alignment:.firstTextBaseline,spacing:6) {
                    if let marker=markers[current.id] { SkyGlyph(SkyGlyph.Kind(marker.glyph),color:palette.accent).frame(width:12,height:12) }
                    Text(caption(current)).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }
            }
        }.accessibilityHidden(true)
    }
    /// "No cloud forecast yet", "Early look", "Cloud forecast · models range 62–88", then a shower or an eclipse.
    func caption(_ night:Night)->String {
        var parts=[night.basisLabel ?? String(localized:"Cloud forecast")]
        if let outlook=outlooks[night.id], outlook.agreement.map({ $0.band != .agree }) == true, let range=outlook.scoreRange, range.upperBound>range.lowerBound {
            parts.append(String(localized:"models range \(range.lowerBound)–\(range.upperBound)"))
        }
        if let marker=markers[night.id] { parts.append(marker.name) }
        return parts.joined(separator:" · ")
    }
    /// The scrub position: a small lens of Liquid Glass over the chosen night, which bends the river
    /// under it and responds to the finger. Solid where glass would cost legibility or is unwanted.
    @ViewBuilder private var lens: some View {
        if palette.nightVision || palette.highContrast || reduceTransparency {
            Circle().fill(palette.panel.opacity(0.35)).overlay(Circle().strokeBorder(palette.accent,lineWidth:1.2))
                .frame(width:lensSize,height:lensSize).allowsHitTesting(false).accessibilityHidden(true)
        } else {
            Color.clear.frame(width:lensSize,height:lensSize)
                .glassEffect(.regular.interactive(),in:.circle)
                .overlay(Circle().strokeBorder(palette.accent.opacity(0.55),lineWidth:0.8))
                .accessibilityHidden(true)
        }
    }
    /// Previous and next night, for anyone who prefers buttons to a long drag.
    private var stepButtons: some View {
        HStack(spacing:12) {
            Button { choose((index ?? 1)-1) } label:{ Label("Previous night",systemImage:"chevron.backward").frame(maxWidth:.infinity,minHeight:44) }
                .disabled((index ?? 0)<=0)
            Button { choose((index ?? -1)+1) } label:{ Label("Next night",systemImage:"chevron.forward").frame(maxWidth:.infinity,minHeight:44) }
                .disabled((index ?? nights.count)>=nights.count-1)
        }
        .buttonStyle(.bordered).tint(palette.accent).font(.subheadline.weight(.medium))
        .accessibilityElement(children:.contain)
    }
    /// The river's default action: the chosen night opens, or is spoken.
    private func activate() {
        if let current, let open { open(current); return }
        AccessibilityNotification.Announcement(spokenValue).post()
    }
    /// At accessibility text sizes the drawn river gives way to a plain, large stepper.
    private var stepper: some View {
        Stepper(value:Binding(get:{index ?? 0},set:choose),in:0...max(0,nights.count-1)) {
            Text(spokenValue).font(.subheadline).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
        }.tint(palette.controlTint).foregroundStyle(palette.ink,palette.muted,palette.muted)
            .accessibilityLabel("Selected night").accessibilityValue(spokenValue).accessibilityHint("Moves one night at a time.")
            .accessibilityInputLabels([Text("Night"),Text("Selected night")])
            .modifier(RiverAccessibility(nights:nights,outlooks:outlooks,markers:markers,peaks:peakOrder,current:index,choose:choose))
    }

    private var spokenValue: String {
        guard let current else { return String(localized:"No nights available") }
        let clouds=current.basisCaption(typical:true) ?? String(localized:"Forecast included")
        return String(localized:"\(current.park.dayLabel(current.id)), \(current.score.value) out of 100, \(current.score.band.label). \(clouds)")+(agreementSpoken(current).map { ". "+$0 } ?? "")+(markers[current.id].map { ". "+$0.name } ?? "")
    }
    private func agreementSpoken(_ night:Night)->String? {
        guard let outlook=outlooks[night.id], let agreement=outlook.agreement else { return nil }
        guard agreement.band != .agree, let range=outlook.scoreRange, range.upperBound>range.lowerBound else { return String(localized:"Forecast models agree.") }
        return agreement.band == .roughly ? String(localized:"Forecast models roughly agree; the score could be \(range.lowerBound) to \(range.upperBound).")
            : String(localized:"Forecast models disagree; the score could be \(range.lowerBound) to \(range.upperBound).")
    }
    private var showsTip:Bool { DebugScenario.screen == nil || DebugScenario.isEnabled("river-tip") }
    /// The glowing nights, best first.
    private var peakOrder:[Int] {
        let ranks=nights.map(\.rankScore)
        return peaks.sorted { ranks[$0]>ranks[$1] || (ranks[$0]==ranks[$1] && $0<$1) }
    }

    /// A score's height on the river, as `draw` places it.
    private func y(_ score:Int,height:Double)->Double {
        let top=moonSize+12, bottom=height-22
        return bottom-(bottom-top)*Double(score)/100
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
        // The detent sharpens with the night's score where Core Haptics can say so.
        if MoonHaptics.enabled { MoonHaptics.shared.detent(score:nights[value].score.value) } else { detents+=1 }
        felt+=1
        tip.invalidate(reason:.actionPerformed)
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

        // The pointer's night, a fainter hairline and ring than the chosen one.
        if let hovered, hovered != index, nights.indices.contains(hovered) {
            let p=point(hovered)
            var hairline=Path(); hairline.move(to:CGPoint(x:p.x,y:moonSize+8)); hairline.addLine(to:CGPoint(x:p.x,y:bottom+4))
            context.stroke(hairline,with:.color(palette.line),style:StrokeStyle(lineWidth:0.6,dash:[2,3]))
            context.stroke(Path(ellipseIn:CGRect(x:p.x-6,y:p.y-6,width:12,height:12)),with:.color(palette.accent.opacity(0.7)),lineWidth:0.9)
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

        // Model spread: a soft vertical glow from the cloudiest model's score to the clearest's,
        // brightest in the middle and fading at both ends, so it reads as a range, not a glyph.
        context.drawLayer { glow in
            glow.addFilter(.blur(radius:1.5))
            for i in nights.indices {
                guard let range=outlooks[nights[i].id]?.scoreRange, range.upperBound>range.lowerBound else { continue }
                let cx=x(i,width:size.width)
                let upper=bottom-span*Double(range.upperBound)/100-4, lower=bottom-span*Double(range.lowerBound)/100+4
                let strength=palette.highContrast ? 0.45 : 0.26
                glow.fill(Path(roundedRect:CGRect(x:cx-4,y:upper,width:8,height:lower-upper),cornerRadius:4),
                          with:.linearGradient(Gradient(stops:[.init(color:palette.ink.opacity(0),location:0),.init(color:palette.ink.opacity(strength),location:0.3),.init(color:palette.ink.opacity(strength),location:0.7),.init(color:palette.ink.opacity(0),location:1)]),
                                               startPoint:CGPoint(x:cx,y:upper),endPoint:CGPoint(x:cx,y:lower)))
            }
        }
        // Where the cloud forecast ends: a quiet tick between the last forecast night and the first without.
        if let lastForecast, lastForecast<nights.count-1 {
            let fx=(x(lastForecast,width:size.width)+x(lastForecast+1,width:size.width))/2
            var tick=Path(); tick.move(to:CGPoint(x:fx,y:top+4)); tick.addLine(to:CGPoint(x:fx,y:bottom))
            context.stroke(tick,with:.color(palette.ink.opacity(palette.highContrast ? 0.6 : 0.3)),style:StrokeStyle(lineWidth:0.7,dash:[1,3]))
            let label=context.resolve(Text("forecast ends").font(.caption2).foregroundStyle(palette.muted))
            let measured=label.measure(in:size)
            let lx=min(max(fx+4+measured.width/2,measured.width/2),size.width-measured.width/2)
            context.draw(label,at:CGPoint(x:lx,y:bottom-measured.height/2-2))
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
            let mark=NightMark.mark(night,differentiate:access.differentiate)
            mark.draw(in:&context,center:p,radius:r,fill:night.basis.fill,color:palette.accent,fillOpacity:1,hollowBackground:.black)
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
#Preview("River • Steps") { if let p=try? ParkData.load().first(where:{$0.id=="jotr"}) { let m=PlanModel();TimeRiver(nights:m.nights(p,from:.now,count:30),selected:.constant(m.tonight(p))).padding().environment(\.nyxAccess,NyxAccess(preferSteps:true)).background(.black) } }
#Preview("River • Night vision") { if let p=try? ParkData.load().first(where:{$0.id=="jotr"}) { let m=PlanModel();TimeRiver(nights:m.nights(p,from:.now,count:30),selected:.constant(m.tonight(p))).padding().environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).background(.black) } }
#Preview("Empty river") { TimeRiver(nights:[],selected:.constant(.now)).padding().background(.black) }
#if DEBUG
/// The river route's own selection, so a scrub, a step or an activation can move it (or not) as in a park page.
struct DebugRiverHost: View {
    let nights:[Night]
    @State var start:Date
    var outlooks:[Date:NightOutlook]=[:]
    var markers:[Date:WhatsUp.Events.Marker]=[:]
    var body: some View { TimeRiver(nights:nights,selected:$start,outlooks:outlooks,markers:markers) }
}
#endif
/// The river explains itself once, then gets out of the way: it closes after the first scrub.
struct RiverTip: Tip {
    var title: Text { Text("Drag along the nights") }
    var message: Text? { Text("Hollow nights have no cloud forecast yet; half-filled ones are an early look. A soft glow spans what three forecast models expect.") }
    var image: Image? { Image(systemName:"hand.draw") }
}
