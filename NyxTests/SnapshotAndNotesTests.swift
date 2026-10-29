import Foundation
import Synchronization
import Testing
@testable import Nyx

/// The widgets' snapshot read once per change and written off the main actor in order; field mode's
/// Lock Screen score as old as its forecast; the trip planner's note in its rows' words; and the
/// iPhone's score breakdown saying when smoke is not counted, in Vision Pro's words.
@MainActor @Suite struct SnapshotAndNotesTests {
    let parks: [Park] = (try? ParkData.load()) ?? []
    func model() -> PlanModel {
        PlanModel(weather: WeatherService(transport: StubHTTP([:]), persist: false), parkStore: ParkStore(transport: StubHTTP([:]), persist: false),
                  detail: ForecastDetailService(transport: StubHTTP([:]), persist: false), defaults: isolatedDefaults())
    }
    /// A snapshot file of the test's own, never the App Group's.
    func file() -> SnapshotFile {
        SnapshotFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("saved-sky-\(UUID().uuidString).json"))
    }
    func snapshot(_ ids: [String]) throws -> SavedSkySnapshot { SavedSkySnapshot(parks: try ids.map(park), forecasts: [:]) }

    // MARK: Field mode's score is as old as its forecast

    /// Field mode opened on a forecast issued 30 hours before the night's dusk: the Live Activity
    /// carries that time, so the Lock Screen says "as of …" as a followed night does, not a
    /// fresh-looking score. An old score is judged against dusk (`scoreAgeLimit`), so the forecast is
    /// issued relative to the night's dusk and the clock is pinned, at every hour of the park's day:
    /// before sunrise "tonight" is the night that began the evening before, and a forecast issued
    /// 30 hours ago was then only 17 hours old at its dusk.
    @Test(arguments: [0, 3, 6, 7, 9, 12, 15, 18, 20, 23])
    func fieldActivityCarriesTheForecastsAge(hour: Int) throws {
        let model = model(), jotr = try park("jotr")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jotr.timeZone
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: hour, minute: 48)))
        model.pinClock(now); model.presentOverride = now
        let dusk = try #require(model.night(jotr).sky.sunset)
        let issued = dusk.addingTimeInterval(-30*3600)
        let hours = (0..<(16*24)).map { (floor(issued.timeIntervalSince1970/3600)-24+Double($0))*3600 }
        model.forecasts[jotr.id] = Forecast(updated: issued, times: hours, clouds: hours.map { _ in 5 })
        let tonight = model.night(jotr)
        try #require(tonight.forecastUpdated == issued)
        let session = FieldSession(park: jotr, model: model, changesPhone: false)
        #expect(session.scoredAt == issued && session.scoredAt == FieldActivities.scoredAt(tonight, now: now))
        let scored = FieldActivities.fieldScored(session.score, closure: session.closure, at: session.scoredAt)
        #expect(scored.at == issued && scored.score == tonight.score.value)
        let attributes = FieldActivityAttributes(night: session.night, score: scored.score, band: scored.band)
        let state = attributes.content(at: now, nightVision: true, scored: scored).state
        #expect(attributes.scoreDay(state) == issued && attributes.scoreLine(state).contains("as of"))
        // A night no forecast reaches does not age: it is scored as of now.
        let fresh = FieldSession(park: try park("deva"), model: model, changesPhone: false)
        #expect(abs(fresh.scoredAt.timeIntervalSinceNow) < 60)
    }

    // MARK: One decoded snapshot per process

    /// Reads share one decode until the file changes; a write, or another process's write, is read again.
    @Test func snapshotReadIsDecodedOncePerChange() throws {
        let file = file()
        #expect(file.read() == nil && file.decodes == 0)
        #expect(file.write(try snapshot(["jotr"])))
        let first = try #require(file.read())
        for _ in 0..<5 { #expect(file.read()?.parks.map(\.id) == ["jotr"]) }
        #expect(first.parks.map(\.id) == ["jotr"] && file.decodes == 1)
        // The same contents again: nothing written, the kept copy stands.
        #expect(!file.write(try snapshot(["jotr"])))
        _ = file.read()
        #expect(file.decodes == 1)
        // A new snapshot is read anew, once.
        #expect(file.write(try snapshot(["jotr", "deva"])))
        #expect(file.read()?.parks.map(\.id) == ["jotr", "deva"] && file.read() != nil && file.decodes == 2)
        // Written by another process (the watch, an older build): its bytes differ, so it is decoded again.
        let url = try #require(file.url)
        try JSONEncoder().encode(try snapshot(["arch"])).write(to: url, options: .atomic)
        #expect(file.read()?.parks.map(\.id) == ["arch"] && file.decodes == 3)
        try FileManager.default.removeItem(at: url)
        #expect(file.read() == nil)
    }
    /// Widget providers read at once on a reload: they wait for one decode and share it.
    @Test func concurrentReadsShareOneDecode() async throws {
        let file = file()
        #expect(file.write(try snapshot(["jotr", "deva", "arch"])))
        let readers = (0..<8).map { _ in Task.detached { file.read()?.parks.count ?? 0 } }
        var counts: [Int] = []
        for reader in readers { counts.append(await reader.value) }
        #expect(counts == Array(repeating: 3, count: 8) && file.decodes == 1)
    }
    /// `SharedSettings.read` and `load` read the bound file (the App Group's in the app and widgets).
    @Test func sharedSettingsReadsTheBoundFile() async throws {
        let file = file()
        #expect(file.write(try snapshot(["deva"])))
        let read = SharedSettings.$snapshotFile.withValue(file) { SharedSettings.read() }
        let loaded = await SharedSettings.$snapshotFile.withValue(file) { await SharedSettings.load() }
        #expect(read?.parks.map(\.id) == ["deva"] && loaded?.parks.map(\.id) == ["deva"] && file.decodes == 1)
    }
    /// The Moon widget's placeholder is drawn from the bundled parks, never from the snapshot.
    @Test func moonPlaceholderNeverReadsTheSnapshot() throws {
        let file = file()
        #expect(file.write(try snapshot(["deva"])))
        let entry = SharedSettings.$snapshotFile.withValue(file) { MoonEntry.placeholder() }
        #expect(entry.park?.id == Park.defaultID && file.decodes == 0)
    }

    // MARK: Written off the main actor, in order

    /// Each write waits for the one asked before it, however slow, and none runs on the main thread.
    @Test func snapshotWritesRunOffTheMainActorInOrder() async throws {
        let order = Mutex<[[String]]>([]), onMain = Mutex<[Bool]>([])
        let writer = SnapshotWriter { snapshot in
            onMain.withLock { $0.append(Thread.isMainThread) }
            // The first is the slow one: a later write must not overtake it.
            if snapshot.parks.count == 1 { Thread.sleep(forTimeInterval: 0.2) }
            order.withLock { $0.append(snapshot.parks.map(\.id)) }
            return true
        }
        let first = writer.enqueue(try snapshot(["jotr"])), second = writer.enqueue(try snapshot(["jotr", "deva"]))
        let third = await writer.write(try snapshot(["jotr", "deva", "arch"]))
        let wrote = (await first.value, await second.value, third)
        #expect(wrote == (true, true, true))
        #expect(order.withLock { $0 } == [["jotr"], ["jotr", "deva"], ["jotr", "deva", "arch"]])
        #expect(onMain.withLock { $0 } == [false, false, false])
        // On disk: the last snapshot asked for stands, and an unchanged one reports no change (no widget reload).
        let file = file(), disk = SnapshotWriter(file: file)
        let a = disk.enqueue(try snapshot(["jotr"])), b = disk.enqueue(try snapshot(["deva"]))
        _ = (await a.value, await b.value)
        #expect(file.read()?.parks.map(\.id) == ["deva"])
        let again = await disk.write(try snapshot(["deva"]))
        #expect(!again)
    }

    // MARK: The trip planner's note

    func night(_ park: Park, daysAhead: Int = 0, forecast: Forecast? = nil, climate: CloudClimate = .shared, now: Date) -> Night {
        let sky = AstronomyEngine().conditions(for: park, on: park.date(park.currentNight(at: now), addingDays: daysAhead))
        return NightPlanner.night(park: park, sky: sky, forecast: forecast, detail: nil, now: now, climate: climate)
    }
    /// The note names exactly the marks the plan's rows show, and what those nights count.
    @Test func tripNoteSaysWhatItsNightsShow() throws {
        let jotr = try park("jotr"), now = Date(timeIntervalSince1970: 1_792_180_800)
        let hours = (0..<(17*24)).map { (floor(now.timeIntervalSince1970/3600)-24+Double($0))*3600 }
        let forecast = Forecast(updated: now, times: hours, clouds: hours.map { _ in 10 })
        let full = night(jotr, forecast: forecast, now: now), early = night(jotr, daysAhead: 6, forecast: forecast, now: now)
        let unavailable = night(jotr, now: now), notYet = night(jotr, daysAhead: 12, now: now), bare = night(jotr, climate: CloudClimate(parks: [:]), now: now)
        try #require(full.basis == .forecast && early.basis.isEarlyLook && !unavailable.beyondForecast && notYet.beyondForecast && bare.usualCloud == nil)
        #expect(UsualCloudsNote.trip([full]) == nil)
        #expect(UsualCloudsNote.trip([full, early]) == "Nights marked \"Early look\" ease the forecast toward each park's usual clouds for the month.")
        #expect(UsualCloudsNote.trip([unavailable]) == "Nights marked \"Cloud forecast unavailable\" count each park's usual clouds for the month.")
        #expect(UsualCloudsNote.trip([notYet]) == "Nights marked \"No cloud forecast yet\" count each park's usual clouds for the month.")
        #expect(UsualCloudsNote.trip([bare]) == "Nights marked \"Cloud forecast unavailable\" count the Moon and darkness only.")
        #expect(UsualCloudsNote.trip([unavailable, notYet, bare, early, full])
                == "Nights marked \"No cloud forecast yet\" or \"Cloud forecast unavailable\" count each park's usual clouds for the month, or the Moon and darkness only where those are not known. Nights marked \"Early look\" ease the forecast toward each park's usual clouds for the month.")
        // A stay led by a forecast night whose other nights lean on the usual clouds: no mark named, the lean said.
        let lean = "In a stay of several nights, nights the forecast does not fully reach lean on each park's usual clouds for the month."
        #expect(UsualCloudsNote.trip([full], unmarked: [early]) == lean)
        #expect(UsualCloudsNote.trip([full], unmarked: [notYet]) == lean)
        #expect(UsualCloudsNote.trip([full], unmarked: [full]) == nil)
        // A night with no usual clouds counts the Moon and darkness only: it leans on no usual clouds.
        #expect(UsualCloudsNote.trip([full], unmarked: [bare]) == nil)
        // Each mark a row shows is named in the note.
        for nights in [[unavailable], [notYet], [early], [unavailable, notYet, early]] {
            let note = try #require(UsualCloudsNote.trip(nights))
            for label in nights.compactMap(\.basisLabel) { #expect(note.contains("\"\(label)\"")) }
        }
    }

    /// A stay's row shows its leading night's mark only: an early look later in a stay led by a full
    /// forecast is not named under the plan; another stay's own mark is.
    @Test func tripNoteNamesOnlyTheRowsMarks() throws {
        let jotr = try park("jotr"), deva = try park("deva"), now = Date(timeIntervalSince1970: 1_792_180_800)
        let hours = (0..<(17*24)).map { (floor(now.timeIntervalSince1970/3600)-24+Double($0))*3600 }
        let forecast = Forecast(updated: now, times: hours, clouds: hours.map { _ in 10 })
        let day = TripDay(jotr.currentNight(at: now))
        var lead = TripStop(day: day, night: night(jotr, daysAhead: 1, forecast: forecast, now: now), closure: nil, hopMeters: nil)
        lead.isBest = true
        let early = TripStop(day: day.adding(1), night: night(jotr, daysAhead: 6, forecast: forecast, now: now), closure: nil, hopMeters: nil)
        try #require(lead.night.basis == .forecast)
        try #require(early.night.basis.isEarlyLook)
        let stay = TripStay.marked([lead, early])
        #expect(stay.map(\.id) == [lead.night.id])
        let away = TripStop(day: day.adding(2), night: night(deva, daysAhead: 12, now: now), closure: nil, hopMeters: nil)
        let both = TripStay.marked([lead, early, away])
        #expect(both.map(\.id) == [lead.night.id, away.night.id])
        #expect(UsualCloudsNote.trip(stay) == nil && UsualCloudsNote.trip([lead.night, early.night]) != nil)
        #expect(UsualCloudsNote.trip(both)?.contains("\"No cloud forecast yet\"") == true)
    }

    // MARK: Smoke not counted, on the iPhone

    /// A smoke forecast cached a week ago ends before tonight: the breakdown says smoke is not
    /// counted, in Vision Pro's words; switched off, or none here yet, it says that instead.
    @Test func breakdownSaysWhenSmokeIsNotCounted() throws {
        let model = model(), jotr = try park("jotr"), now = Date.now
        let reach = String(localized: "No smoke forecast on this device reaches this night, so smoke is not counted.")
        #expect(model.smokeNote(model.night(jotr)) == String(localized: "No smoke forecast on this device yet, so smoke is not counted."))
        let first = (floor(now.timeIntervalSince1970/3600)-8*24)*3600
        let old = (0..<(5*24)).map { first+Double($0)*3600 }
        model.details[jotr.id] = ForecastDetail(air: HourlySeries(updated: now.addingTimeInterval(-8*86400), times: old, values: ["aerosol_optical_depth": old.map { _ in 0.6 }]))
        let tonight = model.night(jotr)
        #expect(tonight.aerosol == nil && model.smokeNote(tonight) == reach)
        #expect(model.smokeNote(tonight) == ScoreInputs(smokeKnown: [jotr.id]).smokeNote(jotr, night: tonight))
        // A forecast that covers the night counts, and nothing is said.
        let hours = (0..<(5*24)).map { (floor(now.timeIntervalSince1970/3600)-24+Double($0))*3600 }
        model.details[jotr.id] = ForecastDetail(air: HourlySeries(updated: now, times: hours, values: ["aerosol_optical_depth": hours.map { _ in 0.05 }]))
        let counted = model.night(jotr)
        #expect(counted.aerosol != nil && model.smokeNote(counted) == nil)
        // Past the smoke forecast's few days, the same park's later night says so.
        #expect(model.smokeNote(model.night(jotr, on: jotr.date(model.tonight(jotr), addingDays: 8))) == reach)
        model.smokeEnabled = false
        #expect(model.smokeNote(model.night(jotr)) == String(localized: "Smoke and haze are off in Your privacy, so smoke is not counted."))
    }
}
