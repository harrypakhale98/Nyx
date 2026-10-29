import Foundation
import Synchronization

/// The world catalogue as the planner reads it, built once off the main thread (`prepareCatalog`):
/// the places in file order, a lookup by id, a spatial index of 1° cells, folded search terms and
/// the forecast regions (`CatalogForecast.Regions`).
nonisolated struct PlaceCatalog: Sendable {
    let places: [Park]
    let regions: CatalogForecast.Regions
    private let byID: [String: Int]
    private let cells: [Cell: [Int]]
    private let terms: [Terms]
    static let empty=PlaceCatalog([])
    /// The bundled catalogue without the curated parks, built once per process (about 60 ms on a
    /// recent Mac: 20 to decode, 40 to fold the search terms) and kept: every model shares it.
    static func bundled(excluding curated: Set<String>) -> PlaceCatalog {
        if let kept=store.withLock({ $0 }), kept.excluded == curated { return kept.catalog }
        let built=PlaceCatalog(((try? CatalogData.load()) ?? []).filter { !curated.contains($0.id) })
        // A failed read (no file) is not kept, so a later model tries again.
        if !built.places.isEmpty { store.withLock { $0=(curated,built) } }
        return built
    }
    private static let store=Mutex<(excluded: Set<String>, catalog: PlaceCatalog)?>(nil)
    /// One degree of latitude and longitude: rows −90…89, columns −180…179.
    nonisolated struct Cell: Hashable, Sendable {
        let row: Int
        let column: Int
        init(row: Int, column: Int) { self.row=row; self.column=Cell.wrap(column) }
        init(latitude: Double, longitude: Double) {
            self.init(row: min(89, max(-90, Int(latitude.rounded(.down)))), column: Int(longitude.rounded(.down)))
        }
        static func wrap(_ column: Int) -> Int { ((column+180)%360+360)%360-180 }
    }
    init(_ places: [Park], locale: Locale = .current) {
        var seen=Set<String>()
        let unique=places.filter { $0.latitude.isFinite && $0.longitude.isFinite && seen.insert($0.id).inserted }
        self.places=unique
        byID=Dictionary(unique.indices.map { (unique[$0].id,$0) },uniquingKeysWith:{ first,_ in first })
        var cells: [Cell: [Int]]=[:]
        for (index,place) in unique.enumerated() { cells[Cell(latitude: place.latitude, longitude: place.longitude),default:[]].append(index) }
        self.cells=cells
        terms=unique.map { Terms($0, locale: locale) }
        regions=CatalogForecast.Regions(unique)
    }
    func place(_ id: String) -> Park? { byID[id].map { places[$0] } }
    /// The places within `radiusMeters` (great-circle) of a point, in file order: only the 1° cells the
    /// circle can reach are read (every column near a pole or for a radius past a quarter of the Earth).
    func nearby(latitude: Double, longitude: Double, radiusMeters: Double) -> [Park] {
        guard !places.isEmpty, latitude.isFinite, longitude.isFinite, radiusMeters.isFinite, radiusMeters>=0 else { return [] }
        let angle=radiusMeters/Park.earthRadius, degrees=angle*180 / .pi+1e-6
        let rows=Int(max(-90, latitude-degrees).rounded(.down))...Int(min(89.999_999, latitude+degrees).rounded(.down))
        let ratio=sin(min(angle, .pi/2))/cos(latitude * .pi/180)
        let columns: [Int]
        if angle >= .pi/2 || latitude+degrees >= 90 || latitude-degrees <= -90 || !(ratio<1) {
            columns=Array(-180...179)
        } else {
            let span=asin(ratio)*180 / .pi+1e-6
            let low=Int((longitude-span).rounded(.down)), high=Int((longitude+span).rounded(.down))
            columns=high-low >= 359 ? Array(-180...179) : Array(Set((low...high).map(Cell.wrap)))
        }
        var found: [Int]=[]
        for row in rows { for column in columns { if let indices=cells[Cell(row: row, column: column)] { found += indices } } }
        return found.sorted().map { places[$0] }.filter { $0.distanceMeters(latitude: latitude, longitude: longitude)<=radiusMeters }
    }
    /// Every place matching an already folded query, with its rank (`Terms.rank`).
    func search(_ needle: String) -> [(Park, Int)] {
        guard !needle.isEmpty else { return [] }
        return zip(places, terms).compactMap { place, terms in terms.rank(needle).map { (place,$0) } }
    }
    /// A place's name (and short name and aliases), region and country (in the reader's language), folded once.
    /// A place shown in the app's language is found by its English name and region too (`Place.searchNames`).
    nonisolated struct Terms: Sendable {
        let names: [String]
        let others: [String]
        init(_ place: Park, locale: Locale = .current) {
            names=Array(Set(place.searchNames+(Park.aliases[place.id] ?? [])).map(Park.folded).filter { !$0.isEmpty }).sorted()
            let country=place.countryCode.isEmpty ? nil : locale.localizedString(forRegionCode: place.countryCode)
            others=(place.searchRegions+(country.map { [$0] } ?? [])).map(Park.folded).filter { !$0.isEmpty }
        }
        /// 0 the whole name, 1 a name beginning with the query, 2 a word of the name beginning with it,
        /// 3 the name containing it; 4 to 7 the same for the region or country; nil for no match.
        func rank(_ needle: String) -> Int? {
            func tier(_ terms: [String]) -> Int? {
                if terms.contains(needle) { return 0 }
                if terms.contains(where: { $0.hasPrefix(needle) }) { return 1 }
                if terms.contains(where: { $0.contains(" "+needle) }) { return 2 }
                if terms.contains(where: { $0.contains(needle) }) { return 3 }
                return nil
            }
            return tier(names) ?? tier(others).map { $0+4 }
        }
    }
}
