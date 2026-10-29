import Foundation
import Testing
@testable import Nyx

/// At dusk on the wrist turns at the iPhone's moment: the iPhone reads its starting point to a tenth
/// of a degree and hands the watch that same point (`WatchContext.dusk`, never the device's location),
/// and the watch app and every complication read the Sun there (`PaletteChoice.nightVision`'s `dusk`),
/// whatever park the wrist's Tonight shows.
struct DuskHandOverTests {
    let parks: [Park]
    init() throws { parks = try ParkData.load() }
    private func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }
    private func local(_ park: Park, _ year: Int, _ month: Int, _ day: Int, _ hour: Int) throws -> Date {
        try #require(park.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }
    /// Los Angeles, as a chosen town is stored, before any rounding.
    private let losAngeles = (latitude: 34.0522, longitude: -118.2437)
    /// What the watch holds after the trip: encoded, sent, decoded.
    private func received(_ context: WatchContext) throws -> WatchContext { try #require(WatchContext(data: try JSONEncoder().encode(context))) }
    private func context(dusk: [Double]?, nightVision: Bool = false) -> WatchContext {
        WatchContext.make(savedParkIDs: ["acad"], homeParkID: "jotr", nightVision: nightVision, forecasts: [:], dusk: dusk)
    }

    /// The point survives the trip whole, rounded to a tenth of a degree.
    @Test func theStartingPointTravelsRounded() throws {
        let point = try #require(NightVisionSchedule.startingPoint(latitude: losAngeles.latitude, longitude: losAngeles.longitude))
        #expect(point == [34.1, -118.2])
        let sent = context(dusk: point)
        #expect(sent.dusk == point)
        let watch = try received(sent)
        #expect(watch.dusk == point)
        #expect(watch.duskPlace?.latitude == 34.1)
        // An older iPhone sends none: the wrist follows the park on Tonight, as before.
        #expect(try received(context(dusk: nil)).duskPlace == nil)
    }

    @Test(arguments: [[91, 0], [.nan, 0], [0, .infinity], [0, 181], [1], [1, 2, 3], []] as [[Double]])
    func nonsenseIsNoPlace(_ point: [Double]) {
        #expect(WatchContext.duskPoint(point) == nil)
        #expect(context(dusk: point).dusk == nil)
    }

    /// A hand-over whose point is garbled still arrives, without a place: `duskPlace` never indexes
    /// past what came.
    @Test(arguments: ["[1]", "[91, 0]", "[0, 181]", "[1, 2, 3]", "\"nowhere\"", "null"])
    func aGarbledPointArrivesAsNone(_ dusk: String) throws {
        let data = try JSONEncoder().encode(context(dusk: [34.1, -118.2]))
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["dusk"] = try JSONSerialization.jsonObject(with: Data(dusk.utf8), options: .fragmentsAllowed)
        let watch = try #require(WatchContext(data: try JSONSerialization.data(withJSONObject: json)))
        #expect(watch.dusk == nil && watch.duskPlace == nil)
    }

    /// The scenario that drifted: planning from Los Angeles with Acadia on the wrist. The iPhone's
    /// At dusk (from the town as stored) and the wrist's (from what it received, through the rule the
    /// watch app and complications share) turn red and back at the same moment, not at Acadia's dusk
    /// three hours earlier.
    @Test func wristAndPhoneTurnTogether() throws {
        let acadia = try park("acad"), jotr = try park("jotr")
        let point = try #require(NightVisionSchedule.startingPoint(latitude: losAngeles.latitude, longitude: losAngeles.longitude))
        let phonePlace = NightVisionSchedule.place(latitude: point[0], longitude: point[1])
        let watch = try received(context(dusk: point))
        let wristPlace = try #require(watch.duskPlace)
        func phone(_ now: Date) -> Bool { NightVisionSchedule.plan(current: false, heldAt: nil, at: phonePlace, now: now).on }
        func wrist(_ now: Date) -> Bool { PaletteChoice.automatic.nightVision(phone: watch.nightVision, park: acadia, dusk: watch.duskPlace, at: now) }

        let noon = try local(jotr, 2026, 10, 26, 12), day = noon.addingTimeInterval(86400)
        let phoneChanges = WristSky.paletteChanges(at: phonePlace, from: noon, to: day)
        let wristChanges = WristSky.paletteChanges(at: wristPlace, from: noon, to: day)
        #expect(phoneChanges.count == 2 && wristChanges.count == 2)
        for (a, b) in zip(phoneChanges, wristChanges) { #expect(abs(a.timeIntervalSince(b)) < 2) }
        // Dusk and dawn alike: either side of each turn, and at noon and midnight, the two agree.
        let moments = [noon, noon.addingTimeInterval(12*3600)] + phoneChanges.flatMap { [$0.addingTimeInterval(-60), $0.addingTimeInterval(60)] }
        for now in moments { #expect(wrist(now) == phone(now), "\(now)") }

        // The comparison can tell: the town unrounded turns about ten seconds away from the point sent.
        let raw = NightVisionSchedule.place(latitude: losAngeles.latitude, longitude: losAngeles.longitude)
        let rawDusk = try #require(WristSky.paletteChanges(at: raw, from: noon, to: day).first)
        #expect(abs(rawDusk.timeIntervalSince(try #require(phoneChanges.first))) > 2)
        // An hour after Acadia's dusk the wrist is still in standard colours, as the phone is; an
        // older iPhone (no point sent) leaves the wrist on Acadia's Sun, red by then.
        let acadiaDusk = try #require(WristSky.paletteChanges(at: acadia, from: noon, to: day).first)
        let after = acadiaDusk.addingTimeInterval(3600)
        #expect(try #require(phoneChanges.first).timeIntervalSince(acadiaDusk) > 2*3600)
        #expect(!wrist(after) && !phone(after))
        #expect(PaletteChoice.automatic.nightVision(phone: false, park: acadia, dusk: try received(context(dusk: nil)).duskPlace, at: after))
    }

    /// No dusk or dawn within a day at the starting point (Denali in June, polar night at 80° north):
    /// the iPhone keeps its switch as set, and the wrist wears that switch rather than the Sun's answer.
    @Test func withNoDuskOrDawnTheWristKeepsThePhonesSwitch() throws {
        let dena = try park("dena")
        let midwinter = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: .gmt, year: 2026, month: 12, day: 21, hour: 12)))
        let cases = [([dena.latitude, dena.longitude], try local(dena, 2026, 6, 21, 1)), ([80, 16], midwinter)]
        for (point, now) in cases {
            for switchOn in [true, false] {
                let watch = try received(context(dusk: point, nightVision: switchOn))
                let place = try #require(watch.duskPlace)
                #expect(WristSky.isPolar(at: place, now))
                let phone = NightVisionSchedule.plan(current: switchOn, heldAt: nil, at: place, now: now).on
                #expect(phone == switchOn)
                #expect(PaletteChoice.automatic.nightVision(phone: watch.nightVision, park: dena, dusk: place, at: now) == phone, "\(point) \(switchOn)")
            }
        }
        // Below 60° a dusk or dawn comes every day of the year, so `isPolar` never searches there.
        let year = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: .gmt, year: 2026, month: 1, day: 1)))
        for latitude in stride(from: -60.0, through: 60, by: 30) {
            for month in 0..<12 {
                let start = year.addingTimeInterval(Double(month)*30.4*86400)
                #expect(!WristSky.paletteChanges(at: WristSky.place(latitude: latitude, longitude: 0), from: start, to: start.addingTimeInterval(WristSky.dayAhead)).isEmpty, "\(latitude) \(month)")
            }
        }
    }
}
