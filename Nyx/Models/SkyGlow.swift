import Foundation

/// Artificial sky glow from NASA Black Marble night lights (VNP46A4, Román et al. 2018), bundled
/// as `skyglow.json` by `Scripts/build_skyglow.py`. Method, calibration and limits: Research/skyglow.md.
/// `glow` is relative (the median national-park centre is 1) and ranks places; it is not a
/// measurement of sky brightness, so the app shows it only as a comparison between parks.
/// The score keeps the hand Bortle estimate (DECISIONS, "Every sky").
nonisolated struct SkyGlow: Sendable {
    /// A light dome: the bearing (degrees from north, clockwise) of a cluster of light and its share
    /// of the site's modelled glow. `city` is named only when a known town lies within 40 km of it.
    nonisolated struct Dome: Codable, Hashable, Sendable {
        let bearing: Double
        let share: Double
        let city: String?
    }
    /// Summed night lights within 150 km, 2013 and 2025. Inflated by product differences (median +34%),
    /// so only a park's rank among parks is ever shown.
    nonisolated struct Trend: Codable, Hashable, Sendable {
        let early: Double
        let late: Double
        let percent: Double
    }
    /// A park centre (with its spots and trend) or a viewing spot (with its name).
    nonisolated struct Site: Codable, Hashable, Sendable {
        var name: String?=nil
        let glow: Double
        let bortle: Double
        let profile: [Int]
        let domes: [Dome]
        var trend: Trend?=nil
        var spots: [Site]?=nil
    }
    let parks: [String: Site]
    /// Park-centre glows, ascending: the scale every level is read against.
    private let ladder: [Double]

    init(parks: [String: Site]) {
        self.parks=parks
        ladder=parks.values.map(\.glow).sorted()
    }
    static let shared: SkyGlow = (try? load()) ?? SkyGlow(parks:[:])
    static func load(bundle: Bundle = .main) throws -> SkyGlow {
        guard let url=bundle.url(forResource:"skyglow",withExtension:"json") else { throw CocoaError(.fileNoSuchFile) }
        struct File: Decodable { let parks: [String: Site] }
        return SkyGlow(parks:try JSONDecoder().decode(File.self,from:Data(contentsOf:url)).parks)
    }
    func park(_ id: String) -> Site? { parks[id] }
    /// A park's light domes for the real sky behind every screen.
    static func lightSources(_ park: Park) -> [SkyProjection.LightSource] {
        guard let site=shared.park(park.id) else { return [] }
        return site.domes.map { SkyProjection.LightSource(bearing:$0.bearing,share:$0.share,glow:site.glow) }
    }
    /// Joined by exact spot name, as in `parks.json`.
    func spot(_ name: String, park id: String) -> Site? { parks[id]?.spots?.first { $0.name==name } }

    // MARK: Levels

    /// Five steps, by where a glow falls among the 63 park centres (fifths). A spot is read on the same scale.
    func level(_ glow: Double) -> Int {
        guard !ladder.isEmpty else { return 3 }
        let below=ladder.filter { $0<glow }.count
        return min(5,1+Int(Double(below)/Double(ladder.count)*5))
    }
    static func levelLabel(_ level: Int) -> String {
        switch level {
        case ...1: String(localized:"Among the darkest national parks")
        case 2: String(localized:"Darker than most national parks")
        case 3: String(localized:"Typical of the national parks")
        case 4: String(localized:"Brighter than most national parks")
        default: String(localized:"Among the brightest national parks")
        }
    }
    /// How a spot compares with its park's centre, when the difference is worth saying (beyond ±40%).
    static func comparison(spot: Double, park: Double) -> String? {
        guard park>0 else { return nil }
        let ratio=spot/park
        if ratio<1/1.4 { return String(localized:"Darker than the park's center") }
        if ratio>1.4 { return String(localized:"Brighter than the park's center") }
        return nil
    }

    // MARK: Light domes

    /// Eight compass points: finer would claim more than a 30° smoothing window can tell.
    static func direction(_ bearing: Double) -> String {
        let index=Int(((bearing.truncatingRemainder(dividingBy:360)+360).truncatingRemainder(dividingBy:360)/45).rounded())%8
        return [String(localized:"north"),String(localized:"northeast"),String(localized:"east"),String(localized:"southeast"),
                String(localized:"south"),String(localized:"southwest"),String(localized:"west"),String(localized:"northwest")][index]
    }
    /// "Las Vegas, east", or "a town to the west" when no listed town is near the light.
    static func place(_ dome: Dome) -> String {
        guard let city=dome.city, !city.isEmpty else { return String(localized:"a town to the \(direction(dome.bearing))") }
        return String(localized:"\(city), \(direction(dome.bearing))")
    }
    /// The domes worth naming, strongest first. A town matched twice (two sectors near one place)
    /// is named once: the second sector's light is real, but the name would be a guess.
    static func namedDomes(_ domes: [Dome]) -> [Dome] {
        var seen=Set<String>()
        return domes.sorted { $0.share>$1.share }.filter { dome in
            guard let city=dome.city else { return true }
            return seen.insert(city).inserted
        }
    }
    /// "Glow on the horizon: Las Vegas, east (45% of this park's light pollution)." then "Also: …" lines.
    static func domeLines(_ domes: [Dome]) -> [String] {
        namedDomes(domes).enumerated().map { index,dome in
            let share=dome.share.formatted(.percent.precision(.fractionLength(0)))
            return index==0 ? String(localized:"Glow on the horizon: \(place(dome)) (\(share) of this park's light pollution).")
                : String(localized:"Also: \(place(dome)) (\(share)).")
        }
    }

    // MARK: Over time

    /// Parks whose 2013–2025 change is not light pollution or not comparable (Research/skyglow.md):
    /// all of Alaska (gap-filled, aurora and snow-window noise on sub-nanowatt cells), Hawaiʻi
    /// Volcanoes (lava), Carlsbad Caverns and Guadalupe Mountains (Permian Basin flaring),
    /// Theodore Roosevelt (Bakken flaring, which fell) and American Samoa (almost no light at all).
    static let trendExcluded: Set<String>=["dena","gaar","glba","katm","kefj","kova","lacl","wrst","havo","cave","gumo","thro","npsa"]
    /// Below this much light within 150 km (nW cm⁻² sr⁻¹ km²), one settlement or sensor noise decides the change.
    static let trendMinimumBase=1500.0
    enum TrendRank: Sendable { case faster, slower }
    /// Only the outer thirds are named: the data can rank, not measure, and the middle is too close to call.
    func trendRank(_ id: String) -> TrendRank? {
        let eligible=parks.filter { !Self.trendExcluded.contains($0.key) && ($0.value.trend?.early ?? 0)>=Self.trendMinimumBase }
            .compactMap { key,site in site.trend.map { (key,$0.percent) } }.sorted { $0.1<$1.1 }
        guard eligible.count>=6, let position=eligible.firstIndex(where:{ $0.0==id }) else { return nil }
        let third=eligible.count/3
        if position<third { return .slower }
        if position>=eligible.count-third { return .faster }
        return nil
    }
    static func trendSentence(_ rank: TrendRank) -> String {
        switch rank {
        case .faster: String(localized:"Night lights around this park grew faster than around most parks between 2013 and 2025.")
        case .slower: String(localized:"Night lights around this park grew more slowly than around most parks between 2013 and 2025.")
        }
    }
}

/// Step-free access at a viewing spot, from nps.gov accessibility pages (retrieved 2026-10-05;
/// Research/accessible-spots.md). A claim is recorded only where an official page makes it.
nonisolated struct SpotAccess: Codable, Hashable, Sendable {
    enum Level: String, Codable, Sendable { case yes, partial, no, unknown }
    let park: String
    let spot: String
    let stepFree: Level
    let features: [String]
    var sourceURL: String?=nil
    var evidence: String?=nil
    var note: String?=nil

    /// Nothing for unknown: silence is more honest than "unknown access" on every row.
    var summary: String? {
        let list=features.compactMap(Self.word).formatted(.list(type:.and))
        switch stepFree {
        case .yes: return list.isEmpty ? String(localized:"Step-free") : String(localized:"Step-free: \(list)")
        case .partial: return list.isEmpty ? String(localized:"Partly step-free") : String(localized:"Partly step-free: \(list)")
        case .no: return String(localized:"Steps or trail")
        case .unknown: return nil
        }
    }
    var symbol: String { stepFree == .no ? "figure.stairs" : "figure.roll" }
    var source: URL? { sourceURL.flatMap(URL.init(string:)) }
    private static func word(_ feature: String) -> String? {
        switch feature {
        case "accessibleParking": String(localized:"accessible parking")
        case "accessibleRestroom": String(localized:"accessible restroom")
        case "pavedPath": String(localized:"paved path")
        case "amphitheater": String(localized:"accessible amphitheater")
        case "viewFromVehicle": String(localized:"view from your vehicle")
        default: nil
        }
    }
}
nonisolated struct AccessData: Sendable {
    let spots: [SpotAccess]
    static let shared: AccessData = (try? load()) ?? AccessData(spots:[])
    static func load(bundle: Bundle = .main) throws -> AccessData {
        guard let url=bundle.url(forResource:"accessible-spots",withExtension:"json") else { throw CocoaError(.fileNoSuchFile) }
        struct File: Decodable { let spots: [SpotAccess] }
        return AccessData(spots:try JSONDecoder().decode(File.self,from:Data(contentsOf:url)).spots)
    }
    func access(park id: String, spot name: String) -> SpotAccess? { spots.first { $0.park==id && $0.spot==name } }
    /// The Parks filter: at least one spot documented as step-free or partly step-free.
    func hasStepFreeViewing(_ id: String) -> Bool { spots.contains { $0.park==id && ($0.stepFree == .yes || $0.stepFree == .partial) } }
}
