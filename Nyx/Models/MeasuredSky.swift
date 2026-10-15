import Foundation

/// Sky brightness measured on the ground by the National Park Service's Night Skies Program, bundled
/// as `nps-skies.json` (the Park Service's night-sky data map; a US Government work, public domain).
/// Each night is the median of that night's data sets from the Park Service's calibrated all-sky
/// camera, at a named site in one of the curated parks (53 of the 63; measured 2001 to 2025, most
/// before 2013).
/// Context beside the Bortle estimate, never part of the score: each site was measured on one night
/// or a few, often many years ago, and sky glow has grown since.
nonisolated struct MeasuredSky: Sendable {
    nonisolated struct Night: Codable, Hashable, Sendable {
        /// The park's local date the night began, `yyyy-MM-dd`.
        let date: String
        /// Zenith sky brightness in magnitudes per square arcsecond (V band), as a handheld Sky
        /// Quality Meter would read it: higher is darker; the darkest natural skies read about 22.
        let sqm: Double
        /// The observers' Bortle class for the night, when they gave one.
        var bortle: Int?=nil
        /// The observers' naked-eye limiting magnitude overhead, when they gave one.
        var zlm: Double?=nil
        var year: Int? { Int(date.prefix(4)) }
    }
    nonisolated struct Site: Codable, Hashable, Sendable {
        let name: String
        /// Absent where the map's positions for this site disagree by more than 2 km.
        var latitude: Double?=nil
        var longitude: Double?=nil
        /// Metres.
        var elevation: Int?=nil
        let nights: [Night]
        /// The most recent night measured here.
        var latest: Night? { nights.max { $0.date<$1.date } }
    }
    /// Park id → its sites, darkest latest reading first.
    let parks: [String: [Site]]

    init(parks: [String: [Site]]) {
        self.parks=parks.mapValues { sites in
            sites.filter { $0.latest != nil }.sorted { ($0.latest?.sqm ?? 0, $1.name)>($1.latest?.sqm ?? 0, $0.name) }
        }
    }
    static let shared: MeasuredSky = (try? load()) ?? MeasuredSky(parks:[:])
    static func load(bundle: Bundle = .main) throws -> MeasuredSky {
        guard let url=bundle.url(forResource:"nps-skies",withExtension:"json") else { throw CocoaError(.fileNoSuchFile) }
        struct File: Decodable { let parks: [String: [Site]] }
        return MeasuredSky(parks:try JSONDecoder().decode(File.self,from:Data(contentsOf:url)).parks)
    }
    func sites(_ park: String) -> [Site] { parks[park] ?? [] }
    /// The measured site within 1 km of a point (a viewing spot), nearest first; nil when none is.
    func site(near latitude: Double, _ longitude: Double, park: String) -> Site? {
        sites(park).compactMap { site -> (Site, Double)? in
            guard let lat=site.latitude, let lon=site.longitude else { return nil }
            let d=Self.distance(latitude,longitude,lat,lon)
            return d<=1000 ? (site,d) : nil
        }.min { $0.1<$1.1 }?.0
    }
    /// The years a park's measurements span, earliest and latest.
    func years(_ park: String) -> ClosedRange<Int>? {
        let years=sites(park).flatMap(\.nights).compactMap(\.year)
        guard let first=years.min(), let last=years.max() else { return nil }
        return first...last
    }
    /// Metres along the surface (haversine on a 6,371 km sphere).
    static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let p1=lat1 * .pi/180, p2=lat2 * .pi/180, dp=(lat2-lat1) * .pi/180, dl=(lon2-lon1) * .pi/180
        let h=sin(dp/2)*sin(dp/2)+cos(p1)*cos(p2)*sin(dl/2)*sin(dl/2)
        return 2*6_371_000*asin(min(1,sqrt(h)))
    }
    /// "21.8": one decimal, as the meters show it.
    static func reading(_ sqm: Double) -> String { sqm.formatted(.number.precision(.fractionLength(1))) }
    /// "2009", or "2005–2012" for a span; never grouped ("2,009").
    static func span(_ years: ClosedRange<Int>) -> String {
        let a=years.lowerBound.formatted(.number.grouping(.never)), b=years.upperBound.formatted(.number.grouping(.never))
        return a==b ? a : "\(a)\u{2060}–\u{2060}\(b)"
    }
}
