import SwiftUI

/// "Where to look": the real sky over the park, turned to wherever the phone points. Not AR:
/// no camera and no overlay, only the sky's geometry drawn in red on black, with the horizon,
/// the cardinal points, the Milky Way along the galactic plane, the brighter stars, and labels for the Moon, the Milky Way's core, the
/// planets and a shower's radiant. Targets out of view get an arrow at the edge. A list gives
/// the same facts to VoiceOver ("Jupiter: 32° up, east-southeast"), and a freeze holds the view.
struct FieldCompassView: View {
    let session: FieldSession
    var fixedPose: SkyCompass.Pose?=nil
    /// At accessibility sizes the eye's clock ends the list (the sky view leaves it to the night page).
    var eyeClock: Binding<Bool>?=nil
    /// At accessibility sizes, what the score's clouds rest on opens the list (the header leaves it to the page).
    var note: String?=nil
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var frozen: SkyCompass.Pose?
    @State private var listed: Bool?
    @State private var targets: [FieldSkyTarget]=[]
    @State private var stars: [CompassStar]=[]
    @State private var band=CompassBand.none
    @State private var explainsBeacon=false
    /// The sky view's measured size, so the spoken "In view" list matches what is drawn.
    @State private var canvasSize=CGSize(width:390,height:600)
    /// VoiceOver's value for the sky view, refreshed once a second rather than every frame.
    @State private var spokenSky=""
    @Environment(\.nyxAccess) private var access
    private var beacon: SkyBeacon { .shared }
    private var motion: FieldMotion { .shared }
    private var sensing: Bool { fixedPose != nil || motion.available }
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The list first under VoiceOver, without attitude sensing, and at accessibility sizes, where
    /// the drawn sky would be a sliver between large controls; the sky stays one tap away.
    private var showsList: Bool { listed ?? (voiceOver || !sensing || typeSize.isAccessibilitySize) }
    private var controlsInList: Bool { showsList && typeSize.isAccessibilitySize }
    var body: some View {
        VStack(spacing:12) {
            if showsList { list } else { sky }
            // At accessibility sizes the list's controls scroll with it: pinned under it, they left the
            // list a sliver between the header and the page switch.
            if !controlsInList { controls.padding(.horizontal,20).readableColumn(WideLayout.proseWidth) }
        }
        .task(id:session.park.id) {
            // Stars move a quarter of a degree a minute: positions are refreshed twice a minute.
            while !Task.isCancelled {
                let now=session.now
                targets=FieldSkyTarget.named(park:session.park,sky:session.night.sky,at:now)
                stars=CompassStar.visible(park:session.park,at:now)
                band=CompassBand.visible(park:session.park,moonIllumination:session.night.sky.moon.illumination,at:now)
                try? await Task.sleep(for:.seconds(30))
            }
        }
        .onAppear { if fixedPose == nil { motion.start() } }
        .onDisappear { motion.stop(); beacon.stop() }
        .sheet(isPresented:$explainsBeacon) {
            PermissionExplainer(symbol:"headphones",title:"Where to look by sound",message:"With headphones, a soft tone sits where the Milky Way's core, a planet or the Moon is, and quickens as you turn toward it, so you can find it with the screen dark. With AirPods that track your head, iOS asks once to use their motion; it stays on this iPhone. Nothing is recorded.",action:"Play the tone") {
                SkyBeacon.explained=true; explainsBeacon=false; switchBeacon(true)
            }.nyxPresentation()
        }
    }
    private func switchBeacon(_ on:Bool) {
        if on && !SkyBeacon.explained { explainsBeacon=true; return }
        beacon.set(on,park:session.park,sky:session.night.sky) { [session] in session.now }
    }
    /// The pose drawn now: held, pinned for a capture, or the phone's.
    private var pose: SkyCompass.Pose { frozen ?? fixedPose ?? motion.pose ?? SkyCompass.Pose(azimuth:180,altitude:30) }
    private var sky: some View {
        // Half the rate in Low Power Mode or when the system asks for less: still following the
        // phone, at less cost. Resting while the device is hot.
        TimelineView(.animation(minimumInterval:PowerState.shared.lowPower || access.reducedResources ? 1/15 : 1/30,paused:frozen != nil || fixedPose != nil || PowerState.shared.thermalSerious)) { _ in
            let pose=pose, targets=targets, stars=stars, band=band
            Canvas { context,size in draw(&context,size:size,pose:pose,targets:targets,stars:stars,band:band) }
        }
        .onGeometryChange(for:CGSize.self) { $0.size } action:{ canvasSize=$0 }
        .accessibilityElement(children:.ignore)
        .accessibilityLabel("Sky view")
        .accessibilityValue(spokenSky)
        .accessibilityHint("Hold your iPhone up toward the sky. A list is also available.")
        .accessibilityAction(named:"Show as a list") { listed=true }
        .task(id:SpokenSkyKey(size:canvasSize,frozen:frozen != nil,targets:targets.count)) {
            while !Task.isCancelled {
                let line=summary(pose,size:canvasSize)
                if line != spokenSky { spokenSky=line }
                try? await Task.sleep(for:.seconds(1))
            }
        }
        // Labels drawn in the sky stop growing at the first accessibility size, where they would
        // cover each other; the list carries every size.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityIgnoresInvertColors(true)
    }
    private var list: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                if let note { Text(note).font(.caption).fixedSize(horizontal:false,vertical:true) }
                if controlsInList { controls.padding(.bottom,8) }
                let sorted=targets.sorted { ($0.altitude > -0.5 ? 0 : 1,-$0.altitude)<($1.altitude > -0.5 ? 0 : 1,-$1.altitude) }
                ForEach(sorted) { target in
                    VStack(alignment:.leading,spacing:4) {
                        Text(target.name).font(.system(.title3,design:.serif))
                        Text(SkyCompass.spoken(altitude:target.altitude,azimuth:target.azimuth)).font(.body).foregroundStyle(palette.muted)
                    }
                    .frame(maxWidth:.infinity,alignment:.leading)
                    .accessibilityElement(children:.ignore).accessibilityLabel(target.spoken)
                }
                if !sensing { Text("This iPhone can't sense where it is pointing, so the sky is listed instead.").font(.footnote).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
                if let eyeClock { EyeClock(session:session,expanded:eyeClock).padding(.top,12) }
            }.padding(.horizontal,24).padding(.vertical,12).readableColumn(WideLayout.proseWidth)
        }
    }
    private var controls: some View {
        VStack(alignment:.leading,spacing:8) {
            ViewThatFits(in:.horizontal) {
                HStack(spacing:12) { buttons }
                VStack(alignment:.leading,spacing:8) { buttons }
            }.font(.subheadline)
            if beacon.isOn { beaconStatus }
            if sensing && fixedPose == nil {
                Text(motion.trueNorth ? String(localized:"Directions use true north.") : String(localized:"Directions use magnetic north, which can differ from true north by several degrees."))
                    .font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                if motion.needsCalibration { Text("Move your iPhone in a slow figure eight to steady the compass.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    @ViewBuilder private var buttons: some View {
        if sensing && !showsList {
            Button { frozen=frozen == nil ? (motion.pose ?? fixedPose) : nil } label:{
                Label(frozen == nil ? "Hold still" : "Follow my iPhone",systemImage:frozen == nil ? "pause" : "location.north.line")
            }.buttonStyle(.bordered)
        }
        if sensing {
            Button { listed = !showsList } label:{ Label(showsList ? "Sky" : "List",systemImage:showsList ? "scope" : "list.bullet") }.buttonStyle(.bordered)
        }
        // DEBUG captures pin the pose; `-nyx-beacon` shows the switch there too.
        if sensing && SkyBeacon.supported && (fixedPose == nil || DebugScenario.isEnabled("beacon")) {
            Toggle(isOn:Binding(get:{ beacon.isOn },set:{ switchBeacon($0) })) { Label("Sound",systemImage:"headphones") }
                .toggleStyle(.button).buttonStyle(.bordered)
                .accessibilityLabel("Where to look by sound")
                .accessibilityHint("Plays a tone in your headphones from the direction of a target in the sky.")
                .accessibilityInputLabels([Text("Sound"),Text("Tone"),Text("Where to look by sound")])
        }
    }
    /// What the tone points to, and a way to point it at something else.
    private var beaconStatus: some View {
        VStack(alignment:.leading,spacing:6) {
            if let target=beacon.target {
                Text("The tone points to \(target.spoken).").font(.caption).fixedSize(horizontal:false,vertical:true)
            } else {
                Text("Nothing Nyx can point to is above the horizon now.").font(.caption).fixedSize(horizontal:false,vertical:true)
            }
            if beacon.choices.count>1 {
                Picker("Toward",selection:Binding(get:{ beacon.chosenID ?? "" },set:{ beacon.choose($0.isEmpty ? nil : $0) })) {
                    Text("Automatic").tag("")
                    ForEach(beacon.choices) { Text($0.name).tag($0.id) }
                }.pickerStyle(.menu).font(.caption)
            }
            Text(beacon.headTracking ? String(localized:"Following your head.") : String(localized:"Following your iPhone. Headphones carry the direction; the speaker only the quickening pulse.")).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }
    }
    /// "Facing south, 30° up. In view: Jupiter, Milky Way core." Placed on the drawn sky's own size
    /// and field of view, so it names what the screen shows.
    private func summary(_ pose:SkyCompass.Pose,size:CGSize)->String {
        let facing=String(localized:"Facing \(Compass.fine(pose.azimuth)), \(Int(pose.altitude.rounded()))° up.")
        let w=Double(size.width), h=Double(size.height), fov=SkyCompass.horizontalFieldOfView(width:w,height:h)
        let inView=targets.filter { $0.altitude > -0.5 && SkyCompass.place(altitude:$0.altitude,azimuth:$0.azimuth,pose:pose,width:w,height:h,fieldOfView:fov).point != nil }.map(\.name)
        return inView.isEmpty ? facing : facing+" "+String(localized:"In view: \(inView.formatted(.list(type:.and))).")
    }
    /// What restarts the spoken value's refresh at once: a new size, a hold, new targets.
    private struct SpokenSkyKey: Equatable { let size:CGSize; let frozen:Bool; let targets:Int }
    // MARK: Drawing

    private func draw(_ context:inout GraphicsContext,size:CGSize,pose:SkyCompass.Pose,targets:[FieldSkyTarget],stars:[CompassStar],band:CompassBand) {
        let ink=palette.ink, w=size.width, h=size.height, fov=SkyCompass.horizontalFieldOfView(width:w,height:h)
        func at(_ altitude:Double,_ azimuth:Double)->SkyCompass.Placement { SkyCompass.place(altitude:altitude,azimuth:azimuth,pose:pose,width:w,height:h,fieldOfView:fov) }
        func point(_ p:SIMD2<Double>)->CGPoint { CGPoint(x:p.x,y:p.y) }
        // Farthest first: the Milky Way under everything else.
        if band.visibility>0.02 { drawBand(&context,band:band,pose:pose,size:size,fieldOfView:fov,ink:ink) }
        // Altitude rings at 30° and 60°, and the horizon, each a run of short segments in view.
        for (altitude,opacity,width) in [(0.0,0.7,1.2),(30.0,0.2,0.6),(60.0,0.2,0.6)] {
            var path=Path(), drawing=false
            for step in 0...180 {
                let placed=SkyCompass.place(altitude:altitude,azimuth:Double(step)*2,pose:pose,width:w,height:h,fieldOfView:fov,clipped:false)
                // Points far beyond the edge are left out, so a line never sweeps across from behind.
                if let p=placed.point, abs(p.x-w/2)<w*3, abs(p.y-h/2)<h*3 { let q=CGPoint(x:p.x,y:p.y); if drawing { path.addLine(to:q) } else { path.move(to:q); drawing=true } } else { drawing=false }
            }
            context.stroke(path,with:.color(ink.opacity(opacity)),style:StrokeStyle(lineWidth:width,dash:altitude==0 ? [] : [2,5]))
        }
        // Cardinal points on the horizon.
        for (azimuth,name) in [(0.0,String(localized:"N")),(90,String(localized:"E")),(180,String(localized:"S")),(270,String(localized:"W"))] {
            // Under the horizon, but never below the window's foot, where the control tray would cut it.
            if let p=at(0,azimuth).point {
                let text=context.resolve(Text(name).font(.system(.callout,design:.serif).weight(.semibold)).foregroundStyle(ink))
                let half=text.measure(in:size).height/2
                let y=p.y+14+half>h-4 ? p.y-14 : p.y+14
                context.draw(text,at:CGPoint(x:p.x,y:min(h-half-4,y)))
            }
        }
        for star in stars {
            guard let p=at(star.altitude,star.azimuth).point else { continue }
            let d=max(1.4,4.2-0.8*star.magnitude)
            // The few brightest (Vega, Arcturus, Antares…) get a faint halo, so they read as landmarks at arm's length.
            if star.magnitude<1.5 {
                let r=d*2.2
                context.fill(Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2)),with:.radialGradient(Gradient(colors:[ink.opacity(0.22),ink.opacity(0)]),center:CGPoint(x:p.x,y:p.y),startRadius:0,endRadius:r))
            }
            context.fill(Path(ellipseIn:CGRect(x:p.x-d/2,y:p.y-d/2,width:d,height:d)),with:.color(ink.opacity(max(0.4,min(1,1.15-0.15*star.magnitude)))))
        }
        // Labels never cover each other: brightest first, each takes the first free spot around
        // its mark (above, below, right, left); one with no room keeps its mark and loses its name.
        var taken: [CGRect]=[]
        func label(_ text:Text,near c:CGPoint,gap:Double) {
            let resolved=context.resolve(text), s=resolved.measure(in:size)
            let spots=[CGPoint(x:c.x,y:c.y-gap),CGPoint(x:c.x,y:c.y+gap),CGPoint(x:c.x+gap/2+s.width/2+6,y:c.y),CGPoint(x:c.x-gap/2-s.width/2-6,y:c.y)]
            for spot in spots {
                let rect=CGRect(x:spot.x-s.width/2,y:spot.y-s.height/2,width:s.width,height:s.height).insetBy(dx:-3,dy:-1)
                guard rect.minX>=0,rect.maxX<=w,rect.minY>=0,rect.maxY<=h,!taken.contains(where:{ $0.intersects(rect) }) else { continue }
                // A dark halo keeps each name at full contrast where it crosses the Milky Way.
                taken.append(rect); context.drawLayer { layer in layer.addFilter(.shadow(color:.black,radius:3)); layer.draw(resolved,at:spot) }; return
            }
        }
        let ordered=targets.filter { $0.altitude > -0.5 }.sorted { $0.magnitude<$1.magnitude }
        var arrows: [(angle:Double,name:String)]=[]
        for target in ordered {
            let placed=at(target.altitude,target.azimuth)
            guard let p=placed.point else { arrows.append((placed.edgeAngle,target.name)); continue }
            let c=point(p)
            switch target.kind {
            case .moon:
                let lit=session.night.sky.moon.illumination
                context.fill(Path(ellipseIn:CGRect(x:c.x-11,y:c.y-11,width:22,height:22)),with:.color(ink.opacity(0.25+0.7*lit)))
                context.stroke(Path(ellipseIn:CGRect(x:c.x-11,y:c.y-11,width:22,height:22)),with:.color(ink),lineWidth:1)
            case .core:
                // The bulge's brightest knot, round and soft, fading with the band (moonlight, twilight); the band carries the rest.
                context.fill(Path(ellipseIn:CGRect(x:c.x-30,y:c.y-30,width:60,height:60)),with:.radialGradient(Gradient(colors:[ink.opacity(0.12+0.18*band.visibility),ink.opacity(0.08*band.visibility),ink.opacity(0)]),center:c,startRadius:0,endRadius:30))
            case .planet:
                context.fill(Path(ellipseIn:CGRect(x:c.x-12,y:c.y-12,width:24,height:24)),with:.radialGradient(Gradient(colors:[ink.opacity(0.25),ink.opacity(0)]),center:c,startRadius:0,endRadius:12))
                context.fill(Path(ellipseIn:CGRect(x:c.x-4.5,y:c.y-4.5,width:9,height:9)),with:.color(ink))
            case .radiant:
                var rays=Path()
                for i in 0..<10 { let a=Double(i)*Double.pi/5; rays.move(to:CGPoint(x:c.x+7*cos(a),y:c.y+7*sin(a))); rays.addLine(to:CGPoint(x:c.x+(i%2==0 ? 18 : 13)*cos(a),y:c.y+(i%2==0 ? 18 : 13)*sin(a))) }
                context.stroke(rays,with:.color(ink.opacity(0.8)),lineWidth:1)
            case .star: break
            }
            label(Text(target.name).font(.system(.subheadline,design:.serif)).foregroundStyle(ink),near:c,gap:target.kind == .core ? 30 : 22)
        }
        for arrow in arrows { edgeArrow(&context,size:size,angle:arrow.angle,name:arrow.name,ink:ink,taken:&taken) }
        // The middle of the window, where the back of the phone points: a crosshair with an open
        // centre, so it never reads as one of the round target marks.
        var reticle=Path()
        for (dx,dy) in [(1.0,0.0),(-1,0),(0,1),(0,-1)] {
            reticle.move(to:CGPoint(x:w/2+dx*6,y:h/2+dy*6)); reticle.addLine(to:CGPoint(x:w/2+dx*16,y:h/2+dy*16))
        }
        context.stroke(reticle,with:.color(ink.opacity(0.6)),style:StrokeStyle(lineWidth:1,lineCap:.round))
    }
    /// The Milky Way: soft discs along the galactic plane, added together, each as wide as the band is
    /// there and as bright as RealSky's model, dimmed toward the horizon (more air to look through),
    /// by twilight, moonlight and sky glow (`CompassBand.visibility`), and kept above the horizon.
    /// Positions are computed twice a minute; each frame only re-projects them for the phone's pose.
    private func drawBand(_ context:inout GraphicsContext,band:CompassBand,pose:SkyCompass.Pose,size:CGSize,fieldOfView fov:Double,ink:Color) {
        let w=size.width, h=size.height, rad=Double.pi/180, focal=(w/2)/tan(fov*rad/2)
        var layer=context
        if let sky=SkyCompass.skySide(pose:pose,width:w,height:h,fieldOfView:fov) { layer.clip(to:Path { $0.addLines(sky.map { CGPoint(x:$0.x,y:$0.y) }); $0.closeSubpath() }) }
        else if pose.altitude<0 { return }
        layer.blendMode = .plusLighter
        let stops=Gradient(stops:[.init(color:ink,location:0),.init(color:ink.opacity(0.55),location:0.4),.init(color:ink.opacity(0.15),location:0.75),.init(color:ink.opacity(0),location:1)])
        for sample in band.samples {
            let placed=SkyCompass.place(altitude:sample.altitude,azimuth:sample.azimuth,pose:pose,width:w,height:h,fieldOfView:fov,clipped:false)
            guard let p=placed.point else { continue }
            let r=focal*tan(sample.halfWidth*rad)/max(0.3,cos(placed.separation*rad))
            guard p.x > -r, p.x<w+r, p.y > -r, p.y<h+r else { continue }
            let extinction=0.35+0.65*min(1,max(0,sample.altitude/25))
            // Discs every 3° overlap about r/3 deep along the band; dividing by that keeps the summed
            // centre line near a quarter of the ink at the core and under a tenth on the faint side.
            let opacity=0.24*sample.brightness*band.visibility*extinction*3/sample.halfWidth
            layer.opacity=opacity
            layer.fill(Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2)),with:.radialGradient(stops,center:CGPoint(x:p.x,y:p.y),startRadius:0,endRadius:r))
        }
        // The window's top edge fades rather than cutting the band under the header.
        context.fill(Path(CGRect(x:0,y:0,width:w,height:56)),with:.linearGradient(Gradient(colors:[.black,.black.opacity(0)]),startPoint:.zero,endPoint:CGPoint(x:0,y:56)))
    }
    /// An arrow just inside the edge toward a target out of view, with its name.
    private func edgeArrow(_ context:inout GraphicsContext,size:CGSize,angle:Double,name:String,ink:Color,taken:inout [CGRect]) {
        let inset=44.0, cx=size.width/2, cy=size.height/2
        let dx=cos(angle), dy = -sin(angle)
        let scale=min((cx-inset)/max(abs(dx),0.001),(cy-inset)/max(abs(dy),0.001))
        let p=CGPoint(x:cx+dx*scale,y:cy+dy*scale)
        var arrow=Path()
        let tip=CGPoint(x:p.x+dx*10,y:p.y+dy*10), back=CGPoint(x:p.x-dx*4,y:p.y-dy*4)
        arrow.move(to:CGPoint(x:back.x-dy*6,y:back.y+dx*6)); arrow.addLine(to:tip); arrow.addLine(to:CGPoint(x:back.x+dy*6,y:back.y-dx*6))
        context.stroke(arrow,with:.color(ink.opacity(0.85)),style:StrokeStyle(lineWidth:1.4,lineCap:.round,lineJoin:.round))
        // The name sits just inside the arrow; when another name is already there, the arrow alone points.
        let resolved=context.resolve(Text(name).font(.caption).foregroundStyle(ink.opacity(0.9))), s=resolved.measure(in:size)
        let at=CGPoint(x:min(max(p.x-dx*(14+s.width/2),s.width/2+4),size.width-s.width/2-4),y:p.y-dy*16)
        let rect=CGRect(x:at.x-s.width/2,y:at.y-s.height/2,width:s.width,height:s.height)
        guard !taken.contains(where:{ $0.intersects(rect) }) else { return }
        taken.append(rect); context.drawLayer { layer in layer.addFilter(.shadow(color:.black,radius:3)); layer.draw(resolved,at:at) }
    }
}

/// The Milky Way over the park at one moment: its centre line in altitude and azimuth, and how much
/// of it the eye can see then.
nonisolated struct CompassBand: Sendable {
    struct Sample: Sendable { let altitude: Double; let azimuth: Double; let brightness: Double; let halfWidth: Double }
    let samples: [Sample]
    let visibility: Double
    static let none=CompassBand(samples:[],visibility:0)
    static func visible(park:Park,moonIllumination:Double,at date:Date)->CompassBand {
        let engine=AstronomyEngine()
        let visibility=SkyCompass.milkyWayVisibility(sunAltitude:engine.solarAltitude(at:date,park:park),moonAltitude:engine.lunarAltitude(at:date,park:park),moonIllumination:moonIllumination,bortle:park.bortleEstimate)
        guard visibility>0.02 else { return .none }
        // Points just under the horizon still light the sky above it (the disc is wider than the gap).
        let samples=SkyCompass.galacticPlane().compactMap { point -> Sample? in
            let h=engine.horizontal(date:date,park:park,ra:point.ra,dec:point.dec)
            return h.altitude > -point.halfWidth ? Sample(altitude:h.altitude,azimuth:h.azimuth,brightness:point.brightness,halfWidth:point.halfWidth) : nil
        }
        return CompassBand(samples:samples,visibility:visibility)
    }
}

/// A catalogue star in the park's sky at one moment.
struct CompassStar: Sendable {
    let altitude: Double
    let azimuth: Double
    let magnitude: Double
    /// Stars to magnitude 3.6 that are above the horizon.
    @MainActor static func visible(park:Park,at date:Date)->[CompassStar] {
        let engine=AstronomyEngine()
        return SkyProjection.shared.stars(brighterThan:3.6).compactMap { star in
            let h=engine.horizontal(date:date,park:park,ra:star.ra,dec:star.dec)
            return h.altitude > -1 ? CompassStar(altitude:h.altitude,azimuth:h.azimuth,magnitude:star.mag) : nil
        }
    }
}
