import Foundation
import SwiftData

/// The current models. Views and services name these; the versions below say how they came to be.
typealias SavedPark=NyxSchemaV1.SavedPark
typealias JournalEntry=NyxSchemaV1.JournalEntry
typealias JournalPhoto=NyxSchemaV1.JournalPhoto

/// The store exactly as 1.1 (7) shipped it, unversioned at the time: saved parks, and journal
/// entries with their photos as one array. Never change these classes; a change belongs in a new
/// version with a migration stage.
nonisolated enum NyxSchemaV0: VersionedSchema {
    static let versionIdentifier=Schema.Version(1,0,0)
    static var models: [any PersistentModel.Type] { [SavedPark.self, JournalEntry.self] }
    @Model nonisolated final class SavedPark {
        @Attribute(.unique) var parkID: String
        var savedAt: Date
        init(parkID: String) { self.parkID=parkID; savedAt = .now }
    }
    @Model nonisolated final class JournalEntry {
        var id: UUID
        var date: Date
        var parkID: String
        var observedBortle: Int
        var notes: String
        @Attribute(.externalStorage) var photos: [Data]
        var thumbnail: Data? = nil
        init(date: Date, parkID: String, observedBortle: Int = 3, notes: String = "", photos: [Data] = []) {
            id=UUID(); self.date=date; self.parkID=parkID; self.observedBortle=observedBortle; self.notes=notes; self.photos=photos
        }
    }
}
/// Each journal photo becomes its own record, stored outside the database, so opening an entry
/// loads only the photos on screen, and each can carry a description for VoiceOver.
nonisolated enum NyxSchemaV1: VersionedSchema {
    static let versionIdentifier=Schema.Version(2,0,0)
    static var models: [any PersistentModel.Type] { [SavedPark.self, JournalEntry.self, JournalPhoto.self] }
    @Model nonisolated final class SavedPark {
        @Attribute(.unique) var parkID: String
        var savedAt: Date
        init(parkID: String) { self.parkID=parkID; savedAt = .now }
    }
    @Model nonisolated final class JournalEntry {
        var id: UUID
        var date: Date
        var parkID: String
        var observedBortle: Int
        var notes: String
        /// In no particular order as stored; `orderedPhotos` reads them in the order they were added.
        @Relationship(deleteRule: .cascade, inverse: \JournalPhoto.entry) var photoItems: [JournalPhoto] = []
        /// A small JPEG of the first photo, so the journal list never loads full photos.
        var thumbnail: Data? = nil
        init(date: Date, parkID: String, observedBortle: Int = 3, notes: String = "", photos: [Data] = []) {
            id=UUID(); self.date=date; self.parkID=parkID; self.observedBortle=observedBortle; self.notes=notes
            if !photos.isEmpty { photoItems=photos.enumerated().map { JournalPhoto(index: $0.offset, data: $0.element) } }
        }
        var orderedPhotos: [JournalPhoto] { photoItems.sorted { $0.index<$1.index } }
        /// The photos' data in order. Setting it keeps each photo that is still there (and its
        /// description), adds new ones and deletes the ones removed.
        var photos: [Data] {
            get { orderedPhotos.map(\.data) }
            set {
                var pool=photoItems, next: [JournalPhoto]=[]
                for (index, data) in newValue.enumerated() {
                    if let match=pool.firstIndex(where: { $0.data == data }) {
                        let photo=pool.remove(at: match); photo.index=index; next.append(photo)
                    } else { next.append(JournalPhoto(index: index, data: data)) }
                }
                photoItems=next
                if let modelContext { for photo in pool { modelContext.delete(photo) } }
            }
        }
    }
    @Model nonisolated final class JournalPhoto {
        /// Position within its entry.
        var index: Int
        @Attribute(.externalStorage) var data: Data
        /// A description for VoiceOver, written by the person.
        var altText: String?
        var entry: JournalEntry?
        init(index: Int, data: Data, altText: String? = nil) { self.index=index; self.data=data; self.altText=altText }
    }
}
/// V0 → V1 moves each entry's photo array into photo records. SwiftData cannot read the old
/// photos and write the new records in one context, so they wait on disk in between: written
/// before the store changes, attached after, and removed only once saved. If the app stops between
/// the two, `JournalMigration.recover` finishes the move on the next launch.
nonisolated enum NyxMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [NyxSchemaV0.self, NyxSchemaV1.self] }
    static var stages: [MigrationStage] {
        [.custom(fromVersion: NyxSchemaV0.self, toVersion: NyxSchemaV1.self,
                 willMigrate: { context in try JournalMigration.stash(context) },
                 didMigrate: { context in try JournalMigration.restore(context) })]
    }
}
nonisolated enum JournalMigration {
    enum MigrationError: Error { case notEnoughSpace }
    /// Free space the move leaves untouched beyond the photo copies, so it never fills the device.
    static let headroom: Int64=100_000_000
    static var folder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("JournalMigration", isDirectory: true)
    }
    /// Copies every V0 entry's photos to `folder/<entry id>/<index>`. The copies take as much space
    /// as the photos, so the move does not start without that room: SwiftData changes the store only
    /// after `willMigrate` returns, so throwing here leaves the file exactly as build 7 wrote it. The
    /// journal then opens as unavailable for this launch, and the move is tried again on the next.
    static func stash(_ context: ModelContext) throws {
        guard let folder else { return }
        let manager=FileManager.default
        // The store is still V0 here, so anything already in the folder is from a move that never finished its first half.
        try? manager.removeItem(at: folder)
        if let store=context.container.configurations.first?.url, !hasRoom(forStoreAt: store) { throw MigrationError.notEnoughSpace }
        do {
            for entry in try context.fetch(FetchDescriptor<NyxSchemaV0.JournalEntry>()) where !entry.photos.isEmpty {
                let place=folder.appendingPathComponent(entry.id.uuidString, isDirectory: true)
                try manager.createDirectory(at: place, withIntermediateDirectories: true)
                for (index, data) in entry.photos.enumerated() { try data.write(to: place.appendingPathComponent(String(index)), options: .atomic) }
            }
        } catch {
            // A half-written stash only takes space; the photos are still in the unchanged store.
            try? manager.removeItem(at: folder)
            throw error
        }
    }
    /// True when the store's volume has room for a copy of everything the store holds, plus
    /// `headroom`. An unreadable capacity counts as room, as before the check existed.
    static func hasRoom(forStoreAt url: URL) -> Bool {
        guard let available=try? url.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage else { return true }
        return available >= footprint(ofStoreAt: url)+headroom
    }
    /// The bytes the store takes: the database, its write-ahead files, and the folder of records
    /// kept outside it (`.<name>_SUPPORT`, where external-storage photos live). An upper bound on the photos.
    static func footprint(ofStoreAt url: URL) -> Int64 {
        let manager=FileManager.default, folder=url.deletingLastPathComponent(), name=url.lastPathComponent
        let support="."+url.deletingPathExtension().lastPathComponent+"_SUPPORT"
        func size(_ file: URL) -> Int64 {
            guard let values=try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true else { return 0 }
            return Int64(values.fileSize ?? 0)
        }
        var total=[name, name+"-wal", name+"-shm"].reduce(Int64(0)) { $0+size(folder.appendingPathComponent($1)) }
        if let files=manager.enumerator(at: folder.appendingPathComponent(support, isDirectory: true), includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) {
            for case let file as URL in files { total+=size(file) }
        }
        return total
    }
    /// Attaches stashed photos to their V1 entries, saves, then removes the stash.
    static func restore(_ context: ModelContext) throws {
        guard let folder, FileManager.default.fileExists(atPath: folder.path) else { return }
        let manager=FileManager.default
        let entries=try context.fetch(FetchDescriptor<NyxSchemaV1.JournalEntry>())
        let names=(try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names {
            guard let id=UUID(uuidString: name), let entry=entries.first(where: { $0.id == id }), entry.photoItems.isEmpty else { continue }
            let place=folder.appendingPathComponent(name, isDirectory: true)
            let files=((try? manager.contentsOfDirectory(atPath: place.path)) ?? []).compactMap { Int($0) }.sorted()
            for index in files {
                let photo=NyxSchemaV1.JournalPhoto(index: index, data: try Data(contentsOf: place.appendingPathComponent(String(index))))
                context.insert(photo)
                photo.entry=entry
            }
        }
        try context.save()
        try manager.removeItem(at: folder)
    }
    /// A move interrupted between the two stages finishes here.
    static func recover(_ container: ModelContainer) {
        guard let folder, FileManager.default.fileExists(atPath: folder.path) else { return }
        try? restore(ModelContext(container))
    }
}
/// Opens the journal's store. When it cannot be opened, Nyx runs with an empty store in memory and
/// says so on the Journal tab only: Tonight, Parks and Calendar never depend on it, and the file
/// on disk is left exactly as it is for a later version to open. Nothing may be written to that
/// stand-in: a journal entry or saved park kept there would be gone on the next launch, so every
/// writer checks `failed` (`PlanModel.journalUnavailable`, `JournalAccess.unavailable`), and the saved
/// parks it reads as empty never reach the widget, the watch or reminders (`SavedSkySync`).
/// `shortOfSpace` says the device is too full for the store (or its one-time move) to be trusted to open.
@MainActor enum JournalStore {
    static func open(inMemory: Bool, url: URL? = nil) -> (container: ModelContainer?, failed: Bool, shortOfSpace: Bool) {
        let schema=Schema(versionedSchema: NyxSchemaV1.self)
        let configuration=url.map { ModelConfiguration(schema: schema, url: $0) } ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            let container=try ModelContainer(for: schema, migrationPlan: NyxMigrationPlan.self, configurations: configuration)
            if !inMemory { JournalMigration.recover(container) }
            return (container, false, false)
        } catch {
            let memory=try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
            return (memory, true, !inMemory && !JournalMigration.hasRoom(forStoreAt: configuration.url))
        }
    }
}
