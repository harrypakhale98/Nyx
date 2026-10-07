import Foundation

/// A US city or town to measure distances from, when location is off or someone plans from home.
/// From the bundled Census list (`places.json`, built by `Scripts/build_places.py`): the 1,000 most
/// populous incorporated places and every state capital. Searched on this device; never fetched.
nonisolated struct StartingPlace: Codable, Hashable, Sendable, Identifiable {
    let name: String
    /// The two-letter postal code: "IL".
    let state: String
    let latitude: Double
    let longitude: Double
    var id: String { label }
    /// "Chicago, IL"
    var label: String { "\(name), \(state)" }
    /// "Chicago" finds Chicago; so do "chicago il", "Chicago, Illinois" and "Saint Paul" for "St. Paul".
    func matches(_ query: String) -> Bool { score(StartingPlaces.normalized(query)) != nil }
    /// Lower is a better match; nil for none. A name that starts with the query beats one that
    /// only contains it; the state, by code or by name, narrows but never matches on its own.
    fileprivate func score(_ needle: String) -> Int? {
        guard !needle.isEmpty else { return nil }
        let name=StartingPlaces.normalized(self.name), code=state.lowercased(), full=Park.folded(StartingPlaces.stateNames[state] ?? state)
        if name==needle { return 0 }
        for suffix in [code, full] where needle.hasSuffix(" "+suffix) {
            let city=String(needle.dropLast(suffix.count+1))
            if name==city { return 0 }
            if name.hasPrefix(city) { return 1 }
        }
        if name.hasPrefix(needle) { return 2 }
        if name.contains(needle) { return 3 }
        return nil
    }
    /// Straight-line distance to a park, in meters.
    func distanceMeters(to park: Park) -> Double { park.distanceMeters(latitude:latitude,longitude:longitude) }
}

nonisolated enum StartingPlaces {
    /// Every bundled place, most populous first.
    static let all: [StartingPlace] = load()
    static func load(bundle: Bundle = .main) -> [StartingPlace] {
        guard let url=bundle.url(forResource:"places",withExtension:"json"), let data=try? Data(contentsOf:url),
              let file=try? JSONDecoder().decode(File.self,from:data) else { return [] }
        return file.places
    }
    /// The best matches for a search, best first; ties keep population order. "St." reads as "Saint".
    static func search(_ query: String, in places: [StartingPlace] = all, limit: Int = 20) -> [StartingPlace] {
        let needle=normalized(query)
        guard !needle.isEmpty else { return [] }
        return places.enumerated().compactMap { index,place in place.score(needle).map { (place,$0,index) } }
            .sorted { ($0.1,$0.2)<($1.1,$1.2) }.prefix(limit).map(\.0)
    }
    /// The one place a name means, for Ask Nyx: an exact name (with or without its state) first,
    /// else the most populous place that starts with it. Nil for an empty or unknown name.
    static func named(_ text: String, in places: [StartingPlace] = all) -> StartingPlace? {
        guard let best=search(text,in:places,limit:1).first, let score=best.score(normalized(text)), score<=2 else { return nil }
        return best
    }
    /// Folded for search, with the usual abbreviations spelled out: "St." is "Saint", "Ft." "Fort", "Mt." "Mount".
    static func normalized(_ text: String) -> String {
        Park.folded(text).split(separator:" ").map { word in ["st":"saint","ft":"fort","mt":"mount"][String(word)] ?? String(word) }.joined(separator:" ")
    }
    static let stateNames: [String:String] = [
        "AL":"Alabama","AK":"Alaska","AZ":"Arizona","AR":"Arkansas","CA":"California","CO":"Colorado","CT":"Connecticut","DE":"Delaware",
        "DC":"District of Columbia","FL":"Florida","GA":"Georgia","HI":"Hawaii","ID":"Idaho","IL":"Illinois","IN":"Indiana","IA":"Iowa",
        "KS":"Kansas","KY":"Kentucky","LA":"Louisiana","ME":"Maine","MD":"Maryland","MA":"Massachusetts","MI":"Michigan","MN":"Minnesota",
        "MS":"Mississippi","MO":"Missouri","MT":"Montana","NE":"Nebraska","NV":"Nevada","NH":"New Hampshire","NJ":"New Jersey",
        "NM":"New Mexico","NY":"New York","NC":"North Carolina","ND":"North Dakota","OH":"Ohio","OK":"Oklahoma","OR":"Oregon",
        "PA":"Pennsylvania","RI":"Rhode Island","SC":"South Carolina","SD":"South Dakota","TN":"Tennessee","TX":"Texas","UT":"Utah",
        "VT":"Vermont","VA":"Virginia","WA":"Washington","WV":"West Virginia","WI":"Wisconsin","WY":"Wyoming",
    ]
    /// `{"places":[["Chicago","IL",41.837,-87.685],…]}`: compact rows, largest first.
    private struct File: Decodable {
        let places: [StartingPlace]
        enum Keys: String, CodingKey { case places }
        init(from decoder: any Decoder) throws {
            var rows=try decoder.container(keyedBy:Keys.self).nestedUnkeyedContainer(forKey:.places)
            var list:[StartingPlace]=[]
            while !rows.isAtEnd {
                var row=try rows.nestedUnkeyedContainer()
                list.append(StartingPlace(name:try row.decode(String.self),state:try row.decode(String.self),latitude:try row.decode(Double.self),longitude:try row.decode(Double.self)))
            }
            places=list
        }
    }
}
