import Foundation
import Synchronization

/// The bundled world grids (G2, `Research/global-plan.md`): the usual clouds and the night sky's
/// brightness for any point on land, read on this device from 10-degree tiles that
/// `Scripts/nyxgrid.py` writes (format 1: raw DEFLATE, a 16-byte header, one byte a cell, 255 for
/// no data). Nothing is fetched: a coordinate never leaves the device for this.
///
/// **Where the tiles are.** `Nyx/Resources/Grid/grid-<layer>-<n|s>DD-<e|w>DDD.bin`. The resources
/// folder is synchronized, and Xcode copies a synchronized subfolder's files to the bundle's root
/// (the Learn essays in `Resources/learn/` are read there too), so tiles are looked for at the root
/// and, should the folder ever be bundled as a folder, in `Grid/`. A tile with no land is not written.
///
/// **Cells.** Rows run north to south, each west to east. A cell holds its south and west edges:
/// from the tile's south edge, i = ⌊(lat − south)·cpd⌋ and row = side − 1 − i; col = ⌊(lon − west)·cpd⌋.
/// A tile's north and east edges belong to the next tile, except at 90° N and 180° E, which clamp
/// into the last tile as `nyxgrid.tile_corner` does. Longitudes outside ±180° wrap; latitudes outside
/// ±90° and non-finite values have no cell.
///
/// **Threads.** Decoded tiles are kept in a small cache behind a `Mutex` (the last `capacity` used,
/// 16 by default: at most a few megabytes). The synchronous reads decode a missing tile on the
/// caller's thread (about a millisecond); `prepare` decodes it off the caller's actor first.
nonisolated final class SkyGrid: Sendable {
    nonisolated enum Layer: String, CaseIterable, Hashable, Sendable {
        case clouds, sky
        /// The header's layer byte.
        var code: UInt8 { self == .clouds ? 1 : 2 }
        var bands: Int { self == .clouds ? 24 : 1 }
    }
    nonisolated struct Key: Hashable, Sendable {
        let layer: Layer
        let south: Int
        let west: Int
    }
    /// One decoded tile.
    nonisolated struct Tile: Sendable {
        let key: Key
        let cellsPerDegree: Int
        let bands: Int
        let cells: [UInt8]
        var side: Int { SkyGrid.tileDegrees*cellsPerDegree }
        /// Row and column of the cell holding a point (clamped into the tile).
        func cell(latitude: Double, longitude: Double) -> (row: Int, col: Int) {
            let cpd = Double(cellsPerDegree), side = side
            let i = min(side-1, max(0, Int(((latitude-Double(key.south))*cpd).rounded(.down))))
            let col = min(side-1, max(0, Int(((longitude-Double(key.west))*cpd).rounded(.down))))
            return (side-1-i, col)
        }
        /// A cell's value, nil for no data (255) or a band the tile lacks.
        func value(band: Int, row: Int, col: Int) -> UInt8? {
            guard band >= 0, band < bands, row >= 0, row < side, col >= 0, col < side else { return nil }
            let v = cells[band*side*side+row*side+col]
            return v == SkyGrid.noData ? nil : v
        }
        func value(band: Int, latitude: Double, longitude: Double) -> UInt8? {
            let at = cell(latitude: latitude, longitude: longitude)
            return value(band: band, row: at.row, col: at.col)
        }
        /// The centre of a cell.
        func centre(row: Int, col: Int) -> (latitude: Double, longitude: Double) {
            let cpd = Double(cellsPerDegree)
            return (Double(key.south)+(Double(side-1-row)+0.5)/cpd, Double(key.west)+(Double(col)+0.5)/cpd)
        }
        /// Format 1, checked: magic, format, layer, size and corner (the file's name must agree with
        /// its header). nil for anything else, so a damaged tile reads as no data, never as a sky.
        static func decode(_ data: Data, expecting key: Key) -> Tile? {
            guard let raw = try? (data as NSData).decompressed(using: .zlib) as Data, raw.count >= 16 else { return nil }
            let bytes = [UInt8](raw)
            guard bytes[0] == 0x4E, bytes[1] == 0x59, bytes[2] == 0x58, bytes[3] == 0x47, bytes[4] == 1, bytes[5] == key.layer.code else { return nil }
            let cpd = Int(bytes[6]), bands = Int(bytes[7])
            let south = Int(Int16(bitPattern: UInt16(bytes[8]) | UInt16(bytes[9]) << 8))
            let west = Int(Int16(bitPattern: UInt16(bytes[10]) | UInt16(bytes[11]) << 8))
            let side = SkyGrid.tileDegrees*cpd
            guard cpd > 0, bands >= key.layer.bands, south == key.south, west == key.west, bytes.count == 16+bands*side*side else { return nil }
            return Tile(key: key, cellsPerDegree: cpd, bands: bands, cells: Array(bytes[16...]))
        }
    }
    /// A stretch of dark sky found by `darkest`. Never named: a cell is land the grid says is dark,
    /// not a place anyone has checked for access, safety or a view.
    nonisolated struct DarkArea: Sendable, Hashable, Identifiable {
        let latitude: Double
        let longitude: Double
        /// Zenith sky brightness, mag/arcsec² (larger is darker).
        let magnitude: Double
        let bortle: Int
        let distanceMeters: Double
        var id: String { "\(latitude),\(longitude)" }
        /// What a dark area is called wherever it is shown.
        static var title: String { String(localized: "A dark area") }
    }

    static let tileDegrees = 10
    static let noData: UInt8 = 255
    /// The app's grids, from the main bundle.
    static let shared = SkyGrid()

    private let files: [Key: URL]
    private let capacity: Int
    private struct Cache {
        var tiles: [Key: Tile] = [:]
        /// Least recently used first.
        var order: [Key] = []
        /// Tiles that failed to decode, not tried again.
        var broken: Set<Key> = []
    }
    private let cache = Mutex(Cache())

    /// `layers` limits what is read (tests use it to stand for a bundle without one).
    init(bundle: Bundle = .main, layers: Set<Layer> = Set(Layer.allCases), capacity: Int = 16) {
        var files: [Key: URL] = [:]
        for directory in [nil, "Grid"] as [String?] {
            for url in bundle.urls(forResourcesWithExtension: "bin", subdirectory: directory) ?? [] {
                if let key = Self.key(fileName: url.deletingPathExtension().lastPathComponent), layers.contains(key.layer), files[key] == nil { files[key] = url }
            }
        }
        self.files = files
        self.capacity = max(1, capacity)
    }

    // MARK: Names and corners

    /// "grid-clouds-n30-w120", as `nyxgrid.tile_name` writes it.
    static func fileName(_ key: Key) -> String {
        "grid-\(key.layer.rawValue)-\(key.south >= 0 ? "n" : "s")\(String(format: "%02d", abs(key.south)))-\(key.west >= 0 ? "e" : "w")\(String(format: "%03d", abs(key.west)))"
    }
    static func key(fileName name: String) -> Key? {
        let parts = name.split(separator: "-")
        guard parts.count == 4, parts[0] == "grid", let layer = Layer(rawValue: String(parts[1])),
              let ns = parts[2].first, ns == "n" || ns == "s", let we = parts[3].first, we == "e" || we == "w",
              let lat = Int(parts[2].dropFirst()), let lon = Int(parts[3].dropFirst()) else { return nil }
        let key = Key(layer: layer, south: ns == "n" ? lat : -lat, west: we == "e" ? lon : -lon)
        guard fileName(key) == name, key.south % tileDegrees == 0, key.west % tileDegrees == 0, (-90...80).contains(key.south), (-180...170).contains(key.west) else { return nil }
        return key
    }
    /// A coordinate the grid can answer for: latitude within ±90°, longitude wrapped into ±180°.
    static func normalized(latitude: Double, longitude: Double) -> (latitude: Double, longitude: Double)? {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude) else { return nil }
        if (-180...180).contains(longitude) { return (latitude, longitude) }
        let wrapped = (longitude+180).truncatingRemainder(dividingBy: 360)
        return (latitude, (wrapped < 0 ? wrapped+360 : wrapped)-180)
    }
    /// The south-west corner of the tile holding a point: `nyxgrid.tile_corner` exactly, including
    /// Python's floor division, so app and build always pick the same tile.
    static func corner(latitude: Double, longitude: Double) -> (south: Int, west: Int) {
        func floorDiv(_ x: Double) -> Int {
            let step = Double(tileDegrees), mod = fmod(x, step)
            var div = (x-mod)/step
            if mod != 0, mod < 0 { div -= 1 }
            var floored = div.rounded(.down)
            if div-floored > 0.5 { floored += 1 }
            return Int(floored)
        }
        let south = floorDiv(latitude+90)*tileDegrees-90, west = floorDiv(longitude+180)*tileDegrees-180
        return (min(80, max(-90, south)), min(170, max(-180, west)))
    }

    // MARK: Reading

    /// Whether any tile of a layer is bundled. Without the sky layer, places keep the assumed or hand-checked Bortle.
    func hasLayer(_ layer: Layer) -> Bool { files.keys.contains { $0.layer == layer } }
    /// The tile holding a point, decoded on first use; nil at sea, off the grid or for a damaged file.
    func tile(_ layer: Layer, latitude: Double, longitude: Double) -> Tile? {
        guard let point = Self.normalized(latitude: latitude, longitude: longitude) else { return nil }
        let corner = Self.corner(latitude: point.latitude, longitude: point.longitude)
        return tile(Key(layer: layer, south: corner.south, west: corner.west))
    }
    func tile(_ key: Key) -> Tile? {
        guard let url = files[key] else { return nil }
        let kept: Tile?? = cache.withLock { cache in
            if cache.broken.contains(key) { return .some(nil) }
            guard let tile = cache.tiles[key] else { return nil }
            if let at = cache.order.firstIndex(of: key) { cache.order.remove(at: at) }
            cache.order.append(key)
            return .some(tile)
        }
        if let kept { return kept }
        // Decoded outside the lock; two threads may decode the same tile once each, never twice in the cache.
        let decoded = (try? Data(contentsOf: url, options: .mappedIfSafe)).flatMap { Tile.decode($0, expecting: key) }
        return cache.withLock { cache in
            guard let decoded else { cache.broken.insert(key); return nil }
            if let existing = cache.tiles[key] { return existing }
            cache.tiles[key] = decoded
            cache.order.append(key)
            while cache.order.count > capacity { cache.tiles[cache.order.removeFirst()] = nil }
            return decoded
        }
    }
    /// Whether the tile holding a point is already decoded (reading it then costs no decode).
    func isCached(_ layer: Layer, latitude: Double, longitude: Double) -> Bool {
        guard let point = Self.normalized(latitude: latitude, longitude: longitude) else { return false }
        let corner = Self.corner(latitude: point.latitude, longitude: point.longitude)
        let key = Key(layer: layer, south: corner.south, west: corner.west)
        return cache.withLock { $0.tiles[key] != nil }
    }
    /// Decodes the tile holding a point off the caller's actor, so the synchronous reads that
    /// follow find it cached. False when there is no tile there.
    @concurrent func prepare(_ layer: Layer, latitude: Double, longitude: Double) async -> Bool {
        tile(layer, latitude: latitude, longitude: longitude) != nil
    }
    /// The usual night for a month (1–12): the mean cloud over the dark hours, percent, and the
    /// estimated share of nights mostly clear (under 30%), percent. nil at sea or without data.
    func cloudNight(latitude: Double, longitude: Double, month: Int) -> (mean: Double, clear: Double)? {
        guard (1...12).contains(month), let point = Self.normalized(latitude: latitude, longitude: longitude),
              let tile = tile(.clouds, latitude: point.latitude, longitude: point.longitude) else { return nil }
        let at = tile.cell(latitude: point.latitude, longitude: point.longitude)
        guard let mean = tile.value(band: month-1, row: at.row, col: at.col), let clear = tile.value(band: 11+month, row: at.row, col: at.col),
              mean <= 100, clear <= 100 else { return nil }
        return (Double(mean), Double(clear))
    }
    /// The night sky's brightness at the zenith, mag/arcsec² (about 22 is pristine), modelled from
    /// satellite night lights; nil at sea or without the sky layer.
    func skyBrightness(latitude: Double, longitude: Double) -> Double? {
        guard let point = Self.normalized(latitude: latitude, longitude: longitude),
              let value = tile(.sky, latitude: point.latitude, longitude: point.longitude)?.value(band: 0, latitude: point.latitude, longitude: point.longitude) else { return nil }
        return Self.magnitude(value)
    }
    static func magnitude(_ value: UInt8) -> Double { 15+Double(value)/20 }

    // MARK: Bortle

    /// The Bortle class for a zenith brightness, by the SQM ranges commonly given for each class
    /// (Bortle 2001, Sky & Telescope; the ranges as tabulated by Dark Skies Awareness and the
    /// "Bortle scale" reference table): 1 from 21.76, 2 from 21.6, 3 from 21.3, 4 from 20.8,
    /// "4.5" from 20.3, 5 from 19.25, 6 from 18.5, 7 from 18.0, 8 below.
    ///
    /// Two choices keep it consistent with `Research/skyglow.md`: never 1, since satellite light
    /// cannot tell class 1 from 2 (skyglow.md's computed classes stop at about 2.1), and the "4.5"
    /// band is read as 5, the brighter neighbour, as the bundled estimates are conservative where
    /// unsure. The table gives no range for 9, so the grid says 8 at most; a city centre is 8 or 9 either way.
    static func bortle(fromMagnitude magnitude: Double) -> Int {
        guard magnitude.isFinite else { return 8 }
        switch magnitude {
        case 21.6...: return 2
        case 21.3...: return 3
        case 20.8...: return 4
        case 19.25...: return 5
        case 18.5...: return 6
        case 18.0...: return 7
        default: return 8
        }
    }
    /// The class for each stored sky value, worked out once.
    private static let bortleByValue: [Int] = (0...255).map { bortle(fromMagnitude: magnitude(UInt8($0))) }

    // MARK: Dark areas

    /// The darkest land within `radiusMeters` (great-circle, cell centres), darkest first and the
    /// nearer of equals first, at most `limit`, each at least `spacingMeters` from the ones before
    /// (by default a sixth of the radius, 10 km at least) so the list is not one patch's
    /// neighbours. Only cells of Bortle `atMostBortle` or darker count as "a dark area". Empty
    /// without the sky layer. Reads every cell in the search box: call it off the main thread.
    func darkest(near origin: (latitude: Double, longitude: Double), radiusMeters: Double, limit: Int = 3,
                 atMostBortle: Int = 4, spacingMeters: Double? = nil) -> [DarkArea] {
        guard limit > 0, radiusMeters.isFinite, radiusMeters > 0, let here = Self.normalized(latitude: origin.latitude, longitude: origin.longitude) else { return [] }
        let spacing = spacingMeters ?? max(10_000, radiusMeters/6)
        let reach = radiusMeters/111_194.93 // degrees of latitude (a 6,371,008.8 m sphere)
        let south = max(-90, here.latitude-reach), north = min(90, here.latitude+reach)
        let widest = max(abs(south), abs(north))
        let spanLon = widest >= 89.999 ? 180 : reach/max(cos(widest*Double.pi/180), 1e-6)
        var lonRanges: [ClosedRange<Double>] = []
        if spanLon >= 180 { lonRanges = [-180...180] } else {
            let lo = here.longitude-spanLon, hi = here.longitude+spanLon
            if lo < -180 { lonRanges = [(lo+360)...180, -180...hi] } else if hi > 180 { lonRanges = [lo...180, -180...(hi-360)] } else { lonRanges = [lo...hi] }
        }
        // The darkest cell of each quarter-degree block, then a spaced pick from the darkest blocks.
        struct Candidate { var value: UInt8; var latitude: Double; var longitude: Double; var distance: Double }
        var blocks: [Int: Candidate] = [:]
        var tileCorners: Set<Key> = []
        for range in lonRanges {
            let s0 = Self.corner(latitude: south, longitude: range.lowerBound), s1 = Self.corner(latitude: north, longitude: range.upperBound)
            for s in stride(from: s0.south, through: s1.south, by: Self.tileDegrees) {
                for w in stride(from: s0.west, through: s1.west, by: Self.tileDegrees) { tileCorners.insert(Key(layer: .sky, south: s, west: w)) }
            }
        }
        for key in tileCorners.sorted(by: { ($0.south, $0.west) < ($1.south, $1.west) }) {
            guard let tile = tile(key) else { continue }
            let cpd = Double(tile.cellsPerDegree), side = tile.side, block = max(1, tile.cellsPerDegree/4)
            let iLow = max(0, Int(((south-Double(key.south))*cpd).rounded(.down))), iHigh = min(side-1, Int(((north-Double(key.south))*cpd).rounded(.down)))
            guard iLow <= iHigh else { continue }
            for range in lonRanges {
                let cLow = max(0, Int(((range.lowerBound-Double(key.west))*cpd).rounded(.down))), cHigh = min(side-1, Int(((range.upperBound-Double(key.west))*cpd).rounded(.down)))
                guard cLow <= cHigh else { continue }
                for i in iLow...iHigh {
                    let row = side-1-i
                    for col in cLow...cHigh {
                        let value = tile.cells[row*side+col]
                        guard value != Self.noData, Self.bortleByValue[Int(value)] <= atMostBortle else { continue }
                        let id = ((key.south+90)*1000+(key.west+180))*1_000_000+(row/block)*1000+col/block
                        if let kept = blocks[id], kept.value > value { continue }
                        let centre = tile.centre(row: row, col: col)
                        let distance = Park.distance(here.latitude, here.longitude, centre.latitude, centre.longitude)
                        guard distance <= radiusMeters else { continue }
                        if let kept = blocks[id], kept.value == value, kept.distance <= distance { continue }
                        blocks[id] = Candidate(value: value, latitude: centre.latitude, longitude: centre.longitude, distance: distance)
                    }
                }
            }
        }
        let ranked = blocks.values.sorted { $0.value != $1.value ? $0.value > $1.value : $0.distance != $1.distance ? $0.distance < $1.distance : ($0.latitude, $0.longitude) < ($1.latitude, $1.longitude) }
        var picked: [DarkArea] = []
        for candidate in ranked where picked.count < limit {
            guard picked.allSatisfy({ Park.distance($0.latitude, $0.longitude, candidate.latitude, candidate.longitude) >= spacing }) else { continue }
            let magnitude = Self.magnitude(candidate.value)
            picked.append(DarkArea(latitude: candidate.latitude, longitude: candidate.longitude, magnitude: magnitude,
                                   bortle: Self.bortle(fromMagnitude: magnitude), distanceMeters: candidate.distance))
        }
        return picked
    }
}
