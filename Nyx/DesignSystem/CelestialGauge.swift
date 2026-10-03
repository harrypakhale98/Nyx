import SwiftUI

struct CelestialGauge: View {
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    @Environment(\.dynamicTypeSize) private var typeSize
    let score: Int
    var hasForecast: Bool=true
    @State private var shown=0
    @State private var milestone=0
    @State private var revealed=false
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing:16) {
                    ZStack { orbit; numeral }.frame(width:220,height:220)
                    band
                    units
                }.frame(maxWidth:.infinity)
            } else {
                ZStack { orbit;VStack(spacing:5) { numeral;band;units.padding(.top,8) } }
                    .frame(maxWidth:300).aspectRatio(1,contentMode:.fit)
            }
        }
        .accessibilityElement(children:.ignore)
        .accessibilityLabel("Darkness score \(score) out of 100. \(ScoreBand.band(score).label). \(hasForecast ? String(localized:"Includes cloud forecast.") : String(localized:"Moon and darkness only. Cloud forecast unavailable."))")
        .task(id:score) {
            // Count up once per appearance; later changes (scrubbing nights) glide on the spring.
            if reduceMotion { shown=score; revealed=true; return }
            if revealed { withAnimation(NyxMotion.spring) { shown=score }; return }
            revealed=true
            shown=0
            for value in stride(from:0,through:score,by:2) {
                if Task.isCancelled { return }
                withAnimation(NyxMotion.spring) { shown=value }
                if value==70 || value==90 { milestone=value }
                try? await Task.sleep(for:.milliseconds(12))
            }
            withAnimation(NyxMotion.spring) { shown=score }
        }
        .sensoryFeedback(.impact(weight:.medium),trigger:milestone)
    }
    private var numeral:some View {
        Text(reduceMotion ? score : shown,format:.number)
            .font(.system(size:typeSize.isAccessibilitySize ? 82 : 108,weight:.light,design:.serif)).tracking(-5)
            .foregroundStyle(palette.accent).contentTransition(.numericText())
    }
    private var band:some View { Text(ScoreBand.band(score).label).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true) }
    private var units:some View { Text("DARKNESS / 100").font(.caption2).tracking(typeSize.isAccessibilitySize ? 0 : 2.5).foregroundStyle(palette.muted).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true) }
    private var orbit:some View {
            TimelineView(.animation(minimumInterval:nil,paused:reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled)) { timeline in
                Canvas { context,size in
                    let center=CGPoint(x:size.width/2,y:size.height/2), radius=min(size.width,size.height)/2-18
                    let t=reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    let displayed = reduceMotion ? score : shown
                    let start=Angle.degrees(140), end=Angle.degrees(400)
                    var track=Path(); track.addArc(center:center,radius:radius,startAngle:start,endAngle:end,clockwise:false)
                    context.stroke(track,with:.color(palette.line),style:StrokeStyle(lineWidth:1.2,lineCap:.round))
                    let tip=Angle.degrees(140+260*Double(displayed)/100)
                    var arc=Path(); arc.addArc(center:center,radius:radius,startAngle:start,endAngle:tip,clockwise:false)
                    let dash:[CGFloat]=hasForecast ? [] : [3,5]
                    // A soft amber glow under the arc, stronger as the score rises.
                    if displayed>0 {
                        context.drawLayer { glow in
                            glow.addFilter(.blur(radius:7))
                            glow.stroke(arc,with:.color(palette.accent.opacity(0.18+0.3*Double(displayed)/100)),style:StrokeStyle(lineWidth:6,lineCap:.round,dash:dash))
                        }
                    }
                    context.stroke(arc,with:.color(palette.accent),style:StrokeStyle(lineWidth:2.3,lineCap:.round,dash:dash))
                    for tick in 0..<41 {
                        let a=(140+Double(tick)*6.5)*Double.pi/180
                        let lit=Double(tick)*2.5<=Double(displayed)
                        let aPoint=CGPoint(x:center.x+cos(a)*(radius-8),y:center.y+sin(a)*(radius-8))
                        let bPoint=CGPoint(x:center.x+cos(a)*(radius-(tick%10==0 ? 17 : 12)),y:center.y+sin(a)*(radius-(tick%10==0 ? 17 : 12)))
                        var line=Path(); line.move(to:aPoint); line.addLine(to:bPoint)
                        context.stroke(line,with:.color(lit ? palette.accent.opacity(tick%10==0 ? 0.75 : 0.45) : palette.line),lineWidth:tick%10==0 ? 0.9 : 0.6)
                    }
                    // The leading star: where tonight's score has reached.
                    if displayed>0 {
                        let point=CGPoint(x:center.x+cos(tip.radians)*radius,y:center.y+sin(tip.radians)*radius)
                        let pulse=reduceMotion ? 1 : 0.85+0.15*sin(t*2.4)
                        context.drawLayer { glow in
                            glow.addFilter(.blur(radius:6))
                            glow.fill(Path(ellipseIn:CGRect(x:point.x-7,y:point.y-7,width:14,height:14)),with:.color(palette.accent.opacity(0.55*pulse)))
                        }
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
                        let twinkle=reduceMotion ? 0.8 : 0.55+0.45*sin(t*(1.2+2.6*energy)+seed)
                        let big=i%4==0
                        let d=big ? 2.6 : 1.4+unit
                        context.fill(Path(ellipseIn:CGRect(x:center.x+cos(a)*orbit-d/2,y:center.y+sin(a)*orbit-d/2,width:d,height:d)),with:.color(palette.ink.opacity((big ? 0.75 : 0.4)*twinkle)))
                    }
                }
            }.accessibilityHidden(true)
    }

}
#Preview("Pristine") { CelestialGauge(score:94).background(.black) }
#Preview("No forecast • still • AX5") { CelestialGauge(score:82,hasForecast:false).environment(\.nyxReduceMotion,true).dynamicTypeSize(.accessibility5).background(.black) }
#Preview("Poor") { CelestialGauge(score:23).background(.black) }

#Preview("Good • Fair") { HStack { CelestialGauge(score:65);CelestialGauge(score:45,hasForecast:false) }.environment(\.nyxReduceMotion,true).background(.black) }
