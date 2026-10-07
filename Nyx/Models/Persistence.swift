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
    static var folder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("JournalMigration", isDirectory: true)
    }
    /// Copies every V0 entry's photos to `folder/<entry id>/<index>`.
    static func stash(_ context: ModelContext) throws {
        guard let folder else { return }
        let manager=FileManager.default
        for entry in try context.fetch(FetchDescriptor<NyxSchemaV0.JournalEntry>()) where !entry.photos.isEmpty {
            let place=folder.appendingPathComponent(entry.id.uuidString, isDirectory: true)
            try manager.createDirectory(at: place, withIntermediateDirectories: true)
            for (index, data) in entry.photos.enumerated() { try data.write(to: place.appendingPathComponent(String(index)), options: .atomic) }
        }
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
/// on disk is left exactly as it is for a later version to open.
@MainActor enum JournalStore {
    static func open(inMemory: Bool, url: URL? = nil) -> (container: ModelContainer?, failed: Bool) {
        let schema=Schema(versionedSchema: NyxSchemaV1.self)
        let configuration=url.map { ModelConfiguration(schema: schema, url: $0) } ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            let container=try ModelContainer(for: schema, migrationPlan: NyxMigrationPlan.self, configurations: configuration)
            if !inMemory { JournalMigration.recover(container) }
            return (container, false)
        } catch {
            return (try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)), true)
        }
    }
}
