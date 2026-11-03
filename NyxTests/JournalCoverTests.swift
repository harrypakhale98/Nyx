import AppIntents
import Foundation
import SwiftData
import Testing
import UIKit
@testable import Nyx

/// The cards' thumbnails moved out of the entries' rows (V3): every way an older store arrives
/// keeps each entry, photo, description and thumbnail exactly once; a move cut short finishes on the
/// next open; every writer keeps one cover per entry with photos; and listing the journal no longer
/// loads them. Every store is on disk in a test folder of its own, and so is any stash.
@MainActor
struct JournalCoverTests {
    private static let night=Date(timeIntervalSince1970: 1_790_899_200)
    private struct Place {
        let root: URL
        var url: URL { root.appendingPathComponent("default.store") }
        var stash: URL { root.appendingPathComponent("JournalMigration", isDirectory: true) }
    }
    private static func place() throws -> Place {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("nyx-cover-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Place(root: root)
    }
    /// Runs `body` with a store folder of its own, removed once everything `body` opened is closed.
    private static func inPlace(_ body: (Place) throws -> Void) throws {
        let folder=try Self.place()
        defer { try? FileManager.default.removeItem(at: folder.root) }
        try autoreleasepool { try body(folder) }
    }
    private static func inPlace(_ body: (Place) async throws -> Void) async throws {
        let folder=try Self.place()
        defer { try? FileManager.default.removeItem(at: folder.root) }
        try await body(folder)
    }
    /// The store opened as the app opens it, with the stash in the test's own folder.
    private static func open(_ place: Place, batches: Int?=nil) throws -> ModelContainer {
        let opened=JournalMigration.$folderOverride.withValue(place.stash) {
            JournalCovers.$batchLimit.withValue(batches) { JournalStore.open(inMemory: false, url: place.url) }
        }
        #expect(!opened.failed)
        return try #require(opened.container)
    }
    /// `count` bytes no other call returns (the seed is in the first eight).
    private static func bytes(_ count: Int, _ seed: Int) -> Data {
        var data=Data(repeating: UInt8(truncatingIfNeeded: seed &* 37 &+ 11), count: count)
        withUnsafeBytes(of: Int64(seed)) { for (offset, byte) in $0.enumerated() where offset<count { data[offset]=byte } }
        return data
    }
    private static func jpeg(_ color: UIColor) throws -> Data {
        try #require(UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
            color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }.jpegData(compressionQuality: 0.8))
    }
    private static func count<T: PersistentModel>(_ type: T.Type, _ context: ModelContext, _ predicate: Predicate<T>?=nil) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>(predicate: predicate))
    }
    /// Covers, covers belonging to no entry, photos, and entries still holding a thumbnail in their row.
    private static func tally(_ container: ModelContainer) throws -> [Int] {
        let context=ModelContext(container)
        return [try count(JournalCover.self, context), try count(JournalCover.self, context, #Predicate { $0.entry == nil }),
                try count(JournalPhoto.self, context), try count(JournalEntry.self, context, #Predicate { $0.legacyThumbnail != nil })]
    }

    // MARK: Upgrades

    /// The V2 journal the move was written for: a night of three photos (one past 200 KB) with two
    /// described and a 150 KB thumbnail, a night with one photo and a tiny thumbnail, photos without
    /// one, a night with neither, saved parks and a spot.
    private struct VersionTwo {
        let ids: [UUID]
        let photos: [[Data]]
        let thumbnails: [Data?]
        static let notes=["Three photos.", "One photo.", "Photos, no thumbnail.", "Words alone."]
        static let parks=["jotr", "deva", "grba", "brca"]
        static let spot="pin:00000000-0000-4000-8000-0000000000aa"
    }
    private static func versionTwo(at url: URL) throws -> VersionTwo {
        let schema=Schema(versionedSchema: NyxSchemaV2.self)
        let context=ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url)))
        let photos=[[bytes(3_000, 1), bytes(250_000, 2), bytes(10_000, 3)], [bytes(4_000, 4)], [bytes(5_000, 5), bytes(6_000, 6)], []]
        let thumbnails: [Data?]=[bytes(150_000, 7), bytes(800, 8), nil, nil]
        var ids: [UUID]=[]
        for index in 0..<4 {
            let entry=NyxSchemaV2.JournalEntry(date: night+Double(index)*86_400, parkID: VersionTwo.parks[index], observedBortle: index+1,
                                               notes: VersionTwo.notes[index], photos: photos[index])
            entry.thumbnail=thumbnails[index]
            context.insert(entry)
            ids.append(entry.id)
        }
        try context.save()
        let first=try #require(try context.fetch(FetchDescriptor<NyxSchemaV2.JournalEntry>()).first { $0.id == ids[0] })
        first.orderedPhotos[0].altText="The ridge at dusk."
        first.orderedPhotos[2].altText="The core over the wash."
        context.insert(NyxSchemaV2.SavedPark(parkID: "deva")); context.insert(NyxSchemaV2.SavedPark(parkID: "grba"))
        context.insert(NyxSchemaV2.SavedSpot(id: VersionTwo.spot, name: "Pinto Basin pullout", latitude: 33.92, longitude: -115.93,
                                             timeZoneID: "America/Los_Angeles", countryCode: "US", region: "California", createdAt: night, note: "Gate locks at 10."))
        try context.save()
        return VersionTwo(ids: ids, photos: photos, thumbnails: thumbnails)
    }
    private static func expectVersionTwo(_ old: VersionTwo, in container: ModelContainer) throws {
        let context=ModelContext(container)
        let entries=try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(entries.count == 4)
        for (index, id) in old.ids.enumerated() {
            let entry=try #require(entries.first { $0.id == id })
            #expect(entry.date == night+Double(index)*86_400 && entry.parkID == VersionTwo.parks[index])
            #expect(entry.observedBortle == index+1 && entry.notes == VersionTwo.notes[index])
            #expect(entry.photos == old.photos[index])
            #expect(entry.cover?.data == old.thumbnails[index] && entry.legacyThumbnail == nil)
        }
        let first=try #require(entries.first { $0.id == old.ids[0] })
        #expect(first.orderedPhotos.map(\.altText) == ["The ridge at dusk.", nil, "The core over the wash."])
        #expect(Set(try context.fetch(FetchDescriptor<SavedPark>()).map(\.parkID)) == ["deva", "grba"])
        let spot=try #require(try context.fetch(FetchDescriptor<SavedSpot>()).first)
        #expect(spot.id == VersionTwo.spot && spot.name == "Pinto Basin pullout" && spot.latitude == 33.92 && spot.note == "Gate locks at 10.")
        // Two covers, both an entry's; 3 + 1 + 2 photos; nothing left in a row.
        #expect(try tally(container) == [2, 0, 6, 0])
    }

    @Test func versionTwoStoreMovesEveryThumbnailOnce() throws {
        try Self.inPlace { place in
            let old=try Self.versionTwo(at: place.url)
            try Self.expectVersionTwo(old, in: try Self.open(place))
            // Opened again, nothing moves or doubles.
            try Self.expectVersionTwo(old, in: try Self.open(place))
        }
    }
    /// A 1.1 (7) store with a thumbnail goes all the way: photos into records, the thumbnail into a cover, the stash gone.
    @Test func versionZeroStoreArrivesWithItsCover() throws {
        try Self.inPlace { place in
            let photos=[Self.bytes(2_000, 20), Self.bytes(200_000, 21)], thumbnail=Self.bytes(120_000, 22)
            var id=UUID()
            do {
                let context=ModelContext(try ModelContainer(for: NyxSchemaV0.SavedPark.self, NyxSchemaV0.JournalEntry.self, configurations: ModelConfiguration(url: place.url)))
                let entry=NyxSchemaV0.JournalEntry(date: Self.night, parkID: "jotr", observedBortle: 2, notes: "Clear and still.", photos: photos)
                entry.thumbnail=thumbnail
                id=entry.id
                context.insert(entry); context.insert(NyxSchemaV0.JournalEntry(date: Self.night+86_400, parkID: "deva", notes: "No photos."))
                context.insert(NyxSchemaV0.SavedPark(parkID: "deva"))
                try context.save()
            }
            let container=try Self.open(place)
            let entries=try ModelContext(container).fetch(FetchDescriptor<JournalEntry>())
            let moved=try #require(entries.first { $0.id == id })
            #expect(entries.count == 2 && moved.photos == photos && moved.notes == "Clear and still." && moved.observedBortle == 2)
            #expect(moved.cover?.data == thumbnail && moved.legacyThumbnail == nil)
            #expect(entries.first { $0.id != id }?.cover == nil)
            #expect(try Self.tally(container) == [1, 0, 2, 0])
            #expect(!FileManager.default.fileExists(atPath: place.stash.path))
            // Opened again as V3, as it is: nothing moves twice.
            #expect(try Self.tally(try Self.open(place)) == [1, 0, 2, 0])
        }
    }
    /// A V1 store with a described photo and a thumbnail, through V2 to V3.
    @Test func versionOneStoreArrivesWithItsCover() throws {
        try Self.inPlace { place in
            let photos=[Self.bytes(3_000, 30), Self.bytes(60_000, 31)], thumbnail=Self.bytes(150_000, 32)
            var id=UUID()
            do {
                let schema=Schema(versionedSchema: NyxSchemaV1.self)
                let context=ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: place.url)))
                let entry=NyxSchemaV1.JournalEntry(date: Self.night, parkID: "jotr", observedBortle: 2, notes: "The core over the ridge.", photos: photos)
                entry.thumbnail=thumbnail
                id=entry.id
                context.insert(entry)
                try context.save()
                entry.orderedPhotos[1].altText="Joshua trees under the Milky Way."
                try context.save()
            }
            let container=try Self.open(place)
            let moved=try #require(try ModelContext(container).fetch(FetchDescriptor<JournalEntry>()).first { $0.id == id })
            #expect(moved.photos == photos && moved.orderedPhotos.map(\.altText) == [nil, "Joshua trees under the Milky Way."])
            #expect(moved.cover?.data == thumbnail && moved.legacyThumbnail == nil)
            #expect(try Self.tally(container) == [1, 0, 2, 0])
        }
    }
    /// A new journal starts as V3, keeps what is written, and has nothing to move. A cover reads the
    /// same from a store in memory (debug routes, and the stand-in when the store cannot open).
    @Test func freshStoreStartsAsVersionThree() throws {
        try Self.inPlace { place in
            do {
                let context=ModelContext(try Self.open(place))
                let entry=JournalEntry(date: Self.night, parkID: "jotr", notes: "First night.", photos: [Self.bytes(2_000, 40)])
                context.insert(entry)
                entry.setThumbnail(Self.bytes(150_000, 41), in: context)
                try context.save()
            }
            let container=try Self.open(place)
            #expect(JournalCovers.move(container) == 0)
            let entry=try #require(try ModelContext(container).fetch(FetchDescriptor<JournalEntry>()).first)
            guard case .cover(let id)=try #require(JournalCovers.picture(of: entry)) else { Issue.record("no cover"); return }
            #expect(JournalCovers.data(id, in: container) == Self.bytes(150_000, 41))
            #expect(try Self.tally(container) == [1, 0, 1, 0])
            let schema=Schema(versionedSchema: NyxSchemaV3.self)
            let memory=try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
            let context=ModelContext(memory)
            let kept=JournalEntry(date: Self.night, parkID: "deva")
            context.insert(kept)
            kept.setThumbnail(Self.bytes(900, 42), in: context)
            try context.save()
            guard case .cover(let memoryID)=try #require(JournalCovers.picture(of: kept)) else { Issue.record("no cover"); return }
            #expect(JournalCovers.data(memoryID, in: memory) == Self.bytes(900, 42))
        }
    }

    // MARK: A move cut short

    /// Upgraded but not yet moved (the app stopped as the store opened): each card still shows the
    /// thumbnail in its row, and the next open moves it.
    @Test func anUnmovedStoreStillShowsItsThumbnails() throws {
        try Self.inPlace { place in
            let old=try Self.versionTwo(at: place.url)
            do {
                let schema=Schema(versionedSchema: NyxSchemaV3.self)
                let container=try ModelContainer(for: schema, migrationPlan: NyxMigrationPlan.self, configurations: ModelConfiguration(schema: schema, url: place.url))
                let entries=try ModelContext(container).fetch(FetchDescriptor<JournalEntry>())
                for (index, id) in old.ids.enumerated() {
                    let entry=try #require(entries.first { $0.id == id })
                    #expect(entry.cover == nil && entry.legacyThumbnail == old.thumbnails[index])
                    #expect(JournalCovers.picture(of: entry) == old.thumbnails[index].map { JournalCovers.Picture.inRow($0) })
                }
                #expect(try Self.tally(container) == [0, 0, 6, 2])
            }
            let container=try Self.open(place)
            try Self.expectVersionTwo(old, in: container)
            let first=try #require(try ModelContext(container).fetch(FetchDescriptor<JournalEntry>()).first { $0.id == old.ids[0] })
            guard case .cover(let id)=try #require(JournalCovers.picture(of: first)) else { Issue.record("no cover"); return }
            #expect(JournalCovers.data(id, in: container) == old.thumbnails[0])
        }
    }
    /// A move stopped after its first batch of 25: the next open moves the other 35, each to its own
    /// entry, none twice.
    @Test func aMoveStoppedAfterOneBatchFinishesOnTheNextOpen() throws {
        try Self.inPlace { place in
            var thumbnails: [UUID: Data]=[:]
            do {
                let schema=Schema(versionedSchema: NyxSchemaV2.self)
                let context=ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: place.url)))
                for index in 0..<60 {
                    let entry=NyxSchemaV2.JournalEntry(date: Self.night+Double(index)*86_400, parkID: "jotr", notes: "Night \(index).", photos: [Self.bytes(1_000, 1_000+index)])
                    entry.thumbnail=Self.bytes(20_000, 2_000+index)
                    thumbnails[entry.id]=entry.thumbnail
                    context.insert(entry)
                }
                try context.save()
            }
            #expect(try Self.tally(try Self.open(place, batches: 1)) == [25, 0, 60, 35])
            let container=try Self.open(place)
            #expect(try Self.tally(container) == [60, 0, 60, 0])
            let entries=try ModelContext(container).fetch(FetchDescriptor<JournalEntry>())
            #expect(entries.count == 60 && entries.allSatisfy { $0.cover?.data == thumbnails[$0.id] && $0.photos.count == 1 })
        }
    }
    /// An entry holding both (a cover written after an earlier move stopped): the cover stays, the row is emptied.
    @Test func aCoverAlreadyWrittenWins() throws {
        try Self.inPlace { place in
            let container=try Self.open(place)
            let context=ModelContext(container)
            let entry=JournalEntry(date: Self.night, parkID: "jotr", notes: "Both.")
            context.insert(entry)
            entry.setThumbnail(Self.bytes(5_000, 50), in: context)
            entry.legacyThumbnail=Self.bytes(5_000, 51)
            try context.save()
            #expect(JournalCovers.move(container) == 1)
            let read=try #require(try ModelContext(container).fetch(FetchDescriptor<JournalEntry>()).first)
            #expect(read.cover?.data == Self.bytes(5_000, 50) && read.legacyThumbnail == nil)
            #expect(try Self.tally(container) == [1, 0, 0, 0])
        }
    }

    // MARK: Writers

    /// The editor writes one cover, replaces it when the first photo changes, and removes it with
    /// the last photo; deleting the night takes its photos and cover with it.
    @Test func theEditorKeepsOneCoverPerEntry() async throws {
        try await Self.inPlace { place in
            let container=try Self.open(place)
            let context=ModelContext(container)
            let orange=try Self.jpeg(.orange), blue=try Self.jpeg(.blue)
            let editor=JournalEditorModel(restoring: false)
            editor.date=Self.night; editor.photos=[orange]
            #expect(await editor.save(context: context, existing: nil))
            let entry=try #require(try context.fetch(FetchDescriptor<JournalEntry>()).first)
            #expect(entry.cover?.data == PhotoScaling.jpeg(orange, maxPixels: 900))
            #expect(try Self.tally(container) == [1, 0, 1, 0])
            let first=try #require(entry.cover?.persistentModelID)

            let changed=JournalEditorModel(entry: entry, restoring: false)
            changed.photos=[blue, orange]
            #expect(await changed.save(context: context, existing: entry))
            #expect(entry.cover?.data == PhotoScaling.jpeg(blue, maxPixels: 900) && entry.cover?.persistentModelID != first)
            #expect(try Self.tally(container) == [1, 0, 2, 0])
            // The card that asked for the old cover gets nothing, not the old picture.
            #expect(JournalCovers.data(first, in: container) == nil)

            let emptied=JournalEditorModel(entry: entry, restoring: false)
            emptied.photos=[]
            #expect(await emptied.save(context: context, existing: entry))
            #expect(entry.cover == nil && JournalCovers.picture(of: entry) == nil)
            #expect(try Self.tally(container) == [0, 0, 0, 0])

            let again=JournalEditorModel(entry: entry, restoring: false)
            again.photos=[orange]
            #expect(await again.save(context: context, existing: entry))
            #expect(try Self.tally(container) == [1, 0, 1, 0])
            context.delete(entry)
            try context.save()
            #expect(try Self.tally(container) == [0, 0, 0, 0])
        }
    }
    /// An entry added from Shortcuts with a photo has one cover.
    @Test func anIntentEntryHasOneCover() async throws {
        try await Self.inPlace { place in
            let container=try Self.open(place)
            let before=(JournalAccess.container, JournalAccess.unavailable)
            defer { JournalAccess.configure(container: before.0, unavailable: before.1) }
            JournalAccess.configure(container: container, unavailable: false)
            let photo=try Self.jpeg(.orange)
            _=try await JournalAccess.add(title: nil, message: "Clear and still.", date: Self.night, location: nil,
                                          files: [IntentFile(data: photo, filename: "night.jpg", type: .jpeg)])
            let entry=try #require(try ModelContext(container).fetch(FetchDescriptor<JournalEntry>()).first)
            #expect(entry.cover != nil && entry.legacyThumbnail == nil)
            #expect(try Self.tally(container) == [1, 0, 1, 0])
        }
    }
    /// Exported, then imported into a new journal: one cover for each night with photos; importing again adds nothing.
    @Test func anImportedJournalHasOneCoverPerNightWithPhotos() throws {
        try Self.inPlace { phone in
            try Self.inPlace { tablet in
                let context=ModelContext(try Self.open(phone))
                for (index, photos) in [[try Self.jpeg(.orange), try Self.jpeg(.blue)], [try Self.jpeg(.red)], []].enumerated() {
                    let entry=JournalEntry(date: Self.night+Double(index)*86_400, parkID: "jotr", notes: "Night \(index).", photos: photos)
                    context.insert(entry)
                    entry.setThumbnail(photos.first.flatMap { PhotoScaling.jpeg($0, maxPixels: 900) }, in: context)
                }
                try context.save()
                let archive=JournalArchive.make(from: try context.fetch(FetchDescriptor<JournalEntry>()), now: Self.night)
                let reread=try JournalArchive(wrapper: archive.fileWrapper())
                let target=try Self.open(tablet)
                let result=try reread.merge(into: ModelContext(target))
                #expect(result.added == 3 && result.skipped == 0)
                #expect(try Self.tally(target) == [2, 0, 3, 0])
                let again=try reread.merge(into: ModelContext(target))
                #expect(again.added == 0 && again.skipped == 3)
                #expect(try Self.tally(target) == [2, 0, 3, 0])
            }
        }
    }

    // MARK: Reading

    /// A card whose cover was deleted before its read came back (its night deleted) gets nothing,
    /// and Nyx carries on.
    @Test func aDeletedCoverReadsAsNothing() throws {
        try Self.inPlace { place in
            let container=try Self.open(place)
            let context=ModelContext(container)
            let entry=JournalEntry(date: Self.night, parkID: "jotr")
            context.insert(entry)
            entry.setThumbnail(Self.bytes(150_000, 60), in: context)
            try context.save()
            let id=try #require(entry.cover?.persistentModelID)
            #expect(JournalCovers.data(id, in: container) == Self.bytes(150_000, 60))
            context.delete(entry)
            try context.save()
            #expect(JournalCovers.data(id, in: container) == nil)
            #expect(try Self.tally(container) == [0, 0, 0, 0])
        }
    }
    /// A night deleted between reading the journal's identifiers and reading the new one
    /// (`MomentsWatcher`) reads as nothing, and Nyx carries on.
    @Test func aDeletedEntryReadsAsNothing() throws {
        try Self.inPlace { place in
            let container=try Self.open(place)
            let context=ModelContext(container)
            let entry=JournalEntry(date: Self.night, parkID: "jotr")
            let night=entry.id
            context.insert(entry)
            try context.save()
            let id=try #require(try context.fetchIdentifiers(FetchDescriptor<JournalEntry>()).first)
            #expect(JournalEntry.id(of: id, in: container) == night)
            context.delete(entry)
            try context.save()
            #expect(JournalEntry.id(of: id, in: container) == nil)
        }
    }
    /// Two hundred nights with 150 KB thumbnails: reading them all as the journal list does takes
    /// under 10 MB, and every card's picture read through the cards' own reads under 15 MB more in
    /// all. The least of three runs counts, since other tests share the process.
    @Test func listingTheJournalLoadsNoThumbnails() throws {
        try Self.inPlace { place in
            do {
                let container=try Self.open(place)
                for start in stride(from: 0, to: 200, by: 50) {
                    try autoreleasepool {
                        let context=ModelContext(container)
                        for index in start..<start+50 {
                            let entry=JournalEntry(date: Self.night+Double(index)*86_400, parkID: "jotr", notes: "Night \(index).")
                            context.insert(entry)
                            entry.setThumbnail(Self.bytes(150_000, 3_000+index), in: context)
                        }
                        try context.save()
                    }
                }
            }
            var listed: [Int]=[], read: [Int]=[]
            for _ in 0..<3 {
                let container=try Self.open(place)
                let base=SpeedBenchmarks.footprint()
                let context=ModelContext(container)
                let entries=try context.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
                let pictures=entries.compactMap { entry in _=entry.notes; return JournalCovers.picture(of: entry) }
                listed.append(SpeedBenchmarks.footprint()-base)
                var bytes=0
                for case .cover(let id) in pictures { autoreleasepool { bytes+=JournalCovers.data(id, in: container)?.count ?? 0 } }
                read.append(SpeedBenchmarks.footprint()-base)
                #expect(entries.count == 200 && pictures.count == 200 && bytes == 200*150_000)
                withExtendedLifetime(entries) {}
            }
            #expect(try #require(listed.min()) < 10_000_000, "listing: \(listed)")
            #expect(try #require(read.min()) < 15_000_000, "reading: \(read)")
        }
    }
}
