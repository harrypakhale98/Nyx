import Foundation
import Testing
import simd
@testable import Nyx

/// The Vision Pro sky's geometry: one rotation of the celestial sphere must put every star where
/// `AstronomyEngine` says it is, and the scrub must map a night's span both ways.
@Suite struct SkyDomeTests {
    let iso = ISO8601DateFormatter()
    let engine = AstronomyEngine()
    func date(_ text: String) throws -> Date { try #require(iso.date(from: text)) }
    func park(_ id: String) throws -> Park { try #require(try ParkData.load().first(where: { $0.id == id })) }
    func degrees(between a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        acos(max(-1, min(1, simd_dot(simd_normalize(a), simd_normalize(b)))))*180/Double.pi
    }

    @Test func directionPutsFacingAheadAndZenithUp() {
        let ahead = SkyDome.direction(altitude: 0, azimuth: 180, facing: 180)
        #expect(simd_length(ahead - SIMD3(0, 0, -1)) < 1e-12)
        // Facing south, west is on the right.
        #expect(simd_length(SkyDome.direction(altitude: 0, azimuth: 270, facing: 180) - SIMD3(1, 0, 0)) < 1e-12)
        #expect(simd_length(SkyDome.direction(altitude: 90, azimuth: 42, facing: 180) - SIMD3(0, 1, 0)) < 1e-12)
        let back = SkyDome.horizontal(of: SkyDome.direction(altitude: 32, azimuth: 141, facing: 180), facing: 180)
        #expect(abs(back.altitude - 32) < 1e-9 && abs(back.azimuth - 141) < 1e-9)
    }

    /// Celestial vectors turned by the night's rotation land at the engine's altitude and azimuth.
    @Test func rotationMatchesEngineHorizontal() throws {
        let stars: [(Double, Double)] = [(101.287, -16.716), (279.234, 38.784), (88.793, 7.407), (213.915, 19.182), (37.95, 89.264), (266.405, -29.008)]
        for (id, moment) in [("jotr", "2026-07-15T07:00:00Z"), ("npsa", "2026-12-01T10:00:00Z"), ("gaar", "2026-12-21T09:00:00Z"), ("acad", "2027-03-10T03:30:00Z")] {
            let park = try park(id), at = try date(moment)
            let rotation = SkyDome.rotation(at: at, park: park)
            #expect(abs(rotation.determinant - 1) < 1e-9)
            for (ra, dec) in stars {
                let r = ra*Double.pi/180, d = dec*Double.pi/180
                let h = engine.horizontal(date: at, park: park, ra: r, dec: d)
                let expected = SkyDome.direction(altitude: h.altitude, azimuth: h.azimuth, facing: SkyDome.facing(for: park))
                let turned = rotation*SkyDome.celestial(ra: r, dec: d)
                #expect(degrees(between: turned, expected) < 0.001, "\(id) RA \(ra): \(degrees(between: turned, expected))°")
            }
        }
    }

    @Test func southernParkFacesNorth() throws {
        #expect(SkyDome.facing(for: try park("npsa")) == 0)
        #expect(SkyDome.facing(for: try park("jotr")) == 180)
    }

    /// Galactic longitude 0, latitude 0 is RA 266.405°, Dec −28.936° (IAU 1958 definition, J2000).
    @Test func galacticCentre() {
        let centre = SkyDome.equatorial(galacticLongitude: 0, latitude: 0)
        #expect(abs(centre.ra*180/Double.pi - 266.405) < 0.01)
        #expect(abs(centre.dec*180/Double.pi + 28.936) < 0.01)
        let pole = SkyDome.equatorial(galacticLongitude: 0, latitude: Double.pi/2)
        #expect(abs(pole.dec*180/Double.pi - 27.128) < 0.01)
    }

    @Test func scrubMapsBothWaysAndClamps() throws {
        let park = try park("jotr")
        let sky = engine.conditions(for: park, on: try date("2026-07-15T20:00:00Z"))
        let span = SkyDome.span(for: sky)
        #expect(span.start == sky.sunset && span.end == sky.sunrise)
        for f in [0, 0.25, 0.5, 0.731, 1] { #expect(abs(SkyDome.fraction(of: SkyDome.moment(f, in: span), in: span) - f) < 1e-9) }
        #expect(SkyDome.moment(-1, in: span) == span.start)
        #expect(SkyDome.moment(2, in: span) == span.end)
        #expect(SkyDome.moment(.nan, in: span) == span.start)
        let darkest = SkyDome.darkest(sky)
        #expect(try #require(sky.darkStart) < darkest && darkest < (try #require(sky.darkEnd)))
    }

    /// No sunset in Denali's June and no sunrise in Gates of the Arctic's December still give a night to scrub.
    @Test func polarNightsHaveASpan() throws {
        let june = engine.conditions(for: try park("dena"), on: try date("2026-06-21T20:00:00Z"))
        #expect(SkyDome.span(for: june).duration > 3*3600)
        let december = engine.conditions(for: try park("gaar"), on: try date("2026-12-21T20:00:00Z"))
        #expect(december.state == .polarNight)
        #expect(abs(SkyDome.span(for: december).duration - 16*3600) < 1)
        let darkest = SkyDome.darkest(december)
        #expect(SkyDome.span(for: december).contains(darkest))
    }

    @Test func twilightRevealsBrightStarsFirst() {
        #expect(SkyDome.visibility(.bright, sunAltitude: 0) == 0)
        #expect(SkyDome.visibility(.milkyWay, sunAltitude: -20) == 1)
        for altitude in stride(from: -4.0, through: -16, by: -2) {
            #expect(SkyDome.visibility(.bright, sunAltitude: altitude) >= SkyDome.visibility(.middle, sunAltitude: altitude))
            #expect(SkyDome.visibility(.middle, sunAltitude: altitude) >= SkyDome.visibility(.faint, sunAltitude: altitude))
            #expect(SkyDome.visibility(.faint, sunAltitude: altitude) >= SkyDome.visibility(.milkyWay, sunAltitude: altitude))
        }
        #expect(SkyDome.skyColor(sunAltitude: -3).z > SkyDome.skyColor(sunAltitude: -10).z)
        #expect(SkyDome.skyColor(sunAltitude: -25) == SkyDome.skyColor(sunAltitude: -18))
    }
}
