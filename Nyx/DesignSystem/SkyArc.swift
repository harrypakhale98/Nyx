import SwiftUI

/// The night as a picture: the sky deepens from dusk through each twilight to true darkness
/// and back, column by column from the Sun's real altitude. The Sun and Moon trace their
/// paths above a horizon line, moonlight washes over the dark hours it spoils, and a marker
/// shows where the night stands now. Times are park-local.
struct SkyArc: View {
    @Environment(\.nyx) private var palette
    let night: Night
    /// Sunset minus an hour to sunrise plus an hour; 18:00–06:00 local when the Sun never crosses.
    private var window:(start:Date,end:Date) {
        if let sunset=night.sky.sunset,let sunrise=night.sky.sunrise,sunrise>sunset {
            return (sunset.addingTimeInterval(-3600),sunrise.addingTimeInterval(3600))
        }
        return (night.sky.evening.addingTimeInterval(6*3600),night.sky.evening.addingTimeInterval(18*3600))
    }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Eyebrow(text:"The shape of the night")
            Canvas { context,size in draw(in:&context,size:size) } symbols: {
                MoonView(geometry:AstronomyEngine().moon(for:night).geometry)
                    .frame(width:20,height:20).tag("moon")
            }
            .frame(height:168)
            .clipShape(RoundedRectangle(cornerRadius:14))
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityHidden(true)
            ViewThatFits(in:.horizontal) {
                HStack(spacing:16) { legend;Spacer() }
                VStack(alignment:.leading,spacing:8) { legend }
            }.font(.caption).foregroundStyle(palette.muted)
            if night.sky.darkHours==0 {
                Text("No true darkness tonight at this latitude.").font(.body).foregroundStyle(palette.ink)
            } else {
                ViewThatFits(in:.horizontal) {
                    HStack { timeLabel("Darkness begins",time:night.sky.darkStart); Spacer(); timeLabel("Darkness ends",time:night.sky.darkEnd) }
                    VStack(alignment:.leading,spacing:12) { timeLabel("Darkness begins",time:night.sky.darkStart); timeLabel("Darkness ends",time:night.sky.darkEnd) }
                }
            }
            Text("Times in \(night.park.timeZoneName)").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }.accessibilityElement(children:.ignore)
            .accessibilityLabel("Sun and Moon paths for \(night.park.dayLabel(night.id)). Sunset \(night.park.time(night.sky.sunset)). \(night.sky.darkHours==0 ? String(localized:"No true darkness tonight at this latitude.") : String(localized:"True darkness from \(night.park.time(night.sky.darkStart)) to \(night.park.time(night.sky.darkEnd)).")) Moonrise \(night.park.time(night.sky.moonrise)), moonset \(night.park.time(night.sky.moonset)). Times in \(night.park.timeZoneName).")
    }

    /// Sky colour for a solar altitude: dusk blue, nebula violet at civil twilight,
    /// deep indigo at nautical, void black from astronomical twilight on.
    private func skyColor(_ altitude:Double)->Color {
        let stops:[(Double,(Double,Double,Double))]=palette.nightVision
            ? [(0,(0.30,0.04,0.03)),(-6,(0.20,0.02,0.015)),(-12,(0.09,0.008,0.005)),(-18,(0,0,0))]
            : [(0,(0.20,0.23,0.42)),(-6,(0.165,0.106,0.306)),(-12,(0.043,0.063,0.149)),(-18,(0,0,0))]
        if altitude>=stops[0].0 { return Color(red:stops[0].1.0,green:stops[0].1.1,blue:stops[0].1.2) }
        for i in 0..<(stops.count-1) where altitude<=stops[i].0 && altitude>stops[i+1].0 {
            let t=(stops[i].0-altitude)/(stops[i].0-stops[i+1].0)
            let a=stops[i].1, b=stops[i+1].1
            return Color(red:a.0+(b.0-a.0)*t,green:a.1+(b.1-a.1)*t,blue:a.2+(b.2-a.2)*t)
        }
        return .black
    }

    private func draw(in context:inout GraphicsContext,size:CGSize) {
        let engine=AstronomyEngine(), park=night.park
        let (start,end)=window
        let duration=end.timeIntervalSince(start)
        let labelBand=22.0, horizon=(size.height-labelBand)*0.74
        func x(_ date:Date)->Double { date.timeIntervalSince(start)/duration*size.width }
        func date(_ x:Double)->Date { start.addingTimeInterval(x/size.width*duration) }
        func y(_ altitude:Double)->Double { horizon-altitude/90*(horizon-10) }

        // The sky, one column at a time.
        let columns=96, column=size.width/Double(columns)
        for i in 0..<columns {
            let altitude=engine.solarAltitude(at:date((Double(i)+0.5)*column),park:park)
            context.fill(Path(CGRect(x:Double(i)*column,y:0,width:column+0.6,height:horizon)),with:.color(skyColor(altitude)))
        }
        // Moonlight washing over the dark hours: brighter for a fuller Moon.
        let samples=72
        let moonPoints=(0...samples).map { step -> (Date,Double) in
            let d=start.addingTimeInterval(duration*Double(step)/Double(samples))
            return (d,engine.lunarAltitude(at:d,park:park))
        }
        if let darkStart=night.sky.darkStart,let darkEnd=night.sky.darkEnd,night.sky.moon.illumination>0.02 {
            // Merge moon-up dark samples into continuous spans, so the wash has no seams.
            var spans:[(Double,Double)]=[]
            for step in 0..<samples where moonPoints[step].1>0 && moonPoints[step].0>=darkStart && moonPoints[step].0<darkEnd {
                let a=x(max(moonPoints[step].0,darkStart)), b=x(min(moonPoints[step+1].0,darkEnd))
                if let last=spans.last,abs(last.1-a)<0.5 { spans[spans.count-1].1=b } else { spans.append((a,b)) }
            }
            let wash=Gradient(colors:[palette.ink.opacity(0.03),palette.ink.opacity(0.05+0.13*night.sky.moon.illumination)])
            for (a,b) in spans {
                context.fill(Path(CGRect(x:a,y:0,width:b-a,height:horizon)),with:.linearGradient(wash,startPoint:CGPoint(x:0,y:0),endPoint:CGPoint(x:0,y:horizon)))
            }
        }
        // A few stars where the sky is truly dark.
        var generator=SeededGenerator(seed:park.id)
        for _ in 0..<26 {
            let sx=Double.random(in:0..<size.width,using:&generator), sy=Double.random(in:4..<(horizon-8),using:&generator)
            let altitude=engine.solarAltitude(at:date(sx),park:park)
            guard altitude < -12 else { continue }
            let fade=min(1,(-12-altitude)/6)
            let d=Double.random(in:0.8..<1.8,using:&generator)
            context.fill(Path(ellipseIn:CGRect(x:sx,y:sy,width:d,height:d)),with:.color(palette.ink.opacity(0.55*fade)))
        }
        // The ground: a low, generic ridge seeded by the park, so each place has its own skyline.
        // Illustrative only; it never claims to be the park's real horizon.
        var ridgeGenerator=SeededGenerator(seed:park.id+"-ridge")
        let peaks=(0...12).map { _ in Double.random(in:0...1,using:&ridgeGenerator) }
        var ridge=Path(); ridge.move(to:CGPoint(x:0,y:size.height))
        for i in 0...48 {
            let u=Double(i)/48, f=u*12, a=Int(f), b=min(12,a+1), w=f-Double(a)
            let blend=peaks[a]*(1-w)+peaks[b]*w
            ridge.addLine(to:CGPoint(x:u*size.width,y:horizon-2-7*blend))
        }
        ridge.addLine(to:CGPoint(x:size.width,y:size.height)); ridge.closeSubpath()
        context.fill(ridge,with:.linearGradient(Gradient(colors:[Color(white:0.06),.black]),startPoint:CGPoint(x:0,y:horizon-9),endPoint:CGPoint(x:0,y:horizon+30)))
        context.stroke(ridge,with:.color(palette.line.opacity(0.8)),lineWidth:0.6)

        // Paths: bright above the horizon, a faint trace below it.
        func trace(_ points:[(Date,Double)],color:Color,width:Double) {
            var path=Path()
            for (i,point) in points.enumerated() {
                let p=CGPoint(x:x(point.0),y:y(point.1))
                if i==0 { path.move(to:p) } else { path.addLine(to:p) }
            }
            var above=context; above.clip(to:Path(CGRect(x:0,y:0,width:size.width,height:horizon)))
            above.stroke(path,with:.color(color),style:StrokeStyle(lineWidth:width,lineCap:.round,lineJoin:.round))
            var below=context; below.clip(to:Path(CGRect(x:0,y:horizon,width:size.width,height:size.height-horizon-labelBand)))
            below.stroke(path,with:.color(color.opacity(0.28)),style:StrokeStyle(lineWidth:1,dash:[2,3]))
        }
        let sunPoints=(0...samples).map { step -> (Date,Double) in
            let d=start.addingTimeInterval(duration*Double(step)/Double(samples))
            return (d,engine.solarAltitude(at:d,park:park))
        }
        trace(sunPoints,color:palette.accent,width:1.8)
        trace(moonPoints,color:palette.ink,width:1.4)
        // The Moon itself, at its highest point in view.
        if let peak=moonPoints.max(by:{ $0.1<$1.1 }),peak.1>0,let symbol=context.resolveSymbol(id:"moon") {
            let px=min(max(x(peak.0),12),size.width-12), py=max(y(peak.1),12)
            context.draw(symbol,at:CGPoint(x:px,y:py))
        }

        // True darkness, bracketed on the ground in amber.
        if let darkStart=night.sky.darkStart,let darkEnd=night.sky.darkEnd,darkEnd>darkStart {
            let a=max(0,x(darkStart)), b=min(size.width,x(darkEnd)), barY=horizon+9
            var bar=Path(); bar.move(to:CGPoint(x:a,y:barY)); bar.addLine(to:CGPoint(x:b,y:barY))
            context.stroke(bar,with:.color(palette.accent.opacity(0.85)),style:StrokeStyle(lineWidth:2,lineCap:.round))
            if b-a>70 {
                let label=context.resolve(Text("True darkness").font(.caption2).foregroundStyle(palette.accent))
                context.draw(label,at:CGPoint(x:(a+b)/2,y:barY+11))
            }
        }

        // Hour labels, park-local, every two or three hours.
        var format=Date.FormatStyle.dateTime.hour(.defaultDigits(amPM:.abbreviated))
        format.timeZone=park.timeZone
        let step=duration>11*3600 ? 3 : 2
        var calendar=park.calendar; calendar.timeZone=park.timeZone
        if var tick=calendar.nextDate(after:start,matching:DateComponents(minute:0),matchingPolicy:.nextTime) {
            while tick<end {
                let hour=calendar.component(.hour,from:tick)
                if hour%step==0 {
                    let tx=x(tick)
                    if tx>18 && tx<size.width-18 {
                        var mark=Path(); mark.move(to:CGPoint(x:tx,y:size.height-labelBand)); mark.addLine(to:CGPoint(x:tx,y:size.height-labelBand+3))
                        context.stroke(mark,with:.color(palette.line),lineWidth:0.6)
                        context.draw(context.resolve(Text(tick.formatted(format)).font(.caption2).foregroundStyle(palette.muted)),at:CGPoint(x:tx,y:size.height-labelBand/2+2))
                    }
                }
                tick=tick.addingTimeInterval(3600)
            }
        }

        // Where the night stands now.
        let now=Date.now
        if now>start && now<end {
            let nx=x(now)
            var marker=Path(); marker.move(to:CGPoint(x:nx,y:14)); marker.addLine(to:CGPoint(x:nx,y:horizon))
            context.stroke(marker,with:.color(palette.ink.opacity(0.7)),style:StrokeStyle(lineWidth:0.8,dash:[2,2]))
            context.fill(Path(ellipseIn:CGRect(x:nx-3.5,y:horizon-3.5,width:7,height:7)),with:.color(palette.ink))
            let label=context.resolve(Text("Now").font(.caption2.weight(.semibold)).foregroundStyle(palette.ink))
            context.draw(label,at:CGPoint(x:min(max(nx,16),size.width-16),y:8))
        }
    }

    @ViewBuilder private var legend:some View {
        Label("Sun",systemImage:"sun.max").foregroundStyle(palette.accent)
        Label("Moon",systemImage:"moon")
        Label("Moonlit hours are lighter",systemImage:"sparkles").labelStyle(.titleOnly)
    }
    private func timeLabel(_ title:LocalizedStringKey,time:Date?)->some View {
        VStack(alignment:.leading,spacing:4) { Text(title).font(.caption).foregroundStyle(palette.muted); Text(night.park.time(time)).font(.system(.title3,design:.serif)) }
    }
}
#Preview("Arc") { if let p=try? ParkData.load().first(where:{$0.id=="jotr"}) { let sky=AstronomyEngine().conditions(for:p,on:.now); SkyArc(night:Night(park:p,sky:sky,score:ScoreEngine().score(sky:sky,bortle:p.bortleEstimate,cloudCover:nil),cloudCover:nil,forecastUpdated:nil)).padding().background(.black) } }

#Preview("No astronomical darkness • AX5") { let m=PlanModel();if let p=m.park("dena") { SkyArc(night:m.night(p,on:Date(timeIntervalSince1970:1782086400))).padding().dynamicTypeSize(.accessibility5).background(.black) } }
