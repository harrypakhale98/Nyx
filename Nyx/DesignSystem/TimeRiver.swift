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
/// small Liquid Glass lens that bends the river beneath it. While a finger scrubs, the lens grows
/// into a loupe lifted above the finger that shows the night's date and score (the finger covers
/// the date row), and the Moon steps beside it, since the page's gauge is usually scrolled away by
/// then (solid in night vision, under Reduce Transparency and Increase Contrast; hidden from
/// VoiceOver, which hears the river's value).
/// Without a long drag: VoiceOver and Voice Control adjust it a night at a time (activating it
/// says the night, never jumps to the middle one); with "prefers action slider alternative" or
/// Switch Control, previous and next night buttons sit under it; at accessibility sizes it becomes
/// a stepper with the best nights a button away.
struct TimeRiver: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    @Environment(\.nyxAccess) private var access
    @Environment(\.locale) private var locale
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
    /// Paces the Moon-haptics detents of a fast scrub that skips nights.
    @State private var pacer=RiverDetents()
    /// Counts a person's choices, so the Moon's texture follows a scrub once it settles.
    @State private var felt=0
    /// A scrub has chosen a night; the tip closes when the finger lifts, not under it.
    @State private var tipPending=false
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
    /// The loupe while scrubbing: its size, its lift above the night's point, and how far it may
    /// rise above the river into the panel (over the eyebrow, never past the panel's padding).
    private let loupeSize=56.0, loupeLift=34.0, loupeHeadroom=24.0
    /// The loupe is up: a horizontal scrub is under way (or a DEBUG capture holds it up).
    private var lifted:Bool { scrubbing==true || DebugScenario.isEnabled("loupe") }
    private let tip=RiverTip()
    private var tipShown:Bool { showsTip && !nights.isEmpty && !typeSize.isAccessibilitySize }
    /// While the tip is above the river the loupe may not rise into its arrow.
    private var tipHeadroom:Double? { tipShown && tip.shouldDisplay ? 0 : nil }

    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Eyebrow(text:startsTonight ? "The next 30 nights" : "30 nights from \(nights.first.map { $0.park.dayLabel($0.id) } ?? "")")
            // The tip stays readable through the first scrub (the loupe keeps below it, `tipHeadroom`), so
            // nothing under the finger moves; it closes once the scrub ends.
            if tipShown { TipView(tip,arrowEdge:.bottom).tipBackground(palette.panel).tint(palette.accent) }
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
        .onChange(of:scrubbing==true) { _,now in if !now && tipPending { tipPending=false; tip.invalidate(reason:.actionPerformed) } }
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
                // The selected night's hairline, from the Moon (or, while scrubbing, the loupe) down to
                // the date row: a shape rather than part of the drawing, so it travels and stretches
                // on the same spring as the loupe and never comes loose from it.
                if let current,let index {
                    let point=CGPoint(x:x(index,width:width),y:y(current.score.value,height:proxy.size.height))
                    let top=lifted ? Self.loupeBottom(loupeCenter(point,width:width,headroom:tipHeadroom),x:point.x,radius:loupeSize/2) : moonSize+2
                    let bottom=proxy.size.height-22+4
                    Rectangle().fill(palette.line).frame(width:0.6*palette.stroke,height:max(0,bottom-top))
                        .offset(x:point.x-0.3*palette.stroke,y:top).accessibilityHidden(true)
                }
                Canvas { context,size in draw(in:&context,size:size) }
                    .accessibilityHidden(true)
                if let current,let index {
                    let point=CGPoint(x:x(index,width:width),y:y(current.score.value,height:proxy.size.height))
                    let loupe=lifted ? loupeCenter(point,width:width,headroom:tipHeadroom) : point
                    let moon=lifted ? moonBeside(loupe,point:point,width:width) : CGPoint(x:point.x,y:moonSize/2)
                    let size=lifted ? loupeSize : lensSize
                    MoonView(geometry:AstronomyEngine().moon(for:current).geometry)
                        .frame(width:moonSize,height:moonSize)
                        .offset(x:moon.x-moonSize/2,y:moon.y-moonSize/2)
                        .accessibilityHidden(true)
                    lens(current,size:size).offset(x:loupe.x-size/2,y:loupe.y-size/2)
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
        // The loupe grows and settles on the shared spring; under Reduce Motion it simply changes size.
        .animation(reduceMotion ? nil : NyxMotion.spring,value:lifted)
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
    /// "No cloud forecast yet", "Early look", "Cloud forecast · models range 62–88", then a shower or
    /// an eclipse. At accessibility sizes each part takes a line of its own (`separator: "\n"`), so
    /// a range never breaks across lines.
    func caption(_ night:Night,separator:String=" · ")->String {
        var parts=[night.basisLabel ?? String(localized:"Cloud forecast")]
        if let outlook=outlooks[night.id], outlook.agreement.map({ $0.band != .agree }) == true, let range=outlook.scoreRange, range.upperBound>range.lowerBound {
            parts.append(String(localized:"models range \(range.lowerBound)–\(range.upperBound)"))
        }
        if let marker=markers[night.id] { parts.append(marker.name) }
        return parts.joined(separator:separator)
    }
    /// The scrub position: a small lens of Liquid Glass over the chosen night, which bends the river
    /// under it. While scrubbing it is a 56 pt loupe naming the night under the finger (its short
    /// date, "Fri 16") above its score in light serif, on glass tinted like the panel so both keep
    /// their contrast over the river. Solid panel colour where glass would cost legibility or is unwanted.
    @ViewBuilder private func lens(_ night:Night,size:Double)->some View {
        let solid=palette.nightVision || palette.highContrast || reduceTransparency
        ZStack {
            if lifted {
                VStack(spacing:1) {
                    // The finger covers the date row; the loupe carries the night's date above it.
                    Text(Self.loupeDate(night.id,locale:locale,timeZone:night.park.timeZone)).font(.system(size:10,weight:.semibold)).monospacedDigit()
                        .foregroundStyle(palette.muted).lineLimit(1).minimumScaleFactor(0.8)
                    // Light, or regular under Bold Text, as the strokes follow it.
                    Text(verbatim:"\(night.score.value)").font(.system(size:22,weight:palette.stroke>1 ? .regular : .light,design:.serif)).monospacedDigit()
                        .foregroundStyle(palette.accent).contentTransition(.numericText(value:Double(night.score.value)))
                }.transition(.opacity)
            }
        }
        .frame(width:size,height:size)
        .modifier(LoupeSurface(solid:solid,lifted:lifted))
        .allowsHitTesting(false).accessibilityHidden(true)
    }
    /// The loupe's date: the weekday and day in the reader's language, in the park's own time zone
    /// ("Fri 16", "vie 16"). Always the date, never "Tonight", so it reads the same on every night.
    nonisolated static func loupeDate(_ date:Date,locale:Locale,timeZone:TimeZone)->String {
        date.formatted(Date.FormatStyle(locale:locale,timeZone:timeZone).weekday(.abbreviated).day())
    }
    /// Where the loupe sits: lifted above the night's point, kept inside the river's width and at
    /// most `headroom` (`loupeHeadroom` by default) above it (a Pristine night near the top lifts
    /// less, never out of the panel, and not at all into the tip's arrow while the tip shows).
    func loupeCenter(_ point:CGPoint,width:Double,headroom:Double?=nil)->CGPoint {
        CGPoint(x:min(max(point.x,loupeSize/2),width-loupeSize/2),y:max(point.y-loupeLift,loupeSize/2-(headroom ?? loupeHeadroom)))
    }
    /// The hairline's top under the loupe: the circle's own lower edge above the night, which at the
    /// first and last nights (the loupe held inside the river) is off the circle's lowest point.
    static func loupeBottom(_ loupe:CGPoint,x:Double,radius:Double)->Double {
        let dx=x-loupe.x
        return loupe.y+(abs(dx)<radius ? (radius*radius-dx*dx).squareRoot() : 0)
    }
    /// The Moon while scrubbing keeps its own row above the river (y 0 to `moonSize`, above every
    /// night's mark), so it never covers the nights being scrubbed. Only when the loupe rises into
    /// that row does the Moon step beside it, toward the middle of the river, so the loupe never
    /// covers it either and the phase still morphs night by night.
    func moonBeside(_ loupe:CGPoint,point:CGPoint,width:Double)->CGPoint {
        let row=moonSize/2
        guard loupe.y-loupeSize/2<moonSize+4 else { return CGPoint(x:min(max(point.x,moonSize/2),width-moonSize/2),y:row) }
        let gap=loupeSize/2+6+moonSize/2
        return CGPoint(x:point.x<width/2 ? loupe.x+gap : loupe.x-gap,y:row)
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
    /// At accessibility text sizes the drawn river gives way to a plain, large stepper: the date,
    /// the score as a large numeral with its band, the stepper on a row of its own, buttons to the
    /// best night and the next of the best (the glow they replace is not drawn here), then what the
    /// score rests on, a part to a line. VoiceOver hears the stepper as before (the best nights are
    /// also its actions); the words above it are what a sighted reader sees.
    private var stepper: some View {
        VStack(alignment:.leading,spacing:10) {
            if let current {
                VStack(alignment:.leading,spacing:6) {
                    Text(current.park.dayLabel(current.id)).font(.headline).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
                    ViewThatFits(in:.horizontal) {
                        HStack(alignment:.firstTextBaseline,spacing:10) { stepperScore(current) }
                        VStack(alignment:.leading,spacing:2) { stepperScore(current) }
                    }
                }.accessibilityHidden(true)
            }
            Stepper("Selected night",value:Binding(get:{index ?? 0},set:choose),in:0...max(0,nights.count-1))
                .labelsHidden().frame(maxWidth:.infinity,alignment:.leading)
                // The third style fills the stepper's capsule under clear − and + glyphs (`stepperFill`).
                .tint(palette.controlTint).foregroundStyle(palette.ink,palette.muted,stepperFill)
                .accessibilityLabel("Selected night").accessibilityValue(spokenValue).accessibilityHint("Moves one night at a time.")
                .accessibilityInputLabels([Text("Night"),Text("Selected night")])
                .modifier(RiverAccessibility(nights:nights,outlooks:outlooks,markers:markers,peaks:peakOrder,current:index,choose:choose))
            // The best nights are a button away for sighted readers too (VoiceOver has them as actions).
            if let best=peakOrder.first {
                VStack(alignment:.leading,spacing:10) {
                    Button { choose(best) } label:{ bestLabel("Best night") }
                        .disabled(index==best)
                    if peakOrder.count>1 {
                        Button { if let next=Self.nextPeak(peaks:peakOrder,current:index) { choose(next) } } label:{ bestLabel("Next of the best nights") }
                    }
                }
                .buttonStyle(.bordered).tint(palette.accent).font(.subheadline.weight(.medium))
            }
            if let current {
                Text(Self.lineCaption(caption(current,separator:"\n"))).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true).accessibilityHidden(true)
            }
        }
    }
    /// The AX stepper's capsule: amber-brown on the panel (in night vision a dark red, the red ink at
    /// 0.26), as the journal's
    /// Bortle stepper, but translucent. The stepper draws a glyph it has disabled (− on tonight, +
    /// on the last night) in this same style over the capsule, so an opaque fill would make that
    /// glyph vanish; at half strength it stays a dim, legible mark, and the enabled glyph in
    /// starlight keeps at least 4.5:1 on the capsule.
    private var stepperFill: Color { palette.nightVision ? palette.ink.opacity(0.26) : palette.accent.opacity(0.5) }
    /// Words alone: at these sizes a glyph would take a column of its own.
    private func bestLabel(_ title:LocalizedStringKey)->some View {
        Text(title).multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true)
            .frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
    }
    /// A caption a part to a line, with each number kept to the word before it ("range 55–83"), so a
    /// line that must wrap never leaves the figures on their own.
    nonisolated static func lineCaption(_ text:String)->String {
        text.replacingOccurrences(of:" (?=[0-9])",with:"\u{00A0}",options:.regularExpression)
    }
    /// The next of the best nights in date order after the one shown, wrapping to the first; the
    /// first when none is chosen.
    nonisolated static func nextPeak(peaks:[Int],current:Int?)->Int? {
        let ordered=peaks.sorted()
        return ordered.first(where:{ $0>(current ?? -1) }) ?? ordered.first
    }
    @ViewBuilder private func stepperScore(_ night:Night)->some View {
        Text(verbatim:"\(night.score.value)").font(.system(.largeTitle,design:.serif).weight(.light)).foregroundStyle(palette.accent)
            .contentTransition(.numericText(value:Double(night.score.value)))
        Text(night.score.band.label).font(.title3).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
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
        let from=index
        withAnimation(reduceMotion ? nil : NyxMotion.spring) { selected=nights[value].id }
        // The detent sharpens with the night's score where Core Haptics can say so. A fast scrub that
        // skips nights feels each one it crossed (at most three, 40 ms apart); a tap, a step or
        // VoiceOver's adjustment is one choice and one detent.
        if MoonHaptics.enabled {
            let crossed=scrubbing==true ? RiverDetents.crossed(from:from,to:value) : [value]
            pacer.play(crossed.map { nights[$0].score.value })
        } else { detents+=1 }
        felt+=1
        if scrubbing==true { tipPending=true } else { tip.invalidate(reason:.actionPerformed) }
    }

    private func draw(in context:inout GraphicsContext,size:CGSize) {
        let top=moonSize+12, bottom=size.height-22, span=bottom-top
        func point(_ i:Int)->CGPoint { CGPoint(x:x(i,width:size.width),y:bottom-span*Double(nights[i].score.value)/100) }
        let lastForecast=nights.lastIndex { $0.score.hasForecast }

        // The selected night's hairline is a shape beneath this drawing (see `river`).

        // The pointer's night, a fainter hairline and ring than the chosen one.
        if let hovered, hovered != index, nights.indices.contains(hovered) {
            let p=point(hovered)
            var hairline=Path(); hairline.move(to:CGPoint(x:p.x,y:moonSize+8)); hairline.addLine(to:CGPoint(x:p.x,y:bottom+4))
            context.stroke(hairline,with:.color(palette.line),style:StrokeStyle(lineWidth:0.6*palette.stroke,dash:[2,3]))
            context.stroke(Path(ellipseIn:CGRect(x:p.x-6,y:p.y-6,width:12,height:12)),with:.color(palette.accent.opacity(0.7)),lineWidth:0.9*palette.stroke)
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
        if let lastForecast, lastForecast>0 { context.stroke(river(0...lastForecast),with:.color(palette.accent),style:StrokeStyle(lineWidth:1.6*palette.stroke,lineCap:.round)) }
        let dashedStart=(lastForecast ?? -1)+1
        if dashedStart<nights.count {
            context.stroke(river(max(0,dashedStart-1)...(nights.count-1)),with:.color(palette.accent.opacity(0.55)),style:StrokeStyle(lineWidth:1.1*palette.stroke,lineCap:.round,dash:[3,4]))
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
            context.stroke(tick,with:.color(palette.ink.opacity(palette.highContrast ? 0.6 : 0.3)),style:StrokeStyle(lineWidth:0.7*palette.stroke,dash:[1,3]))
            let label=context.resolve(Text("forecast ends").font(.caption2).foregroundStyle(palette.muted))
            let measured=label.measure(in:size)
            let lx=min(max(fx+4+measured.width/2,measured.width/2),size.width-measured.width/2)
            context.draw(label,at:CGPoint(x:lx,y:bottom-measured.height/2-2))
        }

        // Thirty nights stand about 11 pt apart on a phone: the floor that keeps an unfilled mark's
        // half fill readable (`NightMark.draw`) stops short of the neighbouring marks, so the river
        // between them still shows under Bold Text and Increase Contrast.
        let pitch=nights.count>1 ? abs(x(1,width:size.width)-x(0,width:size.width)) : size.width
        let floor=min(NightMark.unfilledFloor(stroke:palette.stroke),max(2.4,pitch*0.28))
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
            mark.draw(in:&context,center:p,radius:r,fill:night.basis.fill,color:palette.accent,fillOpacity:1,stroke:palette.stroke,minimumRadius:i==index ? nil : floor,hollowBackground:.black)
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
                        if let next=TimeRiver.nextPeak(peaks:peaks,current:current) { choose(next) }
                    }
                }
                if MoonHaptics.enabled, let current, nights.indices.contains(current) {
                    Button("Feel the Moon") { let moon=nights[current].sky.moon; MoonHaptics.shared.play(.moon(illumination:moon.illumination,waxing:moon.waxing)) }
                }
            }
    }
}
#Preview("River") { if let p=try? ParkData.load().first(where:{$0.id=="jotr"}) { let m=PlanModel();TimeRiver(nights:m.nights(p,from:.now,count:30),selected:.constant(m.tonight(p))).padding().background(.black) } }
#Preview("River • AX5") { if let p=try? ParkData.load().first(where:{$0.id=="jotr"}) { let m=PlanModel();ScrollView { TimeRiver(nights:m.nights(p,from:.now,count:30),selected:.constant(m.tonight(p))).padding() }.dynamicTypeSize(.accessibility5).background(.black) } }
#Preview("River • AX5 • night vision") { if let p=try? ParkData.load().first(where:{$0.id=="jotr"}) { let m=PlanModel();ScrollView { TimeRiver(nights:m.nights(p,from:.now,count:30),selected:.constant(m.tonight(p))).padding() }.dynamicTypeSize(.accessibility5).environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).background(.black) } }
#Preview("River • Steps") { if let p=try? ParkData.load().first(where:{$0.id=="jotr"}) { let m=PlanModel();TimeRiver(nights:m.nights(p,from:.now,count:30),selected:.constant(m.tonight(p))).padding().environment(\.nyxAccess,NyxAccess(preferSteps:true)).background(.black) } }
#Preview("River • Night vision") { if let p=try? ParkData.load().first(where:{$0.id=="jotr"}) { let m=PlanModel();TimeRiver(nights:m.nights(p,from:.now,count:30),selected:.constant(m.tonight(p))).padding().environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).background(.black) } }
#Preview("River • Loupe") { if let p=try? ParkData.load().first(where:{$0.id=="jotr"}) { let m=PlanModel();VStack(spacing:24) { LoupePreview(night:m.night(p),solid:false);LoupePreview(night:m.night(p),solid:true) }.padding(40).background(Color(red:0.043,green:0.063,blue:0.149)) } }
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
/// The loupe's surface: panel-tinted, interactive Liquid Glass (the small lens is clear glass that
/// bends the river), or under night vision, Reduce Transparency and Increase Contrast a solid
/// panel fill that grows the same way, opaque while lifted so the numeral keeps 4.5:1.
private struct LoupeSurface: ViewModifier {
    @Environment(\.nyx) private var palette
    let solid:Bool
    let lifted:Bool
    @ViewBuilder func body(content:Content)->some View {
        if solid {
            content.background(Circle().fill(lifted ? palette.panel : palette.panel.opacity(0.35)))
                .overlay(Circle().strokeBorder(palette.accent,lineWidth:1.2*palette.stroke))
        } else {
            content.glassEffect(lifted ? Glass.regular.tint(palette.panel.opacity(0.7)).interactive() : Glass.regular.interactive(),in:.circle)
                .overlay(Circle().strokeBorder(palette.accent.opacity(0.55),lineWidth:0.8*palette.stroke))
        }
    }
}
/// The detents a fast scrub plays: one per night crossed, at most three per change (evenly
/// spaced, ending on the night chosen), each at least 40 ms after the last so they stay distinct.
@MainActor final class RiverDetents {
    private var last:ContinuousClock.Instant?
    private var pending:Task<Void,Never>?
    nonisolated static let maximum=3
    static let spacing=Duration.milliseconds(40)
    /// The nights to tick between `from` (exclusive) and `to` (inclusive), in order.
    nonisolated static func crossed(from:Int?,to:Int)->[Int] {
        guard let from, from != to else { return [to] }
        let n=abs(to-from), k=min(maximum,n), sign=to>from ? 1 : -1
        return (1...k).map { j in from+sign*Int((Double(n)*Double(j)/Double(k)).rounded()) }
    }
    func play(_ scores:[Int]) {
        pending?.cancel()
        pending=Task { @MainActor [weak self] in
            for score in scores {
                guard let self, !Task.isCancelled else { return }
                if let last=self.last {
                    let wait=last+Self.spacing-ContinuousClock.now
                    if wait>Duration.zero { try? await Task.sleep(for:wait) }
                }
                if Task.isCancelled { return }
                MoonHaptics.shared.detent(score:score)
                self.last=ContinuousClock.now
            }
        }
    }
}
/// The loupe alone, glass and solid, for previews.
private struct LoupePreview: View {
    @Environment(\.nyx) private var palette
    let night:Night
    let solid:Bool
    var body: some View {
        VStack(spacing:1) {
            Text(TimeRiver.loupeDate(night.id,locale:.current,timeZone:night.park.timeZone)).font(.system(size:10,weight:.semibold)).monospacedDigit().foregroundStyle(palette.muted)
            Text(verbatim:"\(night.score.value)").font(.system(size:22,weight:.light,design:.serif)).monospacedDigit().foregroundStyle(palette.accent)
        }.frame(width:56,height:56).modifier(LoupeSurface(solid:solid,lifted:true))
    }
}
/// The river explains itself once, then gets out of the way: it closes after the first scrub.
struct RiverTip: Tip {
    var title: Text { Text("Drag along the nights") }
    var message: Text? { Text("Hollow nights have no cloud forecast yet; half-filled ones are an early look. A soft glow spans what three forecast models expect.") }
    var image: Image? { Image(systemName:"hand.draw") }
}
