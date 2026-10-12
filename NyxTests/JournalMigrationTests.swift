import Foundation
import SwiftData
import Testing
@testable import Nyx

/// The journal's one-time photo move from 1.1 (7), on the paths where photos sit outside the store:
/// a move interrupted between its two stages finishes on the next open, nothing is attached twice,
/// and a device without room is refused before anything changes. Each test keeps the stash in its
/// own folder (`JournalMigration.$folderOverride`), never the app's.
@MainActor
struct JournalMigrationTests {
    private static func folder(_ name: String) throws -> URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("nyx-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    /// Photos waiting in `stash/<entry id>/<index>`, as the first stage writes them.
    private static func stash(_ photos: [Int: Data], for id: UUID, in stash: URL) throws {
        let place=stash.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
        for (index, data) in photos { try data.write(to: place.appendingPathComponent(String(index))) }
    }

    /// Killed after the store changed but before the photos were attached: the next open attaches
    /// them, in their order (10 after 2), to the entry that has none, and removes the stash.
    @Test func anInterruptedMoveFinishesOnTheNextOpen() throws {
        let root=try Self.folder("recover"), stash=root.appendingPathComponent("JournalMigration", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url=root.appendingPathComponent("default.store")
        let schema=Schema(versionedSchema: NyxSchemaV2.self)
        let waiting=JournalEntry(date: .now, parkID: "jotr", notes: "Photos still in the stash.")
        let id=waiting.id
        do {
            let context=ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url)))
            context.insert(waiting); context.insert(JournalEntry(date: .now, parkID: "deva", notes: "No photos."))
            try context.save()
        }
        let photos=[0: Data([1]), 2: Data([2, 2]), 10: Data(repeating: 3, count: 50_000)]
        try Self.stash(photos, for: id, in: stash)
        // A folder that is no entry's, and a stray file, are left out.
        try Self.stash([0: Data([9])], for: UUID(), in: stash)
        try Data([0]).write(to: stash.appendingPathComponent("notes.txt"))

        let opened=JournalMigration.$folderOverride.withValue(stash) { JournalStore.open(inMemory: false, url: url) }
        #expect(!opened.failed)
        let context=ModelContext(try #require(opened.container))
        let entries=try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(entries.count == 2)
        #expect(entries.first { $0.id == id }?.photos == [Data([1]), Data([2, 2]), Data(repeating: 3, count: 50_000)])
        #expect(entries.first { $0.id != id }?.photos.isEmpty == true)
        #expect(!FileManager.default.fileExists(atPath: stash.path))
    }
    /// The second half run twice (its save landed, the stash removal did not): an entry that already
    /// has its photos gets nothing again, and the stash goes. With no stash, nothing happens.
    @Test func aMoveAlreadyAttachedIsNotRepeated() throws {
        let root=try Self.folder("restore"), stash=root.appendingPathComponent("JournalMigration", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let schema=Schema(versionedSchema: NyxSchemaV2.self)
        let container=try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context=ModelContext(container)
        let entry=JournalEntry(date: .now, parkID: "jotr", notes: "Moved.", photos: [Data([1]), Data([2])])
        context.insert(entry)
        try context.save()
        try Self.stash([0: Data([1]), 1: Data([2])], for: entry.id, in: stash)
        try JournalMigration.$folderOverride.withValue(stash) { try JournalMigration.restoreCurrent(context) }
        #expect(entry.photos == [Data([1]), Data([2])] && entry.photoItems.count == 2)
        #expect(!FileManager.default.fileExists(atPath: stash.path))
        // Nothing waiting: a no-op that does not throw.
        try JournalMigration.$folderOverride.withValue(stash) { try JournalMigration.restoreCurrent(context) }
        #expect(entry.photoItems.count == 2)
    }
    /// Without room for a copy of the photos, the first half refuses before writing anything: no stash,
    /// and the 1.1 store exactly as it was, to be opened again later.
    @Test func noRoomLeavesTheOldStoreUntouched() throws {
        let root=try Self.folder("room"), stash=root.appendingPathComponent("JournalMigration", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url=root.appendingPathComponent("default.store")
        let old=try ModelContainer(for: NyxSchemaV0.SavedPark.self, NyxSchemaV0.JournalEntry.self, configurations: ModelConfiguration(url: url))
        let context=ModelContext(old)
        context.insert(NyxSchemaV0.JournalEntry(date: .now, parkID: "jotr", notes: "Clear.", photos: [Data(repeating: 7, count: 20_000)]))
        try context.save()
        let before=try Data(contentsOf: url)
        // Leave more free space than any device has.
        JournalMigration.$headroomOverride.withValue(Int64.max/2) {
            #expect(!JournalMigration.hasRoom(forStoreAt: url))
            JournalMigration.$folderOverride.withValue(stash) {
                #expect(throws: JournalMigration.MigrationError.notEnoughSpace) { try JournalMigration.stash(context) }
            }
        }
        #expect(!FileManager.default.fileExists(atPath: stash.path))
        #expect(try Data(contentsOf: url) == before)
        #expect(try context.fetch(FetchDescriptor<NyxSchemaV0.JournalEntry>()).first?.photos.count == 1)
        // With the usual headroom, this device has room.
        #expect(JournalMigration.hasRoom(forStoreAt: url))
    }
}
