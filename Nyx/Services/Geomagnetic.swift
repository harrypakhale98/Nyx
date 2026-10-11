import Foundation

/// Where a place sits in Earth's magnetic field, for the aurora note. Aurora follows magnetic
/// latitude, not geographic latitude, so one rule serves both hemispheres.
///
/// `latitude` reads corrected geomagnetic latitude from the bundled 1° grid (`geomagnetic.bin`),
/// traced along the field lines of IGRF-14 at epoch 2025.0 from the aurora's lower edge (110 km);
/// it agrees with NASA's calculator to about 0.02° (Research/geomagnetic.md). When the file is
/// absent or fails any check (a target that bundles no grid), it falls back to the centred dipole,
/// `dipoleLatitude`. Only the fallback carries the dipole's regional bias: good across North
/// America, about 3–5° too high in Europe and 4–5° too low in Australasia (Hobart near −49°).
nonisolated enum Geomagnetic {
    /// The north geomagnetic (dipole) pole for epoch 2025.0, from the IGRF-14 dipole coefficients
    /// (g10, g11, h11): about 80.8° N, 72.8° W. Approximate. The dipole pole moves slowly (about
    /// 80.65° N, 72.7° W in 2020, so a few hundredths of a degree a year); the faster-moving magnetic
    /// dip pole is a different point and is not used here.
    static let poleLatitude = 80.8
    static let poleLongitude = -72.8

    /// The bundled grid, read once on first use; nil when the file is absent or unreadable.
    static let bundledGrid: Grid? = grid(in: .main)

    /// The grid in a bundle, or nil when it has none or the file fails a check.
    static func grid(in bundle: Bundle) -> Grid? {
        guard let url = bundle.url(forResource: "geomagnetic", withExtension: "bin"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return Grid(data: data)
    }

    /// Corrected geomagnetic latitude in degrees, −90…90, from `grid` (the bundled one by default);
    /// the centred dipole when there is no grid or the point is not a number.
    static func latitude(latitude: Double, longitude: Double, grid: Grid? = bundledGrid) -> Double {
        guard let grid, latitude.isFinite, longitude.isFinite else { return dipoleLatitude(latitude: latitude, longitude: longitude) }
        return grid.latitude(latitude: latitude, longitude: longitude)
    }
    static func latitude(of place: Place) -> Double { latitude(latitude: place.latitude, longitude: place.longitude) }

    /// The centred-dipole latitude in degrees, −90…90: φm = asin(sin φ sin φp + cos φ cos φp cos(λ − λp)).
    /// The fallback when no grid is bundled.
    static func dipoleLatitude(latitude: Double, longitude: Double) -> Double {
        let rad = Double.pi/180
        let s = sin(latitude*rad)*sin(poleLatitude*rad) + cos(latitude*rad)*cos(poleLatitude*rad)*cos((longitude-poleLongitude)*rad)
        return asin(max(-1, min(1, s)))/rad
    }

    /// `geomagnetic.bin`: little-endian, a 32-byte header ("NYXM", format 1, cells per degree,
    /// epoch, altitude, south and west edges, rows, columns, scale), then rows × columns Int16
    /// values (degrees × scale), rows south to north, each row west to east, wrapping in longitude.
    nonisolated struct Grid: Sendable {
        let rows: Int, columns: Int
        let south: Double, west: Double, step: Double, scale: Double
        let values: [Int16]

        /// Nil unless the header is exactly what this reader understands, the size matches, the
        /// columns go once around the world, and every value is a latitude.
        init?(data: Data) {
            guard data.count >= 32 else { return nil }
            let parsed: (rows: Int, columns: Int, perDegree: Int, south: Int, west: Int, scale: Int, values: [Int16])? = data.withUnsafeBytes { raw in
                func u16(_ offset: Int) -> Int { Int(UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))) }
                func i16(_ offset: Int) -> Int { Int(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: Int16.self))) }
                guard Array(raw.prefix(4)) == Array("NYXM".utf8), raw[4] == 1 else { return nil }
                let rows = u16(14), columns = u16(16), perDegree = Int(raw[5]), scale = u16(18)
                guard rows > 1, columns > 1, perDegree > 0, scale > 0, columns == 360*perDegree,
                      raw.count == 32 + rows*columns*2 else { return nil }
                let values = (0..<rows*columns).map { Int16(littleEndian: raw.loadUnaligned(fromByteOffset: 32 + 2*$0, as: Int16.self)) }
                return (rows, columns, perDegree, i16(10), i16(12), scale, values)
            }
            guard let parsed else { return nil }
            let limit = 90*parsed.scale
            guard parsed.values.allSatisfy({ abs(Int($0)) <= limit }) else { return nil }
            rows = parsed.rows; columns = parsed.columns
            south = Double(parsed.south); west = Double(parsed.west)
            step = 1/Double(parsed.perDegree); scale = Double(parsed.scale)
            values = parsed.values
        }

        /// Bilinear between the four surrounding cells. Longitude wraps (the cell east of the last
        /// column is the first); latitude clamps to the first and last rows, which at ±90° hold one
        /// value repeated, so the poles need no special case.
        func latitude(latitude: Double, longitude: Double) -> Double {
            let y = min(max((latitude - south)/step, 0), Double(rows - 1))
            var x = ((longitude - west).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)/step
            if x >= Double(columns) { x = 0 }
            let i = min(Int(y), rows - 2), j = min(Int(x), columns - 1), east = (j + 1) % columns
            let fy = y - Double(i), fx = x - Double(j)
            func value(_ row: Int, _ column: Int) -> Double { Double(values[row*columns + column])/scale }
            let lower = value(i, j)*(1 - fx) + value(i, east)*fx
            let upper = value(i + 1, j)*(1 - fx) + value(i + 1, east)*fx
            return lower*(1 - fy) + upper*fy
        }
    }

    /// How often aurora reaches a sky, by |φm|. The bounds follow the usual table of the auroral
    /// oval's equatorward view line by Kp index (Kp 3 near 60°, Kp 5 near 56°, Kp 7 near 52°):
    /// `often` sees aurora at quiet to unsettled levels, `active` needs active nights or minor
    /// storms, `storms` only strong ones. Below 52° aurora is too rare for a standing note.
    enum AuroraReach: Int, Comparable, Sendable {
        case none, storms, active, often
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
        init(geomagneticLatitude degrees: Double) {
            switch abs(degrees) {
            case 60...: self = .often
            case 56..<60: self = .active
            case 52..<56: self = .storms
            default: self = .none
            }
        }
    }
    static func auroraReach(_ place: Place) -> AuroraReach { AuroraReach(geomagneticLatitude: latitude(of: place)) }
}
