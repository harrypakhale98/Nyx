import Foundation
import SwiftData
import Testing
import UIKit
@testable import Nyx

/// Answers Open-Meteo with the bodies it is given, one per request in turn (the last repeats), so a
/// test can follow a good forecast with malformed ones.
actor ScriptedHTTP: HTTPTransport {
    private var bodies: [String]
    private(set) var count=0
    init(_ bodies: [String]) { self.bodies=bodies }
    func then(_ body: String) { bodies=[body] }
    func get(_ url: URL) async throws -> Data {
        count+=1
        let body=bodies.count>1 ? bodies.removeFirst() : bodies.first ?? ""
        return Data(body.utf8)
    }
}
/// A weather service that answers every refresh with one fixed forecast for Joshua Tree.
struct FixedWeather: WeatherProviding {
    let forecast: Forecast
    func forecasts(for parks: [Park], network: Bool, force: Bool) async -> [String: Forecast] { ["jotr": forecast] }
    func hydrate(_ parks: [Park]) async -> [String: Forecast] { [:] }
    func seed(_ cached: [String: Forecast], parks: [Park]) async {}
}

/// The engine audit's regressions: dates in any calendar, forecasts that never go backwards, the
/// watch scoring as the iPhone does, honest Siri words, malformed data from either service, odd
/// time zones, the poles, and a hostile journal file.
@MainActor struct EngineAuditTests {
    static func zone(_ id: String) throws -> TimeZone { try #require(TimeZone(identifier: id)) }
    static func spot(_ suffix: String, _ latitude: Double, _ longitude: Double, _ zone: String) -> Park {
        Place(spotID: "pin:00000000-0000-4000-8000-0000000000\(suffix)", name: "Test spot \(suffix)", latitude: latitude, longitude: longitude,
              timeZoneID: zone, countryCode: "", region: "")
    }
    /// A local wall-clock moment in `park`'s zone.
    static func local(_ park: Park, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try #require(park.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    // MARK: Calendars

    /// A date picked on a device set to the Buddhist or Japanese calendar is the same Gregorian day:
    /// 2026, never 2569 or year 8 of Reiwa.
    @Test(arguments: [Calendar.Identifier.buddhist, .japanese, .gregorian])
    func aPickedDayIsGregorianInAnyCalendar(_ identifier: Calendar.Identifier) throws {
        var calendar=Calendar(identifier: identifier)
        calendar.timeZone=try Self.zone("America/Los_Angeles")
        let jotr=try park("jotr")
        let picked=try Self.local(jotr, 2026, 10, 10, 20)
        #expect(TripDay(picked, calendar: calendar).iso == "2026-10-10")
        // Just after midnight it is already the next day, as the person's own clock says.
        #expect(TripDay(picked.addingTimeInterval(4.5*3600), calendar: calendar).iso == "2026-10-11")
        #expect(FollowNightWords.evening(of: picked.addingTimeInterval(4.5*3600), at: jotr, calendar: calendar) == (try Self.local(jotr, 2026, 10, 11, 12)))
        // Trip planning and Find the best night read the same day.
        let days=TripPlanner.days(first: TripDay(picked, calendar: calendar), last: TripDay(picked.addingTimeInterval(86400), calendar: calendar), weekendsOnly: false)
        #expect(days.map(\.iso) == ["2026-10-10", "2026-10-11"])
    }

    // MARK: Forecasts never go backwards

    @Test func anOlderForecastNeverReplacesANewerOne() async throws {
        let base=Date(timeIntervalSince1970: 1_791_763_200)
        func forecast(_ updated: Date) -> Forecast { Forecast(updated: updated, times: [base.timeIntervalSince1970], clouds: [10]) }
        let older=forecast(base), newer=forecast(base.addingTimeInterval(3600))
        #expect(!Forecast.replaces(older, newer) && Forecast.replaces(newer, older))
        #expect(Forecast.replaces(older, nil) && !Forecast.replaces(nil, newer) && !Forecast.replaces(newer, newer))
        // A refresh that finishes late with the older forecast leaves the newer one in place.
        let http=StubHTTP([:])
        let model=PlanModel(weather: FixedWeather(forecast: older), parkStore: ParkStore(transport: http, persist: false),
                            detail: ForecastDetailService(transport: http, persist: false), defaults: isolatedDefaults())
        model.weatherEnabled=false
        await model.refreshForecasts(watching: [])
        #expect(model.forecasts["jotr"]?.updated == older.updated)
        model.forecasts["jotr"]=newer
        await model.refreshForecasts(watching: [])
        #expect(model.forecasts["jotr"]?.updated == newer.updated)
    }

    // MARK: The watch scores as the iPhone does

    /// The watch is handed every hour a forecast still counts for (ten days from its issue, and a
    /// day more for the last night), so a night nine and a half days out scores the same on both.
    @Test func theWatchKeepsEveryHourThatStillCounts() throws {
        let jotr=try park("jotr")
        let now=Date(timeIntervalSince1970: 1_796_158_800)
        let updated=now.addingTimeInterval(-3600)
        let first=(floor(now.timeIntervalSince1970/86400)-1)*86400
        let hours=(0..<(16*24)).map { first+Double($0)*3600 }
        let forecast=Forecast(updated: updated, times: hours, clouds: hours.map { _ in 30 })
        let context=WatchContext.make(savedParkIDs: ["jotr"], homeParkID: "jotr", nightVision: false, forecasts: ["jotr": forecast], now: now)
        let data=try #require(context.data)
        let sent=try #require(WatchContext(data: data)?.cloudForecasts["jotr"])
        let last=try #require(sent.times.last)
        #expect(last >= updated.timeIntervalSince1970+10*86400 && last <= updated.timeIntervalSince1970+WatchContext.forecastReach)
        let late=jotr.date(jotr.currentNight(at: now), addingDays: 9)
        let sky=AstronomyEngine().conditions(for: jotr, on: late)
        let phone=NightPlanner.night(park: jotr, sky: sky, forecast: forecast, detail: nil, now: now)
        let wrist=NightPlanner.night(park: jotr, sky: sky, forecast: sent, detail: nil, now: now)
        #expect(phone.basis.isEarlyLook && phone.score.value == wrist.score.value && phone.basis == wrist.basis)
    }

    // MARK: Siri's words

    /// "No true darkness in the next 14 nights" only when none of them has any.
    @Test func noDarknessIsSaidOnlyWhenNoNightHasIt() throws {
        let gaar=try park("gaar"), jotr=try park("jotr")
        let june=try Self.local(gaar, 2026, 6, 15, 13)
        let planner=NightPlanner(forecasts: [:])
        let summer=try #require(BestNightSearch.answer(parks: [gaar], planner: planner, from: june, nights: 14, now: june))
        #expect(summer.noDarkness && BestNightSearch.dialog(summer, voiceOnly: false).hasPrefix(String(localized: "No true darkness at \(gaar.shortName) in the next 14 nights.")))
        // A best night without darkness among nights that have some is named as the best, not as "no darkness".
        let polar=AstronomyEngine().conditions(for: gaar, on: june), dark=AstronomyEngine().conditions(for: jotr, on: try Self.local(jotr, 2026, 6, 15, 13))
        let lit=Night(park: gaar, sky: polar, score: DarknessScore(value: 60, moonPoints: 30, cloudPoints: 20, bortlePoints: 10, lengthPoints: 0), cloudCover: 5, forecastUpdated: june)
        let shorter=Night(park: jotr, sky: dark, score: DarknessScore(value: 50, moonPoints: 20, cloudPoints: 20, bortlePoints: 5, lengthPoints: 5), cloudCover: 5, forecastUpdated: june)
        let mixed=BestNightSearch.Answer(nights: [lit, shorter], count: 2)
        #expect(polar.darkHours == 0 && dark.darkHours > 0 && !mixed.noDarkness)
        #expect(BestNightSearch.dialog(mixed, voiceOnly: false).hasPrefix(String(localized: "The best of the next 2 nights:")))
    }

    // MARK: Hourly windows

    /// A window under a second long with no valid hour in it has no mean, never 0/0.
    @Test func aSliverOfAWindowHasNoMean() {
        let t0=1_790_000_000.0
        let start=Date(timeIntervalSince1970: t0+100)
        #expect(HourlyWindow.mean(times: [t0, t0+3600], values: [nil, nil], from: start, to: start.addingTimeInterval(0.5), valid: 0...100) == nil)
        #expect(HourlyWindow.mean(times: [t0, t0+3600], values: [40, nil], from: start, to: start.addingTimeInterval(0.5), valid: 0...100) == 40)
        let forecast=Forecast(updated: .now, times: [t0, t0+3600], clouds: [nil, nil])
        #expect(forecast.mean(from: start, to: start.addingTimeInterval(0.5)) == nil)
    }

    // MARK: Park alerts

    /// One alert with a null field never costs the others; a list of codes with spaces and capitals
    /// reaches each park; a code Nyx does not know is ignored.
    @Test func alertsDecodeOneRecordAtATime() async throws {
        let body="""
        {"total":"5","data":[
          {"id":"a1","title":"Road closed","description":null,"category":"Park Closure","parkCode":"jotr"},
          {"id":"a2","title":"Trail closed","description":"Storm damage","parkCode":"ACAD, EVER "},
          {"id":"a3","title":"Elsewhere","description":"x","category":"Caution","parkCode":"zzzz"},
          {"title":"No id","description":"x","category":"Caution","parkCode":"jotr"},
          {"id":"a5","title":"Fire danger","description":"High","category":"Danger","parkCode":"deva"}
        ]}
        """
        let parks=try ["jotr", "acad", "ever", "deva"].map(park)
        let store=ParkStore(transport: StubHTTP(["/api/v1/alerts": body]), persist: false)
        let cache=try #require(await store.alerts(for: parks, key: "test", network: true, force: true).cache)
        #expect(cache.alerts["jotr"]?.map(\.id) == ["a1"] && cache.alerts["jotr"]?.first?.description == "")
        #expect(cache.alerts["acad"]?.map(\.id) == ["a2"] && cache.alerts["ever"]?.map(\.id) == ["a2"] && cache.alerts["acad"]?.first?.category == "")
        #expect(cache.alerts["deva"]?.map(\.id) == ["a5"] && cache.alerts["zzzz"] == nil)
    }

    // MARK: Open-Meteo answers that cannot be read

    /// A body that does not match the request (too few places, unequal hours and clouds, no hours,
    /// an error object) is never stored: the last good forecast stays.
    @Test func malformedForecastsKeepTheCache() async throws {
        let parks=try ["jotr", "deva"].map(park)
        let good="{\"hourly\":{\"time\":[1790000000,1790003600],\"cloud_cover\":[10,20]}}"
        let http=ScriptedHTTP(["[\(good),\(good)]"])
        let clock=BudgetClock(Date(timeIntervalSince1970: 1_790_000_000))
        let service=WeatherService(transport: http, persist: false, clock: { clock.now })
        let first=await service.forecasts(for: parks, network: true)
        let kept=try #require(first["deva"]?.updated)
        #expect(first["jotr"]?.updated == kept)
        let unequal="{\"hourly\":{\"time\":[1,2,3],\"cloud_cover\":[1]}}", empty="{\"hourly\":{\"time\":[],\"cloud_cover\":[]}}"
        for body in ["[\(good)]", "[\(empty),\(empty)]", "{\"error\":true,\"reason\":\"Cannot initialize\"}", "", "[\(good),\(unequal)]"] {
            clock.advance(7*3600)
            await http.then(body)
            let after=await service.forecasts(for: parks, network: true)
            #expect(after["deva"]?.updated == kept && after["deva"]?.clouds == [10, 20], "\(body)")
        }
        // Only the well-formed half of the last answer was taken.
        #expect(await service.forecasts(for: parks, network: false)["jotr"]?.updated != kept)
        #expect(await http.count == 6)
    }

    // MARK: Requests in flight

    /// Spots asked for while another spots request is on its way are asked for once it ends, not
    /// dropped because a request was running.
    @Test func aJoinedSpotsRequestStillAsksForItsOwnSpots() async throws {
        let echo=OpenMeteoEcho(hold: true)
        let service=WeatherService(transport: echo, persist: false, suite: "nyx.tests.spots.\(UUID().uuidString)")
        let a=Self.spot("a1", 34.1, -116.1, "America/Los_Angeles"), b=Self.spot("b2", 40.1, -105.1, "America/Denver")
        let first=Task { await service.spotForecasts(for: [a], network: true) }
        var tries=0
        while !(await echo.waiting), tries<500 { tries+=1; try await Task.sleep(for: .milliseconds(5)) }
        let second=Task { await service.spotForecasts(for: [b], network: true) }
        try await Task.sleep(for: .milliseconds(50))
        await echo.release()
        #expect(await first.value[a.id] != nil)
        #expect(await second.value[b.id] != nil)
        #expect(await echo.urls.count == 2)
    }

    // MARK: Ask Nyx's dates

    /// A date the model gets wrong (February 30, month 13, year 0, 9999, nothing, a word) is tonight.
    @Test func toolDatesThatAreNotDaysAreTonight() throws {
        let jotr=try park("jotr")
        let now=Date(timeIntervalSince1970: 1_796_158_800)
        let lookup=NightLookup(parks: [jotr], forecasts: [:], now: now)
        let clock=ContinuousClock(), start=clock.now
        for text in ["2026-02-30", "2026-13-01", "0000-01-01", "9999-12-31", "", "tonight", "2026-12-1", "12/14/2026"] {
            #expect(lookup.day(text, at: jotr) == nil, "\(text)")
            #expect(lookup.night(text, at: jotr) == jotr.currentNight(at: now), "\(text)")
            #expect(lookup.whatsUp(park: "Joshua Tree", on: text).first?.contains(jotr.isoDay(jotr.currentNight(at: now))) == true, "\(text)")
        }
        #expect(lookup.night("2026-12-14", at: jotr) == (try Self.local(jotr, 2026, 12, 14, 12)))
        #expect(lookup.bestNights(park: "Joshua Tree", from: "9999-12-31", nights: 3).count == 3)
        if Bench.enabled { #expect(clock.now-start < .seconds(2)) }
    }

    // MARK: Time zones

    /// Half- and quarter-hour zones, a daylight-saving night, and the zones furthest from UTC: every
    /// night is a sensible noon-to-noon window with a finite darkness, and 01:30 is still last night.
    @Test(arguments: [("Asia/Kathmandu", 27.7, 85.3), ("Australia/Adelaide", -34.9, 138.6), ("Australia/Lord_Howe", -31.55, 159.08),
                      ("Pacific/Chatham", -43.95, -176.55), ("Pacific/Apia", -13.83, -171.76), ("Pacific/Kiritimati", 1.87, -157.4)])
    func oddZonesHaveSensibleNights(_ zone: String, _ latitude: Double, _ longitude: Double) throws {
        let place=Self.spot("c3", latitude, longitude, zone)
        #expect(place.timeZone.identifier == zone)
        // October 3, 2026: Adelaide and Lord Howe move their clocks forward before the next noon.
        let evening=try Self.local(place, 2026, 10, 3, 12)
        let sky=AstronomyEngine().conditions(for: place, on: evening)
        let length=sky.end.timeIntervalSince(sky.evening)/3600
        #expect(sky.evening == evening && (22.5...25.5).contains(length), "\(length)")
        let sunset=try #require(sky.sunset), sunrise=try #require(sky.sunrise)
        let darkStart=try #require(sky.darkStart), darkEnd=try #require(sky.darkEnd)
        #expect(sunset < darkStart && darkStart < darkEnd && darkEnd < sunrise)
        #expect(sky.darkHours.isFinite && (6...13).contains(sky.darkHours), "\(sky.darkHours)")
        #expect(place.calendar.component(.hour, from: sunset) >= 16 && place.calendar.component(.hour, from: sunset) <= 20)
        let early=try Self.local(place, 2026, 10, 4, 1, 30)
        #expect(place.currentNight(at: early) == evening)
        #expect(place.currentNight(at: sunrise.addingTimeInterval(60)) == place.date(evening, addingDays: 1))
        let score=ScoreEngine().score(sky: sky, bortle: place.bortleEstimate, cloudCover: 20)
        #expect((0...100).contains(score.value))
    }

    // MARK: Reminders across daylight saving

    /// A reminder for the night after the clocks change fires at 6 PM on the park's new clock, and
    /// the calendar trigger reads 6 PM in the park's zone, not the device's.
    @Test func reminderFiresAtSixOnTheParksClockAcrossDST() throws {
        let jotr=try park("jotr")
        let zone=jotr.timeZone
        func night(_ day: Int, month: Int, updated: Date) throws -> Night {
            let sky=AstronomyEngine().conditions(for: jotr, on: try Self.local(jotr, 2026, month, day, 12))
            return Night(park: jotr, sky: sky, score: DarknessScore(value: 94, moonPoints: 39, cloudPoints: 24, bortlePoints: 18, lengthPoints: 13), cloudCover: 4, forecastUpdated: updated)
        }
        let scheduler=NotificationScheduler(center: StubNotifications(), ledger: ReminderLedger(suite: "nyx-ledger-test-\(UUID().uuidString)"))
        // Sunday, November 1, 2026, 09:00 in California, hours after the clocks went back: the night
        // of November 2 is announced at 6 PM on the 1st, Pacific Standard Time.
        let after=try Self.local(jotr, 2026, 11, 1, 9)
        let plan=try #require(scheduler.plans(nights: [try night(2, month: 11, updated: after)], now: after).first)
        #expect(plan.fireDate == (try Self.local(jotr, 2026, 11, 1, 18)) && zone.secondsFromGMT(for: plan.fireDate) == -8*3600)
        let parts=SystemNotifications.fireComponents(plan.fireDate, in: zone)
        #expect((parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second) == (2026, 11, 1, 18, 0, 0))
        #expect(parts.calendar?.identifier == .gregorian && parts.timeZone == zone && parts.date == plan.fireDate)
        // The day before, still on daylight time: 6 PM too, an hour apart in UTC.
        let before=try Self.local(jotr, 2026, 10, 31, 9)
        let earlier=try #require(scheduler.plans(nights: [try night(1, month: 11, updated: before)], now: before).first)
        let wall=SystemNotifications.fireComponents(earlier.fireDate, in: zone)
        #expect(wall.hour == 18 && wall.day == 31 && zone.secondsFromGMT(for: earlier.fireDate) == -7*3600)
    }

    // MARK: The night turns over at sunrise

    @Test func widgetsRedrawASecondAfterSunrise() throws {
        let jotr=try park("jotr"), gaar=try park("gaar")
        let now=Date(timeIntervalSince1970: 1_796_158_800)
        let turnovers=jotr.nightTurnovers(from: now, to: now.addingTimeInterval(86400))
        let sunrise=try #require(AstronomyEngine().conditions(for: jotr, on: jotr.currentNight(at: now)).sunrise)
        #expect(turnovers == [sunrise.addingTimeInterval(1)])
        #expect(jotr.currentNight(at: sunrise.addingTimeInterval(1)) != jotr.currentNight(at: sunrise.addingTimeInterval(-2)))
        // Under the midnight sun the night moves on at 3 AM.
        let june=try Self.local(gaar, 2026, 6, 20, 13)
        let summer=gaar.nightTurnovers(from: june, to: june.addingTimeInterval(86400))
        #expect(summer == [try Self.local(gaar, 2026, 6, 21, 3)])
        #expect(TonightTimeline(snapshot: SavedSkySnapshot(parks: [jotr], forecasts: [:]), large: false).turnovers(from: now, to: now.addingTimeInterval(86400)) == turnovers)
    }

    // MARK: Score clamps

    @Test func outOfRangeInputsAreClamped() throws {
        let jotr=try park("jotr")
        let sky=AstronomyEngine().conditions(for: jotr, on: try Self.local(jotr, 2026, 12, 10, 12))
        let engine=ScoreEngine()
        func score(_ bortle: Int, _ cloud: Double?) -> DarknessScore { engine.score(sky: sky, bortle: bortle, cloudCover: cloud) }
        #expect(score(3, 150).value == score(3, 100).value && score(3, 150).cloudUsed == 100)
        #expect(score(3, -5).value == score(3, 0).value && score(3, -5).cloudUsed == 0)
        #expect(score(0, 20).value == score(1, 20).value && score(10, 20).value == score(9, 20).value && score(99, 20).value == score(9, 20).value)
        for bortle in [-3, 0, 1, 9, 10, 99] {
            for cloud in [-5.0, 0, 150, .nan, .infinity] as [Double] {
                let value=score(bortle, cloud).value
                #expect((0...100).contains(value), "\(bortle) \(cloud)")
            }
        }
    }

    // MARK: Cache files

    /// A cache file that is empty, garbage, or written by a future version with a different shape
    /// reads as nothing (the bundled data and on-device math take over); unknown extra fields are ignored.
    @Test func damagedCacheFilesReadAsNothing() throws {
        let name="test-\(UUID().uuidString)"
        let file=CacheDirectory.url.appendingPathComponent("nyx-\(name).json")
        defer { CacheDirectory.remove(name: name) }
        for bytes in [Data(), Data("not json at all".utf8), Data([0xFF, 0x00, 0xFE]), Data("{\"updated\":\"tomorrow\",\"times\":{},\"clouds\":7}".utf8)] {
            try bytes.write(to: file)
            #expect(CacheDirectory.read(Forecast.self, name: name) == nil)
            #expect(CacheDirectory.read(ParkAlertsCache.self, name: name) == nil)
        }
        try Data("{\"updated\":800000000,\"times\":[1790000000],\"clouds\":[12],\"schema\":9,\"models\":{\"x\":[1]}}".utf8).write(to: file)
        #expect(CacheDirectory.read(Forecast.self, name: name)?.clouds == [12])
    }

    // MARK: The poles

    /// Saved spots at Svalbard in June and December and at the South Pole: explicit polar states,
    /// finite hours, and a score in range, never NaN.
    @Test func polarSpotsHaveFiniteNights() throws {
        let svalbard=Self.spot("d4", 78.2, 15.6, "Arctic/Longyearbyen"), pole=Self.spot("e5", -89.9, 0, SavedSpots.solarZone(longitude: 0))
        let cases: [(Park, Int, DarknessState)]=[(svalbard, 6, .polarDay), (svalbard, 12, .normal), (pole, 12, .polarDay), (pole, 6, .polarNight)]
        for (place, month, state) in cases {
            let evening=try Self.local(place, 2026, month, 21, 12)
            let sky=AstronomyEngine().conditions(for: place, on: evening)
            #expect(sky.state == state || (state == .normal && sky.state == .polarNight), "\(place.latitude) \(month) \(sky.state)")
            #expect(sky.darkHours.isFinite && (0...24.01).contains(sky.darkHours))
            if state == .polarDay { #expect(sky.darkHours == 0 && sky.sunset == nil) }
            let value=ScoreEngine().score(sky: sky, bortle: place.bortleEstimate, cloudCover: 10).value
            #expect((0...100).contains(value))
            _=place.currentNight(at: evening.addingTimeInterval(14*3600))
            #expect(!place.nightTurnovers(from: evening, to: evening.addingTimeInterval(86400+60)).isEmpty)
        }
        for longitude in [180.0, -180, 179.9, -179.9] {
            let zone=SavedSpots.solarZone(longitude: longitude)
            #expect(TimeZone(identifier: zone) != nil, "\(zone)")
        }
        #expect(SavedSpots.solarZone(longitude: 180) == "Etc/GMT-12" && SavedSpots.solarZone(longitude: -180) == "Etc/GMT+12")
    }

    // MARK: A hostile journal file

    /// Out-of-range Bortle classes are clamped, a park id that is a path is never stored, spots at
    /// impossible coordinates are left out, and one photo file named several times is used once.
    @MainActor @Test func hostileJournalImportsSafely() throws {
        let opened=JournalStore.open(inMemory: true)
        let context=ModelContext(try #require(opened.container))
        let size=CGSize(width: 8, height: 8)
        let format=UIGraphicsImageRendererFormat(); format.scale=1
        let photo=try #require(UIGraphicsImageRenderer(size: size, format: format).image { $0.fill(CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: 0.8))
        let shared=JournalArchive.Photo(file: "same.jpg", altText: nil)
        func entry(_ parkID: String, _ bortle: Int, _ photos: [JournalArchive.Photo]) -> JournalArchive.Entry {
            JournalArchive.Entry(id: UUID(), date: Date(timeIntervalSince1970: 1_790_000_000+Double(bortle)*86400), parkID: parkID,
                                 observedBortle: bortle, notes: "Night \(parkID) \(bortle)", photos: photos)
        }
        let entries=[entry("../x", 0, [shared]), entry("jotr", 99, [shared, shared]), entry("JOTR/../../etc", 5, []), entry("wd:Q24451", -4, [JournalArchive.Photo(file: "../../secret", altText: nil)])]
        func badSpot(_ suffix: String, _ latitude: Double, _ longitude: Double) -> JournalArchive.Spot {
            JournalArchive.Spot(id: "pin:00000000-0000-4000-8000-0000000000\(suffix)", name: "Bad", latitude: latitude, longitude: longitude, timeZoneID: "Nowhere/Zone",
                                countryCode: "", region: "", created: .now, note: nil, saved: true)
        }
        let spots=[badSpot("f1", .nan, 10), badSpot("f2", 10, .infinity), badSpot("f3", 91, 0), badSpot("f4", 40, -105), JournalArchive.Spot(id: "../pin", name: "Bad", latitude: 1, longitude: 1,
                   timeZoneID: "UTC", countryCode: "", region: "", created: .now, note: nil, saved: true)]
        let archive=JournalArchive(manifest: JournalArchive.Manifest(format: 2, exported: .now, entries: entries, spots: spots), photos: ["same.jpg": photo])
        let result=try archive.merge(into: context)
        #expect(result.added == 4 && result.skipped == 0)
        let stored=try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(stored.allSatisfy { (1...9).contains($0.observedBortle) })
        #expect(Set(stored.map(\.parkID)) == ["", "jotr", "wd:Q24451"])
        // The first entry to name the file has it; the second, naming it twice, has none.
        #expect(stored.first { $0.parkID == "jotr" }?.orderedPhotos.isEmpty == true)
        #expect(stored.first { $0.notes.hasPrefix("Night ../x") }?.orderedPhotos.count == 1)
        #expect(stored.first { $0.parkID == "wd:Q24451" }?.orderedPhotos.isEmpty == true)
        // Only the spot at real coordinates arrives, in a zone that exists.
        let kept=try context.fetch(FetchDescriptor<SavedSpot>())
        #expect(kept.map(\.latitude) == [40] && kept.allSatisfy { TimeZone(identifier: $0.timeZoneID) != nil })
    }
}
