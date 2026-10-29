import Foundation
import SwiftUI
import Testing
@testable import Nyx

/// The iPhone's and iPad's screens give one answer in one set of words: Assistive Access weighs the
/// places Tonight weighs, a forecast is old by one measure, the Moon is thin by one threshold, and
/// the lines under a dial follow one rule for a clear window.
@MainActor @Suite struct OneAnswerTests {
    let parks: [Park] = (try? ParkData.load()) ?? []
    func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }
    func model() -> PlanModel {
        PlanModel(weather: WeatherService(transport: StubHTTP([:]), persist: false), parkStore: ParkStore(transport: StubHTTP([:]), persist: false),
                  detail: ForecastDetailService(transport: StubHTTP([:]), persist: false), defaults: isolatedDefaults())
    }

    /// Under Near me the device is the starting point everywhere, Assistive Access included: it once
    /// measured from the chosen starting point and could name another place than the full app.
    @Test func assistiveAccessWeighsTonightsPlaces() throws {
        let model = model(), jotr = try park("jotr"), acad = try park("acad")
        model.choose(parkID: jotr.id)
        #expect(AssistiveTonight.inReach(model).map(\.id) == model.shortlistInReach.map(\.id))
        model.location.latitude = acad.latitude; model.location.longitude = acad.longitude
        defer { model.location.latitude = nil; model.location.longitude = nil }
        let reach = AssistiveTonight.inReach(model)
        #expect(reach.map(\.id) == model.shortlist(model.placesInReach().places).map(\.id))
        #expect(reach.contains { $0.id == acad.id } && !reach.contains { $0.id == jotr.id })
        #expect(AssistiveTonight.best(model)?.id == model.ranked(model.shortlistInReach).first?.id)
    }
    /// A forecast is old once clouds would be asked for again (`ForecastReuse.clouds`), from the model's present.
    @Test func aForecastIsStaleByOneMeasure() {
        let model = model(), now = Date(timeIntervalSince1970: 1_792_180_800)
        model.presentOverride = now
        #expect(!model.forecastIsStale(now.addingTimeInterval(-ForecastReuse.clouds+60)))
        #expect(model.forecastIsStale(now.addingTimeInterval(-ForecastReuse.clouds-60)))
    }
    /// A clear window is said only while it is ahead and covers at most three quarters of true darkness.
    @Test func aClearWindowIsSaidOnlyWhenPartial() throws {
        let jotr = try park("jotr"), now = Date(timeIntervalSince1970: 1_792_180_800)
        let sky = AstronomyEngine().conditions(for: jotr, on: jotr.currentNight(at: now))
        let night = NightPlanner.night(park: jotr, sky: sky, forecast: nil, detail: nil, now: now)
        let start = try #require(sky.darkStart), dark = sky.darkHours*3600
        #expect(dark > 0)
        let late = ClearWindow(interval: DateInterval(start: start.addingTimeInterval(dark/2), duration: dark/4), moonDown: true, core: nil)
        let whole = ClearWindow(interval: DateInterval(start: start, duration: dark), moonDown: true, core: nil)
        #expect(NightNotes<EmptyView>.partialWindow(night, window: late, now: now) == late)
        #expect(NightNotes<EmptyView>.partialWindow(night, window: whole, now: now) == nil)
        #expect(NightNotes<EmptyView>.partialWindow(night, window: late, now: late.interval.end.addingTimeInterval(60)) == nil)
    }
    /// A kept night's first line and the share card say the Moon in the shared words (`MoonPhase.litText`),
    /// and the card draws the disc exactly when the Moon is not negligible.
    @Test func keptNightsAndCardsSayTheMoonOneWay() throws {
        let jotr = try park("jotr")
        for day in [0, 4, 9, 15] {
            let now = Date(timeIntervalSince1970: 1_792_180_800+Double(day)*86_400)
            let night = NightPlanner.night(park: jotr, sky: AstronomyEngine().conditions(for: jotr, on: jotr.currentNight(at: now)), forecast: nil, detail: nil, now: now)
            let moon = night.sky.moon
            #expect(JournalPrefill(night: night).notes.hasSuffix("\(moon.name), \(moon.litText)."))
            let line = ShareCard(night: night).dateLine
            #expect(moon.negligible ? line != jotr.dayLabel(night.id) : line == jotr.dayLabel(night.id))
        }
    }
}
