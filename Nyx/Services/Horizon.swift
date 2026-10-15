import Foundation

/// The real terrain horizon around the curated parks' viewing spots and park points, bundled as
/// `horizons.json`: for each, the ground elevation and the highest terrain in each 5° of azimuth,
/// out to 100 km, seen from 1.7 m above the ground, with Earth's curvature and standard refraction.
/// From USGS 3DEP (bare earth, public domain), checked against Copernicus WorldDEM-30/90, which also
/// fills the few samples over water. Terrain only: trees and buildings, and anything within 300 m,
/// are not in it, and a place where the two elevation models disagreed is left out (no profile, so
/// nothing is said about its horizon).
nonisolated struct Horizon: Sendable, Equatable {
    /// Metres above sea level.
    let elevation: Double
    /// Degrees above the astronomical horizon, highest within each 5° of azimuth from true north,
    /// clockwise (bin i covers i·5° to i·5° + 5°).
    let bins: [Double]
    /// The terrain's height toward an azimuth (degrees).
    func altitude(toward azimuth: Double) -> Double {
        guard !bins.isEmpty else { return 0 }
        let a = (azimuth.truncatingRemainder(dividingBy: 360)+360).truncatingRemainder(dividingBy: 360)
        return bins[min(bins.count-1, Int(a/(360/Double(bins.count))))]
    }
    /// The highest terrain all round and where it lies.
    var highest: (altitude: Double, azimuth: Double) {
        let i = bins.indices.max { bins[$0] < bins[$1] } ?? 0
        return (bins.isEmpty ? 0 : bins[i], (Double(i)+0.5)*360/Double(max(1, bins.count)))
    }

    /// The bundled profiles by park id: the park's own point and its spots by exact name.
    nonisolated struct Table: Sendable {
        nonisolated struct Entry: Decodable, Sendable { let park: Raw?; let spots: [String: Raw]? }
        nonisolated struct Raw: Decodable, Sendable { let e: Double; let h: [Int] }
        let places: [String: Entry]
        static let shared: Table = load() ?? Table(places: [:])
        /// Nil where the file is not bundled (the widgets).
        static func load(bundle: Bundle = .main) -> Table? {
            guard let url = bundle.url(forResource: "horizons", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
            struct File: Decodable { let places: [String: Entry] }
            return (try? JSONDecoder().decode(File.self, from: data)).map { Table(places: $0.places) }
        }
        func spot(_ name: String, park id: String) -> Horizon? { places[id]?.spots?[name].map(Self.horizon) }
        func park(_ id: String) -> Horizon? { places[id]?.park.map(Self.horizon) }
        /// The horizon at the park's main viewing spot (`Park.forecastPoint`, its first spot) with
        /// the spot's name, else at the park's own point with no name; nil where neither has one.
        func main(_ park: Park) -> (horizon: Horizon, spot: String?)? {
            if let first = park.viewingSpots.first { return spot(first.name, park: park.id).map { ($0, first.name) } }
            return self.park(park.id).map { ($0, nil) }
        }
        private static func horizon(_ raw: Raw) -> Horizon { Horizon(elevation: raw.e, bins: raw.h.map { Double($0)/10 }) }
    }

    /// Terrain lower than this all round is said to be open.
    static let open = 3.0
    /// A body counts as clear of the terrain a degree above it.
    static let clearance = 1.0
}
