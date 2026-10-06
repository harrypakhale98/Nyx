import SwiftUI

/// "Where to look": the real sky over the park, turned to wherever the phone points. Not AR:
/// no camera and no overlay, only the sky's geometry drawn in red on black, with the horizon,
/// the cardinal points, the brighter stars, and labels for the Moon, the Milky Way's core, the
/// planets and a shower's radiant. Targets out of view get an arrow at the edge. A list gives
/// the same facts to VoiceOver ("Jupiter: 32° up, east-southeast"), and a freeze holds the view.
struct FieldCompassView: View {
    let session: FieldSession
    var fixedPose: SkyCompass.Pose?=nil
    /// At accessibility sizes the eye's clock ends the list (the sky view leaves it to the night page).
    var eyeClock: Binding<Bool>?=nil
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var frozen: SkyCompass.Pose?
    @State private var listed: Bool?
    @State private var targets: [FieldSkyTarget]=[]
    @State private var stars: [CompassStar]=[]
    private var motion: FieldMotion { .shared }
    private var sensing: Bool { fixedPose != nil || motion.available }
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The list first under VoiceOver, without attitude sensing, and at accessibility sizes, where
    /// the drawn sky would be a sliver between large controls; the sky stays one tap away.
    private var showsList: Bool { listed ?? (voiceOver || !sensing || typeSize.isAccessibilitySize) }
    var body: some View {
        VStack(spacing:12) {
            if showsList { list } else { sky }
            controls.padding(.horizontal,20).readableColumn(WideLayout.proseWidth)
        }
        .task(id:session.park.id) {
            // Stars move a quarter of a degree a minute: positions are refreshed twice a minute.
            while !Task.isCancelled {
                let now=session.now
                targets=FieldSkyTarget.named(park:session.park,sky:session.night.sky,at:now)
                stars=CompassStar.visible(park:session.park,at:now)
                try? await Task.sleep(for:.seconds(30))
            }
        }
        .onAppear { if fixedPose == nil { motion.start() } }
        .onDisappear { motion.stop() }
    }
    private var sky: some View {
        TimelineView(.animation(minimumInterval:1/30,paused:frozen != nil || fixedPose != nil)) { _ in
            let pose=frozen ?? fixedPose ?? motion.pose ?? SkyCompass.Pose(azimuth:180,altitude:30)
            let targets=targets, stars=stars
            Canvas { context,size in draw(&context,size:size,pose:pose,targets:targets,stars:stars) }
                .accessibilityElement(children:.ignore)
                .accessibilityLabel("Sky view")
                .accessibilityValue(summary(pose))
                .accessibilityHint("Hold your iPhone up toward the sky. A list is also available.")
                .accessibilityAction(named:"Show as a list") { listed=true }
        }
        // Labels drawn in the sky stop growing at the first accessibility size, where they would
        // cover each other; the list carries every size.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityIgnoresInvertColors(true)
    }
    private var list: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
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
    }
    /// "Facing south, 30° up. In view: Jupiter, Milky Way core."
    private func summary(_ pose:SkyCompass.Pose)->String {
        let facing=String(localized:"Facing \(Compass.fine(pose.azimuth)), \(Int(pose.altitude.rounded()))° up.")
        let inView=targets.filter { $0.altitude > -0.5 && SkyCompass.place(altitude:$0.altitude,azimuth:$0.azimuth,pose:pose,width:390,height:600).point != nil }.map(\.name)
        return inView.isEmpty ? facing : facing+" "+String(localized:"In view: \(inView.formatted(.list(type:.and))).")
    }
    // MARK: Drawing

    private func draw(_ context:inout GraphicsContext,size:CGSize,pose:SkyCompass.Pose,targets:[FieldSkyTarget],stars:[CompassStar]) {
        let ink=palette.ink, w=size.width, h=size.height, fov=SkyCompass.horizontalFieldOfView(width:w,height:h)
        func at(_ altitude:Double,_ azimuth:Double)->SkyCompass.Placement { SkyCompass.place(altitude:altitude,azimuth:azimuth,pose:pose,width:w,height:h,fieldOfView:fov) }
        func point(_ p:SIMD2<Double>)->CGPoint { CGPoint(x:p.x,y:p.y) }
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
            if let p=at(0,azimuth).point { context.draw(Text(name).font(.system(.callout,design:.serif).weight(.semibold)).foregroundStyle(ink),at:CGPoint(x:p.x,y:p.y+14)) }
        }
        for star in stars {
            guard let p=at(star.altitude,star.azimuth).point else { continue }
            let d=max(1.2,3.4-0.7*star.magnitude)
            context.fill(Path(ellipseIn:CGRect(x:p.x-d/2,y:p.y-d/2,width:d,height:d)),with:.color(ink.opacity(max(0.35,min(1,1.1-0.15*star.magnitude)))))
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
                taken.append(rect); context.draw(resolved,at:spot); return
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
                context.fill(Path(ellipseIn:CGRect(x:c.x-34,y:c.y-22,width:68,height:44)),with:.radialGradient(Gradient(colors:[ink.opacity(0.35),ink.opacity(0)]),center:c,startRadius:0,endRadius:34))
            case .planet:
                context.fill(Path(ellipseIn:CGRect(x:c.x-4,y:c.y-4,width:8,height:8)),with:.color(ink))
            case .radiant:
                var rays=Path()
                for i in 0..<10 { let a=Double(i)*Double.pi/5; rays.move(to:CGPoint(x:c.x+7*cos(a),y:c.y+7*sin(a))); rays.addLine(to:CGPoint(x:c.x+(i%2==0 ? 18 : 13)*cos(a),y:c.y+(i%2==0 ? 18 : 13)*sin(a))) }
                context.stroke(rays,with:.color(ink.opacity(0.8)),lineWidth:1)
            case .star: break
            }
            label(Text(target.name).font(.system(.subheadline,design:.serif)).foregroundStyle(ink),near:c,gap:target.kind == .core ? 30 : 22)
        }
        for arrow in arrows { edgeArrow(&context,size:size,angle:arrow.angle,name:arrow.name,ink:ink,taken:&taken) }
        // The middle of the window: where the back of the phone points.
        var reticle=Path(); reticle.addEllipse(in:CGRect(x:w/2-14,y:h/2-14,width:28,height:28))
        context.stroke(reticle,with:.color(ink.opacity(0.5)),lineWidth:0.8)
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
        taken.append(rect); context.draw(resolved,at:at)
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
