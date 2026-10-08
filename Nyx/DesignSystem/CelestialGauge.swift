import SwiftUI

/// The Darkness Score as an instrument. On first appearance the score counts up like an odometer:
/// a decaying spring, fast at first and settling slowly over the last few points, with the arc
/// leading the numeral by about 80 ms, a medium tick at 70 and 90 and a light one where it lands.
/// The count-up runs at the display's rate and then stops; the ambient stars and the glint redraw
/// at 30 Hz at most. Later changes (scrubbing nights) sweep on the shared spring.
///
/// Only the drawing scales with the dial. The numeral is part of the drawing; the band and
/// "DARKNESS / 100" keep their own text styles and move below the dial when it is too small to
/// hold them (onboarding, a small hero) or the text is at an accessibility size, where the
/// numeral stays more than twice the band's size, capped by the width.
struct CelestialGauge: View {
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.nyxAccess) private var access
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
    /// Where the arc has reached, 0…100.
    @State private var arc=0.0
    /// The numeral shown.
    @State private var shown=0
    @State private var milestone=0
    @State private var landed=0
    @State private var revealed=false
    /// Where an iPad's pointer rests over the dial: the glint on the glass follows it, like light on a real instrument.
    @State private var pointer: CGPoint?
    /// Whether any of the dial shows in its scroll view; the ambient stars rest while it is scrolled away.
    @State private var onScreen=true
    /// The dial's side, measured.
    @State private var side: CGFloat=300
    /// The width offered at accessibility sizes, where the dial grows with the text up to it.
    @State private var available: CGFloat=0
    /// Band and units fit inside a dial this size at standard text sizes.
    static let labelsInsideFrom: CGFloat=236
    private var labelsInside: Bool { !typeSize.isAccessibilitySize && side>=Self.labelsInsideFrom }
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
        .accessibilityLabel("Darkness score \(score) out of 100. \(ScoreBand.band(score).label). \(spokenBasis ?? (hasForecast ? String(localized:"Includes cloud forecast.") : String(localized:"No full cloud forecast; usual clouds count.")))")
        .accessibilityInputLabels([Text("Score"),Text("Darkness score")])
        .task(id:score) { await reveal() }
        .sensoryFeedback(.impact(weight:.medium),trigger:milestone)
        .sensoryFeedback(.impact(weight:.light),trigger:landed)
        .onScrollVisibilityChange(threshold:0.02) { onScreen=$0 }
        // Tilt only while the glint can be drawn and the dial is in view.
        .motionTilt(onScreen && !export && !reduceMotion && !palette.nightVision && !access.reduceHighlighting && !access.reducedResources)
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
    private func reveal() async {
        if reduceMotion || export { arc=Double(score); shown=score; revealed=true; return }
        if revealed { withAnimation(NyxMotion.spring) { arc=Double(score); shown=score }; return }
        revealed=true
        arc=0; shown=0
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
        arc=Double(score); shown=score
        landed+=1
    }
    // MARK: Parts

    private func numeral(size:CGFloat)->some View {
        Text(reduceMotion || export ? score : shown,format:.number)
            .font(.system(size:max(24,size),weight:.light,design:.serif)).tracking(-size*0.046)
            .foregroundStyle(palette.accent).contentTransition(.numericText(value:Double(shown)))
            .lineLimit(1).fixedSize()
    }
    /// At accessibility sizes the numeral is at least 2.2 times the band label's size (and never
    /// under the standard 108 pt), the dial drawn around it, never wider than the column.
    nonisolated static func accessibleNumeral(band:Double,side:Double)->Double { min(max(108,band*2.2),side*0.42) }
    nonisolated static func accessibleSide(band:Double,width:Double)->Double {
        let wanted=max(108,band*2.2)/0.36
        return max(160,min(width>0 ? width : 300,wanted))
    }
    private var band:some View { Text(ScoreBand.band(score).label).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true) }
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
                let center=CGPoint(x:size.width/2,y:size.height/2), radius=min(size.width,size.height)/2-18
                let t=still ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let tip=Angle.degrees(140+260*displayed/100)
                // Specular glint on the glass rim. It slides with the phone's tilt, as light on a real dial would.
                if !reduceMotion && !export && !palette.nightVision && !access.reduceHighlighting && !access.reducedResources {
                    let tilt=MotionTilt.shared
                    let mid=pointer.map { atan2($0.y-center.y,$0.x-center.x) } ?? (-90+tilt.x*55-tilt.y*12)*Double.pi/180, half=22*Double.pi/180
                    var glint=Path(); glint.addArc(center:center,radius:radius+11,startAngle:.radians(mid-half),endAngle:.radians(mid+half),clockwise:false)
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
                    let orbit=radius+9+unit*9
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
            let center=CGPoint(x:size.width/2,y:size.height/2), radius=min(size.width,size.height)/2-18
            // A soft inner shadow: the numeral sits inside the instrument, not on top of the sky.
            let well=radius-14
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
                let aPoint=CGPoint(x:center.x+cos(a)*(radius-8),y:center.y+sin(a)*(radius-8))
                let bPoint=CGPoint(x:center.x+cos(a)*(radius-(tick%10==0 ? 17 : 12)),y:center.y+sin(a)*(radius-(tick%10==0 ? 17 : 12)))
                var line=Path(); line.move(to:aPoint); line.addLine(to:bPoint)
                context.stroke(line,with:.color(lit ? palette.accent.opacity(tick%10==0 ? 0.75 : 0.45) : palette.line),lineWidth:tick%10==0 ? 0.9 : 0.6)
            }
        }
    }
}
/// The glass rim the arc runs along: a band 26 pt wide centred on the arc's radius, open at the
/// bottom like the dial itself, so the labels inside never sit on glass.
nonisolated struct DialRing:Shape {
    func path(in rect:CGRect)->Path {
        let center=CGPoint(x:rect.midX,y:rect.midY), radius=min(rect.width,rect.height)/2-18
        var arc=Path()
        arc.addArc(center:center,radius:radius,startAngle:.degrees(136),endAngle:.degrees(404),clockwise:false)
        return arc.strokedPath(StrokeStyle(lineWidth:26,lineCap:.round))
    }
}
#Preview("Pristine") { CelestialGauge(score:94).background(.black) }
#Preview("No forecast • still • AX5") { CelestialGauge(score:82,hasForecast:false).environment(\.nyxReduceMotion,true).dynamicTypeSize(.accessibility5).background(.black) }
#Preview("Poor") { CelestialGauge(score:23).background(.black) }
#Preview("Good • Fair") { HStack { CelestialGauge(score:65);CelestialGauge(score:45,hasForecast:false) }.environment(\.nyxReduceMotion,true).background(.black) }
#Preview("Small dial • labels below") { CelestialGauge(score:88).frame(width:188).environment(\.nyxReduceMotion,true).background(.black) }
#Preview("Night vision") { CelestialGauge(score:91).environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).background(.black) }
