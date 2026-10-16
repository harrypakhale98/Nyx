import Foundation
import Testing
@testable import Nyx

/// The nearest dark sky (`SkyGrid.nearestDark`, `DarkerSky`): when it is offered, where it points,
/// and the words every surface shares. On the Mojave fixture tiles (`SkyGridTests`): the origin's
/// own sky is Bortle 7; A is Bortle 2 about 36 km northeast, its neighbour A' a little dimmer and
/// farther north, B Bortle 3 and C Bortle 4 about 250 km away.
struct DarkerSkyTests {
    let bundle = Bundle(for: BundleAnchor.self)
    var grid: SkyGrid { SkyGrid(bundle: bundle) }
    static let origin = SkyGridTests.origin
    static let a = SkyGridTests.a, aNext = SkyGridTests.aNext

    // MARK: The light map

    /// The nearest cell dark enough, then the darkest a little beyond it: A from the origin, B or C
    /// only when A is not dark enough, A rather than its nearer neighbour when A is close behind.
    @Test func nearestDarkFindsTheAreaNotItsEdge() throws {
        let grid = grid
        let found = try #require(grid.nearestDark(to: Self.origin, radiusMeters: 300_000))
        #expect(found.latitude == Self.a.0 && found.longitude == Self.a.1 && found.bortle == 2)
        #expect(abs(found.distanceMeters-36_500) < 200)
        // North of A', with A a quarter farther away: the darker A is chosen.
        let north = (latitude: 36.7, longitude: -116.125)
        let fromNorth = try #require(grid.nearestDark(to: north, radiusMeters: 300_000))
        #expect(fromNorth.latitude == Self.a.0)
        // Close to A' with A well beyond the quarter: the nearer A' stands.
        let close = (latitude: 36.45, longitude: -116.125)
        #expect(grid.nearestDark(to: close, radiusMeters: 300_000)?.latitude == Self.aNext.0)
        // Nothing dark enough, nothing in reach, no sky layer, bad input.
        #expect(grid.nearestDark(to: Self.origin, radiusMeters: 300_000, atMostBortle: 1) == nil)
        #expect(grid.nearestDark(to: Self.origin, radiusMeters: 10_000) == nil)
        #expect(SkyGrid(bundle: bundle, layers: [.clouds]).nearestDark(to: Self.origin, radiusMeters: 300_000) == nil)
        #expect(grid.nearestDark(to: Self.origin, radiusMeters: .nan) == nil && grid.nearestDark(to: (91, 0), radiusMeters: 1000) == nil)
        #expect(grid.nearestDark(to: (0, 179.9), radiusMeters: 300_000) == nil)
    }
    /// The sky layer gives coastal sea a value: a cell the land test refuses is passed over, and
    /// with nothing accepted there is no answer.
    @Test func nearestDarkKeepsToLand() throws {
        let grid = grid
        let notA: (Double, Double) -> Bool = { lat, lon in !(lat == Self.a.0 && lon == Self.a.1) }
        let found = try #require(grid.nearestDark(to: Self.origin, radiusMeters: 300_000, onLand: notA))
        #expect(found.latitude == Self.aNext.0 && found.longitude == Self.aNext.1)
        #expect(grid.nearestDark(to: Self.origin, radiusMeters: 300_000, onLand: { _, _ in false }) == nil)
        #expect(DarkerSky.offer(from: Self.origin, radiusMeters: 300_000, darkestInReach: nil, system: .kilometers, grid: grid, onLand: { _, _ in false }) == nil)
    }
    /// The bundled outline: inland desert yes, the open Gulf no, a point a kilometre off a coast no.
    @Test func inlandOnTheBundledLand() throws {
        let land = try #require(WorldLand.bundled)
        #expect(land.inland(latitude: 24.2, longitude: 46.6))       // south of Riyadh
        #expect(land.inland(latitude: 36.1, longitude: -116.1))     // the Mojave
        #expect(!land.inland(latitude: 25.6, longitude: 54.6))      // the Gulf off Dubai
        #expect(!land.inland(latitude: 0, longitude: -140))         // the Pacific
        #expect(!land.inland(latitude: 33.7, longitude: -118.42))   // just off Palos Verdes
    }

    // MARK: When it is offered

    /// Offered with nothing in reach or only suburban and brighter skies, and only for a sky two
    /// classes darker; never when a place in reach is dark already.
    @Test func neededClass() {
        #expect(DarkerSky.needed(darkestInReach: nil) == 4)
        #expect(DarkerSky.needed(darkestInReach: 2) == nil && DarkerSky.needed(darkestInReach: 4) == nil)
        #expect(DarkerSky.needed(darkestInReach: 5) == 3 && DarkerSky.needed(darkestInReach: 6) == 4 && DarkerSky.needed(darkestInReach: 8) == 4)
    }
    @Test func offerFollowsTheRule() throws {
        let grid = grid
        let none = try #require(DarkerSky.offer(from: Self.origin, radiusMeters: 300_000, darkestInReach: nil, system: .kilometers, grid: grid))
        #expect(none.area.latitude == Self.a.0 && none.darkestInReach == nil)
        // A lies east-northeast: about 68 degrees from north.
        #expect((60...75).contains(none.bearing))
        #expect(DarkerSky.offer(from: Self.origin, radiusMeters: 300_000, darkestInReach: 4, system: .kilometers, grid: grid) == nil)
        #expect(DarkerSky.offer(from: Self.origin, radiusMeters: 300_000, darkestInReach: 7, system: .kilometers, grid: grid)?.darkestInReach == 7)
        // A small radius still looks as far as Tonight's wider reach.
        #expect(DarkerSky.offer(from: Self.origin, radiusMeters: 10_000, darkestInReach: nil, system: .kilometers, grid: grid) != nil)
        // Standing in the dark already: the From home panel's to describe, not a trip.
        #expect(DarkerSky.offer(from: Self.a, radiusMeters: 300_000, darkestInReach: nil, system: .kilometers, grid: grid) == nil)
        // Widgets, the watch and Vision Pro bundle no sky tiles: never offered there.
        #expect(DarkerSky.offer(from: Self.origin, radiusMeters: 300_000, darkestInReach: nil, system: .kilometers, grid: SkyGrid(bundle: bundle, layers: [.clouds])) == nil)
    }
    @Test func bearings() {
        #expect(abs(DarkerSky.bearing(from: (0, 0), to: (1, 0))) < 1e-9)
        #expect(abs(DarkerSky.bearing(from: (0, 0), to: (0, 1))-90) < 1e-9)
        #expect(abs(DarkerSky.bearing(from: (0, 0), to: (-1, 0))-180) < 1e-9)
        #expect(abs(DarkerSky.bearing(from: (0, 0), to: (0, -1))-270) < 1e-9)
        // Across the antimeridian, the short way: east.
        #expect(abs(DarkerSky.bearing(from: (0, 179.5), to: (0, -179.5))-90) < 1e-9)
    }

    // MARK: Words

    @Test func sharedWords() throws {
        let offer = try #require(DarkerSky.offer(from: Self.origin, radiusMeters: 300_000, darkestInReach: 7, system: .kilometers, grid: grid))
        let km = DarkerSky.distance(offer.area.distanceMeters, .kilometers), miles = DarkerSky.distance(offer.area.distanceMeters, .miles)
        #expect(km == String(localized: "about \(SearchRadius.format(40, .kilometers))"))
        #expect(miles == String(localized: "about \(SearchRadius.format(20, .miles))"))
        #expect(DarkerSky.distance(6_000, .kilometers) == String(localized: "about \(SearchRadius.format(6, .kilometers))"))
        #expect(DarkerSky.headline(offer, system: .kilometers) == "The nearest dark sky is \(km) \(Compass.name(offer.bearing)), as the crow flies.")
        #expect(DarkerSky.skyLine(offer) == "\(BortleScale.name(2)), Bortle 2, estimated from satellite data.")
        #expect(DarkerSky.comparison(offer) == "The darkest place in reach has a Bortle 7 sky.")
        let record = DarkerSky.record(offer, from: "Somewhere", system: .kilometers)
        #expect(record.contains("no name, no score") && record.contains("\(km) \(Compass.name(offer.bearing)) of Somewhere") && record.hasSuffix("Bortle 2."))
        let nothing = DarkerSky.Offer(area: offer.area, bearing: offer.bearing, darkestInReach: nil)
        #expect(DarkerSky.comparison(nothing) == nil)
    }
    /// Ask Nyx: one more record after the places, said as a light-map estimate, only when what is
    /// in reach is bright; none from a dark park.
    @Test func askNyxRecordsTheNearestDarkSky() {
        func place(_ id: String, _ lat: Double, _ lon: Double, bortle: Int) -> Park {
            Park(id: id, nps: nil, name: id, countryCode: "US", region: "NV", kind: .custom, curated: false, latitude: lat, longitude: lon,
                 timeZoneID: "America/Los_Angeles", darkSkyDesignated: false, bortleEstimate: bortle, description: "", sourceURL: "", sourceNote: "", viewingSpots: [])
        }
        var lookup = NightLookup(parks: [place("Brightville", Self.origin.latitude, Self.origin.longitude, bortle: 7)], forecasts: [:], now: Date(timeIntervalSince1970: 1_797_217_200))
        lookup.grid = grid
        let bright = lookup.parksNear(park: "Brightville", radius: 100, system: .kilometers)
        #expect(bright.count == 2 && bright[0].hasPrefix("Brightville") && bright[1].hasPrefix("Nearest dark area on the satellite light map"))
        var dark = NightLookup(parks: [place("Darkville", Self.a.0, Self.a.1, bortle: 2)], forecasts: [:], now: Date(timeIntervalSince1970: 1_797_217_200))
        dark.grid = grid
        #expect(dark.parksNear(park: "Darkville", radius: 100, system: .kilometers).count == 1)
    }
}
