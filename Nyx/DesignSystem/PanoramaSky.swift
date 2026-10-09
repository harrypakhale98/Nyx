import SwiftUI

/// The sky over a park at one moment in altitude and azimuth (degrees): RealSky's bright-star
/// catalogue, a seeded field of fainter stars (denser along the Milky Way), the galactic plane,
/// the planets, the Moon, a shower's radiant and NASA's light domes. Kept per park and five-minute
/// slot, so the full-screen sky can turn to face any direction, and the Bortle figure can redraw
/// it at any class, without working out the astronomy again.
nonisolated struct HorizonSky: Sendable {
    struct Star: Sendable { let altitude: Double; let azimuth: Double; let magnitude: Double; let colorIndex: Double; let seed: Double }
    struct Point: Sendable { let altitude: Double; let azimuth: Double; let brightness: Double }
    struct Mark: Sendable, Identifiable { var id: String { name }; let altitude: Double; let azimuth: Double; let name: String; let magnitude: Double }
    struct Dome: Sendable { let bearing: Double; let intensity: Double; let halfWidth: Double }
    let id: String
    let moment: Date
    let stars: [Star]
    /// Stars fainter than the catalogue (magnitude 4.5 to 7.8), placed by a fixed seed: drawn only
    /// as far as a sky's limiting magnitude allows. Their pattern is an illustration, not a catalogue.
    let dust: [Star]
    let galaxy: [[Point]]
    /// The Milky Way's bright centre in Sagittarius, when it is above the horizon.
    let core: Point?
    let planets: [Mark]
    let radiant: Mark?
    let moon: Mark?
    let moonIllumination: Double
    let moonWaxing: Bool
    let domes: [Dome]
    let sunAltitude: Double
    /// The Sun at least 12° down: the Milky Way and light domes are drawn only then.
    var dark: Bool { sunAltitude < -12 }
}
@MainActor final class HorizonSkies {
    static let shared=HorizonSkies()
    private var cache:[String:HorizonSky]=[:]
    private var recent:[String]=[]
    private let capacity=48
    /// Galactic longitude and latitude (radians) to right ascension and declination (J2000).
    nonisolated static func equatorial(l:Double,b:Double)->(ra:Double,dec:Double) {
        let rad=Double.pi/180, poleRA=192.85948*rad, poleDec=27.12825*rad, nodeL=122.93192*rad
        let dec=asin(sin(b)*sin(poleDec)+cos(b)*cos(poleDec)*cos(nodeL-l))
        let ra=poleRA+atan2(cos(b)*sin(nodeL-l),sin(b)*cos(poleDec)-cos(b)*sin(poleDec)*cos(nodeL-l))
        return (ra,dec)
    }
    /// 2,600 faint stars from a fixed seed: half spread evenly over the sky, half within about 12°
    /// of the galactic plane, magnitudes weighted toward the faint end as real star counts are.
    private lazy var dustField:[(ra:Double,dec:Double,mag:Double)]={
        var state:UInt64=0x9E3779B97F4A7C15
        func next()->Double { state=state &* 6364136223846793005 &+ 1442695040888963407; return Double(state>>11)/Double(1<<53) }
        return (0..<2600).map { index in
            let l=next()*2*Double.pi
            let b:Double
            if index%2==0 { b=asin(2*next()-1) }
            else { let u=max(1e-9,next()), v=next(); b=12*Double.pi/180*sqrt(-2*log(u))*cos(2*Double.pi*v) }
            let place=Self.equatorial(l:l,b:max(-Double.pi/2,min(Double.pi/2,b)))
            return (place.ra,place.dec,4.5+3.3*pow(next(),0.45))
        }
    }()
    func sky(park:Park,night:Date,at instant:Date)->HorizonSky {
        let slot=Date(timeIntervalSince1970:(instant.timeIntervalSince1970/300).rounded(.down)*300)
        let key="\(park.id)-\(Int(slot.timeIntervalSince1970))"
        if let cached=cache[key] { return cached }
        let engine=AstronomyEngine(), conditions=engine.conditions(for:park,on:park.evening(night)), rad=Double.pi/180
        func horizontal(_ ra:Double,_ dec:Double)->(altitude:Double,azimuth:Double) { engine.horizontal(date:slot,park:park,ra:ra,dec:dec) }
        var stars:[HorizonSky.Star]=[]
        for (index,star) in SkyProjection.shared.stars(brighterThan:9).enumerated() {
            let h=horizontal(star.ra,star.dec)
            guard h.altitude > -2 else { continue }
            stars.append(.init(altitude:h.altitude,azimuth:h.azimuth,magnitude:star.mag,colorIndex:max(-0.4,min(2,star.bv)),seed:Double(index%97)/97))
        }
        var dust:[HorizonSky.Star]=[]
        for (index,star) in dustField.enumerated() {
            let h=horizontal(star.ra,star.dec)
            guard h.altitude > -1 else { continue }
            dust.append(.init(altitude:h.altitude,azimuth:h.azimuth,magnitude:star.mag,colorIndex:0.6,seed:Double(index%89)/89))
        }
        // The galactic plane, brightest toward the core (l = 0), faintest toward the anticentre.
        var segments:[[HorizonSky.Point]]=[], current:[HorizonSky.Point]=[]
        var core:HorizonSky.Point?
        for step in 0...180 {
            let l=Double(step)*2*rad
            let place=Self.equatorial(l:l,b:0)
            let h=horizontal(place.ra,place.dec)
            let point=HorizonSky.Point(altitude:h.altitude,azimuth:h.azimuth,brightness:0.35+0.65*pow((1+cos(l))/2,2))
            if step==0 && h.altitude>0 { core=point }
            if h.altitude > -10 { current.append(point) } else if !current.isEmpty { segments.append(current); current=[] }
        }
        if !current.isEmpty { segments.append(current) }
        let sun=engine.solarAltitude(at:slot,park:park)
        var planets:[HorizonSky.Mark]=[]
        let almanac=SkyAlmanac()
        for planet in SkyAlmanac.Planet.allCases {
            let position=almanac.position(of:planet,at:slot), h=horizontal(position.ra,position.dec)
            if h.altitude>0 { planets.append(.init(altitude:h.altitude,azimuth:h.azimuth,name:planet.name,magnitude:position.magnitude)) }
        }
        var radiant:HorizonSky.Mark?
        if let shower=WhatsUp.Events(park:park,sky:conditions).shower, shower.hourlyRate>=5 || shower.isPeakNight {
            let h=horizontal(shower.shower.radiantRA*rad,shower.shower.radiantDec*rad)
            if h.altitude>0 { radiant=HorizonSky.Mark(altitude:h.altitude,azimuth:h.azimuth,name:String(localized:"\(shower.shower.localizedName) radiant"),magnitude:0) }
        }
        let lunar=engine.equatorial(of:.moon,at:slot), m=horizontal(lunar.ra,lunar.dec), phase=engine.moonPhase(at:slot)
        let moon:HorizonSky.Mark? = m.altitude > -0.5 ? .init(altitude:m.altitude,azimuth:m.azimuth,name:String(localized:"Moon"),magnitude:-12) : nil
        let domes=SkyProjection.shared.lightSources(park).compactMap { source -> HorizonSky.Dome? in
            let amount=source.share*source.glow
            guard amount>=0.01 else { return nil }
            return .init(bearing:source.bearing,intensity:min(1,(amount/4).squareRoot()),halfWidth:10+20*source.share)
        }
        let sky=HorizonSky(id:key,moment:slot,stars:stars,dust:dust,galaxy:segments,core:core,planets:planets,radiant:radiant,moon:moon,
                           moonIllumination:phase.illumination,moonWaxing:phase.waxing,domes:domes,sunAltitude:sun)
        cache[key]=sky
        recent.append(key)
        if recent.count>capacity { cache[recent.removeFirst()]=nil }
        return sky
    }
}

/// How light pollution changes what an eye can see, class by class (Bortle 2001, in round
/// numbers): the faintest star, how much of the Milky Way survives, and how high and bright the
/// glow climbs from the horizon. For drawing an illustration; Nyx never measures a sky.
nonisolated enum BortleScale {
    static let classes=1...9
    /// Faintest naked-eye star, for a class between 1 and 9 (fractions blend neighbours).
    static func limitingMagnitude(_ bortle:Double)->Double { 7.8-0.475*(clamped(bortle)-1) }
    /// How much of the Milky Way's light survives: full at 1, structureless by 5, gone from 7.
    static func milkyWay(_ bortle:Double)->Double {
        let b=clamped(bortle)
        return b<=7 ? max(0,pow((7-b)/6,1.3)) : 0
    }
    /// How high the glow climbs above the horizon, in degrees.
    static func glowHeight(_ bortle:Double)->Double { let b=clamped(bortle); return b<=1 ? 0 : min(90,pow(b-1,1.55)*3.6) }
    /// How bright that glow is at the horizon, 0…1.
    static func glowStrength(_ bortle:Double)->Double { let b=clamped(bortle); return b<=1 ? 0 : min(0.5,0.035*(b-1)+0.004*pow(b-1,2)) }
    /// A lift of the whole sky toward grey, from about class 6.
    static func skyLift(_ bortle:Double)->Double { max(0,(clamped(bortle)-5.5)*0.03) }
    static func clamped(_ bortle:Double)->Double { min(9,max(1,bortle)) }
    static func name(_ bortle:Int)->String {
        switch bortle {
        case ...1: String(localized:"Excellent dark-sky site")
        case 2: String(localized:"Typical truly dark site")
        case 3: String(localized:"Rural sky")
        case 4: String(localized:"Rural to suburban transition")
        case 5: String(localized:"Suburban sky")
        case 6: String(localized:"Bright suburban sky")
        case 7: String(localized:"Suburban to urban transition")
        case 8: String(localized:"City sky")
        default: String(localized:"Inner-city sky")
        }
    }
    /// One thing you can check with your own eyes, for the journal's observed class.
    static func cue(_ bortle:Int)->String {
        switch bortle {
        case ...1: String(localized:"The Milky Way is bright enough to cast faint shadows, and the zodiacal light is easy to see.")
        case 2: String(localized:"The summer Milky Way shows fine structure, and clouds look like black holes in the stars.")
        case 3: String(localized:"Some light glows low on the horizon, but the Milky Way still looks complex overhead.")
        case 4: String(localized:"Light domes rise in several directions; the Milky Way fades toward the horizon.")
        case 5: String(localized:"The Milky Way is faint overhead and gone near the horizon.")
        case 6: String(localized:"The Milky Way shows only overhead, if at all, and the sky glows gray well above the horizon.")
        case 7: String(localized:"No Milky Way; the whole sky has a gray-white glow.")
        case 8: String(localized:"The sky glows white or orange, bright enough to read by.")
        default: String(localized:"Only the Moon, the planets and a few bright stars remain.")
        }
    }
}

/// What the sky canvas draws, and how.
nonisolated struct PanoramaOptions: Equatable, Sendable {
    /// The azimuth at the centre of the view, degrees from north.
    var facing: Double
    /// The altitude at the centre of the view, degrees.
    var centreAltitude: Double=40
    /// Stereographic units across the view's height: larger is wider-angle.
    var span: Double=2.6
    var labels=true
    /// A Bortle class (1…9, fractions blend) for how much light pollution to draw; nil draws the
    /// geometry alone.
    var bortle: Double?=nil
    var showsMoon=true
    var nightVision=false
    /// How far eyes have adapted to the dark, 0…1. Below 1 the faintest stars are held back (only
    /// the brightest show near 0) and the Milky Way gathers last, from 0.7. Planets, the Moon and
    /// the light domes are drawn whole at any value. An illustration of the order stars arrive in,
    /// not of its timing: real adaptation takes 20 to 30 minutes.
    var adaptation: Double=1
}
/// Altitude and azimuth to a point on the view: a stereographic projection around the centre.
nonisolated struct SkyFrame: Sendable {
    let facing: Double
    let centre: Double
    let size: CGSize
    let scale: Double
    init(options:PanoramaOptions,size:CGSize) {
        facing=options.facing; centre=options.centreAltitude; self.size=size; scale=size.height/options.span
    }
    func point(_ altitude:Double,_ azimuth:Double)->CGPoint? {
        let rad=Double.pi/180, a=altitude*rad, c=centre*rad, d=(azimuth-facing)*rad
        let denominator=1+sin(c)*sin(a)+cos(c)*cos(a)*cos(d)
        guard denominator>0.12 else { return nil }
        let k=2/denominator
        return CGPoint(x:size.width/2+k*cos(a)*sin(d)*scale,y:size.height*0.5-k*(cos(c)*sin(a)-sin(c)*cos(a)*cos(d))*scale)
    }
    /// Degrees of azimuth a horizontal drag of one point turns, near the middle of the view.
    var degreesPerPoint: Double { 180/Double.pi/scale }
    func visible(_ p:CGPoint,margin:Double=8)->Bool { p.x > -margin && p.x<size.width+margin && p.y > -margin && p.y<size.height+margin }
}

/// The sky drawn: background and twilight, light pollution, light domes, the Milky Way, faint and
/// bright stars, planets, the Moon and a radiant, then the ground, compass points and names.
struct PanoramaCanvas: View {
    @Environment(\.nyx) private var palette
    let sky: HorizonSky
    var options: PanoramaOptions
    var body: some View {
        let ink=palette.ink
        Canvas { context,size in PanoramaCanvas.draw(sky:sky,options:options,ink:ink,in:&context,size:size) }
            .background(Color.black)
            .accessibilityIgnoresInvertColors()
    }
    static func draw(sky:HorizonSky,options:PanoramaOptions,ink:Color,in context:inout GraphicsContext,size:CGSize) {
        let frame=SkyFrame(options:options,size:size)
        let bortle=options.bortle
        // Twilight and moonlight wash out faint stars, as light pollution does.
        let twilight=max(0,min(1,(sky.sunAltitude+18)/12))
        let moonWash=options.showsMoon ? (sky.moon.map { max(0,min(1,$0.altitude/25)) } ?? 0)*sky.moonIllumination : 0
        var limit=(bortle.map(BortleScale.limitingMagnitude) ?? 6.6)-2.2*moonWash-4*twilight
        let adaptation=max(0,min(1,options.adaptation))
        limit=PanoramaCanvas.adaptedLimit(limit,adaptation:adaptation)
        let milkyWay=(bortle.map(BortleScale.milkyWay) ?? 0.85)*(sky.dark ? 1 : 0)*(1-0.85*moonWash)*PanoramaCanvas.milkyWayGathered(adaptation)
        let horizonY=frame.point(0,options.facing)?.y ?? size.height*0.8
        // The sky itself: near black, lifted by twilight, moonlight and city light toward the horizon.
        let lift=0.08*twilight+0.06*moonWash+(bortle.map(BortleScale.skyLift) ?? 0)
        let zenith=Color(red:0.004+lift*0.5,green:0.008+lift*0.6,blue:0.03+lift*0.9)
        let low=Color(red:0.02+lift*0.9,green:0.025+lift*0.9,blue:0.07+lift*1.1)
        context.fill(Path(CGRect(origin:.zero,size:size)),with:.linearGradient(Gradient(colors:[zenith,low]),startPoint:.zero,endPoint:CGPoint(x:0,y:horizonY)))
        // Light pollution: a warm glow climbing from the whole horizon.
        if let bortle, BortleScale.glowStrength(bortle)>0 {
            let top=frame.point(BortleScale.glowHeight(bortle),options.facing)?.y ?? 0
            let warm=Color(red:1,green:0.72,blue:0.45)
            let strength=BortleScale.glowStrength(bortle)
            context.fill(Path(CGRect(x:0,y:min(top,horizonY-1),width:size.width,height:max(1,horizonY-min(top,horizonY-1)))),
                         with:.linearGradient(Gradient(stops:[.init(color:warm.opacity(0),location:0),.init(color:warm.opacity(strength*0.45),location:0.6),.init(color:warm.opacity(strength),location:1)]),
                                              startPoint:CGPoint(x:0,y:top),endPoint:CGPoint(x:0,y:horizonY)))
        }
        // NASA's light domes at their bearings, when the sky is dark enough for them to show.
        if sky.dark {
            let warm=Color(red:1,green:0.64,blue:0.36)
            for dome in sky.domes {
                guard let base=frame.point(0,dome.bearing), let top=frame.point(14,dome.bearing), let left=frame.point(0,dome.bearing-dome.halfWidth), let right=frame.point(0,dome.bearing+dome.halfWidth) else { continue }
                let rx=max(2,hypot(right.x-left.x,right.y-left.y)/2), ry=max(2,hypot(top.x-base.x,top.y-base.y))
                guard base.x > -rx, base.x<size.width+rx else { continue }
                let peak=0.06+0.24*dome.intensity
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius:max(2,ry*0.08)))
                    layer.translateBy(x:base.x,y:base.y)
                    layer.scaleBy(x:rx/ry,y:1)
                    layer.fill(Path(ellipseIn:CGRect(x:-ry,y:-ry,width:ry*2,height:ry*2)),with:.radialGradient(Gradient(stops:[.init(color:warm.opacity(peak),location:0),.init(color:warm.opacity(peak*0.4),location:0.45),.init(color:warm.opacity(0),location:1)]),center:.zero,startRadius:0,endRadius:ry))
                }
            }
        }
        // The Milky Way: a broad soft band and a brighter spine, brightest toward the core.
        if milkyWay>0.01 {
            let band=frame.scale*0.34
            for (width,blur,strength) in [(band,band*0.22,0.10),(band*0.42,band*0.1,0.12)] {
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius:blur))
                    for segment in sky.galaxy {
                        var path=Path(), drawing=false, total=0.0, count=0.0
                        for point in segment {
                            guard let p=frame.point(point.altitude,point.azimuth), abs(p.x-size.width/2)<size.width*2 else { drawing=false; continue }
                            if drawing { path.addLine(to:p) } else { path.move(to:p); drawing=true }
                            total+=point.brightness; count+=1
                        }
                        guard count>1 else { continue }
                        glow.stroke(path,with:.color(ink.opacity(strength*milkyWay*total/count*1.6)),style:StrokeStyle(lineWidth:width,lineCap:.round,lineJoin:.round))
                    }
                }
            }
            if let core=sky.core, let p=frame.point(core.altitude,core.azimuth) {
                let r=frame.scale*0.2
                context.fill(Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:2*r,height:2*r)),with:.radialGradient(Gradient(colors:[ink.opacity(0.2*milkyWay),ink.opacity(0)]),center:p,startRadius:0,endRadius:r))
            }
        }
        // Faint stars, as far as the sky's limiting magnitude reaches; dimmer as they near it.
        // A brighter sky also lowers every star's contrast against it.
        let contrast=1-0.07*((bortle ?? 3)-1)
        for star in sky.dust where star.magnitude<limit {
            guard let p=frame.point(star.altitude,star.azimuth), frame.visible(p) else { continue }
            let fade=min(1,(limit-star.magnitude)/0.9)*contrast
            let d=0.8+0.6*(1-(star.magnitude-4.5)/3.3)
            context.fill(Path(ellipseIn:CGRect(x:p.x-d/2,y:p.y-d/2,width:d,height:d)),with:.color(ink.opacity(0.5*fade)))
        }
        for star in sky.stars where star.magnitude<limit {
            guard let p=frame.point(star.altitude,star.azimuth), frame.visible(p) else { continue }
            let fade=min(1,max(0,limit-star.magnitude))*contrast
            let d=max(1.1,3.9-0.6*star.magnitude)
            let brightness=max(0.4,min(1,1.25-0.15*star.magnitude))*fade
            if star.magnitude<1.2 {
                let r=d*2.4
                context.fill(Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:2*r,height:2*r)),with:.radialGradient(Gradient(colors:[tint(star.colorIndex,ink:ink).opacity(0.25*fade),.clear]),center:p,startRadius:0,endRadius:r))
            }
            context.fill(Path(ellipseIn:CGRect(x:p.x-d/2,y:p.y-d/2,width:d,height:d)),with:.color(tint(star.colorIndex,ink:ink).opacity(brightness)))
        }
        // Planets: warm points as bright as the brightest stars.
        let warm=Color(red:1,green:0.86,blue:0.66).mix(with:ink,by:0.3)
        for planet in sky.planets {
            guard let p=frame.point(planet.altitude,planet.azimuth), frame.visible(p) else { continue }
            let d=max(3.2,min(5.4,4.4-0.4*planet.magnitude))
            context.fill(Path(ellipseIn:CGRect(x:p.x-d*1.6,y:p.y-d*1.6,width:d*3.2,height:d*3.2)),with:.radialGradient(Gradient(colors:[warm.opacity(0.25),warm.opacity(0)]),center:p,startRadius:0,endRadius:d*1.6))
            context.fill(Path(ellipseIn:CGRect(x:p.x-d/2,y:p.y-d/2,width:d,height:d)),with:.color(warm))
        }
        if let radiant=sky.radiant, sky.dark, let p=frame.point(radiant.altitude,radiant.azimuth) {
            var rays=Path()
            for i in 0..<10 {
                let angle=Double(i)*Double.pi/5+0.3, inner=7.0, outer=inner+(i%2==0 ? 13 : 8)
                rays.move(to:CGPoint(x:p.x+inner*cos(angle),y:p.y+inner*sin(angle)))
                rays.addLine(to:CGPoint(x:p.x+outer*cos(angle),y:p.y+outer*sin(angle)))
            }
            context.stroke(rays,with:.color(ink.opacity(0.55)),style:StrokeStyle(lineWidth:0.8,lineCap:.round))
        }
        if options.showsMoon, let moon=sky.moon, let p=frame.point(moon.altitude,moon.azimuth), frame.visible(p,margin:30) {
            let r=7.0, lit=sky.moonIllumination
            context.fill(Path(ellipseIn:CGRect(x:p.x-r*5,y:p.y-r*5,width:r*10,height:r*10)),with:.radialGradient(Gradient(colors:[ink.opacity(0.18*lit),ink.opacity(0)]),center:p,startRadius:r,endRadius:r*5))
            context.fill(Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:2*r,height:2*r)),with:.color(Color(white:0.12)))
            context.fill(MoonDisc.litPath(center:p,radius:r,illumination:lit,litRight:sky.moonWaxing,samples:32),with:.color(ink))
        }
        // The ground: everything below the horizon, dark, with a faint edge.
        var ground=Path(), edge=Path(), started=false
        for step in stride(from:-110.0,through:110,by:4) {
            guard let p=frame.point(0,options.facing+step) else { continue }
            if started { ground.addLine(to:p); edge.addLine(to:p) } else { ground.move(to:CGPoint(x:p.x,y:size.height+10)); ground.addLine(to:p); edge.move(to:p); started=true }
        }
        if started, let last=ground.currentPoint {
            ground.addLine(to:CGPoint(x:last.x,y:size.height+10)); ground.closeSubpath()
            context.fill(ground,with:.color(Color(red:0.012,green:0.012,blue:0.02)))
            context.stroke(edge,with:.color(ink.opacity(0.22)),lineWidth:0.6)
        }
        guard options.labels else { return }
        // Compass points just under the horizon.
        let points=[(0.0,String(localized:"N")),(45,String(localized:"NE")),(90,String(localized:"E")),(135,String(localized:"SE")),(180,String(localized:"S")),(225,String(localized:"SW")),(270,String(localized:"W")),(315,String(localized:"NW"))]
        for (azimuth,name) in points {
            guard let p=frame.point(0,azimuth), p.x>16, p.x<size.width-16 else { continue }
            let text=context.resolve(Text(name).font(.system(azimuth.truncatingRemainder(dividingBy:90)==0 ? .callout : .caption,design:.serif).weight(.semibold)).foregroundStyle(ink.opacity(azimuth.truncatingRemainder(dividingBy:90)==0 ? 0.9 : 0.6)))
            context.draw(text,at:CGPoint(x:p.x,y:min(size.height-14,p.y+16)))
        }
        // Names, brightest first, never over one another.
        var taken:[CGRect]=[]
        func label(_ name:String,at p:CGPoint,gap:Double) {
            let text=context.resolve(Text(name).font(.system(.footnote,design:.serif)).foregroundStyle(ink.opacity(0.92)))
            let s=text.measure(in:size)
            for spot in [CGPoint(x:p.x,y:p.y-gap),CGPoint(x:p.x,y:p.y+gap),CGPoint(x:p.x+gap/2+s.width/2+4,y:p.y)] {
                let rect=CGRect(x:spot.x-s.width/2,y:spot.y-s.height/2,width:s.width,height:s.height).insetBy(dx:-3,dy:-1)
                guard rect.minX>=4, rect.maxX<=size.width-4, rect.minY>=4, rect.maxY<=horizonY, !taken.contains(where:{ $0.intersects(rect) }) else { continue }
                taken.append(rect)
                context.drawLayer { layer in layer.addFilter(.shadow(color:.black,radius:3)); layer.draw(text,at:spot) }
                return
            }
        }
        if options.showsMoon, let moon=sky.moon, let p=frame.point(moon.altitude,moon.azimuth), frame.visible(p) { label(moon.name,at:p,gap:18) }
        for planet in sky.planets.sorted(by:{ $0.magnitude<$1.magnitude }) { if let p=frame.point(planet.altitude,planet.azimuth), frame.visible(p) { label(planet.name,at:p,gap:14) } }
        if milkyWay>0.15, let core=sky.core, let p=frame.point(core.altitude,core.azimuth), frame.visible(p) { label(String(localized:"Milky Way core"),at:p,gap:frame.scale*0.12) }
        if let radiant=sky.radiant, sky.dark, let p=frame.point(radiant.altitude,radiant.azimuth), frame.visible(p) { label(radiant.name,at:p,gap:24) }
    }
    /// The limiting magnitude while eyes adapt: at 0 nothing fainter than magnitude −1.5 (no star
    /// at all), rising to the sky's own limit at 1, so the brightest stars arrive first.
    nonisolated static func adaptedLimit(_ limit:Double,adaptation:Double)->Double {
        min(limit,-1.5+max(0,min(1,adaptation))*(limit+1.5))
    }
    /// How much of the Milky Way shows while eyes adapt: none until 0.7, all of it at 1 (smoothstep).
    nonisolated static func milkyWayGathered(_ adaptation:Double)->Double {
        let t=max(0,min(1,(adaptation-0.7)/0.3))
        return t*t*(3-2*t)
    }
    /// B−V colour index to a gentle warm or cool tint over starlight (Ballesteros).
    static func tint(_ colorIndex:Double,ink:Color)->Color {
        let temperature=4600*(1/(0.92*colorIndex+1.7)+1/(0.92*colorIndex+0.62))
        let warmth=max(-1,min(1,(6500-temperature)/3500))
        return warmth>0 ? Color(red:1,green:1-0.18*warmth,blue:1-0.42*warmth).mix(with:ink,by:0.35)
            : Color(red:1+0.25*warmth,green:1+0.1*warmth,blue:1).mix(with:ink,by:0.35)
    }
    /// What is up and where, for VoiceOver: "Facing south at 11:40 PM. Jupiter, high in the southeast. …"
    static func summary(sky:HorizonSky,facing:Double,park:Park,bortle:Double?)->String {
        var lines=[String(localized:"Facing \(Compass.name(facing)), \(park.time(sky.moment)).")]
        if sky.sunAltitude > -6 { lines.append(String(localized:"The Sun is barely down; the sky is still bright.")) }
        else if !sky.dark { lines.append(String(localized:"The sky is still in twilight.")) }
        func place(_ mark:(altitude:Double,azimuth:Double))->String {
            mark.altitude>=50 ? String(localized:"high in the \(Compass.name(mark.azimuth))")
                : mark.altitude<15 ? String(localized:"low in the \(Compass.name(mark.azimuth))")
                : String(localized:"partway up in the \(Compass.name(mark.azimuth))")
        }
        if let moon=sky.moon, moon.altitude>0 { lines.append(String(localized:"The Moon, \(Int((sky.moonIllumination*100).rounded())) percent lit, \(place((moon.altitude,moon.azimuth))).")) }
        for planet in sky.planets.sorted(by:{ $0.magnitude<$1.magnitude }) { lines.append("\(planet.name), \(place((planet.altitude,planet.azimuth))).") }
        let milkyWay=(bortle.map(BortleScale.milkyWay) ?? 0.85)*(sky.dark ? 1 : 0)
        if milkyWay>0.15, let core=sky.core { lines.append(String(localized:"The Milky Way's core, \(place((core.altitude,core.azimuth))).")) }
        if let radiant=sky.radiant, sky.dark { lines.append("\(radiant.name), \(place((radiant.altitude,radiant.azimuth))).") }
        if sky.dark, !sky.domes.isEmpty {
            let toward=sky.domes.sorted { $0.intensity>$1.intensity }.prefix(3).map { Compass.name($0.bearing) }
            lines.append(String(localized:"Town light glows on the horizon toward the \(Array(Set(toward)).sorted().formatted(.list(type:.and))).")) 
        }
        return lines.joined(separator:" ")
    }
}
#Preview("Panorama • south at midnight") {
    let m=PlanModel()
    if let p=m.home {
        let night=m.night(p)
        let sky=HorizonSkies.shared.sky(park:p,night:night.id,at:night.sky.darkStart.map { $0.addingTimeInterval(3*3600) } ?? night.id)
        PanoramaCanvas(sky:sky,options:PanoramaOptions(facing:180,bortle:Double(p.bortleEstimate))).ignoresSafeArea()
    }
}
#Preview("Panorama • eyes adapting (0.45)") {
    let m=PlanModel()
    if let p=m.home {
        let night=m.night(p)
        let sky=HorizonSkies.shared.sky(park:p,night:night.id,at:night.sky.darkStart.map { $0.addingTimeInterval(3*3600) } ?? night.id)
        PanoramaCanvas(sky:sky,options:PanoramaOptions(facing:180,bortle:Double(p.bortleEstimate),adaptation:0.45)).ignoresSafeArea()
    }
}
#Preview("Panorama • Bortle 8") {
    let m=PlanModel()
    if let p=m.home {
        let night=m.night(p)
        let sky=HorizonSkies.shared.sky(park:p,night:night.id,at:night.sky.darkStart.map { $0.addingTimeInterval(3*3600) } ?? night.id)
        PanoramaCanvas(sky:sky,options:PanoramaOptions(facing:180,labels:false,bortle:8)).frame(height:300)
    }
}
