import Foundation
import Testing
@testable import Nyx

/// Routes into the app on a cold launch (widgets, reminders, Spotlight, links, Handoff, Siri) and the
/// world catalogue read off the main thread from launch: a place abroad is waited for, never dropped
/// or swapped for another; a starting point abroad picked before the catalogue arrives ends at a place
/// near it. Also what Siri says about closures where Nyx cannot check them, the forecast cache Siri
/// reads for places abroad, a spot's reminder spacing and the world list's order.
@MainActor
struct LaunchRoutingTests {
    private static let kruger="wd:Q24451"
    private static func model() -> PlanModel {
        PlanModel(weather: WeatherService(transport: StubHTTP([:]), persist: false), parkStore: ParkStore(transport: StubHTTP([:]), persist: false),
                  detail: ForecastDetailService(transport: StubHTTP([:]), persist: false))
    }
    private static func catalogPlace(_ id: String) throws -> Park { try #require(try CatalogData.load().first { $0.id == id }) }
    private static let spot=Place(spotID: "pin:00000000-0000-4000-8000-0000000000ab", name: "Pullout off Pinto Basin Road", latitude: 33.92, longitude: -115.93,
                                  timeZoneID: "America/Los_Angeles", countryCode: "US", region: "California")

    // MARK: Cold launch

    /// A place abroad named before the catalogue is read is found once it is; a park at once; an id
    /// Nyx does not know is nothing, never another place.
    @Test func aPlaceAbroadNamedOnAColdLaunchIsWaitedFor() async throws {
        let model=Self.model()
        // Straight after launch, before the catalogue has been installed: not known yet, and waited for.
        #expect(model.park(Self.kruger) == nil && model.awaitsCatalog(Self.kruger))
        #expect(!model.awaitsCatalog("jotr") && !model.awaitsCatalog("pin:00000000-0000-4000-8000-000000000000"))
        let found=await model.place(named: Self.kruger)
        #expect(found?.id == Self.kruger)
        #expect(!model.awaitsCatalog(Self.kruger))
        #expect(await model.place(named: "jotr")?.id == "jotr")
        #expect(await model.place(named: "wd:Q1") == nil)
        #expect(await model.place(named: "pin:00000000-0000-4000-8000-000000000000") == nil)
    }
    /// Field mode with no place named: the last place used in the field, even abroad on a cold launch,
    /// else the starting place.
    @Test func fieldModeWithoutANamedPlaceWaitsForTheLastOneAbroad() async throws {
        let model=Self.model()
        #expect(await model.usualFieldPlace(lastUsed: Self.kruger)?.id == Self.kruger)
        #expect(await model.usualFieldPlace(lastUsed: nil)?.id == model.home?.id)
        #expect(await model.usualFieldPlace(lastUsed: "wd:Q1")?.id == model.home?.id)
    }
    /// A starting city abroad chosen before the catalogue is read (first run, `-nyx-place`) ends with
    /// the catalogue place nearest it as the home park, not the nearest US park an ocean away; a park
    /// chosen meanwhile is kept.
    @Test func aStartingPointAbroadChosenEarlyEndsNearIt() async throws {
        let defaults=UserDefaults.standard, keys=["homePark", "homePlace", "startChosen"]
        let kept=keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, kept) { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
        let windhoek=try #require(StartingPlaces.all.first { $0.name == "Windhoek" })
        let model=Self.model()
        #expect(!model.catalogIsReady)
        model.choose(windhoek)
        // Until the catalogue is read, the nearest curated park stands in.
        #expect(model.park(model.homeID)?.curated == true)
        await model.catalogReady()
        for _ in 0..<100 where !model.homeID.hasPrefix(Park.catalogPrefix) { try await Task.sleep(for: .milliseconds(10)) }
        let home=try #require(model.home)
        #expect(home.isCatalogPlace && home.countryCode == "NA")
        #expect(home.distanceMeters(latitude: windhoek.latitude, longitude: windhoek.longitude) < 1_000_000)

        // The person chose a park before the catalogue arrived: it stays.
        let other=Self.model()
        other.choose(windhoek)
        other.choose(parkID: "deva")
        await other.catalogReady()
        try await Task.sleep(for: .milliseconds(50))
        #expect(other.homeID == "deva")
    }

    // MARK: Handoff

    /// Handoff carries a place abroad as a link does, and refuses what a link would.
    @Test func handoffCarriesAPlaceAbroad() throws {
        let kruger=try Self.catalogPlace(Self.kruger)
        let evening=kruger.evening(kruger.currentNight(at: .now))
        let handoff=ParkHandoff(park: kruger, night: evening)
        #expect(handoff.userInfo["park"] == Self.kruger)
        let back=try #require(ParkHandoff(userInfo: handoff.userInfo))
        #expect(back == handoff && back.evening(in: kruger) == evening)
        #expect(ParkHandoff(userInfo: ["park": "wd%3AQ24451"])?.parkID == Self.kruger)
        #expect(ParkHandoff(userInfo: ["park": "JOTR"])?.parkID == "jotr")
        for bad in ["../x", "wd:Q0123", "wd:24451", "wd:Q", "wd:Q12a", "pin:nope", "jotr1", "x", "", "file:///etc"] {
            #expect(ParkHandoff(userInfo: ["park": bad]) == nil, "\(bad)")
        }
        // The same rule as links.
        for raw in ["jotr", "JOTR", "wd:Q24451", "wd%3AQ24451", "WD:q24451", "pin:00000000-0000-4000-8000-0000000000AB", "../x", "wd:Q0123", "pin:nope"] {
            #expect(PlaceIDText.validated(raw) == DeepLink.placeID(raw), "\(raw)")
        }
    }

    // MARK: Siri

    /// Siri reads a place abroad's cached forecast under the name the forecast client writes it.
    @Test func siriReadsAPlaceAbroadsCachedForecast() throws {
        let id="wd:Q\(Int.random(in: 900_000_000...999_999_999))"
        let name=SpotForecast.cacheName(id)
        #expect(name == "weather-" + id.replacingOccurrences(of: ":", with: "-"))
        defer { try? FileManager.default.removeItem(at: CacheDirectory.url.appendingPathComponent("nyx-\(name).json")) }
        let now=Date.now
        CacheDirectory.write(Forecast(updated: now, times: [now.timeIntervalSince1970], clouds: [12]), name: name)
        var place=try Self.catalogPlace(Self.kruger)
        place=Place(spotID: id, name: place.name, latitude: place.latitude, longitude: place.longitude, timeZoneID: place.timeZoneID,
                    countryCode: place.countryCode, region: place.region)
        #expect(BestNightSearch.forecasts(for: [place], shared: nil)[id]?.clouds == [12])
    }
    /// At a place the Park Service does not run, every spoken answer and card says Nyx cannot check
    /// closures there; a national park's answers are as they were.
    @Test func siriSaysWhereItCannotCheckClosures() throws {
        let kruger=try Self.catalogPlace(Self.kruger), jotr=try #require(try ParkData.load().first { $0.id == "jotr" })
        let abroad=String(localized: "Nyx can't check closures here. Check the park's own site before you go.")
        let local=String(localized: "Nyx has no alerts for this place. Check access, local rules and closures before you go.")
        #expect(DarknessAnswer.unknownClosures(kruger) == abroad && DarknessAnswer.unknownClosures(Self.spot) == local && DarknessAnswer.unknownClosures(jotr) == nil)
        let now=Date(timeIntervalSince1970: 1_790_899_200)
        for voiceOnly in [false, true] {
            for (park, line) in [(kruger, abroad), (Self.spot, local)] {
                let night=DarknessAnswer(park: park, forecast: nil, detail: nil, now: now, voiceOnly: voiceOnly).night
                let dialog=DarknessAnswer.dialog(night, closure: nil, voiceOnly: voiceOnly)
                #expect(dialog == night.spokenSummary(.siriTonight(voiceOnly: voiceOnly)) + " " + line)
                let best=try #require(BestNightSearch.answer(parks: [park], planner: NightPlanner(forecasts: [:]), from: now, nights: 7, now: now))
                #expect(BestNightSearch.dialog(best, voiceOnly: voiceOnly).hasSuffix(line))
                #expect(DarkWindowAnswer.dialog(park: park, sky: night.sky, closure: nil, voiceOnly: voiceOnly, device: park.timeZone).hasSuffix(line))
                #expect(WhatsUpAnswer.dialog(WhatsUp(park: park, sky: night.sky, isTonight: true), park: park, closure: nil, voiceOnly: voiceOnly, device: park.timeZone).hasSuffix(line))
            }
            let night=DarknessAnswer(park: jotr, forecast: nil, detail: nil, now: now).night
            #expect(DarknessAnswer.dialog(night, closure: nil, voiceOnly: voiceOnly) == night.spokenSummary(.siriTonight(voiceOnly: voiceOnly)))
            #expect(!DarknessAnswer.dialog(night, closure: "Park closed.", voiceOnly: voiceOnly).contains(abroad))
        }
    }

    // MARK: Reminders

    /// A spot's reminder holds the spot for the week, as a park's does, though its id has hyphens.
    @Test func aSpotsReminderHoldsItForTheWeek() throws {
        let now=Date(timeIntervalSince1970: 1_790_899_200)
        let spot=Self.spot
        func night(_ days: Int) -> Night {
            let sky=AstronomyEngine().conditions(for: spot, on: spot.date(spot.currentNight(at: now), addingDays: days))
            return Night(park: spot, sky: sky, score: DarknessScore(value: 94, moonPoints: 39, cloudPoints: 24, bortlePoints: 18, lengthPoints: 13),
                         cloudCover: 4, forecastUpdated: now.addingTimeInterval(Double(days-1)*86_400))
        }
        let seen=NotificationScheduler.identifier(park: spot, night: night(1).id)
        let parsed=try #require(NotificationScheduler.scoreReminder(seen))
        #expect(parsed.parkID == spot.id && parsed.night == night(1).id)
        let scheduler=NotificationScheduler(center: StubNotifications(), ledger: ReminderLedger(suite: "nyx-ledger-test-\(UUID().uuidString)"))
        #expect(scheduler.plans(nights: [night(2)], now: now).count == 1)
        #expect(scheduler.plans(nights: [night(2)], now: now, delivered: [seen]).isEmpty)
        // Parks and places abroad read as before; shower reminders and strangers are not score reminders.
        #expect(NotificationScheduler.scoreReminder("nyx-night-jotr-1790899200")?.parkID == "jotr")
        #expect(NotificationScheduler.scoreReminder("nyx-night-wd:Q24451-1790899200")?.parkID == "wd:Q24451")
        #expect(NotificationScheduler.scoreReminder("nyx-night-jotr-meteors-1790899200") == nil)
        #expect(NotificationScheduler.scoreReminder("nyx-night-1790899200") == nil)
        #expect(NotificationScheduler.scoreReminder("nyx-night-jotr-x") == nil && NotificationScheduler.scoreReminder("other-jotr-1") == nil)
    }

    // MARK: The world list

    /// Within a country, places are in the order of the names the rows show, not their full names.
    @Test func aCountryIsInTheOrderOfTheNamesShown() throws {
        func place(_ id: String, _ name: String, short: String?) throws -> Park {
            let record: [String: Any]=["id": id, "name": name, "countryCode": "DE", "region": "", "kind": "nationalPark", "curated": false,
                                       "latitude": 50.0, "longitude": 10.0, "timeZoneID": "Europe/Berlin", "darkSkyDesignated": false,
                                       "bortleEstimate": 3, "description": "", "sourceURL": "https://www.wikidata.org/wiki/\(id.dropFirst(3))",
                                       "sourceNote": "Wikidata, CC0.", "viewingSpots": [] as [Any]]
            var park=try JSONDecoder().decode(Park.self, from: JSONSerialization.data(withJSONObject: record))
            park.localShortName=short
            return park
        }
        let rhoen=try place("wd:Q1", "Biosphärenreservat Rhön", short: "Rhön")
        let wald=try place("wd:Q2", "Nationalpark Bayerischer Wald", short: "Bayerischer Wald")
        let berchtesgaden=try place("wd:Q3", "Nationalpark Berchtesgaden", short: "Berchtesgaden")
        let etosha=try place("wd:Q4", "Etosha National Park", short: nil)
        let groups=WorldBrowse.groups([rhoen, wald, berchtesgaden, etosha], home: "DE") { $0 }
        #expect(groups.first?.places.map(\.shortName) == ["Bayerischer Wald", "Berchtesgaden", "Etosha", "Rhön"])
        #expect(WorldBrowse.shownBefore(wald, rhoen) && !WorldBrowse.shownBefore(rhoen, wald))
    }
}
