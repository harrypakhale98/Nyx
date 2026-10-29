import Foundation
import Testing
@testable import Nyx

/// Night vision's three choices on iPhone and iPad: At dusk turns red at civil dusk and back at
/// civil dawn at the starting point, a turn by hand holds until the next dusk or dawn, and where no
/// dusk comes (the midnight Sun, polar night) the switch stays as it was set.
struct NightVisionModeTests {
    let parks: [Park]
    let engine = AstronomyEngine()
    init() throws { parks = try ParkData.load() }
    private func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }
    private func local(_ park: Park, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try #require(park.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }
    /// The same change found from another starting moment: the search bisects to about a second.
    private func near(_ a: Date?, _ b: Date) -> Bool { a.map { abs($0.timeIntervalSince(b)) < 2 } ?? false }
    private func suite() throws -> UserDefaults {
        let name = "NightVisionModeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func atDuskIsOffBeforeTheNightOnThroughItAndOffAfter() throws {
        // The starting point as At dusk sees it: Joshua Tree's coordinates, nothing else.
        let jotr = try park("jotr"), place = NightVisionSchedule.place(latitude: jotr.latitude, longitude: jotr.longitude)
        let changes = WristSky.paletteChanges(at: place, from: try local(jotr, 2026, 10, 7, 12), to: try local(jotr, 2026, 10, 8, 12))
        let dusk = try #require(changes.first), dawn = try #require(changes.last)
        #expect(changes.count == 2)
        // Civil dusk: after sunset, before true darkness, the Sun 6° down.
        let sky = engine.conditions(for: jotr, on: try local(jotr, 2026, 10, 7, 12))
        let sunset = try #require(sky.sunset), dark = try #require(sky.darkStart)
        #expect(dusk > sunset && dusk < dark)
        #expect(abs(engine.solarAltitude(at: dusk, park: place) + 6) < 0.05)
        let before = NightVisionSchedule.plan(current: true, heldAt: nil, at: place, now: dusk.addingTimeInterval(-600))
        #expect(!before.on && !before.held && near(before.next, dusk))
        let during = NightVisionSchedule.plan(current: false, heldAt: nil, at: place, now: try local(jotr, 2026, 10, 8, 0))
        #expect(during.on && !during.polar && near(during.next, dawn))
        let after = NightVisionSchedule.plan(current: true, heldAt: nil, at: place, now: dawn.addingTimeInterval(600))
        #expect(!after.on && !after.polar)
        // The next look comes at the change itself: a minute either side reads differently.
        #expect(NightVisionSchedule.plan(current: false, heldAt: nil, at: place, now: dusk.addingTimeInterval(60)).on)
        #expect(!NightVisionSchedule.plan(current: false, heldAt: nil, at: place, now: dawn.addingTimeInterval(60)).on)
    }

    @Test func aTurnByHandHoldsUntilTheNextDuskOrDawn() throws {
        let jotr = try park("jotr"), place = NightVisionSchedule.place(latitude: jotr.latitude, longitude: jotr.longitude)
        let changes = WristSky.paletteChanges(at: place, from: try local(jotr, 2026, 10, 7, 12), to: try local(jotr, 2026, 10, 8, 12))
        let dusk = try #require(changes.first), dawn = try #require(changes.last)
        // Turned off at 10 PM: off through the night, until dawn.
        let turned = try local(jotr, 2026, 10, 7, 22)
        let late = NightVisionSchedule.plan(current: false, heldAt: turned, at: place, now: dawn.addingTimeInterval(-60))
        #expect(late.held && !late.on && near(late.next, dawn))
        let morning = NightVisionSchedule.plan(current: false, heldAt: turned, at: place, now: dawn.addingTimeInterval(60))
        #expect(!morning.held && !morning.on)
        // Turned on at noon: red through the afternoon; at dusk At dusk takes over (and agrees).
        let noon = try local(jotr, 2026, 10, 7, 12)
        let afternoon = NightVisionSchedule.plan(current: true, heldAt: noon, at: place, now: dusk.addingTimeInterval(-60))
        #expect(afternoon.held && afternoon.on)
        let evening = NightVisionSchedule.plan(current: true, heldAt: noon, at: place, now: dusk.addingTimeInterval(60))
        #expect(!evening.held && evening.on)
        // Turned on at noon and left: the next dawn turns it off, the hold long over.
        #expect(!NightVisionSchedule.plan(current: true, heldAt: noon, at: place, now: dawn.addingTimeInterval(60)).on)
        // A hold from the future (a clock set back) has lapsed.
        #expect(!NightVisionSchedule.plan(current: true, heldAt: noon.addingTimeInterval(3600), at: place, now: noon).held)
    }

    @Test func noDuskOrDawnLeavesTheSwitchAsItWasSet() throws {
        // Denali at the June solstice: the Sun never drops 6°, so no dusk in the day ahead.
        let dena = try park("dena"), summer = NightVisionSchedule.place(latitude: dena.latitude, longitude: dena.longitude)
        for current in [true, false] {
            let plan = NightVisionSchedule.plan(current: current, heldAt: nil, at: summer, now: try local(dena, 2026, 6, 21, 1))
            #expect(plan.polar && plan.next == nil && plan.on == current && !plan.held)
        }
        // Polar night at 80° north in December: the Sun never climbs above −6°, and no dawn comes.
        let svalbard = NightVisionSchedule.place(latitude: 80, longitude: 16)
        let midwinter = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: .gmt, year: 2026, month: 12, day: 21, hour: 12)))
        for current in [true, false] {
            let plan = NightVisionSchedule.plan(current: current, heldAt: nil, at: svalbard, now: midwinter)
            #expect(plan.polar && plan.on == current)
        }
        // A turn by hand there holds; with no dusk or dawn to end it, it simply stays.
        let held = NightVisionSchedule.plan(current: true, heldAt: midwinter.addingTimeInterval(-3600), at: summer, now: try local(dena, 2026, 6, 21, 1))
        #expect(held.polar && held.on)
    }

    @Test func theModeIsTheSwitchUnlessAtDuskIsChosen() throws {
        let defaults = try suite()
        #expect(NightVisionMode.current(defaults) == .off)
        // The key every surface, Vision Pro's own and builds already installed read: never renamed.
        #expect(NightLook.nightVisionKey == "nightVision")
        defaults.set(true, forKey: NightLook.nightVisionKey)
        #expect(NightVisionMode.current(defaults) == .on)
        // Off and On: a turn by hand needs no hold.
        NightVisionMode.turnedByHand(defaults)
        #expect(NightVisionMode.heldAt(defaults) == nil)
        defaults.set(true, forKey: NightVisionMode.atDuskKey)
        #expect(NightVisionMode.current(defaults) == .dusk)
        let now = Date(timeIntervalSince1970: 1_791_158_400)
        NightVisionMode.turnedByHand(defaults, now: now)
        #expect(NightVisionMode.heldAt(defaults) == now)
        #expect(NightVisionMode.allCases == [.off, .on, .dusk])
    }
}
