import Foundation
import Testing
@testable import Nyx

/// References: PyEphem 4.x (VSOP87 planets, epoch of date; geometric horizon for the core).
@Suite struct SkyAlmanacTests {
    let almanac = SkyAlmanac()
    let iso = ISO8601DateFormatter()
    func date(_ text: String) throws -> Date { try #require(iso.date(from: text)) }
    func park(_ id: String) throws -> Park { try #require(try ParkData.load().first(where: { $0.id == id })) }

    @Test func planetsMatchPyEphem() throws {
        let fixtures: [(String, SkyAlmanac.Planet, Double, Double, Double)] = [
            ("2026-10-05T04:00:00Z", .mercury, 212.929, -15.620, 0.01),
            ("2026-10-05T04:00:00Z", .venus, 213.508, -21.279, -4.37),
            ("2026-10-05T04:00:00Z", .mars, 126.698, 20.287, 1.10),
            ("2026-10-05T04:00:00Z", .jupiter, 142.927, 15.288, -1.74),
            ("2026-10-05T04:00:00Z", .saturn, 11.406, 1.953, 0.32),
            ("2028-07-01T05:00:00Z", .mercury, 77.677, 20.411, 0.01),
            ("2028-07-01T05:00:00Z", .venus, 63.237, 17.011, -4.48),
            ("2028-07-01T05:00:00Z", .mars, 75.355, 22.980, 1.47),
            ("2028-07-01T05:00:00Z", .jupiter, 172.047, 4.768, -1.74),
            ("2028-07-01T05:00:00Z", .saturn, 37.375, 12.279, 0.42),
            ("2032-05-10T02:00:00Z", .mercury, 33.712, 11.675, -0.80),
            ("2032-05-10T02:00:00Z", .venus, 41.581, 15.046, -3.80),
            ("2032-05-10T02:00:00Z", .mars, 65.864, 22.155, 1.56),
            ("2032-05-10T02:00:00Z", .jupiter, 304.319, -19.959, -2.24),
            ("2032-05-10T02:00:00Z", .saturn, 81.091, 22.081, 0.09),
        ]
        for (date, planet, ra, dec, magnitude) in fixtures {
            let p = almanac.position(of: planet, at: try #require(iso.date(from: date)))
            let dRA = (p.ra*180/Double.pi - ra + 540).truncatingRemainder(dividingBy: 360) - 180
            let separation = hypot(dRA*cos(dec*Double.pi/180), p.dec*180/Double.pi - dec)
            #expect(separation < 0.1, "\(planet) \(date) off by \(separation)°")
            // Schlyter's Mercury phase law differs from PyEphem's by up to ~0.7 mag; the app says "about".
            #expect(abs(p.magnitude - magnitude) < (planet == .mercury ? 0.8 : 0.25), "\(planet) \(date) magnitude")
        }
    }
    /// The galactic core sets (10° altitude) at Joshua Tree at 09:43 UTC on 2027-07-11 (PyEphem, no refraction).
    @Test func coreTimingAtJoshuaTree() throws {
        let jotr = try park("jotr")
        let sky = AstronomyEngine().conditions(for: jotr, on: try date("2027-07-10T20:00:00Z"))
        let core = almanac.core(for: jotr, sky: sky)
        let set = try #require(core.sets)
        #expect(abs(set.timeIntervalSince(try date("2027-07-11T09:43:26Z"))) < 240)
        #expect(abs(core.highestAzimuth - 180) < 3)
        #expect(core.highestAltitude > 26 && core.highestAltitude < 28)
        #expect(core.dark != nil)
    }
    /// The core never clears 10° anywhere in Alaska; American Samoa sees it nearly overhead.
    @Test func coreAtTheExtremes() throws {
        let night = try date("2027-06-15T20:00:00Z")
        let dena = try park("dena"), npsa = try park("npsa")
        let alaska = almanac.core(for: dena, sky: AstronomyEngine().conditions(for: dena, on: night))
        #expect(alaska.neverUp && alaska.dark == nil)
        let samoa = almanac.core(for: npsa, sky: AstronomyEngine().conditions(for: npsa, on: night))
        #expect(samoa.highestAltitude > 70)
    }
    /// Peak instants from solar longitude agree with PyEphem's J2000 solar longitude within 15 minutes.
    @Test func meteorPeakFromSolarLongitude() throws {
        let geminids = SkyAlmanac.MeteorShower(code: "GEM", name: "Geminids", start: "12-04", end: "12-20", peakSolarLongitude: 262.2,
            radiantRA: 112, radiantDec: 33, zhr: 150, velocity: 35)
        let peak = try #require(almanac.peakDate(of: geminids, near: try date("2026-12-10T00:00:00Z")))
        #expect(abs(peak.timeIntervalSince(try date("2026-12-14T13:41:07Z"))) < 900)
    }
    /// The Geminid radiant is high before dawn at Joshua Tree on the 2026 peak night, with the Moon down.
    @Test func geminidsAtJoshuaTree() throws {
        let jotr = try park("jotr")
        let geminids = SkyAlmanac.MeteorShower(code: "GEM", name: "Geminids", start: "12-04", end: "12-20", peakSolarLongitude: 262.2,
            radiantRA: 112, radiantDec: 33, zhr: 150, velocity: 35)
        let sky = AstronomyEngine().conditions(for: jotr, on: try date("2026-12-13T20:00:00Z"))
        let night = try #require(almanac.showers([geminids], for: jotr, sky: sky, bortle: 3).first)
        #expect(night.isPeakNight && night.moonDownAtBest)
        #expect(night.radiantAltitude > 75)
        #expect(night.hourlyRate > 50 && night.hourlyRate < 150)
    }
    /// Polar day: nothing is "visible" in a sky with no darkness, and nothing crashes.
    @Test func polarDayHasNoPlanetsOrCore() throws {
        let gaar = try park("gaar")
        let sky = AstronomyEngine().conditions(for: gaar, on: try date("2027-06-21T20:00:00Z"))
        #expect(almanac.core(for: gaar, sky: sky).dark == nil)
        #expect(almanac.planets(for: gaar, sky: sky).isEmpty)
    }
}
