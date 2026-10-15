import Foundation
import Testing
@testable import Nyx

/// The aurora note follows geomagnetic latitude, in both hemispheres, on nights when the Sun gets at
/// least 12° down; not a US state. Corrected geomagnetic latitude comes from the bundled IGRF-14
/// grid; the centred dipole (pole 80.8° N 72.8° W) is the fallback.
struct AuroraTests {
    let parks: [Park]
    init() throws { parks = try ParkData.load() }
    func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }
    func evening(_ park: Park, _ iso: String) throws -> Date { try #require(TripDay(iso: iso)).evening(in: park) }
    /// A park moved to other coordinates and zone: the same record otherwise, so it stays whole as `Place` grows.
    func place(_ id: String, latitude: Double, longitude: Double, zone: String) throws -> Park {
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(try park("jotr"))) as? [String: Any])
        json["id"] = id; json["latitude"] = latitude; json["longitude"] = longitude; json["timeZoneID"] = zone
        json["countryCode"] = "NZ"; json["region"] = ""; json.removeValue(forKey: "nps")
        return try JSONDecoder().decode(Park.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// The fallback, hand-worked: φm = asin(sin φ sin φp + cos φ cos φp cos(λ − λp)).
    @Test func geomagneticLatitudeByHand() throws {
        let φp = Geomagnetic.poleLatitude, λp = Geomagnetic.poleLongitude
        #expect(abs(Geomagnetic.dipoleLatitude(latitude: φp, longitude: λp) - 90) < 1e-6)
        #expect(abs(Geomagnetic.dipoleLatitude(latitude: -φp, longitude: λp+180) + 90) < 1e-6)
        // On the equator, 180° from the pole's meridian: −(90 − 80.8); on its meridian: +9.2.
        #expect(abs(Geomagnetic.dipoleLatitude(latitude: 0, longitude: λp+180) + (90-φp)) < 1e-9)
        #expect(abs(Geomagnetic.dipoleLatitude(latitude: 0, longitude: λp) - (90-φp)) < 1e-9)
        // The geographic poles sit at ±80.8° geomagnetic, whatever the longitude.
        #expect(abs(Geomagnetic.dipoleLatitude(latitude: 90, longitude: 10) - φp) < 1e-9)
        #expect(abs(Geomagnetic.dipoleLatitude(latitude: -90, longitude: -120) + φp) < 1e-9)
        // Denali (63.3° N, 150.5° W) by hand: about 63.7°.
        let dena = try park("dena")
        #expect(abs(Geomagnetic.dipoleLatitude(latitude: dena.latitude, longitude: dena.longitude) - 63.7) < 0.1)
    }

    /// Reach never falls as |φm| rises, and is the same north and south.
    @Test func reachIsMonotonic() {
        var last = Geomagnetic.AuroraReach.none
        for tenth in 0...900 {
            let φm = Double(tenth)/10
            let reach = Geomagnetic.AuroraReach(geomagneticLatitude: φm)
            #expect(reach >= last, "\(φm)")
            #expect(reach == Geomagnetic.AuroraReach(geomagneticLatitude: -φm), "\(φm)")
            last = reach
        }
        #expect(Geomagnetic.AuroraReach(geomagneticLatitude: 51.9) == .none && Geomagnetic.AuroraReach(geomagneticLatitude: 52) == .storms)
        #expect(Geomagnetic.AuroraReach(geomagneticLatitude: 56) == .active && Geomagnetic.AuroraReach(geomagneticLatitude: 60) == .often)
    }

    /// The 63 parks on the grid: every Alaska park keeps a note; the northern tier has one; the tropics
    /// have none. Against the dipole: Acadia drops out (51.6°), Badlands, Wind Cave and Yellowstone
    /// come in just over 52°, and Kenai Fjords and Lake Clark move from often to active (just under 60°).
    @Test func whichParksHaveANote() throws {
        let nps = parks.filter { $0.nps != nil && $0.kind == .nationalPark }
        let reach = Dictionary(uniqueKeysWithValues: nps.map { ($0.id, Geomagnetic.auroraReach($0)) })
        #expect(Set(reach.filter { $0.value == .often }.keys) == ["gaar", "kova", "dena", "wrst", "glba"])
        #expect(Set(reach.filter { $0.value == .active }.keys) == ["katm", "voya", "isro", "lacl", "kefj"])
        #expect(Set(reach.filter { $0.value == .storms }.keys) == ["glac", "thro", "noca", "olym", "mora", "badl", "wica", "yell"])
        for park in nps where park.region == "AK" {
            #expect(SkyNotes.aurora(park: park, evening: try evening(park, "2026-12-01")) != nil, "\(park.id)")
            #expect(SkyNotes.aurora(park: park, evening: try evening(park, "2026-10-15"), forecast: true)?.contains("NOAA's forecast for the next three nights") == true, "\(park.id)")
        }
        for id in ["npsa", "havo", "hale", "viis", "jotr", "acad"] {
            let p = try park(id)
            #expect(Geomagnetic.auroraReach(p) == .none, "\(id)")
            #expect(SkyNotes.aurora(park: p, evening: try evening(p, "2026-12-01")) == nil, "\(id)")
        }
    }

    /// Aurora needs a dark night: none under Alaska's bright June nights, but Glacier's June nights get dark enough.
    @Test func onlyOnNightsDarkEnough() throws {
        let dena = try park("dena"), katm = try park("katm"), glac = try park("glac")
        #expect(SkyNotes.aurora(park: dena, evening: try evening(dena, "2026-06-21")) == nil)
        #expect(SkyNotes.aurora(park: katm, evening: try evening(katm, "2026-06-21")) == nil)
        #expect(SkyNotes.aurora(park: katm, evening: try evening(katm, "2026-11-01"))?.contains("toward the north") == true)
        let june = try #require(SkyNotes.aurora(park: glac, evening: try evening(glac, "2026-06-21")))
        #expect(june.hasPrefix("Aurora reaches here only during strong solar storms, low toward the north."))
        // Lowest Sun at solar midnight: |φ + δ| − 90, near −3° at Denali on the solstice, near −50° in December.
        #expect(abs(SkyNotes.lowestSun(park: dena, evening: try evening(dena, "2026-06-21")) + 3.3) < 0.3)
        #expect(abs(SkyNotes.lowestSun(park: dena, evening: try evening(dena, "2026-12-21")) + 50.1) < 0.3)
    }

    /// The south, on the grid: 45° S 170° E (New Zealand's South Island) sits at about −52.3°, just in
    /// the storm tier (the dipole read −48.6°, short of it); 54.5° S 159° E (Macquarie Island) at about
    /// −64.1°, where aurora is often seen (the dipole read −59.4°).
    @Test func southernHemisphere() throws {
        let nz = try place("test:nz", latitude: -45, longitude: 170, zone: "Pacific/Auckland")
        #expect(abs(Geomagnetic.latitude(of: nz) + 52.3) < 0.1)
        #expect(abs(Geomagnetic.dipoleLatitude(latitude: -45, longitude: 170) + 48.6) < 0.1)
        #expect(Geomagnetic.auroraReach(nz) == .storms)
        let storms = try #require(SkyNotes.aurora(park: nz, evening: try evening(nz, "2026-06-21")))
        #expect(storms.contains("low toward the south"))
        let macquarie = try place("test:macquarie", latitude: -54.5, longitude: 158.95, zone: "Australia/Hobart")
        #expect(abs(Geomagnetic.latitude(of: macquarie) + 64.1) < 0.1)
        #expect(abs(Geomagnetic.dipoleLatitude(latitude: -54.5, longitude: 158.95) + 59.4) < 0.1)
        #expect(Geomagnetic.auroraReach(macquarie) == .often)
        #expect(SkyNotes.aurora(park: macquarie, evening: try evening(macquarie, "2026-06-21"))?.hasPrefix("Aurora is often seen here") == true)
    }

    // MARK: The corrected-latitude grid

    /// Against a validation table (grid column: CGM for 2025, the
    /// 110 km field line mapped to the ground), within 0.1°.
    @Test func gridMatchesTheValidationTable() throws {
        #expect(Geomagnetic.bundledGrid != nil)
        let table: [(name: String, latitude: Double, longitude: Double, cgm: Double)] = [
            ("Edinburgh", 55.95, -3.19, 53.2), ("Hobart", -42.88, 147.33, -53.7), ("Fairbanks", 64.84, -147.72, 65.2),
            ("Minneapolis", 44.98, -93.27, 54.3), ("Reykjavík", 64.15, -21.94, 64.2), ("Christchurch", -43.53, 172.64, -50.3),
        ]
        for row in table {
            #expect(abs(Geomagnetic.latitude(latitude: row.latitude, longitude: row.longitude) - row.cgm) < 0.1, "\(row.name)")
        }
        // Edinburgh moves from active (dipole 57.9°) to storms; Christchurch stays below the tiers.
        #expect(Geomagnetic.AuroraReach(geomagneticLatitude: Geomagnetic.latitude(latitude: 55.95, longitude: -3.19)) == .storms)
        #expect(Geomagnetic.AuroraReach(geomagneticLatitude: Geomagnetic.latitude(latitude: -43.53, longitude: 172.64)) == .none)
    }

    /// The last column (179° E) and the first (180° W) are neighbours: no seam at the antimeridian,
    /// and any longitude, however written, lands on the same value.
    @Test func gridWrapsAtTheAntimeridian() throws {
        let grid = try #require(Geomagnetic.bundledGrid)
        #expect(grid.rows == 181 && grid.columns == 360 && grid.step == 1 && grid.south == -90 && grid.west == -180)
        for latitude in [65.0, 60.3, -55.0, 0.5] {
            let east = grid.latitude(latitude: latitude, longitude: 179.9999), west = grid.latitude(latitude: latitude, longitude: -179.9999)
            #expect(abs(east - west) < 0.001, "\(latitude)")
            #expect(grid.latitude(latitude: latitude, longitude: 180) == grid.latitude(latitude: latitude, longitude: -180))
            #expect(abs(grid.latitude(latitude: latitude, longitude: 540) - grid.latitude(latitude: latitude, longitude: 180)) < 1e-9)
            #expect(abs(grid.latitude(latitude: latitude, longitude: -200) - grid.latitude(latitude: latitude, longitude: 160)) < 1e-9)
        }
        // Halfway between the last column and the first is their average (row 150 is 60° N).
        let last = Double(grid.values[150*360 + 359])/grid.scale, first = Double(grid.values[150*360])/grid.scale
        #expect(abs(grid.latitude(latitude: 60, longitude: 179.5) - (last + first)/2) < 1e-9)
    }

    /// Rows clamp at the poles, where each edge row holds one value.
    @Test func gridClampsAtThePoles() throws {
        let grid = try #require(Geomagnetic.bundledGrid)
        let north = grid.latitude(latitude: 90, longitude: 0), south = grid.latitude(latitude: -90, longitude: 0)
        for longitude in stride(from: -180.0, through: 180, by: 37.5) {
            #expect(grid.latitude(latitude: 90, longitude: longitude) == north)
            #expect(grid.latitude(latitude: -90, longitude: longitude) == south)
        }
        #expect(grid.latitude(latitude: 95, longitude: 10) == north && grid.latitude(latitude: -95, longitude: 10) == south)
        #expect(north > 80 && south < -70)
    }

    /// No file, or a file that fails any check: the dipole, never a crash or a guess.
    @Test func fallsBackToTheDipole() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "nyx-no-grid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let empty = try #require(Bundle(url: folder))
        #expect(Geomagnetic.grid(in: empty) == nil)
        for (latitude, longitude) in [(55.95, -3.19), (-42.88, 147.33), (63.73, -148.91), (0.0, 0.0)] {
            #expect(Geomagnetic.latitude(latitude: latitude, longitude: longitude, grid: nil) == Geomagnetic.dipoleLatitude(latitude: latitude, longitude: longitude))
        }

        let url = try #require(Bundle.main.url(forResource: "geomagnetic", withExtension: "bin"))
        let good = try Data(contentsOf: url)
        #expect(Geomagnetic.Grid(data: good) != nil)
        #expect(Geomagnetic.Grid(data: Data()) == nil)
        #expect(Geomagnetic.Grid(data: good.prefix(31)) == nil)
        #expect(Geomagnetic.Grid(data: good.dropLast(2)) == nil)
        func altered(_ offset: Int, _ byte: UInt8) -> Data { var data = good; data[offset] = byte; return data }
        #expect(Geomagnetic.Grid(data: altered(0, UInt8(ascii: "X"))) == nil)   // not "NYXM"
        #expect(Geomagnetic.Grid(data: altered(4, 2)) == nil)                    // a format this reader does not know
        #expect(Geomagnetic.Grid(data: altered(16, 100)) == nil)                 // columns that do not go once around
        #expect(Geomagnetic.Grid(data: altered(18, 0)) == nil)                   // scale 100 → 0
        var wild = good; wild[33] = 0x7F                                          // the first value far past 90°
        #expect(Geomagnetic.Grid(data: wild) == nil)
        // A slice that does not start at index 0 reads the same.
        let sliced = (Data([0, 0]) + good).dropFirst(2)
        let grid = try #require(Geomagnetic.Grid(data: sliced))
        #expect(grid.latitude(latitude: 55.95, longitude: -3.19) == Geomagnetic.latitude(latitude: 55.95, longitude: -3.19))
    }
}
