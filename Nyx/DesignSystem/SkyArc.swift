import SwiftUI

/// The night as a picture: the sky deepens from dusk through each twilight to true darkness
/// and back, continuously from the Sun's real altitude. The Sun and Moon trace their
/// paths above a horizon line, moonlight washes over the dark hours it spoils, and a marker
/// shows where the night stands now. Times are park-local.
struct SkyArc: View {
    @Environment(\.nyx) private var palette
    @Environment(\.nyxAccess) private var access
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var scenePhase
    let night: Night
    /// Whether this is tonight's night, for copy that names it.
    var isTonight=true
    /// The Milky Way core's line from What's up, so VoiceOver hears the same times the panel shows.
    var core:WhatsUp.Item?=nil
    /// The chart's width, so a wide column draws a taller night instead of a flatter one.
    @State private var chartWidth=0.0
    /// About 2.4:1 wherever the column allows (168 pt tall on iPhone, as before; up to 300 pt on a wide iPad).
    private var chartHeight:Double { SkyArc.height(width:chartWidth) }
    nonisolated static func height(width:Double)->Double { min(300,max(168,(width/2.4).rounded())) }
    /// The Moon grows with the chart: 20 pt at the phone's height.
    private var moonSize:Double { (20*chartHeight/168).rounded() }
    /// Sunset minus an hour to sunrise plus an hour; 18:00–06:00 local when the Sun never crosses.
    private var window:(start:Date,end:Date) { ArcTouch.window(night) }
    /// Feel the night under your finger: the arc's columns while a finger explores it, the column
    /// under the finger, and the pending resting announcement. With VoiceOver running, its double tap
    /// hands the whole element to the finger. Without it, a finger held 0.3 s on the picture reads the
    /// hour (`ArcHold`); one that moves first fails the hold, so a flick over the arc still scrolls the
    /// page. DEBUG `-nyx-arc-touch` takes the VoiceOver path without VoiceOver and rests a finger for
    /// captures; `restsFinger` rests one in previews.
    @State private var touchColumns:[ArcTouch.Column]=[]
    @State private var touchColumn:Int?
    @State private var restTask:Task<Void,Never>?
    /// Previews: a finger resting at 55% of the night, as `-nyx-arc-touch` draws it for captures.
    var restsFinger=false
    /// True while a finger is down. A gesture's state resets when it ends and when it is cancelled
    /// (a call, a banner, Control Center, the app leaving), which `onEnded` never hears; the hum,
    /// the hairline and the pending words end with it.
    @GestureState private var touching=false
    /// True while a sighted finger holds the picture. UIKit's recognizer reports its end, its
    /// cancellation and its failure alike, and each ends the touch.
    @State private var holding=false
    private var touchEnabled:Bool { voiceOver || DebugScenario.isEnabled("arc-touch") }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            // The heading stays its own element, so the heading rotor still finds this section.
            Eyebrow(text:"The shape of the night")
            chart
        }
    }
    private var chart: some View {
        VStack(alignment:.leading,spacing:14) {
            Canvas { context,size in draw(in:&context,size:size) } symbols: {
                // Added as light, so an unlit Moon near new vanishes into a bright twilight as it does
                // in the sky, instead of punching a black disc in it; opaque under Increase Contrast.
                MoonView(geometry:AstronomyEngine().moon(for:night).geometry).blendMode(palette.highContrast ? .normal : .plusLighter)
                    .frame(width:moonSize,height:moonSize).tag("moon")
            }
            .frame(height:chartHeight)
            .onGeometryChange(for:Double.self) { $0.size.width.rounded() } action:{ if abs($0-chartWidth)>=1 { chartWidth=$0 } }
            .task(id:chartWidth) { if DebugScenario.isEnabled("arc-touch") || restsFinger, !voiceOver, chartWidth>0 { touch(at:chartWidth*0.55,quiet:true) } }
            // Sighted touch reads the picture only, never the legend or the times below it, and steps
            // aside for the VoiceOver path's gesture over the whole element.
            .contentShape(Rectangle())
            .gesture(ArcHold(enabled:!touchEnabled) { x in
                if let x { holding=true; touch(at:x,held:true) } else if holding { holding=false }
            })
            .clipShape(RoundedRectangle(cornerRadius:14))
            // The Moon is drawn into the canvas, where MoonView's own exemption cannot reach.
            .accessibilityIgnoresInvertColors()
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            // Outside the drawing's text-size cap, so the finger's words grow for the readers who use it.
            .overlay(alignment:.topLeading) { finger }
            .accessibilityHidden(true)
            ViewThatFits(in:.horizontal) {
                HStack(spacing:16) { legend;Spacer() }
                VStack(alignment:.leading,spacing:8) { legend }
            }.font(.caption).foregroundStyle(palette.muted)
            // VoiceOver's hint already explains direct touch, where "touch and hold" would be wrong.
            Text(voiceOver ? (access.differentiate ? "Moonlit hours are lighter and hatched." : "Moonlit hours are lighter.")
                 : (access.differentiate ? "Moonlit hours are lighter and hatched. Touch and hold to read any hour." : "Moonlit hours are lighter. Touch and hold to read any hour.")).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            if night.sky.darkHours==0 {
                Text(SkyConditions.noDarknessMessage(tonight:isTonight)).font(.body).foregroundStyle(palette.ink)
            } else {
                ViewThatFits(in:.horizontal) {
                    HStack { timeLabel("Darkness begins",time:night.sky.darkStart); Spacer(); timeLabel("Darkness ends",time:night.sky.darkEnd) }
                    VStack(alignment:.leading,spacing:12) { timeLabel("Darkness begins",time:night.sky.darkStart); timeLabel("Darkness ends",time:night.sky.darkEnd) }
                }
            }
            Text("Times in \(night.park.timeZoneName)").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }
            // The whole element answers the finger, as VoiceOver hands the whole element to it: below
            // the picture, the finger still reads the hour above it (the chart spans the full width).
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0).updating($touching) { _,state,_ in state=true }.onChanged { touch(at:$0.location.x) },including:touchEnabled ? .all : .subviews)
            // A held finger holds the park page still, as the river's scrub does.
            .preference(key:RiverScrubbingKey.self,value:holding)
            .onChange(of:touching) { _,down in if !down { endTouch() } }
            .onChange(of:holding) { _,down in if !down { endTouch() } }
            .onChange(of:scenePhase) { _,phase in if phase != .active { endTouch() } }
            .onChange(of:voiceOver) { _,on in if !on { endTouch() } }
            .onDisappear { endTouch() }
            .accessibilityElement(children:.ignore)
            .accessibilityInputLabels([Text("Shape of the night"),Text("Sky arc")])
            .accessibilityHint(touchHint+" "+String(localized:"An audio graph of the Sun, Moon and Milky Way core is available."))
            // A double tap hands the arc to the finger; ordinary swipes and the audio graph are untouched.
            .accessibilityDirectTouch(true,options:[.silentOnTouch,.requiresActivation])
            .nightChart { [night=night,window=window,summary=spokenSummary] in NightChart.sky(night,window:window,summary:summary) }
            .accessibilityLabel("Sun and Moon paths for \(night.park.dayLabel(night.id)). Sunset \(night.park.time(night.sky.sunset)). \(night.sky.darkHours==0 ? SkyConditions.noDarknessMessage(tonight:isTonight) : String(localized:"True darkness from \(night.park.time(night.sky.darkStart)) to \(night.park.time(night.sky.darkEnd)).")) Moonrise \(night.park.time(night.sky.moonrise)), moonset \(night.park.time(night.sky.moonset)). \(core.map { $0.spoken+" " } ?? "")Times in \(night.park.timeZoneName).")
    }

    /// "Feel" only where there is something to feel: an iPad without a Taptic Engine, or the
    /// Moon-haptics switch off, explores the night by the resting words alone.
    private var touchHint:String {
        MoonHaptics.enabled ? String(localized:"Double-tap, then slide a finger to feel the night.") : String(localized:"Double-tap, then slide a finger to explore the night.")
    }
    private var spokenSummary:String {
        let darkness=night.sky.darkHours==0 ? SkyConditions.noDarknessMessage(tonight:isTonight) : String(localized:"True darkness from \(night.park.time(night.sky.darkStart)) to \(night.park.time(night.sky.darkEnd)).")
        return String(localized:"Sunset \(night.park.time(night.sky.sunset)).")+" "+darkness+" "+String(localized:"Moonrise \(night.park.time(night.sky.moonrise)), moonset \(night.park.time(night.sky.moonset)).")
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
        // Taller on a wide iPad: the Milky Way's band and the Moon grow with the chart (1 on iPhone).
        let grow=size.height/168
        func x(_ date:Date)->Double { date.timeIntervalSince(start)/duration*size.width }
        func date(_ x:Double)->Date { start.addingTimeInterval(x/size.width*duration) }
        func y(_ altitude:Double)->Double { horizon-altitude/90*(horizon-10) }

        // The sky: one continuous twilight from the Sun's altitude at 65 points across the night,
        // then one wash that deepens it toward the zenith, as a real sky darkens overhead.
        let sky=Gradient(stops:(0...64).map { i in
            let u=Double(i)/64
            return Gradient.Stop(color:skyColor(engine.solarAltitude(at:date(u*size.width),park:park)),location:u)
        })
        let skyRect=Path(CGRect(x:0,y:0,width:size.width,height:horizon))
        context.fill(skyRect,with:.linearGradient(sky,startPoint:.zero,endPoint:CGPoint(x:size.width,y:0)))
        context.fill(skyRect,with:.linearGradient(Gradient(stops:[.init(color:.black.opacity(0.3),location:0),.init(color:.clear,location:0.75)]),startPoint:.zero,endPoint:CGPoint(x:0,y:horizon)))
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
                // Without colour, moonlight is a light diagonal hatch as well as a wash.
                if access.differentiate {
                    var hatch=Path(), x0=a-horizon
                    while x0<b { hatch.move(to:CGPoint(x:x0,y:horizon)); hatch.addLine(to:CGPoint(x:x0+horizon,y:0)); x0+=9 }
                    var clipped=context; clipped.clip(to:Path(CGRect(x:a,y:0,width:b-a,height:horizon)))
                    clipped.stroke(hatch,with:.color(palette.ink.opacity(0.22)),lineWidth:0.6*palette.stroke)
                }
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
        context.stroke(ridge,with:.color(palette.line.opacity(0.8)),lineWidth:0.6*palette.stroke)

        // Paths: bright above the horizon, a faint trace below it.
        // `gap` keeps the path out from under a disc drawn on it (the Moon, which is added as light
        // and would otherwise show its own track running through it).
        func trace(_ points:[(Date,Double)],color:Color,width:Double,gap:Path?=nil) {
            var path=Path()
            for (i,point) in points.enumerated() {
                let p=CGPoint(x:x(point.0),y:y(point.1))
                if i==0 { path.move(to:p) } else { path.addLine(to:p) }
            }
            var above=context; above.clip(to:Path(CGRect(x:0,y:0,width:size.width,height:horizon)))
            if let gap { above.clip(to:gap,options:.inverse) }
            above.stroke(path,with:.color(color),style:StrokeStyle(lineWidth:width*palette.stroke,lineCap:.round,lineJoin:.round))
            var below=context; below.clip(to:Path(CGRect(x:0,y:horizon,width:size.width,height:size.height-horizon-labelBand)))
            below.stroke(path,with:.color(color.opacity(0.28)),style:StrokeStyle(lineWidth:palette.stroke,dash:[2,3]))
        }
        let sunPoints=(0...samples).map { step -> (Date,Double) in
            let d=start.addingTimeInterval(duration*Double(step)/Double(samples))
            return (d,engine.solarAltitude(at:d,park:park))
        }
        // The Milky Way's bright center: a soft band with a dotted spine, only between sunset and
        // sunrise, beneath the Sun and Moon so it reads as the faintest of the three.
        var coreSegments:[[CGPoint]]=[], segment:[CGPoint]=[]
        var corePeak:(point:CGPoint,altitude:Double)?
        for (d,sun) in sunPoints {
            let altitude=engine.horizontal(date:d,park:park,ra:SkyAlmanac.coreRA,dec:SkyAlmanac.coreDec).altitude
            if sun < -0.833 && altitude>0 {
                let point=CGPoint(x:x(d),y:y(altitude))
                segment.append(point)
                if altitude>(corePeak?.altitude ?? 0) { corePeak=(point,altitude) }
            } else if !segment.isEmpty { coreSegments.append(segment); segment=[] }
        }
        if !segment.isEmpty { coreSegments.append(segment) }
        let corePaths=coreSegments.filter { $0.count>1 }.map { points in
            var path=Path(); path.move(to:points[0]); for point in points.dropFirst() { path.addLine(to:point) }; return path
        }
        if !corePaths.isEmpty {
            context.drawLayer { band in
                band.addFilter(.blur(radius:4))
                for path in corePaths { band.stroke(path,with:.color(palette.ink.opacity(0.16*access.glow)),style:StrokeStyle(lineWidth:10*grow,lineCap:.round,lineJoin:.round)) }
            }
            for path in corePaths { context.stroke(path,with:.color(palette.ink.opacity(0.7)),style:StrokeStyle(lineWidth:1.3*palette.stroke,lineCap:.round,dash:[0.1,3.6])) }
            if let peak=corePeak, peak.altitude>=8 {
                let label=context.resolve(Text("Core").font(.caption2).foregroundStyle(palette.muted))
                let measured=label.measure(in:CGSize(width:80,height:20))
                let lx=min(max(peak.point.x,measured.width/2+4),size.width-measured.width/2-4)
                context.draw(label,at:CGPoint(x:lx,y:max(measured.height/2+2,peak.point.y-measured.height/2-5)))
            }
        }
        trace(sunPoints,color:palette.accent,width:1.8)
        // The Moon itself sits at its highest point in view; its track stops at the disc's edge.
        let moonPeak:CGPoint?=moonPoints.max(by:{ $0.1<$1.1 }).flatMap { peak in
            guard peak.1>0 else { return nil }
            // Held a clear 6 pt inside the chart's rounded clip, so the disc never touches its edge at dusk or dawn.
            let edge=moonSize/2+6
            return CGPoint(x:min(max(x(peak.0),edge),size.width-edge),y:max(y(peak.1),edge))
        }
        let moonRadius=moonSize/2+0.5
        trace(moonPoints,color:palette.ink,width:1.4,gap:moonPeak.map { Path(ellipseIn:CGRect(x:$0.x-moonRadius,y:$0.y-moonRadius,width:moonRadius*2,height:moonRadius*2)) })
        // Without colour, the Sun's path is named where it last stands clear of the horizon.
        if access.differentiate, let last=sunPoints.last(where:{ $0.1>3 && x($0.0)>24 }) ?? sunPoints.first(where:{ $0.1>3 }) {
            let label=context.resolve(Text("Sun").font(.caption2.weight(.semibold)).foregroundStyle(palette.accent))
            let measured=label.measure(in:CGSize(width:60,height:20))
            context.draw(label,at:CGPoint(x:min(max(x(last.0),measured.width/2+4),size.width-measured.width/2-4),y:max(measured.height/2+2,y(last.1)-measured.height/2-3)))
        }
        if let moonPeak,let symbol=context.resolveSymbol(id:"moon") { context.draw(symbol,at:moonPeak) }

        // True darkness, bracketed on the ground in amber.
        if let darkStart=night.sky.darkStart,let darkEnd=night.sky.darkEnd,darkEnd>darkStart {
            let a=max(0,x(darkStart)), b=min(size.width,x(darkEnd)), barY=horizon+9
            var bar=Path(); bar.move(to:CGPoint(x:a,y:barY)); bar.addLine(to:CGPoint(x:b,y:barY))
            context.stroke(bar,with:.color(palette.accent.opacity(0.85)),style:StrokeStyle(lineWidth:2*palette.stroke,lineCap:.round))
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
                        context.stroke(mark,with:.color(palette.line),lineWidth:0.6*palette.stroke)
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
            context.stroke(marker,with:.color(palette.ink.opacity(0.7)),style:StrokeStyle(lineWidth:0.8*palette.stroke,dash:[2,2]))
            context.fill(Path(ellipseIn:CGRect(x:nx-3.5,y:horizon-3.5,width:7,height:7)),with:.color(palette.ink))
            let label=context.resolve(Text("Now").font(.caption2.weight(.semibold)).foregroundStyle(palette.ink))
            context.draw(label,at:CGPoint(x:min(max(nx,16),size.width-16),y:8))
        }
    }

    /// Where the finger rests: a hairline through the arc and the time and sky beside it, for anyone
    /// who explores by touch with some sight. VoiceOver hears the same line when the finger rests.
    @ViewBuilder private var finger:some View {
        if let i=touchColumn, touchColumns.indices.contains(i), chartWidth>0 {
            let x=(Double(i)+0.5)*chartWidth/Double(ArcTouch.columnCount)
            let caption=ArcTouch.caption(touchColumns[i],night:night), width=chartWidth
            let ground=chartHeight-22, label=labelRow(at:x)
            ZStack(alignment:.topLeading) {
                // Through the sky and the amber bar, then again below the "True darkness" label, never
                // through its words.
                Rectangle().fill(palette.ink.opacity(0.85)).frame(width:palette.stroke,height:label.map { $0.lowerBound } ?? ground)
                    .offset(x:x-palette.stroke/2)
                if let label {
                    Rectangle().fill(palette.ink.opacity(0.85)).frame(width:palette.stroke,height:max(0,ground-label.upperBound))
                        .offset(x:x-palette.stroke/2,y:label.upperBound)
                }
                // Short captions hug the finger; at large text sizes a long one wraps to two lines
                    // inside the chart (6 pt from each edge) instead of being cut at both ends.
                Text(caption).font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(palette.ink).multilineTextAlignment(.center)
                    .padding(.horizontal,8).padding(.vertical,3)
                    .background(RoundedRectangle(cornerRadius:10).fill(palette.panel)).overlay(RoundedRectangle(cornerRadius:10).stroke(palette.line,lineWidth:0.5*palette.stroke))
                    .padding(.horizontal,6)
                    .fixedSize(horizontal:false,vertical:true)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .alignmentGuide(.leading) { d in -min(max(x-d.width/2,0),width-d.width) }
                    .offset(y:6)
            }
            .frame(width:chartWidth,height:chartHeight,alignment:.topLeading)
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
    /// The rows the "True darkness" label takes under the amber bar, when the drawing names it and
    /// the finger at `x` stands over the bar (as `draw` places them: the bar 9 pt under the horizon).
    private func labelRow(at x:Double)->ClosedRange<Double>? {
        guard let darkStart=night.sky.darkStart, let darkEnd=night.sky.darkEnd, darkEnd>darkStart, chartWidth>0 else { return nil }
        let (start,end)=window, duration=end.timeIntervalSince(start)
        guard duration>0 else { return nil }
        let a=max(0,darkStart.timeIntervalSince(start)/duration*chartWidth), b=min(chartWidth,darkEnd.timeIntervalSince(start)/duration*chartWidth)
        guard b-a>70, x>=a, x<=b else { return nil }
        let barY=(chartHeight-22)*0.74+9
        return (barY+3)...(barY+19)
    }
    /// A finger at `x` on the arc: the hum follows it, moments crossed click, and resting 0.4 s
    /// says the time and the sky. `quiet` (DEBUG captures) draws the finger only.
    /// `held`: from the sighted hold.
    private func touch(at x:Double,quiet:Bool=false,held:Bool=false) {
        guard touchEnabled || touching || holding || held || quiet, chartWidth>0 else { return }
        let fresh=touchColumns.isEmpty
        if fresh { touchColumns=ArcTouch.columns(night:night,window:window) }
        let sample=ArcTouch.sample(x:x,width:chartWidth,columns:touchColumns,night:night,tonight:isTonight)
        guard sample.column != touchColumn else { return }
        let previous=touchColumn
        touchColumn=sample.column
        if quiet { return }
        if fresh { MoonHaptics.shared.beginArcTouch(strength:sample.strength) }
        let crossed=previous.map { ArcTouch.crossed(touchColumns,from:$0,to:sample.column) } ?? sample.crossing.map { [$0] } ?? []
        MoonHaptics.shared.followArcTouch(strength:sample.strength,crossings:crossed)
        restTask?.cancel()
        // Spoken only for VoiceOver; a sighted finger reads the same words in the caption.
        guard voiceOver else { return }
        let spoken=sample.spoken
        restTask=Task {
            try? await Task.sleep(for:.milliseconds(400))
            if !Task.isCancelled { NightListener.announce(spoken,priority:.low) }
        }
    }
    private func endTouch() {
        holding=false
        restTask?.cancel(); restTask=nil
        MoonHaptics.shared.endArcTouch()
        touchColumn=nil
        touchColumns=[]
    }

    @ViewBuilder private var legend:some View {
        Label("Sun",systemImage:"sun.max").foregroundStyle(palette.accent)
        Label("Moon",systemImage:"moon")
        Label { Text("Milky Way core") } icon:{ SkyGlyph(.core,color:palette.muted).frame(width:16,height:16) }
    }
    private func timeLabel(_ title:LocalizedStringKey,time:Date?)->some View {
        VStack(alignment:.leading,spacing:4) { Text(title).font(.caption).foregroundStyle(palette.muted); Text(night.park.time(time)).font(.system(.title3,design:.serif)) }
    }
}
/// Touch and hold the sky arc's picture, then slide: UIKit's long press (0.3 s, 10 pt of slack).
/// It hands over where the finger is the moment the hold succeeds, so the hairline appears under a
/// still finger, and it fails as soon as a finger travels first, so a flick over the arc scrolls the
/// page; a SwiftUI long press sequenced before a drag reported no place until the finger moved, and
/// over the park page's scroll view it kept a swipe that began on the arc from scrolling (iOS 27).
/// `changed` gets the finger's x in the picture while held and nil when the hold ends, is cancelled
/// or fails. Off while VoiceOver's direct touch owns the arc.
private struct ArcHold: UIGestureRecognizerRepresentable {
    var enabled=true
    let changed:(Double?)->Void
    func makeUIGestureRecognizer(context:Context)->UILongPressGestureRecognizer {
        let recognizer=UILongPressGestureRecognizer()
        recognizer.minimumPressDuration=0.3
        recognizer.allowableMovement=10
        recognizer.isEnabled=enabled
        return recognizer
    }
    func updateUIGestureRecognizer(_ recognizer:UILongPressGestureRecognizer,context:Context) {
        recognizer.isEnabled=enabled
    }
    func handleUIGestureRecognizerAction(_ recognizer:UILongPressGestureRecognizer,context:Context) {
        switch recognizer.state {
        case .began,.changed: changed(context.converter.localLocation.x)
        default: changed(nil)
        }
    }
}
#Preview("Arc") { if let p=try? ParkData.load().first(where:{$0.id=="jotr"}) { let sky=AstronomyEngine().conditions(for:p,on:.now); SkyArc(night:Night(park:p,sky:sky,score:ScoreEngine().score(sky:sky,bortle:p.bortleEstimate,cloudCover:nil),cloudCover:nil,forecastUpdated:nil)).padding().background(.black) } }

#Preview("Arc • Bold Text") { if let p=try? ParkData.load().first(where:{$0.id=="jotr"}) { let sky=AstronomyEngine().conditions(for:p,on:.now); SkyArc(night:Night(park:p,sky:sky,score:ScoreEngine().score(sky:sky,bortle:p.bortleEstimate,cloudCover:nil),cloudCover:nil,forecastUpdated:nil)).padding().background(.black).environment(\.nyx,NyxPalette(nightVision:false,highContrast:false,boldText:true)) } }

#Preview("No astronomical darkness • AX5") { let m=PlanModel();if let p=m.park("dena") { SkyArc(night:m.night(p,on:Date(timeIntervalSince1970:1782086400))).padding().dynamicTypeSize(.accessibility5).background(.black) } }

#Preview("Arc • Finger resting") { if let p=try? ParkData.load().first(where:{$0.id=="deva"}) { let sky=AstronomyEngine().conditions(for:p,on:.now); SkyArc(night:Night(park:p,sky:sky,score:ScoreEngine().score(sky:sky,bortle:p.bortleEstimate,cloudCover:nil),cloudCover:nil,forecastUpdated:nil),restsFinger:true).padding().background(.black) } }

