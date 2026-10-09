import SwiftUI

/// The Darkness Score as an instrument. The first time a park, night and score is shown in a
/// session the score counts up like an odometer: a decaying spring, fast at first and settling
/// slowly over the last few points, with the arc leading the numeral by about 80 ms and a medium
/// tick at 70 and 90. Then, in order: the final digit, the band word and a light tick arrive
/// together, and a moment later the forecast models' range fades in along the track. The word is
/// never shown beside a number still counting, so the dial never pairs "81" with "Pristine".
/// The same park and night seen again settles in 0.35 s with one light tick; later changes
/// (scrubbing nights) sweep on the shared spring. While the reveal is unseen and nobody can see it
/// (onboarding over the tabs, first light, another tab, the background), the dial waits empty.
/// The count-up runs at the display's rate and then stops; the ambient stars and the glint redraw
/// at 30 Hz at most.
///
/// Only the drawing scales with the dial, the glass rim included (`DialMetrics`). The numeral is
/// part of the drawing; the band and "DARKNESS / 100" keep their own text styles and move below
/// the dial when it is too small to hold them (onboarding, a small hero) or the text is at an
/// accessibility size, where the numeral stays more than twice the band's size, capped by the width.
struct CelestialGauge: View {
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.nyxAccess) private var access
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.nyxRevealHeld) private var revealHeld
    @ScaledMetric(relativeTo:.title3) private var bandMetric=20.0
    let score: Int
    var hasForecast: Bool=true
    /// What the night's clouds rest on, spoken after the band as the caption under the dial says it
    /// (`Night.basisCaption`): a full forecast, an early look, the usual clouds, or the Moon and
    /// darkness only. Nil keeps the general note.
    var spokenBasis: String?=nil
    /// A still drawing for exported images (share cards): the score at once, no ambient motion,
    /// and no claim on the tilt sensor.
    var export=false
    /// The park, night and score this dial answers (`ScoreReveals.key`): the count-up plays once
    /// per key in a session and waits while it cannot be seen. Nil counts up on every first
    /// appearance, never waits, and remembers nothing.
    var revealKey: String?=nil
    /// The forecast models' range around the score (`modelRange`), drawn after the score settles.
    /// Nil draws none.
    var range: ClosedRange<Int>?=nil
    /// The milestone and landing ticks. Off for an example dial, so the real answer owns them.
    var haptics=true
    /// Called with the `revealKey` the dial has settled on: after the landing, at once without
    /// motion, after each later sweep, and when a settled dial is handed a new key for the score it
    /// already shows. Tonight's subtle double tap waits for its own park and night to arrive here.
    var onSettled: ((String?)->Void)?=nil
    /// Where the arc has reached, 0…100.
    @State private var arc=0.0
    /// The numeral shown.
    @State private var shown=0
    @State private var milestone=0
    @State private var landed=0
    /// The band word shows: the count has landed, was cut short, or never ran.
    @State private var settled=false
    /// The dial waits empty: before the first reveal, and while an unseen reveal is held.
    @State private var waiting=true
    /// The model range has faded in (after the word).
    @State private var rangeShown=false
    /// This dial has settled on a score once; any later score sweeps to it.
    @State private var revealedOnce=false
    /// The score whose count-up last started here: a different score arriving mid-count sweeps.
    @State private var countedScore: Int?
    /// Bumped by every reveal, so a cancelled one never writes over the one after it.
    @State private var generation=0
    /// Where an iPad's pointer rests over the dial: the glint on the glass follows it, like light on a real instrument.
    @State private var pointer: CGPoint?
    /// VoiceOver's sentence, built once per score and range rather than on every frame of the count.
    @State private var spoken=SpokenLabel()
    /// Whether any of the dial shows in its scroll view; the ambient stars rest while it is scrolled away.
    @State private var onScreen=true
    /// The dial's side, measured.
    @State private var side: CGFloat=300
    /// The width offered at accessibility sizes, where the dial grows with the text up to it.
    @State private var available: CGFloat=0
    /// Band and units fit inside a dial this size at standard text sizes.
    static let labelsInsideFrom: CGFloat=236
    private var labelsInside: Bool { !typeSize.isAccessibilitySize && side>=Self.labelsInsideFrom }
    private var still: Bool { reduceMotion || export }
    /// An unseen reveal waits while nobody can watch it: onboarding or first light over the tabs,
    /// scrolled away or in another tab, or Nyx in the background. Not while merely inactive: a
    /// cold launch stays inactive for about a second with the dial already on screen.
    private var held: Bool { revealKey != nil && (revealHeld || !onScreen || scenePhase == .background) }
    private var bandVisible: Bool { still || settled }
    private var numeralVisible: Bool { still || !waiting }
    private var rangeVisible: Bool { still || (settled && rangeShown) }
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                let dial=Self.accessibleSide(band:bandMetric,width:available)
                VStack(spacing:16) {
                    ZStack { bezel; drawing; numeral(size:Self.accessibleNumeral(band:bandMetric,side:dial)) }.frame(width:dial,height:dial)
                    band
                    units
                }
                .frame(maxWidth:.infinity)
                .onGeometryChange(for:CGFloat.self) { $0.size.width } action:{ available=$0 }
            } else {
                VStack(spacing:6) {
                    ZStack { bezel; drawing }
                        .overlay { VStack(spacing:5) { numeral(size:side*0.36); if labelsInside { band; units.padding(.top,side<270 ? 2 : 8) } } }
                        .frame(maxWidth:300).aspectRatio(1,contentMode:.fit)
                        .onGeometryChange(for:CGFloat.self) { min($0.size.width,$0.size.height) } action:{ side=$0 }
                        // No taller than on the widest iPhone, so a wide column does not open a gap around the dial.
                        .frame(maxWidth:354)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location): pointer=location
                            case .ended: pointer=nil
                            }
                        }
                    if !labelsInside { band; units }
                }
            }
        }
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityInputLabels([Text("Score"),Text("Darkness score")])
        .task(id:RevealTrigger(score:score,held:held)) { await reveal() }
        .onDisappear { if !revealedOnce { countedScore=nil } }
        // Another park or night with the score already on the dial: nothing moves, but it has settled.
        .onChange(of:revealKey) { _,key in if settled && !waiting && shown==score { onSettled?(key) } }
        .sensoryFeedback(.impact(weight:.medium),trigger:milestone) { _,_ in haptics }
        .sensoryFeedback(.impact(weight:.light),trigger:landed) { _,_ in haptics }
        .onScrollVisibilityChange(threshold:0.02) { onScreen=$0 }
        // Tilt only while the glint can be drawn and the dial is in view.
        .motionTilt(onScreen && !export && !reduceMotion && !palette.nightVision && !access.reduceHighlighting && !access.reducedResources)
    }
    /// The label is the settled answer from the first frame (VoiceOver never hears the count),
    /// with the models' range when the dial draws it.
    private var accessibilityText: String {
        spoken.text(for:SpokenLabel.Inputs(score:score,hasForecast:hasForecast,basis:spokenBasis,range:range)) { inputs in
            let basis=inputs.basis ?? (inputs.hasForecast ? String(localized:"Includes cloud forecast.") : String(localized:"No full cloud forecast; usual clouds count."))
            let label=String(localized:"Darkness score \(inputs.score) out of 100. \(ScoreBand.band(inputs.score).label). \(basis)")
            guard let range=inputs.range else { return label }
            return label+" "+String(localized:"Forecast models: \(range.lowerBound) to \(range.upperBound).")
        }
    }
    // MARK: The count-up

    /// The odometer's progress `t` seconds in: an exponential settle, fastest at the start.
    nonisolated static func progress(_ t:Double,settle:Double=0.28)->Double { t<=0 ? 0 : 1-exp(-t/settle) }
    /// The arc leads the numeral by this much.
    nonisolated static let numeralLag=0.08
    /// The numeral `t` seconds into the count-up.
    nonisolated static func countValue(score:Int,at t:Double)->Int { min(score,Int((Double(score)*progress(t-numeralLag)).rounded())) }
    /// The milestones a step of the count from `old` to `new` crosses (70 and 90), for the medium ticks.
    nonisolated static func milestones(from old:Int,to new:Int)->[Int] { [70,90].filter { old<$0 && new>=$0 } }
    /// How long the count-up runs for a score: until the numeral rounds to it.
    nonisolated static func duration(score:Int)->Double { score<=0 ? 0 : 0.28*log(2.2*Double(score))+numeralLag }
    /// How long a score already seen this session takes to settle.
    nonisolated static let settleDuration=0.35

    /// What a reveal does, decided before anything moves:
    /// - `instant`: Reduce Motion and exported images show the score at once, even while held.
    /// - `sweep`: this dial already settled once, or its count was overtaken by a new score (cached,
    ///   then computed): the shared spring to the new score, a light tick only if it never landed.
    /// - `settle`: the park, night and score were revealed earlier this session: a 0.35 s spring,
    ///   one light tick, no milestone pulses.
    /// - `hold`: unseen, and nobody can watch: the dial waits empty and silent.
    /// - `odometer`: the full count-up, the only reveal that marks its key as seen.
    nonisolated enum RevealPlan: Equatable, Sendable { case hold, instant, sweep, settle, odometer }
    nonisolated static func plan(seen:Bool,held:Bool,reduceMotion:Bool,export:Bool,alreadyRevealed:Bool)->RevealPlan {
        if reduceMotion || export { return .instant }
        if alreadyRevealed { return .sweep }
        if seen { return .settle }
        if held { return .hold }
        return .odometer
    }
    /// Whether a reveal finds this dial already answered: it settled once, or its count-up for a
    /// different score was under way when the new score arrived.
    nonisolated static func alreadyRevealed(revealedOnce:Bool,countedScore:Int?,score:Int)->Bool {
        revealedOnce || countedScore.map { $0 != score } == true
    }
    /// The part of the dial a reveal decides: where the arc is, the numeral, and whether the word shows.
    nonisolated struct Face: Equatable, Sendable {
        var arc: Double
        var shown: Int
        var settled: Bool
        static let empty=Face(arc:0,shown:0,settled:false)
        static func answer(_ score:Int)->Face { Face(arc:Double(score),shown:score,settled:true) }
    }
    /// Where each plan leaves the dial: the whole answer, or empty while held. The odometer starts empty.
    nonisolated static func face(after plan:RevealPlan,score:Int)->Face {
        switch plan {
        case .hold, .odometer: .empty
        case .instant, .sweep, .settle: .answer(score)
        }
    }
    /// What a cancelled count-up leaves behind. SwiftUI cancels the old task when the score or the
    /// hold changes and starts the next reveal at once, so the old count's cleanup can run before or
    /// after the new reveal has written the dial. If no reveal came after it (`generation == mine`,
    /// the dial left the screen), it ends on the whole answer, so the word is never left hidden
    /// beside a number. If one did, it leaves that reveal's dial alone, never writing an old score.
    nonisolated static func cancelled(_ face:Face,score:Int,generation:Int,mine:Int)->Face {
        generation==mine ? .answer(score) : face
    }
    private var face: Face {
        get { Face(arc:arc,shown:shown,settled:settled) }
        nonmutating set { arc=newValue.arc; shown=newValue.shown; settled=newValue.settled }
    }
    private func reveal() async {
        generation+=1
        let mine=generation, key=revealKey
        let plan=Self.plan(seen:key.map { ScoreReveals.seen.contains($0) } ?? false,held:held,reduceMotion:reduceMotion,export:export,
                           alreadyRevealed:Self.alreadyRevealed(revealedOnce:revealedOnce,countedScore:countedScore,score:score))
        let end=Self.face(after:plan,score:score)
        switch plan {
        case .instant:
            face=end; waiting=false; rangeShown=true
            onSettled?(key)
        case .hold:
            face=end; waiting=true; rangeShown=false; countedScore=nil
        case .sweep:
            let landing = !revealedOnce
            withAnimation(NyxMotion.spring) {
                face=end; waiting=false
                if landing { landed+=1 }
            }
            revealedOnce=true
            ScoreReveals.note(key,plan:.sweep,landed:true)
            onSettled?(key); showRange()
        case .settle:
            withAnimation(.spring(duration:Self.settleDuration)) { face=end; waiting=false; landed+=1 }
            revealedOnce=true
            onSettled?(key); showRange()
        case .odometer:
            await count(key:key,generation:mine)
        }
    }
    private func count(key:String?,generation mine:Int) async {
        countedScore=score
        face=Self.face(after:.odometer,score:score); waiting=false; rangeShown=false
        let interval=LaunchSignposts.begin("Score reveal"), began=Date.now
        var finished=false
        defer {
            if !finished {
                LaunchSignposts.end(interval)
                ScoreReveals.note(key,plan:.odometer,landed:false)
                // Cut short: the whole answer if nothing followed, otherwise the next reveal's dial.
                face=Self.cancelled(face,score:score,generation:generation,mine:mine)
            }
        }
        let clock=ContinuousClock(), start=clock.now, total=Self.duration(score:score)
        while !Task.isCancelled {
            let elapsed=start.duration(to:clock.now)
            let t=Double(elapsed.components.seconds)+Double(elapsed.components.attoseconds)/1e18
            let value=Self.countValue(score:score,at:t)
            if let crossed=Self.milestones(from:shown,to:value).last { milestone=crossed }
            arc=Double(score)*Self.progress(t)
            shown=value
            if t>=total || value>=score { break }
            try? await Task.sleep(for:.milliseconds(8))
        }
        guard !Task.isCancelled else { return }
        finished=true
        LaunchSignposts.end(interval); LaunchSignposts.firstLanding(countStarted:began)
        // The final digit, the word and the light tick in one transaction.
        withAnimation(NyxMotion.spring) { face = .answer(score); landed+=1 }
        revealedOnce=true
        ScoreReveals.note(key,plan:.odometer,landed:true)
        onSettled?(key); showRange()
    }
    /// Uncertainty comes last: the model range fades in a beat after the word.
    private func showRange() {
        withAnimation(NyxMotion.spring.delay(0.3)) { rangeShown=true }
    }
    /// The forecast models' range to draw around a score (`NightOutlook.scoreRange`, which already
    /// holds the score): only on a night whose clouds are a full forecast, only when the models do
    /// not agree (where the time river and the Clouds tile say "Forecast models agree", the dial
    /// never shows a spread), and only when it spans more than 4 points, below which a band would
    /// read as noise around the tip.
    nonisolated static func modelRange(_ outlook:NightOutlook?,basis:CloudBasis)->ClosedRange<Int>? {
        guard basis == .forecast, let outlook, let agreement=outlook.agreement, agreement.band != .agree,
              let models=outlook.scoreRange, models.upperBound-models.lowerBound>4 else { return nil }
        return models
    }
    // MARK: Parts

    private func numeral(size:CGFloat)->some View {
        Text(reduceMotion || export ? score : shown,format:.number)
            .font(.system(size:max(24,size),weight:.light,design:.serif)).tracking(-size*0.046)
            .foregroundStyle(palette.accent).contentTransition(.numericText(value:Double(shown)))
            .lineLimit(1).fixedSize()
            .opacity(numeralVisible ? 1 : 0)
    }
    /// At accessibility sizes the numeral is at least 2.2 times the band label's size (and never
    /// under the standard 108 pt), the dial drawn around it, never wider than the column.
    nonisolated static func accessibleNumeral(band:Double,side:Double)->Double { min(max(108,band*2.2),side*0.42) }
    nonisolated static func accessibleSide(band:Double,width:Double)->Double {
        let wanted=max(108,band*2.2)/0.36
        return max(160,min(width>0 ? width : 300,wanted))
    }
    /// Always laid out, so its slot is reserved and nothing moves when it arrives (at accessibility
    /// sizes too). It shows only once the score has settled, and a new night's word cross-fades;
    /// it never steps through the bands the count passes.
    private var band:some View {
        Text(ScoreBand.band(score).label).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
            .contentTransition(.opacity)
            .opacity(bandVisible ? 1 : 0).blur(radius:bandVisible ? 0 : 6)
    }
    private var units:some View { Text("Darkness / 100").textCase(.uppercase).font(.caption2).tracking(typeSize.isAccessibilitySize ? 0 : 2.5*min(1,max(0.4,(side-200)/100))).foregroundStyle(palette.muted).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true) }
    /// The instrument's body: a ring of Liquid Glass the arc runs along, so the dial reads as an
    /// object, not a chart. Solid and dark under Reduce Transparency and in night vision, where
    /// glass would flatten toward the text colour.
    @ViewBuilder private var bezel:some View {
        if reduceTransparency || palette.nightVision || palette.highContrast {
            DialRing().fill(palette.panel.opacity(0.9)).overlay(DialRing().stroke(palette.line,lineWidth:0.5))
        } else {
            Color.clear.glassEffect(.clear,in:DialRing())
        }
    }
    private var drawing:some View {
        let displayed=reduceMotion || export ? Double(score) : arc
        return ZStack {
            // The models' range sits under the arc; a hairline outside it where glows are dimmed or red.
            if let range {
                ModelRangeBand(range:range,palette:palette,glow:access.glow,hairline:palette.highContrast || palette.nightVision || access.reduceHighlighting)
                    .opacity(rangeVisible ? 1 : 0)
            }
            DialFace(value:displayed,hasForecast:hasForecast,palette:palette,glow:access.glow)
            ambient(displayed)
        }.accessibilityHidden(true)
    }
    /// The glint, the leading star's pulse and the orbiting stars: decoration, at 30 Hz at most,
    /// still under Reduce Motion, reduced resources, Low Power Mode and in exported images, and
    /// resting while the dial is scrolled out of view.
    private func ambient(_ displayed:Double)->some View {
        let still=reduceMotion || export || access.reducedResources || PowerState.shared.lowPower
        return TimelineView(.animation(minimumInterval:1/30,paused:still || !onScreen)) { timeline in
            Canvas { context,size in
                let dial=min(size.width,size.height), k=DialMetrics.scale(side:dial)
                let center=CGPoint(x:size.width/2,y:size.height/2), radius=dial/2-DialMetrics.inset(side:dial)
                let t=still ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let tip=Angle.degrees(140+260*displayed/100)
                // Specular glint on the glass rim. It slides with the phone's tilt, as light on a real dial would.
                if !reduceMotion && !export && !palette.nightVision && !access.reduceHighlighting && !access.reducedResources {
                    let tilt=MotionTilt.shared
                    let mid=pointer.map { atan2($0.y-center.y,$0.x-center.x) } ?? (-90+tilt.x*55-tilt.y*12)*Double.pi/180, half=22*Double.pi/180
                    var glint=Path(); glint.addArc(center:center,radius:radius+11*k,startAngle:.radians(mid-half),endAngle:.radians(mid+half),clockwise:false)
                    let from=CGPoint(x:center.x+cos(mid-half)*radius,y:center.y+sin(mid-half)*radius), to=CGPoint(x:center.x+cos(mid+half)*radius,y:center.y+sin(mid+half)*radius)
                    context.stroke(glint,with:.linearGradient(Gradient(colors:[.white.opacity(0),.white.opacity(0.35),.white.opacity(0)]),startPoint:from,endPoint:to),style:StrokeStyle(lineWidth:2.5,lineCap:.round))
                }
                // The leading star: where tonight's score has reached.
                if displayed>0.5 {
                    let point=CGPoint(x:center.x+cos(tip.radians)*radius,y:center.y+sin(tip.radians)*radius)
                    let pulse=still ? 1 : 0.85+0.15*sin(t*2.4)
                    context.fill(Path(ellipseIn:CGRect(x:point.x-10,y:point.y-10,width:20,height:20)),with:.radialGradient(Gradient(colors:[palette.accent.opacity(0.6*pulse*access.glow),palette.accent.opacity(0)]),center:point,startRadius:0,endRadius:10))
                    context.fill(Path(ellipseIn:CGRect(x:point.x-3.2,y:point.y-3.2,width:6.4,height:6.4)),with:.color(palette.ink))
                }
                // Orbiting stars: a loose ring that swirls faster and twinkles harder as the score rises.
                let energy=pow(Double(score)/100,3)
                for i in 0..<28 {
                    let seed=Double(i)*12.9898
                    let jitter=sin(seed)*43758.5453; let unit=jitter-floor(jitter)
                    let speed=(0.02+0.22*energy)*(i%2==0 ? 1 : 0.72)
                    let a=Double(i)*2*Double.pi/28+unit*0.4+t*speed
                    let orbit=radius+(9+unit*9)*k
                    let twinkle=still ? 0.8 : 0.55+0.45*sin(t*(1.2+2.6*energy)+seed)
                    let big=i%4==0
                    let d=big ? 2.6 : 1.4+unit
                    context.fill(Path(ellipseIn:CGRect(x:center.x+cos(a)*orbit-d/2,y:center.y+sin(a)*orbit-d/2,width:d,height:d)),with:.color(palette.ink.opacity((big ? 0.75 : 0.4)*twinkle)))
                }
            }
        }
    }
}
/// The dial's well, track, glow, arc and ticks for a value 0…100. Animatable, so a new night's
/// score sweeps the arc on the shared spring instead of jumping.
private struct DialFace: View, Animatable {
    var value: Double
    let hasForecast: Bool
    let palette: NyxPalette
    let glow: Double
    var animatableData: Double { get { value } set { value=newValue } }
    var body: some View {
        Canvas { context,size in
            let dial=min(size.width,size.height), k=DialMetrics.scale(side:dial)
            let center=CGPoint(x:size.width/2,y:size.height/2), radius=dial/2-DialMetrics.inset(side:dial)
            // A soft inner shadow: the numeral sits inside the instrument, not on top of the sky.
            let well=radius-14*k
            context.fill(Path(ellipseIn:CGRect(x:center.x-well,y:center.y-well,width:2*well,height:2*well)),with:.radialGradient(Gradient(stops:[.init(color:.black.opacity(0.55),location:0),.init(color:.black.opacity(0.35),location:0.8),.init(color:.black.opacity(0.6),location:1)]),center:center,startRadius:0,endRadius:well))
            let start=Angle.degrees(140), end=Angle.degrees(400)
            var track=Path(); track.addArc(center:center,radius:radius,startAngle:start,endAngle:end,clockwise:false)
            context.stroke(track,with:.color(palette.line),style:StrokeStyle(lineWidth:1.2,lineCap:.round))
            let displayed=min(100,max(0,value))
            let tip=Angle.degrees(140+260*displayed/100)
            var arc=Path(); arc.addArc(center:center,radius:radius,startAngle:start,endAngle:tip,clockwise:false)
            let dash:[CGFloat]=hasForecast ? [] : [3,5]
            if displayed>0.5 {
                // A soft amber glow under the arc, stronger as the score rises.
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius:7))
                    layer.stroke(arc,with:.color(palette.accent.opacity((0.18+0.3*displayed/100)*glow)),style:StrokeStyle(lineWidth:6,lineCap:.round,dash:dash))
                }
                context.stroke(arc,with:.color(palette.accent),style:StrokeStyle(lineWidth:2.3,lineCap:.round,dash:dash))
            }
            for tick in 0..<41 {
                let a=(140+Double(tick)*6.5)*Double.pi/180
                let lit=Double(tick)*2.5<=displayed
                let outer=radius-8*k, inner=radius-(tick%10==0 ? 17 : 12)*k
                let aPoint=CGPoint(x:center.x+cos(a)*outer,y:center.y+sin(a)*outer)
                let bPoint=CGPoint(x:center.x+cos(a)*inner,y:center.y+sin(a)*inner)
                var line=Path(); line.move(to:aPoint); line.addLine(to:bPoint)
                context.stroke(line,with:.color(lit ? palette.accent.opacity(tick%10==0 ? 0.75 : 0.45) : palette.line),lineWidth:tick%10==0 ? 0.9 : 0.6)
            }
        }
    }
}
/// The forecast models' range along the track, from the score the cloudiest model would give to
/// the clearest's: a soft amber glow riding the rim beside the arc, in the language of the time
/// river's model glow. Under Increase Contrast, night vision and Reduce Highlighting it is a 1.5 pt hairline
/// just outside the track with a small tick at each end, so it never reads as more arc. No
/// dashes: on this dial dashes mean "no full forecast".
private struct ModelRangeBand: View {
    let range: ClosedRange<Int>
    let palette: NyxPalette
    let glow: Double
    let hairline: Bool
    var body: some View {
        Canvas { context,size in
            let dial=min(size.width,size.height), k=DialMetrics.scale(side:dial)
            let center=CGPoint(x:size.width/2,y:size.height/2), radius=dial/2-DialMetrics.inset(side:dial)
            let from=Angle.degrees(140+260*Double(range.lowerBound)/100), to=Angle.degrees(140+260*Double(range.upperBound)/100)
            if hairline {
                let r=radius+7*k
                var path=Path(); path.addArc(center:center,radius:r,startAngle:from,endAngle:to,clockwise:false)
                for end in [from,to] {
                    path.move(to:CGPoint(x:center.x+cos(end.radians)*(r-3.5),y:center.y+sin(end.radians)*(r-3.5)))
                    path.addLine(to:CGPoint(x:center.x+cos(end.radians)*(r+3.5),y:center.y+sin(end.radians)*(r+3.5)))
                }
                context.stroke(path,with:.color(palette.accent),style:StrokeStyle(lineWidth:1.5,lineCap:.butt))
            } else {
                // Riding the rim just outside the track, so the part below the score shows beside the lit arc.
                var path=Path(); path.addArc(center:center,radius:radius+6*k,startAngle:from,endAngle:to,clockwise:false)
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius:3+2*k))
                    layer.stroke(path,with:.color(palette.accent.opacity(0.6*glow)),style:StrokeStyle(lineWidth:max(6,9*k),lineCap:.round))
                }
                context.stroke(path,with:.color(palette.accent.opacity(0.35*glow)),style:StrokeStyle(lineWidth:2,lineCap:.round))
                // A short tick at each end, so the band reads as a measured span (where the cloudiest
                // and clearest models would put the score), not as more glow, even beside a high score.
                let r=radius+6*k, half=max(3,5*k)
                var ends=Path()
                for end in [from,to] {
                    ends.move(to:CGPoint(x:center.x+cos(end.radians)*(r-half),y:center.y+sin(end.radians)*(r-half)))
                    ends.addLine(to:CGPoint(x:center.x+cos(end.radians)*(r+half),y:center.y+sin(end.radians)*(r+half)))
                }
                context.stroke(ends,with:.color(palette.accent.opacity(0.4+0.4*glow)),style:StrokeStyle(lineWidth:1.2,lineCap:.round))
            }
        }
        .allowsHitTesting(false)
    }
}
/// How the dial's drawing scales with its side: everything keeps its proportions below the
/// standard 300 pt dial, and the glass rim thins with it (never under 16 pt), so a small dial
/// (onboarding, 176 pt) is an instrument, not a thick ring crowding the numeral.
nonisolated enum DialMetrics {
    static let standard: CGFloat=300
    static func scale(side:CGFloat)->CGFloat { min(1,max(0,side)/standard) }
    /// The rim's width.
    static func ringWidth(side:CGFloat)->CGFloat { max(16,26*scale(side:side)) }
    /// From the frame's edge to the arc's radius.
    static func inset(side:CGFloat)->CGFloat { 18*scale(side:side) }
}
/// The glass rim the arc runs along: a band centred on the arc's radius (26 pt on the standard
/// dial, `DialMetrics`), open at the bottom like the dial itself, so the labels inside never sit on glass.
nonisolated struct DialRing:Shape {
    func path(in rect:CGRect)->Path {
        let side=min(rect.width,rect.height)
        let center=CGPoint(x:rect.midX,y:rect.midY), radius=side/2-DialMetrics.inset(side:side)
        var arc=Path()
        arc.addArc(center:center,radius:radius,startAngle:.degrees(136),endAngle:.degrees(404),clockwise:false)
        return arc.strokedPath(StrokeStyle(lineWidth:DialMetrics.ringWidth(side:side),lineCap:.round))
    }
}
/// The score reveals seen this session, by `key`: in memory only, empty at every launch. A key is
/// added only when a count-up lands in front of the person, never when it is held or cut short.
@MainActor enum ScoreReveals {
    static var seen: Set<String>=[]
    /// "park|night|score": a new score for the same night (a forecast arriving) is a new answer.
    nonisolated static func key(parkID:String,night:String,score:Int)->String { "\(parkID)|\(night)|\(score)" }
    /// Every reveal reports how it ended here; only a count-up that landed marks its key.
    static func note(_ key:String?,plan:CelestialGauge.RevealPlan,landed:Bool) {
        guard let key, plan == .odometer, landed else { return }
        seen.insert(key)
    }
}
/// VoiceOver's sentence for the dial, kept until its inputs change. A plain reference held in
/// `@State`, so remembering it never invalidates the view.
@MainActor private final class SpokenLabel {
    struct Inputs: Equatable { let score: Int; let hasForecast: Bool; let basis: String?; let range: ClosedRange<Int>? }
    private var inputs: Inputs?
    private var cached=""
    func text(for new:Inputs,_ build:(Inputs)->String)->String {
        if new != inputs { inputs=new; cached=build(new) }
        return cached
    }
}
/// What restarts a reveal: a new score, or the hold lifting or falling.
nonisolated struct RevealTrigger: Equatable, Sendable { let score: Int; let held: Bool }
private struct RevealHeldKey: EnvironmentKey { static let defaultValue=false }
extension EnvironmentValues {
    /// Set over the tabs while onboarding or first light covers them: Tonight's unseen reveal waits
    /// for the person instead of playing behind a sheet.
    var nyxRevealHeld: Bool { get { self[RevealHeldKey.self] } set { self[RevealHeldKey.self]=newValue } }
}
#Preview("Pristine") { CelestialGauge(score:94).background(.black) }
#Preview("No forecast • still • AX5") { CelestialGauge(score:82,hasForecast:false).environment(\.nyxReduceMotion,true).dynamicTypeSize(.accessibility5).background(.black) }
#Preview("Poor") { CelestialGauge(score:23).background(.black) }
#Preview("Good • Fair") { HStack { CelestialGauge(score:65);CelestialGauge(score:45,hasForecast:false) }.environment(\.nyxReduceMotion,true).background(.black) }
#Preview("Small dial • labels below") { CelestialGauge(score:88).frame(width:188).environment(\.nyxReduceMotion,true).background(.black) }
#Preview("Model range") { CelestialGauge(score:84,range:76...92).background(.black) }
#Preview("Model range • still") { CelestialGauge(score:84,range:76...92).environment(\.nyxReduceMotion,true).background(.black) }
#Preview("Model range • contrast hairline") { CelestialGauge(score:84,range:76...92).environment(\.nyx,NyxPalette(nightVision:false,highContrast:true)).environment(\.nyxReduceMotion,true).background(.black) }
#Preview("Held • waiting") { CelestialGauge(score:94,revealKey:"preview|2026-10-08|94").environment(\.nyxRevealHeld,true).background(.black) }
#Preview("Silent example • 176 pt") { CelestialGauge(score:94,haptics:false).frame(height:176).background(.black) }
#Preview("Night vision") { CelestialGauge(score:91).environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).background(.black) }
