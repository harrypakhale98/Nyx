import Foundation
import Testing
@testable import Nyx

/// The iPhone → watch context and the night milestones the watch counts down to.
struct WatchTests {
    func park(_ id: String) throws -> Park { try #require(try ParkData.load().first { $0.id == id }) }
    private let t0 = 1_791_158_400.0 // 2026-10-05 00:00 UTC
    private func forecast(hours: Int, updated: Date, gapAt gap: Int? = nil) -> Forecast {
        let times = (0..<hours).map { t0 + Double($0)*3600 + ($0 == gap ? 1800 : 0) }
        return Forecast(updated: updated, times: times, clouds: (0..<hours).map { $0 % 7 == 3 ? nil : Double(($0*13) % 101) })
    }

    @Test func contextRoundTripsThroughWatchConnectivityShape() throws {
        let now = Date(timeIntervalSince1970: t0 + 30*3600)
        let full = forecast(hours: 17*24, updated: now.addingTimeInterval(-3600))
        let context = WatchContext.make(savedParkIDs: ["jotr", "deva"], homeParkID: "grba", nightVision: true, forecasts: ["jotr": full, "grba": full, "yell": full], now: now)
        // Only saved parks and the starting park travel; the rest stay on the iPhone.
        #expect(Set(context.forecasts.keys) == ["jotr", "grba"])
        let decoded = try #require(WatchContext(dictionary: context.dictionary))
        #expect(decoded == context)
        #expect(decoded.nightVision && decoded.homeParkID == "grba" && decoded.savedParkIDs == ["jotr", "deva"])
        // The rebuilt forecast gives the same cloud mean as the iPhone's for any window it kept.
        let rebuilt = try #require(decoded.cloudForecasts["jotr"])
        // A window between the fixture's missing hours (a window touching one has no mean, by design).
        let start = now.addingTimeInterval(9*3600+600), end = now.addingTimeInterval(14*3600+1200)
        let phone = try #require(full.mean(from: start, to: end, now: now))
        #expect(rebuilt.mean(from: start, to: end, now: now) == phone)
        #expect(rebuilt.updated == full.updated)
        // Missing hours travel as missing, never as a value.
        #expect(rebuilt.clouds.contains { $0 == nil })
        #expect(rebuilt.mean(from: now.addingTimeInterval(8*3600), to: now.addingTimeInterval(9*3600), now: now) == nil)
        // Trimmed to last night through nine days ahead.
        #expect(rebuilt.times.first ?? 0 >= now.timeIntervalSince1970 - 25*3600)
        #expect(rebuilt.times.last ?? .infinity <= now.timeIntervalSince1970 + 9*86400)
    }

    @Test func contextRejectsGapsOtherVersionsAndOversizedPayloads() throws {
        let now = Date(timeIntervalSince1970: t0 + 30*3600)
        // A series with a gap would invent times when compacted: that park travels without clouds.
        let gappy = forecast(hours: 200, updated: now, gapAt: 50)
        #expect(CompactForecast(gappy, from: now.addingTimeInterval(-86400), to: now.addingTimeInterval(86400)) == nil)
        #expect(WatchContext.make(savedParkIDs: ["jotr"], homeParkID: "jotr", nightVision: false, forecasts: ["jotr": gappy], now: now).forecasts.isEmpty)
        // Unknown versions and junk are ignored, never misread.
        let encoded = try #require(WatchContext.make(savedParkIDs: [], homeParkID: "jotr", nightVision: false, forecasts: [:], now: now).data)
        var json = try #require(String(data: encoded, encoding: .utf8))
        json = json.replacingOccurrences(of: "\"version\":1", with: "\"version\":99")
        #expect(WatchContext(data: Data(json.utf8)) == nil)
        #expect(WatchContext(dictionary: [WatchContext.key: Data("{}".utf8)]) == nil)
        #expect(WatchContext(dictionary: ["other": 1]) == nil)
        // Every park saved: the context stays under WatchConnectivity's limit, saved order first.
        let ids = try ParkData.load().map(\.id)
        let full = forecast(hours: 17*24, updated: now)
        let all = WatchContext.make(savedParkIDs: ids, homeParkID: "jotr", nightVision: false, forecasts: Dictionary(uniqueKeysWithValues: ids.map { ($0, full) }), now: now)
        #expect((all.data?.count ?? .max) <= WatchContext.byteBudget)
        #expect(all.forecasts[ids[0]] != nil)
        #expect(all.savedParkIDs == ids)
    }

    @Test func milestonesAreOrderedAndInsideTheNight() throws {
        let engine = AstronomyEngine()
        for id in ["jotr", "acad", "npsa", "dena", "gaar"] {
            let park = try park(id)
            for month in [1, 3, 6, 9, 12] {
                let date = try #require(park.calendar.date(from: DateComponents(year: 2026, month: month, day: 15, hour: 12)))
                let sky = engine.conditions(for: park, on: date)
                let list = NightMilestone.list(for: sky)
                #expect(zip(list, list.dropFirst()).allSatisfy { $0.date <= $1.date }, "\(id) \(month)")
                #expect(Set(list.map(\.kind)).count == list.count)
                let from = sky.sunset ?? sky.evening, to = sky.sunrise ?? sky.end
                #expect(list.allSatisfy { $0.date >= from && $0.date <= to }, "\(id) \(month)")
                if let dusk = list.firstIndex(where: { $0.kind == .darkStart }), let dawn = list.firstIndex(where: { $0.kind == .darkEnd }) { #expect(dusk < dawn) }
                // The next milestone is always the first one still ahead.
                if let first = list.first {
                    #expect(NightMilestone.next(after: first.date.addingTimeInterval(-1), in: sky) == first)
                    #expect(NightMilestone.next(after: first.date, in: sky) == list.dropFirst().first)
                }
            }
        }
    }

    @Test func polarNightsHaveNoInventedEdges() throws {
        let engine = AstronomyEngine()
        // Denali in June: no true darkness, so no dusk or dawn milestone and the night is twilight at most.
        let denali = try park("dena")
        let june = try #require(denali.calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12)))
        let summer = engine.conditions(for: denali, on: june)
        #expect(!NightMilestone.list(for: summer).contains { $0.kind == .darkStart || $0.kind == .darkEnd })
        #expect(summer.phase(at: summer.evening.addingTimeInterval(13*3600)) != .dark)
        // Gates of the Arctic in December: the Sun never rises, so only true darkness has edges, inside the night.
        let gates = try park("gaar")
        let december = try #require(gates.calendar.date(from: DateComponents(year: 2026, month: 12, day: 21, hour: 12)))
        let winter = engine.conditions(for: gates, on: december)
        let list = NightMilestone.list(for: winter)
        #expect(!list.contains { $0.kind == .sunset || $0.kind == .sunrise })
        #expect(list.allSatisfy { $0.date > winter.evening && $0.date < winter.end })
        // Joshua Tree in October: an ordinary night reads day → twilight → dark → twilight.
        let tree = try park("jotr")
        let october = try #require(tree.calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12)))
        let night = engine.conditions(for: tree, on: october)
        let sunset = try #require(night.sunset), dark = try #require(night.darkStart), dawn = try #require(night.darkEnd)
        #expect(night.phase(at: sunset.addingTimeInterval(-60)) == .day)
        #expect(night.phase(at: sunset.addingTimeInterval(60)) == .twilight)
        #expect(night.phase(at: dark.addingTimeInterval(60)) == .dark)
        #expect(night.phase(at: dawn.addingTimeInterval(60)) == .twilight)
    }

    @Test func nightVisionRedKeepsTextReadableOnBlack() {
        // WCAG AA for body text: 4.5:1, for every red text level the watch uses.
        for level in NightRed.levels { #expect(NightRed.contrastOnBlack(opacity: level) >= 4.5, "\(level)") }
        #expect(NightRed.contrastOnBlack(opacity: 1) > 6)
    }
}
