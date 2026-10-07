import Foundation
import Testing
@testable import Nyx

/// The sky beside the score: eclipses seen in part, planets by twilight and brightness, meteor
/// ranges, the clear window, the observer's notes, and rise and set times against the U.S. Naval
/// Observatory at the polar and tropical parks.
struct ScienceTests {
    let parks: [Park]
    let engine = AstronomyEngine()
    init() throws { parks = try ParkData.load() }
    func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }
    func evening(_ park: Park, _ iso: String) throws -> Date { try #require(TripDay(iso: iso)).evening(in: park) }
    func local(_ text: String, _ park: Park) throws -> Date {
        var style = Date.ParseStrategy(format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)", timeZone: park.timeZone)
        style.isLenient = false
        return try Date(text, strategy: style)
    }

    /// The same sky with a new Moon, so a test of clouds or the core is not decided by moonlight.
    func newMoon(_ sky: SkyConditions) -> SkyConditions {
        SkyConditions(evening: sky.evening, end: sky.end, sunset: sky.sunset, sunrise: sky.sunrise, civilDusk: sky.civilDusk, nauticalDusk: sky.nauticalDusk,
                      darkStart: sky.darkStart, darkEnd: sky.darkEnd, state: sky.state, moon: MoonPhase(fraction: 0), moonrise: nil, moonset: nil,
                      moonBelowFraction: 1, darkHours: sky.darkHours, moonlight: 0, lowestSun: sky.lowestSun)
    }

    // MARK: Eclipses (S6, AS-7)

    /// Virgin Islands, 2026-03-03: totality comes after moonset, but the partial phase is up from
    /// 5:50 to 6:36 AM. It used to read "Not visible".
    @Test func partialPhaseBeforeMoonset() throws {
        let viis = try park("viis")
        let sky = engine.conditions(for: viis, on: try evening(viis, "2026-03-02"))
        let night = try #require(SkyAlmanac().lunarEclipse(SkyEvents.shared.lunarEclipses, for: viis, sky: sky))
        let visible = try #require(night.visible)
        #expect(night.stage == .umbral)
        #expect(abs(visible.start.timeIntervalSince(try local("2026-03-03 05:50", viis))) < 120)
        #expect(abs(visible.end.timeIntervalSince(try local("2026-03-03 06:36", viis))) < 180)
        let item = WhatsUp.eclipseItem(night, park: viis)
        #expect(item.detail.hasPrefix("Sets during the partial phase") && item.timed)
        #expect(WhatsUp.Events(park: viis, sky: sky).glyph == .eclipse)
    }
    /// Badlands, 2029-12-20: the Moon rises at 4:13 PM already in Earth's shadow; partial until 5:28.
    @Test func moonRisesInEarthsShadow() throws {
        let badl = try park("badl")
        let sky = engine.conditions(for: badl, on: try evening(badl, "2029-12-20"))
        let night = try #require(SkyAlmanac().lunarEclipse(SkyEvents.shared.lunarEclipses, for: badl, sky: sky))
        let visible = try #require(night.visible)
        #expect(night.stage == .umbral)
        #expect(abs(visible.start.timeIntervalSince(try local("2029-12-20 16:13", badl))) < 180)
        #expect(abs(visible.end.timeIntervalSince(try local("2029-12-20 17:28", badl))) < 120)
        #expect(WhatsUp.eclipseItem(night, park: badl).detail.hasPrefix("Rises already in Earth's shadow; partial phase visible"))
    }

    // MARK: Planets and meteors (AS-11, AS-14)

    @Test func planetsNeedTwilightForTheirBrightness() throws {
        #expect(SkyAlmanac.twilightLimit(magnitude: -4) == -6 && SkyAlmanac.twilightLimit(magnitude: -1) == -9 && SkyAlmanac.twilightLimit(magnitude: 0.5) == -12)
        // American Samoa, 2027-07-04: Mercury at +2.1 in civil twilight is no longer listed.
        let npsa = try park("npsa")
        let sky = engine.conditions(for: npsa, on: try evening(npsa, "2027-07-04"))
        let planets = SkyAlmanac().planets(for: npsa, sky: sky)
        #expect(!planets.contains { $0.planet == .mercury })
        for planet in planets {
            #expect(planet.bestAltitude >= SkyAlmanac.planetMinimumAltitude - 0.01)
            #expect(engine.solarAltitude(at: planet.best, park: npsa) <= SkyAlmanac.twilightLimit(magnitude: planet.magnitude) + 0.5)
        }
        // Mars at +1.0 is as bright as Spica: "bright", not "faint".
        #expect(WhatsUp.brightness(1.04) == "bright" && WhatsUp.brightness(1.6) == "faint")
    }
    @Test func meteorRatesAreARange() {
        #expect(WhatsUp.rateText(130) == "70–130 an hour")
        #expect(WhatsUp.rateText(20) == "10–20 an hour")
        #expect(WhatsUp.rateText(1) == "about 1 an hour")
        #expect(WhatsUp.rateText(0) == "fewer than 1 an hour")
    }

    // MARK: The clear window (AS-5)

    /// Joshua Tree, the night clocks fall back (2027-11-06, with the Moon set aside): clear until
    /// 1:30 AM PST, then overcast. The window ends at 1:30 standard time, not daylight time.
    @Test func clearWindowAcrossDaylightSaving() throws {
        let jotr = try park("jotr")
        let sky = newMoon(engine.conditions(for: jotr, on: try evening(jotr, "2027-11-06")))
        let dusk = try #require(sky.darkStart)
        let boundary = Date(timeIntervalSince1970: try local("2027-11-07 01:30", jotr).timeIntervalSince1970)
        // The parse picks the first 1:30 (daylight time); the clouds turn at the second, an hour later.
        let standard = boundary.addingTimeInterval(jotr.timeZone.isDaylightSavingTime(for: boundary) ? 3600 : 0)
        let first = floor(dusk.timeIntervalSince1970/3600)*3600-3*3600
        let hours = (0..<24).map { first+Double($0)*3600 }.map { (time: Date(timeIntervalSince1970: $0), cloud: $0 < standard.timeIntervalSince1970 ? 5.0 : 100) }
        let window = try #require(ClearWindow.find(park: jotr, sky: sky, hours: hours))
        #expect(abs(window.interval.start.timeIntervalSince(try #require(sky.darkStart))) < 120)
        #expect(abs(window.interval.end.timeIntervalSince(standard)) < 120)
        #expect(window.line(park: jotr).hasPrefix("Best window: "))
        #expect(window.line(park: jotr).contains(jotr.time(standard)))
        #expect(!window.moonDown) // new moon: nothing to say about the Moon
    }
    @Test func clearWindowNamesMoonAndCore() throws {
        let jotr = try park("jotr")
        // 2027-07-04, new moon: the core is up in July darkness; clear all night.
        let sky = engine.conditions(for: jotr, on: try evening(jotr, "2027-07-04"))
        let first = floor(sky.evening.timeIntervalSince1970/3600)*3600
        let hours = (0..<30).map { (time: Date(timeIntervalSince1970: first+Double($0)*3600), cloud: 0.0) }
        let window = try #require(ClearWindow.find(park: jotr, sky: sky, hours: hours))
        #expect(window.core != nil)
        #expect(window.line(park: jotr).contains("clear"))
        // Overcast all night: no window, and nothing is said.
        #expect(ClearWindow.find(park: jotr, sky: sky, hours: hours.map { ($0.time, 90.0) }) == nil)
    }
    @Test func clearWindowNeedsTrueDarkness() throws {
        let dena = try park("dena")
        let summer = engine.conditions(for: dena, on: try evening(dena, "2026-06-21"))
        let hours = (0..<30).map { (time: summer.evening.addingTimeInterval(Double($0)*3600), cloud: 0.0) }
        #expect(ClearWindow.find(park: dena, sky: summer, hours: hours) == nil)
        let gaar = try park("gaar")
        let polarNight = engine.conditions(for: gaar, on: try evening(gaar, "2026-12-21"))
        let dark = (0..<30).map { (time: polarNight.evening.addingTimeInterval(Double($0)*3600), cloud: 0.0) }
        let window = try #require(ClearWindow.find(park: gaar, sky: polarNight, hours: dark))
        #expect(window.interval.duration > 6*3600)
    }

    // MARK: Observer's notes (AS-12)

    @Test func auroraSeasonInAlaskaOnly() throws {
        let dena = try park("dena"), jotr = try park("jotr")
        #expect(SkyNotes.aurora(park: dena, evening: try evening(dena, "2026-10-15"))?.contains("Nyx does not forecast aurora") == true)
        #expect(SkyNotes.aurora(park: dena, evening: try evening(dena, "2026-06-15")) == nil)
        #expect(SkyNotes.aurora(park: jotr, evening: try evening(jotr, "2026-10-15")) == nil)
        #expect(parks.filter { SkyNotes.aurora(park: $0, evening: (try? evening($0, "2026-12-01")) ?? .now) != nil }.count == 8)
    }
    @Test func satellitesCatchSunlight() throws {
        #expect(abs(SkyNotes.shellDepression-23.0) < 0.1)
        let jotr = try park("jotr")
        let winter = engine.conditions(for: jotr, on: try evening(jotr, "2026-12-21"))
        #expect(SkyNotes.satellites(park: jotr, sky: winter)?.hasPrefix("Satellites overhead catch sunlight until") == true)
        // At 44° N in June the Sun never reaches 23° down: satellites cross all night.
        let acad = try park("acad")
        let june = engine.conditions(for: acad, on: try evening(acad, "2026-06-21"))
        if june.darkHours > 0 { #expect(SkyNotes.satellites(park: acad, sky: june)?.contains("all through true darkness") == true) }
        let dena = try park("dena")
        #expect(SkyNotes.satellites(park: dena, sky: engine.conditions(for: dena, on: try evening(dena, "2026-06-21"))) == nil)
    }
    @Test func zodiacalLightBySeasonAndHemisphere() throws {
        let jotr = try park("jotr"), npsa = try park("npsa")
        // New moon, March: evening, west. New moon, October: morning, east.
        #expect(SkyNotes.zodiacal(park: jotr, sky: engine.conditions(for: jotr, on: try evening(jotr, "2027-03-08")))?.contains("west after dusk") == true)
        #expect(SkyNotes.zodiacal(park: jotr, sky: engine.conditions(for: jotr, on: try evening(jotr, "2026-10-10")))?.contains("east before dawn") == true)
        // American Samoa, inverted: March is a morning season.
        #expect(SkyNotes.zodiacal(park: npsa, sky: engine.conditions(for: npsa, on: try evening(npsa, "2027-03-08")))?.contains("east before dawn") == true)
        // A bright sky shows none.
        let cuva = try park("cuva")
        #expect(SkyNotes.zodiacal(park: cuva, sky: engine.conditions(for: cuva, on: try evening(cuva, "2027-03-08"))) == nil)
    }
    @Test func limitingMagnitudeFallsWithMoonGlowAndHaze() throws {
        let grba = try park("grba"), cuva = try park("cuva")
        let newMoon = engine.conditions(for: grba, on: try evening(grba, "2026-11-09"))
        let fullMoon = engine.conditions(for: grba, on: try evening(grba, "2026-11-24"))
        let dark = try #require(SkyNotes.limitingMagnitude(park: grba, sky: newMoon, aerosol: nil))
        #expect(dark > 7 && dark <= SkyAlmanac.limitingMagnitude(bortle: grba.bortleEstimate))
        #expect(try #require(SkyNotes.limitingMagnitude(park: grba, sky: fullMoon, aerosol: nil)) < dark - 1)
        #expect(try #require(SkyNotes.limitingMagnitude(park: grba, sky: newMoon, aerosol: 0.8)) < dark - 0.5)
        let city = engine.conditions(for: cuva, on: try evening(cuva, "2026-11-09"))
        #expect(try #require(SkyNotes.limitingMagnitude(park: cuva, sky: city, aerosol: nil)) < dark - 1.5)
    }
    @Test func coreRisesIntoALightDome() throws {
        let jotr = try park("jotr")
        let sky = engine.conditions(for: jotr, on: try evening(jotr, "2027-07-10"))
        let core = SkyAlmanac().core(for: jotr, sky: sky)
        let dark = try #require(core.dark)
        let azimuth = SkyAlmanac().highest(ra: SkyAlmanac.coreRA, dec: SkyAlmanac.coreDec, park: jotr, in: dark).azimuth
        func site(_ glow: Double, _ domes: [SkyGlow.Dome]) -> SkyGlow.Site { SkyGlow.Site(glow: glow, bortle: 3, profile: [], domes: domes) }
        var sites = Dictionary(uniqueKeysWithValues: (0..<10).map { ("p\($0)", site(0.1, [])) })
        sites["jotr"] = site(5, [SkyGlow.Dome(bearing: azimuth+10, share: 0.6, city: "Testville")])
        #expect(SkyNotes.coreGlow(park: jotr, sky: sky, core: core, glow: SkyGlow(parks: sites)) == "The core rises into the glow of Testville.")
        sites["jotr"] = site(5, [SkyGlow.Dome(bearing: azimuth+90, share: 0.6, city: "Testville")])
        #expect(SkyNotes.coreGlow(park: jotr, sky: sky, core: core, glow: SkyGlow(parks: sites)) == nil)
    }

    // MARK: Rise and set against the U.S. Naval Observatory (AS-15)

    /// Polar, tropical and Caribbean parks: the Moon within 180 seconds and the Sun within 60.
    @Test func polarAndTropicalReferences() throws {
        struct File: Decodable { struct Case: Decodable { let park: String; let night: String; let event: String; let local: String? }; let cases: [Case] }
        let url = try #require(Bundle(for: BundleAnchor.self).url(forResource: "usno-polar-tropical", withExtension: "json"))
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        #expect(file.cases.count == 20)
        for item in file.cases {
            let park = try park(item.park)
            let sky = engine.conditions(for: park, on: try evening(park, item.night))
            switch item.event {
            case "moonBelowAllNight":
                #expect(sky.moonrise == nil && sky.moonset == nil, "\(item.park) \(item.night)")
                #expect(engine.lunarAltitude(at: sky.evening.addingTimeInterval(12*3600), park: park) < 0)
            case "sunset":
                let actual = try local(try #require(item.local), park)
                #expect(abs(try #require(sky.sunset).timeIntervalSince(actual)) < 60, "\(item.park) \(item.night) sunset")
            default:
                let actual = try local(try #require(item.local), park)
                let predicted = item.event == "moonrise" ? sky.moonrise : sky.moonset
                #expect(abs(try #require(predicted, "\(item.park) \(item.night) \(item.event)").timeIntervalSince(actual)) < 180, "\(item.park) \(item.night) \(item.event)")
            }
        }
    }
}
