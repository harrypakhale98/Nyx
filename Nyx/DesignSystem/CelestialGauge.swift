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
            if reduceMotion { shown=score; return }
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
            TimelineView(.animation(minimumInterval:1/20,paused:reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled)) { timeline in
                Canvas { context,size in
                    let center=CGPoint(x:size.width/2,y:size.height/2), radius=min(size.width,size.height)/2-18
                    let t=reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    let displayed = reduceMotion ? score : shown
                    let start=Angle.degrees(140), end=Angle.degrees(400)
                    var track=Path(); track.addArc(center:center,radius:radius,startAngle:start,endAngle:end,clockwise:false)
                    context.stroke(track,with:.color(palette.line),style:StrokeStyle(lineWidth:1.2,lineCap:.round))
                    var arc=Path(); arc.addArc(center:center,radius:radius,startAngle:start,endAngle:.degrees(140+260*Double(displayed)/100),clockwise:false)
                    context.stroke(arc,with:.color(palette.accent),style:StrokeStyle(lineWidth:2.3,lineCap:.round,dash:hasForecast ? [] : [3,5]))
                    for tick in 0..<41 {
                        let a=(140+Double(tick)*6.5)*Double.pi/180
                        let aPoint=CGPoint(x:center.x+cos(a)*(radius-8),y:center.y+sin(a)*(radius-8))
                        let bPoint=CGPoint(x:center.x+cos(a)*(radius-(tick%10==0 ? 17 : 12)),y:center.y+sin(a)*(radius-(tick%10==0 ? 17 : 12)))
                        var line=Path(); line.move(to:aPoint); line.addLine(to:bPoint)
                        context.stroke(line,with:.color(palette.line),lineWidth:0.6)
                    }
                    for i in 0..<12 {
                        let a=Double(i)*2*Double.pi/12+t*(0.025+Double(score)/5000)
                        let orbit=radius+10+Double(i%3)*2
                        let point=CGRect(x:center.x+cos(a)*orbit-1,y:center.y+sin(a)*orbit-1,width:i%3==0 ? 3 : 1.5,height:i%3==0 ? 3 : 1.5)
                        context.fill(Path(ellipseIn:point),with:.color(palette.ink.opacity(i%3==0 ? 0.7 : 0.35)))
                    }
                }
            }.accessibilityHidden(true)
    }

}
#Preview("Pristine") { CelestialGauge(score:94).background(.black) }
#Preview("No forecast • still • AX5") { CelestialGauge(score:82,hasForecast:false).environment(\.nyxReduceMotion,true).dynamicTypeSize(.accessibility5).background(.black) }
#Preview("Poor") { CelestialGauge(score:23).background(.black) }

#Preview("Good • Fair") { HStack { CelestialGauge(score:65);CelestialGauge(score:45,hasForecast:false) }.environment(\.nyxReduceMotion,true).background(.black) }
