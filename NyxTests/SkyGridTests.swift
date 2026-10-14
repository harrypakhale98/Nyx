import Foundation
import Testing
@testable import Nyx

/// The bundled world grids: the tile format, the corner and cell
/// rules, the usual clouds for places the per-park file does not hold, From home tonight with and
/// without the sky layer, and the dark areas within a radius. The four fixture tiles in
/// `NyxTests/Fixtures/` come from a small script that also prints the
/// centres, magnitudes and distances used here.
struct SkyGridTests {
    let bundle = Bundle(for: BundleAnchor.self)
    var grid: SkyGrid { SkyGrid(bundle: bundle) }
    /// Mojave fixture origin and its dark cells' centres (`make_grid_fixtures.py`).
    static let origin = (latitude: 36.0, longitude: -116.5)
    static let a = (36.125, -116.125), aNext = (36.375, -116.125), b = (37.625, -114.375), c = (34.125, -117.875), e = (40.625, -116.375)

    func place(_ id: String, _ lat: Double, _ lon: Double, zone: String = "America/Los_Angeles", curated: Bool = false) -> Park {
        Park(id: id, nps: nil, name: "Somewhere", countryCode: "US", region: "", kind: .custom, curated: curated, latitude: lat, longitude: lon,
             timeZoneID: zone, darkSkyDesignated: false, bortleEstimate: 7, description: "", sourceURL: "", sourceNote: "", viewingSpots: [])
    }
    func evening(_ park: Park, _ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(park.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    // MARK: Format and rules

    @Test func readsTheFixtureTiles() {
        let grid = grid
        #expect(grid.hasLayer(.clouds) && grid.hasLayer(.sky))
        // November at A is its own cell; elsewhere January 20 / 70, rising and falling by 5 a month.
        #expect(grid.cloudNight(latitude: 36.1, longitude: -116.1, month: 11).map { [$0.mean, $0.clear] } == [12, 78])
        #expect(grid.cloudNight(latitude: 33, longitude: -113, month: 1).map { [$0.mean, $0.clear] } == [20, 70])
        #expect(grid.cloudNight(latitude: 33, longitude: -113, month: 12).map { [$0.mean, $0.clear] } == [75, 15])
        #expect(grid.cloudNight(latitude: -14.28, longitude: -170.7, month: 7).map { [$0.mean, $0.clear] } == [60, 25])
        let dark = grid.skyBrightness(latitude: 36.1, longitude: -116.1)
        #expect(dark.map { abs($0-21.9) < 1e-9 } == true)
        #expect(grid.skyBrightness(latitude: 33, longitude: -113).map { abs($0-18.0) < 1e-9 } == true)
        #expect(grid.skyBrightness(latitude: 40.6, longitude: -116.3).map { abs($0-21.7) < 1e-9 } == true)
    }
    /// Sea (255), a tile that is not bundled, coordinates off the Earth and months that do not exist.
    @Test func noDataIsNil() {
        let grid = grid
        #expect(grid.cloudNight(latitude: 35, longitude: -119.9, month: 1) == nil)
        #expect(grid.skyBrightness(latitude: 35, longitude: -119.9) == nil)
        #expect(grid.cloudNight(latitude: 50, longitude: 10, month: 1) == nil && grid.skyBrightness(latitude: 50, longitude: 10) == nil)
        #expect(grid.cloudNight(latitude: 36, longitude: -116, month: 0) == nil && grid.cloudNight(latitude: 36, longitude: -116, month: 13) == nil)
        for (lat, lon) in [(90.5, -116.0), (-91.0, -116.0), (Double.nan, -116.0), (36.0, Double.infinity)] {
            #expect(grid.skyBrightness(latitude: lat, longitude: lon) == nil && grid.cloudNight(latitude: lat, longitude: lon, month: 1) == nil)
        }
        let damaged = SkyGrid.Key(layer: .sky, south: 30, west: -120)
        #expect(SkyGrid.Tile.decode(Data([1, 2, 3]), expecting: damaged) == nil)
    }
    /// A file whose header disagrees with its name is refused, never read as another place's sky.
    @Test func headerMustMatchTheName() throws {
        let url = try #require(bundle.url(forResource: "grid-sky-n30-w120", withExtension: "bin"))
        let data = try Data(contentsOf: url)
        #expect(SkyGrid.Tile.decode(data, expecting: SkyGrid.Key(layer: .sky, south: 30, west: -120))?.cellsPerDegree == 4)
        #expect(SkyGrid.Tile.decode(data, expecting: SkyGrid.Key(layer: .sky, south: 40, west: -120)) == nil)
        #expect(SkyGrid.Tile.decode(data, expecting: SkyGrid.Key(layer: .clouds, south: 30, west: -120)) == nil)
    }
    @Test func tileNames() {
        let key = SkyGrid.Key(layer: .sky, south: -50, west: 160)
        #expect(SkyGrid.fileName(key) == "grid-sky-s50-e160" && SkyGrid.key(fileName: "grid-sky-s50-e160") == key)
        #expect(SkyGrid.key(fileName: "grid-clouds-n30-w120") == SkyGrid.Key(layer: .clouds, south: 30, west: -120))
        #expect(SkyGrid.key(fileName: "grid-clouds-n00-e000") == SkyGrid.Key(layer: .clouds, south: 0, west: 0))
        for bad in ["grid-sky-n35-w120", "grid-moon-n30-w120", "grid-sky-n30-w120x", "grid-sky-n90-w120", "grid-sky-n30-e180", "grid-sky-n3-w120", "sky-n30-w120"] {
            #expect(SkyGrid.key(fileName: bad) == nil, "\(bad)")
        }
    }
    /// `nyxgrid.tile_corner`, printed by `make_grid_fixtures.py` for these points, and the rule's
    /// invariant (a point lies in its tile; 90° N and 180° E clamp into the last tile) on a lattice.
    @Test func cornerRuleMatchesTheBuildScript() {
        let points: [(Double, Double)] = [(36.0, -116.0), (-14.25, -170.7), (90, 180), (-90, -180), (0, 0), (-0.01, -0.01), (40, -110), (39.999, -110.001),
                                          (-10, -170), (-10.0001, -170.0001), (89.9, 179.9), (-89.9, -179.9), (12.5, 77.6), (-33.9, 18.4), (64.1, -21.9), (-45.0, 170.0)]
        let python: [(Int, Int)] = [(30, -120), (-20, -180), (80, 170), (-90, -180), (0, 0), (-10, -10), (40, -110), (30, -120),
                                    (-10, -170), (-20, -180), (80, 170), (-90, -180), (10, 70), (-40, 10), (60, -30), (-50, 170)]
        for ((lat, lon), want) in zip(points, python) {
            let got = SkyGrid.corner(latitude: lat, longitude: lon)
            #expect(got.south == want.0 && got.west == want.1, "\(lat), \(lon)")
        }
        for lat in stride(from: -90.0, through: 90.0, by: 0.73) {
            for lon in stride(from: -180.0, through: 180.0, by: 1.37) {
                let corner = SkyGrid.corner(latitude: lat, longitude: lon)
                #expect(Double(corner.south) <= lat && (lat < Double(corner.south+10) || corner.south == 80), "\(lat)")
                #expect(Double(corner.west) <= lon && (lon < Double(corner.west+10) || corner.west == 170), "\(lon)")
            }
        }
        // Longitudes past ±180° wrap; the antimeridian itself stays on the east edge as in the script.
        #expect(SkyGrid.normalized(latitude: 10, longitude: 200)?.longitude == -160 && SkyGrid.normalized(latitude: 10, longitude: -190)?.longitude == 170)
        #expect(SkyGrid.normalized(latitude: 10, longitude: 180)?.longitude == 180 && SkyGrid.normalized(latitude: 91, longitude: 0) == nil)
    }
    /// A cell holds its south and west edges: A spans 36.0–36.25 N, 116.25–116.0 W.
    @Test func cellEdges() {
        let grid = grid
        func mag(_ lat: Double, _ lon: Double) -> Double? { grid.skyBrightness(latitude: lat, longitude: lon) }
        #expect(mag(36.0, -116.25).map { abs($0-21.9) < 1e-9 } == true)
        #expect(mag(36.2499, -116.0001).map { abs($0-21.9) < 1e-9 } == true)
        #expect(mag(35.9999, -116.1).map { abs($0-18.0) < 1e-9 } == true)
        #expect(mag(36.1, -116.0).map { abs($0-18.0) < 1e-9 } == true)
        // A wrapped longitude reads the same cell.
        #expect(mag(36.1, -116.1+360) == mag(36.1, -116.1))
    }
    /// The SQM ranges per class (Bortle 2001; the "Bortle scale" reference table), never 1 and at most 8.
    @Test func bortleFromMagnitude() {
        let cases: [(Double, Int)] = [(22.0, 2), (21.76, 2), (21.6, 2), (21.59, 3), (21.3, 3), (21.29, 4), (20.8, 4), (20.5, 5), (19.25, 5),
                                      (19.2, 6), (18.5, 6), (18.49, 7), (18.0, 7), (17.99, 8), (15.0, 8), (.nan, 8)]
        for (mag, want) in cases { #expect(SkyGrid.bortle(fromMagnitude: mag) == want, "\(mag)") }
        var last = 9
        for value in 0...254 {
            let bortle = SkyGrid.bortle(fromMagnitude: SkyGrid.magnitude(UInt8(value)))
            #expect(bortle <= last && (2...8).contains(bortle)); last = bortle
        }
    }
    /// The cache keeps only the last `capacity` tiles; `prepare` decodes off the caller's actor.
    @Test func cacheIsBoundedAndPreparable() async {
        let grid = SkyGrid(bundle: bundle, capacity: 1)
        #expect(!grid.isCached(.clouds, latitude: 36, longitude: -116))
        #expect(await grid.prepare(.clouds, latitude: 36, longitude: -116))
        #expect(grid.isCached(.clouds, latitude: 36, longitude: -116))
        _ = grid.skyBrightness(latitude: 36, longitude: -116)
        #expect(grid.isCached(.sky, latitude: 36, longitude: -116) && !grid.isCached(.clouds, latitude: 36, longitude: -116))
        #expect(await grid.prepare(.sky, latitude: 50, longitude: 10) == false)
        let cloudsOnly = SkyGrid(bundle: bundle, layers: [.clouds])
        #expect(cloudsOnly.hasLayer(.clouds) && !cloudsOnly.hasLayer(.sky) && cloudsOnly.skyBrightness(latitude: 36.1, longitude: -116.1) == nil)
    }

    // MARK: Usual clouds

    /// A place the per-park file does not hold reads the grid, marked as an estimate; its words say so.
    @Test func cloudsFallBackToTheGridForOtherPlaces() throws {
        let climate = CloudClimate(parks: [:], grid: grid)
        let here = place("pin:dark", 36.1, -116.1)
        let november = try #require(climate.typical(here, on: try evening(here, 2027, 11, 15)))
        #expect(november == CloudClimate.Typical(month: 11, cloud: 12, clear: 78, estimated: true))
        #expect(climate.sentence(here, on: try evening(here, 2027, 11, 15)) == "About 8 in 10 November nights here are mostly clear.")
        let extremes = place("pin:edge", 35.1, -115.1)
        #expect(climate.sentence(extremes, on: try evening(extremes, 2027, 1, 15)) == "January nights here are rarely clear, by an estimate.")
        #expect(climate.sentence(extremes, on: try evening(extremes, 2027, 9, 15)) == "Nearly every September night here is mostly clear, by an estimate.")
        let samoa = place("pin:samoa", -14.28, -170.7, zone: "Pacific/Pago_Pago")
        #expect(climate.typical(samoa, on: try evening(samoa, 2027, 7, 1)) == CloudClimate.Typical(month: 7, cloud: 60, clear: 25, estimated: true))
        #expect(climate.typical(place("pin:sea", 35, -119.9), on: .now) == nil)
        // Without a grid (every hand-built climate, and `load`) nothing changes.
        #expect(CloudClimate(parks: [:]).typical(here, on: .now) == nil)
        #expect(CloudClimate.Typical(month: 1, cloud: 90, clear: 3).sentence(monthName: "January") == "January nights here are rarely clear.")
    }
    /// The 63 parks keep their own ten years of ERA5, even where a grid tile covers them (Joshua Tree, Death Valley).
    @Test func curatedParksKeepTheirOwnClouds() throws {
        let file = try #require(CloudClimate.load())
        let withGrid = CloudClimate(parks: file.parks, grid: grid)
        let parks = try ParkData.load()
        #expect(!parks.isEmpty)
        for park in parks {
            for month in 1...12 {
                let night = try evening(park, 2027, month, 15)
                #expect(withGrid.typical(park, on: night) == file.typical(park, on: night), "\(park.id) \(month)")
                #expect(withGrid.typical(park, on: night)?.estimated == false)
            }
        }
    }

    // MARK: From home tonight

    func home(_ grid: SkyGrid, _ lat: Double = 36.1, _ lon: Double = -116.1) throws -> HomeSky {
        let origin = HomeSky.Origin(name: "Here", state: "", latitude: lat, longitude: lon, timeZone: try #require(TimeZone(identifier: "America/Los_Angeles")), source: .device)
        // 7 PM in Los Angeles on Geminid night.
        return HomeSky(origin: origin, now: Date(timeIntervalSince1970: 1_797_217_200), grid: grid)
    }
    /// Without the sky layer, the light words and numbers are today's: Bortle 7 assumed, a suburban
    /// sky for meteors, no score, and the "no light map" line (the panel shows it for `.assumed`).
    @Test func homeUnchangedWithoutTheSkyLayer() throws {
        let bare = try home(SkyGrid(bundle: bundle, layers: []))
        #expect(bare.light == .assumed && bare.place.bortleEstimate == HomeSky.assumedBortle && bare.estimate == nil)
        #expect(bare.usualClouds == nil && bare.usualCloudsTitle == nil && bare.skyClass == nil && bare.skyLine == nil)
        #expect(!bare.summary.contains("Usual clouds") && !bare.summary.contains("Sky brightness"))
        if let shower = bare.shower { #expect(shower.detail.contains("suburban sky") && !shower.detail.contains("satellite")) }
        // The cloud layer alone adds the month's usual clouds and nothing about light.
        let clouds = try home(SkyGrid(bundle: bundle, layers: [.clouds]))
        #expect(clouds.light == .assumed && clouds.place.bortleEstimate == HomeSky.assumedBortle && clouds.estimate == nil && clouds.skyClass == nil)
        #expect(clouds.usualClouds == CloudClimate.Typical(month: 12, cloud: 75, clear: 15, estimated: true))
        #expect(clouds.usualCloudsTitle == "Usual clouds for December" && clouds.usualCloudsLine == "About 2 in 10 December nights here are mostly clear.")
        #expect(clouds.shower?.detail == bare.shower?.detail && clouds.planets.map(\.spoken) == bare.planets.map(\.spoken))
    }
    /// With the sky layer: the grid's class, said to be a satellite estimate, and tonight scored on the usual clouds.
    @Test func homeWithTheSkyLayer() throws {
        let lit = try home(grid)
        guard case .satellite(let magnitude) = lit.light else { Issue.record("expected the grid's sky"); return }
        #expect(abs(magnitude-21.9) < 1e-9 && lit.place.bortleEstimate == 2 && lit.skyClass == "Bortle 2")
        #expect(lit.skyLine?.contains("Estimated from satellite data") == true && lit.summary.contains("Sky brightness: Bortle 2."))
        let estimate = try #require(lit.estimate)
        #expect(estimate.basis == .usual && estimate.usualCloud == 75)
        if let shower = lit.shower { #expect(shower.detail.contains("Bortle 2 sky, estimated from satellite data") && !shower.detail.contains("suburban")) }
        // At sea or off the grid the assumed sky returns.
        let sea = try home(grid, 35, -119.9), offGrid = try home(grid, 50, 10)
        #expect(sea.light == .assumed && offGrid.light == .assumed && offGrid.place.bortleEstimate == HomeSky.assumedBortle)
    }
    /// A park keeps its own hand-checked Bortle and its own words; the grid is not read for it.
    @Test func homeAtAParkKeepsThePark() throws {
        let jotr = try #require(try ParkData.load().first { $0.id == "jotr" })
        let origin = try #require(HomeSky.origin(location: nil, place: nil, park: jotr))
        let sky = HomeSky(origin: origin, now: Date(timeIntervalSince1970: 1_797_217_200), grid: grid)
        #expect(sky.light == .park && sky.place.bortleEstimate == jotr.bortleEstimate && sky.usualClouds == nil && sky.skyClass == nil)
    }

    // MARK: Dark areas

    /// Darkest first, never neighbours: A's darker-than-B neighbour A' is passed over at the default spacing.
    @Test func darkestAreasInOrderAndSpaced() {
        let grid = grid
        let found = grid.darkest(near: Self.origin, radiusMeters: 300_000)
        #expect(found.map(\.bortle) == [2, 3, 4])
        #expect(zip(found.map(\.magnitude), [21.9, 21.5, 21.0]).allSatisfy { abs($0-$1) < 1e-9 })
        for (area, centre) in zip(found, [Self.a, Self.b, Self.c]) { #expect(area.latitude == centre.0 && area.longitude == centre.1) }
        #expect(zip(found.map(\.distanceMeters), [36_500.0, 261_600, 243_200]).allSatisfy { abs($0-$1) < 200 })
        for (i, one) in found.enumerated() {
            for other in found[(i+1)...] { #expect(Park.distance(one.latitude, one.longitude, other.latitude, other.longitude) >= 50_000) }
        }
        // With no spacing the neighbour comes second.
        let close = grid.darkest(near: Self.origin, radiusMeters: 300_000, spacingMeters: 1)
        #expect(close.map(\.latitude) == [Self.a.0, Self.aNext.0, Self.b.0])
        // A wider search crosses into the tile to the north; D lies beyond it.
        let wide = grid.darkest(near: Self.origin, radiusMeters: 600_000)
        #expect(wide.map(\.latitude) == [Self.a.0, Self.e.0, Self.b.0] && wide.allSatisfy { $0.distanceMeters <= 600_000 })
        #expect(grid.darkest(near: Self.origin, radiusMeters: 300_000, atMostBortle: 3).count == 2)
        #expect(grid.darkest(near: Self.origin, radiusMeters: 300_000, limit: 1).first?.latitude == Self.a.0)
        #expect(SkyGrid.DarkArea.title == "A dark area")
    }
    /// Nothing dark enough, nothing in reach, no sky layer, or a search over a pole or the antimeridian: an empty list, never a crash.
    @Test func darkestAtTheEdges() {
        let grid = grid
        #expect(grid.darkest(near: Self.origin, radiusMeters: 300_000, atMostBortle: 1).isEmpty)
        #expect(grid.darkest(near: Self.origin, radiusMeters: 10_000).isEmpty)
        #expect(grid.darkest(near: Self.origin, radiusMeters: 300_000, limit: 0).isEmpty)
        #expect(grid.darkest(near: Self.origin, radiusMeters: .nan).isEmpty && grid.darkest(near: (91, 0), radiusMeters: 1000).isEmpty)
        #expect(SkyGrid(bundle: bundle, layers: [.clouds]).darkest(near: Self.origin, radiusMeters: 300_000).isEmpty)
        #expect(grid.darkest(near: (89.9, 0), radiusMeters: 300_000).isEmpty)
        #expect(grid.darkest(near: (0, 179.9), radiusMeters: 300_000).isEmpty && grid.darkest(near: (-14.3, -179.9), radiusMeters: 300_000).isEmpty)
    }
}
