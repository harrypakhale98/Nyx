import CoreHaptics
import Foundation
import SwiftData
import Testing
import UIKit
@testable import Nyx

private func jpeg(_ color: UIColor) throws -> Data {
    try #require(UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
        color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
    }.jpegData(compressionQuality: 0.8))
}

/// The journal's export written to disk, the editor's photo messages, the Moon's touch layers and
/// spoken label, and Ask Nyx's rows built from data rather than from words.
@MainActor struct JournalExportAndGuideTests {
    let parks: [Park]
    init() throws { parks=try ParkData.load() }
    /// 2026-12-01, 21:00 UTC: afternoon in every US park.
    let now=Date(timeIntervalSince1970: 1_796_158_800)

    // MARK: Journal

    /// The export written straight to disk, a night's photos at a time, is the same package byte for
    /// byte as the archive made in memory, and it imports.
    @Test func exportOnDiskMatchesTheArchiveAndImports() async throws {
        let schema=Schema(versionedSchema: NyxSchemaV2.self)
        let container=try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let phone=container.mainContext
        let first=JournalEntry(date: Date(timeIntervalSince1970: 1_790_899_200.6), parkID: "jotr", observedBortle: 2, notes: "Saturn's rings.")
        let second=JournalEntry(date: Date(timeIntervalSince1970: 1_790_999_200), parkID: "deva", notes: "Windy.")
        let third=JournalEntry(date: Date(timeIntervalSince1970: 1_791_099_200), parkID: "grba", notes: "Clear.")
        for entry in [first, second, third] { phone.insert(entry) }
        phone.insert(SavedSpot(id: "pin:00000000-0000-4000-8000-000000000001", name: "Pullout", latitude: 34, longitude: -116, timeZoneID: "America/Los_Angeles", countryCode: "US", region: "CA"))
        try phone.save()
        first.photos=[try jpeg(.orange), try jpeg(.blue)]
        first.orderedPhotos.first?.altText="The Milky Way over Joshua trees."
        third.photos=[try jpeg(.green)]
        try phone.save()
        let moment=Date(timeIntervalSince1970: 1_796_000_000.4)
        let made=JournalArchive.make(from: try phone.fetch(FetchDescriptor<JournalEntry>()), now: moment)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("nyx-test-\(UUID().uuidString).nyxjournal", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await Task.detached { try JournalArchive.write(container, to: folder, now: moment, batch: 1) }.value
        let memory=try made.fileWrapper()
        #expect(try Data(contentsOf: folder.appendingPathComponent("entries.json")) == memory.fileWrappers?["entries.json"]?.regularFileContents)
        let files=try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("Photos").path)
        #expect(Set(files) == Set(made.photos.keys) && files.count == 3 && made.manifest.format == 2)
        for (name, data) in made.photos { #expect(try Data(contentsOf: folder.appendingPathComponent("Photos").appendingPathComponent(name)) == data) }
        // Read back as the exporter reads it, and imported on another device.
        #expect(try JournalArchive(wrapper: FileWrapper(url: folder, options: [])) == made)
        let other=ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)))
        let prepared=try JournalImport.read(folder)
        #expect(try await prepared.merge(into: other, batch: 2).added == 3)
        let imported=try #require(try other.fetch(FetchDescriptor<JournalEntry>()).first { $0.id == first.id })
        #expect(imported.photos.count == 2 && imported.orderedPhotos.first?.altText == "The Milky Way over Joshua trees.")
        // Staged for the exporter in a folder of its own, cleared when asked.
        let staged=try await Task.detached { try JournalExport.stage(container, now: moment) }.value
        #expect(staged.deletingLastPathComponent().path == JournalExport.folder.path)
        #expect(FileManager.default.fileExists(atPath: staged.appendingPathComponent("entries.json").path))
        JournalExport.clear(staged)
        #expect(!FileManager.default.fileExists(atPath: staged.path))
        // A package says when it was staged in its name; an hour on, the next export sweeps it.
        let named=JournalExport.folder.appendingPathComponent("1700000000-\(UUID().uuidString).nyxjournal", isDirectory: true)
        #expect(JournalExport.stagedAt(named) == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(JournalExport.stagedAt(JournalExport.folder.appendingPathComponent("leftover")) == nil)
    }
    /// Clearing the picker after a load changes it to an empty pick: that pick loads nothing and
    /// leaves the last load's message ("This photo is too large…") on screen.
    @Test func anEmptyPickKeepsTheMessage() async {
        let editor=JournalEditorModel()
        editor.error="This photo is too large. Choose a smaller image."
        await editor.load([])
        #expect(editor.error == "This photo is too large. Choose a smaller image." && !editor.loadingPhotos && editor.photos.isEmpty)
    }

    // MARK: Moon by touch

    /// A pattern's intensity curve scales every event in it, so the hum's curve sits on a layer of
    /// its own and the taps and swells keep their strength.
    @Test func humCurvesNeverDimTheTaps() throws {
        let texture=MoonTexture.moon(illumination: 0.5, waxing: true)
        let layers=MoonHaptics.layers(texture)
        #expect(layers.count == 2)
        for layer in layers where !layer.curves.isEmpty { #expect(layer.events.allSatisfy { $0.type == .hapticContinuous } && layer.events.count == 1) }
        let taps=try #require(layers.first { $0.curves.isEmpty })
        #expect(taps.events.count == texture.taps.count && taps.events.allSatisfy { $0.type == .hapticTransient })
        #expect(MoonHaptics.layers(MoonTexture.moon(illumination: 0, waxing: true)).count == 1)

        let jotr=try park("jotr")
        let night=NightPlanner(forecasts: [:]).night(jotr, on: jotr.currentNight(at: now), now: now)
        let touch=NightTouch(NightSonification(park: jotr, sky: night.sky))
        let night24=MoonHaptics.layers(touch)
        let hum=try #require(night24.first { !$0.curves.isEmpty })
        #expect(hum.events.count == 1 && hum.curves.count == MoonHaptics.humCurves(touch).count)
        let marks=night24.filter { $0.curves.isEmpty }
        #expect(marks.flatMap(\.events).count == touch.taps.count+touch.swells.count)
    }
    /// A Moon with no lit side to see is not said to be lit from one.
    @Test func aNewMoonHasNoLitSide() {
        let new=MoonGeometry(phaseAngle: .pi, brightLimb: 0, north: 0, librationLongitude: 0, librationLatitude: 0, waxing: true)
        #expect(!MoonView.label(new).contains("lit from") && MoonView.label(new).hasSuffix(", 0 percent lit"))
        #expect(!MoonView.label(new, moment: "at 9:00 PM").contains("lit from") && MoonView.label(new, moment: "at 9:00 PM").hasSuffix("as seen at 9:00 PM"))
        let crescent=MoonGeometry(phaseAngle: 2.5, brightLimb: 0, north: 0, librationLongitude: 0, librationLatitude: 0, waxing: true)
        #expect(MoonView.label(crescent).contains("lit from the top"))
    }

    // MARK: Ask Nyx

    /// Each record carries its place, night and score as data, so its row needs no English words.
    @Test func recordsCarryTheirNightAsData() throws {
        let arch=try park("arch")
        let lookup=NightLookup(parks: parks, forecasts: [:], now: now)
        let night=NightPlanner(forecasts: [:]).night(arch, on: arch.currentNight(at: now), now: now)
        let fact=lookup.fact(night)
        #expect(fact.text == lookup.describe(night) && fact.place?.id == "arch" && fact.night == night.id && fact.score == night.score.value && fact.band == night.score.band.label)
        // A record worded in Japanese, with its full-width semicolons and its own word for tonight, still makes the right row.
        let japanese=GuideRecord(GuideFact(text: "アーチーズ；12月1日（火）（2026-12-01）；スコア94/100 最高；雲の予報なし", place: arch, night: night.id, score: 94, band: "最高"))
        #expect(japanese.park?.id == "arch" && japanese.night == night.id && japanese.score == 94 && japanese.band == "最高" && japanese.line.isEmpty)
        let start=GuideRecord(GuideFact(text: "Starting point: Chicago, IL. Distances are straight-line estimates."))
        #expect(start.park == nil && start.score == nil && start.line.hasPrefix("Starting point"))
        // Parks near: the distance and tonight's night come with the record.
        let near=try #require(lookup.parksNearFacts(park: "Arches", radius: 150, system: .miles).first { $0.place != nil })
        let row=GuideRecord(near)
        #expect(row.detail?.contains("miles straight-line from Arches") == true && near.text.contains(row.detail ?? "-") && row.night != nil && row.score != nil)
        // What's up: each sky event is about that night at that park, its own line the event alone.
        let sky=lookup.whatsUpFacts(park: "Arches", on: "tonight")
        #expect(sky.first?.score != nil && sky.dropFirst().allSatisfy { $0.place?.id == "arch" && $0.night == sky.first?.night && $0.line != nil && $0.score == nil })
        #expect(lookup.whatsUp(park: "Arches", on: "tonight") == sky.map(\.text))
        // The ledger keeps the data beside the words it numbers.
        let ledger=GuideLedger(firstID: 2)
        #expect(ledger.add([fact]) == "ID 2: \(fact.text)" && ledger.facts == [fact] && ledger.all == [fact.text])
        #expect(OnDeviceGuide.recordPlace("アーチーズ；12月1日") == "アーチーズ")
    }
    /// Fitting records or notes to the model's context takes a handful of token counts, not one per item.
    @Test func fittingTakesAFewCountsNotOneEach() async {
        var calls=0
        #expect(await OnDeviceGuide.most(200, least: 0) { calls+=1; return $0<=37 } == 37)
        #expect(calls<=10)
        calls=0
        #expect(await OnDeviceGuide.most(50, least: 1) { calls+=1; return $0<=50 } == 50)
        #expect(calls == 1)
        #expect(await OnDeviceGuide.most(50, least: 1) { _ in false } == 1)
        #expect(await OnDeviceGuide.most(0, least: 0) { _ in false } == 0)
    }
    /// The year's few words may repeat a number from the notes the model was given.
    @Test func reflectionsMayQuoteTheNotes() {
        let facts=["Nights out: 3", "Darkest sky: Great Basin, Bortle 1"]
        #expect(OnDeviceGuide.reflectionGrounded("You counted 40 meteors at Great Basin.", facts: facts, notes: ["Saw 40 meteors before midnight."]))
        #expect(!OnDeviceGuide.reflectionGrounded("You counted 40 meteors at Great Basin.", facts: facts, notes: ["Cold and clear."]))
        #expect(!OnDeviceGuide.reflectionGrounded("What a year!", facts: facts, notes: []))
    }
}
