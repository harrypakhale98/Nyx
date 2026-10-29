import Foundation
import Testing
import UIKit
@testable import Nyx

/// What Apple Watch follows when the iPhone is out of reach for a while: the places it asked for
/// reach the iPhone once it can be told, Tonight's pick on the iPhone lasts only its own night, a
/// spot travels with its usual clouds or not at all, and every line under a score says what would help.
@MainActor struct WatchFollowTests {
    /// 2026-10-07 12:00 UTC.
    let now = Date(timeIntervalSince1970: 1_791_158_400 + 30*3600)
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }

    /// Told once per list: a place kept while the iPhone was away, or a face set to a park it does
    /// not follow, is told when it can be; the same list is not told again at every wake.
    @Test func theWatchTellsTheIPhoneItsPlacesOncePerList() {
        let following = WatchContext(sent: now, savedParkIDs: ["deva"], homeParkID: "jotr", nightVision: false, forecasts: [:], watchParkIDs: ["yell"])
        // Nothing to say: the iPhone already follows what the watch wants (in any order).
        #expect(!WatchContext.shouldTell(["yell"], context: following, told: nil, toldAt: nil, now: now))
        #expect(!WatchContext.shouldTell([], context: WatchContext(sent: now, savedParkIDs: [], homeParkID: "jotr", nightVision: false, forecasts: [:]),
                                         told: nil, toldAt: nil, now: now))
        // A place kept while the iPhone was out of reach, or a face set since.
        #expect(WatchContext.shouldTell(["yell", "grca"], context: following, told: nil, toldAt: nil, now: now))
        // A place let go of: the iPhone can stop following it.
        #expect(WatchContext.shouldTell([], context: following, told: nil, toldAt: nil, now: now))
        // Before anything has come from the iPhone.
        #expect(WatchContext.shouldTell(["yell"], context: nil, told: nil, toldAt: nil, now: now))
        // Told already and answered: not again for a while, even if the iPhone cannot follow it.
        #expect(!WatchContext.shouldTell(["grca"], context: following, told: ["grca"], toldAt: now.addingTimeInterval(-3600), now: now))
        #expect(WatchContext.shouldTell(["grca"], context: following, told: ["grca"], toldAt: now.addingTimeInterval(-WatchContext.retell), now: now))
        // Another list, or a told moment in the future (the clock was changed), is told again.
        #expect(WatchContext.shouldTell(["grca"], context: following, told: ["zion"], toldAt: now, now: now))
        #expect(WatchContext.shouldTell(["grca"], context: following, told: ["grca"], toldAt: now.addingTimeInterval(600), now: now))
    }
    /// Lists compare as sets, and the watch never asks for more than the iPhone follows: faces
    /// reordered, or a ninth place the iPhone would cut, ask nothing new until `retell`.
    @Test func reorderedOrLongListsAreNotToldAgain() {
        let following = WatchContext(sent: now, savedParkIDs: ["deva"], homeParkID: "jotr", nightVision: false, forecasts: [:], watchParkIDs: ["yell"])
        #expect(!WatchContext.shouldTell(["grca", "zion"], context: following, told: ["zion", "grca"], toldAt: now.addingTimeInterval(-60), now: now))
        let many = (1...10).map { "p\($0)" }
        let wanted = WatchContext.wanted(pinned: "p1", faces: many)
        #expect(wanted == Array(many.prefix(WatchContext.maxWatchPlaces)) && WatchContext.maxWatchPlaces == WatchRequest.maxPlaces)
        #expect(WatchContext.wanted(pinned: "zion", faces: ["grca", "zion"]) == ["zion", "grca"])
        // The iPhone follows the eight it was handed: nothing to tell.
        let eight = WatchContext(sent: now, savedParkIDs: [], homeParkID: "jotr", nightVision: false, forecasts: [:], watchParkIDs: wanted)
        #expect(!WatchContext.shouldTell(many, context: eight, told: nil, toldAt: nil, now: now))
        // One of them it cannot follow (a spot removed): told once, then not again for a while.
        let seven = WatchContext(sent: now, savedParkIDs: [], homeParkID: "jotr", nightVision: false, forecasts: [:], watchParkIDs: Array(wanted.dropFirst()))
        #expect(!WatchContext.shouldTell(wanted, context: seven, told: wanted.reversed(), toldAt: now.addingTimeInterval(-3600), now: now))
        #expect(WatchContext.shouldTell(wanted, context: seven, told: wanted, toldAt: now.addingTimeInterval(-WatchContext.retell), now: now))
    }

    /// A place the watch wants but the iPhone does not follow yet offers to ask, in words that say
    /// so; a park merely browsed still says to save it.
    @Test func aWantedPlaceTheIPhoneDoesNotFollowCanBeAskedFor() throws {
        let yell = try park("yell"), deva = try park("deva")
        let context = WatchContext.make(savedParkIDs: ["deva"], homeParkID: "jotr", nightVision: false, forecasts: [:], now: now)
        let wanted = CloudSource.of(context: context, park: yell, now: now, wanted: ["yell"])
        #expect(wanted == .wanted && wanted.isStale)
        #expect(wanted.line(for: yell) == "Open Nyx on \(device) for clouds.")
        #expect(CloudSource.of(context: context, park: yell, now: now) == .missing(followed: false))
        // Followed already: asked for or not, the iPhone could refresh it.
        #expect(CloudSource.of(context: context, park: deva, now: now, wanted: ["deva"]) == .missing(followed: true))
        // Before any context there is nothing to compare with.
        #expect(CloudSource.of(context: nil, park: yell, now: now, wanted: ["yell"]) == .unsynced)
    }

    /// With "Clouds at your saved spots" off on the iPhone, a spot without a recent forecast says
    /// so, and offers no request that could not help; a park is unaffected.
    @Test func aSpotWithItsCloudsOffOnIPhoneSaysSo() throws {
        let spot = Place(spotID: "pin:00000000-0000-4000-8000-000000000001", name: "Test spot", latitude: 34.01, longitude: -116.17,
                         timeZoneID: "America/Los_Angeles", countryCode: "US", region: "CA")
        #expect(spot.id.hasPrefix(Park.spotPrefix) && Park.spotPrefix == SavedSpots.prefix)
        let off = WatchContext.make(savedParkIDs: [spot.id, "deva"], homeParkID: "jotr", nightVision: false, forecasts: [:], places: [spot], spotForecastsOff: true, now: now)
        let source = CloudSource.of(context: off, park: spot, now: now)
        #expect(source == .spotsOff && !source.isStale)
        #expect(source.line(for: spot) == String(localized: "Clouds at your saved spots is off in Nyx on iPhone."))
        #expect(CloudSource.of(context: off, park: try park("deva"), now: now) == .missing(followed: true))
        // An old forecast kept from before the switch went off cannot be refreshed either.
        let times = (0..<48).map { now.timeIntervalSince1970 - 3*86400 + Double($0)*3600 }
        let old = Forecast(updated: now.addingTimeInterval(-3*86400), times: times, clouds: times.map { _ in 20 })
        let kept = WatchContext.make(savedParkIDs: [spot.id], homeParkID: "jotr", nightVision: false, forecasts: [spot.id: old], places: [spot],
                                     spotForecastsOff: true, now: now.addingTimeInterval(-3*86400))
        #expect(CloudSource.of(context: kept, park: spot, now: now) == .spotsOff)
        // On: as before.
        let on = WatchContext.make(savedParkIDs: [spot.id], homeParkID: "jotr", nightVision: false, forecasts: [:], places: [spot], now: now)
        #expect(CloudSource.of(context: on, park: spot, now: now) == .missing(followed: true))
    }

    /// Tonight's pick on the iPhone answers only for the night it was picked for, as on the iPhone:
    /// a watch away from it for days falls back rather than showing last week's pick.
    @Test func tonightsPickLastsItsOwnNight() throws {
        let jotr = try park("jotr")
        let evening = try #require(jotr.calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 21)))
        let night = jotr.isoDay(jotr.currentNight(at: evening))
        let context = WatchContext.make(savedParkIDs: [], homeParkID: "deva", nightVision: false, forecasts: [:], tonightParkID: "jotr", tonightNight: night,
                                        now: evening)
        let sent = try #require(context.data.flatMap { WatchContext(data: $0) })
        #expect(sent.tonightNight == night)
        #expect(sent.stillPicks(jotr, at: evening))
        // Past midnight, before sunrise: still that night.
        #expect(sent.stillPicks(jotr, at: evening.addingTimeInterval(5*3600)))
        // The next day, and days later: no longer tonight's answer.
        #expect(!sent.stillPicks(jotr, at: evening.addingTimeInterval(16*3600)))
        #expect(!sent.stillPicks(jotr, at: evening.addingTimeInterval(5*86400)))
        #expect(!sent.stillPicks(try park("deva"), at: evening))
        // From an iPhone that did not send the night: the night the context was sent in stands in.
        let bytes = try #require(context.data)
        var object = try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        object["tonightNight"] = nil
        object["spotForecastsOff"] = nil
        object["alertsOff"] = nil; object["smokeOff"] = nil
        let older = try #require(WatchContext(data: try JSONSerialization.data(withJSONObject: object)))
        #expect(older.tonightNight == nil && !older.spotForecastsOff && older.tonightParkID == "jotr")
        #expect(!older.alertsOff && !older.smokeOff && older.alertsNote(jotr) == nil && older.smokeNote == nil)
        #expect(older.stillPicks(jotr, at: evening.addingTimeInterval(3600)) && !older.stillPicks(jotr, at: evening.addingTimeInterval(86400)))
        // A night without a pick is never carried.
        #expect(WatchContext.make(savedParkIDs: [], homeParkID: "deva", nightVision: false, forecasts: [:], tonightNight: night, now: evening).tonightNight == nil)
        // The two new values count in what was sent.
        #expect(context != context.stamped(tonightNight: "2026-10-08") && context != context.stamped(spotsOff: true))
        #expect(context != context.stamped(alertsOff: true) && context != context.stamped(smokeOff: true))
        // The iPhone's switches off: its own words, said on the wrist, and they survive the trip.
        let off = try #require(context.stamped(alertsOff: true, smokeOff: true).data.flatMap { WatchContext(data: $0) })
        #expect(off.alertsNote(jotr) == String(localized: "Park alerts are off in Your privacy, so closures are not checked."))
        #expect(off.smokeNote == String(localized: "Smoke and haze are off in Your privacy, so smoke is not counted."))
        #expect(off.stamped(alertsOff: true).alertsNote(jotr) != nil && WatchContext(sent: evening, savedParkIDs: [], homeParkID: "jotr", nightVision: false, forecasts: [:],
                closures: ["jotr": "Road closed"], alertsOff: true).alertsNote(jotr) == nil)
    }

    /// A spot or world place travels with its usual clouds or not at all: without them the wrist
    /// would score its nights past the forecast with no clouds, clearer than the iPhone's.
    @Test func aPlaceNeverTravelsWithoutItsUsualClouds() throws {
        let places = Array(try TestData.catalog().lazy.filter { CloudClimate.shared.months(for: $0) != nil }.prefix(400))
        let context = WatchContext.make(savedParkIDs: places.map(\.id), homeParkID: "jotr", nightVision: false, forecasts: [:], places: places, now: now)
        #expect((context.data?.count ?? .max) <= WatchContext.byteBudget)
        // Not trivial: the budget ran out among the places.
        #expect(!context.places.isEmpty && context.places.count < places.count)
        #expect(context.places.allSatisfy { context.usualClouds[$0.id] != nil })
        #expect(context.places.map(\.id) == Array(places.prefix(context.places.count)).map(\.id))
    }

    /// The face keeps its one-line design only where nothing would be cut: a closure always wraps whole.
    @Test func aClosureIsNeverCutOnTheWatchFace() {
        #expect(WatchTonightLayout.designed(standardSize: true, closure: false))
        #expect(!WatchTonightLayout.designed(standardSize: true, closure: true))
        #expect(!WatchTonightLayout.designed(standardSize: false, closure: false))
        // Measured, a closure that leaves the dial too small scrolls; one that leaves room stays fixed.
        #expect(WatchTonightLayout.choose(room: 180, words: 120, standardSize: false, accessibilitySize: false) == .scrolling)
        #expect(WatchTonightLayout.choose(room: 180, words: 60, standardSize: false, accessibilitySize: false) == .fixed)
    }
}

private extension WatchContext {
    /// The same context with one of the new values changed.
    func stamped(tonightNight: String? = nil, spotsOff: Bool? = nil, alertsOff: Bool? = nil, smokeOff: Bool? = nil) -> WatchContext {
        WatchContext(sent: sent, savedParkIDs: savedParkIDs, homeParkID: homeParkID, nightVision: nightVision, brighterRed: brighterRed, forecasts: forecasts,
                     details: details, closures: closures, ranges: ranges, places: places, usualClouds: usualClouds, tonightParkID: tonightParkID,
                     watchParkIDs: watchParkIDs, droppedParkIDs: droppedParkIDs, dataVersion: dataVersion, sequence: sequence, aurora: aurora,
                     tonightNight: tonightNight ?? self.tonightNight, spotForecastsOff: spotsOff ?? spotForecastsOff,
                     alertsOff: alertsOff ?? self.alertsOff, smokeOff: smokeOff ?? self.smokeOff)
    }
}
