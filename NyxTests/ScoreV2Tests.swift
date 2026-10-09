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
        // The watch: what the iPhone hands over (clouds and smoke), decoded on the wrist and scored by
        // `WatchSky.night`'s one call, is the phone's night, smoke cap included.
        let sent = WatchContext.make(savedParkIDs: ["jotr"], homeParkID: "jotr", nightVision: false, forecasts: ["jotr": f], details: ["jotr": d], now: now)
        let received = try #require(WatchContext(dictionary: sent.dictionary))
        let wrist = NightPlanner.night(park: jotr, sky: s, forecast: received.cloudForecasts["jotr"], detail: received.forecastDetails["jotr"], now: now)
        same(wrist, "Watch")
        #expect(wrist.aerosol != nil && wrist.aerosol == reference.aerosol && wrist.score.value <= 74)
        // Vision Pro has no forecast: it matches the phone given the same inputs.
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
    /// A park's usual clouds can cap a whole month at one score (Arches at 73 in October 2026). The
    /// new Moon must still outrank a gibbous Moon, though late October's true darkness is longer:
    /// ties look at the uncapped sum of parts before the length of the night.
    @Test func aCappedTieGoesToTheDarkerNightNotTheLongerOne() throws {
        let arch = try park("arch")
        let newSky = engine.conditions(for: arch, on: try evening(arch, "2026-10-08"))
        let gibbousSky = engine.conditions(for: arch, on: try evening(arch, "2026-10-31"))
        #expect(gibbousSky.darkHours > newSky.darkHours + 1.0/60)
        #expect(newSky.moon.illumination < 0.1 && gibbousSky.moon.illumination > 0.5)
        let newMoon = Night(park: arch, sky: newSky, score: DarknessScore(value: 73, moonPoints: 39.5, cloudPoints: 14, bortlePoints: 17.5, lengthPoints: 11, basis: .usual), cloudCover: nil, forecastUpdated: nil)
        let gibbous = Night(park: arch, sky: gibbousSky, score: DarknessScore(value: 73, moonPoints: 21, cloudPoints: 14, bortlePoints: 17.5, lengthPoints: 12, basis: .usual), cloudCover: nil, forecastUpdated: nil)
        #expect(NightPlanner.better(newMoon, gibbous) && !NightPlanner.better(gibbous, newMoon))
        #expect(NightPlanner.ranked([gibbous, newMoon]).first?.id == newMoon.id)
        #expect(NightPlanner.best([gibbous, newMoon])?.id == newMoon.id)
    }
    /// Parks sorted by "Darkest tonight" follow `NightPlanner.better` exactly, never alphabetical order on a tie.
    @Test func parksListBreaksTiesByGlow() throws {
        let model = PlanModel()
        model.forecasts = [:]; model.details = [:]
        let ranked = model.ranked(model.parks)
        let nights = ranked.map { model.night($0) }
        for (x, y) in zip(nights, nights.dropFirst()) {
            #expect(!NightPlanner.better(y, x), "\(x.park.id) \(y.park.id)")
        }
    }
    /// Every "best night" helper (the widget's week ring and spoken best, the week strip, the
    /// chart summary, the Tonight control, and the watch's Tonight, week and complications, which
    /// call `NightPlanner.best`) breaks a tie the same way: here the longer true darkness, not the first night.
    @Test func bestNightHelpersBreakTiesAlike() throws {
        let grba = try park("grba")
        let score = DarknessScore(value: 97, moonPoints: 40, cloudPoints: 25, bortlePoints: 17.5, lengthPoints: 15)
        let short = Night(park: grba, sky: engine.conditions(for: grba, on: try evening(grba, "2026-10-09")), score: score, cloudCover: 0, forecastUpdated: nil)
        let long = Night(park: grba, sky: engine.conditions(for: grba, on: try evening(grba, "2026-12-09")), score: score, cloudCover: 0, forecastUpdated: nil)
        #expect(long.sky.darkHours > short.sky.darkHours + 1)
        let week = [short, long]
        #expect(NightPlanner.best(week)?.id == long.id && NightPlanner.ranked(week).first?.id == long.id)
        #expect(NightChart.summary(week).contains(grba.dayLabel(long.id)))
        // The control: the darkest saved park tonight by the same rule, whatever "next" chose for a widget.
        let parks = try ["jotr", "deva", "grba", "bibe", "grca", "arch", "cany", "brca"].map(park)
        let now = try evening(grba, "2026-12-09")
        let snapshot = SavedSkySnapshot(parks: parks, forecasts: [:])
        let tonight = parks.map { snapshot.planner.night($0, on: $0.currentNight(at: now), now: now) }
        #expect(TonightControlValue(snapshot: snapshot, pinned: nil, now: now).parkID == NightPlanner.best(tonight)?.park.id)
    }

    // MARK: Haleakalā's layers (J)

    /// A layer forecast much older than the total-cloud forecast never replaces it.
    @Test func staleSummitLayersGiveWayToTheFresherForecast() throws {
        let hale = try park("hale")
        let night = try evening(hale, "2026-12-09")
        let s = engine.conditions(for: hale, on: night)
        let now = night.addingTimeInterval(-3600)
        let total = forecast(updated: now, cover: 90)
        func scored(layersAge: TimeInterval) -> Night {
            let detail = ForecastDetail(layers: series(now.addingTimeInterval(-layersAge), s.cloudWindow, ["cloud_cover_low": 90, "cloud_cover_mid": 10, "cloud_cover_high": 10]))
            return NightPlanner.night(park: hale, sky: s, forecast: total, detail: detail, now: now)
        }
        let recent = scored(layersAge: 6*3600)
        #expect(recent.upperCloudOnly && abs((recent.cloudCover ?? 0)-19) < 0.01)
        let stale = scored(layersAge: 2*86400)
        #expect(!stale.upperCloudOnly && stale.cloudCover == 90 && stale.score.value <= recent.score.value)
    }

    /// The watch scores Haleakalā's summit from the same mid and high cloud as the iPhone, and every
    /// park saved with clouds and smoke still fits WatchConnectivity's budget.
    @Test func watchReceivesSummitLayersAndSmokeWithinBudget() throws {
        let hale = try park("hale")
        let night = try evening(hale, "2026-12-09")
        let s = engine.conditions(for: hale, on: night)
        let now = night.addingTimeInterval(-3600)
        let total = forecast(updated: now, cover: 90)
        let detail = ForecastDetail(layers: series(now, s.cloudWindow, ["cloud_cover_low": 90, "cloud_cover_mid": 10, "cloud_cover_high": 10]),
                                    air: series(now, s.cloudWindow, ["aerosol_optical_depth": 0.3]))
        let phone = NightPlanner.night(park: hale, sky: s, forecast: total, detail: detail, now: now)
        let sent = WatchContext.make(savedParkIDs: ["hale"], homeParkID: "hale", nightVision: false, forecasts: ["hale": total], details: ["hale": detail],
                                     closures: ["hale": "Summit District closed"], aboveInversion: ["hale"], now: now)
        let data = try #require(sent.data)
        let received = try #require(WatchContext(data: data))
        let wrist = NightPlanner.night(park: hale, sky: s, forecast: received.cloudForecasts["hale"], detail: received.forecastDetails["hale"], now: now)
        #expect(phone.upperCloudOnly && wrist.upperCloudOnly && wrist.score.value == phone.score.value && wrist.cloudCover == phone.cloudCover)
        #expect(wrist.score.limit == phone.score.limit && received.closures["hale"] == "Summit District closed")
        // Only the summit's layers travel, and only the variables the score reads.
        #expect(received.details["hale"]?.layers?.values.keys.sorted() == ["cloud_cover_high", "cloud_cover_mid"])
        let all = parks.map(\.id)
        let budget = WatchContext.make(savedParkIDs: all, homeParkID: "jotr", nightVision: false,
                                       forecasts: Dictionary(uniqueKeysWithValues: all.map { ($0, total) }),
                                       details: Dictionary(uniqueKeysWithValues: all.map { ($0, detail) }), now: now)
        #expect((budget.data?.count ?? .max) <= WatchContext.byteBudget)
        #expect(budget.forecasts[all[0]] != nil && budget.details[all[0]]?.air != nil && budget.details[all[0]]?.layers == nil)
    }

    // MARK: Beyond the forecast (K)

    @Test func nightsPastTenDaysAreBeyondTheForecastNotUnavailable() throws {
        let jotr = try park("jotr")
        let now = try evening(jotr, "2026-12-01")
        let fresh = forecast(updated: now, cover: 20)
        let planner = NightPlanner(forecasts: ["jotr": fresh])
        for days in 10...13 {
            let night = planner.night(jotr, on: jotr.date(jotr.currentNight(at: now), addingDays: days), now: now)
            #expect(night.basis == .usual, "\(days)")
            #expect(NightPlanner.beyondForecast(night, forecast: fresh, now: now), "\(days)")
        }
        // A forecast eleven days old that still covers tomorrow: that night is "unavailable", not "not yet".
        let stale = forecast(updated: now.addingTimeInterval(-11*86400), cover: 20)
        let tomorrow = NightPlanner(forecasts: ["jotr": stale]).night(jotr, on: jotr.date(jotr.currentNight(at: now), addingDays: 1), now: now)
        #expect(tomorrow.basis == .usual && !NightPlanner.beyondForecast(tomorrow, forecast: stale, now: now))
        // No forecast at all: a week out should have had one; twelve nights out could not.
        let none = NightPlanner(forecasts: [:])
        #expect(!NightPlanner.beyondForecast(none.night(jotr, on: jotr.date(jotr.currentNight(at: now), addingDays: 5), now: now), forecast: nil, now: now))
        #expect(NightPlanner.beyondForecast(none.night(jotr, on: jotr.date(jotr.currentNight(at: now), addingDays: 12), now: now), forecast: nil, now: now))
    }

    // MARK: Smoke: one value for the score and its words (L)

    @Test func smokeCaveatDescribesTheSmokeTheScoreUsed() throws {
        let model = PlanModel(weather: WeatherService(persist: false), parkStore: ParkStore(persist: false),
                              detail: ForecastDetailService(persist: false))
        defer { model.smokeEnabled = true }
        model.smokeEnabled = true
        let deva = try park("deva")
        let tonight = model.night(deva)
        // An aerosol forecast three days old (past the 36 hours the other context lines keep) still covers tonight.
        let air = series(model.today.addingTimeInterval(-3*86400), tonight.sky.cloudWindow, ["aerosol_optical_depth": 0.6])
        model.forecasts = [:]; model.details = ["deva": ForecastDetail(air: air)]
        let smoky = model.night(deva)
        #expect(smoky.score.value <= 59 && smoky.aerosol == 0.6)
        #expect(model.outlook(smoky)?.clarity == .heavy && model.smokeCaveat(smoky) != nil)
        // "Smoke and haze" off: the cached smoke stops counting everywhere, at once.
        model.smokeEnabled = false
        #expect(model.details["deva"]?.air == nil)
        let clean = model.night(deva)
        #expect(clean.aerosol == nil && clean.score.value >= smoky.score.value && model.smokeCaveat(clean) == nil)
        // And it stays out while the switch is off, whatever arrives.
        model.details = ["deva": ForecastDetail(air: air)]
        #expect(model.details["deva"] == nil)
    }

    // MARK: Background refresh (M)

    /// A model that last looked at the clock hours ago moves to the current night when asked, as
    /// the saved-park refresh does before it publishes.
    @Test func tickMovesTonightAcrossTheTurnover() throws {
        let model = PlanModel(weather: WeatherService(persist: false), parkStore: ParkStore(persist: false),
                              detail: ForecastDetailService(persist: false))
        let jotr = try park("jotr")
        let before = model.tonight(jotr)
        let later = model.today.addingTimeInterval(2*86400)
        model.tick(later)
        #expect(model.today == later && model.tonight(jotr) == jotr.date(before, addingDays: 2))
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

    // MARK: A breakdown that adds up

    /// The parts a breakdown prints are whole points that add up to the sum it names, whatever the
    /// fractions: rounding each part alone printed 40 + 25 + 15 + 15 beside "add up to 94".
    @Test func displayedPartsAlwaysAddUpToTheSum() {
        let joshua = DarknessScore(value: 89, moonPoints: 39.6, cloudPoints: 24.6, bortlePoints: 15, lengthPoints: 14.55, limit: .skyGlow(89))
        #expect(joshua.partsSum == 94)
        let shown = joshua.displayedParts
        #expect(shown.moon + (shown.cloud ?? 0) + shown.glow + shown.length == 94)
        #expect(shown.moon == 40 && shown.cloud == 25 && shown.glow == 15 && shown.length == 14)
        // Every engine score, over a grid of skies: the shown parts make the sum, none leaves its range.
        for moonlight in stride(from: 0.0, through: 1, by: 0.07) {
            for dark in [0.0, 0.4, 2.3, 6.7, 9.71, 12] {
                for cloud in [nil, 0.0, 13.3, 47.5, 88.8] as [Double?] {
                    for bortle in 1...9 {
                        let score = scoring.score(sky: sky(moonlight: moonlight, dark: dark), bortle: bortle, cloudCover: cloud)
                        let parts = score.displayedParts
                        #expect(parts.moon + (parts.cloud ?? 0) + parts.glow + parts.length == score.partsSum)
                        #expect((parts.cloud == nil) == (score.cloudPoints == nil))
                        let scale = score.cloudPoints == nil ? 1/0.75 : 1
                        #expect(Double(parts.moon) <= (40*scale).rounded() && Double(parts.glow) <= (20*scale).rounded() && Double(parts.length) <= (15*scale).rounded() && (parts.cloud ?? 0) <= 25)
                        #expect(score.value <= score.partsSum)
                    }
                }
            }
        }
    }
}
