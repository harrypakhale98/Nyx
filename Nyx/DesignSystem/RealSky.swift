import SwiftUI

/// The real sky over a park on a night: 904 stars from the Yale Bright Star Catalogue (to
/// magnitude 4.5) in their true colours, and the Milky Way placed along the galactic plane.
/// Seen facing south (north in the southern hemisphere) at the middle of that night's darkness.
/// It is the geometry of the sky, not a visibility forecast: clouds belong to the score.
struct RealSky: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    @Environment(\.nyx) private var palette
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    let park: Park
    let night: Date
    /// 0…1. Higher-scoring nights twinkle harder and show a brighter Milky Way.
    var twinkle: Double=0.3
    var strength: Double=0.6
    var body: some View {
        let sky=SkyProjection.shared.sky(for:park,night:night)
        let strength=palette.nightVision ? strength*0.45 : strength
        TimelineView(.animation(minimumInterval:1/30,paused:reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled)) { timeline in
            let t=reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let tilt=reduceMotion ? (x:0.0,y:0.0) : (x:MotionTilt.shared.x,y:MotionTilt.shared.y)
            ZStack {
                // Far to near: the Milky Way and faint stars barely move, bright stars move most.
                StarLayer(sky:sky,band:.faint,ink:palette.ink,strength:strength,milkyWay:twinkle).equatable().offset(x:tilt.x*2,y:tilt.y*2)
                StarLayer(sky:sky,band:.middle,ink:palette.ink,strength:strength,milkyWay:0).equatable().offset(x:tilt.x*4,y:tilt.y*4)
                Canvas { context,size in
                    let amplitude=0.12+0.3*twinkle, speed=0.45+0.7*twinkle
                    for star in sky.bright {
                        let shimmer=reduceMotion ? 0.85 : 0.7+amplitude*sin(t*speed*(1+star.seed)+star.seed*6.28)
                        StarLayer.draw(star,in:&context,size:size,ink:palette.ink,opacity:shimmer*strength)
                    }
                }.offset(x:tilt.x*7,y:tilt.y*7)
            }
        }
        .onAppear { MotionTilt.shared.start(reduceMotion:reduceMotion) }
        .onDisappear { MotionTilt.shared.stop() }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// One cached depth layer. Equatable, so SwiftUI redraws it only when the sky changes,
/// never on the per-frame parallax offset applied around it.
private struct StarLayer: View, Equatable {
    enum Band { case faint, middle }
    let sky: SkyProjection.Sky
    let band: Band
    let ink: Color
    let strength: Double
    let milkyWay: Double
    static func == (a:Self,b:Self)->Bool { a.sky.id==b.sky.id && a.band==b.band && a.ink==b.ink && a.strength==b.strength && a.milkyWay==b.milkyWay }
    var body: some View {
        Canvas { context,size in
            if band == .faint && sky.dark {
                // The Milky Way: a soft glow along the galactic plane, brightest toward the core.
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius:size.width*0.05))
                    for segment in sky.galaxy {
                        var path=Path()
                        for (i,point) in segment.enumerated() {
                            let p=SkyProjection.screen(point.position,size:size)
                            if i==0 { path.move(to:p) } else { path.addLine(to:p) }
                        }
                        let core=segment.map(\.brightness).reduce(0,+)/Double(max(1,segment.count))
                        glow.stroke(path,with:.color(ink.opacity((0.05+0.11*milkyWay)*core*strength/0.6)),style:StrokeStyle(lineWidth:size.width*0.2,lineCap:.round,lineJoin:.round))
                    }
                }
            }
            for star in band == .faint ? sky.faint : sky.middle { StarLayer.draw(star,in:&context,size:size,ink:ink,opacity:strength) }
        }
    }
    static func draw(_ star:SkyProjection.Star,in context:inout GraphicsContext,size:CGSize,ink:Color,opacity:Double) {
        let p=SkyProjection.screen(star.position,size:size)
        guard p.x > -4, p.x < size.width+4, p.y > -4, p.y < size.height+4 else { return }
        let d=star.diameter
        context.fill(Path(ellipseIn:CGRect(x:p.x-d/2,y:p.y-d/2,width:d,height:d)),with:.color(star.tint(ink).opacity(min(1,star.brightness*opacity))))
    }
}

/// Positions are computed once per park and night and kept, so screens can share them.
@MainActor final class SkyProjection {
    static let shared=SkyProjection()
    nonisolated struct Star: Sendable {
        /// Stereographic projection units; the screen maps about ±0.95 vertically.
        let position: SIMD2<Double>
        let diameter: Double
        let brightness: Double
        /// −0.4 (blue-white) … 2 (deep orange): the B−V colour index.
        let colorIndex: Double
        let seed: Double
        func tint(_ ink:Color)->Color {
            // Ballesteros: B−V to temperature; then a gentle warm/cool tint over starlight.
            let temperature=4600*(1/(0.92*colorIndex+1.7)+1/(0.92*colorIndex+0.62))
            let warmth=max(-1,min(1,(6500-temperature)/3500))
            return warmth>0 ? Color(red:1,green:1-0.18*warmth,blue:1-0.42*warmth).mix(with:ink,by:0.35)
                : Color(red:1+0.25*warmth,green:1+0.1*warmth,blue:1).mix(with:ink,by:0.35)
        }
    }
    nonisolated struct GalaxyPoint: Sendable { let position: SIMD2<Double>; let brightness: Double }
    nonisolated struct Sky: Sendable {
        let id: String
        let faint: [Star]
        let middle: [Star]
        let bright: [Star]
        let galaxy: [[GalaxyPoint]]
        /// True when the Sun is at least 12° down at the moment shown: the Milky Way is drawn only then.
        let dark: Bool
    }
    private var cache:[String:Sky]=[:]
    private lazy var catalogue:[(ra:Double,dec:Double,mag:Double,bv:Double)]={
        guard let url=Bundle.main.url(forResource:"stars",withExtension:"json"),let data=try? Data(contentsOf:url),
              let rows=try? JSONDecoder().decode([[Double]].self,from:data) else { return [] }
        return rows.compactMap { $0.count==4 ? (ra:$0[0]*Double.pi/180,dec:$0[1]*Double.pi/180,mag:$0[2],bv:$0[3]) : nil }
    }()
    /// Map projection units to a screen: the vertical field spans about 125°, the horizontal
    /// about 60° on a phone, close to what you take in standing under the sky.
    nonisolated static func screen(_ p:SIMD2<Double>,size:CGSize)->CGPoint {
        let scale=size.height/2.6
        return CGPoint(x:size.width/2+p.x*scale,y:size.height*0.5-p.y*scale)
    }
    func sky(for park:Park,night:Date)->Sky {
        let engine=AstronomyEngine()
        let sky=engine.conditions(for:park,on:night)
        // The middle of true darkness; otherwise local midnight.
        let moment:Date
        if let a=sky.darkStart,let b=sky.darkEnd,b>a { moment=a.addingTimeInterval(b.timeIntervalSince(a)/2) } else { moment=sky.evening.addingTimeInterval(12*3600) }
        let key="\(park.id)-\(Int(moment.timeIntervalSince1970/600))"
        if let cached=cache[key] { return cached }
        let facing=park.latitude<0 ? 0.0 : 180.0, centreAltitude=45.0*Double.pi/180
        func project(_ ra:Double,_ dec:Double)->SIMD2<Double>? {
            let h=engine.horizontal(date:moment,park:park,ra:ra,dec:dec)
            guard h.altitude > -2 else { return nil }
            let alt=h.altitude*Double.pi/180, dAz=(h.azimuth-facing)*Double.pi/180
            let k=2/(1+sin(centreAltitude)*sin(alt)+cos(centreAltitude)*cos(alt)*cos(dAz))
            return SIMD2(k*cos(alt)*sin(dAz), k*(cos(centreAltitude)*sin(alt)-sin(centreAltitude)*cos(alt)*cos(dAz)))
        }
        var faint:[Star]=[], middle:[Star]=[], bright:[Star]=[]
        for (index,star) in catalogue.enumerated() {
            guard let position=project(star.ra,star.dec) else { continue }
            let brightness=max(0.35,min(1,1.2-0.16*star.mag))
            let diameter=max(1.1,3.8-0.6*star.mag)
            let item=Star(position:position,diameter:diameter,brightness:brightness,colorIndex:max(-0.4,min(2,star.bv)),seed:Double(index%97)/97)
            if star.mag<2.2 { bright.append(item) } else if star.mag<3.6 { middle.append(item) } else { faint.append(item) }
        }
        // The galactic plane (b = 0) in J2000, from the north galactic pole (RA 192.859°, Dec +27.128°).
        let poleRA=192.85948*Double.pi/180, poleDec=27.12825*Double.pi/180, nodeL=122.93192*Double.pi/180
        var segments:[[GalaxyPoint]]=[], current:[GalaxyPoint]=[]
        for step in 0...180 {
            let l=Double(step)*2*Double.pi/180
            let dec=asin(cos(poleDec)*cos(nodeL-l))
            let ra=poleRA+atan2(sin(nodeL-l), -sin(poleDec)*cos(nodeL-l))
            // Brightest toward the core in Sagittarius (l = 0), faintest toward the anticentre.
            let brightness=0.35+0.65*pow((1+cos(l))/2,2)
            if let p=project(ra,dec) { current.append(GalaxyPoint(position:p,brightness:brightness)) }
            else if !current.isEmpty { segments.append(current); current=[] }
        }
        if !current.isEmpty { segments.append(current) }
        let result=Sky(id:key,faint:faint,middle:middle,bright:bright,galaxy:segments,dark:engine.solarAltitude(at:moment,park:park) < -12)
        cache[key]=result
        return result
    }
}
