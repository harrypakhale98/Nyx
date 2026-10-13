import Foundation
import CoreGraphics

/// Nyx's maps of Earth: the world's land (`WorldLand`) under the places, on a projection fitted to
/// what the map shows (`MapFrame`), in a canvas `aspect` times as tall as it is wide. A region map
/// is Lambert azimuthal equal-area centred on it, so every place sits at its true place, Hawaiʻi
/// as far from California as it is; the whole world is Equal Earth. No MapKit: nothing leaves
/// the device to draw a map.
nonisolated enum SkyMap {
    static let aspect = 0.63
    /// Where a map of places looks: around the starting point, each of the five US areas that hold
    /// the curated parks, or the whole world.
    enum Region: String, CaseIterable, Hashable, Sendable {
        case around, lower48, alaska, hawaii, samoa, virginIslands, world
        /// The five US areas, in the order a reader meets them.
        static let unitedStates: [Region] = [.lower48, .alaska, .hawaii, .samoa, .virginIslands]
        var name: String {
            switch self {
            case .around: String(localized:"Around you")
            case .lower48: String(localized:"Lower 48")
            case .alaska: String(localized:"Alaska")
            case .hawaii: String(localized:"Hawaiʻi")
            case .samoa: String(localized:"American Samoa")
            case .virginIslands: String(localized:"U.S. Virgin Islands")
            case .world: String(localized:"World")
            }
        }
    }
    /// A US area: a Lambert map centred on `centre`, fitted around its coasts' extremes (`edges`),
    /// and the box of longitudes and latitudes that counts as inside it.
    struct Area: Sendable {
        let centre: GeoPoint
        let edges: [GeoPoint]
        let latitudes: ClosedRange<Double>
        let longitudes: ClosedRange<Double>
        let minimumKm: Double
    }
    static func area(_ region: Region) -> Area? {
        func g(_ lat: Double, _ lon: Double) -> GeoPoint { GeoPoint(latitude:lat,longitude:lon) }
        switch region {
        case .lower48:
            // Cape Flattery, Cape Mendocino, San Diego, Brownsville, the Dry Tortugas, Key West, Cape Sable,
            // Lubec, northern Maine, the Northwest Angle and the 49th parallel.
            return Area(centre:g(38.5,-96),edges:[g(48.38,-124.73),g(40.44,-124.41),g(32.53,-117.12),g(25.84,-97.15),g(24.63,-82.87),g(24.55,-81.8),
                                                  g(25.12,-81.09),g(44.81,-66.95),g(47.46,-69.22),g(49.38,-95.15),g(49,-110),g(49,-123)],
                        latitudes:24...50,longitudes:(-125.5)...(-66.5),minimumKm:0)
        case .alaska:
            // Utqiagvik, the Arctic and Pacific ends of the border, the panhandle's south, Unimak, Nunivak, Cape Prince of Wales.
            return Area(centre:g(62.5,-152),edges:[g(71.39,-156.48),g(69.65,-141),g(60.3,-141),g(54.7,-130.6),g(54.8,-163.4),g(60,-166.4),g(65.6,-168.1)],
                        latitudes:51...72,longitudes:(-180)...(-129.9),minimumKm:0)
        case .hawaii:
            // Niʻihau, Kauaʻi, the Big Island's south and east capes.
            return Area(centre:g(20.6,-157.3),edges:[g(22.23,-159.79),g(21.95,-160.25),g(18.91,-155.68),g(20.27,-154.81)],
                        latitudes:18.5...22.5,longitudes:(-160.5)...(-154.5),minimumKm:0)
        case .samoa:
            return Area(centre:g(-14.27,-170.13),edges:[g(-14.33,-170.84),g(-14.25,-169.42),g(-14.38,-170.6),g(-14.17,-169.6)],
                        latitudes:(-14.6)...(-13.9),longitudes:(-171.2)...(-169.2),minimumKm:170)
        case .virginIslands:
            return Area(centre:g(18.05,-64.8),edges:[g(18.38,-65.03),g(18.33,-64.67),g(17.68,-64.88),g(17.76,-64.56),g(18.45,-64.75)],
                        latitudes:17.6...18.5,longitudes:(-65.1)...(-64.5),minimumKm:110)
        case .around, .world: return nil
        }
    }
    /// The map of `region`: a US area as above; around `origin`, the circle of `radiusMeters` (never
    /// under 100 km); the world on Equal Earth, centred on the Pacific for a starting point there.
    static func frame(_ region: Region, origin: GeoPoint?, radiusMeters: Double, aspect: Double = aspect) -> MapFrame {
        switch region {
        case .world: return MapFrame.world(centralMeridian:MapFrame.worldMeridian(for:origin?.longitude),aspect:aspect)
        case .around:
            guard let origin else { return frame(.lower48,origin:nil,radiusMeters:radiusMeters,aspect:aspect) }
            return MapFrame.around(origin,radiusMeters:max(100_000,radiusMeters),aspect:aspect)
        default:
            guard let area=area(region) else { return MapFrame.world(aspect:aspect) }
            let projection=WorldProjection.azimuthal(area.centre)
            return MapFrame.fit(area.edges.compactMap(projection.project),projection:projection,aspect:aspect,padding:0.03,minimum:area.minimumKm/GeoPoint.earthRadiusKm)
        }
    }
    /// The lower 48, the map a US starting point opens on.
    static let lower48 = frame(.lower48,origin:nil,radiusMeters:0)
    /// The US area whose map holds a place, by its box (a place in Canada or Mexico near the border
    /// counts as the lower 48's: only the reading order and the default map use this).
    static func region(of point: GeoPoint) -> Region? {
        Region.unitedStates.first { region in
            guard let area=area(region) else { return false }
            return area.latitudes.contains(point.latitude) && (area.longitudes.contains(point.longitude) || (region == .alaska && point.longitude>=172))
        }
    }
    static func region(_ park: Park) -> Region? { region(of:GeoPoint(park)) }
    /// A park's place on the lower 48's map (canvas units). Outside it, still its true place on that
    /// projection, off the canvas.
    static func position(_ park: Park) -> CGPoint { lower48.point(park) ?? CGPoint(x:0.5,y:aspect/2) }
    /// The map a person sees first: for a starting point in the US or its territories, the US area
    /// that holds it (the lower 48 for most, so the curated parks show as they always have);
    /// anywhere else, the circle around it. No starting point: the lower 48.
    static func defaultRegion(origin: GeoPoint?, countryCode: String?) -> Region {
        guard let origin else { return .lower48 }
        let american=americanCodes.contains(countryCode?.uppercased() ?? "US")
        guard american else { return .around }
        return region(of:origin) ?? .around
    }
    /// The United States and its territories, as places' country codes give them.
    static let americanCodes: Set<String> = ["US","AS","VI","PR","GU","MP","UM"]
    /// A US place: a curated park, a catalogue place in the US or a territory, or a saved spot there
    /// (by its nearest town's country, or inside the states' outline, so a spot near the border whose
    /// nearest town lies across it still counts).
    static func isAmerican(_ place: Park) -> Bool {
        if place.curated || americanCodes.contains(place.countryCode.uppercased()) { return true }
        return place.isSavedSpot && USOutline.contains(latitude:place.latitude,longitude:place.longitude)
    }
    /// The places a map of `region` may draw. A US area's box reaches into Canada, Mexico and the
    /// Bahamas, and its name ("Lower 48") says the United States, so it draws US places only; the
    /// circle around the starting point and the world draw every place.
    static func places(_ places: [Park], for region: Region) -> [Park] {
        guard Region.unitedStates.contains(region) else { return places }
        return places.filter(isAmerican)
    }
    /// Every place Nyx knows once: the curated parks, the rest of the catalogue, then saved spots.
    static func merged(parks: [Park], catalog: [Park], spots: [Park]) -> [Park] {
        guard !catalog.isEmpty else { return parks+spots }
        let known=Set(parks.map(\.id))
        return parks+catalog.filter { !known.contains($0.id) }+spots
    }
    /// The places a map draws: every saved spot and curated park in view, then the rest best first
    /// (`rank`, darkest first), each kept only where no place already kept lies within `spacing`
    /// (canvas units), at most `limit` in all. Where more than `scoreLimit` crowd the view (the
    /// world), they are thinned first by what is known without a forecast (a dark-sky designation,
    /// then the darker Bortle estimate), so a map never scores thousands of places to draw a few
    /// hundred. Returns the places drawn and how many lay in view.
    static func shown(_ places: [Park], in frame: MapFrame, spacing: Double = 0.03, limit: Int = 200, scoreLimit: Int = 400,
                      rank: ([Park]) -> [Park]) -> (places: [Park], inView: Int) {
        shown(pool(places,in:frame,spacing:spacing,scoreLimit:scoreLimit),spacing:spacing,limit:limit,rank:rank)
    }
    /// A map's places before any is scored: those always drawn (curated parks and saved spots in
    /// view), the rest (thinned by what is known without a forecast where more than `scoreLimit`
    /// crowd the view), each one's point, and how many lay in view. `rest` is exactly what `shown`
    /// hands to `rank`, so a screen can work out those nights off the main thread first.
    struct Pool: Sendable {
        let fixed: [Park]
        let rest: [Park]
        let points: [String: CGPoint]
        let inView: Int
    }
    static func pool(_ places: [Park], in frame: MapFrame, spacing: Double = 0.03, scoreLimit: Int = 400) -> Pool {
        var points:[String:CGPoint]=[:], fixed:[Park]=[], rest:[Park]=[]
        for place in places {
            guard points[place.id] == nil, let p=frame.point(place), frame.shows(p,margin:0.01) else { continue }
            points[place.id]=p
            if place.curated || place.isSavedSpot { fixed.append(place) } else { rest.append(place) }
        }
        let inView=fixed.count+rest.count
        if rest.count>scoreLimit {
            let known=rest.sorted { a,b in
                if a.darkSkyDesignated != b.darkSkyDesignated { return a.darkSkyDesignated }
                return a.bortleEstimate != b.bortleEstimate ? a.bortleEstimate<b.bortleEstimate : a.id<b.id
            }
            let pinned=Set(fixed.map(\.id))
            rest=MapThinning.thin(always:fixed,ranked:known,point:{ points[$0.id] ?? .zero },spacing:spacing,limit:scoreLimit+fixed.count).filter { !pinned.contains($0.id) }
        }
        return Pool(fixed:fixed,rest:rest,points:points,inView:inView)
    }
    /// The places drawn from a pool: the fixed ones, then the rest as `rank` orders them, thinned.
    static func shown(_ pool: Pool, spacing: Double = 0.03, limit: Int = 200, rank: ([Park]) -> [Park]) -> (places: [Park], inView: Int) {
        (MapThinning.thin(always:pool.fixed,ranked:rank(pool.rest),point:{ pool.points[$0.id] ?? .zero },spacing:spacing,limit:max(limit,pool.fixed.count)),pool.inView)
    }
    /// The circle `meters` around a place, as `steps` points on Earth (exact on any projection).
    static func circle(around centre: GeoPoint, meters: Double, steps: Int = 96) -> [GeoPoint] {
        let d=min(Double.pi,meters/1000/GeoPoint.earthRadiusKm), φ=centre.latitude*GeoPoint.radian, λ=centre.longitude*GeoPoint.radian
        let up=centre.unit, east=SIMD3(-sin(λ),cos(λ),0), north=SIMD3(-sin(φ)*cos(λ),-sin(φ)*sin(λ),cos(φ))
        return (0...max(3,steps)).map { i in
            let b=2*Double.pi*Double(i)/Double(max(3,steps))
            return GeoPoint(unit:up*cos(d)+(east*sin(b)+north*cos(b))*sin(d))
        }
    }
    /// The search radius around the starting point as drawn on a regional map (canvas units): nil on
    /// the world map (a few hundred kilometres is a speck there) or when the ring misses the view.
    static func ring(around origin: GeoPoint?, meters: Double, on frame: MapFrame) -> [CGPoint]? {
        guard let origin, meters>0, case .azimuthal=frame.projection else { return nil }
        let points=circle(around:origin,meters:meters).compactMap(frame.point)
        return points.contains { frame.shows($0) } ? points : nil
    }
    /// The faint stars behind a constellation or a trip: the curated parks on the lower 48's map (as
    /// they have always been drawn); on any other map, every catalogue place in view, thinned.
    static func background(_ places: [Park], in frame: MapFrame, spacing: Double = 0.012) -> [CGPoint] {
        let usual=frame == lower48
        let candidates=places.filter { !$0.isSavedSpot && (!usual || $0.curated) }
        let located=candidates.compactMap { place in frame.point(place).flatMap { frame.shows($0,margin:0.02) ? (place,$0) : nil } }
        guard !usual else { return located.map(\.1) }
        let points=Dictionary(located.map { ($0.0.id,$0.1) },uniquingKeysWith:{ a,_ in a })
        let ranked=located.map(\.0).sorted { (a: Park, b: Park) -> Bool in
            if a.curated != b.curated { return a.curated }
            return a.bortleEstimate != b.bortleEstimate ? a.bortleEstimate<b.bortleEstimate : a.id<b.id
        }
        let kept=MapThinning.thin(always:[],ranked:ranked,point:{ (place: Park) -> CGPoint in points[place.id] ?? .zero },spacing:spacing,limit:600)
        return kept.compactMap { points[$0.id] }
    }
}

/// Thinning a crowded map: places walked best first, each kept only when nothing kept before it
/// lies within `spacing`, so a map shows the darkest of each crowd and never thousands of marks.
nonisolated enum MapThinning {
    private struct Cell: Hashable { let x: Int; let y: Int }
    static func thin<T>(always: [T], ranked: [T], point: (T) -> CGPoint, spacing: Double, limit: Int) -> [T] {
        let size=max(1e-9,spacing)
        func cell(_ p: CGPoint) -> Cell { Cell(x:Int((p.x/size).rounded(.down)),y:Int((p.y/size).rounded(.down))) }
        var grid:[Cell:[CGPoint]]=[:], kept:[T]=[]
        func keep(_ item: T, _ p: CGPoint) { kept.append(item); grid[cell(p),default:[]].append(p) }
        for item in always { keep(item,point(item)) }
        for item in ranked {
            guard kept.count<limit else { break }
            let p=point(item), c=cell(p)
            var crowded=false
            search: for dx in -1...1 { for dy in -1...1 {
                for q in grid[Cell(x:c.x+dx,y:c.y+dy)] ?? [] where hypot(q.x-p.x,q.y-p.y)<spacing { crowded=true; break search }
            } }
            if !crowded { keep(item,p) }
        }
        return kept
    }
}

/// A logged night, as the constellation and the recap need it: plain values, so layout is pure.
nonisolated struct LoggedNight: Identifiable, Sendable, Hashable {
    let id: UUID
    let date: Date
    let parkID: String
    let observedBortle: Int
    /// That night's darkness score at the park (with its usual clouds; past clouds are not kept).
    var score: Int?
    /// What was written that night; only the on-device recap reads it, and only on this iPhone.
    var notes: String = ""
    /// The place's own zone; nil when the place is unknown here, and the device's zone stands in.
    var timeZone: TimeZone? = nil
    /// The Gregorian year of the night where it was spent.
    var year: Int { JournalYear.year(date, zone: timeZone ?? .current) }
}
/// A journal's years: the Gregorian year of each night in its own place's time zone, whatever
/// calendar the device uses (a Buddhist or Japanese calendar numbers years differently, and a
/// night in Hawaiʻi on New Year's Eve is still the old year there), written for the reader with
/// `Date.FormatStyle` ("2026", "2026年"), never as a bare number.
nonisolated enum JournalYear {
    static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar=Calendar(identifier: .gregorian)
        calendar.timeZone=zone
        return calendar
    }
    static func year(_ date: Date, zone: TimeZone) -> Int { calendar(zone).component(.year, from: date) }
    static func label(_ year: Int, locale: Locale = .current) -> String {
        let gregorian=calendar(.gmt)
        guard let midyear=gregorian.date(from: DateComponents(year: year, month: 7, day: 1, hour: 12)) else { return year.formatted(.number.grouping(.never)) }
        return midyear.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: gregorian, timeZone: .gmt).year())
    }
}
/// Meteorological seasons, as most people name them: winter runs December to February and
/// belongs to the year its January falls in.
nonisolated struct Season: Hashable, Comparable, Sendable {
    enum Kind: Int, Sendable { case winter, spring, summer, autumn }
    let year: Int
    let kind: Kind
    init(year: Int, kind: Kind) { self.year=year; self.kind=kind }
    init(_ date: Date, calendar: Calendar) {
        let month=calendar.component(.month,from:date), year=calendar.component(.year,from:date)
        switch month {
        case 12: self.init(year:year+1,kind:.winter)
        case 1,2: self.init(year:year,kind:.winter)
        case 3...5: self.init(year:year,kind:.spring)
        case 6...8: self.init(year:year,kind:.summer)
        default: self.init(year:year,kind:.autumn)
        }
    }
    var name: String {
        switch kind {
        case .winter: String(localized:"Winter \(JournalYear.label(year))")
        case .spring: String(localized:"Spring \(JournalYear.label(year))")
        case .summer: String(localized:"Summer \(JournalYear.label(year))")
        case .autumn: String(localized:"Autumn \(JournalYear.label(year))")
        }
    }
    static func < (a: Season, b: Season) -> Bool { (a.year,a.kind.rawValue)<(b.year,b.kind.rawValue) }
}

/// Your constellation: one star per logged night at its place on the map, brighter for a darker
/// night, and each season's stars joined into a figure. The map is the lower 48's while every
/// night lies on it (as it has always been drawn); otherwise it is fitted around the journal's
/// places, so a night in Namibia or on a saved spot abroad shines at its true place. Deterministic:
/// the same journal always draws the same sky.
nonisolated struct ConstellationLayout: Sendable {
    struct Star: Identifiable, Sendable {
        var id: UUID { night.id }
        let night: LoggedNight
        /// Canvas units on `frame`.
        let point: CGPoint
        /// 0.3…1.
        let brightness: Double
        let season: Season
    }
    struct Line: Sendable, Hashable { let from: CGPoint; let to: CGPoint; let season: Season
        static func == (a: Line, b: Line) -> Bool { a.from==b.from && a.to==b.to && a.season==b.season }
        func hash(into hasher: inout Hasher) { hasher.combine(from.x); hasher.combine(from.y); hasher.combine(to.x); hasher.combine(to.y); hasher.combine(season) }
    }
    let stars: [Star]
    let lines: [Line]
    /// Oldest first: the order in which the figures draw themselves.
    let seasons: [Season]
    /// The map the stars sit on.
    let frame: MapFrame
    /// True on the lower 48's map: every night there (or none, with a US starting point).
    var onLower48: Bool { frame == SkyMap.lower48 }
    /// Nights at the same park spiral out from it by the golden angle, this far apart (canvas units),
    /// so a favourite park becomes a small cluster rather than one overwritten star.
    static let clusterSpacing = 0.009

    /// `empty`: the map with no nights yet (the lower 48, or the starting point's own map).
    init(nights: [LoggedNight], parks: [Park], calendar: Calendar = .current, empty: MapFrame = SkyMap.lower48) {
        let byID=Dictionary(parks.map { ($0.id,$0) },uniquingKeysWith:{ first,_ in first })
        let ordered=nights.sorted(by:{ ($0.date,$0.id.uuidString)<($1.date,$1.id.uuidString) }).compactMap { night in byID[night.parkID].map { (night,$0) } }
        let frame=Self.frame(places:ordered.map { GeoPoint($0.1) },empty:empty)
        var seen:[String:Int]=[:], stars:[Star]=[]
        for (night,park) in ordered {
            guard let base=frame.point(park) else { continue }
            let n=seen[park.id,default:0]; seen[park.id]=n+1
            let angle=Double(n)*2.399963, radius=Self.clusterSpacing*Double(n).squareRoot()
            stars.append(Star(night:night,point:CGPoint(x:base.x+radius*cos(angle),y:base.y+radius*sin(angle)),
                              brightness:Self.brightness(bortle:night.observedBortle,score:night.score),season:Season(night.date,calendar:JournalYear.calendar(park.timeZone))))
        }
        self.frame=frame
        self.stars=stars
        seasons=Array(Set(stars.map(\.season))).sorted()
        lines=seasons.flatMap { season in Self.figure(stars.filter { $0.season==season }.map(\.point)).map { Line(from:$0.0,to:$0.1,season:season) } }
    }
    /// The lower 48's map while every place lies on it; otherwise the smallest map around them all
    /// (never narrower than 1,200 km, so one night abroad shows its country, not a field).
    static func frame(places: [GeoPoint], empty: MapFrame = SkyMap.lower48) -> MapFrame {
        guard !places.isEmpty else { return empty }
        if places.allSatisfy({ SkyMap.lower48.shows($0) }) { return SkyMap.lower48 }
        return MapFrame.fitting(places,aspect:SkyMap.aspect,padding:0.12,minimumKm:1200)
    }
    /// Observed darkness leads (what you saw), the night's score follows (what the Moon allowed).
    static func brightness(bortle: Int, score: Int?) -> Double {
        let sky=Double(9-min(9,max(1,bortle)))/8
        let night=score.map { Double(min(100,max(0,$0)))/100 } ?? sky
        return 0.3+0.7*(0.6*sky+0.4*night)
    }
    /// A season's figure: the minimum spanning tree of its stars (Prim, from the first night), the
    /// way real constellation figures join near neighbours without crossing the sky.
    static func figure(_ points: [CGPoint]) -> [(CGPoint, CGPoint)] {
        guard points.count>1 else { return [] }
        var inTree=[0], edges:[(CGPoint,CGPoint)]=[]
        var rest=Array(1..<points.count)
        func distance(_ a: Int, _ b: Int) -> Double { hypot(points[a].x-points[b].x,points[a].y-points[b].y) }
        while !rest.isEmpty {
            var best:(from:Int,to:Int,d:Double)?
            for a in inTree { for (i,b) in rest.enumerated() {
                let d=distance(a,b)
                if best == nil || d<(best?.d ?? .infinity) { best=(a,i,d) }
            } }
            guard let best else { break }
            let b=rest.remove(at:best.to)
            edges.append((points[best.from],points[b])); inTree.append(b)
        }
        return edges
    }
}

/// "7 of 63 national park skies": each park you have logged a night in, with the darkest sky you
/// observed there. A count, never a score to chase.
nonisolated struct SkiesSeen: Sendable {
    struct Place: Identifiable, Sendable { let id: String; let name: String; let darkestBortle: Int; let nights: Int }
    let parks: [Place]
    let total: Int
    init(nights: [LoggedNight], parks all: [Park]) {
        total=all.count
        let groups=Dictionary(grouping:nights,by:\.parkID)
        parks=all.compactMap { park in groups[park.id].map { Place(id:park.id,name:park.shortName,darkestBortle:$0.map(\.observedBortle).min() ?? 9,nights:$0.count) } }
            .sorted { ($0.darkestBortle,$0.name)<($1.darkestBortle,$1.name) }
    }
    var line: String { String(localized:"\(parks.count) of \(total) national park skies") }
}

/// A year under the stars, from the journal alone: nights out, places, the darkest sky observed,
/// the Moon's phases met, and the best meteor shower or eclipse you were out for. The template is
/// the honest fallback and the facts any on-device wording must keep.
nonisolated struct YearRecap: Sendable {
    struct Darkest: Sendable { let parkID: String; let parkName: String; let date: Date; let bortle: Int; let dateLabel: String }
    let year: Int
    let nights: Int
    let parkNames: [String]
    let newParkNames: [String]
    /// Every place of the year is a national park (a curated park, or a catalogue place of that kind),
    /// so the words can say "national parks"; otherwise they say "places".
    let allNationalParks: Bool
    let darkest: Darkest?
    /// Indices 0…7, new moon first, as `YearRecap.phaseIndex` numbers them.
    let phases: Set<Int>
    let event: String?

    init(year: Int, nights all: [LoggedNight], parks: [Park], calendar: Calendar = .current, astronomy: AstronomyEngine = AstronomyEngine()) {
        self.year=year
        let byID=Dictionary(parks.map { ($0.id,$0) },uniquingKeysWith:{ first,_ in first })
        let known=all.filter { byID[$0.parkID] != nil }
        // The night's Gregorian year where it was spent; `calendar`'s zone only for a place unknown here.
        func yearOf(_ night: LoggedNight) -> Int { JournalYear.year(night.date, zone: byID[night.parkID]?.timeZone ?? night.timeZone ?? calendar.timeZone) }
        let nights=known.filter { yearOf($0)==year }.sorted { $0.date<$1.date }
        self.nights=nights.count
        let visited=Array(Set(nights.map(\.parkID)))
        allNationalParks=visited.allSatisfy { byID[$0]?.kind == .nationalPark }
        let before=Set(known.filter { yearOf($0)<year }.map(\.parkID))
        parkNames=visited.compactMap { byID[$0]?.shortName }.sorted()
        newParkNames=visited.filter { !before.contains($0) }.compactMap { byID[$0]?.shortName }.sorted()
        let dark=nights.min { a,b in (a.observedBortle,-(a.score ?? 0),a.date)<(b.observedBortle,-(b.score ?? 0),b.date) }
        darkest=dark.flatMap { night in byID[night.parkID].map { Darkest(parkID:$0.id,parkName:$0.shortName,date:night.date,bortle:night.observedBortle,dateLabel:$0.dateLabel(night.date)) } }
        var phases=Set<Int>(), best:(rank:Double,text:String)?
        for night in nights {
            guard let park=byID[night.parkID] else { continue }
            let sky=astronomy.conditions(for:park,on:park.evening(night.date))
            phases.insert(Self.phaseIndex(sky.moon.fraction))
            let events=WhatsUp.Events(park:park,sky:sky)
            // An eclipse you could see outranks any shower; then the shower with the higher published rate.
            if let eclipse=events.eclipse, eclipse.visible != nil {
                // Whole sentences per type: lowercasing the eclipse's title would break "Luna" in Spanish.
                let text=switch eclipse.eclipse.type {
                case "total": String(localized:"You were out for the total lunar eclipse at \(park.shortName).")
                case "partial": String(localized:"You were out for the partial lunar eclipse at \(park.shortName).")
                default: String(localized:"You were out for the penumbral lunar eclipse at \(park.shortName).")
                }
                if (best?.rank ?? -1)<1000 { best=(1000,text) }
            } else if let shower=events.shower, shower.isPeakNight, WhatsUp.Events.isNotable(shower.shower), shower.shower.zhr>(best?.rank ?? -1) {
                best=(shower.shower.zhr,String(localized:"You were out for the \(shower.shower.localizedName) peak at \(park.shortName)."))
            }
        }
        self.phases=phases
        event=best?.text
    }
    /// The eight named phases, with the same boundaries as `MoonPhase.name`.
    static func phaseIndex(_ fraction: Double) -> Int {
        switch fraction {
        case ..<0.03, 0.97...: 0
        case ..<0.22: 1
        case ..<0.28: 2
        case ..<0.47: 3
        case ..<0.53: 4
        case ..<0.72: 5
        case ..<0.78: 6
        default: 7
        }
    }
    /// The phase each index names, mid-phase, for drawing the row of eight Moons.
    static func phaseFraction(_ index: Int) -> Double { [0.0,0.125,0.25,0.375,0.5,0.625,0.75,0.875][max(0,min(7,index))] }
    /// The deterministic recap, in Nyx's voice. Every sentence is a fact from the journal.
    var template: String {
        guard nights>0 else { return String(localized:"No nights recorded in \(JournalYear.label(year)) yet. Your first night will be your first star.") }
        var lines:[String]=[]
        let nightsText=nights==1 ? String(localized:"one night") : String(localized:"\(nights) nights")
        let parksText=allNationalParks
            ? (parkNames.count==1 ? String(localized:"one national park") : String(localized:"\(parkNames.count) national parks"))
            : (parkNames.count==1 ? String(localized:"one place") : String(localized:"\(parkNames.count) places"))
        switch newParkNames.count {
        case 0: lines.append(String(localized:"In \(JournalYear.label(year)) you spent \(nightsText) under the stars in \(parksText)."))
        case parkNames.count: lines.append(String(localized:"In \(JournalYear.label(year)) you spent \(nightsText) under the stars in \(parksText), each one new to you."))
        default: lines.append(String(localized:"In \(JournalYear.label(year)) you spent \(nightsText) under the stars in \(parksText), \(newParkNames.count) of them new to you."))
        }
        if let darkest { lines.append(String(localized:"Your darkest sky was \(darkest.parkName) on \(darkest.dateLabel): Bortle \(darkest.bortle), as you saw it.")) }
        lines.append(phases.count==8 ? String(localized:"You met all eight of the Moon's phases.") : phases.count==1 ? String(localized:"You met one of the Moon's eight phases.") : String(localized:"You met \(phases.count) of the Moon's eight phases."))
        if let event { lines.append(event) }
        return Sentences.join(lines)
    }
    /// Facts for the on-device model, one per line, never more than the template already says.
    var facts: [String] {
        var facts=[String(localized:"Year: \(JournalYear.label(year))"),String(localized:"Nights recorded: \(nights)"),allNationalParks ? String(localized:"Parks: \(Phrase.list(parkNames))") : String(localized:"Places: \(Phrase.list(parkNames))")]
        if !newParkNames.isEmpty { facts.append(allNationalParks ? String(localized:"New parks this year: \(Phrase.list(newParkNames))") : String(localized:"New places this year: \(Phrase.list(newParkNames))")) }
        if let darkest { facts.append(String(localized:"Darkest observed sky: \(darkest.parkName), \(darkest.dateLabel), Bortle \(darkest.bortle)")) }
        facts.append(String(localized:"Moon phases met: \(phases.count) of 8"))
        if let event { facts.append(event) }
        return facts
    }
}

/// First light: the first time Nyx opens at a park after astronomical dusk, once per park.
nonisolated enum FirstLight {
    static func key(_ parkID: String) -> String { "firstLight.\(parkID)" }
    /// True darkness has begun and the night is not yet over, and this park has not had its moment.
    static func shouldShow(sky: SkyConditions, now: Date, alreadySeen: Bool) -> Bool {
        guard !alreadySeen, let darkStart=sky.darkStart, sky.darkHours>0 else { return false }
        return now>=darkStart && now<(sky.darkEnd ?? sky.sunrise ?? sky.end)
    }
}
