import Foundation
import Testing
@testable import Nyx

/// The same park and night read the same however long Nyx has been open or offline: a kept night
/// follows the forecast's age, notes under lists use the rows' words, Ask Nyx reads the app's clock,
/// smoke that no longer reaches a night is said, and reminders neither repeat nor swap on a tie.
@MainActor @Suite struct StaleInputsTests {
    let parks: [Park] = (try? ParkData.load()) ?? []
    let now = Date(timeIntervalSince1970: 1_792_180_800) // 2026-10-16 20:00 UTC
    func night(_ park: Park, daysAhead: Int = 0, forecast: Forecast? = nil, detail: ForecastDetail? = nil, climate: CloudClimate = .shared) -> Night {
        let sky = AstronomyEngine().conditions(for: park, on: park.date(park.currentNight(at: now), addingDays: daysAhead))
        return NightPlanner.night(park: park, sky: sky, forecast: forecast, detail: detail, now: now, climate: climate)
    }
    func model() -> PlanModel {
        PlanModel(weather: WeatherService(transport: StubHTTP([:]), persist: false), parkStore: ParkStore(transport: StubHTTP([:]), persist: false),
                  detail: ForecastDetailService(transport: StubHTTP([:]), persist: false), defaults: isolatedDefaults())
    }

    // MARK: A kept night follows the forecast's age

    /// A forecast 35 hours old that ends before tonight: "No cloud forecast yet". Two hours later,
    /// with no new forecast, it is no longer recent and tonight is "Cloud forecast unavailable", as
    /// the widget and Siri (computing afresh) say, although the night was kept.
    @Test func keptNightTurnsUnavailablePastThirtySixHours() throws {
        let model = model(), jotr = try park("jotr")
        let start = Date.now
        model.presentOverride = start
        let window = AstronomyEngine().conditions(for: jotr, on: jotr.evening(model.tonight(jotr))).cloudWindow
        let updated = start.addingTimeInterval(-35*3600)
        let first = (floor(updated.timeIntervalSince1970/3600)-24)*3600
        let last = min(window.start.timeIntervalSince1970, start.timeIntervalSince1970)-3*3600
        let hours = Array(stride(from: first, through: last, by: 3600))
        model.forecasts[jotr.id] = Forecast(updated: updated, times: hours, clouds: hours.map { _ in 0 })
        let before = model.night(jotr)
        #expect(before.basis == .usual && before.beyondForecast && before.basisLabel == "No cloud forecast yet")
        model.presentOverride = start.addingTimeInterval(2*3600)
        let after = model.night(jotr)
        #expect(!after.beyondForecast && after.basisLabel == "Cloud forecast unavailable")
        let fresh = NightPlanner.night(park: jotr, sky: after.sky, forecast: model.forecasts[jotr.id], detail: nil, now: start.addingTimeInterval(2*3600))
        #expect(after.basisLabel == fresh.basisLabel && after.score.value == fresh.score.value)
    }

    // MARK: Notes under lists in the rows' words

    @Test func estimateNoteSaysWhatTheRowsSay() throws {
        let jotr = try park("jotr")
        let tonight = night(jotr), later = night(jotr, daysAhead: 12), bare = night(jotr, climate: CloudClimate(parks: [:]))
        #expect(UsualCloudsNote([]) == nil)
        let hours = (0..<(17*24)).map { (floor(now.timeIntervalSince1970/3600)-24+Double($0))*3600 }
        #expect(UsualCloudsNote([night(jotr, forecast: Forecast(updated: now, times: hours, clouds: hours.map { _ in 0 }))]) == nil)
        let unavailable = try #require(UsualCloudsNote([tonight]))
        #expect(unavailable.estimate == "Scores marked Estimate: cloud forecast unavailable. They use each park's usual clouds.")
        #expect(unavailable.estimate.localizedCaseInsensitiveContains(try #require(tonight.basisLabel)))
        #expect(!unavailable.estimate.contains("yet"))
        let notYet = try #require(UsualCloudsNote([later]))
        #expect(notYet.estimate == "Scores marked Estimate: no cloud forecast yet. They use each park's usual clouds.")
        #expect(notYet.estimate.localizedCaseInsensitiveContains(try #require(later.basisLabel)))
        #expect(UsualCloudsNote([bare])?.estimate == "Scores marked Estimate: cloud forecast unavailable. They count the Moon and darkness only.")
        #expect(UsualCloudsNote([tonight, later, bare])?.estimate
                == "Scores marked Estimate: no cloud forecast yet, or unavailable. They use each park's usual clouds, or the Moon and darkness only where those are not known.")
        #expect(notYet.hollow == "Hollow: no cloud forecast yet, so the park's usual clouds.")
        #expect(UsualCloudsNote([bare])?.hollow == "Hollow: cloud forecast unavailable, so the Moon and darkness only.")
    }
    /// The calendar's key and the river's tip name only the hollow nights there are.
    @Test func monthKeyAndRiverTipFollowTheirNights() throws {
        let jotr = try park("jotr")
        let tonight = night(jotr), later = night(jotr, daysAhead: 12)
        #expect(CalendarView.legend([tonight, later]).contains("Hollow: no cloud forecast yet, or unavailable, so the park's usual clouds."))
        #expect(CalendarView.legend([later]).contains("Hollow: no cloud forecast yet, so the park's usual clouds."))
        #expect(CalendarView.legend([]).hasPrefix("Solid: full forecast.") && !CalendarView.legend([]).contains("Hollow"))
        let tip = RiverTip.message(hollow: UsualCloudsNote([tonight])?.hollow)
        #expect(tip.hasPrefix("Hollow: cloud forecast unavailable, so the park's usual clouds. Half-filled"))
        #expect(!RiverTip.message(hollow: nil).contains("Hollow"))
    }

    // MARK: Ask Nyx on the app's clock

    /// `today` moves only when a night turns over; Ask Nyx reads forecasts' age on `present`, as the park page does.
    @Test func askNyxReadsTheAppsClock() throws {
        let model = model()
        let later = model.today.addingTimeInterval(5*3600)
        model.presentOverride = later
        #expect(GuideView.lookup(model).now == later)
        #expect(GuideView.lookup(model).now == model.present)
        #expect(GuideView.lookup(model).today == model.today)
    }
    /// Just after sunrise at Joshua Tree, before the app's `today` has moved on: Ask Nyx's tonight is
    /// still the Tonight tab's night, while forecasts' age is read on the real clock.
    @Test func askNyxsTonightIsTheTonightTabs() throws {
        let jotr = try park("jotr")
        let beforeSunrise = Date(timeIntervalSince1970: 1_792_180_800-7*3600), afterSunrise = beforeSunrise.addingTimeInterval(90*60)
        #expect(jotr.currentNight(at: beforeSunrise) != jotr.currentNight(at: afterSunrise))
        let lookup = NightLookup(parks: [jotr], forecasts: [:], now: afterSunrise, today: beforeSunrise)
        #expect(lookup.night("tonight", at: jotr) == jotr.currentNight(at: beforeSunrise))
        #expect(NightLookup(parks: [jotr], forecasts: [:], now: afterSunrise).night("tonight", at: jotr) == jotr.currentNight(at: afterSunrise))
        // Tonight asked for by its date is the same night, not pushed to the next one.
        let iso = jotr.isoDay(jotr.currentNight(at: beforeSunrise))
        #expect(lookup.bestNights(park: "Joshua Tree", from: iso, nights: 1) == lookup.bestNights(park: "Joshua Tree", from: "tonight", nights: 1))
    }

    // MARK: Smoke that ends before the night

    /// A smoke forecast cached a week ago no longer covers tonight: the score cannot count it, and the
    /// headset says so beside the score, in the row's words and above the list.
    @Test func smokeThatEndsBeforeTheNightIsSaid() throws {
        let jotr = try park("jotr")
        let first = (floor(now.timeIntervalSince1970/3600)-8*24)*3600
        let old = (0..<(5*24)).map { first+Double($0)*3600 }
        let stale = HourlySeries(updated: now.addingTimeInterval(-8*86400), times: old, values: ["aerosol_optical_depth": old.map { _ in 0.6 }])
        let tonight = night(jotr, detail: ForecastDetail(air: stale))
        #expect(tonight.aerosol == nil && !tonight.score.isSmokeLimited)
        let inputs = ScoreInputs(smokeKnown: [jotr.id])
        let reach = String(localized: "No smoke forecast on this device reaches this night, so smoke is not counted.")
        #expect(inputs.smokeNote(jotr, night: tonight) == reach)
        #expect(inputs.spoken(jotr, night: tonight).contains(String(localized: "Smoke not counted.")))
        #expect(inputs.listNote([jotr], nights: [jotr.id: tonight])?.contains(reach) == true)
        // A forecast that covers the night counts, and nothing is said.
        let hours = (0..<(5*24)).map { (floor(now.timeIntervalSince1970/3600)-24+Double($0))*3600 }
        let fresh = night(jotr, detail: ForecastDetail(air: HourlySeries(updated: now, times: hours, values: ["aerosol_optical_depth": hours.map { _ in 0.05 }])))
        #expect(fresh.aerosol != nil)
        #expect(inputs.smokeNote(jotr, night: fresh) == nil && !inputs.spoken(jotr, night: fresh).contains(String(localized: "Smoke not counted.")))
        #expect(inputs.listNote([jotr], nights: [jotr.id: fresh]) == nil || inputs.listNote([jotr], nights: [jotr.id: fresh])?.contains(reach) == false)
    }

    // MARK: Shower reminders

    func showerNights() throws -> (now: Date, jotr: Night, deva: Night) {
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let morning = try #require(pacific.date(from: DateComponents(year: 2026, month: 12, day: 13, hour: 8)))
        func peak(_ id: String) throws -> Night {
            let park = try park(id)
            return NightPlanner.night(park: park, sky: AstronomyEngine().conditions(for: park, on: park.evening(morning)), forecast: nil, detail: nil, now: morning)
        }
        let jotr = try peak("jotr"), deva = try peak("deva")
        for night in [jotr, deva] { #expect(WhatsUp.Events(park: night.park, sky: night.sky).reminderShower?.shower.code == "GEM") }
        return (morning, jotr, deva)
    }
    /// One reminder a night across saved parks: an open park before a closed one, whichever rate.
    @Test func showerReminderTakesTheOpenPark() throws {
        let (now, jotr, deva) = try showerNights()
        let scheduler = NotificationScheduler(center: StubNotifications(), ledger: ReminderLedger(suite: "nyx-ledger-test-\(UUID().uuidString)"))
        #expect(scheduler.showerPlans(nights: [jotr, deva], now: now, delivered: [], closures: ["jotr": "Park Boulevard closed"]).map(\.parkID) == ["deva"])
        #expect(scheduler.showerPlans(nights: [jotr, deva], now: now, delivered: [], closures: ["deva": "Badwater Road closed"]).map(\.parkID) == ["jotr"])
        #expect(scheduler.showerPlans(nights: [jotr, deva], now: now, delivered: []).count == 1)
    }
    /// Death Valley's shower reminder was delivered at 16:00; a closure there since makes Joshua Tree
    /// the open pick, but that night already had its reminder: no second one.
    @Test func deliveredShowerReminderIsNotRepeatedElsewhere() throws {
        let (now, jotr, deva) = try showerNights()
        let scheduler = NotificationScheduler(center: StubNotifications(), ledger: ReminderLedger(suite: "nyx-ledger-test-\(UUID().uuidString)"))
        let told = NotificationScheduler.showerIdentifier(park: deva.park, night: deva.id)
        #expect(scheduler.showerPlans(nights: [jotr, deva], now: now, delivered: [told], closures: ["deva": "Badwater Road closed"]).isEmpty)
        #expect(scheduler.plans(nights: [jotr, deva], now: now, delivered: [told], showers: true, closures: ["deva": "Badwater Road closed"]).isEmpty)
        // A park no longer saved: its delivered reminder still holds the night.
        let zion = try park("zion")
        let elsewhere = NotificationScheduler.showerIdentifier(park: zion, night: zion.evening(jotr.id))
        #expect(scheduler.showerPlans(nights: [jotr], now: now, delivered: [elsewhere]).isEmpty)
    }

    /// A removed place's delivered shower reminder blocks its own local day: Haleakalā's noon and a
    /// spot in Tonga's fall in the same UTC hours a day apart, so each is read in its own time zone.
    @Test func deliveredShowerDayIsThePlacesOwn() throws {
        func noon(_ zone: String) throws -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: zone))
            return try #require(calendar.date(from: DateComponents(year: 2026, month: 12, day: 13, hour: 12)))
        }
        let hawaii = "nyx-night-hale-meteors-\(Int(try noon("Pacific/Honolulu").timeIntervalSince1970))"
        #expect(NotificationScheduler.showerDays([hawaii], nights: []) == ["2026-12-13"])
        let tonga = "nyx-night-pin:5C1A-77E2-meteors-\(Int(try noon("Pacific/Tongatapu").timeIntervalSince1970))"
        #expect(NotificationScheduler.showerDays([tonga], nights: [], zone: { _ in TimeZone(identifier: "Pacific/Tongatapu") }) == ["2026-12-13"])
        #expect(NotificationScheduler.showerDays([tonga], nights: [], zone: { _ in nil }) == ["2026-12-12"])
    }

    // MARK: A pending reminder keeps its night on a tie

    /// Two nights at Zion scoring 94: with nothing pending, the night every surface names; with the
    /// other already pending, it stays rather than swapping on a refresh.
    @Test func pendingReminderKeepsItsNightOnATie() async throws {
        let zion = try park("zion"), engine = AstronomyEngine()
        let now = Date(timeIntervalSince1970: 1790899200-6*3600), tonight = zion.currentNight(at: now)
        func night(_ offset: Int, moon: Double) -> Night {
            Night(park: zion, sky: engine.conditions(for: zion, on: zion.date(tonight, addingDays: offset)),
                  score: DarknessScore(value: 94, moonPoints: moon, cloudPoints: 24, bortlePoints: 18, lengthPoints: 13), cloudCover: 4, forecastUpdated: now)
        }
        let earlier = night(1, moon: 39), later = night(2, moon: 45)
        #expect(NightPlanner.better(later, earlier))
        let earlierID = NotificationScheduler.identifier(park: zion, night: earlier.id), laterID = NotificationScheduler.identifier(park: zion, night: later.id)
        let scheduler = NotificationScheduler(center: StubNotifications(), ledger: ReminderLedger(suite: "nyx-ledger-test-\(UUID().uuidString)"))
        #expect(scheduler.plans(nights: [earlier, later], now: now).map(\.id) == [laterID])
        #expect(scheduler.plans(nights: [earlier, later], now: now, pending: [earlierID]).map(\.id) == [earlierID])
        // A night that scores higher still wins over a pending one.
        let higher = Night(park: zion, sky: later.sky, score: DarknessScore(value: 95, moonPoints: 45, cloudPoints: 24, bortlePoints: 18, lengthPoints: 13), cloudCover: 4, forecastUpdated: now)
        #expect(scheduler.plans(nights: [earlier, higher], now: now, pending: [earlierID]).map(\.id) == [laterID])
        // Through a refresh: the pending one stays, the other is never added.
        let center = StubNotifications(ids: [earlierID])
        await NotificationScheduler(center: center, ledger: ReminderLedger(suite: "nyx-ledger-test-\(UUID().uuidString)")).reschedule(nights: [earlier, later], now: now)
        let pending = await center.pendingIDs()
        #expect(pending.contains(earlierID) && !pending.contains(laterID))
    }
}
