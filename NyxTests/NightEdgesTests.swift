import Foundation
import Testing
@testable import Nyx

/// The edges of a night: the sunset and sunrise that belong to it far from a zone's meridian,
/// planet rises and sets that frame what is seen, clouds where no usual clouds are known, ties that
/// rank the same in any order, a trip's last night across a change of clocks, and Handoff days.
@Suite struct NightEdgesTests {
    let parks: [Park] = (try? ParkData.load()) ?? []
    let engine = AstronomyEngine()
    func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }
    func noon(_ park: Park, _ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(park.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }
    /// Auyuittuq, Baffin Island: east of its zone's meridian, so on a short December day the Sun
    /// sets before local noon.
    let auyuittuq = Park(id: "wd:Q789743", nps: nil, name: "Auyuittuq", countryCode: "CA", region: "NU", kind: .custom, curated: false,
                         latitude: 67.5, longitude: -66, timeZoneID: "America/Iqaluit", darkSkyDesignated: false, bortleEstimate: 1,
                         description: "", sourceURL: "", sourceNote: "", viewingSpots: [])

    // MARK: Sunset and sunrise

    @Test func anArcticNightKeepsItsOwnSunsetWhenTheSunSetsBeforeNoon() throws {
        let place = auyuittuq
        let sky = engine.conditions(for: place, on: try noon(place, 2026, 12, 11))
        let sunset = try #require(sky.sunset), sunrise = try #require(sky.sunrise)
        // Before the window opens, on the night's own day; never the next day's sunset.
        #expect(sunset < sky.evening && sunset > sky.evening.addingTimeInterval(-6*3600))
        #expect(place.calendar.component(.day, from: sunset) == 11)
        #expect(sunrise > sunset && sunrise < sky.end && place.calendar.component(.day, from: sunrise) == 12)
        #expect(sky.state == .normal && sky.darkHours > 0)
        // The next night's sunset comes after this night's sunrise: no sunset is told twice.
        let next = engine.conditions(for: place, on: try noon(place, 2026, 12, 12))
        let nextSunset = try #require(next.sunset)
        #expect(nextSunset > sunrise && place.calendar.component(.day, from: nextSunset) == 12)
    }
    /// The U.S. parks keep the times they had: Joshua Tree, Gates of the Arctic as polar night
    /// begins (a sunset, no sunrise), and Kobuk Valley in January, whose sunrise comes after noon.
    @Test func usParksKeepTheirSunsetsAndSunrises() throws {
        func check(_ id: String, _ y: Int, _ m: Int, _ d: Int, sunset: Double, sunrise: Double?) throws {
            let p = try park(id)
            let sky = engine.conditions(for: p, on: try noon(p, y, m, d))
            let set = try #require(sky.sunset, "\(id)")
            #expect(abs(set.timeIntervalSince1970-sunset) < 60, "\(id) sunset")
            if let sunrise {
                #expect(abs((sky.sunrise?.timeIntervalSince1970 ?? 0)-sunrise) < 60, "\(id) sunrise")
            } else {
                #expect(sky.sunrise == nil, "\(id) sunrise")
            }
        }
        try check("jotr", 2026, 12, 11, sunset: 1797035691, sunrise: 1797086354)
        try check("gaar", 2026, 12, 11, sunset: 1797027425, sunrise: nil)
        try check("kova", 2026, 1, 1, sunset: 1767310420, sunrise: 1767390237)
    }

    // MARK: Planets

    /// Venus at Denali on 2028-03-15 is up at dusk, sets after midnight and rises again before
    /// sunrise: its rise and set frame the evening stretch it is seen, never "8:14 AM – 1:48 AM".
    @Test func aPlanetsRiseAndSetFrameTheStretchItIsSeen() throws {
        let almanac = SkyAlmanac()
        for (id, y, m, d) in [("dena", 2028, 3, 15), ("gaar", 2026, 1, 1)] {
            let p = try park(id)
            let sky = engine.conditions(for: p, on: try noon(p, y, m, d))
            let planets = almanac.planets(for: p, sky: sky)
            #expect(!planets.isEmpty)
            for planet in planets {
                if let rises = planet.rises { #expect(rises <= planet.visible.start, "\(id) \(planet.planet)") }
                if let sets = planet.sets { #expect(sets >= planet.visible.end, "\(id) \(planet.planet)") }
                if let rises = planet.rises, let sets = planet.sets { #expect(rises < sets, "\(id) \(planet.planet)") }
            }
        }
        let dena = try park("dena")
        let venus = try #require(almanac.planets(for: dena, sky: engine.conditions(for: dena, on: try noon(dena, 2028, 3, 15))).first { $0.planet == .venus })
        #expect(venus.rises == nil && venus.sets != nil)
        let gaar = try park("gaar")
        let saturn = try #require(almanac.planets(for: gaar, sky: engine.conditions(for: gaar, on: try noon(gaar, 2026, 1, 1))).first { $0.planet == .saturn })
        #expect(saturn.rises == nil && saturn.sets != nil)
    }

    // MARK: Clouds with no usual clouds

    /// A place with no usual clouds: a forecast counts as it stands while it counts at all, said
    /// as an early look counted as it stands; ten days out the cloud term is dropped and the
    /// score counts the Moon and darkness only, as its words say.
    @Test func withNoUsualCloudsAFadedForecastIsDropped() throws {
        let jotr = try park("jotr"), now = Date(timeIntervalSince1970: 1_792_180_800)
        let start = now.timeIntervalSince1970-86400
        let times = (0..<(17*24)).map { start+Double($0)*3600 }
        let forecast = Forecast(updated: now, times: times, clouds: times.map { _ in 80 })
        let bare = CloudClimate(parks: [:])
        func night(_ days: Int) -> Night {
            let sky = engine.conditions(for: jotr, on: jotr.date(jotr.currentNight(at: now), addingDays: days))
            return NightPlanner.night(park: jotr, sky: sky, forecast: forecast, detail: nil, now: now, climate: bare)
        }
        let near = night(1), early = night(6), far = night(11)
        #expect(near.basis == .forecast && abs((near.score.cloudUsed ?? 0)-80) < 0.01)
        #expect(early.basis.isEarlyLook && abs((early.score.cloudUsed ?? 0)-80) < 0.01 && early.usualCloud == nil)
        let caption = try #require(early.basisCaption())
        #expect(caption.contains("counted as it stands") && !caption.contains("eased"))
        #expect(early.basisLine == "Early look · forecast counted as it stands")
        #expect(far.basis == .usual && far.score.cloudPoints == nil && far.score.cloudUsed == nil && far.cloudCover == nil)
        #expect(far.score.value == ScoreEngine().score(sky: far.sky, bortle: jotr.bortleEstimate, cloudCover: nil).value)
        #expect(far.beyondForecast && far.basisCaption()?.contains("This score counts the Moon and darkness only.") == true)
    }

    // MARK: Ties

    /// Three nights at one park, all scoring 80, whose sums of parts sit 0.3 apart: with a
    /// tolerance, A tied B and B tied C while C beat A. On a grid every order ranks them alike.
    @Test func tiesRankTheSameInAnyOrder() throws {
        let jotr = try park("jotr"), first = jotr.currentNight(at: Date(timeIntervalSince1970: 1_792_180_800))
        func night(_ offset: Int, moon: Double) -> Night {
            Night(park: jotr, sky: engine.conditions(for: jotr, on: jotr.date(first, addingDays: offset)),
                  score: DarknessScore(value: 80, moonPoints: moon, cloudPoints: 20, bortlePoints: 15, lengthPoints: 10), cloudCover: 20, forecastUpdated: nil)
        }
        // October: true darkness grows a few minutes every two nights.
        let c = night(1, moon: 25.6), b = night(3, moon: 25.3), a = night(5, moon: 25.0)
        #expect(a.sky.darkHours > b.sky.darkHours + 1.0/60 && b.sky.darkHours > c.sky.darkHours + 1.0/60)
        let all = [a, b, c]
        for x in all { for y in all { for z in all where NightPlanner.better(x, y) && NightPlanner.better(y, z) {
            #expect(NightPlanner.better(x, z), "\(x.id) \(y.id) \(z.id)")
        } } }
        for x in all { for y in all where x.id != y.id { #expect(NightPlanner.better(x, y) != NightPlanner.better(y, x)) } }
        let orders = [[a, b, c], [a, c, b], [b, a, c], [b, c, a], [c, a, b], [c, b, a]]
        let ranked = Set(orders.map { NightPlanner.ranked($0).map(\.id) })
        #expect(ranked.count == 1)
        // The trip planner's summed tie-breaks agree with `better` night by night.
        for x in all { for y in all where x.id != y.id {
            #expect(TripPlanner.Tie(x).beats(TripPlanner.Tie(y)) == NightPlanner.better(x, y))
        } }
    }

    // MARK: Trip and Handoff days

    /// Thirteen calendar days on, across the end of daylight saving time: never a day short.
    @Test func theLatestLastNightCountsCalendarDays() throws {
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let first = try #require(pacific.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 0, minute: 30)))
        let last = TripPlanner.latestLast(first: first, weekendsOnly: false, calendar: pacific)
        let parts = pacific.dateComponents([.month, .day, .hour, .minute], from: last)
        #expect(parts.month == 11 && parts.day == 7 && parts.hour == 0 && parts.minute == 30)
        #expect(TripPlanner.clampedLast(first.addingTimeInterval(40*86400), first: first, weekendsOnly: false, calendar: pacific) == last)
    }
    @Test func handoffNamesOnlyRealDays() {
        #expect(ParkHandoff(userInfo: ["park": "jotr", "night": "2026-02-31"])?.night == nil)
        #expect(ParkHandoff(userInfo: ["park": "jotr", "night": "2026-02-29"])?.night == nil)
        #expect(ParkHandoff(userInfo: ["park": "jotr", "night": "2026-04-31"])?.night == nil)
        #expect(ParkHandoff(userInfo: ["park": "jotr", "night": "2028-02-29"])?.night == "2028-02-29")
        #expect(ParkHandoff(parkID: auyuittuq.id, night: "2026-02-31").evening(in: auyuittuq) == nil)
    }
}
