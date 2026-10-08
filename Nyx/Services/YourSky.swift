import Foundation
import CoreGraphics

/// The United States drawn as a sky: every national park at its place, in a canvas `aspect` times
/// as tall as it is wide. The lower 48 use an equirectangular projection with longitudes squeezed
/// by cos 37°, so the country keeps its familiar shape. Alaska, Hawaiʻi, American Samoa and the
/// Virgin Islands sit in insets in the empty sea, each projected on its own, as on any US map.
nonisolated enum SkyMap {
    /// A little deeper than the insets need, so their names fit beneath them.
    static let aspect = 0.63
    enum Region: CaseIterable, Sendable { case lower48, alaska, hawaii, samoa, virginIslands }
    struct Inset: Sendable {
        let region: Region
        /// In canvas units (x 0…1, y 0…aspect).
        let frame: CGRect
        let longitudes: ClosedRange<Double>
        let latitudes: ClosedRange<Double>
        var name: String {
            switch region {
            case .lower48: ""
            case .alaska: String(localized:"Alaska")
            case .hawaii: String(localized:"Hawaiʻi")
            case .samoa: String(localized:"Am. Samoa")
            case .virginIslands: String(localized:"Virgin Is.")
            }
        }
        /// The name in full, for VoiceOver: the drawn one is abbreviated to fit the map.
        var spokenName: String {
            switch region {
            case .samoa: String(localized:"American Samoa")
            case .virginIslands: String(localized:"U.S. Virgin Islands")
            default: name
            }
        }
    }
    static let insets: [Inset] = [
        Inset(region:.lower48,frame:CGRect(x:0.02,y:0.02,width:0.96,height:0.53),longitudes:(-125)...(-66.5),latitudes:24...49.5),
        Inset(region:.alaska,frame:CGRect(x:0.02,y:0.40,width:0.17,height:0.17),longitudes:(-166)...(-134),latitudes:56...70),
        Inset(region:.hawaii,frame:CGRect(x:0.20,y:0.47,width:0.08,height:0.08),longitudes:(-157.2)...(-154.6),latitudes:18.7...21.3),
        Inset(region:.samoa,frame:CGRect(x:0.32,y:0.50,width:0.05,height:0.05),longitudes:(-171)...(-169),latitudes:(-15)...(-13.5)),
        Inset(region:.virginIslands,frame:CGRect(x:0.88,y:0.47,width:0.06,height:0.06),longitudes:(-65.5)...(-64),latitudes:17.8...18.8),
    ]
    static func region(_ park: Park) -> Region {
        switch park.state { case "AK": .alaska; case "HI": .hawaii; case "AS": .samoa; case "VI": .virginIslands; default: .lower48 }
    }
    static func inset(_ region: Region) -> Inset { insets.first { $0.region==region } ?? insets[0] }
    /// A park's place on the canvas. Each region is fitted into its frame with its true aspect
    /// (longitude scaled by the cosine of the middle latitude) and centred, north up.
    static func position(_ park: Park) -> CGPoint { position(latitude:park.latitude,longitude:park.longitude,in:inset(region(park))) }
    static func position(latitude: Double, longitude: Double, in inset: Inset) -> CGPoint {
        let squeeze=cos((inset.latitudes.lowerBound+inset.latitudes.upperBound)/2 * .pi/180)
        let width=(inset.longitudes.upperBound-inset.longitudes.lowerBound)*squeeze, height=inset.latitudes.upperBound-inset.latitudes.lowerBound
        let scale=min(inset.frame.width/width,inset.frame.height/height)
        let x0=inset.frame.midX-width*scale/2, y0=inset.frame.midY-height*scale/2
        return CGPoint(x:x0+(longitude-inset.longitudes.lowerBound)*squeeze*scale,y:y0+(inset.latitudes.upperBound-latitude)*scale)
    }
    /// A region's coasts and borders in canvas units, drawn very faintly under the stars so they
    /// read as places. `clip` keeps an inset's outline inside its frame.
    struct Outline: Sendable {
        let region: Region
        let clip: CGRect
        let rings: [[CGPoint]]
    }
    /// US Census Bureau cartographic boundary cb_2023_us_nation_20m (public domain), simplified.
    /// Puerto Rico (the file's Caribbean region) has no national park and is left out; American
    /// Samoa and the Virgin Islands are too small at this scale to draw.
    static let outlines: [Outline] = outlines(from: Bundle.main.url(forResource: "us-outline", withExtension: "json"))
    static func outlines(from url: URL?) -> [Outline] {
        struct File: Decodable { let regions: [String: [[[Double]]]] }
        guard let url, let data=try? Data(contentsOf: url), let file=try? JSONDecoder().decode(File.self, from: data) else { return [] }
        let keys: [(String, Region)]=[("lower48", .lower48), ("alaska", .alaska), ("hawaii", .hawaii)]
        return keys.compactMap { key, region in
            guard let polygons=file.regions[key] else { return nil }
            let inset=inset(region)
            // Islands whose middle lies outside the inset's range (Kauaʻi, the Alexander
            // Archipelago's outer islands) would only show as fragments at the frame's edge.
            let rings=polygons.compactMap { ring -> [CGPoint]? in
                let points=ring.filter { $0.count==2 }
                guard points.count>2 else { return nil }
                let lon=points.map { $0[0] }.reduce(0, +)/Double(points.count), lat=points.map { $0[1] }.reduce(0, +)/Double(points.count)
                guard inset.longitudes.contains(lon), inset.latitudes.contains(lat) else { return nil }
                return points.map { position(latitude: $0[1], longitude: $0[0], in: inset) }
            }
            let clip=region == .lower48 ? CGRect(x: 0, y: 0, width: 1, height: aspect) : inset.frame.insetBy(dx: -0.004, dy: -0.004)
            return rings.isEmpty ? nil : Outline(region: region, clip: clip, rings: rings)
        }
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
        case .winter: String(localized:"Winter \(String(year))")
        case .spring: String(localized:"Spring \(String(year))")
        case .summer: String(localized:"Summer \(String(year))")
        case .autumn: String(localized:"Autumn \(String(year))")
        }
    }
    static func < (a: Season, b: Season) -> Bool { (a.year,a.kind.rawValue)<(b.year,b.kind.rawValue) }
}

/// Your constellation: one star per logged night at its park's place on the sky map, brighter for a
/// darker night, and each season's stars joined into a figure. Deterministic: the same journal
/// always draws the same sky.
nonisolated struct ConstellationLayout: Sendable {
    struct Star: Identifiable, Sendable {
        var id: UUID { night.id }
        let night: LoggedNight
        /// Canvas units, as `SkyMap`.
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
    /// Nights at the same park spiral out from it by the golden angle, this far apart (canvas units),
    /// so a favourite park becomes a small cluster rather than one overwritten star.
    static let clusterSpacing = 0.009

    init(nights: [LoggedNight], parks: [Park], calendar: Calendar = .current) {
        let byID=Dictionary(parks.map { ($0.id,$0) },uniquingKeysWith:{ first,_ in first })
        var seen:[String:Int]=[:], stars:[Star]=[]
        for night in nights.sorted(by:{ ($0.date,$0.id.uuidString)<($1.date,$1.id.uuidString) }) {
            guard let park=byID[night.parkID] else { continue }
            let n=seen[park.id,default:0]; seen[park.id]=n+1
            let base=SkyMap.position(park), angle=Double(n)*2.399963, radius=Self.clusterSpacing*Double(n).squareRoot()
            stars.append(Star(night:night,point:CGPoint(x:base.x+radius*cos(angle),y:base.y+radius*sin(angle)),
                              brightness:Self.brightness(bortle:night.observedBortle,score:night.score),season:Season(night.date,calendar:calendar)))
        }
        self.stars=stars
        seasons=Array(Set(stars.map(\.season))).sorted()
        lines=seasons.flatMap { season in Self.figure(stars.filter { $0.season==season }.map(\.point)).map { Line(from:$0.0,to:$0.1,season:season) } }
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

/// A year under the stars, from the journal alone: nights out, parks, the darkest sky observed,
/// the Moon's phases met, and the best meteor shower or eclipse you were out for. The template is
/// the honest fallback and the facts any on-device wording must keep.
nonisolated struct YearRecap: Sendable {
    struct Darkest: Sendable { let parkID: String; let parkName: String; let date: Date; let bortle: Int; let dateLabel: String }
    let year: Int
    let nights: Int
    let parkNames: [String]
    let newParkNames: [String]
    let darkest: Darkest?
    /// Indices 0…7, new moon first, as `YearRecap.phaseIndex` numbers them.
    let phases: Set<Int>
    let event: String?

    init(year: Int, nights all: [LoggedNight], parks: [Park], calendar: Calendar = .current, astronomy: AstronomyEngine = AstronomyEngine()) {
        self.year=year
        let byID=Dictionary(parks.map { ($0.id,$0) },uniquingKeysWith:{ first,_ in first })
        let known=all.filter { byID[$0.parkID] != nil }
        func yearOf(_ night: LoggedNight) -> Int { calendar.component(.year,from:night.date) }
        let nights=known.filter { yearOf($0)==year }.sorted { $0.date<$1.date }
        self.nights=nights.count
        let visited=Array(Set(nights.map(\.parkID)))
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
        guard nights>0 else { return String(localized:"No nights logged in \(String(year)) yet. Your first night will be your first star.") }
        var lines:[String]=[]
        let nightsText=nights==1 ? String(localized:"one night") : String(localized:"\(nights) nights")
        let parksText=parkNames.count==1 ? String(localized:"one national park") : String(localized:"\(parkNames.count) national parks")
        switch newParkNames.count {
        case 0: lines.append(String(localized:"In \(String(year)) you spent \(nightsText) under the stars in \(parksText)."))
        case parkNames.count: lines.append(String(localized:"In \(String(year)) you spent \(nightsText) under the stars in \(parksText), each one new to you."))
        default: lines.append(String(localized:"In \(String(year)) you spent \(nightsText) under the stars in \(parksText), \(newParkNames.count) of them new to you."))
        }
        if let darkest { lines.append(String(localized:"Your darkest sky was \(darkest.parkName) on \(darkest.dateLabel): Bortle \(darkest.bortle), as you saw it.")) }
        lines.append(phases.count==8 ? String(localized:"You met all eight of the Moon's phases.") : phases.count==1 ? String(localized:"You met one of the Moon's eight phases.") : String(localized:"You met \(phases.count) of the Moon's eight phases."))
        if let event { lines.append(event) }
        return lines.joined(separator:" ")
    }
    /// Facts for the on-device model, one per line, never more than the template already says.
    var facts: [String] {
        var facts=[String(localized:"Year: \(String(year))"),String(localized:"Nights logged: \(nights)"),String(localized:"Parks: \(parkNames.joined(separator:", "))")]
        if !newParkNames.isEmpty { facts.append(String(localized:"New parks this year: \(newParkNames.joined(separator:", "))")) }
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
