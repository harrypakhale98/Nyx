import Foundation
import Testing
@testable import Nyx

/// Rules the Vision Pro sky shares with the iPhone: one weight for a night's drawn and scored
/// clouds, one rule for pointing to the galactic core, and spoken lines that say their own note.
struct VisionSkyRulesTests {
    func park(_ id: String) throws -> Park { try #require(try ParkData.load().first { $0.id==id }) }

    /// Every hour of a night is eased toward the usual clouds by the weight the score gave the
    /// night (its lead to the middle of the cloud window), not by each hour's own lead: near the
    /// ten-day edge the hour drawn at dawn keeps the night's share of the forecast.
    @Test func skyCloudEasesByTheNightsWeight() throws {
        let issued=Date(timeIntervalSince1970: 1_790_000_000)
        let times=(0..<384).map { (issued.timeIntervalSince1970/3600).rounded(.down)*3600+Double($0)*3600 }
        let forecast=Forecast(updated: issued, times: times, clouds: times.map { _ in 80 })
        let middle=issued.addingTimeInterval(9.5*86400), dawn=issued.addingTimeInterval(9.9*86400)
        let weight=CloudBasis.forecastWeight(leadDays: 9.5)
        let basis=CloudBasis.from(weight: weight, leadDays: 9.5)
        let drawn=try #require(SkyDome.cloud(at: dawn, forecast: forecast, basis: basis, usual: 50, reference: middle))
        #expect(abs(drawn-(weight*80+(1-weight)*50)/100) < 1e-9)
        // Measured from the hour itself, the same hour would have eased further than the score did.
        let own=try #require(SkyDome.cloud(at: dawn, forecast: forecast, basis: basis, usual: 50))
        #expect(own < drawn)
        // Near the three-day edge, a night scored as a full forecast draws its late hours at full weight too.
        let near=try #require(SkyDome.cloud(at: issued.addingTimeInterval(3.2*86400), forecast: forecast, basis: .forecast, usual: 50,
                                            reference: issued.addingTimeInterval(2.9*86400)))
        #expect(near == 0.8)
    }

    /// The core is pointed to only above the horizon and once most of the band shows.
    @Test func coreVisibilityIsOneRule() {
        #expect(!SkyDome.coreVisible(altitude: -1, sunAltitude: -30))
        #expect(!SkyDome.coreVisible(altitude: 20, sunAltitude: -12))
        #expect(SkyDome.coreVisible(altitude: 20, sunAltitude: -15))
        #expect(SkyDome.coreVisible(altitude: 20, sunAltitude: -40))
        // The threshold is where the Milky Way's layer passes 0.3.
        for sun in stride(from: -20.0, through: -10, by: 0.1) {
            #expect(SkyDome.coreVisible(altitude: 10, sunAltitude: sun) == (SkyDome.visibility(.milkyWay, sunAltitude: sun) > 0.3))
        }
    }

    /// VoiceOver hears the same localized note the row shows, not a fixed English one.
    @Test func spokenLinesSayTheirNote() throws {
        let deva=try park("deva")
        let night=try #require(deva.calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12)))
        let sky=AstronomyEngine().conditions(for: deva, on: night)
        let glow=WhatsUp.gegenscheinItem(SkyAlmanac.Gegenschein(at: night.addingTimeInterval(12*3600), altitude: 50, azimuth: 180), park: deva)
        let note=try #require(glow.note)
        #expect(glow.spoken == "\(glow.title), \(note). \(glow.detail)")
        let window=SkyAlmanac.nightWindow(sky)
        let planet=SkyAlmanac.PlanetNight(planet: .venus, magnitude: -4, visible: window, best: window.start.addingTimeInterval(1800),
                                          bestAltitude: 12, bestAzimuth: 250, rises: nil, sets: nil)
        let best=WhatsUp.planetBestItem(planet, day: night, park: deva, sky: sky)
        let bestNote=try #require(best.note)
        #expect(best.spoken == "\(best.title), \(bestNote). \(best.detail)")
    }
}
