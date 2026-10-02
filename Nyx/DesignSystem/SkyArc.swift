import SwiftUI

struct SkyArc: View {
    @Environment(\.nyx) private var palette
    let night: Night
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Eyebrow(text:"The shape of the night")
            Canvas { context,size in
                let duration=night.sky.end.timeIntervalSince(night.sky.evening), horizon=size.height*0.42
                func x(_ date:Date)->Double { date.timeIntervalSince(night.sky.evening)/duration*size.width }
                let bands=[(night.sky.sunset,night.sky.civilDusk,0.12),(night.sky.civilDusk,night.sky.nauticalDusk,0.23),(night.sky.nauticalDusk,night.sky.darkStart,0.36),(night.sky.darkStart,night.sky.darkEnd,0.65)]
                for (a,b,opacity) in bands {
                    if let a,let b,b>a { context.fill(Path(CGRect(x:x(a),y:0,width:x(b)-x(a),height:size.height)),with:.color(palette.panel.opacity(opacity))) }
                }
                var line=Path(); line.move(to:CGPoint(x:0,y:horizon)); line.addLine(to:CGPoint(x:size.width,y:horizon))
                context.stroke(line,with:.color(palette.line),style:StrokeStyle(lineWidth:0.7,dash:[2,4]))
                let engine=AstronomyEngine()
                for moon in [false,true] {
                    var path=Path()
                    for step in 0...64 {
                        let date=night.sky.evening.addingTimeInterval(duration*Double(step)/64)
                        let altitude=moon ? engine.lunarAltitude(at:date,park:night.park) : engine.solarAltitude(at:date,park:night.park)
                        let point=CGPoint(x:Double(step)/64*size.width,y:horizon-altitude/90*size.height*0.52)
                        if step==0 { path.move(to:point) } else { path.addLine(to:point) }
                    }
                    context.stroke(path,with:.color(moon ? palette.ink : palette.accent),style:StrokeStyle(lineWidth:1.6,dash:moon ? [4,4] : []))
                }
                let now=Date.now
                if now>=night.sky.evening && now<=night.sky.end {
                    let px=x(now)
                    var marker=Path(); marker.move(to:CGPoint(x:px,y:0)); marker.addLine(to:CGPoint(x:px,y:size.height))
                    context.stroke(marker,with:.color(palette.ink.opacity(0.6)),lineWidth:0.5)
                    context.fill(Path(ellipseIn:CGRect(x:px-3,y:horizon-3,width:6,height:6)),with:.color(palette.ink))
                }
            }.frame(height:120).clipped().accessibilityHidden(true)
            ViewThatFits(in:.horizontal) {
                HStack { legend;Spacer() }
                VStack(alignment:.leading,spacing:8) { legend }
            }.font(.caption).foregroundStyle(palette.muted)
            if night.sky.darkHours==0 {
                Text("No true darkness tonight at this latitude.").font(.body).foregroundStyle(palette.ink)
            } else {
                ViewThatFits(in:.horizontal) {
                    HStack { timeLabel("True darkness",time:night.sky.darkStart); Spacer(); timeLabel("Dawn",time:night.sky.darkEnd) }
                    VStack(alignment:.leading,spacing:12) { timeLabel("True darkness",time:night.sky.darkStart); timeLabel("Dawn",time:night.sky.darkEnd) }
                }
            }
            Text("Times in \(night.park.timeZoneID)").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }.accessibilityElement(children:.ignore)
            .accessibilityLabel("Sun and Moon paths for \(night.park.dayLabel(night.id)). Sunset \(night.park.time(night.sky.sunset)). \(night.sky.darkHours==0 ? String(localized:"No true darkness tonight at this latitude.") : String(localized:"True darkness from \(night.park.time(night.sky.darkStart)) to \(night.park.time(night.sky.darkEnd)).")) Moonrise \(night.park.time(night.sky.moonrise)), moonset \(night.park.time(night.sky.moonset)). Times in \(night.park.timeZoneID).")
    }
    @ViewBuilder private var legend:some View { Label("Sun",systemImage:"sun.max").foregroundStyle(palette.accent);Label("Moon · dashed",systemImage:"moon") }
    private func timeLabel(_ title:LocalizedStringKey,time:Date?)->some View {
        VStack(alignment:.leading,spacing:4) { Text(title).font(.caption).foregroundStyle(palette.muted); Text(night.park.time(time)).font(.system(.title3,design:.serif)) }
    }
}
#Preview("Arc") { if let p=try? ParkData.load().first(where:{$0.id=="jotr"}) { let sky=AstronomyEngine().conditions(for:p,on:.now); SkyArc(night:Night(park:p,sky:sky,score:ScoreEngine().score(sky:sky,bortle:p.bortleEstimate,cloudCover:nil),cloudCover:nil,forecastUpdated:nil)).padding().background(.black) } }

#Preview("No astronomical darkness • AX5") { let m=PlanModel();if let p=m.park("dena") { SkyArc(night:m.night(p,on:Date(timeIntervalSince1970:1782086400))).padding().dynamicTypeSize(.accessibility5).background(.black) } }
