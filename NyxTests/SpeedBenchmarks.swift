import Foundation
import Testing
@testable import Nyx

/// What the screens ask of the engine, timed: a Parks keystroke, a calendar's month, a 200-night journal,
/// the bundled parks read and a park's calendar, and one night for 3,000 places (the size the global plan
/// would reach). Off by default; `TEST_RUNNER_NYX_BENCH=1` runs it. Each prints milliseconds as
/// `BENCH|name|ms`. Uses only what the app already had before its caches, so the same file times both.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["NYX_BENCH"] != nil), .serialized)
struct SpeedBenchmarks {
    private let clock=ContinuousClock()
    private func milliseconds(_ duration: Duration) -> Double { Double(duration.components.seconds)*1000+Double(duration.components.attoseconds)/1e15 }
    /// The median of `runs` timings of `work`, so one slow run under load does not decide it.
    private func time(_ name: String, runs: Int=5, _ work: () -> Void) -> Double {
        var times: [Double]=[]
        for _ in 0..<runs { times.append(milliseconds(clock.measure(work))) }
        let median=times.sorted()[times.count/2]
        print("BENCH|\(name)|\(String(format: "%.2f", median))")
        return median
    }

    /// ParksView ranks, scans and fills its rotors per keystroke: about four nights per park.
    @Test func parksKeystroke() {
        let model=PlanModel()
        _=model.parks.map { model.night($0) }  // tonight's skies once, as the list's first appearance does
        let ms=time("parks keystroke (63 parks x 4 nights)") { for park in model.parks { for _ in 0..<4 { _=model.night(park) } } }
        #expect(ms>0)
    }
    /// Plan's month pager: three pages of 35 nights at the starting park.
    @Test func calendarMonth() {
        let model=PlanModel()
        guard let park=model.park("jotr") else { Issue.record("no jotr"); return }
        let start=park.currentNight(at: .now)
        let nights=(0..<105).map { park.date(start, addingDays: $0-35) }
        _=nights.map { model.night(park, on: $0) }
        let ms=time("calendar three pages (105 nights)") { for night in nights { _=model.night(park, on: night) } }
        #expect(ms>0)
    }
    /// The Journal's constellation and recap: a score for every recorded night, again on each render.
    @Test func journal200() {
        let model=PlanModel()
        let ids=model.parks.map(\.id)
        let entries=(0..<200).map { i in JournalEntry(date: Date.now.addingTimeInterval(-Double(i)*86400*3.3), parkID: ids[i%ids.count]) }
        _=model.loggedNights(entries)
        let ms=time("journal render (200 entries)") { _=model.loggedNights(entries) }
        #expect(ms>0)
    }
    /// The bundled parks, read where a widget, an intent or a view asks for them.
    @Test func parkDataLoad() throws {
        let ms=time("parks.json read x50") { for _ in 0..<50 { _=try? ParkData.load() } }
        #expect(ms>0)
    }
    /// A park's calendar, read for every date a screen formats.
    @Test func parkCalendar() throws {
        let parks=try ParkData.load()
        let ms=time("Park.calendar x12,600") { for park in parks { for _ in 0..<200 { _=park.calendar.timeZone } } }
        #expect(ms>0)
    }
    /// One night at 3,000 places (the 63 parks' records, moved about), as a catalogue that size would ask.
    @Test func catalog3000() throws {
        let url=try #require(Bundle.main.url(forResource: "parks", withExtension: "json"))
        let base=try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        var records: [[String: Any]]=[]
        for i in 0..<3000 {
            var record=base[i%base.count]
            record["id"]="syn\(i)"
            if let latitude=record["latitude"] as? Double { record["latitude"]=max(-60, min(70, latitude+Double(i%17)*0.3-2.4)) }
            if let longitude=record["longitude"] as? Double { record["longitude"]=longitude+Double(i%23)*0.4-4.4 }
            records.append(record)
        }
        let places=try JSONDecoder().decode([Park].self, from: JSONSerialization.data(withJSONObject: records))
        let engine=AstronomyEngine(), now=Date.now
        let ms=time("3,000 places, one night each", runs: 3) {
            for place in places { _=NightPlanner.night(park: place, sky: engine.conditions(for: place, on: place.currentNight(at: now)), forecast: nil, detail: nil, now: now) }
        }
        #expect(ms>0)
    }
}
