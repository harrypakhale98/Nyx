import Foundation
import SwiftUI
import Testing
@testable import Nyx

/// The maps draw the world's land on equal-area projections (Lambert azimuthal for a region,
/// Equal Earth for the world), place every curated park on the lower 48's map or its own US area's,
/// and thin a crowded catalogue so a map never carries thousands of marks.
struct WorldMapTests {
    let parks=(try? ParkData.load()) ?? []
    func park(_ id: String) throws -> Park { try #require(parks.first { $0.id==id }) }
    func g(_ latitude: Double, _ longitude: Double) -> GeoPoint { GeoPoint(latitude:latitude,longitude:longitude) }
    /// A catalogue place for a test: anywhere, with a chosen Bortle estimate.
    func place(_ id: String, _ latitude: Double, _ longitude: Double, bortle: Int = 3, curated: Bool = false, kind: Park.Kind = .darkSkyPark) -> Park {
        Park(id:id,nps:nil,name:id,countryCode:"NA",region:"",kind:kind,curated:curated,latitude:latitude,longitude:longitude,timeZoneID:"UTC",
             darkSkyDesignated:false,bortleEstimate:bortle,description:"",sourceURL:"",sourceNote:"",viewingSpots:[])
    }
    static let land=WorldLand.load(Bundle.main.url(forResource:"world-land",withExtension:"json"))

    // MARK: Projections

    /// Forward then inverse returns the place within 1e-9 degrees, on both projections, from centres
    /// across the world (both hemispheres, the date line, near a pole).
    @Test func projectionsRoundTrip() {
        let centres=[g(39.74,-104.99),g(-41.29,174.78),g(64.84,-147.72),g(0,0),g(-14.27,-170.13),g(-24.7,15.9),g(78.2,15.6)]
        let points=centres+[g(51.5,-0.12),g(-33.9,151.2),g(19.4,-155.3),g(35.7,139.7),g(-54.8,-68.3),g(70,-150),g(0.01,179.99),g(10,-179.99)]
        for centre in centres {
            let lambert=WorldProjection.azimuthal(centre)
            for point in points where point.angle(to:centre)<170*GeoPoint.radian {
                let back=lambert.project(point).flatMap(lambert.inverse)
                #expect(back.map { abs($0.latitude-point.latitude)<1e-9 && abs(GeoPoint.wrapped($0.longitude-point.longitude))<1e-9 } == true,"\(centre) \(point)")
            }
        }
        for meridian in [0.0,150,-96] {
            let world=WorldProjection.equalEarth(centralMeridian:meridian)
            for point in points {
                let back=world.project(point).flatMap(world.inverse)
                #expect(back.map { abs($0.latitude-point.latitude)<1e-9 && abs(GeoPoint.wrapped($0.longitude-point.longitude))<1e-9 } == true,"\(meridian) \(point)")
            }
        }
        // Equal Earth's published extent: ±2.7066 by ±1.3174, 2.0546 : 1.
        let bounds=WorldProjection.equalEarthBounds
        #expect(abs(bounds.maxX-2.7066)<1e-4 && abs(bounds.maxY-1.3174)<1e-4 && abs(bounds.width/bounds.height-2.0546)<1e-3)
    }
    /// Lambert is equal-area: the circle r kilometres around the centre has ρ = 2 sin(r / 2R), and
    /// a place r kilometres away in any direction lands on it.
    @Test func lambertRadiusIsTrue() {
        let denver=g(39.74,-104.99), lambert=WorldProjection.azimuthal(denver)
        let ρ=WorldProjection.azimuthalRadius(meters:500_000)
        for point in SkyMap.circle(around:denver,meters:500_000,steps:24) {
            let q=lambert.project(point)
            #expect(q.map { abs(hypot($0.x,$0.y)-ρ)<1e-9 } == true)
            #expect(abs(Park.distance(point.latitude,point.longitude,denver.latitude,denver.longitude)-500_000)<500)
        }
    }
    /// The centre of a map is the centre of the view: at the plane's origin, and at the middle of the canvas.
    @Test func centreMapsToTheMiddle() {
        for centre in [g(39.74,-104.99),g(-41.29,174.78),g(69.6,18.9)] {
            let q=WorldProjection.azimuthal(centre).project(centre)
            #expect(q.map { abs($0.x)<1e-12 && abs($0.y)<1e-12 } == true)
            let frame=MapFrame.around(centre,radiusMeters:320_000,aspect:SkyMap.aspect)
            let p=frame.point(centre)
            #expect(p.map { abs($0.x-0.5)<1e-9 && abs($0.y-SkyMap.aspect/2)<1e-9 } == true)
            #expect(abs(frame.aspect-SkyMap.aspect)<1e-12)
            // North is up and east is right.
            let north=frame.point(g(centre.latitude+1,centre.longitude)), east=frame.point(g(centre.latitude,centre.longitude+1))
            #expect((north?.y ?? 1)<SkyMap.aspect/2 && (east?.x ?? 0)>0.5)
        }
    }
    /// The antipode has no point on a Lambert map, never NaN; points beside it still do, inside the
    /// projection's disc; and land drawn from a centre whose antipode lies inside a continent still
    /// fills the land and leaves the sea (Madrid's antipode is off New Zealand; Wellington's is in Spain).
    @Test func antipodeIsHandled() throws {
        let madrid=g(40.42,-3.7), lambert=WorldProjection.azimuthal(madrid)
        #expect(madrid.antipode.latitude == -40.42 && abs(madrid.antipode.longitude-176.3)<1e-9)
        #expect(lambert.project(madrid.antipode) == nil)
        #expect(MapFrame.around(madrid,radiusMeters:300_000,aspect:SkyMap.aspect).point(madrid.antipode) == nil)
        let beside=try #require(lambert.project(g(-40.3,176.3)))
        #expect(beside.x.isFinite && beside.y.isFinite && hypot(beside.x,beside.y)<2)
        #expect(lambert.inverse(CGPoint(x:2.1,y:0)) == nil)
        #expect(abs(madrid.angle(to:madrid.antipode)-Double.pi)<1e-12)

        let land=try #require(Self.land)
        func filled(_ frame: MapFrame, _ point: GeoPoint) throws -> Bool {
            let size=CGSize(width:800,height:800*frame.aspect), placement=WorldLand.Placement(frame,in:size)
            let p=placement.screen(try #require(frame.point(point)))
            return land.shapes(frame,at:placement).fill.contains(p,eoFill:true)
        }
        let europe=MapFrame.around(madrid,radiusMeters:7_000_000,aspect:SkyMap.aspect)
        #expect(try filled(europe,g(25,10)) && filled(europe,g(50,30)) && filled(europe,g(40,-100)))   // Sahara, Ukraine, Kansas
        #expect(try !filled(europe,g(30,-40)) && !filled(europe,g(35,18)))                              // the Atlantic, the Ionian Sea
        let wellington=g(-41.29,174.78)
        let pacific=MapFrame.around(wellington,radiusMeters:3_000_000,aspect:SkyMap.aspect)
        #expect(try filled(pacific,g(-25,135)) && filled(pacific,g(-43.5,171)))                          // central Australia, Canterbury
        #expect(try !filled(pacific,g(-38,160)) && !filled(pacific,g(-30,-175)))                         // the Tasman Sea, the open Pacific
    }

    // MARK: Fitting

    /// A fitted map shows every place inside its canvas, at the canvas's shape; places spread over
    /// half the world go on Equal Earth instead.
    @Test func fittingShowsEveryPoint() {
        let sets:[[GeoPoint]]=[
            [g(36.5,-117),g(38.2,-109.9),g(37.6,-112.2),g(36.1,-112.1)],           // the Southwest
            [g(64.8,-147.7),g(63.1,-151),g(58.5,-155)],                               // Alaska
            [g(-14.27,-170.7)],                                                      // one place, American Samoa
            [g(52,-1),g(-41,174)],                                                   // the far side of the world
            [g(10,179.5),g(-10,-179.5),g(5,178)],                                    // across the date line
            [g(78.2,15.6),g(69.6,18.9)],                                             // Svalbard and Tromsø
        ]
        for points in sets {
            let frame=MapFrame.fitting(points,aspect:SkyMap.aspect)
            #expect(abs(frame.aspect-SkyMap.aspect)<1e-9)
            for point in points {
                let p=frame.point(point)
                #expect(p.map { frame.shows($0) && $0.x>0.01 && $0.x<0.99 } == true,"\(points) \(point)")
            }
        }
        if case .equalEarth=MapFrame.fitting([g(52,-1),g(-41,174)],aspect:SkyMap.aspect).projection {} else { Issue.record("half the world should be on Equal Earth") }
        if case .azimuthal=MapFrame.fitting([g(10,179.5),g(-10,-179.5)],aspect:SkyMap.aspect).projection {} else { Issue.record("the date line is no seam for Lambert") }
        // One place is never a field: the map is at least the minimum across.
        let one=MapFrame.fitting([g(-14.27,-170.7)],aspect:SkyMap.aspect,minimumKm:600)
        #expect(one.plane.width*GeoPoint.earthRadiusKm>=600-1e-6)
        // The world map holds every place on Earth, centred on the Pacific for a starting point there.
        #expect(MapFrame.worldMeridian(for:174.8)==150 && MapFrame.worldMeridian(for:-157.8)==150 && MapFrame.worldMeridian(for:-96)==0 && MapFrame.worldMeridian(for:nil)==0)
        for meridian in [0.0,150] {
            let world=MapFrame.world(centralMeridian:meridian,aspect:SkyMap.aspect)
            for point in [g(89,0),g(-89,179),g(0,-180),g(0,180),g(-14.27,-170.7),g(64.8,-147.7)] { #expect(world.shows(point),"\(meridian) \(point)") }
        }
    }

    // MARK: The United States

    /// The map a US starting point opens on holds every lower-48 park; Alaska, Hawaiʻi, American
    /// Samoa and the Virgin Islands are one choice away in the area menu, and each of their parks
    /// sits inside its own area's map. Every curated park belongs to exactly one area.
    @Test func everyCuratedParkIsOnItsAreasMap() throws {
        #expect(parks.count==63)
        var counts:[SkyMap.Region:Int]=[:]
        for park in parks {
            let region=try #require(SkyMap.region(park),"\(park.id)")
            counts[region,default:0]+=1
            let frame=SkyMap.frame(region,origin:nil,radiusMeters:0)
            let p=try #require(frame.point(park))
            #expect(frame.shows(p) && p.x>0.01 && p.x<0.99 && p.y>0.01 && p.y<frame.aspect-0.01,"\(park.id) on \(region)")
            if region == .lower48 { #expect(SkyMap.lower48.shows(p)) }
        }
        #expect(counts == [.lower48:51,.alaska:8,.hawaii:2,.samoa:1,.virginIslands:1])
        #expect(SkyMap.frame(.lower48,origin:nil,radiusMeters:0) == SkyMap.lower48)
        // North is up and east is right on the lower 48's map.
        #expect(try SkyMap.position(park("acad")).x>SkyMap.position(park("olym")).x)
        #expect(try SkyMap.position(park("glac")).y<SkyMap.position(park("bibe")).y)
        // The lower 48 fills its canvas from coast to coast, as the map always has.
        #expect(try SkyMap.position(park("olym")).x<0.15 && SkyMap.position(park("acad")).x>0.85)
        // Alaska's parks are far off the lower 48's map, at their true place: no inset.
        #expect(try !SkyMap.lower48.shows(SkyMap.position(park("gaar"))))
    }
    @Test func defaultAreaFollowsTheStartingPoint() {
        #expect(SkyMap.defaultRegion(origin:g(41.88,-87.63),countryCode:"US") == .lower48)
        #expect(SkyMap.defaultRegion(origin:g(61.22,-149.9),countryCode:"US") == .alaska)
        #expect(SkyMap.defaultRegion(origin:g(21.31,-157.86),countryCode:"US") == .hawaii)
        #expect(SkyMap.defaultRegion(origin:g(-14.28,-170.7),countryCode:"AS") == .samoa)
        #expect(SkyMap.defaultRegion(origin:g(18.34,-64.93),countryCode:"VI") == .virginIslands)
        #expect(SkyMap.defaultRegion(origin:g(48.85,2.35),countryCode:"FR") == .around)
        #expect(SkyMap.defaultRegion(origin:g(43.65,-79.38),countryCode:"CA") == .around)       // Toronto: its own circle
        #expect(SkyMap.defaultRegion(origin:nil,countryCode:nil) == .lower48)
        // Around a starting point, the search radius is a true circle filling the view.
        let toronto=g(43.65,-79.38)
        let around=SkyMap.frame(.around,origin:toronto,radiusMeters:320_000)
        let ring=SkyMap.ring(around:toronto,meters:320_000,on:around)
        #expect(ring.map { $0.allSatisfy { around.shows($0) } } == true)
        #expect(SkyMap.ring(around:toronto,meters:320_000,on:SkyMap.frame(.world,origin:toronto,radiusMeters:0)) == nil)
    }

    // MARK: Crowds

    /// A crowded map keeps the curated parks and saved spots whatever their spacing, then the best of
    /// each crowd, never two within the spacing and never more than the limit.
    @Test func crowdedMapsAreThinned() {
        let frame=MapFrame.around(g(50,10),radiusMeters:1_500_000,aspect:SkyMap.aspect)
        var places:[Park]=[]
        for i in 0..<40 { for j in 0..<40 { places.append(place("wd:Q\(i*40+j)",44+Double(i)*0.3,1+Double(j)*0.45,bortle:1+(i+j)%8)) } }
        places.append(place("curated",50,10,curated:true,kind:.nationalPark))
        places.append(place("curated2",50.01,10.01,curated:true,kind:.nationalPark))
        places.append(place("pin:mine",50.02,10.02,kind:.custom))
        var scored=0
        let shown=SkyMap.shown(places,in:frame,spacing:0.03,limit:120,scoreLimit:300) { ranked in scored=ranked.count; return ranked.sorted { $0.bortleEstimate<$1.bortleEstimate } }
        #expect(shown.inView>1000 && scored<=300)
        #expect(shown.places.count<=120)
        let ids=Set(shown.places.map(\.id))
        #expect(ids.isSuperset(of:["curated","curated2","pin:mine"]))
        let points=shown.places.compactMap { place in frame.point(place).map { (place,$0) } }
        for (i,a) in points.enumerated() { for b in points[(i+1)...] where !(a.0.curated || a.0.isSavedSpot) || !(b.0.curated || b.0.isSavedSpot) {
            #expect(hypot(a.1.x-b.1.x,a.1.y-b.1.y) >= 0.03-1e-12,"\(a.0.id) \(b.0.id)")
        } }
        // Places out of view are never drawn.
        #expect(shown.places.allSatisfy { frame.shows(frame.point($0) ?? CGPoint(x:-1,y:-1),margin:0.011) })
        // Thinning keeps the first of each crowd.
        let kept=MapThinning.thin(always:[CGPoint(x:0,y:0)],ranked:[CGPoint(x:0.01,y:0),CGPoint(x:0.5,y:0.5),CGPoint(x:0.51,y:0.5)],point:{ $0 },spacing:0.05,limit:10)
        #expect(kept == [CGPoint(x:0,y:0),CGPoint(x:0.5,y:0.5)])
    }

    // MARK: Tonight's map

    @Test func tonightMapReadsWestToEastAndRanksDarkestFirst() throws {
        let now=try #require(ISO8601DateFormatter().date(from:"2026-10-09T18:00:00Z")), engine=AstronomyEngine()
        let nights=parks.map { park in NightPlanner.night(park:park,sky:engine.conditions(for:park,on:park.evening(park.currentNight(at:now))),forecast:nil,detail:nil,now:now) }
        let map=TonightMap(nights:nights,frame:SkyMap.lower48)
        #expect(map.marks.count==63 && map.inView==63)
        // The US areas in turn, each west to east.
        let order=SkyMap.Region.unitedStates
        #expect(map.marks.map(\.region) == map.marks.map(\.region).sorted { (order.firstIndex(of:$0) ?? 9)<(order.firstIndex(of:$1) ?? 9) })
        #expect(map.marks.last?.id == "viis")
        #expect(map.darkest.map(\.id) == nights.sorted(by:NightPlanner.better).map(\.park.id))
        // The reveal crosses the map as drawn, west to east.
        let reveal=map.marks.sorted { (map.reveal[$0.id] ?? 0)<(map.reveal[$1.id] ?? 0) }.map(\.point.x)
        #expect(reveal == reveal.sorted() && map.reveal.values.allSatisfy { (0..<1).contains($0) })
        // A thinned map says how many places lie in view.
        #expect(TonightMap(nights:nights,frame:SkyMap.lower48,inView:200).summary.contains("200"))
        // A world map places Hawaiʻi and Acadia truly: Hawaiʻi far west of Acadia, on the canvas.
        let world=TonightMap(nights:nights,frame:SkyMap.frame(.world,origin:nil,radiusMeters:0))
        let havo=try #require(world.marks.first { $0.id=="havo" }), acad=try #require(world.marks.first { $0.id=="acad" })
        #expect(havo.point.x<acad.point.x && world.frame.shows(havo.point) && world.frame.shows(acad.point))
    }

    // MARK: Marks on their land

    /// Every mark sits on the land drawn under it, on every kind of map the Parks map opens: the world
    /// (from starting points in California, Hawaiʻi, Berlin, Ishigaki and Wellington, both central
    /// meridians), the circle around a starting point, and the US areas. Each mark comes through
    /// `TonightMap` exactly as the screen places it, is drawn within 3 points of the land under the
    /// same coordinate (small islands are simplified), and lies wholly inside the canvas.
    @Test @MainActor func marksSitOnTheirLand() throws {
        let land=try #require(Self.land)
        let now=try #require(ISO8601DateFormatter().date(from:"2026-10-11T18:00:00Z")), engine=AstronomyEngine()
        let hale=try park("hale"), noca=try park("noca")
        let kruger=place("wd:Q24451",-24.01139,31.48528), iriomote=place("wd:Q703967",24.31667,123.88333)
        let torres=place("wd:Q901646",-50.98306,-72.96639), tatra=place("wd:Q1080683",49.18028,19.91944)
        let rhon=place("wd:Q20850",50.5,10.0)
        func night(_ park: Park) -> Night {
            NightPlanner.night(park:park,sky:engine.conditions(for:park,on:park.evening(park.currentNight(at:now))),forecast:nil,detail:nil,now:now)
        }
        let size=CGSize(width:329,height:329*SkyMap.aspect)
        func check(_ places: [Park], on frame: MapFrame, _ name: String) {
            let map=TonightMap(nights:places.map(night),frame:frame)
            #expect(map.marks.count==places.count,"\(name): every place has a mark")
            let placement=WorldLand.Placement(frame,in:size), fill=land.shapes(frame,at:placement).fill
            let canvas=CGRect(x:placement.dx,y:placement.dy,width:placement.scale,height:placement.scale*frame.aspect)
            let scale=TonightMapCanvas.markScale(width:size.width,frame:frame)
            for mark in map.marks {
                let p=placement.screen(mark.point)
                // The same coordinate on the land's own projection: the mark is drawn exactly there.
                let ground=placement.screen(frame.canvas(plane:frame.projection.project(GeoPoint(latitude:mark.latitude,longitude:mark.longitude)) ?? .zero))
                #expect(hypot(p.x-ground.x,p.y-ground.y)<1e-6,"\(name): \(mark.name)")
                let reach=mark.radius*scale
                #expect(canvas.insetBy(dx:reach,dy:reach).contains(p),"\(name): \(mark.name) at \(p) is cut by the canvas \(canvas)")
                // The NPS coordinate for American Samoa lies at sea between Tutuila and Ofu, and is drawn there.
                guard mark.id != "npsa" else { continue }
                let near=[CGPoint.zero]+(0..<12).map { i in CGPoint(x:3*cos(Double(i)*Double.pi/6),y:3*sin(Double(i)*Double.pi/6)) }
                #expect(near.contains { fill.contains(CGPoint(x:p.x+$0.x,y:p.y+$0.y),eoFill:true) },"\(name): \(mark.name) at \(p) is off its land")
            }
        }
        let everywhere=[hale,noca,kruger,iriomote,torres,tatra]
        for origin in [nil,g(34.13,-116.04),g(21.31,-157.86),g(52.52,13.4),g(24.34,124.16),g(-41.29,174.78)] as [GeoPoint?] {
            check(everywhere,on:SkyMap.frame(.world,origin:origin,radiusMeters:0),"world from \(String(describing:origin))")
        }
        check([kruger],on:SkyMap.frame(.around,origin:g(-25.47,30.97),radiusMeters:320_000),"around Mbombela")
        check([iriomote],on:SkyMap.frame(.around,origin:g(24.34,124.16),radiusMeters:320_000),"around Ishigaki")
        check([torres],on:SkyMap.frame(.around,origin:g(-53.16,-70.91),radiusMeters:320_000),"around Punta Arenas")
        check([tatra,rhon],on:SkyMap.frame(.around,origin:g(52.52,13.4),radiusMeters:482_803),"around Berlin, 300 miles")
        check([noca],on:SkyMap.frame(.lower48,origin:nil,radiusMeters:0),"lower 48")
        check([hale],on:SkyMap.frame(.hawaii,origin:nil,radiusMeters:0),"Hawaiʻi")
        check(parks.filter { SkyMap.region($0) == .alaska },on:SkyMap.frame(.alaska,origin:nil,radiusMeters:0),"Alaska")
        check(parks.filter { SkyMap.region($0) == .virginIslands },on:SkyMap.frame(.virginIslands,origin:nil,radiusMeters:0),"Virgin Islands")
        check(parks.filter { SkyMap.region($0) == .samoa },on:SkyMap.frame(.samoa,origin:nil,radiusMeters:0),"American Samoa")
    }
    /// The world opens on Greenwich from the Americas (California included, so its own continent
    /// is not pushed against the right edge with Brazil cut off) and on the Pacific from East Asia,
    /// Oceania, Hawaiʻi and Alaska; either way the world's sides leave room for a whole mark.
    @Test @MainActor func worldMapKeepsItsStartAndEdgesWhole() throws {
        for (longitude,meridian) in [(-116.04,0.0),(-122.42,0),(-73.99,0),(-46.6,0),(13.4,0),(-157.86,150),(-149.9,150),(-170.7,150),(124.16,150),(174.78,150),(151.2,150)] {
            #expect(MapFrame.worldMeridian(for:longitude)==meridian,"\(longitude)")
        }
        let world=SkyMap.frame(.world,origin:g(34.13,-116.04),radiusMeters:0)
        // From California: the Americas on the map's western half, the eastern tip of Brazil well inside it.
        #expect(parks.filter { SkyMap.region($0) == .lower48 }.allSatisfy { (world.point($0)?.x ?? 1)<0.4 })
        #expect(try #require(world.point(g(-7.15,-34.8))).x<0.45)
        let size=CGSize(width:329,height:329*SkyMap.aspect)
        for meridian in [0.0,150] {
            let frame=MapFrame.world(centralMeridian:meridian,aspect:SkyMap.aspect), placement=WorldLand.Placement(frame,in:size)
            // The largest mark whole on the west; on the east, its closure triangle too (drawn 0.8 r + 7 points to its right).
            let radius=TonightMap.radius(score:100)*TonightMapCanvas.markScale(width:size.width,frame:frame)
            let west=placement.screen(try #require(frame.point(g(0,meridian-180)))), east=placement.screen(try #require(frame.point(g(0,meridian+179.999))))
            #expect(west.x>=radius && east.x+0.8*radius+7<=size.width,"\(meridian): \(west.x) \(east.x)")
        }
    }

    // MARK: Names on the map

    /// A name always lies inside the map, clear of the names before it and of its own mark: beside the
    /// mark where a side fits, slid back inside from a corner (Tatra in the corner of "Around
    /// Berlin"), and left out when it cannot fit at all.
    @Test @MainActor func namesStayInsideTheMap() throws {
        let area=CGRect(x:0,y:0,width:329,height:207).insetBy(dx:2,dy:2), text=CGSize(width:52,height:14), gap=17.0
        func inside(_ o: CGPoint?) -> Bool { o.map { area.contains(CGRect(origin:$0,size:text)) } ?? false }
        // Room on the right: the right-hand side, as before.
        let free=try #require(TonightMapLabels.origin(text:text,beside:CGPoint(x:100,y:100),gap:gap,in:area,avoiding:[]))
        #expect(free == CGPoint(x:117,y:93))
        // Every corner, and hard against every edge: inside the map, never on the mark.
        for p in [CGPoint(x:322,y:200),CGPoint(x:6,y:6),CGPoint(x:322,y:6),CGPoint(x:6,y:200),CGPoint(x:300,y:204),CGPoint(x:164,y:205),CGPoint(x:327,y:100)] {
            let o=TonightMapLabels.origin(text:text,beside:p,gap:gap,in:area,avoiding:[])
            #expect(inside(o),"\(p): \(String(describing:o))")
            if let o { #expect(!CGRect(origin:o,size:text).intersects(CGRect(x:p.x-gap+4,y:p.y-gap+4,width:2*gap-8,height:2*gap-8)),"\(p) covers its mark") }
        }
        // Clear of an earlier name.
        let taken=[CGRect(x:200,y:150,width:129,height:57)]
        let o=TonightMapLabels.origin(text:text,beside:CGPoint(x:322,y:200),gap:gap,in:area,avoiding:taken)
        #expect(o.map { inside($0) && !taken[0].intersects(CGRect(origin:$0,size:text)) } ?? true)
        // No room anywhere: left out, never drawn past the edge.
        #expect(TonightMapLabels.origin(text:CGSize(width:400,height:14),beside:CGPoint(x:160,y:100),gap:gap,in:area,avoiding:[]) == nil)
        #expect(TonightMapLabels.origin(text:text,beside:CGPoint(x:160,y:100),gap:gap,in:area,avoiding:[area]) == nil)
    }

    // MARK: Your constellation

    /// A journal in the lower 48 keeps the lower 48's map (no visible change); a night abroad moves
    /// the map to hold every night at its true place.
    @Test @MainActor func constellationFramesItsPlaces() throws {
        let id={ UUID() }
        let home=[LoggedNight(id:id(),date:.now,parkID:"grba",observedBortle:1),LoggedNight(id:id(),date:.now,parkID:"jotr",observedBortle:3)]
        let us=ConstellationLayout(nights:home,parks:parks)
        #expect(us.onLower48 && us.frame == SkyMap.lower48)
        #expect(try us.stars.first { $0.night.parkID=="grba" }?.point == SkyMap.position(park("grba")))
        #expect(us.content(parks:parks).background.count == parks.filter { SkyMap.lower48.shows(SkyMap.position($0),margin:0.02) }.count)

        let namib=place("wd:Q1427364",-25.1,16.0,bortle:1)
        let abroad=ConstellationLayout(nights:home+[LoggedNight(id:id(),date:.now,parkID:namib.id,observedBortle:1)],parks:parks+[namib])
        #expect(!abroad.onLower48 && abroad.stars.count==3)
        #expect(abroad.stars.allSatisfy { abroad.frame.shows($0.point) })
        // Alaska with the lower 48: one Lambert map holds both, Denali north-west of Great Basin.
        let north=ConstellationLayout(nights:home+[LoggedNight(id:id(),date:.now,parkID:"dena",observedBortle:1)],parks:parks)
        let dena=try #require(north.stars.first { $0.night.parkID=="dena" }), grba=try #require(north.stars.first { $0.night.parkID=="grba" })
        #expect(!north.onLower48 && dena.point.x<grba.point.x && dena.point.y<grba.point.y && north.frame.shows(dena.point))
        // No nights: the map chosen for the starting point.
        let empty=ConstellationLayout(nights:[],parks:parks,empty:SkyMap.frame(.around,origin:g(48.85,2.35),radiusMeters:400_000))
        #expect(!empty.onLower48 && empty.stars.isEmpty)
    }

    // MARK: The land

    /// world-land.json decodes into Natural Earth's land, the Caspian and the large lakes, and reads
    /// as land where land is: an island in a lake (Isle Royale, Manitoulin) is land again.
    @Test func landDecodes() throws {
        let land=try #require(Self.land)
        #expect(land.rings.count==1325 && land.rings.filter(\.lake).count==146)
        #expect(land.pointCount>20_000 && land.pointCount<35_000)
        #expect(land.contains(g(39.74,-104.99)) && land.contains(g(-25,135)) && land.contains(g(-80,0)) && land.contains(g(64.9,-18.5)))
        #expect(!land.contains(g(30,-40)) && !land.contains(g(42,51)) && !land.contains(g(-30,-140)))   // the Atlantic, the Caspian, the Pacific
        // The Great Lakes, Great Salt Lake and Lake Victoria are water; Lake Eyre, a salt pan dry most years, is not cut.
        for lake in [g(47.7,-87.5),g(44.0,-87.0),g(44.8,-82.4),g(42.2,-81.2),g(43.6,-77.8),g(41.1,-112.5),g(-1.0,33.0)] { #expect(!land.contains(lake),"\(lake)") }
        #expect(land.contains(g(48.0,-88.9)) && land.contains(g(45.8,-82.2)) && land.contains(g(41.88,-87.65)) && land.contains(g(-28.4,137.3)))
        // Every frame the app opens draws land, with the world's outline only on Equal Earth.
        let size=CGSize(width:390,height:246)
        for region in SkyMap.Region.allCases {
            let frame=SkyMap.frame(region,origin:g(41.88,-87.63),radiusMeters:320_000)
            let shapes=land.shapes(frame,at:WorldLand.Placement(frame,in:size))
            #expect(!shapes.fill.isEmpty && !shapes.coast.isEmpty,"\(region)")
            #expect((shapes.edge != nil) == (region == .world),"\(region)")
        }
    }
}
