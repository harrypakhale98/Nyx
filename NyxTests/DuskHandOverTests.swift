import Foundation
import Testing
@testable import Nyx

/// At dusk on the wrist turns at the iPhone's minute: the iPhone hands over its starting point
/// (`WatchContext.dusk`, a tenth of a degree, never the device's location) and the watch app and
/// every complication read the Sun there, whatever park the wrist's Tonight shows.
struct DuskHandOverTests {
    let parks: [Park]
    init() throws { parks = try ParkData.load() }
    private func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }

    /// The point survives the trip whole, rounded to a tenth of a degree; nonsense is dropped.
    @Test func theStartingPointTravelsRoundedAndSurvivesDecoding() throws {
        let sent = WatchContext.make(savedParkIDs: ["acad"], homeParkID: "jotr", nightVision: false, forecasts: [:], dusk: [34.0522, -118.2437])
        #expect(sent.dusk == [34.1, -118.2])
        let data = try JSONEncoder().encode(sent)
        let received = try #require(WatchContext(data: data))
        #expect(received.dusk == [34.1, -118.2])
        #expect(received.duskPlace?.latitude == 34.1)
        #expect(WatchContext.duskPoint([91, 0]) == nil && WatchContext.duskPoint([.nan, 0]) == nil && WatchContext.duskPoint([1]) == nil)
        // An older iPhone sends none: the wrist follows the park on Tonight, as before.
        #expect(WatchContext.make(savedParkIDs: [], homeParkID: "jotr", nightVision: false, forecasts: [:]).duskPlace == nil)
    }

    /// The scenario that drifted: planning from Los Angeles with Acadia on the wrist. At every five
    /// minutes of an evening the wrist's At dusk (`PaletteChoice.automatic` at `duskPlace`, which
    /// `WatchStore` and `WristLook` pass ahead of the park on Tonight) agrees with the iPhone's, and
    /// the wrist's dusk is the iPhone's, not Acadia's three hours earlier.
    @Test func wristAndPhoneTurnAtTheSameMinute() throws {
        let acadia = try park("acad"), jotr = try park("jotr")
        let context = WatchContext.make(savedParkIDs: ["acad"], homeParkID: "jotr", nightVision: false, forecasts: [:], dusk: [34.0522, -118.2437])
        let point = try #require(context.dusk)
        let phonePlace = NightVisionSchedule.place(latitude: point[0], longitude: point[1])
        let wristPlace = context.duskPlace ?? acadia
        let noon = try #require(jotr.calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 12)))
        for minute in stride(from: 0, to: 18*60, by: 5) {
            let now = noon.addingTimeInterval(Double(minute)*60)
            let phone = NightVisionSchedule.plan(current: false, heldAt: nil, at: phonePlace, now: now).on
            #expect(PaletteChoice.automatic.nightVision(phone: nil, park: wristPlace, at: now) == phone, "\(now)")
        }
        let day = noon.addingTimeInterval(86400)
        let phoneDusk = try #require(WristSky.paletteChanges(at: phonePlace, from: noon, to: day).first)
        let wristDusk = try #require(WristSky.paletteChanges(at: wristPlace, from: noon, to: day).first)
        let acadiaDusk = try #require(WristSky.paletteChanges(at: acadia, from: noon, to: day).first)
        #expect(abs(wristDusk.timeIntervalSince(phoneDusk)) < 2)
        #expect(phoneDusk.timeIntervalSince(acadiaDusk) > 2*3600)
    }
}
