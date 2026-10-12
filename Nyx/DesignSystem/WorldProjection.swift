import Foundation
import CoreGraphics

/// A place on Earth, in degrees, as the maps draw it.
nonisolated struct GeoPoint: Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    init(latitude: Double, longitude: Double) { self.latitude=latitude; self.longitude=longitude }
    init(_ place: Park) { self.init(latitude:place.latitude,longitude:place.longitude) }
    /// The mean radius of Earth (IUGG), in kilometres.
    static let earthRadiusKm = 6371.0088
    static let radian = Double.pi/180
    /// The unit vector: x toward 0° N 0° E, y toward 0° N 90° E, z toward the North Pole.
    var unit: SIMD3<Double> {
        let φ=latitude*Self.radian, λ=longitude*Self.radian
        return SIMD3(cos(φ)*cos(λ),cos(φ)*sin(λ),sin(φ))
    }
    init(unit v: SIMD3<Double>) {
        let flat=(v.x*v.x+v.y*v.y).squareRoot()
        self.init(latitude:atan2(v.z,flat)/Self.radian,longitude:flat<1e-15 ? 0 : atan2(v.y,v.x)/Self.radian)
    }
    /// The point on the far side of Earth.
    var antipode: GeoPoint { GeoPoint(latitude:-latitude,longitude:Self.wrapped(longitude+180)) }
    /// The angle between two places seen from Earth's centre, in radians (atan2, so exact near 0 and π).
    func angle(to other: GeoPoint) -> Double {
        let a=unit, b=other.unit
        let cross=SIMD3(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x)
        return atan2((cross*cross).sum().squareRoot(),(a*b).sum())
    }
    /// A longitude in (−180°, 180°].
    static func wrapped(_ longitude: Double) -> Double {
        var λ=longitude.truncatingRemainder(dividingBy:360)
        if λ <= -180 { λ+=360 } else if λ>180 { λ-=360 }
        return λ
    }
    /// The middle of some places: their mean direction from Earth's centre. Nil for none; the first
    /// place when they cancel out (two antipodes).
    static func middle(of points: [GeoPoint]) -> GeoPoint? {
        guard let first=points.first else { return nil }
        let sum=points.reduce(SIMD3<Double>(repeating:0)) { $0+$1.unit }
        return (sum*sum).sum()<1e-18 ? first : GeoPoint(unit:sum)
    }
}

/// The two equal-area projections Nyx draws Earth with (Research/world-map.md), on a unit sphere,
/// with x east and y north on the plane:
/// - **Lambert azimuthal equal-area**, centred on a place: every regional map. Areas are true
///   everywhere, shapes near-true for a few thousand kilometres, and its only seam is the antipode.
/// - **Equal Earth** (Šavrič, Patterson and Jenny, 2019): the whole world.
nonisolated enum WorldProjection: Hashable, Sendable {
    case azimuthal(GeoPoint)
    case equalEarth(centralMeridian: Double)
    func project(_ point: GeoPoint) -> CGPoint? { Projector(self).project(point) }
    func inverse(_ point: CGPoint) -> GeoPoint? { Projector(self).inverse(point) }
    /// Lambert: the plane radius of the circle `meters` from the centre (ρ = 2 sin(r / 2R)).
    static func azimuthalRadius(meters: Double) -> Double { 2*sin(min(Double.pi,max(0,meters/1000/GeoPoint.earthRadiusKm))/2) }
    /// Lambert: the angle from the centre (radians) at plane radius ρ, the radius's inverse.
    static func azimuthalAngle(radius ρ: Double) -> Double { 2*asin(min(1,max(0,ρ/2))) }

    // Equal Earth's coefficients.
    static let a1=1.340264, a2 = -0.081106, a3=0.000893, a4=0.003796
    private static let m=3.0.squareRoot()/2
    /// Equal Earth at a longitude `dλ` radians from the central meridian (not wrapped, so a ring
    /// drawn across the seam can run past it and be clipped) and latitude `φ` radians.
    static func equalEarth(dλ: Double, φ: Double) -> CGPoint {
        let θ=asin(m*sin(φ)), θ2=θ*θ, θ6=θ2*θ2*θ2
        let x=dλ*cos(θ)/(m*(a1+3*a2*θ2+θ6*(7*a3+9*a4*θ2)))
        let y=θ*(a1+a2*θ2+θ6*(a3+a4*θ2))
        return CGPoint(x:x,y:y)
    }
    /// Equal Earth's whole outline (the ±180° meridians, pole lines between them), clockwise from
    /// the top left: the world's edge, and the clip for rings drawn across the seam.
    static func equalEarthOutline(steps: Int = 90) -> [CGPoint] {
        let n=max(2,steps)
        let east=(0...n).map { i in equalEarth(dλ:.pi,φ:Double.pi/2-Double.pi*Double(i)/Double(n)) }
        let west=(0...n).map { i in equalEarth(dλ:-.pi,φ:-Double.pi/2+Double.pi*Double(i)/Double(n)) }
        return [equalEarth(dλ:-.pi,φ:.pi/2)]+east+west
    }
    /// The plane rectangle Equal Earth fills: about ±2.7066 by ±1.3174.
    static let equalEarthBounds: CGRect = {
        let corner=equalEarth(dλ:.pi,φ:.pi/2), x=equalEarth(dλ:.pi,φ:0).x
        return CGRect(x:-x,y:-corner.y,width:2*x,height:2*corner.y)
    }()
}

/// A projection with its trigonometry worked out once, for projecting many points.
nonisolated struct Projector: Sendable {
    let projection: WorldProjection
    /// Lambert's centre and its east and north directions.
    private let up, east, north: SIMD3<Double>
    private let lambda0: Double
    init(_ projection: WorldProjection) {
        self.projection=projection
        switch projection {
        case .azimuthal(let centre):
            let φ=centre.latitude*GeoPoint.radian, λ=centre.longitude*GeoPoint.radian
            up=centre.unit
            east=SIMD3(-sin(λ),cos(λ),0)
            north=SIMD3(-sin(φ)*cos(λ),-sin(φ)*sin(λ),cos(φ))
            lambda0=λ
        case .equalEarth(let meridian):
            up=SIMD3(0,0,1); east=SIMD3(0,1,0); north=SIMD3(0,0,1)
            lambda0=meridian*GeoPoint.radian
        }
    }
    func project(_ point: GeoPoint) -> CGPoint? {
        switch projection {
        case .azimuthal: return project(unit:point.unit)
        case .equalEarth:
            let dλ=GeoPoint.wrapped((point.longitude*GeoPoint.radian-lambda0)/GeoPoint.radian)*GeoPoint.radian
            return WorldProjection.equalEarth(dλ:dλ,φ:point.latitude*GeoPoint.radian)
        }
    }
    /// Lambert from a unit vector: nil only at the antipode, where the projection has no point.
    func project(unit v: SIMD3<Double>) -> CGPoint? {
        let cosc=(v*up).sum()
        guard 1+cosc>1e-12 else { return nil }
        let k=(2/(1+cosc)).squareRoot()
        return CGPoint(x:k*(v*east).sum(),y:k*(v*north).sum())
    }
    /// Lambert: the cosine of the angle from the centre (x), then the east (y) and north (z)
    /// components; the bearing from north is atan2(y, z).
    func local(unit v: SIMD3<Double>) -> SIMD3<Double> { SIMD3((v*up).sum(),(v*east).sum(),(v*north).sum()) }
    func inverse(_ q: CGPoint) -> GeoPoint? {
        switch projection {
        case .azimuthal(let centre):
            let ρ=hypot(q.x,q.y)
            guard ρ<=2+1e-12 else { return nil }
            guard ρ>1e-15 else { return centre }
            let c=WorldProjection.azimuthalAngle(radius:ρ)
            // Along the bearing (x/ρ, y/ρ) from the centre by c, in three dimensions: exact at every latitude.
            let along=(east*(q.x/ρ)+north*(q.y/ρ))*sin(c)
            return GeoPoint(unit:up*cos(c)+along)
        case .equalEarth:
            typealias W=WorldProjection
            guard abs(q.y)<=W.equalEarthBounds.maxY+1e-12 else { return nil }
            var θ=q.y
            for _ in 0..<12 {
                let θ2=θ*θ, θ6=θ2*θ2*θ2
                let f=θ*(W.a1+W.a2*θ2+θ6*(W.a3+W.a4*θ2))-q.y, fp=W.a1+3*W.a2*θ2+θ6*(7*W.a3+9*W.a4*θ2)
                let step=f/fp
                θ-=step
                if abs(step)<1e-15 { break }
            }
            let θ2=θ*θ, θ6=θ2*θ2*θ2
            let dλ=3.0.squareRoot()/2*q.x*(W.a1+3*W.a2*θ2+θ6*(7*W.a3+9*W.a4*θ2))/cos(θ)
            guard abs(dλ)<=Double.pi+1e-9 else { return nil }
            let φ=asin(min(1,max(-1,2*sin(θ)/3.0.squareRoot())))
            return GeoPoint(latitude:φ/GeoPoint.radian,longitude:GeoPoint.wrapped((lambda0+dλ)/GeoPoint.radian))
        }
    }
}

/// What a map shows: a projection and the part of its plane in view, `aspect` times as tall as it
/// is wide. Points on the map are in canvas units: x 0…1 west to east, y 0…aspect north to south,
/// so a frame fits any view of its shape by one uniform scale.
nonisolated struct MapFrame: Hashable, Sendable {
    let projection: WorldProjection
    /// The plane rectangle in view (y north), exactly `aspect` times as tall as it is wide.
    let plane: CGRect
    /// Builds the frame from any plane rectangle, widened about its middle to the canvas's shape.
    init(projection: WorldProjection, plane box: CGRect, aspect: Double) {
        self.projection=projection
        let width=max(1e-9,box.width,box.height/aspect)
        plane=CGRect(x:box.midX-width/2,y:box.midY-width*aspect/2,width:width,height:width*aspect)
    }
    var aspect: Double { plane.height/plane.width }
    var projector: Projector { Projector(projection) }
    /// Plane to canvas.
    var transform: CGAffineTransform {
        let s=1/plane.width
        return CGAffineTransform(a:s,b:0,c:0,d:-s,tx:-plane.minX*s,ty:plane.maxY*s)
    }
    func canvas(plane q: CGPoint) -> CGPoint { CGPoint(x:(q.x-plane.minX)/plane.width,y:(plane.maxY-q.y)/plane.width) }
    func plane(canvas p: CGPoint) -> CGPoint { CGPoint(x:plane.minX+p.x*plane.width,y:plane.maxY-p.y*plane.width) }
    /// A place on the canvas; nil only where the projection has no point (Lambert's antipode).
    func point(_ geo: GeoPoint) -> CGPoint? { projection.project(geo).map { canvas(plane:$0) } }
    func point(latitude: Double, longitude: Double) -> CGPoint? { point(GeoPoint(latitude:latitude,longitude:longitude)) }
    func point(_ place: Park) -> CGPoint? { point(GeoPoint(place)) }
    /// The place under a point on the canvas.
    func geo(at canvasPoint: CGPoint) -> GeoPoint? { projection.inverse(plane(canvas:canvasPoint)) }
    /// True when a canvas point lies in view, `margin` canvas units outside the edges counting as in.
    func shows(_ p: CGPoint, margin: Double = 0) -> Bool { p.x >= -margin && p.x<=1+margin && p.y >= -margin && p.y<=aspect+margin }
    func shows(_ geo: GeoPoint, margin: Double = 0) -> Bool { point(geo).map { shows($0,margin:margin) } ?? false }
    /// Lambert: the farthest any corner of the view lies from the centre, in radians (π for Equal Earth).
    var reach: Double {
        guard case .azimuthal=projection else { return .pi }
        let corners=[CGPoint(x:plane.minX,y:plane.minY),CGPoint(x:plane.maxX,y:plane.minY),CGPoint(x:plane.minX,y:plane.maxY),CGPoint(x:plane.maxX,y:plane.maxY)]
        return corners.map { hypot($0.x,$0.y)>=2 ? .pi : WorldProjection.azimuthalAngle(radius:hypot($0.x,$0.y)) }.max() ?? .pi
    }

    /// A Lambert map centred on `centre` showing the circle `radiusMeters` around it, with a margin.
    static func around(_ centre: GeoPoint, radiusMeters: Double, aspect: Double, padding: Double = 0.08) -> MapFrame {
        let ρ=WorldProjection.azimuthalRadius(meters:max(1000,radiusMeters))*(1+padding)
        return MapFrame(projection:.azimuthal(centre),plane:CGRect(x:-ρ,y:-ρ,width:2*ρ,height:2*ρ),aspect:aspect)
    }
    /// The whole world on Equal Earth, centred on `centralMeridian`. The sides keep `worldSideMargin`
    /// of plane beside the outline, so a place on the seam (Fiji, the Aleutians, Samoa) shows its
    /// whole mark and closure triangle inside the canvas rather than cut at its edge.
    static func world(centralMeridian: Double = 0, aspect: Double) -> MapFrame {
        MapFrame(projection:.equalEarth(centralMeridian:centralMeridian),plane:WorldProjection.equalEarthBounds.insetBy(dx:-worldSideMargin,dy:-0.03),aspect:aspect)
    }
    /// About 12 points on a phone-wide world map: the largest mark's reach with its closure triangle.
    static let worldSideMargin = 0.22
    /// The world centred on the Pacific (150° E) for a starting point in or across it (East Asia,
    /// Australia, New Zealand, Hawaiʻi, Alaska, Polynesia), so it sits inside the map rather than at
    /// its edge; otherwise on Greenwich, as most atlases. The Americas' Pacific coast (110° to 140° W)
    /// stays on Greenwich, so a start in California opens on the map most people know rather than one
    /// with its own continent pushed against the right edge and the Atlantic split.
    static func worldMeridian(for longitude: Double?) -> Double {
        guard let longitude else { return 0 }
        let λ=GeoPoint.wrapped(longitude)
        return λ>=110 || λ <= -140 ? 150 : 0
    }
    /// Places too far apart for one Lambert map (more than this from their middle) go on Equal Earth.
    static let azimuthalLimit = 70*GeoPoint.radian
    /// The smallest map that shows every place: Lambert centred on their middle, padded by `padding`
    /// of its size and never narrower than `minimumKm`; Equal Earth when they span half the world.
    static func fitting(_ points: [GeoPoint], aspect: Double, padding: Double = 0.08, minimumKm: Double = 600) -> MapFrame {
        guard let middle=GeoPoint.middle(of:points) else { return world(aspect:aspect) }
        if points.contains(where:{ $0.angle(to:middle)>azimuthalLimit }) {
            let projection=WorldProjection.equalEarth(centralMeridian:worldMeridian(for:middle.longitude))
            return fit(points.compactMap(projection.project),projection:projection,aspect:aspect,padding:padding,minimum:minimumKm/GeoPoint.earthRadiusKm)
        }
        let projection=WorldProjection.azimuthal(middle)
        return fit(points.compactMap(projection.project),projection:projection,aspect:aspect,padding:padding,minimum:minimumKm/GeoPoint.earthRadiusKm)
    }
    /// The plane box around `points`, padded, at least `minimum` wide and tall, at the canvas's shape.
    static func fit(_ points: [CGPoint], projection: WorldProjection, aspect: Double, padding: Double, minimum: Double) -> MapFrame {
        guard let first=points.first else { return world(aspect:aspect) }
        var box=points.dropFirst().reduce(CGRect(origin:first,size:.zero)) { $0.union(CGRect(origin:$1,size:.zero)) }
        let pad=padding*max(box.width,box.height,minimum)
        box=box.insetBy(dx:-pad,dy:-pad)
        if box.width<minimum { box=box.insetBy(dx:-(minimum-box.width)/2,dy:0) }
        if box.height<minimum*aspect { box=box.insetBy(dx:0,dy:-(minimum*aspect-box.height)/2) }
        return MapFrame(projection:projection,plane:box,aspect:aspect)
    }
}
