import Foundation
import Testing
@testable import Nyx

/// Haleakalā past its cloud layers' days, the forecast-only points at Denali and Kenai Fjords, and
/// the Moonlight line on nights with no true darkness.
@MainActor struct SummitAndSitesTests {
    let engine=AstronomyEngine()
    func evening(_ park: Park, _ iso: String) throws -> Date { try #require(TripDay(iso: iso)).evening(in: park) }
    func forecast(updated: Date, cover: Double) -> Forecast {
        let start=updated.timeIntervalSince1970-86400
        return Forecast(updated: updated, times: (0..<(17*24)).map { start+Double($0)*3600 }, clouds: Array(repeating: cover, count: 17*24))
    }

    // MARK: Haleakalā past its layers

    /// Ten days out, past any layer forecast asked for now, the summit counts no cloud at all: its usual
    /// clouds are total cloud, mostly the inversion's low cloud below the summit. Labelled "Moon and
    /// darkness only" and drawn hollow, even with a total-cloud forecast that reaches the night.
    @Test func aSummitNightPastItsLayersCountsTheMoonAndDarknessOnly() throws {
        let hale=try park("hale")
        let night=try evening(hale, "2026-12-09")
        let s=engine.conditions(for: hale, on: night)
        let now=night.addingTimeInterval(-10*86400)
        for total in [nil, forecast(updated: now, cover: 90)] {
            let far=NightPlanner.night(park: hale, sky: s, forecast: total, detail: nil, now: now)
            #expect(far.score.cloudPoints == nil && far.usualCloud == nil && far.cloudCover == nil)
            #expect(far.basis == .usual && far.basis.fill == .hollow && far.beyondForecast)
            #expect(far.basisCaption()?.contains(String(localized: "This score counts the Moon and darkness only.")) == true)
            #expect(far.basisLine == String(localized: "No cloud forecast yet · Moon and darkness only"))
            #expect(far.score.bandWithBasis == String(localized: "\(far.score.band.label), Moon and darkness only"))
            #expect(far.typicalClouds == nil)
            // Where its label stands alone under the score (the watch), it says so rather than "No cloud forecast yet".
            #expect(far.standaloneBasisLabel == String(localized: "Moon and darkness only"))
            // So does the line under a widget's or the watch week's band word.
            #expect(far.basisNote == String(localized: "Moon and darkness only"))
        }
        // Layers asked for three days earlier reach no further: still the Moon and darkness only.
        let old=now.addingTimeInterval(-3*86400)
        let start=old.timeIntervalSince1970
        let layers=HourlySeries(updated: old, times: (0..<(7*24)).map { start+Double($0)*3600 },
                                values: ["cloud_cover_mid": Array(repeating: 10, count: 7*24), "cloud_cover_high": Array(repeating: 10, count: 7*24)])
        let layered=NightPlanner.night(park: hale, sky: s, forecast: nil, detail: ForecastDetail(layers: layers), now: now)
        #expect(layered.score.cloudPoints == nil && layered.beyondForecast)
    }
    /// Three days out with no layers yet (offline, or not asked for): the usual clouds still count, so
    /// tonight offline never reads as if the summit were always clear; "Cloud forecast unavailable".
    @Test func aSummitNightWithinItsLayersKeepsTheUsualClouds() throws {
        let hale=try park("hale")
        let night=try evening(hale, "2026-12-09")
        let s=engine.conditions(for: hale, on: night)
        let near=NightPlanner.night(park: hale, sky: s, forecast: nil, detail: nil, now: night.addingTimeInterval(-3*86400))
        #expect(near.usualCloud != nil && near.score.cloudPoints != nil && near.basis == .usual && !near.beyondForecast)
        #expect(near.basisLabel == String(localized: "Cloud forecast unavailable") && near.standaloneBasisLabel == near.basisLabel && near.basisNote == near.basisLabel)
        // Every other park keeps its usual clouds ten days out.
        let havo=try park("havo")
        let far=NightPlanner.night(park: havo, sky: engine.conditions(for: havo, on: try evening(havo, "2026-12-09")), forecast: nil, detail: nil,
                                   now: night.addingTimeInterval(-10*86400))
        #expect(far.usualCloud != nil && far.score.cloudPoints != nil)
    }
    /// A Moon-and-darkness-only night reads high on any moonless night, so wherever nights are ranked
    /// (a best night recommended, or the darkest named) it comes after every night whose clouds count;
    /// the scores shown are unchanged.
    @Test func aNightWithoutCloudsRanksAfterNightsWithThem() throws {
        let hale=try park("hale"), jotr=try park("jotr")
        let haleNight=try evening(hale, "2026-12-09"), jotrNight=try evening(jotr, "2026-12-09")
        let now=jotrNight.addingTimeInterval(-10*86400)
        let bare=NightPlanner.night(park: hale, sky: engine.conditions(for: hale, on: haleNight), forecast: nil, detail: nil, now: now)
        let counted=NightPlanner.night(park: jotr, sky: engine.conditions(for: jotr, on: jotrNight), forecast: forecast(updated: jotrNight.addingTimeInterval(-86400), cover: 25), detail: nil,
                                       now: jotrNight.addingTimeInterval(-86400))
        try #require(bare.score.cloudPoints == nil && counted.score.cloudPoints != nil)
        #expect(bare.score.value > counted.score.value)
        #expect(NightPlanner.better(counted, bare, closures: [:]) && !NightPlanner.better(bare, counted, closures: [:]))
        // Even with a closure at the counted night's park.
        #expect(NightPlanner.better(counted, bare, closures: ["jotr": "Park Boulevard closed"]))
        #expect(NightPlanner.ranked([bare, counted], closures: [:]).map(\.park.id) == ["jotr", "hale"])
        #expect(NightPlanner.best([bare, counted])?.park.id == "jotr")
        #expect(NightPlanner.better(counted, bare) && !NightPlanner.better(bare, counted))
        #expect(NightPlanner.ranked([bare, counted]).map(\.park.id) == ["jotr", "hale"])
        #expect(WidgetSelection.ordered([bare, counted]).first?.park.id == "jotr")
        // The park page's "Darker on…" never names a night the score cannot see clouds for.
        let tonight=NightPlanner.night(park: hale, sky: engine.conditions(for: hale, on: hale.date(haleNight, addingDays: -10)), forecast: nil, detail: nil,
                                       now: now)
        let ahead=(0..<NightPlanner.horizon).map { NightPlanner.night(park: hale, sky: engine.conditions(for: hale, on: hale.date(tonight.id, addingDays: $0)), forecast: nil, detail: nil, now: now) }
        #expect(ahead.contains { $0.score.cloudPoints == nil } && NightPlanner.best(ahead)?.score.cloudPoints != nil)
        if let darker=NightVerdict.darker(than: tonight, among: ahead) { #expect(darker.score.cloudPoints != nil) }
    }

    /// The trip planner keeps the same rule: a night that counts no clouds is chosen only when no
    /// night in reach counts them, so a one-night trip picks `NightPlanner.best`'s night, and so does
    /// every night of a longer one. The week across parks puts the counted park's row first.
    @Test func theTripPlannerAndTheWeekPutCountedNightsFirst() throws {
        let hale=try park("hale"), havo=try park("havo")
        let days=try ["2026-12-08", "2026-12-09", "2026-12-10"].map { try #require(TripDay(iso: $0)) }
        let now=try evening(hale, "2026-12-08").addingTimeInterval(-10*86400)
        let grid=TripPlanner.nights(parks: [hale, havo], days: days, forecasts: [:], now: now)
        for row in grid {
            let bare=try #require(row.first { $0.park.id == "hale" }), counted=try #require(row.first { $0.park.id == "havo" })
            try #require(bare.score.cloudPoints == nil && counted.score.cloudPoints != nil && bare.score.value > counted.score.value)
            #expect(NightPlanner.best(row)?.park.id == "havo")
        }
        let one=TripPlanner.plan(days: [days[1]], grid: [grid[1]], closures: [:], maxHopMeters: 1e9)
        #expect(one.stops.map(\.night.park.id) == [NightPlanner.best(grid[1])?.park.id])
        let three=TripPlanner.plan(days: days, grid: grid, closures: [:], maxHopMeters: 1e9)
        #expect(three.stops.map(\.night.park.id) == ["havo", "havo", "havo"])
        // Even when the counted park lists a closure.
        #expect(TripPlanner.plan(days: [days[1]], grid: [grid[1]], closures: ["havo": "Crater Rim Drive closed"], maxHopMeters: 1e9).stops.first?.night.park.id == "havo")
        let weeks=[hale, havo].map { park in (0..<WeekAcrossParks.nights).map { NightPlanner.night(park: park, sky: engine.conditions(for: park, on: park.date(days[0].evening(in: park), addingDays: $0)), forecast: nil, detail: nil, now: now) } }
        let week=WeekAcrossParks.make(weeks)
        #expect(week.rows.map(\.park.id) == ["havo", "hale"])
        #expect(week.best.map { week.rows[$0.row].park.id } == "havo")
        // A week's dots are sized across the nights that count clouds; with none, across all of them.
        let mixed=[weeks[0][0], weeks[1][0], weeks[1][1]], counted=[weeks[1][0].score.value, weeks[1][1].score.value]
        let range=NightMark.range(mixed), bare=NightMark.range(weeks[0])
        #expect(range.low == counted.min() && range.high == counted.max())
        #expect(bare.low == weeks[0].map(\.score.value).min() && bare.high == weeks[0].map(\.score.value).max())
    }
    /// Layers asked for on the UTC day before end an hour short of the seventh night: from 00:00 UTC
    /// (2 p.m. in Hawaii) until they are asked for again, that night is past them, never scored on
    /// the summit's total cloud.
    @Test func theSeventhNightStaysPastLayersAskedForTheDayBefore() throws {
        let hale=try park("hale")
        var utc=Calendar(identifier: .gregorian)
        utc.timeZone=try #require(TimeZone(identifier: "UTC"))
        let asked=try #require(utc.date(from: DateComponents(year: 2026, month: 12, day: 2, hour: 14)))
        let start=utc.startOfDay(for: asked).timeIntervalSince1970
        let hours=NightPlanner.layerDays*24
        let layers=HourlySeries(updated: asked, times: (0..<hours).map { start+Double($0)*3600 },
                                values: ["cloud_cover_mid": Array(repeating: 10, count: hours), "cloud_cover_high": Array(repeating: 10, count: hours)])
        let now=try #require(utc.date(from: DateComponents(year: 2026, month: 12, day: 3, hour: 0, minute: 30)))
        let seventh=hale.date(hale.currentNight(at: now), addingDays: 6)
        let sky=engine.conditions(for: hale, on: seventh)
        try #require(!NightPlanner.pastLayers(sky.cloudWindow, now: now))
        try #require(sky.cloudWindow.end.timeIntervalSince1970 > start+Double(hours-1)*3600+1800)
        let night=NightPlanner.night(park: hale, sky: sky, forecast: forecast(updated: now, cover: 90), detail: ForecastDetail(layers: layers), now: now)
        #expect(night.score.cloudPoints == nil && night.usualCloud == nil && night.beyondForecast)
        #expect(night.score.bandWithBasis == String(localized: "\(night.score.band.label), Moon and darkness only"))
        // The sixth night, which the layers cover, counts them.
        let sixth=NightPlanner.night(park: hale, sky: engine.conditions(for: hale, on: hale.date(seventh, addingDays: -1)), forecast: nil,
                                     detail: ForecastDetail(layers: layers), now: now)
        #expect(sixth.upperCloudOnly && sixth.score.cloudPoints != nil)
        // Layers too old to use say nothing about where today's would end: the usual clouds, "unavailable".
        let later=asked.addingTimeInterval(Forecast.recentFor+3600)
        let stale=NightPlanner.night(park: hale, sky: sky, forecast: nil, detail: ForecastDetail(layers: layers), now: later)
        #expect(!NightPlanner.pastLayers(sky.cloudWindow, layers: layers, now: later))
        #expect(stale.score.cloudPoints != nil && stale.usualCloud != nil && !stale.beyondForecast)
    }

    // MARK: Denali and Kenai Fjords

    /// Their clouds are asked for at the visitor centres people reach by road, not in the wilderness at
    /// the park's centre; neither point is a viewing spot, and the sky stays at the centre.
    @Test func denaliAndKenaiFjordsForecastAtTheirVisitorCentres() throws {
        let dena=try park("dena"), kefj=try park("kefj")
        #expect(dena.forecastPoint == (63.73091, -148.91713))
        #expect(kefj.forecastPoint == (60.18833, -149.63165))
        #expect(dena.viewingSpots.isEmpty && kefj.viewingSpots.isEmpty)
        #expect(dena.forecastSite?.sourceURL.hasPrefix("https://www.nps.gov/dena/") == true && kefj.forecastSite?.sourceURL.hasPrefix("https://www.nps.gov/kefj/") == true)
        #expect((dena.latitude, dena.longitude) == (63.29777484, -151.0526568))
        // Only these two have one; a park with spots keeps its first spot.
        let parks=try ParkData.load()
        #expect(parks.filter { $0.forecastSite != nil }.map(\.id).sorted() == ["dena", "kefj"])
        let hale=try park("hale"), first=try #require(hale.viewingSpots.first)
        #expect(hale.forecastPoint == (first.latitude, first.longitude))
        // The terrain horizon stays at the first viewing spot, or the park's own point, never the forecast point.
        #expect(Horizon.Table.shared.main(dena).map { $0.spot == nil } ?? true)
        if let main=Horizon.Table.shared.main(hale) { #expect(main.spot == first.name) }
        // The point round-trips with the park.
        #expect(try JSONDecoder().decode(Park.self, from: JSONEncoder().encode(dena)) == dena)
    }

    // MARK: Moonlight without true darkness

    @Test func theMoonlightLineFollowsTheDarkness() throws {
        let glac=try park("glac")
        let june=engine.conditions(for: glac, on: try evening(glac, "2027-06-20"))
        let december=engine.conditions(for: glac, on: try evening(glac, "2026-12-09"))
        #expect(june.darkHours == 0 && december.darkHours > 0)
        // With no true darkness the engine counts the Moon by its phase alone, as the line says.
        let light=ScoreEngine().score(sky: june, bortle: glac.bortleEstimate, cloud: 0, basis: .forecast, aerosol: nil)
        #expect(abs(light.moonPoints-40*(1-june.moon.illumination)) < 0.001)
    }
}
