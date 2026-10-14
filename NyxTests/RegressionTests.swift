import Foundation
import ImageIO
import SwiftData
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Nyx

/// Regressions in the engine and security fixes: real journal exports import, the photos read
/// only as the merge reaches them, a failed import leaves the store as it was, Ask Nyx's closure
/// guard reads only what is said about a closed place, a failed request is never sent again once
/// per waiter, closures reach the wrist first, and a republish asked for during a run always runs.
@MainActor struct RegressionTests {
    // MARK: Helpers

    private static func jpeg(_ color: UIColor) throws -> Data {
        let format=UIGraphicsImageRendererFormat(); format.scale=1
        return try #require(UIGraphicsImageRenderer(size: CGSize(width: 24, height: 16), format: format).image { context in
            color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
        }.jpegData(compressionQuality: 0.8))
    }
    private static func entry(_ notes: String, photos: [String]=[], offset: Double=0) -> JournalArchive.Entry {
        JournalArchive.Entry(id: UUID(), date: Date(timeIntervalSince1970: 1_790_899_200+offset), parkID: "jotr", observedBortle: 2, notes: notes,
                             photos: photos.map { JournalArchive.Photo(file: $0, altText: nil) })
    }
    private static func container() throws -> ModelContainer {
        let schema=Schema(versionedSchema: NyxSchemaV2.self)
        return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }
    private static func package(_ manifest: JournalArchive.Manifest) throws -> URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("nyx-review-\(UUID().uuidString).nyxjournal", isDirectory: true)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Photos", isDirectory: true), withIntermediateDirectories: true)
        let encoder=JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: url.appendingPathComponent("entries.json"))
        return url
    }
    /// A file of `size` bytes that takes no room (APFS keeps it sparse).
    private static func sparse(_ url: URL, size: Int) throws {
        #expect(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle=try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()
    }
    /// Waits, a few milliseconds at a time, until `condition` holds (or about five seconds pass).
    private static func until(_ condition: () async -> Bool) async throws {
        var tries=0
        while !(await condition()), tries<1000 { tries+=1; try await Task.sleep(for: .milliseconds(5)) }
        #expect(await condition())
    }

    // MARK: Journal import

    /// Seventy nights of four 2 MB photos (560 MB, past the old 500 MB package cap) are read and
    /// counted for the confirmation from the files' sizes alone: none is decoded (these are not
    /// even images), so every one is still counted.
    @Test func aLongJournalIsCountedFromItsSizesAlone() throws {
        let entries=(0..<70).map { night in Self.entry("Night \(night)", photos: (0..<4).map { "\(night)-\($0).jpg" }, offset: Double(night)*86400) }
        let url=try Self.package(JournalArchive.Manifest(format: 1, exported: .now, entries: entries))
        defer { try? FileManager.default.removeItem(at: url) }
        for entry in entries { for photo in entry.photos { try Self.sparse(url.appendingPathComponent("Photos/\(photo.file)"), size: 2_000_000) } }
        let prepared=try JournalImport.read(url)
        let context=ModelContext(try Self.container())
        #expect(try prepared.summary(in: context) == JournalImport.Summary(nights: 70, photos: 280, alreadyHere: 0, spots: 0))
        // The refusal names the limits that remain: nights, photos a night, and each photo's size.
        let size=Int64(PhotoScaling.maxSourceBytes).formatted(.byteCount(style: .file))
        #expect(JournalView.tooLargeMessage.contains(size) && JournalView.tooLargeMessage.contains("Nothing was changed"))
    }
    /// The photos stay in the file until the merge reads them: one removed after the confirmation
    /// was built is simply missing from its night, and a night already in the journal is skipped.
    @Test func photosAreReadOnlyWhenTheMergeReachesThem() async throws {
        let here=Self.entry("Already here.", photos: ["here.jpg"])
        let entries=[here, Self.entry("Orange.", photos: ["a.jpg"], offset: 3600), Self.entry("Blue.", photos: ["b.jpg"], offset: 7200)]
        let url=try Self.package(JournalArchive.Manifest(format: 1, exported: .now, entries: entries))
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.jpeg(.orange).write(to: url.appendingPathComponent("Photos/a.jpg"))
        try Self.jpeg(.blue).write(to: url.appendingPathComponent("Photos/b.jpg"))
        try Self.jpeg(.red).write(to: url.appendingPathComponent("Photos/here.jpg"))
        let container=try Self.container()
        let context=ModelContext(container)
        let existing=JournalEntry(date: here.date, parkID: here.parkID, notes: here.notes)
        existing.id=here.id
        context.insert(existing); try context.save()
        let prepared=try JournalImport.read(url)
        #expect(try prepared.summary(in: context) == JournalImport.Summary(nights: 3, photos: 3, alreadyHere: 1, spots: 0))
        try FileManager.default.removeItem(at: url.appendingPathComponent("Photos/b.jpg"))
        let result=try await prepared.merge(into: context, batch: 1)
        #expect(result.added == 2 && result.skipped == 1)
        let stored=try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(stored.first { $0.notes == "Orange." }?.photoItems.count == 1 && stored.first { $0.notes == "Orange." }?.thumbnail != nil)
        #expect(stored.first { $0.notes == "Blue." }?.photoItems.isEmpty == true)
        #expect(stored.first { $0.id == here.id }?.photoItems.isEmpty == true)
    }
    /// The merge works in a context of its own: something else saving the journal's context while
    /// the import runs commits none of it, and a failed final save leaves the store unchanged.
    @Test func aFailedImportSaveLeavesTheStoreUnchanged() async throws {
        let container=try Self.container()
        let context=ModelContext(container)
        context.autosaveEnabled=true
        let spot=JournalArchive.Spot(id: "pin:00000000-0000-4000-8000-000000000001", name: "Pullout", latitude: 34, longitude: -116, timeZoneID: "America/Los_Angeles",
                                     countryCode: "US", region: "CA", created: .now, note: nil, saved: false)
        let manifest=JournalArchive.Manifest(format: 2, exported: .now, entries: [Self.entry("One.", photos: ["a.jpg"]), Self.entry("Two.", offset: 60)], spots: [spot])
        let prepared=try JournalImport(JournalArchive(manifest: manifest, photos: ["a.jpg": try Self.jpeg(.orange)]))
        struct Full: Error {}
        await #expect(throws: Full.self) {
            _=try await prepared.merge(into: context, batch: 1) { _ in
                // The app's own context saves meanwhile (autosave, or a park saved), then the import's save fails.
                try context.save()
                throw Full()
            }
        }
        #expect(!context.hasChanges)
        let fresh=ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<JournalEntry>()).isEmpty && fresh.fetch(FetchDescriptor<JournalPhoto>()).isEmpty)
        #expect(try fresh.fetch(FetchDescriptor<SavedSpot>()).isEmpty)
        // The same import, saved: everything arrives at once.
        #expect(try await prepared.merge(into: context, batch: 1).added == 2)
        #expect(try fresh.fetch(FetchDescriptor<JournalEntry>()).count == 2 && fresh.fetch(FetchDescriptor<SavedSpot>()).count == 1)
    }

    // MARK: Ask Nyx and closures

    /// Only what is said about a place with a closure is read: other places' access, the sky, the
    /// forecast service, a denied opening and a confirmed closure all pass; opening the closed place,
    /// by name or as the sentence after its name, does not.
    @Test func theClosureGuardReadsOnlyWhatIsSaidAboutAClosedPlace() {
        let records=["Joshua Tree; Fri, Oct 16 (2026-10-16); score 90/100 Excellent; getting there: the north entrance road is open in summer only. "+OnDeviceGuide.closureRecord,
                     "Arches; Fri, Oct 16 (2026-10-16); score 80/100 Excellent. No closures in the last park update. Check all park alerts before you go."]
        let closed=OnDeviceGuide.closedNames(records)
        #expect(closed == ["Joshua Tree"])
        for calm in ["Arches: no closures in the last park update.", "Joshua Tree promises open skies on Friday, at 90.", "Joshua Tree tendrá cielo abierto el viernes.",
                     "Joshua Tree aura un ciel ouvert vendredi.", "Clouds over Joshua Tree come from Open-Meteo.", "Joshua Tree scores 90. The park is open but the road is closed.",
                     "Joshua Tree is not open to cars this week.", "Joshua Tree is closed; read the alert in Nyx.", "Arches scores 80. No closures in the last park update. Check all park alerts before you go.",
                     // A record quoted word for word is the record's own words.
                     "At Joshua Tree, getting there: the north entrance road is open in summer only."] {
            #expect(!OnDeviceGuide.claimsAccess(calm, closed: closed, records: records), "\(calm)")
        }
        for claim in ["Joshua Tree is open tonight.", "Joshua Tree scores 90 on Friday. It is open.", "Joshua Tree has no closures.", "Joshua Tree's roads are passable.",
                      "Joshua Tree está abierto esta noche.", "Joshua Tree ist geöffnet."] {
            #expect(OnDeviceGuide.claimsAccess(claim, closed: closed, records: records), "\(claim)")
        }
        // No closure anywhere: nothing is read at all.
        #expect(!OnDeviceGuide.claimsAccess("Joshua Tree is open tonight.", closed: [], records: records))
        // The lookup's closed places count too, by short and full name.
        let jotr=try? park("jotr")
        let lookup=jotr.map { NightLookup(parks: [$0], forecasts: [:], now: .now, closed: [$0.id]) }
        #expect(OnDeviceGuide.closedNames([], lookup: lookup).contains("Joshua Tree"))
    }

    // MARK: Requests in flight

    /// Three callers asking for the same forecast detail while it is on its way, and the request
    /// fails without a backoff (a timeout): each kind is asked once, not once per caller.
    @Test func aFailedDetailRequestIsNotSentAgainPerWaiter() async throws {
        let echo=OpenMeteoEcho(hold: true)
        let service=ForecastDetailService(transport: echo, persist: false)
        let parks=[try park("jotr")]
        let callers=(0..<3).map { _ in Task { await service.details(for: parks, weather: true, smoke: false) } }
        try await Self.until { await service.waiting == 3 }
        await echo.refuse(URLError(.timedOut))
        await echo.release()
        for caller in callers { #expect(await caller.value.isEmpty) }
        // One request for the models and one for the layers.
        #expect(await echo.urls.count == 2)
    }
    @Test func aFailedSpotsRequestIsNotSentAgainPerWaiter() async throws {
        let echo=OpenMeteoEcho(hold: true)
        let service=WeatherService(transport: echo, persist: false, suite: "nyx.tests.spots.\(UUID().uuidString)")
        let spot=EngineEdgeCaseTests.spot("d4", 34.1, -116.1, "America/Los_Angeles")
        let callers=(0..<3).map { _ in Task { await service.spotForecasts(for: [spot], network: true) } }
        try await Self.until { await service.spotWaiting == 3 }
        await echo.refuse(URLError(.timedOut))
        await echo.release()
        for caller in callers { #expect(await caller.value.isEmpty) }
        #expect(await echo.urls.count == 1)
    }
    @Test func aFailedSummitRequestIsNotSentAgainPerWaiter() async throws {
        let echo=OpenMeteoEcho(hold: true)
        let service=SummitLayerService(transport: echo, persist: false)
        let summit=[try park("hale")]
        let callers=(0..<3).map { _ in Task { await service.layers(for: summit, network: true) } }
        try await Self.until { await service.waiting == 3 }
        await echo.refuse(URLError(.timedOut))
        await echo.release()
        for caller in callers { #expect(await caller.value.isEmpty) }
        #expect(await echo.urls.count == 1)
    }

    // MARK: Closures on the wrist

    /// Forty saved parks, each with a full forecast, its detail and a closure: every closure
    /// reaches the wrist, and it is the forecasts that give way.
    @Test func closuresReachTheWristBeforeForecasts() throws {
        let now=Date(timeIntervalSince1970: 1_791_158_400)
        let ids=Array(try ParkData.load().map(\.id).prefix(40))
        let hours=17*24
        let forecast=Forecast(updated: now, times: (0..<hours).map { now.timeIntervalSince1970-86400+Double($0)*3600 }, clouds: (0..<hours).map { Double(($0*13) % 101)+0.5 })
        let closures=Dictionary(uniqueKeysWithValues: ids.map { ($0, "Park Boulevard is closed between the north and west entrances.") })
        let context=WatchContext.make(savedParkIDs: ids, homeParkID: ids[0], nightVision: false, forecasts: Dictionary(uniqueKeysWithValues: ids.map { ($0, forecast) }),
                                      closures: closures, now: now)
        #expect(context.closures == closures)
        #expect(context.forecasts.count < ids.count && context.forecasts[ids[0]] != nil)
        #expect((context.data?.count ?? .max) <= WatchContext.byteBudget)
    }

    // MARK: Saved-sky runs

    /// A run asked for during another goes after it; a run cut short still publishes what was
    /// queued from the cache, without new requests.
    @Test func aQueuedRepublishAlwaysRuns() {
        #expect(SavedSkySync.followUp(nil, cancelled: false) == nil && SavedSkySync.followUp(nil, cancelled: true) == nil)
        #expect(SavedSkySync.followUp((publishOnly: true, background: false), cancelled: true).map { [$0.publishOnly, $0.background] } == [true, false])
        #expect(SavedSkySync.followUp((publishOnly: false, background: true), cancelled: true).map { [$0.publishOnly, $0.background] } == [true, true])
        #expect(SavedSkySync.followUp((publishOnly: false, background: false), cancelled: false).map { [$0.publishOnly, $0.background] } == [false, false])
    }

    // MARK: Layout and colour

    /// A two-column page past its widest keeps the extra room as its scroll views' margins.
    @Test func twoColumnPagesKeepTheirScrollViewsFullWidth() {
        #expect(WideLayout.twoColumnSide(1376) == 68 && WideLayout.twoColumnSide(1240) == 0 && WideLayout.twoColumnSide(1000) == 0)
        #expect(WideLayout.twoColumnSide(1377) == 68)
    }
    /// The immersive sky on Vision Pro writes in the brighter red at full strength: the standard
    /// red is below 4.5:1 for protan eyes there, and so is the brighter one below full opacity.
    @Test func skyWordsInNightVisionUseTheBrighterRed() {
        func seen(_ tint: NightTint, _ opacity: Double, _ vision: ColorVision) -> Double {
            func linear(_ v: Double) -> Double { v<=0.04045 ? v/12.92 : pow((v+0.055)/1.055, 2.4) }
            func encoded(_ v: Double) -> Double { v<=0.0031308 ? v*12.92 : 1.055*pow(v, 1/2.4)-0.055 }
            let rgb=SIMD3(encoded(linear(tint.rgb.x)*opacity), encoded(linear(tint.rgb.y)*opacity), encoded(linear(tint.rgb.z)*opacity))
            return vision.contrast(rgb, SIMD3(0, 0, 0))
        }
        for vision in ColorVision.allCases { #expect(seen(.brighter, 1, vision) >= 4.5, "\(vision)") }
        #expect(seen(.standard, 1, .protan) < 4.5 && seen(.brighter, 0.78, .protan) < 4.5)
    }
}
