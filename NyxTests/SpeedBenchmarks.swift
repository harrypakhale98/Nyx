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
    /// The widgets' snapshot with all 63 parks' forecasts, read as a reload reads it: five readers
    /// (Tonight, Lock Screen, Moon, the control, Siri's park list). Before: each decoded its own copy
    /// and held it while it built its timeline. After: one decode per change of the file, shared.
    /// Memory is the process footprint while the five copies are held, over the footprint before.
    @Test func snapshotReads() throws {
        let sky=SameSkyTests(), model=PlanModel(), reference=Date.now
        let forecasts=Dictionary(uniqueKeysWithValues: model.parks.enumerated().map { ($1.id, sky.forecast($0+1, at: reference)) })
        let details=Dictionary(uniqueKeysWithValues: model.parks.enumerated().map { ($1.id, sky.detail($0+1, at: reference)) })
        let saved=model.parks.filter { ["jotr", "deva", "chis"].contains($0.id) }
        let written=SavedSkySync.snapshot(parks: saved, followed: saved, bundled: model.parks, forecasts: forecasts, details: details, closures: [:])
        let file=SnapshotFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("bench-\(UUID().uuidString).json"))
        #expect(file.write(written))
        let url=try #require(file.url)
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes=(try? Data(contentsOf: url).count) ?? 0
        print("BENCH|snapshot bytes|\(bytes)")
        let uncached=time("snapshot read x5, each decoding (before)") { for _ in 0..<5 { _=try? JSONDecoder().decode(SavedSkySnapshot.self, from: Data(contentsOf: url)) } }
        _=file.read()
        let cached=time("snapshot read x5, one decode kept (after)") { for _ in 0..<5 { _=file.read() } }
        // A fresh file object (a fresh extension process): one decode, shared by the five readers.
        let fresh=SnapshotFile(url: url), sharedBase=Self.footprint()
        let shared=(0..<5).compactMap { _ in fresh.read() }
        let after=Self.footprint()-sharedBase
        let heldBase=Self.footprint()
        let held=(0..<5).compactMap { _ in try? JSONDecoder().decode(SavedSkySnapshot.self, from: Data(contentsOf: url)) }
        let before=Self.footprint()-heldBase
        print("BENCH|snapshot 5 copies held (before) MB|\(String(format: "%.2f", Double(max(0, before))/1_048_576))")
        print("BENCH|snapshot one shared copy (after) MB|\(String(format: "%.2f", Double(max(0, after))/1_048_576))")
        #expect(shared.count == 5 && held.count == 5 && cached<uncached && file.decodes == 1 && fresh.decodes == 1)
    }
    /// The process's physical footprint (what iOS holds an extension to), in bytes.
    nonisolated static func footprint() -> Int {
        var info=task_vm_info_data_t()
        var count=mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size/MemoryLayout<integer_t>.size)
        let result=withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
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
