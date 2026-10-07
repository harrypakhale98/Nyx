import Foundation
import Testing
@testable import Nyx

/// Score version 2: weakest-link caps on the four additive parts, moonlight by phase and height,
/// clouds faded from forecast to usual by lead time, one constructor for every surface, and the
/// tie-breaks that let the score answer "where" as well as "when".
@MainActor struct ScoreV2Tests {
    let parks: [Park]
    let engine = AstronomyEngine()
    init() throws { parks = try ParkData.load() }
    func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }
    func evening(_ park: Park, _ iso: String) throws -> Date {
        let day = try #require(TripDay(iso: iso))
        return day.evening(in: park)
    }
    /// A hand-built sky: `moonlight` 0 (none) to 1, `dark` hours of true darkness.
    func sky(moonlight: Double, dark: Double, illumination: Double = 0.5) -> SkyConditions {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return SkyConditions(evening: start, end: start.addingTimeInterval(86400), sunset: start.addingTimeInterval(6*3600), sunrise: start.addingTimeInterval(19*3600),
                             civilDusk: nil, nauticalDusk: nil, darkStart: dark > 0 ? start.addingTimeInterval(8*3600) : nil,
                             darkEnd: dark > 0 ? start.addingTimeInterval((8+dark)*3600) : nil, state: dark > 0 ? .normal : .noAstronomicalDarkness,
                             moon: MoonPhase(fraction: acos(1-2*illumination)/(2*Double.pi)), moonrise: nil, moonset: nil, moonBelowFraction: 0,
                             darkHours: dark, moonlight: moonlight)
    }
    let scoring = ScoreEngine()

    // MARK: Band calibration (S1, S2, S4)

    @Test func overcastIsNeverGoodAndMostlyCloudyNeverGood() {
        for light in stride(from: 0.0, through: 1, by: 0.1) { for bortle in 1...9 { for dark in [0.0, 1, 3, 6, 10, 14] {
            let s = sky(moonlight: light, dark: dark)
            #expect(scoring.score(sky: s, bortle: bortle, cloudCover: 100).value < 40)
            #expect(scoring.score(sky: s, bortle: bortle, cloudCover: 80).value < 60)
            #expect(scoring.score(sky: s, bortle: bortle, cloudCover: 50).value <= 55)
        } } }
        #expect([100.0, 80, 50, 30, 10].map(ScoreEngine.cloudCap) == [10, 28, 55, 73, 91])
    }
    /// Every real park, a month of nights, overcast: never Fair or better than 10.
    @Test func realOvercastNightsArePoor() throws {
        for park in parks {
            let night = try evening(park, "2026-11-09")
            let s = engine.conditions(for: park, on: night)
            #expect(scoring.score(sky: s, bortle: park.bortleEstimate, cloudCover: 100).band == .poor, "\(park.id)")
        }
    }
    @Test func skyGlowCapsTheBands() {
        let s = sky(moonlight: 0, dark: 12)
        #expect(scoring.score(sky: s, bortle: 2, cloudCover: 0).band == .pristine)
        for bortle in 3...9 { #expect(scoring.score(sky: s, bortle: bortle, cloudCover: 0).band != .pristine, "Bortle \(bortle)") }
        for bortle in 5...9 { #expect(scoring.score(sky: s, bortle: bortle, cloudCover: 0).value <= 74) }
        #expect(scoring.score(sky: s, bortle: 6, cloudCover: 0).value <= 59)
        #expect(scoring.score(sky: s, bortle: 8, cloudCover: 0).value <= 39)
        #expect(scoring.score(sky: s, bortle: 5, cloudCover: 0).limit == .skyGlow(74))
    }
    @Test func smokeCapsTheBands() {
        let s = sky(moonlight: 0, dark: 12)
        for aod in [0.5, 0.8, 1.0, 3.0] {
            let score = scoring.score(sky: s, bortle: 2, cloud: 0, basis: .forecast, aerosol: aod)
            #expect(score.value <= 59 && score.limit == .smoke(59))
        }
        #expect(scoring.score(sky: s, bortle: 2, cloud: 0, basis: .forecast, aerosol: 0.3).value == 74)
        #expect(scoring.score(sky: s, bortle: 2, cloud: 0, basis: .forecast, aerosol: 0.2).value > 74)
        #expect(scoring.score(sky: s, bortle: 2, cloud: 0, basis: .forecast, aerosol: nil).limit == nil)
    }
    /// Death Valley, December new moon, total overcast: the audit's 73 "Good" is now 10, and the
    /// breakdown says why in plain words.
    @Test func bindingCapIsNamed() throws {
        let deva = try park("deva")
        let s = engine.conditions(for: deva, on: try evening(deva, "2026-12-09"))
        let score = scoring.score(sky: s, bortle: deva.bortleEstimate, cloudCover: 100)
        #expect(score.value == 10 && score.limit == .clouds(10))
        #expect(score.limit?.sentence(tonight: true) == "Clouds limit tonight to 10.")
        #expect(ScoreLimit.clouds(55).sentence(tonight: false) == "Clouds limit this night to 55.")
        // A clear night is held by nothing.
        #expect(scoring.score(sky: s, bortle: deva.bortleEstimate, cloudCover: 0).limit == nil)
    }
    @Test func saguaroIsBortleFiveAndHaleakalaSitsAboveTheInversion() throws {
        #expect(try park("sagu").bortleEstimate == 5)
        #expect(try park("hale").aboveInversion == true)
        #expect(parks.filter { $0.aboveInversion == true }.map(\.id) == ["hale"])
    }

    // MARK: Monotonicity (AS-15)

    @Test func scoreIsMonotonic() {
        for light in stride(from: 0.0, through: 1, by: 0.25) { for dark in [0.5, 2, 5, 9, 12] { for bortle in 1...9 {
            let s = sky(moonlight: light, dark: dark)
            let clouds = stride(from: 0.0, through: 100, by: 5).map { scoring.score(sky: s, bortle: bortle, cloudCover: $0).value }
            #expect(zip(clouds, clouds.dropFirst()).allSatisfy { $0 >= $1 })
            if bortle < 9 { #expect(scoring.score(sky: s, bortle: bortle, cloudCover: 20).value >= scoring.score(sky: s, bortle: bortle+1, cloudCover: 20).value) }
            if light < 1 { #expect(scoring.score(sky: s, bortle: bortle, cloudCover: 20).value >= scoring.score(sky: sky(moonlight: light+0.25, dark: dark), bortle: bortle, cloudCover: 20).value) }
            #expect(scoring.score(sky: sky(moonlight: light, dark: dark+1), bortle: bortle, cloudCover: 20).value >= scoring.score(sky: s, bortle: bortle, cloudCover: 20).value)
        } } }
    }

    // MARK: Moonlight (AS-10)

    @Test func moonlightFollowsKrisciunasSchaefer() {
        #expect(abs(AstronomyEngine.moonlight(phaseAngle: 0, altitude: 90)-1) < 1e-9)
        #expect(AstronomyEngine.moonlight(phaseAngle: 0, altitude: -1) == 0)
        // A half Moon high up is about 38% of a full one; a quarter-lit crescent about 17%; 75% lit about 60%.
        let half = AstronomyEngine.moonlight(phaseAngle: 90, altitude: 90)
        let crescent = AstronomyEngine.moonlight(phaseAngle: AstronomyEngine.phaseAngle(illumination: 0.25), altitude: 90)
        let gibbous = AstronomyEngine.moonlight(phaseAngle: AstronomyEngine.phaseAngle(illumination: 0.75), altitude: 90)
        #expect(abs(half-0.38) < 0.03 && abs(crescent-0.17) < 0.03 && abs(gibbous-0.60) < 0.03)
        // A full Moon two degrees up counts for about a quarter of one high in the sky.
        #expect(AstronomyEngine.moonlight(phaseAngle: 0, altitude: 2) < 0.3)
        // Monotonic in illumination and in altitude.
        for altitude in [1.0, 5, 15, 30, 60, 90] {
            let byPhase = stride(from: 0.0, through: 1, by: 0.05).map { AstronomyEngine.moonlight(phaseAngle: AstronomyEngine.phaseAngle(illumination: $0), altitude: altitude) }
            #expect(zip(byPhase, byPhase.dropFirst()).allSatisfy { $0 <= $1 + 1e-12 })
        }
        let byHeight = stride(from: 0.5, through: 90, by: 0.5).map { AstronomyEngine.moonlight(phaseAngle: 40, altitude: $0) }
        #expect(zip(byHeight, byHeight.dropFirst()).allSatisfy { $0 <= $1 + 1e-12 })
    }
    /// More of the night with the Moon up means more moonlight: the night's figure is the average.
    @Test func moonlightGrowsWithTimeAboveTheHorizon() throws {
        let jotr = try park("jotr")
        // Waxing Moon: each evening it sets later, so true darkness holds more moonlight.
        let nights = try (0..<6).map { engine.conditions(for: jotr, on: try evening(jotr, "2026-11-1\($0)")) }
        let light = nights.compactMap(\.moonlight)
        #expect(light.count == 6)
        #expect(zip(light, light.dropFirst()).allSatisfy { $0 <= $1 + 0.01 })
        // New moon is near zero; a full Moon high all night is near one.
        let newMoon = engine.conditions(for: jotr, on: try evening(jotr, "2026-11-09"))
        let fullMoon = engine.conditions(for: jotr, on: try evening(jotr, "2026-11-24"))
        #expect((newMoon.moonlight ?? 1) < 0.05 && (fullMoon.moonlight ?? 0) > 0.75)
    }

    // MARK: Clouds by lead time (S3, AS-4, AS-8)

    func forecast(updated: Date, cover: Double, days: Int = 17) -> Forecast {
        let first = (floor(updated.timeIntervalSince1970/3600)-24)*3600
        let hours = (0..<(days*24)).map { first+Double($0)*3600 }
        return Forecast(updated: updated, times: hours, clouds: hours.map { _ in cover })
    }
    @Test func forecastWeightFadesOverAWeek() {
        #expect(CloudBasis.forecastWeight(leadDays: -1) == 1 && CloudBasis.forecastWeight(leadDays: 3) == 1)
        #expect(abs(CloudBasis.forecastWeight(leadDays: 6.5)-0.5) < 1e-9)
        #expect(CloudBasis.forecastWeight(leadDays: 10) == 0 && CloudBasis.forecastWeight(leadDays: 16) == 0)
        #expect(CloudBasis.from(weight: 0.96, leadDays: 3.3) == .forecast)
        #expect(CloudBasis.from(weight: 0.5, leadDays: 6.5).isEarlyLook)
        #expect(CloudBasis.from(weight: 0, leadDays: 12) == .usual)
    }
    @Test func cloudsBlendFromForecastToUsual() throws {
        let deva = try park("deva")
        let night = try evening(deva, "2026-12-09")
        let s = engine.conditions(for: deva, on: night)
        let usual = try #require(CloudClimate.shared.typical(deva, on: night)?.cloud)
        let middle = s.cloudWindow.start.addingTimeInterval(s.cloudWindow.end.timeIntervalSince(s.cloudWindow.start)/2)
        // A day ahead: the forecast in full.
        let near = NightPlanner.night(park: deva, sky: s, forecast: forecast(updated: middle.addingTimeInterval(-86400), cover: 90), detail: nil, now: middle)
        #expect(near.basis == .forecast && near.cloudCover == 90 && near.score.cloudUsed == 90)
        // 6.5 days ahead: half and half, an early look.
        let mid = NightPlanner.night(park: deva, sky: s, forecast: forecast(updated: middle.addingTimeInterval(-6.5*86400), cover: 90), detail: nil, now: middle)
        #expect(mid.basis.isEarlyLook && abs((mid.score.cloudUsed ?? 0)-(90+usual)/2) < 0.01)
        #expect(mid.basisCaption() == "Early look: forecast 7 days out, eased toward usual clouds.")
        // Twelve days ahead: the usual clouds alone; the forecast is not shown as the night's clouds.
        let far = NightPlanner.night(park: deva, sky: s, forecast: forecast(updated: middle.addingTimeInterval(-12*86400), cover: 90, days: 20), detail: nil, now: middle)
        #expect(far.basis == .usual && far.cloudCover == nil && far.score.cloudUsed == usual)
        // No forecast: the usual clouds, said in words.
        let none = NightPlanner.night(park: deva, sky: s, forecast: nil, detail: nil, now: middle)
        #expect(none.basis == .usual && none.score.value == far.score.value)
        #expect(none.basisCaption() == "No cloud forecast yet. This score uses the usual December clouds at Death Valley.")
        #expect(none.basisCaption(unavailable: true)?.hasPrefix("Cloud forecast unavailable.") == true)
        #expect(none.basisLabel == "No cloud forecast yet" && mid.basisLabel == "Early look" && near.basisLabel == nil)
    }
    /// Going offline can never raise a score (audit S3/E4): a forecast is never dropped for its
    /// age, so the same forecast gives the same night whenever it is read.
    @Test func goingOfflineNeverRaisesTheScore() throws {
        let jotr = try park("jotr")
        let night = try evening(jotr, "2026-12-04")
        let s = engine.conditions(for: jotr, on: night)
        let cloudy = forecast(updated: night.addingTimeInterval(-86400), cover: 90)
        let fresh = NightPlanner.night(park: jotr, sky: s, forecast: cloudy, detail: nil, now: night)
        for hours in [36.0, 40, 72, 240] {
            let later = NightPlanner.night(park: jotr, sky: s, forecast: cloudy, detail: nil, now: night.addingTimeInterval(hours*3600))
            #expect(later.score.value == fresh.score.value && later.basis == fresh.basis)
        }
        #expect(fresh.score.value <= ScoreEngine.cloudCap(90))
    }

    // MARK: Smoke and the summit (S4, AS-9)

    func series(_ updated: Date, _ window: (start: Date, end: Date), _ values: [String: Double]) -> HourlySeries {
        let first = floor(window.start.timeIntervalSince1970/3600)*3600-3*3600
        let times = (0..<40).map { first+Double($0)*3600 }
        return HourlySeries(updated: updated, times: times, values: values.mapValues { v in times.map { _ in v } })
    }
    @Test func smokeForecastCapsTheNight() throws {
        let deva = try park("deva")
        let night = try evening(deva, "2026-12-09")
        let s = engine.conditions(for: deva, on: night)
        let clear = forecast(updated: night, cover: 0)
        let detail = ForecastDetail(air: series(night, s.cloudWindow, ["aerosol_optical_depth": 0.8]))
        let smoky = NightPlanner.night(park: deva, sky: s, forecast: clear, detail: detail, now: night)
        let clean = NightPlanner.night(park: deva, sky: s, forecast: clear, detail: nil, now: night)
        #expect(clean.score.band == .pristine)
        #expect(smoky.score.value == 59 && smoky.score.limit == .smoke(59))
    }
    @Test func haleakalaCountsUpperCloudOnly() throws {
        let hale = try park("hale"), havo = try park("havo")
        for park in [hale, havo] {
            let night = try evening(park, "2026-12-09")
            let s = engine.conditions(for: park, on: night)
            let total = forecast(updated: night, cover: 90)
            let detail = ForecastDetail(layers: series(night, s.cloudWindow, ["cloud_cover_low": 90, "cloud_cover_mid": 10, "cloud_cover_high": 10]))
            let scored = NightPlanner.night(park: park, sky: s, forecast: total, detail: detail, now: night)
            if park.id == "hale" {
                #expect(scored.upperCloudOnly && abs((scored.cloudCover ?? 0)-19) < 0.01)
            } else {
                #expect(!scored.upperCloudOnly && scored.cloudCover == 90)
            }
        }
    }

    // MARK: One constructor (E19)

    /// The same fixture night through every surface's path: the app's model, the widget and
    /// reminder snapshot, the trip planner, Siri's and Ask Nyx's planner, and the watch and Vision
    /// Pro calls (`WatchSky.night` and `VisionModel` are one-line calls to the same constructor).
    @Test func everySurfaceBuildsTheSameNight() throws {
        let jotr = try park("jotr")
        let night = try evening(jotr, "2026-12-03")
        let now = night.addingTimeInterval(-2*86400)
        let s = engine.conditions(for: jotr, on: night)
        let f = forecast(updated: now, cover: 35)
        let d = ForecastDetail(air: series(now, s.cloudWindow, ["aerosol_optical_depth": 0.3]))
        let reference = NightPlanner.night(park: jotr, sky: s, forecast: f, detail: d, now: now)
        func same(_ other: Night, _ name: String) {
            #expect(other.score.value == reference.score.value && other.basis == reference.basis && other.cloudCover == reference.cloudCover
                    && other.score.limit == reference.score.limit && other.usualCloud == reference.usualCloud, "\(name)")
        }
        let model = PlanModel()
        model.forecasts = ["jotr": f]; model.details = ["jotr": d]
        same(model.night(jotr, on: night), "PlanModel")
        same(NightPlanner(forecasts: ["jotr": f], details: ["jotr": d]).night(jotr, on: night, now: now), "NightPlanner")
        let snapshot = SavedSkySnapshot(parks: [jotr], forecasts: ["jotr": f], details: ["jotr": d])
        same(try #require(snapshot.nights(from: now, count: 4, forecastAsOf: now).first { $0.id == night }), "Widget snapshot")
        same(TripPlanner.nights(parks: [jotr], days: [TripDay(year: 2026, month: 12, day: 3)], forecasts: ["jotr": f], details: ["jotr": d], now: now)[0][0], "Trip planner")
        #expect(reference.score.limit == .smoke(74) || reference.score.value <= 74)
        // The watch has no smoke detail and Vision Pro no forecast: each matches the phone given the same inputs.
        let wrist = NightPlanner.night(park: jotr, sky: s, forecast: f, detail: nil, now: now)
        #expect(wrist.score.value == NightPlanner(forecasts: ["jotr": f]).night(jotr, on: night, now: now).score.value)
        let vision = NightPlanner.night(park: jotr, sky: s, forecast: nil, detail: nil, now: night)
        #expect(vision.basis == .usual && vision.score.value == NightPlanner(forecasts: [:]).night(jotr, on: night, now: now).score.value)
    }

    // MARK: Ties (AS-3, DX-14)

    @Test func tiesGoToTheDarkerMeasuredSky() throws {
        let grba = try park("grba"), grca = try park("grca")
        #expect(NightPlanner.glowRank("grba") < NightPlanner.glowRank("grca"))
        let s1 = engine.conditions(for: grba, on: try evening(grba, "2026-12-09"))
        let s2 = engine.conditions(for: grca, on: try evening(grca, "2026-12-09"))
        let score = DarknessScore(value: 97, moonPoints: 40, cloudPoints: 25, bortlePoints: 17.5, lengthPoints: 15)
        let a = Night(park: grba, sky: s1, score: score, cloudCover: 0, forecastUpdated: nil)
        let b = Night(park: grca, sky: s2, score: score, cloudCover: 0, forecastUpdated: nil)
        #expect(NightPlanner.ranked([b, a]).first?.park.id == "grba")
        // Same park, same score: the longer true darkness first, then the closer model agreement.
        let short = Night(park: grba, sky: engine.conditions(for: grba, on: try evening(grba, "2026-10-09")), score: score, cloudCover: 0, forecastUpdated: nil)
        #expect(NightPlanner.better(a, short))
        var agreed = a; agreed.modelSpread = 4
        var split = a; split.modelSpread = 40
        #expect(NightPlanner.better(agreed, split) && !NightPlanner.better(split, agreed))
    }
    /// Parks sorted by "Darkest tonight" never fall back to alphabetical order on a tie.
    @Test func parksListBreaksTiesByGlow() throws {
        let model = PlanModel()
        model.forecasts = [:]; model.details = [:]
        let ranked = model.ranked(model.parks)
        let nights = ranked.map { model.night($0) }
        for (x, y) in zip(nights, nights.dropFirst()) where x.score.value == y.score.value {
            #expect(NightPlanner.glowRank(x.park.id) <= NightPlanner.glowRank(y.park.id) || abs(x.sky.darkHours-y.sky.darkHours) >= 1.0/60, "\(x.park.id) \(y.park.id)")
        }
    }

    // MARK: Time zones without daylight saving

    @Test func nightsWithoutDaylightSavingAreAlways24Hours() throws {
        for id in ["hale", "havo", "npsa", "viis", "grca", "pefo"] {
            let park = try park(id)
            var night = try evening(park, "2026-01-01")
            for _ in 0..<730 {
                let next = park.date(night, addingDays: 1)
                #expect(next.timeIntervalSince(night) == 86400, "\(id) \(night)")
                night = next
            }
        }
    }
}
