import SwiftUI

/// The world's land under Nyx's maps: Natural Earth 1:50m (public domain), simplified for a phone
/// (`world-land.json`). Decoded once, off the main thread, into rings kept
/// both as degrees and as unit vectors, so a map is one cheap pass of dot products per layout.
/// A picture of coasts drawn faintly under the stars, never a land-or-sea test below about 10 km.
nonisolated final class WorldLand: Sendable {
    struct Ring: Sendable {
        /// (longitude, latitude) in degrees, closed (the last point repeats the first).
        let degrees: [SIMD2<Double>]
        let units: [SIMD3<Double>]
        /// A hole in the land: the Caspian Sea and the large lakes (an island in one is a land ring inside it).
        let lake: Bool
        /// The ring's middle direction and its angular radius around it (radians): a cheap cull.
        let middle: SIMD3<Double>
        let radius: Double
        /// Longitude and latitude bounds, for the point-in-ring test.
        let box: (minLon: Double, maxLon: Double, minLat: Double, maxLat: Double)
    }
    let rings: [Ring]
    var pointCount: Int { rings.reduce(0) { $0+$1.units.count } }
    init(rings: [Ring]) { self.rings=rings }

    static func load(_ url: URL?) -> WorldLand? {
        guard let url, let data=try? Data(contentsOf:url) else { return nil }
        return decode(data)
    }
    static func decode(_ data: Data) -> WorldLand? {
        struct File: Decodable { let regions: [String: [[[Double]]]] }
        guard let file=try? JSONDecoder().decode(File.self,from:data) else { return nil }
        let rings=["land","lakes"].flatMap { key in (file.regions[key] ?? []).compactMap { ring(from:$0,lake:key=="lakes") } }
        return rings.isEmpty ? nil : WorldLand(rings:rings)
    }
    static func ring(from raw: [[Double]], lake: Bool) -> Ring? {
        let degrees=raw.compactMap { $0.count>=2 ? SIMD2($0[0],$0[1]) : nil }
        guard degrees.count>=3 else { return nil }
        let units=degrees.map { GeoPoint(latitude:$0.y,longitude:$0.x).unit }
        let sum=units.reduce(SIMD3<Double>(repeating:0),+)
        let length=(sum*sum).sum().squareRoot()
        let middle=length>1e-12 ? sum/length : SIMD3<Double>(0,0,-1)
        let radius=units.map { acos(min(1,max(-1,($0*middle).sum()))) }.max() ?? .pi
        let lons=degrees.map(\.x), lats=degrees.map(\.y)
        return Ring(degrees:degrees,units:units,lake:lake,middle:middle,radius:radius,
                    box:(lons.min() ?? 0,lons.max() ?? 0,lats.min() ?? 0,lats.max() ?? 0))
    }
    /// True inside a ring, by a ray along the latitude (as on the longitude–latitude plane, where
    /// Natural Earth's rings are proper polygons: split at ±180°, Antarctica closed along −90°).
    static func contains(_ ring: Ring, latitude: Double, longitude: Double) -> Bool {
        guard (ring.box.minLon...ring.box.maxLon).contains(longitude), (ring.box.minLat...ring.box.maxLat).contains(latitude) else { return false }
        var inside=false, j=ring.degrees.count-1
        for i in ring.degrees.indices {
            let a=ring.degrees[i], b=ring.degrees[j]
            if (a.y>latitude) != (b.y>latitude), longitude<(b.x-a.x)*(latitude-a.y)/(b.y-a.y)+a.x { inside.toggle() }
            j=i
        }
        return inside
    }
    /// On land: inside an odd number of rings (land, less its lakes).
    func contains(_ point: GeoPoint) -> Bool {
        rings.reduce(false) { $0 != Self.contains($1,latitude:point.latitude,longitude:point.longitude) }
    }

    /// The land as drawn: `fill` (even-odd: land less its lakes), `coast` (the shoreline only: never
    /// Natural Earth's cuts along 180° or the South Pole's edge), and `edge`, the world's outline
    /// on Equal Earth (nil on a regional map).
    struct Shapes { var fill=Path(); var coast=Path(); var edge: Path? }
    /// Where the canvas sits in a view: `scale` points per canvas unit, offset by (dx, dy).
    struct Placement: Hashable, Sendable {
        let scale: Double, dx: Double, dy: Double
        init(scale: Double, dx: Double, dy: Double) { self.scale=scale; self.dx=dx; self.dy=dy }
        /// A frame fitted (centred, whole) into a view of `size`.
        init(_ frame: MapFrame, in size: CGSize) {
            let s=max(0.0001,min(size.width,size.height/frame.aspect))
            self.init(scale:s,dx:(size.width-s)/2,dy:(size.height-frame.aspect*s)/2)
        }
        func screen(_ canvas: CGPoint) -> CGPoint { CGPoint(x:dx+canvas.x*scale,y:dy+canvas.y*scale) }
    }
    /// Lambert draws nothing past this angle from its centre: a point beyond it is held on that
    /// circle at its own bearing (and the circle followed between two such points), so a coast
    /// running near the antipode never sends a line across the map. Maps never reach this far.
    static let horizon=150*GeoPoint.radian
    func shapes(_ frame: MapFrame, at placement: Placement) -> Shapes {
        let toScreen=frame.transform.concatenating(CGAffineTransform(a:placement.scale,b:0,c:0,d:placement.scale,tx:placement.dx,ty:placement.dy))
        switch frame.projection {
        case .azimuthal(let centre): return azimuthal(centre:centre,frame:frame,transform:toScreen)
        case .equalEarth(let meridian): return equalEarth(meridian:meridian,transform:toScreen)
        }
    }
    /// An edge Natural Earth cut rather than a shore: along ±180° or along the South Pole.
    private static func isCut(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Bool {
        (abs(a.x)>=179.99 && abs(b.x)>=179.99 && (a.x>0)==(b.x>0)) || (a.y <= -89.99 && b.y <= -89.99)
    }
    private static func addCoast(_ path: inout Path, ring: Ring, points: [CGPoint], kept: [Int]) {
        // `kept[i]`: the index in `points` of the ring's ith point (arcs between held points add more).
        var drawing=false
        for i in 1..<ring.degrees.count {
            if isCut(ring.degrees[i-1],ring.degrees[i]) { drawing=false; continue }
            if !drawing { path.move(to:points[kept[i-1]]); drawing=true }
            for k in (kept[i-1]+1)...kept[i] { path.addLine(to:points[k]) }
        }
    }
    private func azimuthal(centre: GeoPoint, frame: MapFrame, transform: CGAffineTransform) -> Shapes {
        let projector=frame.projector, up=centre.unit
        let horizon=Self.horizon, cosHorizon=cos(horizon), rim=2*sin(horizon/2)
        let reach=min(horizon,frame.reach+5*GeoPoint.radian)
        let antipode=centre.antipode
        var shapes=Shapes(), aroundAntipode=0
        for ring in rings {
            // A ring wholly beyond the view's corners cannot touch it.
            if acos(min(1,max(-1,(ring.middle*up).sum())))-ring.radius>reach { continue }
            var points:[CGPoint]=[], kept:[Int]=[], held:Double?=nil, inside=0
            points.reserveCapacity(ring.units.count); kept.reserveCapacity(ring.units.count)
            for v in ring.units {
                let local=projector.local(unit:v)
                if local.x>=cosHorizon {
                    let k=(2/(1+local.x)).squareRoot()
                    points.append(CGPoint(x:k*local.y,y:k*local.z).applying(transform))
                    held=nil; inside+=1
                } else {
                    let bearing=atan2(local.y,local.z)
                    if let from=held {
                        let turn=atan2(sin(bearing-from),cos(bearing-from)), steps=Int(abs(turn)/0.1)
                        if steps>0 { for s in 1...steps { let b=from+turn*Double(s)/Double(steps+1); points.append(CGPoint(x:rim*sin(b),y:rim*cos(b)).applying(transform)) } }
                    }
                    points.append(CGPoint(x:rim*sin(bearing),y:rim*cos(bearing)).applying(transform))
                    held=bearing
                }
                kept.append(points.count-1)
            }
            guard inside>0 else { continue }
            shapes.fill.addLines(points); shapes.fill.closeSubpath()
            Self.addCoast(&shapes.coast,ring:ring,points:points,kept:kept)
            if Self.contains(ring,latitude:antipode.latitude,longitude:antipode.longitude) { aroundAntipode+=1 }
        }
        // A ring around the antipode holds the land beyond it, not within: an even-odd fill with the
        // horizon added draws the land between the coast and the horizon.
        if aroundAntipode%2==1 {
            shapes.fill.addEllipse(in:CGRect(x:-rim,y:-rim,width:2*rim,height:2*rim).applying(transform))
        }
        return shapes
    }
    private func equalEarth(meridian: Double, transform: CGAffineTransform) -> Shapes {
        var shapes=Shapes()
        let λ0=meridian, radian=GeoPoint.radian
        for ring in rings {
            // Unwrapped from the meridian, following the ring, so a ring across the map's seam runs
            // on past it (and is drawn again from the other side) and a ring around a pole ends a
            // full turn from where it began (and is closed along the pole).
            var dλ:[Double]=[], previous=ring.degrees[0].x
            dλ.reserveCapacity(ring.degrees.count)
            var run=GeoPoint.wrapped(previous-λ0)
            for p in ring.degrees {
                run+=GeoPoint.wrapped(p.x-previous); previous=p.x
                dλ.append(run)
            }
            let turn=(dλ.last ?? 0)-(dλ.first ?? 0)
            let pole=abs(turn)>180 ? (ring.degrees.map(\.y).reduce(0,+)<0 ? -90.0 : 90.0) : nil
            let low=dλ.min() ?? 0, high=dλ.max() ?? 0
            for shift in [-360.0,0,360] where low+shift<180 && high+shift > -180 {
                var points=zip(dλ,ring.degrees).map { WorldProjection.equalEarth(dλ:($0+shift)*radian,φ:$1.y*radian).applying(transform) }
                let kept=Array(points.indices)
                Self.addCoast(&shapes.coast,ring:ring,points:points,kept:kept)
                if let pole, let last=dλ.last, let first=dλ.first {
                    points.append(WorldProjection.equalEarth(dλ:(last+shift)*radian,φ:pole*radian).applying(transform))
                    points.append(WorldProjection.equalEarth(dλ:(first+shift)*radian,φ:pole*radian).applying(transform))
                }
                shapes.fill.addLines(points); shapes.fill.closeSubpath()
            }
        }
        var edge=Path()
        edge.addLines(WorldProjection.equalEarthOutline().map { $0.applying(transform) }); edge.closeSubpath()
        shapes.edge=edge
        return shapes
    }
}

/// The land, loaded once for the whole app and drawn from a small cache of projected shapes: a
/// map projects its 29,000 points when its frame or size changes, never per frame of motion.
@MainActor @Observable final class WorldLandStore {
    static let shared=WorldLandStore()
    /// Nil until loaded; maps draw their places at once and the land arrives under them.
    private(set) var land: WorldLand?
    @ObservationIgnored private var loading: Task<WorldLand?,Never>?
    nonisolated private struct Key: Hashable { let frame: MapFrame; let placement: WorldLand.Placement }
    @ObservationIgnored private var cache: [Key:WorldLand.Shapes]=[:]
    @ObservationIgnored private var recent: [Key]=[]
    /// Decodes `world-land.json` off the main thread the first time any map asks.
    @discardableResult func load() async -> WorldLand? {
        if let land { return land }
        let task=loading ?? Task.detached(priority:.userInitiated) { WorldLand.load(Bundle.main.url(forResource:"world-land",withExtension:"json")) }
        loading=task
        let loaded=await task.value
        if land == nil { land=loaded }
        return land
    }
    func shapes(_ frame: MapFrame, at placement: WorldLand.Placement) -> WorldLand.Shapes? {
        guard let land else { return nil }
        let key=Key(frame:frame,placement:placement)
        if let kept=cache[key] { return kept }
        let made=land.shapes(frame,at:placement)
        cache[key]=made; recent.append(key)
        // A few maps on screen at once (the journal, a trip, the parks), each at a size or two.
        if recent.count>8 { cache[recent.removeFirst()]=nil }
        return made
    }
}

/// Draws the land under a map in Nyx's palette: a faint fill and a hairline coast, a little
/// stronger under night vision and Increase Contrast, so coasts read with night-adapted eyes.
@MainActor enum MapLand {
    static func draw(_ context: GraphicsContext, frame: MapFrame, in size: CGSize, palette: NyxPalette, fill: Double, coast: Double) {
        let placement=WorldLand.Placement(frame,in:size)
        guard let shapes=WorldLandStore.shared.shapes(frame,at:placement) else { return }
        var layer=context
        let canvas=CGRect(x:placement.dx,y:placement.dy,width:placement.scale,height:placement.scale*frame.aspect)
        layer.clip(to:Path(canvas))
        if let edge=shapes.edge {
            layer.stroke(edge,with:.color(palette.ink.opacity(coast*0.6)),style:StrokeStyle(lineWidth:0.5))
            layer.clip(to:edge)
        }
        let boost=palette.highContrast ? 2.0 : palette.nightVision ? 1.25 : 1
        if fill>0 { layer.fill(shapes.fill,with:.color(palette.ink.opacity(fill*boost)),style:FillStyle(eoFill:true)) }
        layer.stroke(shapes.coast,with:.color(palette.ink.opacity(min(0.6,coast*boost))),style:StrokeStyle(lineWidth:0.6,lineJoin:.round))
    }
}
